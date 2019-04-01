#!/usr/bin/env bash

readonly TEST_IMAGE="${TEST_IMAGE-admpresales/nimbusapp-test:0.1.0}"
readonly TEST_CONTAINER="${TEST_CONTAINER-nimbusapp-test-web}"

export NIMBUS_EXE="$PWD/nimbusapp"

function cleanup_containers() {
    for f in "$@"; do
        for c in $(docker ps -qaf "name=$1"); do
            docker rm -f $c
        done
    done
}

function is_first_test() {
    if [[ "$BATS_TEST_NAME" == "${BATS_TEST_NAMES[0]}" ]]; then
        return 0
    else
        return 1
    fi
}

function is_last_test() {
    if [[ "$BATS_TEST_NAME" == "${BATS_TEST_NAMES[${#BATS_TEST_NAMES[@]}-1]}" ]]; then
        return 0
    else
        return 1
    fi
}