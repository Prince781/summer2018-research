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

# run_test <appname> <runtime-f> <cmd>
function run_test() {
	local appname=$1
        local runtime_f=$2
	local cmd=${@:3}
	local stats=`readlink -f stats/${appname}-runtimes.txt`
	local perf_stats=`readlink -f stats/${appname}-rhm.txt`
	local task_mapper=`readlink -f ./Task_mapper2`
	local count=4

        if [ ! -e $task_mapper ]; then
            make CFLAGS=-std=gnu99 LDFLAGS=-lm Task_mapper2
        fi

        if [ ! -e $(dirname $stats) ]; then
            mkdir -p $(dirname $stats)
        fi

	cd parsec-3.0

	export PATH=$PATH:$(readlink -f bin)
	export PARSECDIR=$(readlink -f .)

	trap "{ cleanup $PARSECDIR; rm -f ${appname}-pipe; pkill -u root,pferro --signal TERM Task_mapper2; exit 1; }" EXIT SIGINT SIGTERM

        if [ $UID -eq 0 ]; then
            chown $SUDO_USER $stats
            chown $SUDO_USER $perf_stats
        fi
	cat <(echo $appname) <(perl -e "printf '-' x ($(wc -m <<< $appname) - 1)") <(echo "") <(echo "Command: $cmd") <(echo "") | tee $stats $perf_stats 1>/dev/null

	schednames=('Colocated' 'Colocated2' 'Colocated3' 'Spread' 'default')
	schedules=('default:colocated' 'default:colocated2' 'default:colocated3' 'default:spread')

	# try with colocated.sched
	for s in $(seq 0 $((${#schednames[@]}-1))); do
		echo ${schednames[$s]}: >> $stats
		echo ${schednames[$s]}: >> $perf_stats
                if "${schednames[$s]}" -eq "default"; then
                    echo "Running default scheduler" &
                else
                    $task_mapper $appname ${schedules[$s]} &
                fi
		local child_pid=$!
		local runtimes=()

		for i in $(seq 1 $count); do
			tm=$($cmd | $runtime_f)
			runtimes+=($tm)
			echo "$tm s" >> $stats
		done

		echo "" >> $stats
		echo "`avg ${runtimes[@]}` s (avg) +/- `stdev ${runtimes[@]}`" >> $stats
		echo "" >> $stats
                
                if [ $UID -eq 0 ]; then
                    # count REMOTE_HIT_MODIFIED (r10d3) hardware counter
                    mkfifo ${appname}-pipe
                    cat ${appname}-pipe >> $perf_stats &
                    perf stat -e r10d3 -e r412e -a --per-core -o ${appname}-pipe $cmd 1>/dev/null
                    rm ${appname}-pipe
                else
                    echo "Warning: Skipping REMOTE_HIT_MODIFIED and LLC_MISSES tests because we lack permissions to run perf-stat"
                fi

		kill -s TERM $child_pid
		echo "Waiting for process $child_pid to terminate..."
		wait $child_pid
		echo "...done"
	done

	cd ..
}

# run_test ferret get_runtime parsecmgmt -a run -p ferret -n 24 -i native
run_test x264 get_runtime2 parsecmgmt -a run -p x264 -n 96 -i native
