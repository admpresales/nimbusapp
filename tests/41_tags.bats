#!/usr/bin/env bats

load helper
load output_assert
load docker_assert

@test "Tags: Fetch All Tags" {
    run "$NIMBUS_EXE" nimbusapp-test tags

    assert_output_contains "0.3.0"
    assert_output_contains "0.2.0"
    assert_output_contains "0.1.0"
    assert_not_output_contains "0.2.0-dev"
}

@test "Tags: Fetch Latest Tag" {
    run "$NIMBUS_EXE" nimbusapp-test --latest tags

    assert_output_contains "0.3.0"
    assert_not_output_contains "0.1.0"
    assert_not_output_contains "0.2.0"
    assert_not_output_contains "0.2.0-dev"
}

@test "Tags: Ouput Order" {
    run "$NIMBUS_EXE" nimbusapp-test tags

    awk 'NR == 1 && $0 ~ /0.3.0/ || NR == 2 && $0 ~ /0.2.0/ || NR == 3 && $0 ~ /0.1.0/ || rc++; END { exit rc }' <<< "$output"
}
