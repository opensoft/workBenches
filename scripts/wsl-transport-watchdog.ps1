[CmdletBinding()]
param(
    [ValidateSet('Daemon', 'Once', 'Status', 'GuestSnapshot')]
    [string]$Mode = 'Daemon',

    [ValidatePattern('^[A-Za-z0-9][A-Za-z0-9._-]*$')]
    [string]$Distribution = 'Ubuntu-24.04',

    [ValidateRange(5, 3600)]
    [int]$IntervalSeconds = 30,

    [ValidateRange(2, 120)]
    [int]$ProbeTimeoutSeconds = 8,

    [ValidateRange(2, 20)]
    [int]$FailureThreshold = 2,

    [string]$StateDirectory = (Join-Path $env:LOCALAPPDATA 'workBenches\wsl-transport-watchdog'),

    [string]$OutputPath
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$script:Version = '1.0.0'
$script:StatePath = Join-Path $StateDirectory 'status.json'
$script:EventPath = Join-Path $StateDirectory 'events.jsonl'
$script:EvidenceDirectory = Join-Path $StateDirectory 'evidence'
$script:HeartbeatSeconds = 600
$script:MaxEventBytes = 5MB
$script:SystemRoot = $env:SystemRoot
if (-not $script:SystemRoot) {
    $script:SystemRoot = [Environment]::GetEnvironmentVariable('SystemRoot', 'Machine')
}
if (-not $script:SystemRoot) {
    throw 'Unable to resolve the Windows system directory.'
}

function Write-AtomicJson {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Path,

        [Parameter(Mandatory = $true)]
        [object]$Value
    )

    $directory = Split-Path -Parent $Path
    New-Item -ItemType Directory -Path $directory -Force | Out-Null
    $temporaryPath = Join-Path $directory ('.{0}.{1}.tmp' -f (Split-Path -Leaf $Path), [guid]::NewGuid().ToString('N'))
    try {
        $Value | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath $temporaryPath -Encoding UTF8
        Move-Item -LiteralPath $temporaryPath -Destination $Path -Force
    }
    finally {
        Remove-Item -LiteralPath $temporaryPath -Force -ErrorAction SilentlyContinue
    }
}

function Rotate-EventLog {
    if (-not (Test-Path -LiteralPath $script:EventPath)) {
        return
    }

    if ((Get-Item -LiteralPath $script:EventPath).Length -lt $script:MaxEventBytes) {
        return
    }

    for ($index = 2; $index -ge 1; $index--) {
        $source = '{0}.{1}' -f $script:EventPath, $index
        $destination = '{0}.{1}' -f $script:EventPath, ($index + 1)
        if (Test-Path -LiteralPath $source) {
            Move-Item -LiteralPath $source -Destination $destination -Force
        }
    }
    Move-Item -LiteralPath $script:EventPath -Destination ($script:EventPath + '.1') -Force
}

function Add-WatchdogEvent {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Event,

        [Parameter(Mandatory = $true)]
        [System.Collections.IDictionary]$Data
    )

    New-Item -ItemType Directory -Path $StateDirectory -Force | Out-Null
    Rotate-EventLog
    $payload = [ordered]@{
        timestamp = [DateTimeOffset]::UtcNow.ToString('o')
        version = $script:Version
        event = $Event
    }
    foreach ($key in $Data.Keys) {
        $payload[$key] = $Data[$key]
    }
    Add-Content -LiteralPath $script:EventPath -Value ($payload | ConvertTo-Json -Depth 10 -Compress) -Encoding UTF8
}

function Stop-OwnedProbe {
    param(
        [Parameter(Mandatory = $true)]
        [System.Diagnostics.Process]$Process
    )

    if ($Process.HasExited) {
        return $false
    }

    try {
        $Process.Kill()
        $null = $Process.WaitForExit(3000)
        return $true
    }
    catch {
        return $false
    }
}

function Invoke-WslTransportProbe {
    $start = [DateTimeOffset]::UtcNow
    $stopwatch = [Diagnostics.Stopwatch]::StartNew()
    $process = $null
    try {
        $startInfo = New-Object System.Diagnostics.ProcessStartInfo
        $startInfo.FileName = (Join-Path $script:SystemRoot 'System32\wsl.exe')
        # Windows PowerShell 5.1 does not expose ProcessStartInfo.ArgumentList.
        # Distribution is constrained to a shell-safe WSL name above, so pass
        # the four fixed arguments without quoting the distribution token.
        $startInfo.Arguments = "--distribution $Distribution --exec /bin/true"
        $startInfo.UseShellExecute = $false
        $startInfo.CreateNoWindow = $true
        $startInfo.RedirectStandardOutput = $true
        $startInfo.RedirectStandardError = $true
        $process = [System.Diagnostics.Process]::Start($startInfo)
        if (-not $process.WaitForExit($ProbeTimeoutSeconds * 1000)) {
            $probePid = $process.Id
            $killed = Stop-OwnedProbe -Process $process
            return [ordered]@{
                outcome = 'timeout'
                healthy = $false
                latency_ms = [int]$stopwatch.ElapsedMilliseconds
                exit_code = $null
                probe_pid = $probePid
                owned_probe_terminated = $killed
                started_at = $start.ToString('o')
            }
        }

        $standardOutput = $process.StandardOutput.ReadToEnd().Trim()
        $standardError = $process.StandardError.ReadToEnd().Trim()
        $errorText = if ($standardError) { $standardError } else { $standardOutput }
        $exitCode = $process.ExitCode
        return [ordered]@{
            outcome = if ($exitCode -eq 0) { 'success' } else { 'exit-error' }
            healthy = ($exitCode -eq 0)
            latency_ms = [int]$stopwatch.ElapsedMilliseconds
            exit_code = $exitCode
            probe_pid = $process.Id
            owned_probe_terminated = $false
            error_summary = if ($errorText) { $errorText.Substring(0, [Math]::Min(500, $errorText.Length)) } else { $null }
            started_at = $start.ToString('o')
        }
    }
    catch {
        return [ordered]@{
            outcome = 'probe-error'
            healthy = $false
            latency_ms = [int]$stopwatch.ElapsedMilliseconds
            exit_code = $null
            probe_pid = if ($null -ne $process) { $process.Id } else { $null }
            owned_probe_terminated = $false
            error_summary = $_.Exception.GetType().Name
            started_at = $start.ToString('o')
        }
    }
    finally {
        $stopwatch.Stop()
        if ($null -ne $process) {
            $process.Dispose()
        }
    }
}

function Get-HostSnapshot {
    $operatingSystem = Get-CimInstance Win32_OperatingSystem
    $computerSystem = Get-CimInstance Win32_ComputerSystem
    $wslProcesses = @(Get-CimInstance Win32_Process -Filter "Name='wsl.exe' OR Name='wslhost.exe'" -ErrorAction SilentlyContinue)
    $vmmem = Get-Process -Name vmmemWSL -ErrorAction SilentlyContinue
    $wslService = Get-CimInstance Win32_Service -Filter "Name='WSLService'" -ErrorAction SilentlyContinue
    $wslBinary = Get-Item -LiteralPath (Join-Path $script:SystemRoot 'System32\wsl.exe') -ErrorAction SilentlyContinue
    $packagedWslPath = if ($env:ProgramFiles) { Join-Path $env:ProgramFiles 'WSL\wsl.exe' } else { $null }
    $packagedWslBinary = if ($packagedWslPath) { Get-Item -LiteralPath $packagedWslPath -ErrorAction SilentlyContinue } else { $null }

    return [ordered]@{
        windows = [ordered]@{
            total_visible_gib = [Math]::Round($computerSystem.TotalPhysicalMemory / 1GB, 2)
            free_physical_gib = [Math]::Round(($operatingSystem.FreePhysicalMemory * 1KB) / 1GB, 2)
            free_virtual_gib = [Math]::Round(($operatingSystem.FreeVirtualMemory * 1KB) / 1GB, 2)
        }
        wsl_service = if ($null -ne $wslService) {
            [ordered]@{
                state = $wslService.State
                process_id = [int]$wslService.ProcessId
                start_mode = $wslService.StartMode
            }
        } else { $null }
        wsl_version = [ordered]@{
            launcher = if ($null -ne $wslBinary) { $wslBinary.VersionInfo.ProductVersion } else { $null }
            package = if ($null -ne $packagedWslBinary) { $packagedWslBinary.VersionInfo.ProductVersion } else { $null }
        }
        host_processes = [ordered]@{
            wsl_exe = @($wslProcesses | Where-Object { $_.Name -eq 'wsl.exe' }).Count
            wslhost_exe = @($wslProcesses | Where-Object { $_.Name -eq 'wslhost.exe' }).Count
            identities = @($wslProcesses | ForEach-Object {
                [ordered]@{
                    name = $_.Name
                    process_id = [int]$_.ProcessId
                    parent_process_id = [int]$_.ParentProcessId
                    creation_date = if ($null -ne $_.CreationDate) { ([DateTimeOffset]$_.CreationDate).ToString('o') } else { $null }
                }
            })
        }
        vmmem = if ($null -ne $vmmem) {
            [ordered]@{
                process_id = $vmmem.Id
                working_set_gib = [Math]::Round($vmmem.WorkingSet64 / 1GB, 2)
                private_memory_gib = [Math]::Round($vmmem.PrivateMemorySize64 / 1GB, 2)
                cpu_seconds = [Math]::Round($vmmem.CPU, 2)
            }
        } else { $null }
    }
}

function Convert-KeyValueFile {
    param([string[]]$Lines)

    $result = [ordered]@{}
    foreach ($line in $Lines) {
        if ($line -match '^([^:]+):\s+([0-9]+)\s*kB$') {
            $result[$Matches[1]] = [int64]$Matches[2]
        }
    }
    return $result
}

function Write-GuestSnapshot {
    if (-not $OutputPath) {
        throw 'GuestSnapshot requires -OutputPath.'
    }

        $distributionRoot = '\\wsl$\{0}' -f $Distribution
    $snapshot = [ordered]@{
        timestamp = [DateTimeOffset]::UtcNow.ToString('o')
        distribution = $Distribution
        filesystem_reachable = $false
        meminfo_kib = $null
        memory_pressure = $null
        uptime = $null
        relay_watchdog = $null
        error = $null
    }
    try {
        $procRoot = Join-Path $distributionRoot 'proc'
        $snapshot.filesystem_reachable = Test-Path -LiteralPath $procRoot
        if ($snapshot.filesystem_reachable) {
            $snapshot.meminfo_kib = Convert-KeyValueFile -Lines (Get-Content -LiteralPath (Join-Path $procRoot 'meminfo'))
            $snapshot.memory_pressure = Get-Content -LiteralPath (Join-Path $procRoot 'pressure\memory')
            $snapshot.uptime = Get-Content -LiteralPath (Join-Path $procRoot 'uptime')
        }
        $relayStatusPath = Join-Path $distributionRoot 'run\wsl-relay-watchdog\status.json'
        if (Test-Path -LiteralPath $relayStatusPath) {
            $snapshot.relay_watchdog = Get-Content -LiteralPath $relayStatusPath -Raw | ConvertFrom-Json
        }
    }
    catch {
        $snapshot.error = $_.Exception.GetType().Name
    }
    Write-AtomicJson -Path $OutputPath -Value $snapshot
}

function Invoke-BoundedGuestSnapshot {
    New-Item -ItemType Directory -Path $script:EvidenceDirectory -Force | Out-Null
    $temporaryPath = Join-Path $script:EvidenceDirectory ('.guest-{0}.json' -f [guid]::NewGuid().ToString('N'))
    $process = $null
    try {
        $powerShellPath = Join-Path $PSHOME 'powershell.exe'
        if (-not (Test-Path -LiteralPath $powerShellPath)) {
            $powerShellPath = (Get-Process -Id $PID).Path
        }
        $startInfo = New-Object System.Diagnostics.ProcessStartInfo
        $startInfo.FileName = $powerShellPath
        $startInfo.Arguments = '-NoProfile -NonInteractive -ExecutionPolicy Bypass -File "{0}" -Mode GuestSnapshot -Distribution "{1}" -StateDirectory "{2}" -OutputPath "{3}"' -f $PSCommandPath, $Distribution, $StateDirectory, $temporaryPath
        $startInfo.UseShellExecute = $false
        $startInfo.CreateNoWindow = $true
        $process = [System.Diagnostics.Process]::Start($startInfo)
        if (-not $process.WaitForExit(5000)) {
            $null = Stop-OwnedProbe -Process $process
            return [ordered]@{ completed = $false; outcome = 'timeout' }
        }
        if ($process.ExitCode -ne 0 -or -not (Test-Path -LiteralPath $temporaryPath)) {
            return [ordered]@{ completed = $false; outcome = 'error'; exit_code = $process.ExitCode }
        }
        return [ordered]@{
            completed = $true
            outcome = 'success'
            snapshot = Get-Content -LiteralPath $temporaryPath -Raw | ConvertFrom-Json
        }
    }
    catch {
        return [ordered]@{ completed = $false; outcome = 'error'; error = $_.Exception.GetType().Name }
    }
    finally {
        if ($null -ne $process) {
            $process.Dispose()
        }
        Remove-Item -LiteralPath $temporaryPath -Force -ErrorAction SilentlyContinue
    }
}

function Get-RelevantWindowsEvents {
    $startTime = (Get-Date).AddMinutes(-10)
    $eventSets = @()
    $queries = @(
        [ordered]@{ name = 'Microsoft-Windows-Host-Network-Service'; filter = @{ ProviderName = 'Microsoft-Windows-Host-Network-Service'; StartTime = $startTime } },
        [ordered]@{ name = 'Microsoft-Windows-Hyper-V-Compute-Admin'; filter = @{ LogName = 'Microsoft-Windows-Hyper-V-Compute-Admin'; StartTime = $startTime } },
        [ordered]@{ name = 'Microsoft-Windows-Hyper-V-Compute-Operational'; filter = @{ LogName = 'Microsoft-Windows-Hyper-V-Compute-Operational'; StartTime = $startTime } },
        [ordered]@{ name = 'Windows power and resume'; filter = @{ LogName = 'System'; ProviderName = @('Microsoft-Windows-Kernel-Power', 'Microsoft-Windows-Power-Troubleshooter'); StartTime = $startTime } }
    )
    foreach ($query in $queries) {
        try {
            $events = @(Get-WinEvent -FilterHashtable $query.filter -MaxEvents 25 -ErrorAction Stop)
            $eventSets += [ordered]@{
                provider = $query.name
                events = @($events | ForEach-Object {
                    [ordered]@{
                        timestamp = ([DateTimeOffset]$_.TimeCreated).ToString('o')
                        id = $_.Id
                        level = $_.LevelDisplayName
                        message = if ($_.Message) { $_.Message.Substring(0, [Math]::Min(1000, $_.Message.Length)) } else { $null }
                    }
                })
            }
        }
        catch {
            $eventSets += [ordered]@{ provider = $query.name; events = @(); error = $_.Exception.GetType().Name }
        }
    }
    return $eventSets
}

function Save-FailureEvidence {
    param(
        [Parameter(Mandatory = $true)]
        [System.Collections.IDictionary]$Probe,

        [Parameter(Mandatory = $true)]
        [int]$ConsecutiveFailures
    )

    New-Item -ItemType Directory -Path $script:EvidenceDirectory -Force | Out-Null
    $timestamp = [DateTimeOffset]::UtcNow
    $evidencePath = Join-Path $script:EvidenceDirectory ('wsl-transport-{0}.json' -f $timestamp.ToString('yyyyMMddTHHmmssfffZ'))
    $evidence = [ordered]@{
        timestamp = $timestamp.ToString('o')
        classification = 'wsl-host-to-guest-session-channel-stuck'
        consecutive_failures = $ConsecutiveFailures
        probe = $Probe
        host = Get-HostSnapshot
        guest = Invoke-BoundedGuestSnapshot
        windows_events = Get-RelevantWindowsEvents
        recovery_boundary = [ordered]@{
            owned_probe_terminated = [bool]$Probe.owned_probe_terminated
            unrelated_processes_signaled = 0
            wsl_service_restarted = $false
            distribution_terminated = $false
            wsl_shutdown = $false
        }
    }
    Write-AtomicJson -Path $evidencePath -Value $evidence
    return $evidencePath
}

function Read-ExistingState {
    if (-not (Test-Path -LiteralPath $script:StatePath)) {
        return $null
    }
    try {
        return Get-Content -LiteralPath $script:StatePath -Raw | ConvertFrom-Json
    }
    catch {
        return $null
    }
}

function Write-CurrentState {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Health,

        [Parameter(Mandatory = $true)]
        [int]$ConsecutiveFailures,

        [Parameter(Mandatory = $true)]
        [System.Collections.IDictionary]$Probe,

        [string]$LastEvidencePath,

        [string]$LastTransition
    )

    $currentProcess = Get-Process -Id $PID
    $state = [ordered]@{
        version = $script:Version
        timestamp = [DateTimeOffset]::UtcNow.ToString('o')
        distribution = $Distribution
        health = $Health
        consecutive_failures = $ConsecutiveFailures
        probe = $Probe
        daemon = [ordered]@{
            process_id = $PID
            process_start_time = ([DateTimeOffset]$currentProcess.StartTime).ToString('o')
            interval_seconds = $IntervalSeconds
            probe_timeout_seconds = $ProbeTimeoutSeconds
            failure_threshold = $FailureThreshold
        }
        last_transition = $LastTransition
        last_evidence_path = $LastEvidencePath
        safeguards = @(
            'kill-only-owned-probe',
            'never-restart-wslservice',
            'never-terminate-distribution',
            'never-shutdown-wsl',
            'never-signal-named-relays-or-sessionleaders'
        )
    }
    Write-AtomicJson -Path $script:StatePath -Value $state
    return $state
}

function Invoke-WatchdogCycle {
    param(
        [int]$PreviousFailureCount,
        [string]$PreviousHealth,
        [string]$LastEvidencePath,
        [string]$LastTransition
    )

    $probe = Invoke-WslTransportProbe
    $failureCount = if ($probe.healthy) { 0 } else { $PreviousFailureCount + 1 }
    $health = if ($probe.healthy) { 'healthy' } elseif ($failureCount -ge $FailureThreshold) { 'stuck' } else { 'degraded' }
    $transition = $LastTransition
    $evidencePath = $LastEvidencePath

    if ($health -ne $PreviousHealth) {
        $transition = [DateTimeOffset]::UtcNow.ToString('o')
        if ($health -eq 'stuck') {
            $evidencePath = Save-FailureEvidence -Probe $probe -ConsecutiveFailures $failureCount
        }
        Add-WatchdogEvent -Event 'health-transition' -Data ([ordered]@{
            previous_health = $PreviousHealth
            health = $health
            consecutive_failures = $failureCount
            probe = $probe
            evidence_path = $evidencePath
        })
    }

    $state = Write-CurrentState -Health $health -ConsecutiveFailures $failureCount -Probe $probe -LastEvidencePath $evidencePath -LastTransition $transition
    return [ordered]@{
        state = $state
        health = $health
        failure_count = $failureCount
        evidence_path = $evidencePath
        transition = $transition
    }
}

function Test-DaemonIdentity {
    param([object]$State)

    if ($null -eq $State -or $null -eq $State.daemon) {
        return $false
    }
    try {
        $process = Get-Process -Id ([int]$State.daemon.process_id) -ErrorAction Stop
        $actualStart = [DateTimeOffset]$process.StartTime
        $expectedStart = [DateTimeOffset]$State.daemon.process_start_time
        return [Math]::Abs(($actualStart - $expectedStart).TotalSeconds) -lt 1
    }
    catch {
        return $false
    }
}

function Show-Status {
    $state = Read-ExistingState
    if ($null -eq $state) {
        [ordered]@{ running = $false; status = 'unavailable'; state_path = $script:StatePath } | ConvertTo-Json -Depth 6
        return 3
    }
    $state | Add-Member -NotePropertyName running -NotePropertyValue (Test-DaemonIdentity -State $state) -Force
    $state | ConvertTo-Json -Depth 10
    if (-not $state.running) {
        return 3
    }
    return 0
}

function Run-Daemon {
    New-Item -ItemType Directory -Path $StateDirectory -Force | Out-Null
    $createdNew = $false
    $mutex = New-Object System.Threading.Mutex($true, 'Local\workBenches.WslTransportWatchdog', [ref]$createdNew)
    if (-not $createdNew) {
        $mutex.Dispose()
        return 0
    }

    $failureCount = 0
    $health = 'starting'
    $lastEvidencePath = $null
    $lastTransition = [DateTimeOffset]::UtcNow.ToString('o')
    $lastHeartbeat = [DateTimeOffset]::MinValue
    Add-WatchdogEvent -Event 'daemon-started' -Data ([ordered]@{ process_id = $PID; distribution = $Distribution })
    try {
        while ($true) {
            $result = Invoke-WatchdogCycle -PreviousFailureCount $failureCount -PreviousHealth $health -LastEvidencePath $lastEvidencePath -LastTransition $lastTransition
            $failureCount = $result.failure_count
            $health = $result.health
            $lastEvidencePath = $result.evidence_path
            $lastTransition = $result.transition
            $now = [DateTimeOffset]::UtcNow
            if (($now - $lastHeartbeat).TotalSeconds -ge $script:HeartbeatSeconds) {
                Add-WatchdogEvent -Event 'heartbeat' -Data ([ordered]@{
                    health = $health
                    consecutive_failures = $failureCount
                    latency_ms = $result.state.probe.latency_ms
                })
                $lastHeartbeat = $now
            }
            Start-Sleep -Seconds $IntervalSeconds
        }
    }
    finally {
        Add-WatchdogEvent -Event 'daemon-stopped' -Data ([ordered]@{ process_id = $PID })
        $mutex.ReleaseMutex()
        $mutex.Dispose()
    }
}

if ($Mode -eq 'GuestSnapshot') {
    Write-GuestSnapshot
    exit 0
}

if ($Mode -eq 'Status') {
    exit (Show-Status)
}

if ($Mode -eq 'Once') {
    $existingState = Read-ExistingState
    $previousFailureCount = if ($null -ne $existingState) { [int]$existingState.consecutive_failures } else { 0 }
    $previousHealth = if ($null -ne $existingState) { [string]$existingState.health } else { 'starting' }
    $lastEvidencePath = if ($null -ne $existingState) { [string]$existingState.last_evidence_path } else { $null }
    $lastTransition = if ($null -ne $existingState) { [string]$existingState.last_transition } else { [DateTimeOffset]::UtcNow.ToString('o') }
    $result = Invoke-WatchdogCycle -PreviousFailureCount $previousFailureCount -PreviousHealth $previousHealth -LastEvidencePath $lastEvidencePath -LastTransition $lastTransition
    $result.state | ConvertTo-Json -Depth 10
    exit $(if ($result.health -eq 'healthy') { 0 } else { 2 })
}

exit (Run-Daemon)
