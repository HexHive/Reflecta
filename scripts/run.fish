#!/usr/bin/env fish

source (status dirname)/common.fish

function setup
    assert test -n "$argv[1]"
    assert test -n "$argv[2]"

    if test -z "$bench"
        echo '$bench not set, using debug'
        set -g bench "debug"
        set -g prefix "/tmp"
    else
        set -g prefix "$benchdir"
    end

    set_default duration 23h

    set -g fuzzer $argv[1]
    set -g target $argv[2]
    set -g start (date --iso-8601=seconds)
    set -g folder "bench:$bench,fuzzer:$fuzzer,target:$target,date:$start"
    set -g output "/tmp/$folder"

    set -g fuzzerdir $targetdir/$fuzzer

    remkdir $output

    pushd /tmp
end

function finish
    if test "$prefix" != "/tmp"
        echo "copying /tmp to $prefix..."
        rm -rf $prefix/$folder
        cp -rp $output $prefix/$folder

        echo "collecting coverage..."
        $scriptdir/collect.fish coverage $prefix/$folder
    end
end

function nautilus
    setup "nautilus" "$argv[1]"

    switch $target
    case ruby
        set grammar $fuzzerdir/grammars/ruby_custom.py
        set driver $targetdir/ruby-afl/bin/ruby-driver
    case mruby
        set grammar $fuzzerdir/grammars/ruby_custom.py
        set driver $targetdir/mruby-afl/bin/mruby-driver
    case php
        set grammar $fuzzerdir/grammars/php_custom.py
        set driver $targetdir/php-afl/bin/php
    case cpython
        set grammar $fuzzerdir/grammars/python_custom.py
        set driver $targetdir/cpython-afl/bin/cpython-driver
    case micropython
        set grammar $fuzzerdir/grammars/python_custom.py
        set driver $targetdir/micropython-afl/bin/micropython-driver
    case v8
        set grammar $fuzzerdir/grammars/javascript_new.py
        set driver $targetdir/v8/out/libfuzzer/d8
    case '*'
        error "unsupported target for $fuzzer: $target"
    end

    assert_exists $grammar
    assert_exists $driver

    timeout --foreground --signal=SIGINT $duration \
    $fuzzerdir/target/release/fuzzer \
        -c $fuzzerdir/config.ron \
        -g $grammar \
        -o $output -- \
        $driver

    finish
end

function polyglot
    setup "polyglot" "$argv[1]"

    afl_ignore_issues

    switch $target
    case php
        set mutator $fuzzerdir/build/php/libpolyglot_mutator.so
        set driver $targetdir/php-afl/bin/php
    case ruby
        set mutator $fuzzerdir/build/ruby/libpolyglot_mutator.so
        set driver $targetdir/ruby-afl/bin/ruby-driver
    case mruby
        set mutator $fuzzerdir/build/ruby/libpolyglot_mutator.so
        set driver $targetdir/mruby-afl/bin/mruby-driver
    case cpython
        set mutator $fuzzerdir/build/python/libpolyglot_mutator.so
        set driver $targetdir/cpython-afl/bin/cpython-driver
    case micropython
        set mutator $fuzzerdir/build/python/libpolyglot_mutator.so
        set driver $targetdir/micropython-afl/bin/micropython-driver
    case v8
        set mutator $fuzzerdir/build/js/libpolyglot_mutator.so
        set driver $targetdir/v8/out/libfuzzer/d8
    case '*'
        error "unsupported target for $fuzzer: $target"
    end

    set corpus $targetdir/corpus
    sed "s|CORPUS|$corpus|"  $workdir/scripts/semantic.yml > /tmp/semantic.yml

    set -x POLYGLOT_CONFIG /tmp/semantic.yml
    set -x AFL_NO_UI 1
    set -x AFL_DISABLE_TRIM 1
    set -x AFL_CUSTOM_MUTATOR_ONLY 1
    set -x AFL_CUSTOM_MUTATOR_LIBRARY $mutator

    timeout --foreground --signal=SIGKILL $duration \
    $targetdir/aflplusplus/afl-fuzz -m none -i $corpus -o $output -- \
        $driver

    finish
end

function polyglot-corpus
    setup "polyglot-corpus" "$argv[1]"

    afl_ignore_issues

    switch $target
    case php
        set mutator $targetdir/polyglot/build/php/libpolyglot_mutator.so
        set corpus $targetdir/polyglot/grammars/php/corpus
        set driver $targetdir/php-afl/bin/php
    case '*'
        error "unsupported target for $fuzzer: $target"
    end

    sed "s|CORPUS|$corpus|"  $workdir/scripts/semantic.yml > /tmp/semantic.yml

    set -x POLYGLOT_CONFIG /tmp/semantic.yml
    set -x AFL_NO_UI 1
    set -x AFL_DISABLE_TRIM 1
    set -x AFL_CUSTOM_MUTATOR_ONLY 1
    set -x AFL_CUSTOM_MUTATOR_LIBRARY $mutator

    timeout --foreground --signal=SIGKILL $duration \
    $targetdir/aflplusplus/afl-fuzz -m none -i $corpus -o $output -- \
        $driver

    finish
end



function reflecta
    setup reflecta-(get_revision $workdir/reflecta) "$argv[1]"

    set build "debug"
    set inspect "--inspect"
    set loglevel "verbose"

    switch $target
    case v8
        set profile "v8r"
        set driver $targetdir/v8/out/fuzzbuild/d8
    case ruby
        set profile "ruby"
        set driver $targetdir/ruby-reflecta/bin/ruby-driver
    case mruby
        set profile "ruby"
        set driver $targetdir/mruby-reflecta/bin/mruby-driver
    case cpython
        set profile "python"
        set driver $targetdir/cpython-reflecta/bin/cpython-driver
    case micropython
        set profile "python"
        set driver $targetdir/micropython-reflecta/bin/micropython-driver
    case php
        set profile "php"
        set driver $targetdir/php-reflecta/bin/php-driver
    case '*'
        error "unsupported target for $fuzzer: $target"
    end

    swift build \
        -c $build \
        --scratch-path /tmp/reflecta.build \
        --package-path $workdir/reflecta

    timeout --foreground --signal=SIGINT $duration \
    swift run \
        -c $build \
        --scratch-path /tmp/reflecta.build \
        --package-path $workdir/reflecta \
        FuzzilliCli $inspect \
        --minCorpusSize=100000 \
        --maxCorpusSize=200000 \
        --logLevel=$loglevel \
        --exportStatistics \
        --profile=$profile \
        --storagePath=$output \
        $driver

    finish
end




function fuzzilli
    setup fuzzilli "$argv[1]"

    switch $target
    case v8
        set profile "v8"
        set driver $targetdir/v8/out/fuzzbuild/d8
    case *
        error "unsupported target for $fuzzer: $target"
    end

    swift build \
        -c debug \
        --scratch-path /tmp/fuzzilli.build \
        --package-path $targetdir/fuzzilli

    timeout --foreground --signal=SIGINT $duration \
    swift run \
        -c debug \
        --scratch-path /tmp/fuzzilli.build \
        --package-path $targetdir/fuzzilli \
        FuzzilliCli \
        --minCorpusSize=10000 \
        --maxCorpusSize=100000 \
        --logLevel=verbose \
        --exportStatistics \
        --profile=$profile \
        --storagePath=$output \
        $driver

    finish
end

eval $argv
