#!/bin/bash

if [ $UID -ne 0 ]; then
    echo "This script should be run as root."
    sleep 1
fi

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
#        local cdir=$1
#	if [[ $cdir = /u/${SUDO_USER}/* ]] || [[ $cdir = /localdisk/${SUDO_USER}/* ]]; then
#		find $cdir -type f -user root -exec rm -f {} \;
#		find $cdir -type d -user root -exec rm -rf {} \;
#	else
#		echo "Refusing to destroy contents of non-user directory $cdir"
#	fi
    return 0
}

curdir=$(pwd)

# run_test <test name> <appname> <runtime-f> <args>
function run_test() {
        local testname=$1
	local appname=$2
        local runtime_f=$3
	local cmd=${@:4}
	local stats=`readlink -fm stats/graphchi/${appname}/${testname}/runtimes-taskset.txt`
	local perf_stats=`readlink -fm stats/graphchi/${appname}/${testname}/perf-taskset.txt`
	local count=4       # number of trials to perform

        if [ ! -e $(dirname $stats) ]; then
            mkdir -p $(dirname $stats)
        fi

        echo "[${testname}] Running ${appname} with ${nthreads} thread(s) ..."

	cd $curdir/graphchi-cpp

	export PATH=$PATH:$(readlink -f bin)
	export PARSECDIR=$(readlink -f .)

	trap "{ cleanup $PARSECDIR; rm -f ${appname}-pipe; pkill -u root,pferro --signal TERM taskset; exit; }" EXIT SIGINT SIGTERM

        # truncate the statistics files
        cat <(hostname) <(echo $appname) <(perl -e "printf '-' x ($(wc -m <<< $appname) - 1)") <(echo "") <(echo "Command: $cmd") <(echo "") | tee $stats $perf_stats 1>/dev/null
        if [ $UID -eq 0 ]; then
            chown $SUDO_USER $stats
            chown $SUDO_USER $perf_stats
        fi

	local schedules=('0,2,4,6,8,10' '0,12,2,14,4,16' '0,2,4,1,3,5')
        # local schedules=(${@:5})

        if [ "$testname" = "serial" ]; then
            schedules=('0')
        elif [ "$testname" != "parallel" ]; then
            echo "Error: test '$testname' must be either serial or parallel"
            exit 1
        fi

	# try with colocated.sched
	for s in $(seq 0 $((${#schedules[@]}-1))); do
                echo "cpuset=${schedules[$s]}:" >> $stats
                echo "cpuset=${schedules[$s]}:" >> $perf_stats
		local runtimes=()

		for j in $(seq 1 $count); do
			tm=$(LIBC_FATAL_STDERR_=1 taskset -c ${schedules[$s]} $cmd 2>/dev/null | $runtime_f)
			runtimes+=($tm)
			echo "$tm s" >> $stats
		done

		echo "" >> $stats
		echo "`avg ${runtimes[@]}` s (avg) +/- `stdev ${runtimes[@]}`" >> $stats
		echo "" >> $stats

                local child_pids=()
                
                if [ $UID -eq 0 ]; then
                    # count REMOTE_HIT_MODIFIED (r10d3) hardware counter
                    echo "Measuring performance counters ..."
                    mkfifo ${appname}-pipe
                    cat ${appname}-pipe >> $perf_stats &
                    child_pids+=($!)
                    LIBC_FATAL_STDERR_=1 perf stat -e r10d3 -e r412e -a --per-core -o ${appname}-pipe taskset -c ${schedules[$s]} $cmd 1>/dev/null
                    rm ${appname}-pipe
                else
                    echo "Warning: Skipping REMOTE_HIT_MODIFIED and LLC_MISSES tests because we lack permissions to run perf-stat"
                fi

                if (( ${#child_pids[@]} > 0 )); then
                    kill -s TERM $child_pids
                    echo "Waiting for process(es) $child_pids to terminate..."
                    wait $child_pids
                    echo "...done"
                fi
	done

	cd $curdir
}

# test on one core
for i in {1..24}; do
    run_test serial sgd get_runtime toolkits/collaborative_filtering/sgd --training=/u/pferro/Downloads/netflix/netflix_train.txt --validation=/u/pferro/Downloads/netflix/netflix_test.txt --sgd_lambda=1e-4 --sgd_gamma=1e-4 --minval=1 --maxval=5 --max_iter=6 --execthreads=$i
    run_test serial biassgd get_runtime toolkits/collaborative_filtering/biassgd --training=/u/pferro/Downloads/netflix/netflix_train.txt --validation=/u/pferro/Downloads/netflix/netflix_test.txt --biassgd_lambda=1e-4 --biassgd_gamma=1e-4 --minval=1 --maxval=5 --max_iter=6 --execthreads=$i
    run_test serial svdpp get_runtime toolkits/collaborative_filtering/svdpp --training=/u/pferro/Downloads/netflix/netflix_train.txt --validation=/u/pferro/Downloads/netflix/netflix_test.txt --biassgd_lambda=1e-4 --biassgd_gamma=1e-4 --minval=1 --maxval=5 --max_iter=6 --execthreads=$i
    run_test serial get_runtime toolkits/collaborative_filtering/als --training=/u/pferro/Downloads/netflix/netflix_train.txt --validation=/u/pferro/Downloads/netflix/netflix_test.txt --lambda=1e-4 --minval=1 --maxval=5 --max_iter=6 --execthreads=$i
done

# test on multiple cores
for i in {1..24}; do
    run_test parallel sgd get_runtime toolkits/collaborative_filtering/sgd --training=/u/pferro/Downloads/netflix/netflix_train.txt --validation=/u/pferro/Downloads/netflix/netflix_test.txt --sgd_lambda=1e-4 --sgd_gamma=1e-4 --minval=1 --maxval=5 --max_iter=6 --execthreads=$i
    run_test parallel biassgd get_runtime toolkits/collaborative_filtering/biassgd --training=/u/pferro/Downloads/netflix/netflix_train.txt --validation=/u/pferro/Downloads/netflix/netflix_test.txt --biassgd_lambda=1e-4 --biassgd_gamma=1e-4 --minval=1 --maxval=5 --max_iter=6 --execthreads=$i
    run_test parallel svdpp get_runtime toolkits/collaborative_filtering/svdpp --training=/u/pferro/Downloads/netflix/netflix_train.txt --validation=/u/pferro/Downloads/netflix/netflix_test.txt --biassgd_lambda=1e-4 --biassgd_gamma=1e-4 --minval=1 --maxval=5 --max_iter=6 --execthreads=$i
    run_test parallel als get_runtime toolkits/collaborative_filtering/als --training=/u/pferro/Downloads/netflix/netflix_train.txt --validation=/u/pferro/Downloads/netflix/netflix_test.txt --lambda=1e-4 --minval=1 --maxval=5 --max_iter=6 --execthreads=$i
done

echo "All tests completed"
