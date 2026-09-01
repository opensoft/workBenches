param(
    [string]$LogDirectory = "$env:LOCALAPPDATA\CodexAudioWatch",
    [int]$PollMilliseconds = 250,
    [int]$NetworkSnapshotSeconds = 10
)

$ErrorActionPreference = 'Stop'

$source = @'
using System;
using System.Collections.Generic;
using System.Diagnostics;
using System.Runtime.InteropServices;

namespace CodexAudioWatch {
    enum EDataFlow { eRender, eCapture, eAll }
    enum ERole { eConsole, eMultimedia, eCommunications }
    enum AudioSessionState { Inactive = 0, Active = 1, Expired = 2 }
    [Flags] enum DeviceState : uint { Active = 0x1 }

    [ComImport, Guid("BCDE0395-E52F-467C-8E3D-C4579291692E")]
    class MMDeviceEnumeratorComObject { }

    [ComImport, InterfaceType(ComInterfaceType.InterfaceIsIUnknown), Guid("A95664D2-9614-4F35-A746-DE8DB63617E6")]
    interface IMMDeviceEnumerator {
        int EnumAudioEndpoints(EDataFlow dataFlow, DeviceState stateMask, out IMMDeviceCollection devices);
        int GetDefaultAudioEndpoint(EDataFlow dataFlow, ERole role, out IMMDevice endpoint);
        int GetDevice([MarshalAs(UnmanagedType.LPWStr)] string id, out IMMDevice device);
        int RegisterEndpointNotificationCallback(IntPtr client);
        int UnregisterEndpointNotificationCallback(IntPtr client);
    }

    [ComImport, InterfaceType(ComInterfaceType.InterfaceIsIUnknown), Guid("0BD7A1BE-7A1A-44DB-8397-C0A388108711")]
    interface IMMDeviceCollection {
        int GetCount(out uint count);
        int Item(uint index, out IMMDevice device);
    }

    [ComImport, InterfaceType(ComInterfaceType.InterfaceIsIUnknown), Guid("D666063F-1587-4E43-81F1-B948E807363F")]
    interface IMMDevice {
        int Activate(ref Guid iid, uint clsCtx, IntPtr activationParams, [MarshalAs(UnmanagedType.IUnknown)] out object instance);
        int OpenPropertyStore(uint access, out IntPtr properties);
        int GetId([MarshalAs(UnmanagedType.LPWStr)] out string id);
        int GetState(out DeviceState state);
    }

    [ComImport, InterfaceType(ComInterfaceType.InterfaceIsIUnknown), Guid("77AA99A0-1BD6-484F-8BC7-2C654C9A9B6F")]
    interface IAudioSessionManager2 {
        int GetAudioSessionControl(IntPtr sessionGuid, uint streamFlags, out IntPtr sessionControl);
        int GetSimpleAudioVolume(IntPtr sessionGuid, uint streamFlags, out IntPtr audioVolume);
        int GetSessionEnumerator(out IAudioSessionEnumerator sessionEnumerator);
        int RegisterSessionNotification(IntPtr sessionNotification);
        int UnregisterSessionNotification(IntPtr sessionNotification);
        int RegisterDuckNotification([MarshalAs(UnmanagedType.LPWStr)] string sessionId, IntPtr duckNotification);
        int UnregisterDuckNotification(IntPtr duckNotification);
    }

    [ComImport, InterfaceType(ComInterfaceType.InterfaceIsIUnknown), Guid("E2F5BB11-0570-40CA-ACDD-3AA01277DEE8")]
    interface IAudioSessionEnumerator {
        int GetCount(out int count);
        int GetSession(int index, out IAudioSessionControl control);
    }

    [ComImport, InterfaceType(ComInterfaceType.InterfaceIsIUnknown), Guid("F4B1A599-7266-4319-A8CA-E70ACB11E8CD")]
    interface IAudioSessionControl {
        int GetState(out AudioSessionState state);
        int GetDisplayName([MarshalAs(UnmanagedType.LPWStr)] out string displayName);
        int SetDisplayName([MarshalAs(UnmanagedType.LPWStr)] string displayName, IntPtr eventContext);
        int GetIconPath([MarshalAs(UnmanagedType.LPWStr)] out string iconPath);
        int SetIconPath([MarshalAs(UnmanagedType.LPWStr)] string iconPath, IntPtr eventContext);
        int GetGroupingParam(out Guid groupingId);
        int SetGroupingParam(ref Guid groupingId, IntPtr eventContext);
        int RegisterAudioSessionNotification(IntPtr client);
        int UnregisterAudioSessionNotification(IntPtr client);
    }

    [ComImport, InterfaceType(ComInterfaceType.InterfaceIsIUnknown), Guid("BFB7FF88-7239-4FC9-8FA2-07C950BE9C6D")]
    interface IAudioSessionControl2 {
        int GetState(out AudioSessionState state);
        int GetDisplayName([MarshalAs(UnmanagedType.LPWStr)] out string displayName);
        int SetDisplayName([MarshalAs(UnmanagedType.LPWStr)] string displayName, IntPtr eventContext);
        int GetIconPath([MarshalAs(UnmanagedType.LPWStr)] out string iconPath);
        int SetIconPath([MarshalAs(UnmanagedType.LPWStr)] string iconPath, IntPtr eventContext);
        int GetGroupingParam(out Guid groupingId);
        int SetGroupingParam(ref Guid groupingId, IntPtr eventContext);
        int RegisterAudioSessionNotification(IntPtr client);
        int UnregisterAudioSessionNotification(IntPtr client);
        int GetSessionIdentifier([MarshalAs(UnmanagedType.LPWStr)] out string sessionIdentifier);
        int GetSessionInstanceIdentifier([MarshalAs(UnmanagedType.LPWStr)] out string sessionInstanceIdentifier);
        int GetProcessId(out uint processId);
        int IsSystemSoundsSession();
        int SetDuckingPreference(bool optOut);
    }

    [ComImport, InterfaceType(ComInterfaceType.InterfaceIsIUnknown), Guid("C02216F6-8C67-4B5B-9D00-D008E73E0064")]
    interface IAudioMeterInformation {
        int GetPeakValue(out float peak);
        int GetMeteringChannelCount(out int channelCount);
        int GetChannelsPeakValues(int channelCount, [Out] float[] peakValues);
        int QueryHardwareSupport(out int hardwareSupportMask);
    }

    public sealed class SessionInfo {
        public string EndpointId;
        public int Pid;
        public string State;
        public string DisplayName;
        public string SessionIdentifier;
        public float Peak;
    }

    public static class AudioSessions {
        public static SessionInfo[] GetAll() {
            var results = new List<SessionInfo>();
            var enumerator = (IMMDeviceEnumerator)(new MMDeviceEnumeratorComObject());
            IMMDeviceCollection collection;
            Marshal.ThrowExceptionForHR(enumerator.EnumAudioEndpoints(EDataFlow.eRender, DeviceState.Active, out collection));
            uint deviceCount;
            Marshal.ThrowExceptionForHR(collection.GetCount(out deviceCount));

            Guid managerGuid = typeof(IAudioSessionManager2).GUID;
            for (uint d = 0; d < deviceCount; d++) {
                IMMDevice device = null;
                object managerObject = null;
                IAudioSessionEnumerator sessions = null;
                try {
                    Marshal.ThrowExceptionForHR(collection.Item(d, out device));
                    string endpointId;
                    Marshal.ThrowExceptionForHR(device.GetId(out endpointId));
                    Marshal.ThrowExceptionForHR(device.Activate(ref managerGuid, 23, IntPtr.Zero, out managerObject));
                    var manager = (IAudioSessionManager2)managerObject;
                    Marshal.ThrowExceptionForHR(manager.GetSessionEnumerator(out sessions));
                    int sessionCount;
                    Marshal.ThrowExceptionForHR(sessions.GetCount(out sessionCount));

                    for (int s = 0; s < sessionCount; s++) {
                        IAudioSessionControl control = null;
                        try {
                            Marshal.ThrowExceptionForHR(sessions.GetSession(s, out control));
                            var control2 = (IAudioSessionControl2)control;
                            var meter = (IAudioMeterInformation)control;
                            uint pid;
                            AudioSessionState state;
                            string displayName = null;
                            string sessionId = null;
                            float peak = 0;
                            control2.GetProcessId(out pid);
                            control2.GetState(out state);
                            control2.GetDisplayName(out displayName);
                            control2.GetSessionIdentifier(out sessionId);
                            meter.GetPeakValue(out peak);
                            results.Add(new SessionInfo {
                                EndpointId = endpointId,
                                Pid = unchecked((int)pid),
                                State = state.ToString(),
                                DisplayName = displayName,
                                SessionIdentifier = sessionId,
                                Peak = peak
                            });
                        } catch { }
                        finally { if (control != null) Marshal.ReleaseComObject(control); }
                    }
                } catch { }
                finally {
                    if (sessions != null) Marshal.ReleaseComObject(sessions);
                    if (managerObject != null) Marshal.ReleaseComObject(managerObject);
                    if (device != null) Marshal.ReleaseComObject(device);
                }
            }
            Marshal.ReleaseComObject(collection);
            Marshal.ReleaseComObject(enumerator);
            return results.ToArray();
        }
    }
}
'@

Add-Type -TypeDefinition $source -Language CSharp

if (-not (Test-Path -LiteralPath $LogDirectory)) {
    New-Item -ItemType Directory -Path $LogDirectory -Force | Out-Null
}

$logPath = Join-Path $LogDirectory ("audio-sessions-{0}.jsonl" -f (Get-Date -Format 'yyyyMMdd-HHmmss'))
$statusPath = Join-Path $LogDirectory 'status.json'
$pidPath = Join-Path $LogDirectory 'watcher.pid'
$utf8NoBom = New-Object System.Text.UTF8Encoding($false)
$writer = New-Object System.IO.StreamWriter($logPath, $true, $utf8NoBom)
$writer.AutoFlush = $true

function Get-ProcessDetails([int]$ProcessId) {
    if ($ProcessId -eq 0) {
        return @{ processName = 'System Sounds'; processPath = $null; commandLine = $null }
    }
    try {
        $process = Get-Process -Id $ProcessId -ErrorAction Stop
        $path = $null
        try { $path = $process.Path } catch { }
        $commandLine = $null
        try { $commandLine = (Get-CimInstance Win32_Process -Filter "ProcessId=$ProcessId").CommandLine } catch { }
        return @{ processName = $process.ProcessName; processPath = $path; commandLine = $commandLine }
    } catch {
        return @{ processName = '<exited>'; processPath = $null; commandLine = $null }
    }
}

function Get-ForegroundProcess {
    try {
        $signature = '[DllImport("user32.dll")] public static extern IntPtr GetForegroundWindow(); [DllImport("user32.dll")] public static extern uint GetWindowThreadProcessId(IntPtr hWnd, out uint processId);'
        if (-not ('CodexForegroundWindow' -as [type])) { Add-Type -MemberDefinition $signature -Name CodexForegroundWindow -Namespace Win32 }
        $handle = [Win32.CodexForegroundWindow]::GetForegroundWindow()
        [uint32]$foregroundPid = 0
        [void][Win32.CodexForegroundWindow]::GetWindowThreadProcessId($handle, [ref]$foregroundPid)
        $foreground = Get-Process -Id $foregroundPid -ErrorAction Stop
        return @{ pid = [int]$foregroundPid; processName = $foreground.ProcessName; windowTitle = $foreground.MainWindowTitle }
    } catch { return $null }
}

try {
    [System.IO.File]::WriteAllText($pidPath, [string]$PID, $utf8NoBom)
    $startup = [ordered]@{ timestamp = (Get-Date).ToString('o'); event = 'watcher_started'; watcherPid = $PID; logPath = $logPath; pollMilliseconds = $PollMilliseconds }
    $writer.WriteLine(($startup | ConvertTo-Json -Compress -Depth 5))
    $lastNetworkSnapshot = [datetime]::MinValue
    $processCache = @{}

    while ($true) {
        $now = Get-Date
        $foreground = Get-ForegroundProcess
        $sessions = [CodexAudioWatch.AudioSessions]::GetAll()
        $activePids = New-Object 'System.Collections.Generic.HashSet[int]'

        foreach ($session in $sessions) {
            if ($session.State -ne 'Active' -and $session.Peak -le 0.0001) { continue }
            [void]$activePids.Add($session.Pid)
            if (-not $processCache.ContainsKey($session.Pid)) { $processCache[$session.Pid] = Get-ProcessDetails $session.Pid }
            $details = $processCache[$session.Pid]
            $record = [ordered]@{
                timestamp = $now.ToString('o')
                event = 'audio_sample'
                endpointId = $session.EndpointId
                pid = $session.Pid
                processName = $details.processName
                processPath = $details.processPath
                commandLine = $details.commandLine
                state = $session.State
                peak = [math]::Round([double]$session.Peak, 6)
                displayName = $session.DisplayName
                sessionIdentifier = $session.SessionIdentifier
                foreground = $foreground
            }
            $writer.WriteLine(($record | ConvertTo-Json -Compress -Depth 6))
        }

        if (($now - $lastNetworkSnapshot).TotalSeconds -ge $NetworkSnapshotSeconds -and $activePids.Count -gt 0) {
            $lastNetworkSnapshot = $now
            try {
                Get-NetTCPConnection -State Established -ErrorAction SilentlyContinue |
                    Where-Object { $activePids.Contains([int]$_.OwningProcess) } |
                    ForEach-Object {
                        $network = [ordered]@{
                            timestamp = $now.ToString('o'); event = 'network'; pid = [int]$_.OwningProcess
                            localAddress = $_.LocalAddress; localPort = $_.LocalPort
                            remoteAddress = $_.RemoteAddress; remotePort = $_.RemotePort
                        }
                        $writer.WriteLine(($network | ConvertTo-Json -Compress))
                    }
            } catch { }
        }

        $status = [ordered]@{ watcherPid = $PID; running = $true; lastPoll = $now.ToString('o'); logPath = $logPath; activeAudioPids = @($activePids) }
        [System.IO.File]::WriteAllText($statusPath, ($status | ConvertTo-Json -Compress), $utf8NoBom)
        Start-Sleep -Milliseconds $PollMilliseconds
    }
} finally {
    try { $writer.WriteLine((([ordered]@{ timestamp = (Get-Date).ToString('o'); event = 'watcher_stopped'; watcherPid = $PID }) | ConvertTo-Json -Compress)) } catch { }
    $writer.Dispose()
    try { Remove-Item -LiteralPath $pidPath -Force } catch { }
}
