# Extract DxO's installer for reverse engineering (read-only analysis, nothing is executed).
# Run through `pixi run -e re re-extract` from the repo root.
# Every extraction goes into its own new, empty directory under build/re/; scripts stay here.
# A step that fails prints its error and later steps that need its output are skipped.

def fresh-dir [path: string] {
    if ($path | path exists) { rm -rf $path }
    mkdir $path
}

def main [] {
    let root = ($env.PIXI_PROJECT_ROOT? | default $env.PWD)
    let re = ($root | path join build re)
    let setup_exe = '/home/jack/Downloads/DxO_PhotoLab9_Setup.exe'
    let ilspy = ($root | path join build tools ilspy ilspycmd)
    let helper = ($root | path join scripts re msi_streams.py)
    let sevenz = (if (which 7zz | is-not-empty) { '7zz' } else { '7z' })

    # a. unpack the setup executable
    print '=== a. 7z x setup exe'
    let setup_dir = ($re | path join setup)
    fresh-dir $setup_dir
    try {
        ^$sevenz x -y $'-o($setup_dir)' $setup_exe
        print '--- files in build/re/setup:'
        glob ($setup_dir | path join '**' '*') | where {|p| ($p | path type) == file } | each {|p| $p | path relative-to $root } | sort | print
    } catch {|e| print $'a FAILED: ($e.msg)' }

    # b. dump Binary.* streams of the msi
    print '=== b. msi Binary streams'
    let msis = (glob ($setup_dir | path join '**' '*.msi'))
    print $'msi files found: ($msis)'
    let bin_dir = ($re | path join msi-binary)
    fresh-dir $bin_dir
    if ($msis | is-empty) { print 'b SKIPPED: no .msi found' } else {
        try { ^python -I $helper ($msis | first) $bin_dir } catch {|e| print $'b FAILED: ($e.msg)' }
    }

    # c. the WiX DTF SFXCA host has an embedded cabinet
    print '=== c. cabextract the custom action dll'
    let ca_dll = ($bin_dir | path join DxO.PhotoLab.Installer.CustomActions.CA.dll)
    let ca_dir = ($re | path join ca)
    fresh-dir $ca_dir
    if not ($ca_dll | path exists) { print $'c SKIPPED: ($ca_dll) not found' } else {
        try {
            ^cabextract -d $ca_dir $ca_dll
            print '--- files in build/re/ca:'
            glob ($ca_dir | path join '**' '*') | where {|p| ($p | path type) == file } | each {|p| $p | path relative-to $root } | sort | print
        } catch {|e| print $'c FAILED: ($e.msg)' }
    }

    # d. decompile DxO.* assemblies only (no Microsoft.* or WixToolset.*)
    print '=== d. ilspycmd'
    let dlls = (glob ($ca_dir | path join '**' 'DxO.*.dll'))
    print $'DxO assemblies: ($dlls | each {|p| $p | path basename })'
    for dll in $dlls {
        let name = ($dll | path basename | str replace -r '\.dll$' '')
        let out = ($re | path join src $name)
        fresh-dir $out
        print $'--- ilspycmd ($name)'
        try { ^$ilspy -p -o $out $dll } catch {|e| print $'d FAILED for ($name): ($e.msg)' }
        print '.cs files:'
        glob ($out | path join '**' '*.cs') | each {|p| $p | path relative-to $root } | sort | print
    }

    # e. fetch the Windows App SDK runtime installer; it is not run
    print '=== e. WindowsAppRuntimeInstall download'
    let appsdk_dir = ($re | path join appsdk)
    fresh-dir $appsdk_dir
    let url = 'https://download-center.dxo.com/PhotoLab/v9/Win/dependencies/WindowsAppSDK/WindowsAppRuntimeInstall-x64_2.2.0.0.exe'
    let dest = ($appsdk_dir | path join WindowsAppRuntimeInstall-x64_2.2.0.0.exe)
    try {
        http get --raw $url | save --force $dest
        print $'sha256: (open --raw $dest | hash sha256)'
        let size = (ls $dest | get size.0)
        print $'size: ($size) = (($size | into int)) bytes'
    } catch {|e| print $'e FAILED: ($e.msg)' }
}
