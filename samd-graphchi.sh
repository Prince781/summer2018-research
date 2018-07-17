#!/bin/bash

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
        local cdir=$1
	if [[ $cdir = /u/${SUDO_USER}/* ]] || [[ $cdir = /localdisk/${SUDO_USER}/* ]]; then
		find $cdir -type f -user root -exec rm -f {} \;
		find $cdir -type d -user root -exec rm -rf {} \;
	else
		echo "Refusing to destroy contents of non-user directory $cdir"
	fi
}

# run_test <appname> <runtime-param> <cmd>
function run_test() {
	local appname=$1
        local runtime_param=$2
	local cmd=${@:3}
	local stats=`readlink -fm stats/samd/graphchi/${appname}-runtimes.txt`
	local count=8

        if [ ! -e $(dirname $stats) ]; then
            mkdir -p $(dirname $stats)
        fi

	cd graphchi-cpp

        export GRAPHCHI_DIR=$(pwd)
	trap "{ cleanup $GRAPHCHI_DIR; }" EXIT SIGINT SIGTERM

        if [ $UID -eq 0 ]; then
            chown $SUDO_USER $stats
            chgrp $SUDO_GROUP $stats
        fi
	cat <(echo $appname) <(perl -e "printf '-' x ($(wc -m <<< $appname) - 1)") <(echo "") <(echo "Command: $cmd") <(echo "") > $stats

        declare -A schedules
        schedules=( ["With samd"]="sam-launch" \
            ["Without samd"]="" )

	# try with colocated.sched
	for s in "${!schedules[@]}"; do
		echo $s: >> $stats
                local actual_cmd=(${schedules[$s]} $cmd)
		local runtimes=()

                for i in $(seq 1 $count); do
                        echo edgelist | ${actual_cmd[@]}
			tm=$(get_runtime $runtime_param)
			runtimes+=($tm)
			echo "$tm s" >> $stats
		done

		echo "" >> $stats
		echo "`avg ${runtimes[@]}` s (avg) +/- `stdev ${runtimes[@]}`" >> $stats
		echo "" >> $stats
	done

	cd ..
}

# run_test pagerank runtime bin/example_apps/pagerank file /u/pferro/Downloads/soc-LiveJournal1.txt niters 10

# run_test communitydetection runtime bin/example_apps/communitydetection file /u/pferro/Downloads/soc-LiveJournal1.txt niters 10 execthreads 22

# run_test connectedcomponents runtime bin/example_apps/connectedcomponents file /u/pferro/Downloads/soc-LiveJournal1.txt niters 10

# run_test minimumspanningforest msf-total-runtime bin/example_apps/minimumspanningforest file /u/pferro/Downloads/soc-LiveJournal1.txt niters 10

# run_test als_edgefactors runtime bin/example_apps/matrix_factorization/als_edgefactors file /u/pferro/Downloads/netflix.mm niters 10 

# run_test stronglyconnectedcomponents runtime bin/example_apps/stronglyconnectedcomponents file /u/pferro/Downloads/soc-LiveJournal1.txt niters 10

# run_test trianglecounting runtime bin/example_apps/trianglecounting file /localdisk/pferro/Downloads/soc-LiveJournal1.txt niters 10 execthreads 24

# run_test sgd runtime toolkits/collaborative_filtering/sgd --training=/u/pferro/Downloads/netflix/netflix_train.txt --validation=/u/pferro/Downloads/netflix/netflix_test.txt --sgd_lambda=1e-4 --sgd_gamma=1e-4 --minval=1 --maxval=5 --max_iter=6 --execthreads=22

# run_test biassgd runtime toolkits/collaborative_filtering/biassgd --training=/u/pferro/Downloads/netflix/netflix_train.txt --validation=/u/pferro/Downloads/netflix/netflix_test.txt --biassgd_lambda=1e-4 --biassgd_gamma=1e-4 --minval=1 --maxval=5 --max_iter=6 --execthreads=22

# run_test svdpp runtime toolkits/collaborative_filtering/svdpp --training=/u/pferro/Downloads/netflix/netflix_train.txt --validation=/u/pferro/Downloads/netflix/netflix_test.txt --biassgd_lambda=1e-4 --biassgd_gamma=1e-4 --minval=1 --maxval=5 --max_iter=6 --execthreads=22

run_test als runtime toolkits/collaborative_filtering/als --training=/u/pferro/Downloads/netflix/netflix_train.txt --validation=/u/pferro/Downloads/netflix/netflix_test.txt --lambda=1e-4 --minval=1 --maxval=5 --max_iter=6 --execthreads=22
