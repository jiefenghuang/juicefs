#!/bin/bash -e
source .github/scripts/common/common.sh

[[ -z "$META" ]] && META=sqlite3
source .github/scripts/start_meta_engine.sh
start_meta_engine $META
META_URL=$(get_meta_url $META)
SOURCE_DIR=/tmp/fsrand
DEST_DIR=/jfs/fsrand

generate_fsrand(){
    seed=$(date +%s)
    ROOT_DIR1=$SOURCE_DIR ROOT_DIR1=/tmp/fsrand2 python3 .github/scripts/fsrand2.py 
}
generate_fsrand

test_sync_with_mount_point(){
    # do_sync_with_mount_point 
    # do_sync_with_mount_point --list-threads 10 --list-depth 5
    # do_sync_with_mount_point --dirs --update --perms --check-all 
    do_sync_with_mount_point --dirs --update --perms --check-all --list-threads 10 --list-depth 5
}
do_sync_with_mount_point(){
    prepare_test
    options=$@
    ./juicefs format $META_URL myjfs
    ./juicefs mount -d $META_URL /jfs
    ./juicefs sync $SOURCE_DIR $DEST_DIR $options --links
    # if [[ ! "$options" =~ "--dirs" ]]; then
    #     find jfs_source -type d -empty -delete
    # fi
    diff -ur --no-dereference $SOURCE_DIR $DEST_DIR
}

test_sync_without_mount_point(){
    do_sync_without_mount_point 
    do_sync_without_mount_point --list-threads 10 --list-depth 5
    do_sync_without_mount_point --dirs --update --perms --check-all 
    do_sync_without_mount_point --dirs --update --perms --check-all --list-threads 10 --list-depth 5
}

do_sync_without_mount_point(){
    prepare_test
    options=$@
    ./juicefs format $META_URL myjfs
    meta_url=$META_URL ./juicefs sync $SOURCE_DIR jfs://meta_url/jfs_source/ $options --links
    ./juicefs mount -d $META_URL /jfs
    # if [[ ! "$options" =~ "--dirs" ]]; then
    #     find $SOURCE_DIR -type d -empty -delete
    # fi
    diff -ur --no-dereference  jfs_source/ /jfs/jfs_source
}



source .github/scripts/common/run_test.sh && run_test $@
