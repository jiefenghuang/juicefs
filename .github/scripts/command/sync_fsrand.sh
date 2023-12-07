#!/bin/bash -e

source .github/scripts/common/common.sh

[[ -z "$META" ]] && META=redis
[[ -z "$SEED" ]] && SEED=$(date +%s)
[[ -z "$MAX_EXAMPLE" ]] && MAX_EXAMPLE=100
trap "echo random seed is $SEED" EXIT
source .github/scripts/start_meta_engine.sh
start_meta_engine $META
META_URL=$(get_meta_url $META)
SOURCE_DIR=/tmp/fsrand/
ROOT_DIR2=/tmp/fsrand2/
DEST_DIR1=/jfs/fsrand1/
DEST_DIR2=/jfs/fsrand2/
rm $SOURCE_DIR -rf
rm $ROOT_DIR2 -rf
user=root
test_sync_with_mount_point(){
    prepare_test
    echo "seed is $SEED"
    sudo -u $user MAX_EXAMPLE=$MAX_EXAMPLE SEED=$SEED DERANDOMIZE=true CLEAN_DIR=False ROOT_DIR1=$SOURCE_DIR ROOT_DIR2=$ROOT_DIR2 python3 .github/scripts/fsrand2.py
    #FIXME: remove this line
    chmod 777 $SOURCE_DIR
    chmod 777 $ROOT_DIR2
    ./juicefs format $META_URL myjfs
    ./juicefs mount -d $META_URL /jfs --enable-xattr
    cat /jfs/.accesslog > accesslog &
    jobid=$!
    trap "kill -9 $jobid" EXIT
    for i in {1..1}; do
        rm $DEST_DIR1 -rf
        rm $DEST_DIR2 -rf
        sudo -u $user ./juicefs sync -v $SOURCE_DIR $DEST_DIR1 --dirs --perms --check-all --links --list-threads 10 --list-depth 5 2>&1| tee sync1.log &
        sudo -u $user ./juicefs sync -v $SOURCE_DIR $DEST_DIR1 --dirs --perms --check-all --links --list-threads 10 --list-depth 5 2>&1| tee sync1.log
        echo sudo -u $user ./juicefs sync -v $SOURCE_DIR $DEST_DIR1 --dirs --perms --check-all --links --list-threads 10 --list-depth 5
        exit 1
        sudo -u $user cp -a $SOURCE_DIR $DEST_DIR2  || true
        check_diff $DEST_DIR1 $DEST_DIR2
    done
    sudo -u $user MAX_EXAMPLE=$MAX_EXAMPLE SEED=$SEED DERANDOMIZE=true CLEAN_DIR=False ROOT_DIR1=$SOURCE_DIR ROOT_DIR2=$ROOT_DIR2 python3 .github/scripts/fsrand2.py
    #FIXME: remove this line
    chmod 777 $SOURCE_DIR
    chmod 777 $ROOT_DIR2
    for i in {1..100}; do
        echo ./juicefs sync -v $SOURCE_DIR $DEST_DIR1 --dirs --perms --check-all --links --update --delete-dst --list-threads 10 --list-depth 5
        sudo -u $user ./juicefs sync -v $SOURCE_DIR $DEST_DIR1 --dirs --perms --check-all --links --update --delete-dst --list-threads 10 --list-depth 5 2>&1| tee sync2.log &
        sudo -u $user ./juicefs sync -v $SOURCE_DIR $DEST_DIR1 --dirs --perms --check-all --links --update --delete-dst --list-threads 10 --list-depth 5 2>&1| tee sync2.log &
        sudo -u $user ./juicefs sync -v $SOURCE_DIR $DEST_DIR1 --dirs --perms --check-all --links --update --delete-dst --list-threads 10 --list-depth 5 2>&1| tee sync2.log || true
        if grep -q "Failed to delete" sync2.log; then
            echo "failed to delete, retry sync"
        else
            echo "sync delete success"
            break
        fi
    done
    rm -rf $DEST_DIR2 && sudo -u $user cp -a $SOURCE_DIR $DEST_DIR2  || true
    check_diff $DEST_DIR1 $DEST_DIR2
}

check_diff(){
    dir1=$1
    dir2=$2
    diff -ur --no-dereference $dir1 $dir2
    # pushd . && cd $SOURCE_DIR && find . -printf "%m:%u:%g:%p\n" | sort && popd
    # pushd . && cd $DEST_DIR && find . -printf "%m:%u:%g:%p\n" | sort && popd
    count=$(find $dir2 -type f -name "*.*.tmp*" | wc -l)
    if [ $count -ne 0 ]; then
        echo "tmp file exists"
        find $dir2 -type f -name "*.*.tmp*" -exec ls -l {} \;
        exit 1
    fi
    pushd . && diff <(cd $dir1 && find . -printf "%m:%u:%g:%p\n" | sort) <(cd $dir2 && find . -printf "%m:%u:%g:%p\n" | sort) && popd
    if [ $? -ne 0 ]; then
        echo "permission or owner or group not equal"
        exit 1
    fi
    # TODO: uncomment this after xattr is supported
    # pushd . && diff <(cd $dir1 && find . -exec getfattr -dm- {} + | sort) <(cd $dir2 && find . -exec getfattr -dm- {} + | sort) && popd
    # if [ $? -ne 0 ]; then
    #     echo "xattr not equal"
    #     exit 1
    # fi
    echo "check diff success"
}

source .github/scripts/common/run_test.sh && run_test $@
         