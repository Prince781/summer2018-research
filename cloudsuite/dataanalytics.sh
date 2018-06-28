#!/bin/sh

# http://cloudsuite.ch/pages/benchmarks/dataanalytics/

# The explosion of accessible human-generated information necessitates
# automated analytical processing to cluster, classify, and filter this
# information. The MapReduce paradigm has emerged as a popular approach to
# handling large-scale analysis, farming out requests to a cluster of nodes
# that first perform filtering and transformation of the data (map) and then
# aggregate the results (reduce). The Data Analytics benchmark is included in
# CloudSuite to cover the increasing importance of machine learning tasks
# analyzing large amounts of data in datacenters using the MapReduce framework.
# It is composed of Mahout, a set of machine learning libraries, running on top
# of Hadoop, an open-source implementation of MapReduce.

# The benchmark consists of running a Naive Bayes classifier on a Wikimedia
# dataset. It uses Hadoop version 2.7.3 and Mahout version 0.12.2.

source ./basic.sh

retvals=()

# pull resources
echo "Getting resources ..."

docker pull cloudsuite/hadoop
retvals+=($?)

docker pull cloudsuite/data-analytics
retvals+=($?)

echo "...done."

for rv in ${retvals[@]}; do
    if [ "$rv" -ne "0" ]; then
        exit 1
    fi
done

network=$(docker network create hadoop-net)
containers=()

if [ "$?" -ne "0" ]; then
    exit 1
fi

cleanup() {
    echo "Stopping containers..."
    docker stop ${containers[@]}
    echo "...done."
    echo "Removing ..."
    docker rm ${containers[@]}
    echo "Removing network ..."
    docker network rm $network
    echo "...done."
}

trap "{ cleanup; exit; }" EXIT TERM QUIT INT

containers+=( $(docker run -d --net $network --name master --hostname master \
    cloudsuite/data-analytics master) )

if [ "$?" -ne "0" ]; then
    exit 1
fi

echo "Sleeping for a bit"
sleep 5

echo "Starting slaves ..."
for i in {1..4}; do
    name=slave$(printf %02d $i)
    containers+=( $(docker run -d --net $network \
        --name $name --hostname $name cloudsuite/hadoop slave) )
    if [ "$?" -ne "0" ]; then
        exit 1
    fi
    sleep 1
done
echo "... done."

echo "Running benchmark"
docker exec master benchmark

# cleanup
