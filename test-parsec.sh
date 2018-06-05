#!/bin/bash

if [ $UID -ne 0 ]; then
	echo "This script must be run as root."
	exit 1
fi

# get_runtime
function get_runtime() {
	grep "QUERY TIME" | sed "s/^.*QUERY TIME: \\?\\([0-9.]\\+\\) seconds.*$/\\1/"
}

# average (list)
function avg() {
	echo ${@:1} | tr " " "\\n" | awk '{sum+=$1}END{print (sum/NR)}'
}

# stdev (list)
function stdev() {
	echo ${@:1} | tr " " "\\n" | awk '{sum+=$1; sumsq+=$1*$1}END{print sqrt(sumsq/NR - (sum/NR)**2)}' 
}

function cleanup() {
	if [[ $(pwd) = /u/$(whoami)/* ]] || [[ $(pwd) = /localhost/$(whoami)/* ]]; then
		find -type f -user root -exec rm -f {} \; .
		find -type d -user root -exec rm -rf {} \; .
	else
		echo "Refusing to destroy contents of non-user directory $PWD"
	fi
}

# run_test <appname> <cmd>
function run_test() {
	local appname=$1
	local cmd=${@:2}
	local stats=`readlink -f stats/${appname}-runtimes.txt`
	local perf_stats=`readlink -f stats/${appname}-rhm.txt`
	local task_mapper=`readlink -f ./Task_mapper2`
	local colocated_sched=`readlink -f colocated.sched`
	local spread_sched=`readlink -f spread.sched`
	local count=4

        if [ ! -e $task_mapper ]; then
            make CFLAGS=-std=gnu99 Task_mapper2
        fi

        if [ ! -e $(dirname $stats) ]; then
            mkdir -p $(dirname $stats)
        fi

        if [ ! -e $colocated_sched ]; then
            echo "$colocated_sched does not exist!"
            exit 1
        fi

        if [ ! -e $spread_sched ]; then
            echo "$spread_sched does not exist!"
            exit 1
        fi

	cd parsec-3.0

	export PATH=$PATH:$(readlink -f bin)
	export PARSECDIR=$(readlink -f .)

	trap "{ cleanup; rm -f ${appname}-pipe; kill -s TERM \$(pgrep -u root Task_mapper2); }" EXIT SIGINT SIGTERM

	chown $SUDO_USER $stats
	chown $SUDO_USER $perf_stats
	cat <(echo $appname) <(perl -e "printf '-' x ($(wc -m <<< $appname) - 1)") <(echo "") <(echo "Command: $cmd") <(echo "") | tee $stats $perf_stats 1>/dev/null

	schednames=('Colocated' 'Spread')
	schedules=($colocated_sched $spread_sched)

	# try with colocated.sched
	for s in $(seq 0 $((${#schednames[@]}-1))); do
		echo ${schednames[$s]}: >> $stats
		echo ${schednames[$s]}: >> $perf_stats
		$task_mapper $appname ${schedules[$s]} &
		local child_pid=$!
		local runtimes=()

		for i in $(seq 1 $count); do
			tm=$($cmd 2>&1 | get_runtime)
			runtimes+=($tm)
			echo "$tm s" >> $stats
		done

		echo "" >> $stats
		echo "`avg ${runtimes[@]}` s (avg) +/- `stdev ${runtimes[@]}`" >> $stats
		echo "" >> $stats

		# count REMOTE_HIT_MODIFIED (r10d3) hardware counter
		mkfifo ${appname}-pipe
		cat ${appname}-pipe >> $perf_stats &
		perf stat -e r10d3 -a --per-core -o ${appname}-pipe $cmd 1>/dev/null
		rm ${appname}-pipe

		kill -s TERM $child_pid
		echo "Waiting for process $child_pid to terminate..."
		wait $child_pid
		echo "...done"
	done

	cd ..

	exit 0
}

run_test ferret parsecmgmt -a run -p ferret -n 24 -i native
