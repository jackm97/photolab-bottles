# Install System.Runtime.WindowsRuntime and System.Runtime.WindowsRuntime.UI.Xaml into a Wine prefix.
# These assemblies ship only in .NET 4.8's Windows 8+/10 CBS packages, not the MSI winetricks installs;
# their destinations follow the KB4486153 component manifests.
# They are extracted at run time from Microsoft's installer (verified by sha256); the binaries are never redistributed.
# Usage: nu scripts/prefix-netfx-winrt.nu <prefix>
# Needs 7z on PATH (the default pixi env provides it).

const INSTALLER = '/home/jack/.cache/winetricks/dotnet48/ndp48-x86-x64-allos-enu.exe'
const INSTALLER_URL = 'https://download.visualstudio.microsoft.com/download/pr/7afca223-55d2-470a-8edc-6a1739ae3252/abd170b4b0ec15ad0222a809b761a036/ndp48-x86-x64-allos-enu.exe'
const INSTALLER_SHA = '95889d6de3f2070c07790ad6cf2000d33d9a1bdfc6a381725ab82ab1c314fd53'
const CAB = 'x64-Windows10.0-KB4486153-x64.cab'
const WINRT_SHA = '1e1e6b4ac4e758fe1066e315f7928c393e1216dbe55c318803dd107123e1a8e3'
const XAML_SHA = '8e035a8667213e5a87b69757251a00c7c5f72c5b1b8f7578ec20688629b189e1'
const TOKEN_VERSION_DIR = 'v4.0_4.0.0.0__b77a5c561934e089'

def sha256 [path: string] {
    open --raw $path | hash sha256
}

# Resolve root/parts one component at a time, reusing an existing directory whose name differs
# only by case. Returns the path and the list of components that were taken from existing dirs
# with a different case than the canonical one.
def resolve-dir [root: string, parts: list<string>] {
    mut cur = $root
    mut diffs = []
    for p in $parts {
        let hit = (if ($cur | path exists) {
            ls --short-names $cur | where {|r| ($r.name | str lowercase) == ($p | str lowercase) } | get -o 0.name
        } else { null })
        let used = (if $hit == null { $p } else { $hit })
        if $hit != null and $hit != $p { $diffs = ($diffs | append $'"($hit)" instead of "($p)"') }
        $cur = ($cur | path join $used)
    }
    {path: $cur, diffs: $diffs}
}

# Run 7z with its output kept in <log>. 7z exits 1 for warnings (the Microsoft cabs always report one)
# and 2 or more for real failures, so only codes above 1 are errors.
def run-7z [log: string, args: list<string>] {
    let code = (try { ^7z ...$args o+e> $log; 0 } catch { ($env.LAST_EXIT_CODE? | default 2) })
    if $code > 1 {
        error make {msg: $'7z failed with exit code ($code): ($args | str join " ")(char nl)(open --raw $log | lines | last 10 | str join (char nl))'}
    }
}

# Make sure the cached installer exists and has the pinned sha256.
def ensure-installer [] {
    let fresh = (not ($INSTALLER | path exists))
    if $fresh {
        mkdir ($INSTALLER | path dirname)
        print $'downloading ($INSTALLER_URL)'
        http get --raw $INSTALLER_URL | save --raw --force $INSTALLER
    }
    let sha = (sha256 $INSTALLER)
    if $sha != $INSTALLER_SHA {
        # Only a file we just downloaded is removed; a pre-existing mismatch is left for the user to look at.
        if $fresh { rm --force $INSTALLER }
        error make {msg: $'installer sha256 mismatch: got ($sha), want ($INSTALLER_SHA)'}
    }
}

# Extract the two assemblies from the Win10 servicing cab into <tmp>/cabx and return their paths.
def extract-sources [tmp: string] {
    let exe_out = ($tmp | path join exe)
    let cab_out = ($tmp | path join cabx)
    mkdir $exe_out
    mkdir $cab_out
    let log = ($tmp | path join 7z.log)
    run-7z $log ['x' '-y' $'-o($exe_out)' $INSTALLER $CAB]
    let cab = ($exe_out | path join $CAB)
    if not ($cab | path exists) { error make {msg: $'($CAB) not found in the installer'} }
    run-7z $log ['x' '-y' $'-o($cab_out)' '-r' '-ir!*system.runtime.windowsruntime*.dll' $cab]

    let winrt = (glob ($cab_out | path join 'msil_system.runtime.windowsruntime_b77a5c561934e089_4.0.15744.161_*' 'system.runtime.windowsruntime.dll'))
    let xaml = (glob ($cab_out | path join 'msil_system.runtime.windowsruntime.ui.xaml_b77a5c561934e089_4.0.15744.161_*' 'system.runtime.windowsruntime.ui.xaml.dll'))
    if ($winrt | length) != 1 { error make {msg: $'expected exactly one System.Runtime.WindowsRuntime source, found ($winrt | length)'} }
    if ($xaml | length) != 1 { error make {msg: $'expected exactly one System.Runtime.WindowsRuntime.UI.Xaml source, found ($xaml | length)'} }
    let winrt_sha = (sha256 ($winrt | first))
    let xaml_sha = (sha256 ($xaml | first))
    if $winrt_sha != $WINRT_SHA { error make {msg: $'System.Runtime.WindowsRuntime sha256 mismatch: got ($winrt_sha), want ($WINRT_SHA)'} }
    if $xaml_sha != $XAML_SHA { error make {msg: $'System.Runtime.WindowsRuntime.UI.Xaml sha256 mismatch: got ($xaml_sha), want ($XAML_SHA)'} }
    {winrt: ($winrt | first), xaml: ($xaml | first)}
}

def main [prefix: string] {
    let prefix = ($prefix | path expand)
    if (which 7z | is-empty) { error make {msg: '7z not found on PATH; run this through pixi (pixi run prefix-netfx-winrt)'} }
    ensure-installer

    let tmp = (mktemp --directory --tmpdir 'netfx-winrt.XXXXXX')
    let result = (try {
        let src = (extract-sources $tmp)
        let items = [
            {name: 'System.Runtime.WindowsRuntime', src: $src.winrt}
            {name: 'System.Runtime.WindowsRuntime.UI.Xaml', src: $src.xaml}
        ]
        mut dests = []
        mut diffs = []
        for it in $items {
            let file = $'($it.name).dll'
            let dirs = [
                (resolve-dir $prefix ['drive_c' 'windows' 'Microsoft.NET' 'Framework' 'v4.0.30319'])
                (resolve-dir $prefix ['drive_c' 'windows' 'Microsoft.NET' 'Framework64' 'v4.0.30319'])
                (resolve-dir $prefix ['drive_c' 'windows' 'Microsoft.NET' 'assembly' 'GAC_MSIL' $it.name $TOKEN_VERSION_DIR])
            ]
            for d in $dirs {
                mkdir $d.path
                let dest = ($d.path | path join $file)
                cp $it.src $dest
                $dests = ($dests | append $dest)
                $diffs = ($diffs | append $d.diffs)
            }
        }
        {ok: true, dests: $dests, diffs: ($diffs | uniq)}
    } catch {|e|
        {ok: false, msg: $e.msg}
    })

    rm --recursive --force $tmp
    if not $result.ok { error make {msg: $result.msg} }

    if ($result.diffs | is-empty) {
        print 'case: every existing directory matched the canonical case (Microsoft.NET, Framework, Framework64, assembly, GAC_MSIL)'
    } else {
        print $'case: used existing directories with different case: ($result.diffs | str join "; ")'
    }
    print 'installed:'
    $result.dests | each {|p| print $p } | ignore
}
