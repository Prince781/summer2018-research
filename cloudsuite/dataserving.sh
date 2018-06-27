#!/bin/sh

source ./basic.sh

network=$(docker network create serving_network)
echo "Created network"

if [ "$?" -ne "0" ]; then
    exit 1
fi

# pull resources
echo "Getting resources ..."

docker pull cloudsuite/data-serving:server
docker pull cloudsuite/data-serving:client

echo "...done."

server_seed=
servers=()

cleanup() {
    echo "Stopping servers ..."
    docker stop $server_seed ${servers[@]}
    echo "...done."
    echo "Removing servers ..."
    docker rm ${servers[@]}
    echo "...done."
    echo "Removing network ..."
    docker network rm $network
    echo "...done."
}

trap "{ cleanup; exit; }" EXIT TERM QUIT INT

echo "Creating servers ..."

server_seed=$(docker run --name cassandra-server-seed \
    --net serving_network cloudsuite/data-serving:server)

if [ "$?" -ne "0" ]; then
    exit 1
fi

for i in {1..4}; do
    name=cassandra-server$i
    echo "$name"
    servers+=( $(docker run --name $name --net serving_network \
        -e CASSANDRA_SEEDS=cassandra-server-seed cloudsuite/data-serving:server) )
    if [ "$?" -ne "0" ]; then
        exit 1
    fi
done
echo "...done."

echo "Running client ..."

client=$(docker run --name cassandra-client --net serving_network \
    cloudsuite/data-serving:client cassandra-server-seed,$(echo ${servers[@]} | sed 's/ /,/g'))

# cleanup
