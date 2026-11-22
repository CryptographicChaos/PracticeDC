<#
    Build-PracticeDC.ps1
    Turns a fresh Windows Server 2022 VM into the practice domain controller for the
    Active Directory security lab: DC1, domain practice.local, with the weak spots the
    lab uses already planted.

    HOW TO USE (once per VM):
      1. Log in as Administrator. Right-click Start > Windows PowerShell (Admin).
      2. Go to the folder with this file and run:
             powershell -ExecutionPolicy Bypass -File .\Build-PracticeDC.ps1
         If several of these VMs share ONE network, add  -SharedNetwork  to the end.
      3. Walk away. The VM restarts by itself two times. Total time is 15 to 25 minutes.
      4. Log in again as PRACTICE\Administrator with the password in the notes.
         A file called "PracticeDC build result.txt" is on the desktop when it is done.

    FOR TEACHING ONLY. The passwords in this file are fake and weak on purpose. Never run
    this on a real server. The script deletes itself when the build is finished.
#>
param(
    [switch]$SharedNetwork
)

$ErrorActionPreference = 'Continue'

# ---- the values the lab runbook expects (do not change: every demo depends on them) ----
$ComputerName  = 'DC1'
$DomainName    = 'practice.local'
$NetbiosName   = 'PRACTICE'
$AdminPassword = 'Practice-DC1-2026!'
$DsrmPassword  = 'Restore-DC1-2026!'
$WeakPassword  = 'Summer2026!'
$TempPassword  = 'Welcome2026!'

$Dir      = 'C:\PracticeDC'
$Self     = Join-Path $Dir 'Build-PracticeDC.ps1'
$StateF   = Join-Path $Dir 'stage.txt'
$OptF     = Join-Path $Dir 'options.txt'
$OrigF    = Join-Path $Dir 'original.txt'
$Log      = Join-Path $Dir 'build.log'
$TaskName = 'PracticeDC-Build'
$Result   = 'C:\Users\Public\Desktop\PracticeDC build result.txt'

function Log {
    param([string]$Message)
    $line = (Get-Date -Format 'yyyy-MM-dd HH:mm:ss') + '  ' + $Message
    try { Add-Content -Path $Log -Value $line -ErrorAction Stop } catch { }
    Write-Host $line
}
function Set-Stage {
    param([int]$Number)
    Set-Content -Path $StateF -Value $Number
}
function Get-Stage { if (Test-Path $StateF) { return [int]((Get-Content $StateF | Select-Object -First 1).Trim()) } return 1 }
function Test-IsDC { return ((Get-CimInstance Win32_ComputerSystem).DomainRole -ge 4) }
function Write-Result {
    param([bool]$Ok, [string[]]$Lines)
    $head = if ($Ok) { 'BUILD FINISHED OK' } else { 'BUILD DID NOT FINISH' }
    $body = @($head + '   ' + (Get-Date -Format 'yyyy-MM-dd HH:mm'), '') + $Lines
    if ($Ok) { $body += @('', 'Next: delete this file, shut the VM down, and take the snapshot named  seeded') }
    else     { $body += @('', 'To try the last part again: open Windows PowerShell (Admin) and run', '    powershell -ExecutionPolicy Bypass -File C:\PracticeDC\Build-PracticeDC.ps1', 'If it is still wrong, send C:\PracticeDC\build.log to Josh.') }
    try { Set-Content -Path $Result -Value $body } catch { }
}
function Stop-Build {
    param([string]$Why)
    Log ('STOPPED: ' + $Why)
    Write-Result $false @($Why)
    schtasks.exe /Delete /TN $TaskName /F 2>$null | Out-Null
    exit 1
}

# ---------------------------------------------------------------------------------------
# Stage 1: runs when the script starts. Password, AD role, computer name, restart.
# ---------------------------------------------------------------------------------------
function Invoke-Stage1 {
    $me = [Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()
    if (-not $me.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
        Write-Host 'Run this from Windows PowerShell (Admin). Right-click Start to find it.' -ForegroundColor Red
        exit 1
    }
    $os = Get-CimInstance Win32_OperatingSystem
    if ($os.ProductType -eq 1) { Write-Host 'This is not Windows Server. Stopping.' -ForegroundColor Red; exit 1 }

    New-Item -ItemType Directory -Force -Path $Dir | Out-Null
    Log ('Stage 1 started on ' + $env:COMPUTERNAME + ' (' + $os.Caption + ')')
    if ($PSCommandPath -and ($PSCommandPath -ne $Self)) {
        Copy-Item -LiteralPath $PSCommandPath -Destination $Self -Force
        Set-Content -Path $OrigF -Value $PSCommandPath
    }
    Set-Content -Path $OptF -Value $(if ($SharedNetwork) { 'SharedNetwork' } else { 'none' })

    if (Test-IsDC) {
        $dom = (Get-CimInstance Win32_ComputerSystem).Domain
        if ($dom -ne $DomainName) { Stop-Build ('This server is already a domain controller for ' + $dom + '. Use a fresh VM.') }
        Log 'Already a domain controller for practice.local. Going straight to planting the weak spots.'
        Set-Stage 3
        Invoke-Stage3
        return
    }

    Log 'Setting the Administrator password to the one on the lab card'
    net.exe user Administrator $AdminPassword | Out-Null
    if ($LASTEXITCODE -ne 0) { Stop-Build 'Could not set the Administrator password.' }
    net.exe user Administrator /active:yes | Out-Null

    Log 'Installing the Active Directory role (about 3 minutes)'
    $f = Install-WindowsFeature AD-Domain-Services -IncludeManagementTools
    if (-not $f.Success) { Stop-Build 'Installing the Active Directory role failed.' }

    Log 'Registering the task that carries the build on after each restart'
    $tr = 'powershell.exe -NoProfile -ExecutionPolicy Bypass -File ' + $Self
    schtasks.exe /Create /TN $TaskName /TR $tr /SC ONSTART /RU SYSTEM /RL HIGHEST /F | Out-Null
    if ($LASTEXITCODE -ne 0) { Stop-Build 'Could not register the startup task.' }

    Set-Stage 2
    if ($env:COMPUTERNAME -ne $ComputerName) {
        Log ('Renaming the computer to ' + $ComputerName + ' and restarting')
        Rename-Computer -NewName $ComputerName -Force
        Write-Host ''
        Write-Host 'The VM restarts now, and once more later. Leave it alone for 15 to 25 minutes.' -ForegroundColor Cyan
        Write-Host ('Then log in as ' + $NetbiosName + '\Administrator with password  ' + $AdminPassword) -ForegroundColor Cyan
        Start-Sleep -Seconds 8
        Restart-Computer -Force
        exit 0
    }
    Log 'The computer is already named DC1, so no restart is needed before the next step'
    Invoke-Stage2
}

# ---------------------------------------------------------------------------------------
# Stage 2: runs by itself after the first restart. Makes the server a domain controller.
# ---------------------------------------------------------------------------------------
function Invoke-Stage2 {
    Log 'Stage 2 started: making this server the domain controller for practice.local'
    if (Test-IsDC) { Log 'It is already a domain controller'; Set-Stage 3; Invoke-Stage3; return }
    $tries = 0
    $tf = Join-Path $Dir 'tries.txt'
    if (Test-Path $tf) { $tries = [int](Get-Content $tf | Select-Object -First 1) }
    $tries++
    Set-Content -Path $tf -Value $tries
    if ($tries -gt 2) { Stop-Build 'Making the domain controller failed twice. See build.log.' }
    try {
        Import-Module ADDSDeployment -ErrorAction Stop
        $sm = ConvertTo-SecureString $DsrmPassword -AsPlainText -Force
        Set-Stage 3
        Install-ADDSForest -DomainName $DomainName -DomainNetbiosName $NetbiosName -InstallDns `
            -SafeModeAdministratorPassword $sm -Force -ErrorAction Stop | Out-Null
        Log 'The domain controller step finished. Windows restarts by itself now.'
    } catch {
        Set-Stage 2
        Log ('The domain controller step failed: ' + $_.Exception.Message)
        if ($tries -ge 2) { Stop-Build ('Making the domain controller failed: ' + $_.Exception.Message) }
        Log 'It will be tried once more after a restart'
        Restart-Computer -Force
    }
}

# ---------------------------------------------------------------------------------------
# Stage 3: runs by itself after the second restart. Plants the weak spots, turns on
# logging, checks the result, then cleans up after itself.
# ---------------------------------------------------------------------------------------
function Invoke-Stage3 {
    Log 'Stage 3 started: waiting for Active Directory to come up'
    if (-not (Test-IsDC)) {
        Log 'This server is not a domain controller yet. Going back to stage 2.'
        Set-Stage 2
        Invoke-Stage2
        return
    }
    $up = $false
    for ($i = 0; $i -lt 80; $i++) {
        try { Import-Module ActiveDirectory -ErrorAction Stop; Get-ADDomain -ErrorAction Stop | Out-Null; $up = $true; break }
        catch { Start-Sleep -Seconds 15 }
    }
    if (-not $up) { Stop-Build 'Active Directory did not answer after 20 minutes.' }
    Log 'Active Directory is up'

    function Add-LabUser {
        param([string]$Name, [string]$Password, [string]$Comment)
        $have = Get-ADUser -Filter ("SamAccountName -eq '" + $Name + "'") -ErrorAction SilentlyContinue
        if ($have) { Log ('  ' + $Name + ' already exists'); return }
        if ($Comment) { net.exe user $Name $Password /add ('/comment:' + $Comment) | Out-Null }
        else          { net.exe user $Name $Password /add | Out-Null }
        if ($LASTEXITCODE -eq 0) { Log ('  made ' + $Name) } else { Log ('  FAILED to make ' + $Name) }
    }

    Log 'Planting the weak spots the lab uses'
    Add-LabUser 'svc_sql' $WeakPassword ''
    setspn.exe -S MSSQLSvc/dc1.practice.local:1433 svc_sql | Out-Null
    try { Set-ADUser svc_sql -KerberosEncryptionType RC4 -ErrorAction Stop } catch { Log ('  FAILED RC4 on svc_sql: ' + $_.Exception.Message) }

    Add-LabUser 'legacy.app' $WeakPassword ''
    try { Set-ADAccountControl legacy.app -DoesNotRequirePreAuth $true -ErrorAction Stop } catch { Log ('  FAILED pre-auth on legacy.app: ' + $_.Exception.Message) }

    Add-LabUser 'samwell.t' $TempPassword ('Temp password: ' + $TempPassword)

    Add-LabUser 'helpdesk.temp' $WeakPassword ''
    net.exe group 'Domain Admins' helpdesk.temp /add 2>$null | Out-Null

    Log 'Turning on the audit logging the lab reads'
    foreach ($sub in 'Kerberos Service Ticket Operations', 'Kerberos Authentication Service', 'User Account Management',
                     'Security Group Management', 'Directory Service Access', 'Directory Service Changes', 'Logon', 'Other Object Access Events') {
        auditpol.exe /set ('/subcategory:' + $sub) /success:enable /failure:enable | Out-Null
        if ($LASTEXITCODE -ne 0) { Log ('  FAILED audit setting: ' + $sub) }
    }

    $opt = 'none'
    if (Test-Path $OptF) { $opt = (Get-Content $OptF | Select-Object -First 1) }
    if ($opt -eq 'SharedNetwork') {
        Log 'Shared network: turning off NetBIOS on the network cards so identical VMs do not fight over the name DC1'
        Get-CimInstance Win32_NetworkAdapterConfiguration -Filter 'IPEnabled = TRUE' | ForEach-Object {
            Invoke-CimMethod -InputObject $_ -MethodName SetTcpipNetbios -Arguments @{ TcpipNetbiosOptions = [uint32]2 } | Out-Null
        }
    }

    # ---- prove the build matches the lab (the runbook's "Build 9") ----
    Log 'Checking the result'
    $bad = @(); $good = @()
    $da = @(Get-ADGroupMember 'Domain Admins' -ErrorAction SilentlyContinue | ForEach-Object { $_.SamAccountName })
    if (($da -contains 'Administrator') -and ($da -contains 'helpdesk.temp')) { $good += 'Domain Admins has Administrator and helpdesk.temp' } else { $bad += 'Domain Admins is missing helpdesk.temp' }
    $u = Get-ADUser svc_sql -Properties * -ErrorAction SilentlyContinue
    if ($u -and (@($u.ServicePrincipalName) -contains 'MSSQLSvc/dc1.practice.local:1433')) { $good += 'svc_sql has its service name (SPN)' } else { $bad += 'svc_sql has no SPN' }
    if ($u -and ($u.'msDS-SupportedEncryptionTypes' -eq 4)) { $good += 'svc_sql is set to RC4' } else { $bad += 'svc_sql is not set to RC4' }
    $u = Get-ADUser legacy.app -Properties DoesNotRequirePreAuth -ErrorAction SilentlyContinue
    if ($u -and $u.DoesNotRequirePreAuth) { $good += 'legacy.app does not need pre-authentication' } else { $bad += 'legacy.app still needs pre-authentication' }
    $u = Get-ADUser samwell.t -Properties Description -ErrorAction SilentlyContinue
    if ($u -and ($u.Description -like 'Temp password*')) { $good += 'samwell.t has the password in its description' } else { $bad += 'samwell.t has no description' }
    $ap = (auditpol.exe /get '/subcategory:Kerberos Service Ticket Operations' | Out-String)
    if ($ap -match 'Success and Failure') { $good += 'Kerberos ticket auditing is on' } else { $bad += 'Kerberos ticket auditing is off' }
    if ($env:COMPUTERNAME -eq $ComputerName) { $good += 'the computer is named DC1' } else { $bad += ('the computer is named ' + $env:COMPUTERNAME + ', not DC1') }
    foreach ($g in $good) { Log ('  ok: ' + $g) }
    foreach ($b in $bad)  { Log ('  WRONG: ' + $b) }

    # ---- clean up: nothing from the build should show up in the lab ----
    Log 'Cleaning up'
    schtasks.exe /Delete /TN $TaskName /F 2>$null | Out-Null
    Get-ChildItem 'C:\Users\*\AppData\Roaming\Microsoft\Windows\PowerShell\PSReadLine\ConsoleHost_history.txt' -Force -ErrorAction SilentlyContinue |
        Remove-Item -Force -ErrorAction SilentlyContinue
    wevtutil.exe cl 'Microsoft-Windows-PowerShell/Operational' 2>$null
    wevtutil.exe cl 'Windows PowerShell' 2>$null
    Remove-Item -LiteralPath $StateF, $OptF, (Join-Path $Dir 'tries.txt') -Force -ErrorAction SilentlyContinue

    if ($bad.Count -eq 0) {
        Log 'BUILD FINISHED OK'
        Write-Result $true (@('This VM is DC1 in the domain practice.local, with the lab weak spots planted.', '') + ($good | ForEach-Object { 'ok: ' + $_ }))
        # the build is done: remove every copy of this script, because it holds the practice passwords
        if (Test-Path $OrigF) {
            $orig = (Get-Content $OrigF | Select-Object -First 1)
            if ($orig -and (Test-Path -LiteralPath $orig)) { Remove-Item -LiteralPath $orig -Force -ErrorAction SilentlyContinue }
            Remove-Item -LiteralPath $OrigF -Force -ErrorAction SilentlyContinue
        }
        Remove-Item -LiteralPath $Self -Force -ErrorAction SilentlyContinue
    } else {
        Log 'BUILD FINISHED WITH PROBLEMS'
        Write-Result $false (@('The build ran, but these do not match the lab:') + ($bad | ForEach-Object { 'WRONG: ' + $_ }))
    }
}

# ---------------------------------------------------------------------------------------
switch (Get-Stage) {
    1 { Invoke-Stage1 }
    2 { Invoke-Stage2 }
    3 { Invoke-Stage3 }
    default { Invoke-Stage1 }
}
