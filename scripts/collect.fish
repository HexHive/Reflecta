#!/usr/bin/env fish

source (status dirname)/common.fish

function failed_runs
    for q in (ffd --no-ignore --type d '(queue|corpus)' $benchdir)
        set lsq (ls $q 2> /dev/null)
        if test -z "$lsq"
            echo (dirname $q)
            # rmdir (dirname $q)
        end
    end
end

function crashes
    mkdir -p $targetdir/crashes

    for c in (echo $benchdir/**/crashes/* | xargs -n 1)
        cp $c $targetdir/crashes
    end
end

function reduce
    set outdir $targetdir/reduced
    remkdir $outdir

    $targetdir/aflplusplus/afl-cmin \
        -C \
        -e \
        -i $targetdir/crashes \
        -o $outdir \
        -- $targetdir/ruby-aflplusplus/ruby

    for c in $outdir/*
        set name (basename $c)
        env AFL_DEBUG=1 AFL_MAP_SIZE=65536 \
            $targetdir/aflplusplus/afl-tmin \
                -e \
                -i $c \
                -o $outdir/$name,reduced \
                -- $targetdir/ruby-aflplusplus/ruby
    end
end

function builtins
    rg  -o \
        -tc \
        --no-filename \
        --no-line-number \
        'rb_define_[a-z0-9_]*\(.*\);' \
        $targetdir/ruby | tr -d ' ' | sort -u
end

function dump_builtins
    builtins | rg 'rb_define_[a-z_]*module\(' | cut -d, -f2 | rg -o '"(.*)"' | tr -d '"' | sort -u | tee $targetdir/modules.txt
    builtins | rg 'rb_define_[a-z_]*method\(' | cut -d, -f2 | rg -o '"(.*)"' | tr -d '"' | sort -u | tee $targetdir/methods.txt
    builtins | rg 'rb_define_[a-z_]*class\(' | rg -o '"(.*)"' | tr -d '"' | sort -u | tee $targetdir/classes.txt
end

function python_builtins
    set builtins (for l in (cat $workdir/python_builtins)
        string match -rq "\d(#(?<module>\w+))+#(?<fn>\w+)\.py.*" $l
        echo $module
        echo $fn
    end | sort -u)

    for b in $builtins
        printf "ctx.rule(u'BUILTIN', u'$b ')\n"
    end
end

function coverage
    if test -z "$argv"
        set benches $benchdir/bench:*reflecta*
    else
        set benches $argv
    end

    for b in (ls -dt $benches/)
        parse_bench_name $b
        echo $b
        if test -z "$queue" -o ! -d "$queue"
            echo "queue folder does not exists, skipping..."
            continue
        end

        if test -d $b/cov \
            -a -s $b/cov/coverage.csv \
            -a -s $b/cov/coverage_over_time.csv \
            echo "Coverage already collected for" (basename $b)
            continue
        end

        remkdir $b/cov
        remkdir /tmp/(basename $b)/covtmp

        cd /tmp

        ffd . --exclude '*.{protobuf,history}' $queue | xargs -P (nproc) -I "{}" $scriptdir/cov.fish run_coverage "'{}'"

        echo "Coverage replay finished!"

        $scriptdir/cov.fish merge_and_report $b

    end
end

function coverage_summary
    for b in (ls -dt $benchdir/bench:*)
        $scriptdir/cov.fish get_total $b
    end | rg branches
end

function bench_duration
    for b in (ls -dt $benchdir/bench:*)
        parse_bench_name $b

        set lsq (ls $queue 2> /dev/null)
        if test -z "$lsq"
            set duration 0
        else
            set first (ls -t $queue | tail -n 1)
            set last (ls -t $queue | head -n 1)
            set duration (math (get_full_time $queue/$last) - (get_full_time $queue/$first))
        end

        set days (math --scale=0 $duration / 86400)
        echo (basename $b) $days"d"(date -ud @$duration "+%Hh%Mm")
    end
end

function requires
    fdfind --maxdepth 1 '.*\.rb' /usr/lib/ruby/3.0.0 \
        | xargs -n 1 basename \
        | cut -d. -f1 \
        | sed 's/\(.*\)/require \'\1\'/' \
        > targets/requires.txt
end

function import_nautilus_mruby
    set benchdir /mnt/data/bench

    for b in ~/nautilus.mruby/nautilus/mruby/*
        set bench "baseline"
        set fuzzer "nautilus-imported"
        set target "ruby-imported"
        set date (date --iso-8601=seconds)

        set targetdir $benchdir/bench:$bench,fuzzer:$fuzzer,target:$target,date:$date

        echo $b "->" $targetdir
        cp -r $b $targetdir

        sleep 1
    end
end

function prune_input_name
    for i in $benchdir/*nautilus*/{outputs/queue,corpus}/*
        set old $i
        set new (echo $i | tr -d '()')

        if test $old != $new
            echo $old "->" $new
            mv $old $new
        end
    end
end

function branches
    objdump -D $argv | rg '\sl?j[a-z]+\s' | wc -l
end

eval $argv
