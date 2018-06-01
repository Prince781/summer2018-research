#!/bin/bash

if [ $UID -ne 0 ]; then
	echo "This script must be run as root."
	exit 1
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

# run_test <appname> <runtime-param> <cmd>
function run_test() {
	local appname=$1
	local runtime_param=$2
	local cmd=${@:3}
	local stats=`readlink -f stats/${appname}-runtimes.txt`
	local perf_stats=`readlink -f stats/${appname}-rhm.txt`
	local task_mapper=`readlink -f ./Task_mapper2`
	local colocated_sched=`readlink -f colocated.sched`
	local spread_sched=`readlink -f spread.sched`
	local count=4

	cd graphchi-cpp

	chown $SUDO_USER $stats
	chown $SUDO_USER $perf_stats
	cat <(echo $appname) <(perl -e "printf '-' x ($(wc -m <<< $appname) - 1)") <(echo "") | tee $stats $perf_stats 1>/dev/null

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
			echo edgelist | $cmd
			tm=$(get_runtime $runtime_param)
			runtimes+=($tm)
			echo "$tm s" >> $stats
		done

		echo "" >> $stats
		echo "`avg ${runtimes[@]}` s (avg) +/- `stdev ${runtimes[@]}`" >> $stats
		echo "" >> $stats

		# count REMOTE_HIT_MODIFIED (r10d3) hardware counter
		mkfifo ${appname}-pipe
		cat ${appname}-pipe >> $perf_stats &
		echo edgelist | perf stat -e r10d3 -a --per-core -o ${appname}-pipe $cmd
		rm ${appname}-pipe

		kill -s TERM $child_pid
		echo "Waiting for process $child_pid to terminate..."
		wait $child_pid
		echo "...done"
	done

	cd ..
}

run_test pagerank runtime bin/example_apps/pagerank file /u/pferro/Downloads/soc-LiveJournal1.txt niters 10

# run_test communitydetection runtime bin/example_apps/communitydetection file /u/pferro/Downloads/soc-LiveJournal1.txt niters 10 execthreads 22

# run_test connectedcomponents runtime bin/example_apps/connectedcomponents file /u/pferro/Downloads/soc-LiveJournal1.txt niters 10

# run_test minimumspanningforest msf-total-runtime bin/example_apps/minimumspanningforest file /u/pferro/Downloads/soc-LiveJournal1.txt niters 10

# run_test als_edgefactors runtime bin/example_apps/matrix_factorization/als_edgefactors file /u/pferro/Downloads/netflix.mm niters 10 

# run_test stronglyconnectedcomponents runtime bin/example_apps/stronglyconnectedcomponents file /u/pferro/Downloads/soc-LiveJournal1.txt niters 10

# run_test trianglecounting runtime bin/example_apps/trianglecounting file /localdisk/pferro/Downloads/soc-LiveJournal1.txt niters 10 execthreads 24

# run_test sgd runtime toolkits/collaborative_filtering/sgd --training=/u/pferro/Downloads/netflix/netflix_train.txt --validation=/u/pferro/Downloads/netflix/netflix_test.txt --sgd_lambda=1e-4 --sgd_gamma=1e-4 --minval=1 --maxval=5 --max_iter=6 --execthreads=22

# run_test biassgd runtime toolkits/collaborative_filtering/biassgd --training=/u/pferro/Downloads/netflix/netflix_train.txt --validation=/u/pferro/Downloads/netflix/netflix_test.txt --biassgd_lambda=1e-4 --biassgd_gamma=1e-4 --minval=1 --maxval=5 --max_iter=6 --execthreads=22

# run_test svdpp runtime toolkits/collaborative_filtering/svdpp --training=/u/pferro/Downloads/netflix/netflix_train.txt --validation=/u/pferro/Downloads/netflix/netflix_test.txt --biassgd_lambda=1e-4 --biassgd_gamma=1e-4 --minval=1 --maxval=5 --max_iter=6 --execthreads=22
