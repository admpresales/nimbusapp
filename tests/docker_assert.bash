#!/bin/bash
#
# docker_assert.bash
#
# Common assertions for testing the state of docker containers
#
# All functions will return 0 for true, 1 for false.
# A false return value will cause the test case to fail
#
# Example usage:
#   @test "Docker works" {
#       docker run -d --name "my-container" $MY_IMAGE
#       assert_container_running "my-container"
#   }
#

# assert_container_status()
#
# Assert that the container has a specific status
#
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

# assert_container_running()
#
# Shortcut function for asserting that a container is running
#
function assert_container_running() {
    assert_container_status "$1" "running"
}

# assert_container_exited()
#
# Shortcut function for asserting that a container has stopped
#
function assert_container_exited() {
    assert_container_status "$1" "exited"
}

# assert_container_exists()
#
# Assert that a container with the specified name exists
#
# Accepts the --silent option to suppress output when being called from another function,
# the output can be confusing if we are later negating the check (see assert_not_container_exists)
#
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

# assert_not_container_exists()
#
# Assert that the named container does not currently exist
#
function assert_not_container_exists() {
    if assert_container_exists --silent "$1" 2>/dev/null; then
        echo "FAIL: assert_not_container_exists $1" >&2
        return 1
    else
        return 0
    fi
}
