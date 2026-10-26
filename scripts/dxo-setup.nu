# Run the DxO PhotoLab 9 installer in the prefix and collect its logs.
# Usage: nu scripts/dxo-setup.nu <prefix>
# Uses wine and wineserver from PATH. Logs go to build/logs/.
def main [prefix: string] {
    let prefix = ($prefix | path expand)
    $env.WINEPREFIX = $prefix
    let work = '/home/jack/photolab-work/dxo'
    let setup = ($work | path join DxO_PhotoLab9_Setup.exe)
    let logs = ($env.PWD | path join build logs)
    mkdir $work $logs

    if not ($setup | path exists) {
        cp /home/jack/Downloads/DxO_PhotoLab9_Setup.exe $work
    }

    # The installer's exit status is not an error for this script; the logs are the result.
    with-env {WINEDEBUG: '+loaddll'} {
        try { ^wine $setup o+e> ($logs | path join dxo-setup.log) } catch {|e| print $'installer exited nonzero: ($e.msg)' }
    }
    # Let msiexec finish.
    ^wineserver -w

    # The prefix user is not $env.USER (Proton-lineage Wine uses steamuser), so glob over users.
    let found = (glob ($prefix | path join drive_c users '*' AppData Local Temp 'photolab*_log.log'))
    for src in $found { cp $src $logs }
    print $'dxo-setup.log: ((($logs | path join dxo-setup.log) | path exists))'
    print $'installer logs found: ($found | str join ", ")'
}
