#!/bin/bash

if [ $UID -ne 0 ]; then
    echo "This script should be run as root."
    sleep 1
fi

# get_runtime
function get_runtime() {
	grep "QUERY TIME" | sed "s/^.*QUERY TIME: \\?\\([0-9.]\\+\\) seconds.*$/\\1/"
}

function get_runtime2() {
    grep "real" | sed "s/^.*real.*\\([[:digit:]]\\+\\)m\\([0-9.]\\+\\).*$/\\1\t\\2/" | awk '{ printf "%f", $1 * 60 + $2 }'
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
        local cdir=$1
	if [[ $cdir = /u/${SUDO_USER}/* ]] || [[ $cdir = /localdisk/${SUDO_USER}/* ]]; then
		find $cdir -type f -user root -exec rm -f {} \;
		find $cdir -type d -user root -exec rm -rf {} \;
	else
		echo "Refusing to destroy contents of non-user directory $cdir"
	fi
}

# run_test <test name> <appname> <nthreads> <runtime-f> <schedules>
function run_test() {
        local testname=$1
	local appname=$2
        local nthreads=$3
        local runtime_f=$4
	# local cmd=${@:5}
        local cmd="parsecmgmt -a run -p ${appname} -n ${nthreads} -i native"
	local stats=`readlink -fm stats/parsec/${appname}/${testname}/runtimes-taskset-n${nthreads}.txt`
	local perf_stats=`readlink -fm stats/parsec/${appname}/${testname}/perf-taskset-n${nthreads}.txt`
	local count=4       # number of trials to perform

        if [ ! -e $(dirname $stats) ]; then
            mkdir -p $(dirname $stats)
        fi

	cd parsec-3.0

	export PATH=$PATH:$(readlink -f bin)
	export PARSECDIR=$(readlink -f .)

	trap "{ cleanup $PARSECDIR; rm -f ${appname}-pipe; pkill -u root,pferro --signal TERM taskset; exit; }" EXIT SIGINT SIGTERM

        if [ $UID -eq 0 ]; then
            chown $SUDO_USER $stats
            chown $SUDO_USER $perf_stats
        fi

        # truncate the statistics files
        cat <(hostname) <(echo $appname) <(perl -e "printf '-' x ($(wc -m <<< $appname) - 1)") <(echo "") <(echo "Command: $cmd") <(echo "") | tee $stats $perf_stats 1>/dev/null

	# schedules=('0,2,4,6,8,10' '0,12,2,14,4,16' '0,2,4,1,3,5')
        local schedules=(${@:5})

	# try with colocated.sched
	for s in $(seq 0 $((${#schedules[@]}-1))); do
                echo "cpuset=${schedules[$s]}:" >> $stats
                echo "cpuset=${schedules[$s]}:" >> $perf_stats
		local runtimes=()

		for i in $(seq 1 $count); do
			tm=$(taskset -c ${schedules[$s]} $cmd | $runtime_f)
			runtimes+=($tm)
			echo "$tm s" >> $stats
		done

		echo "" >> $stats
		echo "`avg ${runtimes[@]}` s (avg) +/- `stdev ${runtimes[@]}`" >> $stats
		echo "" >> $stats

                local child_pids=()
                
                if [ $UID -eq 0 ]; then
                    # count REMOTE_HIT_MODIFIED (r10d3) hardware counter
                    mkfifo ${appname}-pipe
                    cat ${appname}-pipe >> $perf_stats &
                    child_pids+=($!)
                    perf stat -e r10d3 -e r412e -a --per-core -o ${appname}-pipe taskset -c ${schedules[$s]} $cmd 1>/dev/null
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

	cd ..
}

# test on one core
#for i in {1,2,16,24}; do
#    run_test serial ferret $i get_runtime 0
#    run_test serial x264 $i get_runtime2 0 
#done

# test on multiple cores
for i in {1,2,4,14,16,24}; do
    run_test parallel ferret $i get_runtime 0,2,4,6,8,10 0,12,2,14,4,16 0,2,4,1,3,5
#    run_test parallel x264 $i get_runtime2 0,2,4,6,8,10 0,12,2,14,4,16 0,2,4,1,3,5
done

