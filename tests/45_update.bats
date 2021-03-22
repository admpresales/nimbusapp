#!/usr/bin/env bats

load helper
load output_assert

@test "Update: Get file" {
    local SRC="$BATS_TMPDIR/update/srv"
    local DST="$BATS_TMPDIR/update/bin"

    local VERSION="$$.$RANDOM"
    local DATE="$$.$RANDOM"

    mkdir -vp "$SRC" "$DST"
    rm -f "$DST/nimbusapp" "$SRC/nimbusapp" "$SRC/nimbusapp.tar.gz"

    cp nimbusapp "$SRC"
    cp nimbusapp "$DST"
    
    pushd "$SRC"

    sed -i  -e "s/\(readonly NIMBUS_RELEASE_VERSION=\).*/\1$VERSION/" \
            -e "s/\(readonly NIMBUS_RELEASE_DATE=\).*/\1$DATE/" \
            "nimbusapp"
    
    tar czf nimbusapp.tar.gz nimbusapp

    popd

    ls -l $SRC $DST

    export NIMBUS_INSTALL_DIR="$DST"
    export NIMBUS_DOWNLOAD_URL="file://$SRC/nimbusapp.tar.gz"

    "$DST/nimbusapp" -f update

    [[ -f "$DST/nimbusapp" ]]

    run "$DST/nimbusapp" version

    (( status == 0 ))

    assert_output_contains "nimbusapp version $VERSION"
    assert_output_contains "Released on $DATE"
}