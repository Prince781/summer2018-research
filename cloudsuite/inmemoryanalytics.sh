#!/bin/sh

# http://cloudsuite.ch/pages/benchmarks/inmemoryanalytics/

# This benchmark uses Apache Spark and runs a collaborative filtering algorithm
# in-memory on a dataset of user-movie ratings. The metric of interest is the
# time in seconds of computing movie recommendations.
# 
# The explosion of accessible human-generated information necessitates automated
# analytical processing to cluster, classify, and filter this information.
# Recommender systems are a subclass of information filtering system that seek to
# predict the ‘rating’ or ‘preference’ that a user would give to an item.
# Recommender systems have become extremely common in recent years, and are
# applied in a variety of applications. The most popular ones are movies, music,
# news, books, research articles, search queries, social tags, and products in
# general. Because these applications suffer from I/O operations, nowadays, most
# of them are running in memory. This benchmark runs the alternating least
# squares (ALS) algorithm which is provided by Spark MLlib.

source ./basic.sh

retvals=()

# pull resources
echo "Getting resources ..."

docker pull cloudsuite/in-memory-analytics
retvals+=($?)
docker pull cloudsuite/movielens-dataset
retvals+=($?)

echo "...done."

for rv in ${retvals[@]}; do
    if [ "$rv" -ne "0" ]; then
        exit 1
    fi
done

containers=()

cleanup() {
    echo "Stopping containers..."
    docker stop ${containers[@]}
    echo "...done."
    echo "Removing ..."
    docker rm ${containers[@]}
    echo "...done."
}

trap "{ cleanup; exit; }" EXIT TERM QUIT INT

containers+=( $(docker create --name data cloudsuite/movielens-dataset) )

docker run --rm --volumes-from data cloudsuite/in-memory-analytics \
    /data/ml-latest-small /data/myratings.csv

# cleanup
