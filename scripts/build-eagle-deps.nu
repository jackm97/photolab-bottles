# Builds the static libraries Eagle's native helpers link against
# (eagle/build-analysis.sh: `g++ -static ... pkg-config --static json-c glib-2.0 sqlite3`)
# from pinned upstream source tarballs, never from distro packages or the host.
#
#   nu scripts/build-eagle-deps.nu --prefix <dir> --work <dir>
#
# Needs on PATH (package-runner.nu runs this inside a `pixi exec` environment
# from conda-forge): gcc, make, cmake, meson, ninja, pkg-config, tar plus
# xz/bzip2/gzip. Installs into <prefix>; to use it set
#   PKG_CONFIG_LIBDIR=<prefix>/lib/pkgconfig:<prefix>/share/pkgconfig
# <work> holds downloads and build trees and must not exist yet.

# name, url, sha256 of each pinned source tarball.
const sources = [
    {
        name: zlib
        url: 'https://github.com/madler/zlib/releases/download/v1.3.2/zlib-1.3.2.tar.xz'
        sha256: 'd7a0654783a4da529d1bb793b7ad9c3318020af77667bcae35f95d0e42a792f3'
    }
    {
        name: sqlite
        url: 'https://www.sqlite.org/2026/sqlite-autoconf-3540100.tar.gz'
        sha256: '926ef8d3eab93fbf6e06011901273eec076b25594a4e1cdadd50c987f4f6d64e'
    }
    {
        name: pcre2
        url: 'https://github.com/PCRE2Project/pcre2/releases/download/pcre2-10.49/pcre2-10.49.tar.bz2'
        sha256: '53c156e1ba416a20da8e65395daa132da0d80e76910424caca3fcdae7831d384'
    }
    {
        name: libffi
        url: 'https://github.com/libffi/libffi/releases/download/v3.8.0/libffi-3.8.0.tar.gz'
        sha256: '7da3e2d9a171eb0a038f592ecad3ff2bb2550f3496d87b3b29ad0cf4430c0db4'
    }
    {
        name: libiconv
        url: 'https://ftp.gnu.org/gnu/libiconv/libiconv-1.19.tar.gz'
        sha256: '88dd96a8c0464eca144fc791ae60cd31cd8ee78321e67397e25fc095c4a19aa6'
    }
    {
        name: json-c
        # 0.17 is what Soda's CI (ubuntu-24.04, libjson-c-dev 0.17-1build1) builds Eagle against;
        # json-c 0.19's linkhash.h trips Eagle's -Werror under C++.
        url: 'https://s3.amazonaws.com/json-c_releases/releases/json-c-0.17.tar.gz'
        sha256: '7550914d58fb63b2c3546f3ccfbe11f1c094147bd31a69dcd23714d7956159e6'
    }
    {
        name: glib
        url: 'https://download.gnome.org/sources/glib/2.90/glib-2.90.1.tar.xz'
        sha256: '93c941aa17d5eb1d53fe838365f29a8b4e539c222a256d974ec8f30fc413e396'
    }
]

# Downloads one source, verifies its sha256 and unpacks it into <work>/src/<name>;
# returns the unpacked directory.
def fetch-source [work: string, s: record] {
    let file = $"($work)/dl/($s.url | path basename)"
    http get --raw $s.url | save --force $file
    let actual = (open --raw $file | hash sha256)
    if $actual != $s.sha256 {
        error make { msg: $"($s.name): sha256 is ($actual), expected ($s.sha256)" }
    }
    let dir = $"($work)/src/($s.name)"
    mkdir $dir
    ^tar -xf $file -C $dir --strip-components=1
    $dir
}

# Autotools library: static only, PIC, libdir fixed to <prefix>/lib.
def autotools [src: string, name: string, extra: list<string>, prefix: string, work: string, jobs: string] {
    print $"== building ($name)"
    let b = $"($work)/build/($name)"
    mkdir $b
    let configure = $"($src)/configure"
    with-env { CFLAGS: '-O2 -fPIC' } {
        do {
            cd $b
            ^$configure $"--prefix=($prefix)" $"--libdir=($prefix)/lib" --disable-shared --enable-static ...$extra
            ^make $"-j($jobs)"
            ^make install
        }
    }
}

def main [
    --prefix: path
    --work: path
] {
    if ($prefix | is-empty) or ($work | is-empty) {
        error make { msg: "--prefix and --work are required" }
    }
    let prefix = ($prefix | path expand)
    let work = ($work | path expand)
    if ($work | path exists) {
        error make { msg: $"($work) already exists" }
    }
    mkdir $"($work)/dl" $"($work)/src" $"($work)/build" $prefix
    let jobs = (sys cpu | length | into string)
    let pc = $"($prefix)/lib/pkgconfig:($prefix)/share/pkgconfig"
    # Only the pinned prefix is searched, so nothing from the host leaks in.
    with-env { PKG_CONFIG_LIBDIR: $pc, PKG_CONFIG_PATH: $pc } {
        let src = ($sources | reduce --fold {} {|s, acc|
            print $"== fetching ($s.name)"
            $acc | insert $s.name (fetch-source $work $s)
        })

        print "== building zlib"
        do {
            cd ($src | get zlib)
            ^./configure $"--prefix=($prefix)" $"--libdir=($prefix)/lib" --static
            ^make $"-j($jobs)"
            ^make install
        }
        autotools ($src | get sqlite) sqlite [] $prefix $work $jobs
        autotools ($src | get pcre2) pcre2 [--disable-pcre2-16 --disable-pcre2-32 --disable-pcre2grep-libz --disable-pcre2grep-libbz2] $prefix $work $jobs
        # glib's pkg-config line names -liconv, so provide GNU libiconv (built before glib).
        autotools ($src | get libiconv) libiconv [] $prefix $work $jobs
        # Without --disable-multi-os-directory libffi installs into ${libdir}/../lib64 on x86_64
        # (toolexeclibdir) whatever --libdir says; with it toolexeclibdir equals libdir.
        autotools ($src | get libffi) libffi [--disable-docs --disable-multi-os-directory] $prefix $work $jobs

        print "== building json-c"
        ^cmake -S ($src | get json-c) -B $"($work)/build/json-c" -DCMAKE_BUILD_TYPE=Release $"-DCMAKE_INSTALL_PREFIX=($prefix)" -DCMAKE_INSTALL_LIBDIR=lib -DBUILD_SHARED_LIBS=OFF -DBUILD_STATIC_LIBS=ON -DBUILD_TESTING=OFF -DBUILD_APPS=OFF -DCMAKE_POSITION_INDEPENDENT_CODE=ON
        ^cmake --build $"($work)/build/json-c" $"-j($jobs)"
        ^cmake --install $"($work)/build/json-c"

        # glib: static, no tests, docs, introspection, translations or optional system integration.
        print "== building glib"
        ^meson setup $"($work)/build/glib" ($src | get glib) $"--prefix=($prefix)" --libdir=lib --buildtype=release --default-library=static --wrap-mode=nodownload -Dtests=false -Dintrospection=disabled -Ddocumentation=false -Dman-pages=disabled -Dnls=disabled -Dlibmount=disabled -Dselinux=disabled -Dxattr=false -Dsysprof=disabled -Dlibelf=disabled -Dglib_debug=disabled -Dc_args=-fPIC
        ^meson compile -C $"($work)/build/glib" $"-j($jobs)"
        ^meson install -C $"($work)/build/glib"

        # The one thing Eagle's build-analysis.sh asks for.
        ^pkg-config --static --exists json-c glib-2.0 sqlite3
        for a in [libz.a libsqlite3.a libpcre2-8.a libffi.a libjson-c.a libglib-2.0.a] {
            if not ($"($prefix)/lib/($a)" | path exists) {
                error make { msg: $"($a) was not installed into ($prefix)/lib" }
            }
        }
        print $"link line: (^pkg-config --static --libs json-c glib-2.0 sqlite3 | str trim)"

        # Smoke test: link a static program against all three exactly as Eagle's build-analysis.sh does.
        let smoke = $"($work)/smoke.c"
        '#include <glib.h>
#include <json-c/json.h>
#include <sqlite3.h>
int main(void) {
    char *s = g_strdup("x");
    json_object *o = json_object_new_object();
    const char *v = sqlite3_libversion();
    g_free(s);
    json_object_put(o);
    return v ? 0 : 1;
}
' | save --force $smoke
        let flags = (^pkg-config --static --cflags --libs glib-2.0 json-c sqlite3 | str trim | split row ' ' | where {|f| $f != '' })
        ^gcc -static $smoke ...$flags -o $"($work)/smoke"
        ^$"($work)/smoke"
    }
}
