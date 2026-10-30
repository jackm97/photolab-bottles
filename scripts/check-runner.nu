# Re-checks a finished runner tarball the way Bottles 67.5 reads it:
#   nu scripts/check-runner.nu <tarball.tar.xz>
# Needs tar and xz on PATH. Extracts into a fresh mktemp directory and removes it.

# windows-rs 0.62.0 Windows.winmd, as pinned in wine/packages/windows-winmd/recipe.yaml.
const winmd_sha256 = 'aea3e9828927aedd1ace2b927911e826f386d5c52dc6bd4151c10d314cb1adbf'

def main [tarball: path] {
    let tarball = ($tarball | path expand)

    # Bottles treats soda-<major>.<minor>-<n> runners with version >= 11.0.26 as having Eagle.
    let top = ($tarball | path basename | str replace --regex '\.tar\.xz$' '' | str replace --regex '-x86_64$' '')
    let m = ($top | parse --regex '^soda-(?<major>\d+)\.(?<minor>\d+)-(?<patch>\d+)(?:-|$)')
    if ($m | is-empty) {
        error make { msg: $"runner name ($top) does not look like soda-<major>.<minor>-<n>[-suffix]" }
    }
    let v = ($m | first)
    let version = [($v.major | into int) ($v.minor | into int) ($v.patch | into int)]
    let minimum = [11 0 26]
    let ok = ($version | zip $minimum | reduce --fold null {|pair, acc|
        if $acc != null { $acc } else if $pair.0 > $pair.1 { true } else if $pair.0 < $pair.1 { false } else { null }
    })
    if $ok == false {
        error make { msg: $"runner version ($version | str join '.') is below 11.0.26" }
    }

    let dir = (^mktemp --directory --tmpdir runner-check.XXXXXX | str trim)
    try {
        ^tar -xJf $tarball -C $dir
        let first = (^tar -tJf $tarball | lines | first)
        if $first != $"($top)-x86_64/" and $first != $"($top)/" {
            error make { msg: $"the first tar entry is ($first), expected the top directory" }
        }
        let root = $"($dir)/($first | str trim --right --char '/')"

        if (do { ^sh -c 'test -x "$1"' sh $"($root)/bin/eagle" } | complete).exit_code != 0 {
            error make { msg: "bin/eagle is missing or not executable" }
        }
        let providers = (open --raw $"($root)/share/eagle/providers.json" | from json)
        if $providers.tracing != 1 {
            error make { msg: $"providers.json tracing is ($providers.tracing), expected 1" }
        }
        for p in [winrt dwrite com wait] {
            let archs = ($providers.profiles | get $p)
            if not ('32' in $archs) or not ('64' in $archs) {
                error make { msg: $"providers.json profile ($p) is ($archs), expected both 32 and 64" }
            }
        }
        let actual = (open --raw $"($root)/share/wine/winmd/Windows.winmd" | hash sha256)
        if $actual != $winmd_sha256 {
            error make { msg: $"Windows.winmd sha256 is ($actual), expected ($winmd_sha256)" }
        }
    } catch {|e|
        rm --recursive --force $dir
        error make { msg: $e.msg }
    }
    rm --recursive --force $dir
    print $"ok: ($top)"
}
