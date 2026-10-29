# Repacks the conda photolab-wine package, plus Windows.winmd from the separate
# windows-winmd package (wine.inf copies it into every new prefix), into a
# Bottles runner tarball and writes everything the release needs into `out/`:
#   photolab-wine-<sha7>-x86_64.tar.xz   runner tarball (bin/, lib/, share/)
#   <original conda .tar.bz2>            copied from dist/
#   photolab-wine-<sha7>-source.tar.xz   LGPL source of the exact wine commit
#   runner-info.json                     name, file_name, url, md5, size, date
# Run from the repository root; wine/ is the checkout of the wine commit.

def main [
    --sha: string
    --wine-repo: string
    --wine-ref: string
    --dist: path = 'dist'
    --out: path = 'out'
] {
    if ($sha | is-empty) or (($sha | str length) < 7) {
        error make { msg: "--sha must be a full commit SHA" }
    }
    let sha7 = ($sha | str substring 0..6)
    let name = $"photolab-wine-($sha7)"
    let top = $"($name)-x86_64"
    print $"packaging ($name) from ($wine_repo) ($wine_ref) ($sha)"

    let dist_abs = ($dist | path expand)
    mkdir $out
    let out_abs = ($out | path expand)

    let pkgs = (glob $"($dist_abs)/**/photolab-wine-*.tar.bz2")
    if ($pkgs | length) != 1 {
        error make { msg: $"expected exactly one photolab-wine-*.tar.bz2 under ($dist_abs), found ($pkgs | length): ($pkgs)" }
    }
    let pkg = ($pkgs | first)

    let winmd_pkgs = (glob $"($dist_abs)/**/windows-winmd-*.tar.bz2")
    if ($winmd_pkgs | length) != 1 {
        error make { msg: $"expected exactly one windows-winmd-*.tar.bz2 under ($dist_abs), found ($winmd_pkgs | length): ($winmd_pkgs)" }
    }
    let winmd_pkg = ($winmd_pkgs | first)
    # windows-rs 0.62.0 Windows.winmd, as pinned in wine/packages/windows-winmd/recipe.yaml.
    let winmd_sha256 = 'aea3e9828927aedd1ace2b927911e826f386d5c52dc6bd4151c10d314cb1adbf'

    # Staging lives outside the repository and is removed also on failure.
    let stage = (^mktemp --directory --tmpdir photolab-runner.XXXXXX | str trim)
    try {
        cp $pkg $out_abs

        let extracted = $"($stage)/pkg"
        mkdir $extracted
        ^tar -xjf $pkg -C $extracted
        for d in [bin lib share] {
            if not ($"($extracted)/($d)" | path exists) {
                error make { msg: $"the package has no ($d)/ directory" }
            }
        }

        mkdir $"($stage)/($top)"
        for d in [bin lib share] {
            mv $"($extracted)/($d)" $"($stage)/($top)/($d)"
        }

        # Windows.winmd from the windows-winmd package, verified against the pinned hash.
        let winmd_dir = $"($stage)/winmd-pkg"
        mkdir $winmd_dir
        ^tar -xjf $winmd_pkg -C $winmd_dir
        let winmd_src = $"($winmd_dir)/share/wine/winmd/Windows.winmd"
        if not ($winmd_src | path exists) {
            error make { msg: $"the windows-winmd package has no share/wine/winmd/Windows.winmd" }
        }
        let winmd_actual = (open --raw $winmd_src | hash sha256)
        if $winmd_actual != $winmd_sha256 {
            error make { msg: $"Windows.winmd sha256 is ($winmd_actual), expected ($winmd_sha256)" }
        }
        mkdir $"($stage)/($top)/share/wine/winmd"
        cp $winmd_src $"($stage)/($top)/share/wine/winmd/Windows.winmd"

        # Multithreaded xz.
        let tarball = $"($out_abs)/($top).tar.xz"
        with-env { XZ_OPT: '-T0' } {
            ^tar -cJf $tarball -C $stage $top
        }

        let md5 = (^md5sum $tarball | split row ' ' | first)
        let size = (ls -D $tarball | get 0.size | into int)
        let date = (date now | format date '%s' | into int)

        {
            name: $name
            file_name: $"($top).tar.xz"
            url: $"https://github.com/jackm97/photolab-bottles/releases/download/($name)/($top).tar.xz"
            md5: $md5
            size: $size
            date: $date
        } | to json | save --force $"($out_abs)/runner-info.json"

        ^git -C wine -c 'tar.tar.xz.command=xz -c' archive --format=tar.xz --prefix=$"($name)-source/" --output $"($out_abs)/($name)-source.tar.xz" $sha
    } catch {|e|
        rm --recursive --force $stage
        error make { msg: $e.msg }
    }
    rm --recursive --force $stage
    print $"wrote ($out_abs):"
    ls $out_abs | select name size | print
}
