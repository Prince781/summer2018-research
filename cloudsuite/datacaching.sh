#!/bin/sh

source ./basic.sh

caching_network=$(docker network create caching_network)
echo "Created network"

if [ "$?" -ne "0" ]; then
    exit 1
fi

# pull resources
echo "Getting resources ..."

docker pull cloudsuite/data-caching:server
docker pull cloudsuite/data-caching:client

echo "...done."

servers=()

cleanup() {
    echo "Stopping servers ..."
    docker stop ${servers[@]}
    echo "...done."
    echo "Removing servers ..."
    docker rm ${servers[@]}
    echo "...done."
    echo "Removing network ..."
    docker network rm $caching_network
    echo "...done."
}

trap "{ cleanup; exit; }" EXIT TERM QUIT INT

echo "Creating servers ..."
for i in {1..4}; do
    name=dc-server$i
    servers+=( $(docker run --name $name --net caching_network \
    -d cloudsuite/data-caching:server -t 4 -m 4096 -n 550) )
    echo "$name"
    if [ "$?" -ne "0" ]; then
        exit 1
    fi
done
echo "...done."

cmds="
cd /usr/src/memcached/memcached_client/;
./loader -a ../twitter_dataset/twitter_dataset_unscaled \
-o ../twitter_dataset/twitter_dataset_30x -s docker_servers.txt -w 4 \
-S 4 -D 4096 -j -T 1;
./loader -a ../twitter_dataset/twitter_dataset_30x \
-s docker_servers.txt -g 0.8 -T 1 -c 200 -w 8
"

# TODO: determine rps, add [-r (0.9*rps)] to the last command, and run
# it again.

echo "cmds: $cmds"

echo "Running dc-client ..."
docker run --rm -it --name dc-client \
--net caching_network cloudsuite/data-caching:client bash -c "$cmds"
echo "...done."

# cleanup
