#!/bin/bash

function assert_container_status() {
    local container="$1"
    local status="$2"

    if [[ -n "$(docker ps -all --quiet --filter "name=${container}" --filter "status=${status}")" ]]; then
        return 0
    else
        echo "FAIL: Could not find \"${container}\" with status \"${status}\"" >&2
        docker ps -all --filter "name=${container}" --format "{{.Names}} {{.Status}}" >&2
        return 1
    fi
}

function assert_container_running() {
    assert_container_status "$1" "running"
}

function assert_container_exited() {
    assert_container_status "$1" "exited"
}

function assert_container_exists() {
    local container silent=0

    if [[ "$1" == "--silent" ]]; then
        silent=1
        shift
    fi

    container="$1"

    # Name needs to match exactly
    if grep -q "^${container}\$" < <(docker ps --all --format "{{.Names}}"); then
        return 0
    else
        (( silent == 0 )) && echo "FAIL: assert_container_exists $1" >&2
        return 1
    fi
}

function assert_not_container_exists() {
    # Suppress error reports
    if assert_container_exists --silent "$1" 2>/dev/null; then
        echo "FAIL: assert_not_container_exists $1" >&2
        return 1
    else
        return 0
    fi
}
