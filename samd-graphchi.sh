#!/bin/bash

pids=()

commands=()

commands+=("runtime bin/example_apps/pagerank file /u/pferro/Downloads/soc-LiveJournal1.txt niters 10")
commands+=("runtime bin/example_apps/communitydetection file /u/pferro/Downloads/soc-LiveJournal1.txt niters 10 execthreads 22")
commands+=("runtime bin/example_apps/connectedcomponents file /u/pferro/Downloads/soc-LiveJournal1.txt niters 10")
commands+=("msf-total-runtime bin/example_apps/minimumspanningforest file /u/pferro/Downloads/soc-LiveJournal1.txt niters 10")
commands+=("runtime bin/example_apps/matrix_factorization/als_edgefactors file /u/pferro/Downloads/netflix.mm niters 10")
commands+=("runtime bin/example_apps/stronglyconnectedcomponents file /u/pferro/Downloads/soc-LiveJournal1.txt niters 10")
commands+=("runtime bin/example_apps/trianglecounting file /localdisk/pferro/Downloads/soc-LiveJournal1.txt niters 10 execthreads 24")
commands+=("runtime toolkits/collaborative_filtering/sgd --training=/u/pferro/Downloads/netflix/netflix_train.txt --validation=/u/pferro/Downloads/netflix/netflix_test.txt --sgd_lambda=1e-4 --sgd_gamma=1e-4 --minval=1 --maxval=5 --max_iter=6 --execthreads=22")
commands+=("runtime toolkits/collaborative_filtering/biassgd --training=/u/pferro/Downloads/netflix/netflix_train.txt --validation=/u/pferro/Downloads/netflix/netflix_test.txt --biassgd_lambda=1e-4 --biassgd_gamma=1e-4 --minval=1 --maxval=5 --max_iter=6 --execthreads=22")
commands+=("runtime toolkits/collaborative_filtering/svdpp --training=/u/pferro/Downloads/netflix/netflix_train.txt --validation=/u/pferro/Downloads/netflix/netflix_test.txt --biassgd_lambda=1e-4 --biassgd_gamma=1e-4 --minval=1 --maxval=5 --max_iter=6 --execthreads=22")
commands+=("runtime toolkits/collaborative_filtering/als --training=/u/pferro/Downloads/netflix/netflix_train.txt --validation=/u/pferro/Downloads/netflix/netflix_test.txt --lambda=1e-4 --minval=1 --maxval=5 --max_iter=6 --execthreads=22")

# get_runtime <param>
function get_runtime() {
    local param=$1
    grep "\\.$param=" graphchi_metrics.txt | sed "s/^.*\\.$param=\\([0-9.]\\+\\).*$/\\1/"
}

# average (list)
function avg() {
    echo ${@:1} | tr " " "\\n" | awk '{sum+=$1}END{print (sum/NR)}'
}

# stdev (list)
function stdev() {
    echo ${@:1} | tr " " "\\n" | awk '{sum+=$1; sumsq+=$1*$1}END{print sqrt(sumsq/NR - (sum/NR)**2)}' 
}

# cleanup $dir
function cleanup() {
    if (( ${#pids} > 0 )); then
        echo "There are these running processes: ${pids[@]}"
        kill -s TERM ${pids[@]}
        echo "Waiting for 5 seconds"
        sleep 5
        kill -9 ${pids[@]}
        wait ${pids[@]}
    fi

    local cdir=$1
    if [[ $cdir = /u/${SUDO_USER}/* ]] || [[ $cdir = /localdisk/${SUDO_USER}/* ]]; then
        find $cdir -type f -user root -exec rm -f {} \;
        find $cdir -type d -user root -exec rm -rf {} \;
    else
        echo "Refusing to destroy contents of non-user directory $cdir"
    fi
}

# test_cmd <stats> <runtime_param> <actual_cmd> ...
function test_cmd() {
    local stats=$1
    local runtime_param=$2
    local actual_cmd=${@:3}
    local runtimes=()
    local count=1

    for i in $(seq 1 $count); do
        echo edgelist | ${actual_cmd[@]}
        tm=$(get_runtime $runtime_param)
        runtimes+=($tm)
        echo "$tm s" >> $stats
    done

    echo "" >> $stats
    echo "`avg ${runtimes[@]}` s (avg) +/- `stdev ${runtimes[@]}`" >> $stats
    echo "" >> $stats
}

# run_tests
function run_tests() {
    cd graphchi-cpp

    if (( $? )); then
        return
    fi

    export GRAPHCHI_DIR=$(pwd)
    trap "{ cleanup $GRAPHCHI_DIR; }" EXIT SIGINT SIGTERM

    if [ $UID -eq 0 ]; then
        chown $SUDO_USER $stats
        chgrp $SUDO_GROUP $stats
    fi

    for prefix in {sam-launch,}; do
        pids=()
        for cmd in "${commands[@]}"; do
            cmd=($cmd)  # convert to array
            local runtime_param=${cmd[1]}
            local appname=`basename $runtime_param`
            local stats=`readlink -fm stats/samd/graphchi/${prefix}/${appname}-runtimes.txt`
            local actual_cmd=($prefix ${cmd[@]:1})

            if [ ! -e $(dirname $stats) ]; then
                mkdir -p $(dirname $stats)
            fi

            cat <(echo $appname) <(perl -e "printf '-' x ($(wc -m <<< $appname) - 1)") <(echo "") <(echo "Command: $cmd") <(echo "") > $stats
            test_cmd $stats $runtime_param ${actual_cmd[@]} &>/dev/null &
            pids+=($!)
        done
        if [ -z $prefix ]; then
            echo "Running control test"
        else
            echo "Running experimental test '$prefix'"
        fi
        wait ${pids[@]}
        pids=()
    done

    cd ..
}

run_tests
