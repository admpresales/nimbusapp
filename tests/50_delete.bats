#!/usr/bin/env bats

load helper
load docker_assert

@test "Delete" {
    "$NIMBUS_EXE" nimbusapp-test:0.1.0 pull
    "$NIMBUS_EXE" nimbusapp-test:0.2.0 pull

    "$NIMBUS_EXE" nimbusapp-test:0.2.0 -f delete

    assert_image_exists "nimbusapp-test-web:0.1.0"
    assert_not_image_exists "nimbusapp-test-web:0.2.0"
}

@test "Purge" {
    "$NIMBUS_EXE" nimbusapp-test:0.1.0 pull
    "$NIMBUS_EXE" nimbusapp-test:0.2.0 pull

    "$NIMBUS_EXE" nimbusapp-test -f purge

    assert_not_image_exists "nimbusapp-test-web:0.1.0"
    assert_image_exists "nimbusapp-test-web:0.2.0"
}
