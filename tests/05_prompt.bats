#!/usr/bin/env bats
#
# Testing prompts to delete containers
#

load helper
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
    run "$NIMBUS_EXE" "$TEST_IMAGE" -d down <<< y

    (( status == 0 ))
    assert_not_container_exists "$TEST_CONTAINER"

    grep "The following containers will be deleted:" <<< $output
    grep "- nimbusapp-test-web" <<< $output
    grep "Do you wish to DELETE these containers [y/n]" <<< $output
    grep "Stopping nimbusapp-test-web ... done" <<< $output
    grep "Removing nimbusapp-test-web ... done" <<< $output
}

@test "Prompt: No" {

    run "$NIMBUS_EXE" "$TEST_IMAGE" -d down <<< n

    (( status == 1 ))
    assert_container_exists "$TEST_CONTAINER"

    grep "The following containers will be deleted:" <<< $output
    grep "- nimbusapp-test-web" <<< $output
    grep "Do you wish to DELETE these containers [y/n]" <<< $output

    grep -v "Stopping" <<< $output
    grep -v "Removing" <<< $output
}

@test "Prompt: Force" {
    run "$NIMBUS_EXE" "$TEST_IMAGE" -d -f down

    (( stauts == 0 ))
    assert_not_container_exists "$TEST_CONTAINER"

    grep -v "The following containers will be deleted:" <<< $output
    grep -v "- nimbusapp-test-web" <<< $output
    grep -v "Do you wish to DELETE these containers [y/n]" <<< $output

    grep "Stopping nimbusapp-test-web ... done" <<< $output
    grep "Removing nimbusapp-test-web ... done" <<< $output
}