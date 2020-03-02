#!/usr/bin/env bats
#
# Testing prompts to recreate containers
#

load helper
load output_assert
load docker_assert

function setup() {
    export NIMBUS_BASEDIR="$BATS_TMPDIR/nimbus-test-recreate"

    # Create directory and container to be recreated later
    if is_first_test; then
        mkdir -p "$NIMBUS_BASEDIR"
        cleanup_containers "$TEST_CONTAINER"

        run "$NIMBUS_EXE" "$TEST_IMAGE" -s "MESSAGE=setup" -d -f up
        ((status == 0))
        assert_container_exists "$TEST_CONTAINER"
        assert_message "setup"
    fi
}

function teardown() {
    if is_last_test; then
        cleanup_containers "$TEST_CONTAINER"
        rm -fr "$NIMBUS_BASEDIR"
    fi
}

# Check the test container's message variable
# NB. Must be run after any output assertions in the test
#     as this will overwrite the output variable
function assert_message() {
    local expected="$1"

    run docker exec "$TEST_CONTAINER" /bin/sh -c 'echo -n $message'

    (( status == 0 ))

    if [[ $output != $expected ]]; then
        echo "FAIL: Expected \`$expected', got \`$output'" >&2
        return 1
    fi

    return 0
}

@test "Recreate: Yes" {
    run "$NIMBUS_EXE" "$TEST_IMAGE" -s "MESSAGE=yes" -d up <<< $'y\n'

    (( status == 0 ))

    assert_output_contains "The following containers will be recreated:"
    assert_output_contains "- /nimbusapp-test-web" 
    assert_output_contains "Recreate the listed containers? \[y/n\]"
    assert_output_contains "Recreating nimbusapp-test-web ... done"

    assert_message "yes"
}

@test "Recreate: No" {
    run "$NIMBUS_EXE" "$TEST_IMAGE" -s "MESSAGE=no" -d up <<< $'n\n'

    (( status == 1 ))
    
    assert_output_contains "The following containers will be recreated:"
    assert_output_contains "- /nimbusapp-test-web" 
    assert_output_contains "Recreate the listed containers? \[y/n\]"

    assert_not_output_contains "Recreating nimbusapp-test-web ... done"

    assert_message "yes" # Should not have changed
}

@test "Recreate: Force" {
    run "$NIMBUS_EXE" "$TEST_IMAGE" -s "MESSAGE=force" -d -f up

    (( stauts == 0 ))

    assert_not_output_contains "The following containers will be recreated:"
    assert_not_output_contains "- /nimbusapp-test-web" 
    assert_not_output_contains "Recreate the listed containers? \[y/n\]"

    assert_output_contains "Recreating nimbusapp-test-web ... done"

    assert_message "force"
}

@test "Recreate: --force-recreate" {
    run "$NIMBUS_EXE" "$TEST_IMAGE" -s "MESSAGE=force-recreate" -d up --force-recreate

    (( stauts == 0 ))

    assert_not_output_contains "The following containers will be recreated:"
    assert_not_output_contains "- /nimbusapp-test-web" 
    assert_not_output_contains "Recreate the listed containers? \[y/n\]"

    assert_output_contains "Recreating nimbusapp-test-web ... done"

    assert_message "force-recreate"
}