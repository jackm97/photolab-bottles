# Make WPF render in software and set the wined3d renderer in the prefix.
# Usage: nu scripts/prefix-render.nu <prefix>
# Uses wine and wineserver from PATH.
def main [prefix: string] {
    let prefix = ($prefix | path expand)
    if not ($prefix | path exists) { error make {msg: $'prefix does not exist: ($prefix)'} }
    $env.WINEPREFIX = $prefix

    # WPF: keep it from presenting through GPU (DXVK-backed) composition.
    ^wine reg add 'HKCU\Software\Microsoft\Avalon.Graphics' /v DisableHWAcceleration /t REG_DWORD /d 1 /f
    # wined3d renderer is a wined3d value, not a DLL override.
    ^wine reg add 'HKCU\Software\Wine\Direct3D' /v renderer /t REG_SZ /d vulkan /f
    ^wineserver -w

    ^wine reg query 'HKCU\Software\Microsoft\Avalon.Graphics' /v DisableHWAcceleration
    ^wine reg query 'HKCU\Software\Wine\Direct3D' /v renderer
}
