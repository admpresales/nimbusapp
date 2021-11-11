#!/usr/bin/env bats

load helper
load docker_assert
load output_assert

function setup() {
    export NIMBUS_BASEDIR="$BATS_TMPDIR/nimbusapp-test-131"

    if is_first_test; then
        rm -rf "$NIMBUS_BASEDIR"
        mkdir -p "$NIMBUS_BASEDIR"
        cleanup_containers "$TEST_CONTAINER"
    fi
}

function teardown() {
    if is_last_test; then
        cleanup_containers "$TEST_CONTAINER" nimbusapp-test-web-clone
        rm -fr "$NIMBUS_BASEDIR"
    fi
}

# Bug where project is deleted if it begins with image name
@test "1.3.3: Project Delete Regression" {
    skip
    : > "$NIMBUS_BASEDIR/apps.config"

    local count

    count="$(wc -l < "$NIMBUS_BASEDIR/apps.config")"
    (( count == 0 ))

    "$NIMBUS_EXE" nimbusapp-test:0.2.0 -d -f up --no-start

    count="$(wc -l < "$NIMBUS_BASEDIR/apps.config")"
    (( count == 1 ))

    "$NIMBUS_EXE" nimbusapp-test:0.2.0 -p nimbusapp-test-clone -s WEB_CONTAINER=nimbusapp-test-web-clone -s PORT=12346 -d -f up --no-start

    count="$(wc -l < "$NIMBUS_BASEDIR/apps.config")"
    (( count == 2 ))

    # This is the regerssion that may delete the "clone" project
    "$NIMBUS_EXE" nimbusapp-test ps

    count="$(wc -l < "$NIMBUS_BASEDIR/apps.config")"
    (( count == 2 ))

    "$NIMBUS_EXE" -p nimbusapp-test-clone ps

    count="$(wc -l < "$NIMBUS_BASEDIR/apps.config")"
    (( count == 2 ))
}