# Testing

To execute tests, the system must have [bats-core](https://github.com/bats-core/bats-core)
installed and in the user's `$PATH`.

## Run All Tests

To run all available test cases, execute the following:

```bash
cd $YOUR_NIMBUSAPP_CLONE
bats tests/*.bats
```

## Run Individual Suites

To run a specific test suite, execute the following, 
replacing 00_basic.bats with the suite you wish to run:

```bash
cd $YOUR_NIMBUSAPP_CLONE
bats tests/00_basic.bats
```

## Test Files

The tests directory contains several types of files, described below:

| File | Description |
|------|-------------|
| tests/helper.bash | Some common test functions and definitions |
| tests/docker_assert.bash | Assertion functions for dealing with docker |
| tests/*.bats | Test suites, ordered numerically in the intended run order |

.bash shared files may be used in .bats scripts with the bats `load` function:
```bash
load helper         # Loads helper.bash
load docker_assert  # Loads docker_assert.bash
```

Each bats file may contain multiple functions:

| Function | Description |
|----------|-------------|
| setup()  | bash function that is run before every test |
| teardown() | bash function that is run after every test |
| @test "My Test" | named unit test, tests within a file will be run in sequence |
