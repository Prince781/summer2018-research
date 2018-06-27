#!/bin/sh

# http://cloudsuite.ch/pages/benchmarks/mediastreaming/

# This benchmark uses the Nginx web server as a streaming server for hosted
# videos of various lengths and qualities. The client, based on httperf’s
# wsesslog session generator, generates a request mix for different videos, to
# stress the server.

# The benchmark has two tiers: the server and the clients. The server runs
# Nginx, and the clients send requests to stream videos from the server. Each
# tier has its own image which is identified by its tag.

source ./basic.sh

retvals=()

# pull resources
echo "Getting resources ..."

docker pull cloudsuite/media-streaming:dataset
retvals+=($?)

docker pull cloudsuite/media-streaming:server
retvals+=($?)

echo "...done."

for rv in ${retvals[@]}; do
    if [ "$rv" -ne "0" ]; then
        exit 1
    fi
done

network=
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

containers+=( $(docker create --name streaming_dataset \
    cloudsuite/media-streaming:dataset) )

network=$(docker network create streaming_network)

containers+=( $(docker run -d --name streaming_server \
    --volumes-from streaming_dataset --net streaming_network \
    cloudsuite/media-streaming:server) )

docker run -t --name=streaming_client -v $(pwd)/mediastreaming-output:/output \
    --volumes-from streaming_dataset --net streaming_network \
    cloudsuite/media-streaming:client streaming_server

# cleanup
