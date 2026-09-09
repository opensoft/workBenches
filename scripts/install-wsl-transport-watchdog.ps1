[CmdletBinding()]
param(
    [ValidateSet('Install', 'Uninstall', 'Start', 'Stop', 'Status')]
    [string]$Action = 'Install',

    [ValidatePattern('^[A-Za-z0-9][A-Za-z0-9._-]*$')]
    [string]$Distribution = 'Ubuntu-24.04'
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$taskName = 'workBenches WSL Transport Watchdog'
$installDirectory = Join-Path $env:LOCALAPPDATA 'workBenches\wsl-transport-watchdog'
$installedScript = Join-Path $installDirectory 'wsl-transport-watchdog.ps1'
$sourceScript = Join-Path $PSScriptRoot 'wsl-transport-watchdog.ps1'
$systemRoot = $env:SystemRoot
if (-not $systemRoot) {
    $systemRoot = [Environment]::GetEnvironmentVariable('SystemRoot', 'Machine')
}
if (-not $systemRoot) {
    throw 'Unable to resolve the Windows system directory.'
}
$powerShellPath = Join-Path $systemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe'

function Get-WatchdogTask {
    return Get-ScheduledTask -TaskName $taskName -ErrorAction SilentlyContinue
}

function Show-WatchdogStatus {
    $task = Get-WatchdogTask
    $taskInfo = if ($null -ne $task) { Get-ScheduledTaskInfo -TaskName $taskName } else { $null }
    $statePath = Join-Path $installDirectory 'status.json'
    $watchdogStatus = if (Test-Path -LiteralPath $statePath) { Get-Content -LiteralPath $statePath -Raw | ConvertFrom-Json } else { $null }
    $daemonRunning = $false
    if ($null -ne $watchdogStatus -and $null -ne $watchdogStatus.daemon) {
        try {
            $daemonProcess = Get-Process -Id ([int]$watchdogStatus.daemon.process_id) -ErrorAction Stop
            $actualStart = [DateTimeOffset]$daemonProcess.StartTime
            $expectedStart = [DateTimeOffset]$watchdogStatus.daemon.process_start_time
            $daemonRunning = [Math]::Abs(($actualStart - $expectedStart).TotalSeconds) -lt 1
        }
        catch {
            $daemonRunning = $false
        }
    }
    [ordered]@{
        installed = ($null -ne $task)
        task_state = if ($null -ne $task) { [string]$task.State } else { $null }
        last_run_time = if ($null -ne $taskInfo) { $taskInfo.LastRunTime.ToString('o') } else { $null }
        last_task_result = if ($null -ne $taskInfo) { $taskInfo.LastTaskResult } else { $null }
        installed_script = $installedScript
        daemon_running = $daemonRunning
        watchdog_status = $watchdogStatus
    } | ConvertTo-Json -Depth 8
}

if ($Action -eq 'Status') {
    Show-WatchdogStatus
    exit 0
}

if ($Action -eq 'Stop') {
    $task = Get-WatchdogTask
    if ($null -ne $task) {
        Stop-ScheduledTask -TaskName $taskName
    }
    Show-WatchdogStatus
    exit 0
}

if ($Action -eq 'Start') {
    if ($null -eq (Get-WatchdogTask)) {
        throw "Scheduled task '$taskName' is not installed."
    }
    Start-ScheduledTask -TaskName $taskName
    Start-Sleep -Seconds 2
    Show-WatchdogStatus
    exit 0
}

if ($Action -eq 'Uninstall') {
    $task = Get-WatchdogTask
    if ($null -ne $task) {
        Stop-ScheduledTask -TaskName $taskName -ErrorAction SilentlyContinue
        Unregister-ScheduledTask -TaskName $taskName -Confirm:$false
    }
    [ordered]@{
        installed = $false
        preserved_state_directory = $installDirectory
    } | ConvertTo-Json
    exit 0
}

if (-not (Test-Path -LiteralPath $sourceScript)) {
    throw "Watchdog source not found: $sourceScript"
}

New-Item -ItemType Directory -Path $installDirectory -Force | Out-Null
$existingTask = Get-WatchdogTask
if ($null -ne $existingTask -and $existingTask.State -eq 'Running') {
    Stop-ScheduledTask -TaskName $taskName
    Start-Sleep -Seconds 1
}
Copy-Item -LiteralPath $sourceScript -Destination $installedScript -Force

$arguments = '-NoProfile -NonInteractive -ExecutionPolicy Bypass -WindowStyle Hidden -File "{0}" -Mode Daemon -Distribution "{1}"' -f $installedScript, $Distribution
$scheduledAction = New-ScheduledTaskAction -Execute $powerShellPath -Argument $arguments
$trigger = New-ScheduledTaskTrigger -AtLogOn -User ([Security.Principal.WindowsIdentity]::GetCurrent().Name)
$settings = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -RestartCount 3 -RestartInterval (New-TimeSpan -Minutes 1) -ExecutionTimeLimit ([TimeSpan]::Zero)
$principal = New-ScheduledTaskPrincipal -UserId ([Security.Principal.WindowsIdentity]::GetCurrent().Name) -LogonType Interactive -RunLevel Limited

Register-ScheduledTask -TaskName $taskName -Action $scheduledAction -Trigger $trigger -Settings $settings -Principal $principal -Description 'Detects WSL host-to-guest session transport timeouts; kills only its own timed-out probe and never restarts or shuts down WSL.' -Force | Out-Null
Start-ScheduledTask -TaskName $taskName
Start-Sleep -Seconds 2
Show-WatchdogStatus
