# Create the Wine prefix if needed and install the runtime dependencies with winetricks.
# Usage: nu scripts/prefix-deps.nu <prefix>
# Uses wine, wineserver and winetricks from PATH.
def main [prefix: string] {
    let prefix = ($prefix | path expand)
    $env.WINEPREFIX = $prefix

    if not ($prefix | path join system.reg | path exists) {
        print $'creating prefix ($prefix)'
        ^wine wineboot -i
        ^wineserver -w
    }

    let verbs = [dotnet48 vcrun2022 d3dcompiler_47 corefonts]
    # Capture winetricks output so an unknown verb can be reported clearly; the
    # output is still printed.
    let result = (^winetricks -q ...$verbs o+e>| tee { print } | collect)
    # WineHQ bug 41727: without OnlyUseLatestCLR, .NET 4's shim in the unmanaged rundll32 that runs wine.inf looks for CLR 2 and pops up "This application could not be started" on every prefix update.
    ^wine reg add 'HKLM\Software\Microsoft\.NETFramework' /v OnlyUseLatestCLR /t REG_DWORD /d 1 /f /reg:64
    ^wine reg add 'HKLM\Software\Microsoft\.NETFramework' /v OnlyUseLatestCLR /t REG_DWORD /d 1 /f /reg:32
    ^wineserver -w
    if ($result =~ '(?i)unknown arg|unknown verb|not a valid verb|unknown option') {
        error make {msg: $'winetricks rejected a verb as unknown:(char nl)($result | lines | where {|l| $l =~ "(?i)unknown|not a valid" } | str join (char nl))'}
    }
}
