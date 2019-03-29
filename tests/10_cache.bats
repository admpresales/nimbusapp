#!/usr/bin/env bats

load helper
load docker_assert

function setup() {
    export NIMBUS_BASEDIR="$BATS_TMPDIR/nimbus-test-$$"
    export CACHE_FILE="$NIMBUS_BASEDIR/cache/nimbusapp-test/jasoncorlett/nimbusapp-test/0.1.0/nimbusapp-test.yml"

    teardown
    mkdir -vp "$NIMBUS_BASEDIR"
}

function teardown() {
    cleanup_containers "nimbusapp-test-web"
    assert_not_container_exists "nimbusapp-test-web"

    rm -fvr "$NIMBUS_BASEDIR"
}

@test "Cache: Use file offline" {
    # Use a regular command to generate the cached file
    [[ ! -f "$CACHE_FILE" ]]

    "$NIMBUS_EXE" jasoncorlett/nimbusapp-test:0.1.0 -d -d render

    [[ -f "$CACHE_FILE" ]]

    # Set a new Docker Hub URL to simulate a connection failure
    export NIMBUS_DOCKERHUB_URL=0.0.0.0:0
    run "$NIMBUS_EXE" jasoncorlett/nimbusapp-test:0.1.0 -d -d up

    # Command should succeed and create the new container
    (( status == 0 ))
    assert_container_running "nimbusapp-test-web"

    # Output should contain the following messages
    grep "No connection to Docker Hub, using cached file!" <<< $output
    grep "Docker Hub: 0.0.0.0:0 Timeout: 10" <<< $output
}

