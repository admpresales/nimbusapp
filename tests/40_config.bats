#!/usr/bin/env bats

load helper
load output_assert
load docker_assert

function setup() {
    export NIMBUS_BASEDIR="$BATS_TMPDIR/nimbus-test-recreate"

    # Create directory and container to be recreated later
    if is_first_test; then
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

@test "Config: Substring" {
    cat >"$NIMBUS_BASEDIR/apps.config" <<EOF
nimbusapp-test.dockerapp admpresales/nimbusapp-test.dockerapp:0.1.0
nimbusapp-test-fake.dockerapp admpresales/nimbusapp-test-fake.dockerapp:0.1.0
EOF

    # Cannot use $TEST_IMAGE here
    run "$NIMBUS_EXE" nimbusapp-test -d -f up

    (( status == 0 ))

    assert_output_contains "Using nimbusapp-test.dockerapp:0.1.0 version found in"
    assert_not_output_contains "Not able to find nimbusapp"
}