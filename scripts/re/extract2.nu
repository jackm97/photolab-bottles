# Step 2 of the DxO installer reverse engineering (read-only analysis, nothing is executed).
# Run: pixi run -e re nu scripts/re/extract2.nu   (from the repo root)
# Each extraction goes into its own new, empty directory under build/re/; scripts stay here.
# A failing part prints its error and the script continues with the next part.

def fresh-dir [path: string] {
    if ($path | path exists) { rm -rf $path }
    mkdir $path
}

def rel [root: string] { each {|p| $p | path relative-to $root } }

def cs-files [dir: string] { glob ($dir | path join '**' '*.cs') }

def main [] {
    let root = ($env.PIXI_PROJECT_ROOT? | default $env.PWD)
    let re = ($root | path join build re)
    let ilspy = ($root | path join build tools ilspy ilspycmd)

    # B. IL of WindowsAppSDKRuntimeHelper
    print '=== B. ilspycmd --ilcode for WindowsAppSDKRuntimeHelper'
    let il_dir = ($re | path join il)
    fresh-dir $il_dir
    let il_file = ($il_dir | path join WindowsAppSDKRuntimeHelper.il)
    let ca_dll = ($re | path join ca DxO.PhotoLab.Installer.CustomActions.dll)
    try {
        ^$ilspy --ilcode -t DxO.PhotoLab.Installer.CustomActions.WindowsAppSDKRuntimeHelper $ca_dll o> $il_file
        print $'wrote ($il_file | path relative-to $root): (ls $il_file | get size.0)'
    } catch {|e| print $'B FAILED: ($e.msg)' }

    # C. official WinRT metadata
    print '=== C. Microsoft.Windows.SDK.Contracts'
    let sdk = ($re | path join sdk-contracts)
    fresh-dir $sdk
    let nupkg = ($sdk | path join sdk-contracts.nupkg)
    let exact = '10.0.26100.1742'
    let got = (try {
        http get --raw $'https://www.nuget.org/api/v2/package/Microsoft.Windows.SDK.Contracts/($exact)' | save --force $nupkg
        true
    } catch {|e| print $'exact version failed: ($e.msg)'; false })
    # Fallback: the highest 10.0.26100.* version in the flat container index.
    let version = (if $got { $exact } else {
        try {
            let idx = (http get https://api.nuget.org/v3-flatcontainer/microsoft.windows.sdk.contracts/index.json)
            let cands = ($idx.versions | where {|v| $v | str starts-with '10.0.26100.' } | sort-by {|v| $v | split row '.' | last | into int })
            print $'10.0.26100.* versions listed: ($cands)'
            let pick = ($cands | last)
            http get --raw $'https://www.nuget.org/api/v2/package/Microsoft.Windows.SDK.Contracts/($pick)' | save --force $nupkg
            $pick
        } catch {|e| print $'C1 FAILED: ($e.msg)'; 'none' }
    })
    print $'NuGet version used: ($version)'
    let pkg = ($sdk | path join pkg)
    fresh-dir $pkg
    let sevenz = (if (which 7zz | is-not-empty) { '7zz' } else { '7z' })
    let winmds = (try {
        ^$sevenz x -y $'-o($pkg)' $nupkg | ignore
        glob ($pkg | path join '**' '*.winmd')
    } catch {|e| print $'C2 FAILED: ($e.msg)'; [] })
    print '--- .winmd files:'
    $winmds | rel $root | sort | str join (char nl) | print

    # The winmd that contains namespace Windows.Management.Deployment.
    let holders = ($winmds | where {|w| (try { (^rg -a -c -F 'Windows.Management.Deployment' $w | str trim | into int) > 0 } catch { false }) })
    print $'winmd files containing Windows.Management.Deployment: ($holders | rel $root)'
    let src = ($sdk | path join src)
    fresh-dir $src
    if ($holders | is-empty) { print 'C3 SKIPPED: no winmd contains the namespace' } else {
        let target = (($holders | where {|w| $w | str ends-with 'Windows.Foundation.UniversalApiContract.winmd' }) | append $holders | first)
        print $'decompiling ($target | path relative-to $root)'
        try { ^$ilspy -p -o $src $target } catch {|e| print $'C3 FAILED: ($e.msg)' }
    }

    print '--- C4: generated files for the requested types'
    let all_cs = (cs-files $src)
    let stems = ($all_cs | each {|p| {stem: ($p | path parse | get stem), path: $p} })
    let wanted_names = ([PackageManager AddPackageOptions StagePackageOptions RegisterPackageOptions PackageStubPreference]
        | append (1..12 | each {|n| $'IPackageManager($n)' })
        | append IPackageManager)
    for n in $wanted_names {
        let hit = ($stems | where stem == $n | get path)
        if ($hit | is-not-empty) { print $'($n): ($hit | rel $root)' }
    }
    print $'names with no own file: ($wanted_names | where {|n| ($stems | where stem == $n | is-empty) })'
    print $'total .cs files in src: ($all_cs | length)'
    let pm9 = ($stems | where stem == 'IPackageManager9' | get -o 0.path)
    if $pm9 != null {
        let words = (open --raw $pm9 | parse --regex '(?<w>[A-Za-z_][A-Za-z0-9_]*)' | get w | uniq)
        let named = ($words | where {|w| ($stems | where stem == $w | is-not-empty) and not ($w in $wanted_names) })
        print '--- other types named in IPackageManager9 that have their own file:'
        for n in $named { print $'($n): ($stems | where stem == $n | get path | rel $root)' }
    } else if ($all_cs | length) > 0 and ($all_cs | length) < 5 {
        print '(project output is a few big files; see paths above)'
    }

    # D. app payload
    print '=== D. payload'
    let payload = ($re | path join payload)
    fresh-dir $payload
    let cabs = (glob ($re | path join setup 'Data*.cab') | sort)
    try { ^cabextract -d $payload ...$cabs | ignore } catch {|e| print $'D1 FAILED: ($e.msg)' }
    let files = (glob ($payload | path join '**' '*') | where {|p| ($p | path type) == file })
    let total = ($files | each {|p| ls $p | get size.0 | into int } | math sum)
    print $'payload files: ($files | length), total size: ($total) bytes'
    for needle in ['MddBootstrapInitialize2' 'Microsoft.WindowsAppRuntime.Bootstrap.dll'] {
        print $'--- files containing ($needle)'
        let matches = (try { ^rg -l -a -F $needle $payload | lines } catch { [] })
        if ($matches | is-empty) { print '(none)' }
        for m in $matches {
            print $'($m | path relative-to $root)  size: (ls $m | get size.0 | into int) bytes'
            ^file $m | lines | first 4 | str join (char nl) | print
        }
    }
}
