# Unattended diagnosis wrapper around the dxo-run task (dxo-run.nu itself is unchanged).
# Usage: nu scripts/dxo-probe.nu [--deadline <sec>] [--channels <WINEDEBUG string>] [--probe 30,50]
#   --deadline  hard deadline in seconds after launch (default 90); wineserver -k at the deadline
#   --channels  passed to the task as DXO_WINEDEBUG (default: unset, so dxo-run.nu uses +loaddll)
#   --probe     comma-separated seconds after launch at which winedbg prints info wnd and bt all
#               (a string, because `nu script.nu` cannot take a list flag from the command line)
# Uses the absolute pixi tool paths and the default prefix .prefixes/dxo. Writes no files itself;
# dxo-run.nu still writes build/logs/dxo-run.log and build/logs/dxo-app/.
# Mailbox tags used: 1 = task finished, 2 = sampler table, 9 = sampler stop, 100+ = bounded calls.

const root = '/home/jack/Projects/photolab-bottles'
const pfx = '/home/jack/Projects/photolab-bottles/.prefixes/dxo'
const bindir = '/home/jack/Projects/photolab-bottles/.pixi/envs/default/bin'
const names = '(?i)^(DxO.*\.exe|wine.*|winedevice.*|wineserver.*)$'

def stamp [] { date now | format date '%Y-%m-%d %H:%M:%S%.3f' }

# Run a closure in a job and wait at most `secs` for its result; a hung call is killed, not waited on.
def bounded [tag: int, secs: int, body: closure] {
    let id = (job spawn {
        let r = (try { do $body } catch {|e| {error: $e.msg} })
        $r | job send 0 --tag $tag
    })
    try {
        job recv --tag $tag --timeout ($secs * 1sec)
    } catch {
        try { job kill $id }
        {error: $'timed out after ($secs) s'}
    }
}

# wineserver -k for the prefix, bounded to 30 s; prints the error if it did not finish cleanly.
def kill-server [tag: int] {
    let r = (bounded $tag 30 {|| with-env {WINEPREFIX: $pfx} { try { ^($bindir | path join wineserver) -k } catch { } } })
    if ($r | describe | str starts-with 'record') and ($r.error? != null) { print $'wineserver -k: ($r.error)' }
}

# One winedbg call, bounded to 30 s; prints output or the error and always returns.
def dbg-call [tag: int, label: string, cmd: string] {
    let r = (bounded $tag 30 {|| with-env {WINEPREFIX: $pfx} { ^($bindir | path join winedbg) --command $cmd o+e>| collect } })
    if ($r | describe | str starts-with 'record') {
        print $'winedbg call failed: ($label): ($r.error? | default "unknown")'
        null
    } else {
        $r | default ''
    }
}

def run-probe [t: int, n: int] {
    print $'=== probe at ($t) s after launch, wall clock (stamp)'
    let procs = (dbg-call (100 + $n * 10) 'info proc' 'info proc')
    if $procs == null { return }
    let line = ($procs | lines | where {|l| $l =~ "DxO\\.PhotoLab\\.exe'" } | where {|l| $l !~ '\\_' } | get -o 0)
    if $line == null { print 'no DxO.PhotoLab.exe line in info proc; probe skipped'; return }
    print $'info proc line: ($line)'
    let pid = ($line | parse --regex '^[ =]*(?<pid>[0-9a-fA-F]+)\s' | get -o 0.pid)
    print '--- info wnd'
    let w = (dbg-call (101 + $n * 10) 'info wnd' 'info wnd')
    if $w != null { print $w }
    print '--- bt all'
    let script = $"attach 0x($pid)(char nl)bt all(char nl)detach"
    let bt = (dbg-call (102 + $n * 10) 'attach + bt all' $script)
    if $bt != null { print $bt }
}

def main [--deadline: int = 90, --channels: string = '', --probe: string = ''] {
    cd $root
    let probe = if ($probe | is-empty) { [] } else { $probe | split row ',' | each {|s| $s | str trim | into int } }
    kill-server 50

    # Memory sampler: every 5 s, RSS of the matching processes; prints nothing until the end.
    let started = (date now)
    let sampler = (job spawn {
        mut rows = []
        mut go = true
        while $go {
            let t = ((date now) - $started | into int) / 1_000_000_000
            $rows = ($rows | append (ps | where name =~ $names | each {|p| {t: $t, pid: $p.pid, name: $p.name, mem: $p.mem} }))
            try { job recv --tag 9 --timeout 5sec; $go = false } catch { }
        }
        $rows | job send 0 --tag 2
    })

    print $'launch wall clock: (stamp)'
    let launch = (date now)
    let task = (job spawn {
        cd $root
        let ch = $channels
        if ($ch | is-empty) {
            try { pixi run --as-is dxo-run } catch {|e| print $'dxo-run: ($e.msg)' }
        } else {
            with-env {DXO_WINEDEBUG: $ch} { try { pixi run --as-is dxo-run } catch {|e| print $'dxo-run: ($e.msg)' } }
        }
        'done' | job send 0 --tag 1
    })

    mut finished = false
    mut n = 0
    for t in ($probe | sort) {
        if $finished or $t >= $deadline { continue }
        let wait = ($t * 1sec) - ((date now) - $launch)
        if $wait > 0sec {
            try { job recv --tag 1 --timeout $wait; $finished = true } catch { }
        }
        if not $finished { run-probe $t $n; $n = $n + 1 }
    }
    if not $finished {
        let wait = ($deadline * 1sec) - ((date now) - $launch)
        if $wait > 0sec {
            try { job recv --tag 1 --timeout $wait; $finished = true } catch { }
        }
    }
    let alive = (not $finished)
    print $'deadline reached, task still running: ($alive), wall clock (stamp)'
    if $alive {
        kill-server 51
        # dxo-run.nu returns after wineserver -w; give it 30 s to copy logs, then kill the job.
        try { job recv --tag 1 --timeout 30sec } catch { print 'task did not return 30 s after wineserver -k; killing its job'; try { job kill $task } }
    }
    kill-server 52

    'stop' | job send $sampler --tag 9
    print '=== memory samples, RSS per sample: seconds after launch, total, top 3 processes'
    let rows = (try { job recv --tag 2 --timeout 30sec } catch { print 'sampler did not report'; [] })
    if ($rows | is-not-empty) {
        $rows | group-by t | items {|t, g|
            let top = ($g | sort-by mem --reverse | first 3 | each {|p| $p.name + ' ' + ($p.pid | into string) + ' ' + ($p.mem | into string) } | str join '; ')
            {t: ($t | into int), total: ($g | get mem | math sum), top: $top}
        } | sort-by t | print
    }

    # Verdict, from the files dxo-run.nu wrote.
    print '=== verdict'
    let log = ($root | path join build logs dxo-run.log)
    let tl = if ($log | path exists) { open --raw $log | lines } else { [] }
    print $'trace log exists: (($log | path exists)) lines: ($tl | length)'
    print $'Protocol error count: ($tl | where {|l| $l | str contains "Protocol error" } | length)'
    print $'job still alive at deadline: ($alive)'
    print $'DxO.PhotoLab.exe loaded: ($tl | any {|l| $l =~ "Loaded L\".*DxO\\.PhotoLab\\.exe\"" })'
    let logdir = ($pfx | path join drive_c users jack AppData Local DxO 'DxO PhotoLab 9' Logs)
    for f in (glob ($logdir | path join '*.txt')) {
        let lines = (open --raw $f | lines)
        let marks = ($lines | enumerate | where {|r| $r.item | str contains "Initializing service 'ServiceLocator' (init order = 0)" } | get index)
        let run = if ($marks | is-empty) { $lines } else { $lines | skip ($marks | last) }
        print $'--- ($f | path basename): run section starts at line ($marks | last | default 0)'
        if ($f | path basename) == 'DxO.PhotoLab.txt' {
            print $'[Licensing] HardwareID: ($run | any {|l| $l | str contains "[Licensing] HardwareID" })'
            let dep = "Initializing service 'DependenciesService' (init order = 20)"
            print $'DependenciesService init: ($run | any {|l| $l | str contains $dep })'
        }
        print 'last 30 lines:'
        $run | last 30 | each {|l| print $l } | ignore
    }
}
