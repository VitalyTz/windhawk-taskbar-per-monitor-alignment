# Lists the monitor identifiers used by the mod; does not change display settings.
Add-Type -TypeDefinition @"
using System;
using System.Runtime.InteropServices;
public static class TaskbarAlignmentMonitors {
    [StructLayout(LayoutKind.Sequential, CharSet = CharSet.Unicode)]
    public struct Info {
        public int cbSize;
        public int left, top, right, bottom;
        public int workLeft, workTop, workRight, workBottom;
        public uint flags;
        [MarshalAs(UnmanagedType.ByValTStr, SizeConst = 32)] public string device;
    }
    public delegate bool Callback(IntPtr monitor, IntPtr hdc, IntPtr rect, IntPtr data);
    [DllImport("user32.dll")] public static extern bool EnumDisplayMonitors(IntPtr hdc, IntPtr rect, Callback callback, IntPtr data);
    [DllImport("user32.dll", CharSet = CharSet.Unicode)] public static extern bool GetMonitorInfo(IntPtr monitor, ref Info info);

    // Display configuration, for the friendly name and the stable device path.
    [StructLayout(LayoutKind.Sequential)] public struct LUID { public uint low; public int high; }
    [StructLayout(LayoutKind.Sequential)] public struct PathSourceInfo { public LUID adapterId; public uint id; public uint modeInfoIdx; public uint statusFlags; }
    [StructLayout(LayoutKind.Sequential)] public struct PathTargetInfo {
        public LUID adapterId; public uint id; public uint modeInfoIdx; public uint outputTechnology;
        public uint rotation; public uint scaling; public uint refreshNumerator; public uint refreshDenominator;
        public uint scanLineOrdering; public int targetAvailable; public uint statusFlags;
    }
    [StructLayout(LayoutKind.Sequential)] public struct PathInfo { public PathSourceInfo sourceInfo; public PathTargetInfo targetInfo; public uint flags; }
    [StructLayout(LayoutKind.Sequential)] public struct ModeInfo { public uint infoType; public uint id; public LUID adapterId; public ModeUnion mode; }
    [StructLayout(LayoutKind.Explicit, Size = 48)] public struct ModeUnion { [FieldOffset(0)] public uint first; }
    [StructLayout(LayoutKind.Sequential)] public struct DeviceInfoHeader { public uint type; public uint size; public LUID adapterId; public uint id; }
    [StructLayout(LayoutKind.Sequential, CharSet = CharSet.Unicode)] public struct SourceName {
        public DeviceInfoHeader header;
        [MarshalAs(UnmanagedType.ByValTStr, SizeConst = 32)] public string viewGdiDeviceName;
    }
    [StructLayout(LayoutKind.Sequential, CharSet = CharSet.Unicode)] public struct TargetName {
        public DeviceInfoHeader header;
        public uint flags; public uint outputTechnology; public ushort edidManufactureId; public ushort edidProductCodeId; public uint connectorInstance;
        [MarshalAs(UnmanagedType.ByValTStr, SizeConst = 64)] public string monitorFriendlyDeviceName;
        [MarshalAs(UnmanagedType.ByValTStr, SizeConst = 128)] public string monitorDevicePath;
    }
    [DllImport("user32.dll")] public static extern int GetDisplayConfigBufferSizes(uint flags, out uint pathCount, out uint modeCount);
    [DllImport("user32.dll")] public static extern int QueryDisplayConfig(uint flags, ref uint pathCount, [Out] PathInfo[] paths, ref uint modeCount, [Out] ModeInfo[] modes, IntPtr topology);
    [DllImport("user32.dll", CharSet = CharSet.Unicode)] public static extern int DisplayConfigGetDeviceInfo(ref SourceName info);
    [DllImport("user32.dll", CharSet = CharSet.Unicode)] public static extern int DisplayConfigGetDeviceInfo(ref TargetName info);
}
"@

# Device name -> friendly name and device path, from the active display paths.
$names = @{}
$pathCount = 0; $modeCount = 0
if ([TaskbarAlignmentMonitors]::GetDisplayConfigBufferSizes(2, [ref]$pathCount, [ref]$modeCount) -eq 0) {
    $paths = New-Object 'TaskbarAlignmentMonitors+PathInfo[]' $pathCount
    $modes = New-Object 'TaskbarAlignmentMonitors+ModeInfo[]' $modeCount
    if ([TaskbarAlignmentMonitors]::QueryDisplayConfig(2, [ref]$pathCount, $paths, [ref]$modeCount, $modes, [IntPtr]::Zero) -eq 0) {
        # PowerShell discards writes to a nested field of a value type, so each
        # request header is built separately and assigned as a whole.
        function New-Header($type, $size, $adapterId, $id) {
            $header = [TaskbarAlignmentMonitors+DeviceInfoHeader]::new()
            $header.type = $type
            $header.size = $size
            $header.adapterId = $adapterId
            $header.id = $id
            return $header
        }
        foreach ($path in $paths[0..([Math]::Max($pathCount, 1) - 1)]) {
            $source = [TaskbarAlignmentMonitors+SourceName]::new()
            $source.header = New-Header 1 ([Runtime.InteropServices.Marshal]::SizeOf($source)) $path.sourceInfo.adapterId $path.sourceInfo.id
            if ([TaskbarAlignmentMonitors]::DisplayConfigGetDeviceInfo([ref]$source) -ne 0) { continue }
            $target = [TaskbarAlignmentMonitors+TargetName]::new()
            $target.header = New-Header 2 ([Runtime.InteropServices.Marshal]::SizeOf($target)) $path.targetInfo.adapterId $path.targetInfo.id
            if ([TaskbarAlignmentMonitors]::DisplayConfigGetDeviceInfo([ref]$target) -ne 0) { continue }
            $key = $source.viewGdiDeviceName
            if ($key -and -not $names.ContainsKey($key)) {
                $names[$key] = [pscustomobject]@{Friendly=$target.monitorFriendlyDeviceName; Path=$target.monitorDevicePath}
            }
        }
    }
}

$rows = [System.Collections.Generic.List[object]]::new()
$callback = [TaskbarAlignmentMonitors+Callback] {
    param($monitor, $hdc, $rect, $data)
    $info = [TaskbarAlignmentMonitors+Info]::new()
    $info.cbSize = [Runtime.InteropServices.Marshal]::SizeOf($info)
    if ([TaskbarAlignmentMonitors]::GetMonitorInfo($monitor, [ref]$info)) {
        $extra = $names[$info.device]
        $rows.Add([pscustomobject]@{
            Device=$info.device; Friendly=$extra.Friendly; Primary=($info.flags -band 1) -ne 0
            Left=$info.left; Top=$info.top; Width=$info.right-$info.left; Height=$info.bottom-$info.top
            DevicePath=$extra.Path
        })
    }
    return $true
}
[void][TaskbarAlignmentMonitors]::EnumDisplayMonitors([IntPtr]::Zero, [IntPtr]::Zero, $callback, [IntPtr]::Zero)
$rows | Format-Table Device, Friendly, Primary, Left, Top, Width, Height -AutoSize
Write-Host 'Device paths (any rule containing # matches part of one):'
$rows | ForEach-Object { Write-Host ("  {0,-12} {1}" -f $_.Device, $_.DevicePath) }
