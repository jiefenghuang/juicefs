#!/bin/bash -e
source .github/scripts/common/common.sh
[[ -z "$META" ]] && META=redis
[[ -z "$SEED" ]] && SEED=$(date +%s)
[[ -z "$MAX_EXAMPLE" ]] && MAX_EXAMPLE=100
[[ -z "$GOCOVERDIR" ]] && GOCOVERDIR=/tmp/cover
[[ -z "$USER" ]] && USER=root
if [ ! -d "$GOCOVERDIR" ]; then
    mkdir -p $GOCOVERDIR
fi
trap "echo random seed is $SEED" EXIT
# trap 'previous_command=$this_command; this_command=$BASH_COMMAND' DEBUG                             
# trap 'echo "exit $? due to $previous_command"' EXIT   

source .github/scripts/start_meta_engine.sh
start_meta_engine $META
META_URL=$(get_meta_url $META)
SOURCE_DIR1=/tmp/fsrand1/
SOURCE_DIR2=/tmp/fsrand2/
DEST_DIR1=/jfs/fsrand1/
DEST_DIR2=/jfs/fsrand2/
rm $SOURCE_DIR1 -rf && sudo -u $USER mkdir $SOURCE_DIR1
rm $SOURCE_DIR2 -rf && sudo -u $USER mkdir $SOURCE_DIR2

test_sync(){
    do_sync --dirs --perms --check-all --links --list-threads 10 --list-depth 5
    do_update --dirs --perms --check-all --links --update --delete-dst --list-threads 10 --list-depth 5
}

test_sync_without_perms(){
    do_sync --dirs --check-all --links --list-threads 10 --list-depth 5
    do_update --dirs --check-all --links --update --delete-dst --list-threads 10 --list-depth 5
}

test_sync_without_links(){
    do_sync --dirs --perms --check-all --list-threads 10 --list-depth 5
    do_update --dirs --perms --check-all --update --delete-dst --list-threads 10 --list-depth 5
}

test_sync_mp(){
    do_sync_with_mp --dirs --perms --check-all --links --list-threads 10 --list-depth 5
    do_update_with_mp --dirs --perms --check-all --links --update --delete-dst --list-threads 10 --list-depth 5
}

test_sync_mp_without_perms(){
    do_sync_with_mp --dirs --check-all --links --list-threads 10 --list-depth 5
    do_update_with_mp --dirs --check-all --links --update --delete-dst --list-threads 10 --list-depth 5
}

test_sync_mp_without_links(){
    do_sync_with_mp --dirs --perms --check-all --list-threads 10 --list-depth 5
    do_update_with_mp --dirs --perms --check-all --update --delete-dst --list-threads 10 --list-depth 5
}

do_sync(){
    prepare_test
    local sync_option=$@
    sudo -u $USER MAX_EXAMPLE=$MAX_EXAMPLE SEED=$SEED DERANDOMIZE=true CLEAN_DIR=False ROOT_DIR1=$SOURCE_DIR1 ROOT_DIR2=$SOURCE_DIR2 python3 .github/scripts/fsrand2.py
    ./juicefs format $META_URL myjfs
    for i in {1..1}; do
        rm $DEST_DIR1 -rf
        rm $DEST_DIR2 -rf
        sudo -u $USER GOCOVERDIR=$GOCOVERDIR meta_url=$META_URL ./juicefs sync $SOURCE_DIR1 jfs://meta_url/fsrand1/ $sync_option 2>&1| tee sync.log || true
        echo sudo -u $USER GOCOVERDIR=$GOCOVERDIR meta_url=$META_URL ./juicefs sync $SOURCE_DIR1 jfs://meta_url/fsrand1/ $sync_option
        ./juicefs mount -d $META_URL /jfs
        do_copy $sync_option
        check_diff $DEST_DIR1 $DEST_DIR2
    done
}

do_sync_with_mp(){
    prepare_test
    local sync_option=$@
    sudo -u $USER MAX_EXAMPLE=$MAX_EXAMPLE SEED=$SEED DERANDOMIZE=true CLEAN_DIR=False ROOT_DIR1=$SOURCE_DIR1 ROOT_DIR2=$SOURCE_DIR2 python3 .github/scripts/fsrand2.py
    #FIXME: remove this line
    chmod 777 $SOURCE_DIR1
    chmod 777 $SOURCE_DIR2
    GOCOVERDIR=$GOCOVERDIR ./juicefs format $META_URL myjfs
    GOCOVERDIR=$GOCOVERDIR ./juicefs mount -d $META_URL /jfs --enable-xattr
    cat /jfs/.accesslog > accesslog &
    local jobid=$!
    trap "kill -9 $jobid || true" EXIT
    for i in {1..1}; do
        rm $DEST_DIR1 -rf
        rm $DEST_DIR2 -rf
        sudo -u $USER GOCOVERDIR=$GOCOVERDIR ./juicefs sync -v $SOURCE_DIR1 $DEST_DIR1 $sync_option 2>&1| tee sync.log || true
        echo sudo -u $USER GOCOVERDIR=$GOCOVERDIR ./juicefs sync -v $SOURCE_DIR1 $DEST_DIR1 $sync_option 
        do_copy $sync_option
        check_diff $DEST_DIR1 $DEST_DIR2
    done
}

do_update(){
    local sync_option=$@
    sudo -u $USER MAX_EXAMPLE=$MAX_EXAMPLE SEED=$SEED DERANDOMIZE=true CLEAN_DIR=False ROOT_DIR1=$SOURCE_DIR1 ROOT_DIR2=$SOURCE_DIR2 python3 .github/scripts/fsrand2.py
    for i in {1..5}; do
        sudo -u $USER GOCOVERDIR=$GOCOVERDIR meta_url=$META_URL ./juicefs sync $SOURCE_DIR1 jfs://meta_url/fsrand1/ $sync_option 2>&1| tee sync.log || true
        echo sudo -u $USER GOCOVERDIR=$GOCOVERDIR meta_url=$META_URL ./juicefs sync $SOURCE_DIR1 jfs://meta_url/fsrand1/ $sync_option
        if grep -q "Failed to delete" sync.log; then
            echo "failed to delete, retry sync"
        else
            echo "sync delete success"
            break
        fi
    done
    do_copy $sync_option
    check_diff $DEST_DIR1 $DEST_DIR2
}

do_update_with_mp(){
    local sync_option=$@
    sudo -u $USER MAX_EXAMPLE=$MAX_EXAMPLE SEED=$SEED DERANDOMIZE=true CLEAN_DIR=False ROOT_DIR1=$SOURCE_DIR1 ROOT_DIR2=$SOURCE_DIR2 python3 .github/scripts/fsrand2.py
    for i in {1..100}; do
        sudo -u $USER GOCOVERDIR=$GOCOVERDIR ./juicefs sync -v $SOURCE_DIR1 $DEST_DIR1 $sync_option  2>&1| tee sync.log || true
        echo sudo -u $USER GOCOVERDIR=$GOCOVERDIR ./juicefs sync -v $SOURCE_DIR1 $DEST_DIR1 $sync_option
        if grep -q "Failed to delete" sync.log; then
            echo "failed to delete, retry sync"
        else
            echo "sync delete success"
            break
        fi
    done
    do_copy $sync_option
    check_diff $DEST_DIR1 $DEST_DIR2
}

do_copy(){
    local sync_option=$@
    local preserve="timestamps"
    local no_preserve=""
    if [[ "$sync_option" =~ "--perms" ]]; then
        preserve+=",mode,ownership"
    else
        no_preserve+="mode,ownership"
    fi
    if [[ "$sync_option" =~ "--links" ]]; then
       preserve+=",links"
    fi
    local cp_option="--recursive --preserve=$preserve"
    if [[ -n "$no_preserve" ]]; then
        cp_option+=" --no-preserve=$no_preserve"
    fi
    if [[ "$sync_option" =~ "--links" ]]; then
        cp_option+=" --no-dereference"
    else
        cp_option+=" --dereference"
    fi
    rm -rf $DEST_DIR2 
    sudo -u $USER cp  $SOURCE_DIR1 $DEST_DIR2 $cp_option || true
    echo sudo -u $USER cp  $SOURCE_DIR1 $DEST_DIR2 $cp_option
}

check_diff(){
    local dir1=$1
    local dir2=$2
    diff -ur --no-dereference $dir1 $dir2
    local count=$(find $dir2 -type f -name "*.*.tmp*" | wc -l)
    if [ $count -ne 0 ]; then
        echo "tmp file exists"
        find $dir2 -type f -name "*.*.tmp*" -exec ls -l {} \;
        exit 1
    fi
    pushd . && diff <(cd $dir1 && find . -printf "%p:%m:%u:%g:%y\n" | sort) <(cd $dir2 && find . -printf "%p:%m:%u:%g:%y\n" | sort) && popd
    if [ $? -ne 0 ]; then
        echo "permission or owner or group not equal"
        exit 1
    fi
    # pushd . && diff <(cd $dir1 && find . ! -type d -printf "%p:%.23T+\n" | sort) <(cd $dir2 && find . ! -type d -printf "%p:%.23T+\n" | sort) && popd
    # if [ $? -ne 0 ]; then
    #     echo "mtime not equal"
    #     exit 1
    # fi
    # TODO: uncomment this after xattr is supported
    # pushd . && diff <(cd $dir1 && find . -exec getfattr -dm- {} + | sort) <(cd $dir2 && find . -exec getfattr -dm- {} + | sort) && popd
    # if [ $? -ne 0 ]; then
    #     echo "xattr not equal"
    #     exit 1
    # fi
    echo "check diff success"
}

source .github/scripts/common/run_test.sh && run_test $@
         