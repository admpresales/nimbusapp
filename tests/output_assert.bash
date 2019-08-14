#!/bin/bash
#
# output_assert.bash
#
# functions for assertion against the output of a bats "run" statement
#

function assert_output_contains() {
    local term="$1"

    if filtered_output | grep -e "$term"; then
        return 0
    else
        echo "FAIL: Expected output to contain: \`$term'" >&2
        filtered_output
        return 1
    fi
}

function assert_not_output_contains() {
    local term="$1"

    if filtered_output | grep -v -e "$term"; then
        return 0
    else
        echo "FAIL: Expected output *not* to contain: \`$term''" >&2
        filtered_output
        return 1
    fi
}

# filtered_output
#
# Filters out characters that could interfere with test cases
# 
# Example: Coloured output with `echo -e "\e[9m"`
#
function filtered_output() {
    sed -e $'s/\x1b\[[0-9]\+m//g' <<< $output
}

