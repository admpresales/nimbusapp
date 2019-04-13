#!/usr/bin/env bats
#
# Testing prompts to delete containers
#

load helper
load output_assert
load docker_assert

function setup() {
    export NIMBUS_BASEDIR="$BATS_TMPDIR/nimbus-test-prompt"

    # Create directory and populate cache
    if is_first_test; then
        mkdir -p "$NIMBUS_BASEDIR"
        cleanup_containers "$TEST_CONTAINER"
        "$NIMBUS_EXE" "$TEST_IMAGE" render
    else
        export NIMBUS_DOCKERHUB_URL="0.0.0.0:0"
    fi

    "$NIMBUS_EXE" "$TEST_IMAGE" -d up
    assert_container_exists "$TEST_CONTAINER"
}

function teardown() {
    if is_last_test; then
        cleanup_containers "$TEST_CONTAINER"
        rm -fr "$NIMBUS_BASEDIR"
    fi
}

@test "Prompt: Yes" {
    run "$NIMBUS_EXE" "$TEST_IMAGE" -d down <<< $'y\n'

    (( status == 0 ))
    assert_not_container_exists "$TEST_CONTAINER"

    assert_output_contains "The following containers will be deleted:"
    assert_output_contains "- /nimbusapp-test-web" 
    assert_output_contains "Do you wish to DELETE these containers? \[y/n\]"
    assert_output_contains "Stopping nimbusapp-test-web ... done"
    assert_output_contains "Removing nimbusapp-test-web ... done"
}

@test "Prompt: No" {

    run "$NIMBUS_EXE" "$TEST_IMAGE" -d down <<< $'n\n'

    (( status == 1 ))
    assert_container_exists "$TEST_CONTAINER"

    assert_output_contains "The following containers will be deleted:"
    assert_output_contains "- /nimbusapp-test-web"
    assert_output_contains "Do you wish to DELETE these containers? \[y/n\]"

    assert_not_output_contains "Stopping"
    assert_not_output_contains "Removing"
}

@test "Prompt: Force" {
    run "$NIMBUS_EXE" "$TEST_IMAGE" -d -f down

    (( stauts == 0 ))
    assert_not_container_exists "$TEST_CONTAINER"

    assert_not_output_contains "The following containers will be deleted:"
    assert_not_output_contains "- /nimbusapp-test-web"
    assert_not_output_contains "Do you wish to DELETE these containers? [y/n]"

    assert_output_contains "Stopping nimbusapp-test-web ... done"
    assert_output_contains "Removing nimbusapp-test-web ... done"
}
