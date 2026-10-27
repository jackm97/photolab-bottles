# Launch DxO PhotoLab 9 in the prefix with loader tracing, then collect the app's own logs.
# Usage: nu scripts/dxo-run.nu <prefix> [--driver wayland|x11]
# --driver wayland (default): DISPLAY is hidden from wine so winex11 cannot initialise and Wine
#   falls back to winewayland (WAYLAND_DISPLAY is passed through). --driver x11 keeps the
#   environment as is. The driver choice is never written to the prefix registry.
# Uses wine and wineserver from PATH. The wine trace goes to build/logs/dxo-run.log;
# the app's logs are copied to build/logs/dxo-app/ (relative to <prefix>/drive_c/users/).
def main [prefix: string, --driver: string = 'wayland'] {
    if $driver not-in ['wayland' 'x11'] { error make {msg: $'--driver must be wayland or x11, got ($driver)'} }
    if $driver == 'wayland' and ($env.WAYLAND_DISPLAY? | default '' | is-empty) {
        error make {msg: 'WAYLAND_DISPLAY is not set; use --driver x11 outside a Wayland session'}
    }
    let prefix = ($prefix | path expand)
    $env.WINEPREFIX = $prefix
    let logs = ($env.PWD | path join build logs)
    let app_logs = ($logs | path join dxo-app)
    mkdir $logs
    let exe = 'C:\Program Files\DxO\DxO PhotoLab 9\DxO.PhotoLab.exe'

    # WINEDEBUG defaults to loader tracing; set DXO_WINEDEBUG to override it.
    let winedebug = ($env.DXO_WINEDEBUG? | default '+loaddll')

    # The app's exit status is not an error for this script; the logs are the result.
    with-env {WINEDEBUG: $winedebug} {
        if $driver == 'wayland' { hide-env --ignore-errors DISPLAY }
        try { ^wine $exe o+e> ($logs | path join dxo-run.log) } catch {|e| print $'wine exited nonzero: ($e.msg)' }
    }
    # The app can leave processes behind after its window closes; wait for them.
    ^wineserver -w

    # The prefix user is not $env.USER (Proton-lineage Wine uses steamuser), so glob over users.
    let users = ($prefix | path join drive_c users)
    let roots = [
        ($users | path join '*' AppData Local DxO '**' '*')
        ($users | path join '*' AppData Roaming DxO '**' '*')
    ]
    let found = ($roots | each {|g| glob $g --no-dir } | flatten | where {|f|
        let rel = ($f | path relative-to $users)
        let in_logs_dir = ($rel | path split | drop 1 | any {|c| ($c | str lowercase) == 'logs' })
        let name = ($f | path basename | str lowercase)
        $in_logs_dir or ($name | str ends-with '.log') or ($name | str ends-with '.txt')
    })

    mkdir $app_logs
    for src in $found {
        let dest = ($app_logs | path join ($src | path relative-to $users))
        mkdir ($dest | path dirname)
        cp $src $dest
    }
    print $'dxo-run.log: (($logs | path join dxo-run.log) | path exists)'
    print $'app logs collected: ($found | length)'
    $found | each {|f| print ($f | path relative-to $users) } | ignore
}
