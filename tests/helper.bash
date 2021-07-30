#!/usr/bin/env bash
#
# helper.bash
#
# Common functions and variables shared across test cases
#
readonly TEST_IMAGE="${TEST_IMAGE-admpresales/nimbusapp-test:0.1.0}"
readonly TEST_CONTAINER="${TEST_CONTAINER-nimbusapp-test-web}"

export ${NIMBUS_EXE="$PWD/nimbusapp"}

# cleanup_containers()
#
# Search for any containers matching the inputs provided and delete them,
# regardless of container state
function cleanup_containers() {
    for f in "$@"; do
        for c in $(docker ps -qaf "name=$1"); do
            docker rm -f $c
        done
    done
}

# is_first_test()
#
# Use bats global variables to determine if we are running as part of the first
# test case in a file. Useful for one-time initialization.
#
# Usage:
#   function setup() {
#       if is_first_test; then
#           initialize_resources
#       fi
#   }
function is_first_test() {
    if [[ "$BATS_TEST_NAME" == "${BATS_TEST_NAMES[0]}" ]]; then
        return 0
    else
        return 1
    fi
}

# is_last_test()
#
# Use bats global variables to determine if we are running as part of the last
# test case in a file. Useful for cleanup.
#
# Usage:
#   function teardown() {
#       if is_last_test; then
#           cleanup_after_tests
#       fi
#   }
#
function is_last_test() {
    if [[ "$BATS_TEST_NAME" == "${BATS_TEST_NAMES[${#BATS_TEST_NAMES[@]}-1]}" ]]; then
        return 0
    else
        return 1
    fi
}

