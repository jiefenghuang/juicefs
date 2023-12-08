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

test_sync_mp(){
    do_sync_with_mount_point --dirs --perms --check-all --links --list-threads 10 --list-depth 5
    do_update --dirs --perms --check-all --links --update --delete-dst --list-threads 10 --list-depth 5
}
test_sync_mp_without_perms(){
    do_sync_with_mount_point --dirs --check-all --links --list-threads 10 --list-depth 5
    do_update --dirs --check-all --links --update --delete-dst --list-threads 10 --list-depth 5
}

do_sync_with_mount_point(){
    prepare_test
    sync_option=$@
    sudo -u $USER MAX_EXAMPLE=$MAX_EXAMPLE SEED=$SEED DERANDOMIZE=true CLEAN_DIR=False ROOT_DIR1=$SOURCE_DIR1 ROOT_DIR2=$SOURCE_DIR2 python3 .github/scripts/fsrand2.py
    #FIXME: remove this line
    chmod 777 $SOURCE_DIR1
    chmod 777 $SOURCE_DIR2
    GOCOVERDIR=$GOCOVERDIR ./juicefs format $META_URL myjfs
    GOCOVERDIR=$GOCOVERDIR ./juicefs mount -d $META_URL /jfs --enable-xattr
    cat /jfs/.accesslog > accesslog &
    jobid=$!
    trap "kill -9 $jobid" EXIT
    for i in {1..1}; do
        rm $DEST_DIR1 -rf
        rm $DEST_DIR2 -rf
        sudo -u $USER GOCOVERDIR=$GOCOVERDIR ./juicefs sync -v $SOURCE_DIR1 $DEST_DIR1 $sync_option 2>&1| tee sync.log
        echo sudo -u $USER GOCOVERDIR=$GOCOVERDIR ./juicefs sync -v $SOURCE_DIR1 $DEST_DIR1 $sync_option 
        do_copy_by_sync_option $sync_option
        check_diff $DEST_DIR1 $DEST_DIR2
    done
}

do_copy_by_sync_option(){
    sync_option=$@
    preserve="timestamps"
    no_preserve=""
    if [[ "$sync_option" =~ "--perms" ]]; then
        preserve+="mode,ownership"
    else
        no_preserve+="mode,ownership"
    fi
    if [[ "$sync_option" =~ "--links" ]]; then
       preserve+=",links"
    fi
    cp_option="--recursive --no-dereference --preserve=$preserve --no-preserve=$no_preserve"
    rm -rf $DEST_DIR2 
    sudo -u $USER cp  $SOURCE_DIR1 $DEST_DIR2 $cp_option
    echo sudo -u $USER cp  $SOURCE_DIR1 $DEST_DIR2 $cp_option
}

do_update(){
    sync_option=$@
    sudo -u $USER MAX_EXAMPLE=$MAX_EXAMPLE SEED=$SEED DERANDOMIZE=true CLEAN_DIR=False ROOT_DIR1=$SOURCE_DIR1 ROOT_DIR2=$SOURCE_DIR2 python3 .github/scripts/fsrand2.py
    for i in {1..10}; do
        sudo -u $USER GOCOVERDIR=$GOCOVERDIR ./juicefs sync -v $SOURCE_DIR1 $DEST_DIR1 $sync_option  2>&1| tee sync.log || true
        echo sudo -u $USER GOCOVERDIR=$GOCOVERDIR ./juicefs sync -v $SOURCE_DIR1 $DEST_DIR1 $sync_option
        if grep -q "Failed to delete" sync2.log; then
            echo "failed to delete, retry sync"
        else
            echo "sync delete success"
            break
        fi
    done
    do_copy_by_sync_option $sync_option
    check_diff $DEST_DIR1 $DEST_DIR2
}


check_diff(){
    dir1=$1
    dir2=$2
    diff -ur --no-dereference $dir1 $dir2
    count=$(find $dir2 -type f -name "*.*.tmp*" | wc -l)
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
         