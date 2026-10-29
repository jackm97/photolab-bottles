# Builds the Bottles catalog and force-pushes it as one commit to the orphan
# branch `catalog` of jackm97/photolab-bottles. Run from the repository root
# with GH_TOKEN set. Inputs come from the environment (set by catalog-sync.yml):
#   COMPONENTS_REF, DEPENDENCIES_REF (default main), RUNNER_TAG (optional).

const repo = 'jackm97/photolab-bottles'
const installer_url = 'https://download.visualstudio.microsoft.com/download/pr/7afca223-55d2-470a-8edc-6a1739ae3252/abd170b4b0ec15ad0222a809b761a036/ndp48-x86-x64-allos-enu.exe'
const installer_sha256 = '95889d6de3f2070c07790ad6cf2000d33d9a1bdfc6a381725ab82ab1c314fd53'
const winrt_cab = 'x64-Windows10.0-KB4486153-x64.cab'

# Reads index.yml under root and checks each entry has a manifest.
def check-index [root: string, label: string] {
    let idx = (open --raw $"($root)/index.yml" | from yaml)
    $idx | transpose name entry | each {|r|
        let sub = ($r.entry | get -o 'Sub-category')
        let p = if $sub == null {
            $"($root)/($r.entry.Category)/($r.name).yml"
        } else {
            $"($root)/($r.entry.Category)/($sub)/($r.name).yml"
        }
        if not ($p | path exists) {
            error make { msg: $"($label): index entry ($r.name) has no manifest at ($p)" }
        }
    } | ignore
    $idx
}

# Downloads and unpacks a bottlesdevs repository at ref into dest; returns the SHA.
def mirror [name: string, ref: string, tmp: string, dest: string] {
    let sha = (^gh api $"repos/bottlesdevs/($name)/commits/($ref)" --jq .sha | str trim)
    ^gh api $"repos/bottlesdevs/($name)/tarball/($sha)" | save --raw $"($tmp)/($name).tar.gz"
    let unpacked = $"($tmp)/($name)"
    mkdir $unpacked
    ^tar -xzf $"($tmp)/($name).tar.gz" -C $unpacked
    let wrappers = (ls $unpacked | where type == dir)
    if ($wrappers | length) != 1 {
        error make { msg: $"($name) tarball has ($wrappers | length) top-level directories, expected 1" }
    }
    mkdir $dest
    # Hidden entries (.github and the like) are left out of the mirror.
    cp -r ...(glob $"($wrappers.0.name)/*" | where {|p| not ($p | path basename | str starts-with '.') }) $dest
    $sha
}

# Finds exactly one directory under root whose name matches pattern.
def one-dir [root: string, pattern: string] {
    let hits = (ls $root | where type == dir | get name | path basename | where {|n| $n =~ $pattern })
    if ($hits | length) != 1 {
        error make { msg: $"expected exactly one directory matching ($pattern) under ($root), found ($hits)" }
    }
    $hits | first
}

# Environment variable value, or the fallback when unset or empty.
def env-or [name: string, fallback: string] {
    let v = ($env | get -o $name | default '')
    if ($v | is-empty) { $fallback } else { $v }
}

def sync-catalog [tmp: string] {
    let components_ref = (env-or COMPONENTS_REF main)
    let dependencies_ref = (env-or DEPENDENCIES_REF main)
    let runner_tag = (env-or RUNNER_TAG '')
    let catalog = $"($tmp)/catalog"
    let comp = $"($catalog)/components"
    let deps = $"($catalog)/dependencies"

    # 1. Upstream mirrors.
    let comp_sha = (mirror components $components_ref $tmp $comp)
    let deps_sha = (mirror dependencies $dependencies_ref $tmp $deps)
    print $"components bottlesdevs/components ($comp_sha)"
    print $"dependencies bottlesdevs/dependencies ($deps_sha)"

    # 2. Our runners.
    let tags = (^gh release list --repo $repo --limit 1000 --json tagName | from json | get tagName
        | where {|t| $t | str starts-with 'photolab-wine-' })
    if ($runner_tag | is-not-empty) and ($runner_tag not-in $tags) {
        error make { msg: $"no release with tag ($runner_tag)" }
    }
    mkdir $"($comp)/runners/wine"
    mut comp_index = (open --raw $"($comp)/index.yml" | from yaml)
    for tag in $tags {
        let dl = $"($tmp)/ri/($tag)"
        mkdir $dl
        let r = (^gh release download $tag --repo $repo --pattern runner-info.json --dir $dl | complete)
        if $r.exit_code != 0 or not ($"($dl)/runner-info.json" | path exists) {
            error make { msg: $"release ($tag) has no readable runner-info.json: ($r.stderr)" }
        }
        let info = (open --raw $"($dl)/runner-info.json" | from json)
        {
            Name: $tag
            Provider: jackm97
            Maintainer: CI
            Channel: stable
            File: [{
                file_name: $info.file_name
                rename: $info.file_name
                url: $info.url
                file_checksum: $info.md5
                file_size: $info.size
                architecture: x86_64
                platform: linux
            }]
        } | to yaml | save --force $"($comp)/runners/wine/($tag).yml"
        $comp_index = ($comp_index | upsert $tag {
            Category: runners
            'Sub-category': wine
            Channel: stable
            Date: ($info.date | into string)
            Platforms: [linux]
            Architectures: [x86_64]
        })
    }
    $comp_index | to yaml | save --force $"($comp)/index.yml"

    # 3. Our dependency, with the installer-derived values filled in.
    let exe = $"($tmp)/ndp48.exe"
    http get --raw $installer_url | save --raw $exe
    let sha256 = (open --raw $exe | hash sha256)
    if $sha256 != $installer_sha256 {
        error make { msg: $"installer SHA-256 is ($sha256), expected ($installer_sha256)" }
    }
    let md5 = (open --raw $exe | hash md5)

    let x = (^7z e -y $"-o($tmp)/exe" $exe $winrt_cab | complete)
    if $x.exit_code >= 2 {
        error make { msg: $"7z failed with ($x.exit_code): ($x.stderr)" }
    }
    let c = (^cabextract -d $"($tmp)/cab" -F '*system.runtime.windowsruntime*' $"($tmp)/exe/($winrt_cab)" | complete)
    if $c.exit_code != 0 {
        error make { msg: $"cabextract failed with ($c.exit_code): ($c.stderr)" }
    }
    let winrt_dir = (one-dir $"($tmp)/cab" '(?i)^msil_system\.runtime\.windowsruntime_b77a5c561934e089_4\.0\.15744\.161_')
    let xaml_dir = (one-dir $"($tmp)/cab" '(?i)^msil_system\.runtime\.windowsruntime\.ui\.xaml_b77a5c561934e089_4\.0\.15744\.161_')

    mkdir $"($deps)/Essentials"
    open --raw $"($env.PWD)/bottles/dependencies/Essentials/netfx48-winrt.yml"
        | str replace --all '__MD5__' $md5
        | str replace --all '__WINRT_DIR__' $winrt_dir
        | str replace --all '__XAML_DIR__' $xaml_dir
        | save --force $"($deps)/Essentials/netfx48-winrt.yml"
    open --raw $"($deps)/index.yml" | from yaml
        | upsert netfx48-winrt {
            Description: '.NET Framework 4.8 Windows Runtime interop assemblies (System.Runtime.WindowsRuntime, .UI.Xaml)'
            Category: Essentials
        }
        | to yaml | save --force $"($deps)/index.yml"

    # 4. Validate.
    let ci = (check-index $comp 'components')
    let di = (check-index $deps 'dependencies')
    for k in [dxvk-3.1.1 vkd3d-proton-3.0.1] {
        if $k not-in ($ci | columns) { error make { msg: $"components index lacks ($k)" } }
    }
    for k in [dotnet48 vcredist2022 d3dcompiler_47 allfonts] {
        if $k not-in ($di | columns) { error make { msg: $"dependencies index lacks ($k)" } }
    }

    # 5. Provenance.
    $"components bottlesdevs/components ($comp_sha)\ndependencies bottlesdevs/dependencies ($deps_sha)\n"
        | save --force $"($catalog)/MIRROR.txt"

    # 6. Publish: a fresh repository holding only the catalog tree.
    ^git -C $catalog init --quiet --initial-branch=catalog
    ^git -C $catalog add -A
    ^git -C $catalog -c user.name=Jack -c user.email=jack@myersjack.dev commit --quiet -m $"catalog: mirror components ($comp_sha | str substring 0..6), dependencies ($deps_sha | str substring 0..6)"
    let head = (^git -C $catalog rev-parse HEAD | str trim)
    let url = $"https://x-access-token:($env.GH_TOKEN)@github.com/($repo).git"
    let p = (^git -C $catalog push --force $url HEAD:refs/heads/catalog | complete)
    if $p.exit_code != 0 {
        error make { msg: ($"push failed: ($p.stderr)" | str replace --all $env.GH_TOKEN '***') }
    }
    print $"catalog branch commit: ($head)"
    if ($env.GITHUB_STEP_SUMMARY? | is-not-empty) {
        $"catalog branch commit: ($head)\n" | save --append $env.GITHUB_STEP_SUMMARY
    }
}

def main [] {
    let tmp = (^mktemp --directory --tmpdir catalog-sync.XXXXXX | str trim)
    try {
        sync-catalog $tmp
    } catch {|e|
        rm --recursive --force $tmp
        error make { msg: $e.msg }
    }
    rm --recursive --force $tmp
}
