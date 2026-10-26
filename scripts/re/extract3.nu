# Step 3 of the DxO installer reverse engineering (read-only analysis, nothing is executed).
# Run: pixi run -e re nu scripts/re/extract3.nu   (from the repo root)
# 0a: decompile DxONET.Common.dll; 0b: IL dumps of the Windows.Management.Deployment types.
# Each extraction goes into its own new, empty directory under build/re/.

def fresh-dir [path: string] {
    if ($path | path exists) { rm -rf $path }
    mkdir $path
}

def main [] {
    let root = ($env.PIXI_PROJECT_ROOT? | default $env.PWD)
    let re = ($root | path join build re)
    let ilspy = ($root | path join build tools ilspy ilspycmd)

    # 0a. DxONET.Common
    print '=== 0a. ilspycmd -p DxONET.Common.dll'
    let common_out = ($re | path join src DxONET.Common)
    fresh-dir $common_out
    try { ^$ilspy -p -o $common_out ($re | path join payload DxONET.Common.dll) } catch {|e| print $'0a FAILED: ($e.msg)' }
    print '--- .cs files mentioning MddBootstrap or WindowsAppRuntime:'
    try { ^rg -l -e 'MddBootstrap' -e 'WindowsAppRuntime' $common_out | lines | each {|p| $p | path relative-to $root } | sort | str join (char nl) | print } catch { print '(none)' }

    # 0b. IL of the deployment types
    # ilspycmd ignores -t together with --ilcode on a winmd (every dump came out as the whole
    # assembly), so dump it once and cut each type out of that file.
    print "=== 0b. IL dumps"
    let winmd = ($re | path join sdk-contracts pkg ref netstandard2.0 Windows.Foundation.UniversalApiContract.winmd)
    let full_dir = ($re | path join il universal)
    fresh-dir $full_dir
    let full = ($full_dir | path join UniversalApiContract.il)
    try { ^$ilspy --ilcode $winmd o> $full } catch {|e| print $"0b full dump FAILED: ($e.msg)" }
    print $"full dump: (ls $full | get size.0 | into int) bytes"
    let il_dir = ($re | path join il deployment)
    fresh-dir $il_dir
    let lines = (open --raw $full | lines)
    let ns = "Windows.Management.Deployment."
    let wanted = [
        IPackageManager9
        AddPackageOptions IAddPackageOptions IAddPackageOptions2
        StagePackageOptions IStagePackageOptions IStagePackageOptions2
        RegisterPackageOptions IRegisterPackageOptions IRegisterPackageOptions2
        PackageVolume IPackageVolume IPackageVolume2
        PackageStubPreference StubPackageOption
    ]
    def cut [lines: list<string>, name: string] {
        let start = ($lines | enumerate | where {|r| $r.item =~ $"^\\.class .* ($name)$" } | get -o 0.index)
        if $start == null { return null }
        let stop = ($lines | enumerate | skip $start | where {|r| $r.item == $"} // end of class ($name)" } | get -o 0.index)
        $lines | skip $start | first ($stop - $start + 1)
    }
    mut queue = $wanted
    mut seen = []
    while ($queue | is-not-empty) {
        let t = ($queue | first)
        $queue = ($queue | skip 1)
        if $t in $seen { continue }
        $seen = ($seen | append $t)
        let block = (cut $lines $"($ns)($t)")
        if $block == null { print $"($t): NOT FOUND in the IL"; continue }
        $block | str join (char nl) | save --force ($il_dir | path join $"($t).il")
        print $"($t): ($block | length) lines"
        # Classes name their interfaces in .interfaceimpl lines; dump any not already wanted.
        let impls = ($block | where {|l| $l =~ "\\.interfaceimpl type" } | each {|l| $l | str replace --regex "^.*\\]" "" | str trim } )
        let extra = ($impls | where {|i| $i | str starts-with $ns } | each {|i| $i | str replace $ns "" } | where {|i| not ($i in $seen) and not ($i in $queue) })
        if ($extra | is-not-empty) { print $"  interfaces named by ($t) not in the list: ($extra)"; $queue = ($queue | append $extra) }
    }
}
