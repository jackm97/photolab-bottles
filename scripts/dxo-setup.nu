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

    let temp = ($prefix | path join drive_c users $env.USER AppData Local Temp)
    let wanted = [photolab_install_log.log photolab_installer_bootstrap_log.log]
    mut found = []
    for n in $wanted {
        let src = ($temp | path join $n)
        if ($src | path exists) {
            cp $src $logs
            $found = ($found | append $n)
        }
    }
    print $'dxo-setup.log: ((($logs | path join dxo-setup.log) | path exists))'
    print $'installer logs found: ($found | str join ", ")'
    print $'installer logs missing: ($wanted | where {|n| not ($n in $found) } | str join ", ")'
}
