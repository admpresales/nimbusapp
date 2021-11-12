#!/usr/bin/env bats
#
# Tests for the nimbusapp --set|-s options, which should be rendered by docker-app
#    into the compose file
#
# - Ensure the --set value is passed to the container
# - Ensure that no undue formatting is performed
#
#

load helper
load docker_assert

function setup() {
    teardown
}

function teardown() {
    cleanup_containers "$TEST_CONTAINER"
}

@test "Set: Modify variable" {
    # Inject a random number to reduce the chances of us hitting the container's default
    local msg="This is a test message - $RANDOM"

    "$NIMBUS_EXE" "$TEST_IMAGE" --set "message=${msg}" -d -d -f up

    run docker exec "$TEST_CONTAINER" /bin/sh -c 'echo -n $message'

    (( status == 0 ))
    [[ "$output" = "$msg" ]]
}

# docker-app parses all -s values as YAML data types, this can cause numeric values (such as 5.00) to be truncated
# nimbusapp should wrap all values in quotes to ensure they are properly treated as strings
@test "Set: Numbers should not be parsed" {
    local msg="5.00"

    run "$NIMBUS_EXE" "$TEST_IMAGE" --set "message=$msg" -d -d render
    run "$NIMBUS_EXE" "$TEST_IMAGE" --set "message=$msg" -d -d up

    (( status == 0 ))
    # grep -e "--set 'message=\"5.00\"'" <<< $output

    run docker exec "$TEST_CONTAINER" /bin/sh -c 'echo $message'

    (( status == 0 ))
    [[ "$output" == "$msg" ]]
}

