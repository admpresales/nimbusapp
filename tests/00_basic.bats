#!/usr/bin/env bats
#
# Warning: These test cases are not isolated, as they depend on the previous steps to
# have left the container in a specific state
#

load helper
load docker_assert

function setup() {
    readonly IMAGE="jasoncorlett/nimbusapp-test:0.1.0"
    readonly CONTAINER=nimbusapp-test-web
    export NIMBUS_BASEDIR="$BATS_TMPDIR/nimbusapp-test-basic"

    if is_first_test; then
        echo "BEFORE FIRST TEST" >&3
        mkdir -p "$NIMBUS_BASEDIR"
        cleanup_containers "$CONTAINER"
    else
        # Stop contact docker hub so we can run quickly
        # This relies on the nimbusapp caching feature

        export NIMBUS_DOCKERHUB_URL="0.0.0.0:0"
    fi
}

function teardown() {
    # Only run once after last
    if is_last_test; then
        echo "AFTER LAST TEST" >&3
        cleanup_containers
        rm -fr "$NIMBUS_BASEDIR"
    fi
}

@test "Basic: Render" {
    run "$NIMBUS_EXE" "$IMAGE" -d render

    (( status == 0 ))
    grep "container_name: nimbusapp-test-web" <<< $output
}

@test "Basic: Create container" {
    cleanup_containers "$CONTAINER"
    assert_not_container_exists "$CONTAINER"

    "$NIMBUS_EXE" "$IMAGE" -d up

    assert_container_running "$CONTAINER"
}

@test "Basic: Stop Container" {
    assert_container_running "$CONTAINER"

    "$NIMBUS_EXE" "$IMAGE" -d stop

    assert_container_exited "$CONTAINER"
}

@test "Basic: Start Container" {
    assert_container_exited "$CONTAINER"

    "$NIMBUS_EXE" "$IMAGE" -d start

    assert_container_running "$CONTAINER"
}

@test "Basic: Restart Container" {
    assert_container_running "$CONTAINER"

    sleep 1

    local before="$(date +"%s")"
    "$NIMBUS_EXE" "$IMAGE" -d restart

    assert_container_running "$CONTAINER"
    local startTime="$(date +"%s" -d "$(docker inspect --format "{{.State.StartedAt}}" "$CONTAINER")")"

    echo "Before Start Command: $before" >&2
    echo "Container Start Time: $startTime" >&2
    (( startTime >= before ))
}

@test "Basic: Destroy Container" {
    assert_container_exists "$CONTAINER"

    "$NIMBUS_EXE" "$IMAGE" -d down

    assert_not_container_exists "$CONTAINER"
}
