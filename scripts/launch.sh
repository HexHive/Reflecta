#!/bin/bash

function error {
    echo "$@"
    exit 1
}

function assert {
    if ! "$@"; then
        error "assertion failed: $*"
    fi
}

function assert_set {
    if [ -z "${!1}" ]; then
        error "assertion failed: \$$1 is not set!"
    fi
}

function set_default {
    if [ -z "${!1}" ]; then
        declare -g "$1"="$2"
        echo "\$$1 is not set, using default value $2!"
    fi
}

function assert_exists {
    assert test -e "$1"
}

function get_available_cores {
    seq 0 $(( $(nproc) - 1 ))
}

function remote {
    eval "$@"
}

function get_idle_core {
    local top_occupied_cores=$(remote "top -1b -d 2 -n 2" \
        | grep "%Cpu" \
        | tail -n $(remote "nproc --all") \
        | tr "%Cpu:," " " \
        | awk '{if ($8 < 50) print $1}')

    local docker_occupied_cores=$(remote "docker ps --filter 'name=\\w+-\\w+-\\d+' --format '{{.Names}}'" \
        | cut -d"-" -f3)

    local occupied_cores=$(echo "$top_occupied_cores" "$docker_occupied_cores" \
        | tr '[:space:]' '|' \
        | xargs printf '^(%s)$')

    local c=$(get_available_cores \
        | grep -vE "$occupied_cores" \
        | head -n 1)

    core="$c"
}

function single {
    while test -z "$core"; do
        get_idle_core
    done

    fuzzer="$1"
    target="$2"
    container="$fuzzer-$target-$core"

    assert_set fuzzer
    assert_set target
    assert_set bench
    assert_set core

    local old=$(remote "docker ps -aq --filter name=$container")
    if [ -n "$old" ]; then
        remote "docker rm -f $old" > /dev/null
    fi

    echo -n "$container: "
    container_id=$(
    docker run \
        --detach \
        --name="$container" \
        --cpuset-cpus="$core" \
        --env "bench=$bench" \
        --env "duration=$duration" \
        -v "$PWD/:/workspaces/Reflecta/" \
        -v "$PWD/bench:/workspaces/Reflecta/bench" \
        --tmpfs /tmp:exec \
        -it chibinz/reflecta:latest \
        /workspaces/Reflecta/scripts/run.fish "$fuzzer" "$target"
    )
    container_id=$(cut -c-12 <<< $container_id)
    echo $container_id
    docker logs -f "$container_id" &> logs/$container.log &
}

function multiple {
    fuzzers="$1"
    targets="$2"
    repeat="$3"

    assert_set fuzzers
    assert_set targets

    set_default repeat 1
    set_default duration "24h"
    set_default bench "$(date +%b%d | tr A-Z a-z)"

    for ((i=1; i<=repeat; i++)); do
        IFS=',' read -ra f_array <<< "$fuzzers"
        for f in "${f_array[@]}"; do
            IFS=',' read -ra t_array <<< "$targets"
            for t in "${t_array[@]}"; do
                single "$f" "$t"
                sleep 2
            done
        done
    done
}

multiple "$@"
