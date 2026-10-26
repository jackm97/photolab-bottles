# Make the prefix report Windows 11 (build 26100) through the NT registry keys.
# Usage: nu scripts/prefix-winver.nu <prefix>
# Uses wine and wineserver from PATH.
def main [prefix: string] {
    let prefix = ($prefix | path expand)
    $env.WINEPREFIX = $prefix

    # Wine's own HKCU\Software\Wine\Version value overrides the NT keys;
    # ntdll only reads the NT keys when it is absent (dlls/ntdll/version.c
    # version_init). Deleting a value that is not there fails; ignore that.
    try { ^wine reg delete 'HKCU\Software\Wine' /v Version /f } catch { print 'Version value not present (ignored)' }

    let key = 'HKLM\Software\Microsoft\Windows NT\CurrentVersion'
    let values = [
        [name type data];
        [CurrentMajorVersionNumber REG_DWORD 10]
        [CurrentMinorVersionNumber REG_DWORD 0]
        [CurrentBuildNumber REG_SZ 26100]
        [CurrentBuild REG_SZ 26100]
        [CurrentVersion REG_SZ 6.3]
    ]
    for view in ['/reg:64' '/reg:32'] {
        for v in $values {
            ^wine reg add $key /v $v.name /t $v.type /d $v.data /f $view
        }
    }
    ^wineserver -w

    print '== wine cmd /c ver'
    ^wine cmd /c ver
    print '== wine C:\windows\syswow64\cmd.exe /c ver'
    ^wine 'C:\windows\syswow64\cmd.exe' /c ver
}
