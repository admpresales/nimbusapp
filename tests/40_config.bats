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
    skip
    cat >"$NIMBUS_BASEDIR/apps.config" <<EOF
# v2
nimbusapp-test admpresales nimbusapp-test 0.1.0
nimbusapp-test-fake admpresales nimbusapp-test-fake 0.1.0
EOF

    cat "$NIMBUS_BASEDIR/apps.config"

    # Cannot use $TEST_IMAGE here
    run "$NIMBUS_EXE" nimbusapp-test -d -f up
    (( status == 0 ))

    # Ensure nothing gets deleted
    grep "nimbusapp-test\s" "$NIMBUS_BASEDIR/apps.config"
    grep "nimbusapp-test-fake\s" "$NIMBUS_BASEDIR/apps.config"
}

@test "Config: Remember" {
    skip
    : > "$NIMBUS_BASEDIR/apps.config"

    run "$NIMBUS_EXE" nimbusapp-test:0.1.0 -d -f up
    (( status == 0 ))
    assert_container_exists "$TEST_CONTAINER"

    grep '^nimbusapp-test admpresales nimbusapp-test 0.1.0$' "$NIMBUS_BASEDIR/apps.config"

    run "$NIMBUS_EXE" nimbusapp-test -d -f down
    (( status == 0 ))
    assert_not_container_exists "$TEST_CONTAINER"
}

@test "Config: Project" {
    skip
    : > "$NIMBUS_BASEDIR/apps.config"

    run "$NIMBUS_EXE" nimbusapp-test:0.1.0 -p testing -d -f up
    (( status == 0 ))
    assert_container_exists "$TEST_CONTAINER"

    grep '^testing admpresales nimbusapp-test 0.1.0$' "$NIMBUS_BASEDIR/apps.config"

    run "$NIMBUS_EXE" -p testing -d -f down
    (( status == 0 ))
    assert_not_container_exists "$TEST_CONTAINER"
}

@test "Config: Upgrade" {
    skip
    cat > "$NIMBUS_BASEDIR/apps.config" <<EOF
nimbusapp-test.dockerapp admpresales/nimbusapp-test:0.1.0
EOF

    run "$NIMBUS_EXE" nimbusapp-test ps

    grep '^nimbusapp-test admpresales nimbusapp-test 0.1.0' "$NIMBUS_BASEDIR/apps.config"
}

@test "Config: Overwrite" {
    skip
        cat > "$NIMBUS_BASEDIR/apps.config" <<EOF
# v2
testing admpresales nimbusapp-test wrong-version
EOF

    "$NIMBUS_EXE" nimbusapp-test:0.1.0 -p testing -d -f up

    grep '^testing admpresales nimbusapp-test 0.1.0' "$NIMBUS_BASEDIR/apps.config"
    wc -l "$NIMBUS_BASEDIR/apps.config" | cut -f1 -d' '
    [[ "$(wc -l "$NIMBUS_BASEDIR/apps.config" | cut -f1 -d' ' | cut -f1)" -eq 2 ]]
}
