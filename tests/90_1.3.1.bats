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
        cleanup_containers "$TEST_CONTAINER"
        rm -fr "$NIMBUS_BASEDIR"
    fi
}

@test "v1.3.1: Logging" {
    local logFile="$NIMBUS_BASEDIR/nimbusapp.log"
    local num="$RANDOM"

    run "$NIMBUS_EXE" "$TEST_IMAGE" -s "MESSAGE=$num" -d -f up

    (( status == 0 ))
    
    cat "$logFile"

    grep "CMD $TEST_IMAGE -s MESSAGE=$num -d -f up" "$logFile"
    
    # grep "DEBUG - -s MESSAGE=$num" "$logFile"

    grep "INFO Using: admpresales/nimbusapp-test.dockerapp:0.1.0" "$logFile"
}

@test "v1.3.1: No Version Message" {
    run "$NIMBUS_EXE" "some_image" -f up

    (( status != 0 ))

    assert_output_contains "ERROR: No version number specified!"
    assert_output_contains "If this is your first time using some_image, please specify a version number"
}

@test "v1.3.1: Underscore Error" {
    run "$NIMBUS_EXE" "octane:test_wrong" -f up

    (( status != 0 ))

    cat <<< "$output"

    assert_output_contains "ERROR: Could not render"
    assert_output_contains "WARNING: Image name contains an underscore which is not used by nimbusapp."
    assert_output_contains "Try using admpresales/octane:test instead"
}
