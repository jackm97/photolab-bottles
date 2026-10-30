# Repacks the conda photolab-wine package, plus Windows.winmd from the separate
# windows-winmd package (wine.inf copies it into every new prefix) and the Eagle
# tooling built from the pinned bottles/soda commit, into a Bottles runner
# tarball and writes everything the release needs into `out/`:
#   soda-11.0-35-photolab-<sha7>-x86_64.tar.xz   runner tarball (bin/, lib/, share/)
#   <original conda .tar.bz2>                    copied from dist/
#   soda-11.0-35-photolab-<sha7>-source.tar.xz   LGPL source of the exact wine commit
#   soda-11.0-35-photolab-<sha7>-eagle-source.tar.xz  eagle/ and .github/build-eagle.sh at the pinned commit
#   EAGLE-SOURCE                                 Eagle and wine commits, one line each
#   runner-info.json                             name, file_name, url, md5, size, date, eagle_source, wine_sha
# Run from the repository root; wine/ is the checkout of the wine commit.
# Needs on PATH: tar xz bzip2 md5sum git curl sh, and pixi (build tools come from `pixi exec`).

# Directory of this script (build-eagle-deps.nu lives next to it); `path self` only works at parse time.
const scripts_dir = (path self | path dirname)

# bottles/soda commit the Eagle payload is built from (full SHA, verified after checkout).
const soda_commit = 'f6ff4d6d99a10eff8a532f618c6b2bbe7b4eae85'
const soda_url = 'https://github.com/bottlesdevs/wine.git'

# Pinned MinGW toolchain (provides x86_64- and i686-w64-mingw32-gcc), used unless both are already on PATH.
const mingw_url = 'https://github.com/xpack-dev-tools/mingw-w64-gcc-xpack/releases/download/v15.2.0-2/xpack-mingw-w64-gcc-15.2.0-2-linux-x64.tar.gz'
const mingw_sha256 = 'daf373cbea59bb04cc610cdc26ef98828eb5c5eee3407d448d3b26272fa816d5'

# conda-forge packages for the Eagle build (build-native.sh, build-analysis.sh, build-debugger.sh, yara autotools).
const eagle_specs = [gcc gxx make cmake meson ninja pkg-config autoconf automake libtool m4 patch python git binutils coreutils sed grep gawk findutils diffutils bash nushell tar xz bzip2 gzip]

# Runs a command inside a throwaway conda-forge environment with the Eagle build tools;
# `vars` are NAME: value pairs set after the environment's activation (via env(1)).
def px-run [vars: record, cmd: list<string>] {
    let specs = ($eagle_specs | each {|s| ['--spec' $s] } | flatten)
    let assigns = ($vars | items {|k, v| $"($k)=($v)" })
    ^pixi exec ...$specs -- env ...$assigns ...$cmd
}

# Returns the directory to put on PATH for the MinGW compilers, or '' when the
# runner already has both on PATH. Download is sha256-verified.
def ensure-mingw [stage: string] {
    if (which x86_64-w64-mingw32-gcc | is-not-empty) and (which i686-w64-mingw32-gcc | is-not-empty) {
        return ''
    }
    let dl = $"($stage)/mingw-dl"
    mkdir $dl
    let archive = $"($dl)/($mingw_url | path basename)"
    ^curl --fail --silent --show-error --location --output $archive $mingw_url
    let actual = (open --raw $archive | hash sha256)
    if $actual != $mingw_sha256 {
        error make { msg: $"MinGW archive sha256 is ($actual), expected ($mingw_sha256)" }
    }
    ^tar -xzf $archive -C $dl
    let bin = (glob $"($dl)/xpack-mingw-w64-gcc-*/bin" | first)
    for t in [x86_64-w64-mingw32-gcc i686-w64-mingw32-gcc] {
        if not ($"($bin)/($t)" | path exists) {
            error make { msg: $"the pinned MinGW archive has no ($t)" }
        }
    }
    rm $archive
    $bin
}

def main [
    --sha: string
    --wine-repo: string
    --wine-ref: string
    --dist: path = 'dist'
    --out: path = 'out'
    --soda-ref: string = $soda_commit
    --eagle-src: string = ''
] {
    if ($sha | is-empty) or (($sha | str length) < 7) {
        error make { msg: "--sha must be a full commit SHA" }
    }
    if not ($soda_ref =~ '^[0-9a-f]{40}$') {
        error make { msg: "--soda-ref must be a full 40-character commit SHA" }
    }
    let sha7 = ($sha | str substring 0..6)
    let name = $"soda-11.0-35-photolab-($sha7)"
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

        # ---- Eagle: bottles/soda eagle/ built at the pinned commit (replaces the tests-free part of .github/build-eagle.sh) ----
        # The soda checkout: a fresh partial clone of bottles/soda, or --eagle-src (local validation only).
        # In both cases HEAD must be exactly the pinned commit.
        let soda = if ($eagle_src | is-empty) {
            let dir = $"($stage)/soda"
            ^git clone --quiet --filter=blob:none --no-checkout $soda_url $dir
            if (do { ^git -C $dir cat-file -e $"($soda_ref)^{commit}" } | complete).exit_code != 0 {
                ^git -C $dir fetch --quiet origin $soda_ref
            }
            ^git -C $dir checkout --quiet --detach $soda_ref
            $dir
        } else {
            $eagle_src | path expand
        }
        let soda_head = (^git -C $soda rev-parse HEAD | str trim)
        if $soda_head != $soda_ref {
            error make { msg: $"the soda checkout is at ($soda_head), expected ($soda_ref)" }
        }
        for f in [eagle/build-native.sh eagle/install.py .github/build-eagle.sh] {
            if not ($"($soda)/($f)" | path exists) {
                error make { msg: $"the soda checkout has no ($f)" }
            }
        }

        # Static json-c, glib-2.0, sqlite3 (and deps) built from pinned sources, see build-eagle-deps.nu.
        let deps = $"($stage)/eagle-deps"
        let specs = ($eagle_specs | each {|s| ['--spec' $s] } | flatten)
        ^pixi exec ...$specs -- nu $"($scripts_dir)/build-eagle-deps.nu" --prefix $deps --work $"($stage)/eagle-deps-work"
        let pc = $"($deps)/lib/pkgconfig:($deps)/share/pkgconfig"

        let mingw_bin = (ensure-mingw $stage)
        let path_list = if ($mingw_bin | is-empty) { $env.PATH } else { $env.PATH | prepend $mingw_bin }

        # eagle/build-native.sh clones https://github.com/VirusTotal/yara at
        # f44a8958e88daa75d765a52a68876f2286d57a51 (eagle/sources.json) and needs network access.
        # build-native.sh refuses an existing package/ or native/ directory; t/ is the TMPDIR.
        let work = $"($stage)/eagle-work"
        mkdir $"($work)/t"
        let build_vars = {
            PKG_CONFIG_PATH: $pc
            PKG_CONFIG_LIBDIR: $pc
            PYTHONDONTWRITEBYTECODE: '1'
            TMPDIR: $"($work)/t"
            TMP: $"($work)/t"
            TEMP: $"($work)/t"
        }
        with-env { PATH: $path_list } {
            px-run $build_vars [sh $"($soda)/eagle/build-native.sh" $"($work)/package" '-' $"($work)/native"]
            ^cp -a $"($work)/package/." $"($stage)/($top)/"
            # install.py imports only the standard library and reads no environment, so -I is safe.
            px-run $build_vars [python3 '-I' $"($soda)/eagle/install.py" $"($stage)/($top)"]
        }

        # ---- Hard checks on the finished tree ----
        let runner = $"($stage)/($top)"
        if (do { ^sh -c 'test -x "$1"' sh $"($runner)/bin/eagle" } | complete).exit_code != 0 {
            error make { msg: "bin/eagle is missing or not executable" }
        }
        let providers = (open --raw $"($runner)/share/eagle/providers.json" | from json)
        if $providers.tracing != 1 {
            error make { msg: $"providers.json tracing is ($providers.tracing), expected 1" }
        }
        for p in [winrt dwrite com wait] {
            let archs = ($providers.profiles | get $p)
            if not ('32' in $archs) or not ('64' in $archs) {
                error make { msg: $"providers.json profile ($p) is ($archs), expected both 32 and 64" }
            }
        }
        if not ($"($runner)/share/wine/winmd/Windows.winmd" | path exists) {
            error make { msg: "share/wine/winmd/Windows.winmd is missing" }
        }

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
            eagle_source: { repo: 'bottles/soda', commit: $soda_ref }
            wine_sha: $sha
        } | to json | save --force $"($out_abs)/runner-info.json"

        $"eagle_source: bottles/soda ($soda_ref) \(($soda_url)\)\nwine: ($wine_repo) ($wine_ref) ($sha)\n" | save --force $"($out_abs)/EAGLE-SOURCE"

        ^git -C wine -c 'tar.tar.xz.command=xz -c' archive --format=tar.xz --prefix=$"($name)-source/" --output $"($out_abs)/($name)-source.tar.xz" $sha

        # Eagle source for the license obligation; yara itself is not vendored, only its revision is noted.
        let yara_rev = (open --raw $"($soda)/eagle/sources.json" | from json | get yara_revision)
        let yara_note = $"($stage)/YARA-REVISION.txt"
        $"yara is fetched by eagle/build-native.sh and not included here:\nhttps://github.com/VirusTotal/yara.git ($yara_rev)\nEagle source: bottles/soda ($soda_ref)\n" | save --force $yara_note
        ^git -C $soda -c 'tar.tar.xz.command=xz -c' archive --format=tar.xz --prefix=$"($name)-eagle-source/" $"--add-file=($yara_note)" --output $"($out_abs)/($name)-eagle-source.tar.xz" $soda_ref eagle .github/build-eagle.sh
    } catch {|e|
        rm --recursive --force $stage
        error make { msg: $e.msg }
    }
    rm --recursive --force $stage
    print $"wrote ($out_abs):"
    ls $out_abs | select name size | print
}
