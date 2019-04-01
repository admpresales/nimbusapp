#!/usr/bin/env bats
#
# Warning: These test cases are not isolated, as they depend on the previous steps to
# have left the container in a specific state
#

load helper
load docker_assert

function setup() {
    export NIMBUS_BASEDIR="$BATS_TMPDIR/nimbusapp-test-basic"

    if is_first_test; then
        mkdir -p "$NIMBUS_BASEDIR"
        cleanup_containers "$TEST_CONTAINER"
    else
        # Stop contact docker hub so we can run quickly
        # This relies on the nimbusapp caching feature

        export NIMBUS_DOCKERHUB_URL="0.0.0.0:0"
    fi
}

function teardown() {
    # Only run once after last
    if is_last_test; then
        cleanup_containers
        rm -fr "$NIMBUS_BASEDIR"
    fi
}

@test "Basic: Render" {
    run "$NIMBUS_EXE" "$TEST_IMAGE" -d render

    (( status == 0 ))
    grep "container_name: nimbusapp-test-web" <<< $output
}

@test "Basic: Create container" {
    cleanup_containers "$TEST_CONTAINER"
    assert_not_container_exists "$TEST_CONTAINER"

    "$NIMBUS_EXE" "$TEST_IMAGE" -d up

    assert_container_running "$TEST_CONTAINER"
}

@test "Basic: Stop Container" {
    assert_container_running "$TEST_CONTAINER"

    "$NIMBUS_EXE" "$TEST_IMAGE" -d stop

    assert_container_exited "$TEST_CONTAINER"
}

@test "Basic: Start Container" {
    assert_container_exited "$TEST_CONTAINER"

    "$NIMBUS_EXE" "$TEST_IMAGE" -d start

    assert_container_running "$TEST_CONTAINER"
}

@test "Basic: Restart Container" {
    assert_container_running "$TEST_CONTAINER"

    sleep 1

    local before="$(date +"%s")"
    "$NIMBUS_EXE" "$TEST_IMAGE" -d restart

    assert_container_running "$TEST_CONTAINER"
    local startTime="$(date +"%s" -d "$(docker inspect --format "{{.State.StartedAt}}" "$TEST_CONTAINER")")"

    echo "Before Start Command: $before" >&2
    echo "Container Start Time: $startTime" >&2
    (( startTime >= before ))
}

@test "Basic: Destroy Container" {
    assert_container_exists "$TEST_CONTAINER"

    "$NIMBUS_EXE" "$TEST_IMAGE" -d down

    assert_not_container_exists "$TEST_CONTAINER"
}
