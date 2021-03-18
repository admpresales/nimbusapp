#!/usr/bin/env bats

load helper
load output_assert
load docker_assert

function setup() {
}

function teardown() {
}

@test "Tags: Fetch All Tags" {
    results="$(\"${NIMBUS_EXE}\"nimbusapp-test tags )"

    if [[ $results != "0.2.0/n0.1.0"]]; then
      exit 1
    fi
}

@test "Config: Remember" {
    results = "$(\"${NIMBUS_EXE}\"nimbusapp-test --latest tags )"

    if [[ $results != "0.1.0"]]; then
      exit 1
    fi
}

