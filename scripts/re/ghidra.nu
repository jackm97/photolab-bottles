# Fetches NSA's pinned Ghidra release into build/tools/, verifying its SHA-256.
# Run from the repository root (pixi tasks do): pixi run -e re re-ghidra
const NAME = 'ghidra_12.1.3_PUBLIC'
const URL = 'https://github.com/NationalSecurityAgency/ghidra/releases/download/Ghidra_12.1.3_build/ghidra_12.1.3_PUBLIC_20260817.zip'
const SHA256 = '93a5d11a9ad510622acaaf908c556a7b9b764d338e78a7567f3689bf5081fd54'

let tools = 'build/tools'
let headless = $'($tools)/($NAME)/support/analyzeHeadless'
if ($headless | path exists) {
    print $'($headless) already exists, nothing to do.'
    exit 0
}

mkdir $tools
let zip = $'($tools)/($NAME)_20260817.zip'

print $'downloading ($URL)'
# --raw keeps the body as bytes; the stream goes straight to disk.
http get --raw --max-time 30min $URL | save --force --raw $zip

let got = (open --raw $zip | hash sha256)
if $got != $SHA256 {
    rm --force $zip
    error make {msg: $'SHA-256 mismatch for ($zip): expected ($SHA256), got ($got); zip deleted'}
}
print $'sha256 ok: ($got)'

# 7z exits 1 for warnings only; anything else is a failure.
^7z x -y $'-o($tools)' $zip
rm --force $zip

if not ($headless | path exists) {
    error make {msg: $'extraction finished but ($headless) is missing'}
}
print $'ready: ($headless)'
