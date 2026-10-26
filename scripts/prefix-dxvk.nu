# Install the DXVK and vkd3d-proton DLLs into a prefix and force them native.
# Usage: nu scripts/prefix-dxvk.nu <prefix>
# Uses wine and wineserver from PATH; the DLLs come from $CONDA_PREFIX/share.
def main [prefix: string] {
    let prefix = ($prefix | path expand)
    $env.WINEPREFIX = $prefix
    let share = ($env.CONDA_PREFIX | path join share)
    let sys32 = ($prefix | path join drive_c windows system32)
    let wow64 = ($prefix | path join drive_c windows syswow64)
    mkdir $sys32 $wow64

    # x64 -> system32, x86 -> syswow64, for both packages.
    let copies = [
        {src: ($share | path join dxvk x64), dst: $sys32}
        {src: ($share | path join vkd3d-proton x64), dst: $sys32}
        {src: ($share | path join dxvk x86), dst: $wow64}
        {src: ($share | path join vkd3d-proton x86), dst: $wow64}
    ]
    mut names = []
    for c in $copies {
        for f in (glob ($c.src | path join '*.dll')) {
            cp $f $c.dst
            $names = ($names | append ($f | path parse | get stem))
        }
    }

    let names = ($names | uniq | sort)
    for n in $names {
        ^wine reg add 'HKCU\Software\Wine\DllOverrides' /v $n /d native /f
    }
    ^wineserver -w
    print 'DLL overrides set to native:'
    $names | each {|n| print $'  ($n)' } | ignore
}
