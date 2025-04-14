#!/usr/bin/env fish

source (status dirname)/common.fish

function setup
    set -g input $argv[1]

    assert_set input

    set -g rundir $benchdir/(echo $input | rg -o 'bench:.*,fuzzer:.*,target:.*,date:[^/]*')
    set -g tmpdir /tmp/(basename $rundir)/covtmp

    set -g log $tmpdir/log
    set -g timestamp (get_full_time $input)

    parse_bench_name $rundir

    set -g bin (get_coverage_binary $target)

    assert_exists $rundir
    assert_exists $tmpdir
end

function get_coverage_binary
    switch $argv
    case ruby mruby micropython cpython php
        echo $targetdir/$argv-sancov/bin/$argv-driver
    case lua luau luajit
        echo (realpath $targetdir/$argv-sancov/bin/$argv)
    case 'ruby-*'
        echo $targetdir/ruby-sancov/bin/ruby-driver
    case v8
        echo $targetdir/v8/out/sancov/d8
    case '*'
        error 'coverage binary not found for' $argv
    end
end

function run_sancov
    set sancovdir $tmpdir/$timestamp.sancov

    mkdir -p $sancovdir

    assert_exists $bin
    assert_exists $sancovdir

    set -x UBSAN_OPTIONS "coverage=1,coverage_dir='$sancovdir'"
    if test "$target" != "v8"
        ulimit -v 2000000
    end

    if contains $target ruby mruby cpython micropython
        set tmpinp /tmp/(basename $input)
        sed 's|^//|#|' $input > $tmpinp
        set input $tmpinp
    end

    timeout -s KILL 1s $bin $input

    set binfile (basename $bin)
    set covfile (ls $sancovdir 2> /dev/null | rg -om 1 "$binfile.*.sancov")
    test -s $sancovdir/$covfile && sancov --print $sancovdir/$covfile > $tmpdir/$timestamp.sancov.csv
end

function run_coverage
    setup $argv

    run_sancov $input
end

function merge_llvm_cov
    pushd $tmpdir
    echo $tmpdir/*.profraw | tr ' ' '\n' | xargs -n 1 basename > $tmpdir/merge.txt
    llvm-profdata merge --input-files=$tmpdir/merge.txt -o $tmpdir/coverage.profdata
    llvm-cov export --format=text --skip-expansions --instr-profile=$tmpdir/coverage.profdata $bin > $covdir/coverage.json
    llvm-cov report --instr-profile=$tmpdir/coverage.profdata $bin | tee $covdir/coverage.txt
    popd
end

function merge_sancov
    set -g bin (get_coverage_binary $target)
    set -g binfile (basename $bin)

    echo $tmpdir
    ls $tmpdir
    fdfind --glob "$binfile*.sancov" $tmpdir

    symbolize (fdfind --glob "$binfile*.sancov" $tmpdir | head -n 1) $bin > $covdir/symbols.csv

    $scriptdir/merge.py $tmpdir
    cp $tmpdir/{coverage_over_time.csv,coverage.csv} $log $covdir/

    $scriptdir/plot.py --overtime (basename $rundir) --output $covdir/coverage_over_time.png
    $scriptdir/plot.py --treemap $tmpdir/coverage.csv --symbol $covdir/symbols.csv --output $covdir/treemap.html
end

function merge_and_report
    set -g rundir (realpath $argv[1])
    set -g tmpdir /tmp/(basename $rundir)/covtmp
    set -g covdir $rundir/cov

    echo $rundir

    parse_bench_name $rundir

    assert_exists $tmpdir
    assert_exists $covdir

    merge_sancov
end

function get_interesting
    set rundir $argv[1]
    set json $rundir/cov/coverage.json

    assert_exists $json
    parse_bench_name $rundir

    jq -r ".data[].files[]
        | { fuzzer: \"$fuzzer\", filename: .filename }
        + (.summary
            | to_entries[]
            | {
                type: .key,
                count: .value.count,
                covered: .value.covered,
                notcovered: (.value.count - .value.covered),
                percent: .value.percent
            })
        | select(.notcovered > 1000 and .percent < 50 and .type == \"regions\")
        | [.[]]
        | @csv" $json
end

function get_total
    set rundir $argv[1]
    set json $rundir/cov/coverage.json

    assert_exists $json
    parse_bench_name $rundir

    jq -r ".data[].totals
        | to_entries[]
        | {
            fuzzer: \"$fuzzer\",
            type: .key,
            count: .value.count,
            covered: .value.covered,
            notcovered: (.value.count - .value.covered),
            percent: .value.percent
        }
        | [.[]]
        | @csv" $json
end

function symbolize
    set input $argv[1]
    set target $argv[2]

    sancov --skip-dead-files=false --symbolize $input $target | \
        jq -r ".\"point-symbol-info\"
            | to_entries[]
            | {
                file: .key,
                t0: (.value
                | to_entries[]
                | {
                    fn: .key,
                    t1: (.value | to_entries[] | {pc: .key, line: .value})
                })
            }
            | {
                file,
                fn: .t0.fn,
                pc: .t0.t1.pc,
                line: .t0.t1.line
            }
            | [.[]]
            | @csv"
end

eval $argv
