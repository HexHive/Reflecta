#!/usr/bin/env fish

source (status dirname)/common.fish

function aflplusplus-fuzzer
    pushd $targetdir/aflplusplus

    git clean -fdx
    make source-only NO_NYX=1 -j

    popd
end

function polyglot-fuzzer
    # git clone https://github.com/OMH4ck/PolyGlot
    # git submodule update --init
    pushd $targetdir/polyglot

    git clean -fdx

    conan profile detect

    env NO_NYX=1 make -j -C AFLplusplus source-only

    set polyglotdir $targetdir/polyglot

    cmake \
        -S $polyglotdir \
        -B $polyglotdir/build/php \
        -G Ninja \
        -DBUILD_TESTING=OFF \
        -DCMAKE_BUILD_TYPE=Release \
        -DPARSER_FILE=$polyglotdir/grammars/php/PhpParser.g4 \
        -DLEXER_FILE=$polyglotdir/grammars/php/PhpLexer.g4 \
        -DGRAMMAR_HELPER_DIR=$polyglotdir/grammars/php

    ninja -C ./build/php

    cmake \
        -S $polyglotdir \
        -B $polyglotdir/build/js \
        -G Ninja \
        -DBUILD_TESTING=OFF \
        -DCMAKE_BUILD_TYPE=Release \
        -DPARSER_FILE=$polyglotdir/grammars/js/JavaScriptParser.g4 \
        -DLEXER_FILE=$polyglotdir/grammars/js/JavaScriptLexer.g4 \
        -DGRAMMAR_HELPER_DIR=$polyglotdir/grammars/js

    ninja -C ./build/js

    cmake \
        -S $polyglotdir \
        -B $polyglotdir/build/python \
        -G Ninja \
        -DBUILD_TESTING=OFF \
        -DCMAKE_BUILD_TYPE=Release \
        -DPARSER_FILE=$polyglotdir/grammars/python/Python3Parser.g4 \
        -DLEXER_FILE=$polyglotdir/grammars/python/Python3Lexer.g4 \
        -DGRAMMAR_HELPER_DIR=$polyglotdir/grammars/python

    ninja -C ./build/python

    cmake \
        -S $polyglotdir \
        -B $polyglotdir/build/ruby \
        -G Ninja \
        -DBUILD_TESTING=OFF \
        -DCMAKE_BUILD_TYPE=Release \
        -DGRAMMAR_FILE=$polyglotdir/grammars/ruby/Corundum.g4 \

    ninja -C ./build/ruby

    popd
end

function check-envs
    assert_set CC
    assert_set CFLAGS
    assert_set target
    assert_set suffix
    assert_set installdir
    assert_exists "$main"
end

function build-pair
    set -g target $argv[1]
    set -g suffix $argv[2]
    set -g installdir $targetdir/$target-$suffix

    check-envs

    rm -rf $targetdir/$target-$suffix /tmp/$target-$suffix
    cp -r $targetdir/$target /tmp/$target-$suffix
    git -C /tmp/$target-$suffix clean -fdx

    $target
end

function ruby
    pushd /tmp/ruby-$suffix

    sed -i 's/#option nodynamic/option nodynamic/' ext/Setup

    ./autogen.sh -i

    ./configure --prefix=$installdir \
        --with-coroutine=pthread \
        --disable-dln \
        --disable-shared \
        --disable-rubygems \
        --disable-install-doc \
        --with-static-linked-ext \
        --enable-static \
        --enable-devel \
        --enable-yjit

    make -j
    make install

    cp -f ext/{extinit.o, **.a} $installdir/lib/

    ruby-driver

    popd
end

function ruby-driver
    check-envs

    $CC $CFLAGS -c -o $installdir/lib/main.o $main

    $CC $CFLAGS -c \
        -o $installdir/lib/ruby-driver.o \
        -I $installdir/include/*/ \
        -I $installdir/include/*/x86_64-linux/ \
        $driverdir/ruby-driver.c

    $CC $CFLAGS \
        -o $installdir/bin/ruby-driver \
        -pie -rdynamic -Wl,--export-dynamic \
        $installdir/lib/{main.o, ruby-driver.o, extinit.o, *.a, libruby-static.a} \
        -lm -lz -lffi -lyaml -lcrypt -lssl -lcrypto


end

function mruby
    pushd /tmp/mruby-$suffix

    make

    cp -r build/host/ $targetdir/mruby-$suffix/

    mruby-driver

    popd
end

function mruby-driver
    check-envs

    $CC $CFLAGS \
        -o $installdir/bin/mruby-driver \
        -I $installdir/include \
        $main \
        $driverdir/mruby-driver.c \
        $installdir/lib/libmruby.a -lm
end

function php
    pushd /tmp/php-$suffix

    ./buildconf --force

    # Try to enable enable all extensions that can be linked in statically
    # Sancov does not play well with .so files.
    ./configure --prefix=$targetdir/php-$suffix \
        --disable-all \
        --disable-cgi \
        --disable-shared \
        --enable-static \
        --enable-debug-assertions \
        --enable-option-checking=fatal \
        --enable-embed=static \
        --enable-calendar=static \
        --enable-ctype=static \
        --enable-filter=static \
        --enable-phar=static \
        --enable-tokenizer=static \
        --enable-fileinfo=static \
        --enable-shmop=static \
        --enable-sockets=static \
        --enable-posix=static \
        --enable-session=static \
        --enable-opcache=static \
        --enable-dom=static \
        --enable-xml=static \
        --with-libxml=static \
        --enable-fuzzer \
        --without-pcre-jit \
        --with-pic

    make -j
    make install

    cp sapi/fuzzer/php-fuzz-* $installdir/bin
    cp sapi/fuzzer/fuzzer-sapi.o $installdir/lib

    php-driver

    popd
end

function php-driver
    check-envs

    set includes (string split ' ' -- ($installdir/bin/php-config --includes))

    $CC $CFLAGS \
        $includes \
        -o $installdir/lib/fuzzer-sapi.o \
        -c $driverdir/fuzzer-sapi.c

    $CC $CFLAGS \
        -o $installdir/bin/php-driver \
        $main \
        $driverdir/php-driver.c \
        $installdir/lib/fuzzer-sapi.o \
        $installdir/lib/libphp.a -lm -lxml2
end

function cpython
    pushd /tmp/cpython-$suffix

    cp $driverdir/Setup.local Modules/Setup.local

    set -x LDFLAGS "$CFLAGS"

    ./configure --prefix=$targetdir/cpython-$suffix \
        --disable-shared \
        --disable-test-modules \
        --with-static-libpython=yes \
        --with-pymalloc=no \
        --with-ensurepip=no

    make -j
    make install

    cp Modules/**/*.a $targetdir/cpython-$suffix/lib

    cpython-driver

    popd
end

function cpython-driver
    check-envs

    $CC $CFLAGS \
        -o $installdir/bin/cpython-driver \
        -I $installdir/include/python* \
        $main \
        $driverdir/cpython-driver.c \
        $installdir/lib/{libpython*.a, *.a} -lffi -lz -lncursesw -lpanel
end

function micropython
    pushd /tmp/micropython-$suffix

    sed -i "s|main.c \\\|$driverdir/lib.c \\\|" ports/unix/Makefile
    env CFLAGS="" make CC=clang -j -C mpy-cross
    make CC="$CC $CFLAGS" -j -C ports/unix all lib

    mkdir -p $targetdir/micropython-$suffix/{bin,lib}
    cp ports/unix/build-standard/micropython $targetdir/micropython-$suffix/bin
    cp ports/unix/build-standard/libmicropython.a $targetdir/micropython-$suffix/lib

    micropython-driver

    popd
end

function micropython-driver
    check-envs

    $CC $CFLAGS \
        -o $installdir/bin/micropython-driver \
        $main \
        $driverdir/micropython-driver.c \
        $installdir/lib/libmicropython.a -lm -lffi
end

function v8
    pushd /tmp/v8-$suffix

    set -xa PATH $targetdir/depot_tools


    echo "Run the following command in $targetdir/v8!" # Use fuzzilli's compile flags
    echo gn gen $installdir --args='is_debug=false dcheck_always_on=true v8_static_library=true v8_enable_verify_heap=true sanitizer_coverage_flags="trace-pc-guard" target_cpu="x64"'
    echo ninja -j8 -C $installdir
end

function aflplusplus
    set -x CC $targetdir/aflplusplus/afl-cc
    set -x CXX $targetdir/aflplusplus/afl-c++
    set -x CFLAGS -DPERSISTENT

    set -g main $driverdir/aflplusplus_main.c
    set -g suffix aflplusplus

    switch $argv
    case ruby
        set -xa CFLAGS -D_FORTIFY_SOURCE=3
    case mruby cpython micropython hermes
        set -x AFL_USE_ASAN 1
        set -x ASAN_OPTIONS "detect_leaks=0"
    case '*'
        error "unknown target $argv"
    end

    if test -z "$fuzzer"
        set fuzzer aflplusplus
    end

    build-pair $argv $fuzzer
end

function afl
    set -x CC $targetdir/aflplusplus/afl-cc
    set -x CXX $targetdir/aflplusplus/afl-c++
    set -x CFLAGS -g -fno-omit-frame-pointer -DAFL
    set -x AFL_LLVM_INSTRUMENT CLASSIC

    set -g main $driverdir/aflplusplus_main.c
    set -g suffix asan

    switch $argv
    case ruby
        set -x CFLAGS -D_FORTIFY_SOURCE=3
    case mruby cpython micropython php
        set -x AFL_USE_ASAN 1
        set -x ASAN_OPTIONS "detect_leaks=0"
    case '*'
        error "unknown target $argv"
    end

    build-pair $argv afl
end

function reflecta
    set -x CC clang
    set -x CXX clang++
    set -x CFLAGS -g -fsanitize-coverage=trace-pc-guard

    set -g main $driverdir/fuzzilli_main.c

    switch $argv
    case ruby
        set -xa CFLAGS -D_FORTIFY_SOURCE=3
    case mruby cpython micropython php
        set -xa CFLAGS -fsanitize=address
        set -x LDFLAGS $CFLAGS
        set -x ASAN_OPTIONS "detect_leaks=0"
    case v8
        set -e CFLAGS
    case '*'
        error "unknown target $argv"
    end

    build-pair $argv reflecta
end

function sancov
    set -x CC clang
    set -x CXX clang++
    set -x CFLAGS -g -Og -fno-sanitize=address -fsanitize-coverage=trace-pc-guard
    set -x LDFLAGS $CFLAGS

    set -g main $driverdir/aflplusplus_main.c
    set -g suffix sancov

    switch $argv
    case ruby mruby cpython cpython39 php
        set -xa CFLAGS -fno-omit-frame-pointer
    case micropython
        true
    case '*'
        error "unknown target $argv"
    end

    build-pair $argv sancov
end

eval $argv
