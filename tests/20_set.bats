#!/usr/bin/env bats

load helper
load docker_assert

function setup() {
    teardown
}

function teardown() {
    cleanup_containers "nimbusapp-test-web"
}

@test "Set: Modify variable" {
    # Inject a random number to reduce the chances of us hitting the container's default
    local msg="This is a test message - $RANDOM"

    "$NIMBUS_EXE" jasoncorlett/nimbusapp-test:0.1.0 --set "message=${msg}" -d -d up

    run docker exec nimbusapp-test-web /bin/sh -c 'echo -n $message'

    (( status == 0 ))
    [[ "$output" = "$msg" ]]
}

# docker-app parses all -s values as YAML data types, this can cause numeric values (such as 5.00) to be truncated
# nimbusapp should wrap all values in quotes to ensure they are properly treated as strings
@test "Set: Numbers should not be parsed" {
    local msg="5.00"

    run "$NIMBUS_EXE" jasoncorlett/nimbusapp-test:0.1.0 --set "message=$msg" -d -d up

    (( status == 0 ))
    grep -e "--set 'message=\"5.00\"'" <<< $output

    run docker exec nimbusapp-test-web /bin/sh -c 'echo $message'

    (( status == 0 ))
    [[ "$output" == "$msg" ]]
}

