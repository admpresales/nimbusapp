#!/usr/bin/env bats

load helper
load docker_assert

@test "Delete" {
    local image="nimbusapp-delete-test"

    for i in {1..3}; do
        docker tag httpd:2.4 "${image}:0.${i}.0"
        assert_image_exists "${image}:0.${i}.0"
    done

    "$NIMBUS_EXE" -s WEB_IMAGE="${image}:0.2.0" "${TEST_IMAGE}" -f delete

    assert_image_exists "${image}:0.1.0"
    assert_image_exists "${image}:0.3.0"
    assert_not_image_exists "${image}:0.2.0"

    docker rmi "${image}:0.1.0" "${image}:0.3.0"
}

@test "Purge" {
    local image="nimbusapp-purge-test"

    for i in {1..3}; do
        docker tag httpd:2.4 "${image}:0.${i}.0"
        assert_image_exists "${image}:0.${i}.0"
    done

    "$NIMBUS_EXE" -s WEB_IMAGE="${image}:0.2.0" "${TEST_IMAGE}" -f up
    "$NIMBUS_EXE" "${TEST_IMAGE}" -f purge

    assert_image_exists "${image}:0.2.0"

    assert_not_image_exists "${image}:0.1.0"
    assert_not_image_exists "${image}:0.3.0"

    docker rmi "${image}:0.2.0"
}
