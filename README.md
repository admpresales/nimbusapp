# nimbusapp
Script to make starting demo containers easier.

This script is based on the images in https://hub.docker.com/u/admpresales

## Installation
Perform a git pull of the project:

git pull https://github.com/admpresales/nimbusapp

Then copy (or create a link) of nimbusapp into your ${HOME}/bin directory.

## Running

Please refer to the individual images on [Docker Hub](https://hub.docker.com/u/admpresales)
for instructions and sample commands for running nimbusapp.

## Tests

To execute tests, the system must have [bats-core](https://github.com/bats-core/bats-core)
installed and in the user's `$PATH`.

**All Tests:**
```bash
cd $YOUR_NIMBUSAPP_CLONE
bats tests/*.bats
```

**Individual Suites:**
```bash
bats tests/00_basic.bats
```
