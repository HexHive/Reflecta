set scriptdir (realpath (status dirname))
set workdir (dirname $scriptdir)
set benchdir $workdir/bench
set driverdir $workdir/drivers
set supportdir $workdir/support
set targetdir $workdir/targets

if not test -d $targetdir
    ln -s /targets/ $targetdir
end

function error
    echo $argv 1>&2
    exit 1
end

function get_full_time
    ls --full-time --time-style='+%s.%N' $argv | cut -d' ' -f6
end

function assert
    if not $argv
        error "assertion failed: $argv"
    end
end

function assert_set
    if test -z "$$argv"
        error "assertion failed: \$$argv is not set!"
    end
end

function set_default
    if test -z "$$argv[1]"
        set -g $argv[1] $argv[2]
        echo "\$$argv[1] is not set, using default value $argv[2]!"
    end
end

function assert_exists
    assert test -e "$argv"
end

function require
    if not command -q $argv
        error "$argv not found"
    end
end

function remkdir
    rm -rf $argv
    mkdir -p $argv
end

function ffd
    if command -q fd
        fd $argv
    else if command -q fdfind
        fdfind $argv
    else
        error "fd or fdfind not found"
    end
end

function get_revision
    assert_exists $argv

    git config --global --add safe.directory $workdir

    set githash (git -C $argv rev-parse --short HEAD)
    set gittag (git -C $argv tag --points-at HEAD)

    echo $githash
end

function parse_bench_name
    assert_exists $argv

    for item in (string split ',' (basename $argv))
        set pair (string split ':' $item)
        set -g $pair[1] $pair[2]
    end

    if test -d $argv/corpus
        set -g queue $argv/corpus
    else if test -d $argv/queue
        set -g queue $argv/queue
    else if test -d $argv/outputs/queue
        set -g queue $argv/outputs/queue
    else if test -d $argv/default/queue
        set -g queue $argv/default/queue
    else
        echo $argv
        echo "no corpus or queue directory found"
    end
end

function afl_ignore_issues
    set -gx AFL_NO_AFFINITY 1
    set -gx AFL_SKIP_CRASHES 1
    set -gx AFL_SKIP_CPUFREQ 1
    set -gx AFL_IGNORE_PROBLEMS 1
    set -gx AFL_NO_WARN_INSTABILITY 1
    set -gx AFL_I_DONT_CARE_ABOUT_MISSING_CRASHES 1
end
