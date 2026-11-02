<#
  Connect-AirPods.ps1 - one-click connect for paired Bluetooth headphones.

  Asks the Windows Bluetooth audio driver to reconnect the device, the same
  request the "Connect" button in Settings makes (KSPROPERTY_ONESHOT_RECONNECT).
  No admin rights needed.

  Usage:
    Connect-AirPods.ps1                  connect anything named *AirPods*
    Connect-AirPods.ps1 -Disconnect      disconnect audio (AirPods rejoin on their own
                                         after ~12 s unless another device takes them)
    Connect-AirPods.ps1 -Name "Sony"     another headset
    Connect-AirPods.ps1 -Quiet           no notification
#>
param(
    [string]$Name = 'AirPods',
    [switch]$Disconnect,
    [switch]$Quiet
)

# The helper is compiled once into a DLL next to this script and rebuilt when the script changes.
$helperDll = Join-Path $PSScriptRoot 'AirPodsConnect.dll'
if (-not ('AirPodsConnect.BtAudio' -as [type]) -and (Test-Path $helperDll) -and
    (Get-Item $helperDll).LastWriteTime -gt (Get-Item $PSCommandPath).LastWriteTime) {
    Add-Type -Path $helperDll
}
if (-not ('AirPodsConnect.BtAudio' -as [type])) {
    Add-Type -OutputAssembly $helperDll -TypeDefinition @'
using System;
using System.Runtime.InteropServices;

namespace AirPodsConnect {
    [ComImport, Guid("BCDE0395-E52F-467C-8E3D-C4579291692E")]
    class MMDeviceEnumerator {}

    [ComImport, Guid("A95664D2-9614-4F35-A746-DE8DB63617E6"), InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
    interface IMMDeviceEnumerator {
        void EnumAudioEndpoints(int dataFlow, uint stateMask, out IntPtr devices);
        void GetDefaultAudioEndpoint(int dataFlow, int role, out IntPtr endpoint);
        void GetDevice([MarshalAs(UnmanagedType.LPWStr)] string id, out IMMDevice device);
    }

    [ComImport, Guid("D666063F-1587-4E43-81F1-B948E807363F"), InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
    interface IMMDevice {
        void Activate(ref Guid iid, uint clsCtx, IntPtr activationParams, [MarshalAs(UnmanagedType.IUnknown)] out object iface);
        void OpenPropertyStore(uint access, out IntPtr store);
        void GetId([MarshalAs(UnmanagedType.LPWStr)] out string id);
        void GetState(out uint state);
    }

    [ComImport, Guid("2A07407E-6497-4A18-9787-32F79BD0D98F"), InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
    interface IDeviceTopology {
        void GetConnectorCount(out uint count);
        void GetConnector(uint index, out IConnector connector);
    }

    [ComImport, Guid("9C2C4058-23F5-41DE-877A-DF3AF236A09E"), InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
    interface IConnector {
        void GetConnectorType(out int type);
        void GetDataFlow(out int flow);
        void ConnectTo(IntPtr other);
        void Disconnect();
        void IsConnected([MarshalAs(UnmanagedType.Bool)] out bool connected);
        void GetConnectedTo(out IntPtr other);
        void GetConnectorIdConnectedTo([MarshalAs(UnmanagedType.LPWStr)] out string id);
        void GetDeviceIdConnectedTo([MarshalAs(UnmanagedType.LPWStr)] out string id);
    }

    [StructLayout(LayoutKind.Sequential)]
    struct KsIdentifier {
        public Guid Set;
        public uint Id;
        public uint Flags;
    }

    [ComImport, Guid("28F54685-06FD-11D2-B27A-00A0C9223196"), InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
    interface IKsControl {
        [PreserveSig]
        int KsProperty(ref KsIdentifier property, uint propertyLength, IntPtr data, uint dataLength, out uint bytesReturned);
    }

    public static class BtAudio {
        public const uint Reconnect = 0;   // KSPROPERTY_ONESHOT_RECONNECT
        public const uint Disconnect = 1;  // KSPROPERTY_ONESHOT_DISCONNECT

        static readonly Guid KSPROPSETID_BtAudio = new Guid("7FA06C40-B8F6-4C7E-8556-E8C33A12E54D");

        static IMMDevice Open(string endpointId) {
            var enumerator = (IMMDeviceEnumerator)new MMDeviceEnumerator();
            IMMDevice device;
            enumerator.GetDevice(endpointId, out device);
            return device;
        }

        // DEVICE_STATE_*: 1 active, 2 disabled, 4 not present, 8 unplugged
        public static uint GetState(string endpointId) {
            uint state;
            Open(endpointId).GetState(out state);
            return state;
        }

        public static int Send(string endpointId, uint op) {
            Guid topologyIid = typeof(IDeviceTopology).GUID;
            object topology;
            Open(endpointId).Activate(ref topologyIid, 23 /* CLSCTX_ALL */, IntPtr.Zero, out topology);

            // The endpoint is wired to the Bluetooth audio driver's KS filter (Microsoft's
            // BthA2dp, or Intel Smart Sound on offload hardware); the property goes there.
            IConnector endpointConnector;
            string filterId;
            ((IDeviceTopology)topology).GetConnector(0, out endpointConnector);
            endpointConnector.GetDeviceIdConnectedTo(out filterId);

            Guid ksIid = typeof(IKsControl).GUID;
            object ks;
            Open(filterId).Activate(ref ksIid, 23 /* CLSCTX_ALL */, IntPtr.Zero, out ks);

            var property = new KsIdentifier { Set = KSPROPSETID_BtAudio, Id = op, Flags = 1 /* KSPROPERTY_TYPE_GET */ };
            uint returned;
            return ((IKsControl)ks).KsProperty(ref property, (uint)Marshal.SizeOf(property), IntPtr.Zero, 0, out returned);
        }
    }
}
'@
    Add-Type -Path $helperDll
}

function Show-Notice([string]$Text, [string]$Kind = 'Info') {
    if ($Quiet) { Write-Output $Text; return }
    Add-Type -AssemblyName System.Windows.Forms, System.Drawing
    $notice = New-Object System.Windows.Forms.NotifyIcon
    $logo = @(
        (Join-Path $PSScriptRoot 'icon.ico'),
        (Join-Path $PSScriptRoot 'assets\icon.ico')
    ) | Where-Object { Test-Path $_ } | Select-Object -First 1
    if ($logo) {
        $notice.Icon = New-Object System.Drawing.Icon $logo
    } else {
        $notice.Icon = [System.Drawing.SystemIcons]::Information
    }
    $notice.Visible = $true
    $notice.ShowBalloonTip(4000, 'AirPods', $Text, [System.Windows.Forms.ToolTipIcon]::$Kind)
    Start-Sleep -Seconds 4
    $notice.Dispose()
}

# Every audio endpoint of the device, stereo "Headphones" first. Which one accepts the
# request depends on the driver: Intel Smart Sound offload rejects both requests on the
# stereo endpoint but accepts them on Hands-Free (even while that endpoint shows as not
# present), so all of them get tried regardless of state.
# Read from the MMDevices registry (much faster than Get-PnpDevice). The device name is in
# PKEY_DeviceInterface_FriendlyName (,6) or, with offload drivers, in ,26.
$mmdevices = 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\MMDevices\Audio'
$endpoints = foreach ($flow in @{ Render = '0.0.0'; Capture = '0.0.1' }.GetEnumerator()) {
    foreach ($key in Get-ChildItem "$mmdevices\$($flow.Key)" -ErrorAction SilentlyContinue) {
        $props = Get-ItemProperty "$($key.PSPath)\Properties" -ErrorAction SilentlyContinue
        $names = "$($props.'{b3f8fa53-0004-438e-9003-51a46e139bfc},6') $($props.'{b3f8fa53-0004-438e-9003-51a46e139bfc},26')"
        if ($names -like "*$Name*") {
            [pscustomobject]@{
                Id     = "{$($flow.Value).00000000}.$($key.PSChildName)"
                Stereo = $props.'{a45c254e-df1c-4efd-8020-67d146a850e0},2' -eq 'Headphones'
                HFP    = $names -like '*Hands-Free*'
            }
        }
    }
}
$endpoints = $endpoints | Sort-Object { -not $_.Stereo }, { -not $_.HFP } | ForEach-Object Id

if (-not $endpoints) {
    Show-Notice "No paired audio device named '$Name' found. Pair it in Settings > Bluetooth & devices first." 'Warning'
    exit 1
}

# Audio is connected when any endpoint is active. (The Bluetooth link itself is no guide:
# AirPods keep it up even with audio disconnected.)
$connected = { @($endpoints | Where-Object { [AirPodsConnect.BtAudio]::GetState($_) -eq 1 }).Count -gt 0 }

if (-not $Disconnect -and (& $connected)) {
    Show-Notice 'Already connected.'
    exit 0
}

$op = if ($Disconnect) { [AirPodsConnect.BtAudio]::Disconnect } else { [AirPodsConnect.BtAudio]::Reconnect }
$sent = $false
foreach ($id in $endpoints) {
    try {
        if ([AirPodsConnect.BtAudio]::Send($id, $op) -ge 0) { $sent = $true; break }
    } catch { }
}

if (-not $sent) {
    Show-Notice 'Windows refused the request. Try toggling Bluetooth off and on.' 'Error'
    exit 1
}

# Wait for the endpoint to change state so the notice reflects what actually happened.
$deadline = (Get-Date).AddSeconds(10)
do {
    Start-Sleep -Milliseconds 500
    $done = if ($Disconnect) { -not (& $connected) } else { & $connected }
} until ($done -or (Get-Date) -gt $deadline)

if ($done) {
    Show-Notice $(if ($Disconnect) { 'Disconnected.' } else { 'Connected.' })
} elseif ($Disconnect) {
    Show-Notice 'Still connected after 10 seconds.' 'Warning'
    exit 1
} else {
    Show-Notice "Couldn't connect. Make sure they're out of the case and nearby." 'Warning'
    exit 1
}
