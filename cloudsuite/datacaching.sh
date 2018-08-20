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

frac_server=0.8 # portion of available memory 
total_mem_mb=$(grep MemAvailable /proc/meminfo | awk '{print $2/1024}') # MemAvailable MB
N_SERVERS=4
server_mem_mb=$(echo "scale=2;($frac_server * $total_mem_mb) / $N_SERVERS" | bc -l)
server_names=   # used for docker_servers.txt

echo "Creating $N_SERVERS servers with $server_mem_mb MB each (total of $(echo "scale=2;$frac_server * 100" | bc -l)% of available mem) ..."
for i in $(seq 1 $N_SERVERS); do
    name=dc-server$i
    servers+=( $(docker run --name $name --net caching_network \
        -d cloudsuite/data-caching:server -t `nproc` -m $server_mem_mb -n 550) )
    server_names+=($name)
    echo "$name"
    if [ "$?" -ne "0" ]; then
        exit 1
    fi
done
echo "...done."

# The original dataset consumes 300MB of server memory, while the recommended
# scaled dataset requires around 10GB of main memory dedicated to the Memcached
# server (scaling factor of 30).
# Instead, we will compute the scaling factor based on the amount of memory
# available on the system.
scaling_factor=$(echo "define max(a,b){if(a>b) return (a) else return (b)};scale=4;max(1, (1 - $frac_server) * $total_mem_mb / 300)" | bc -l)

echo "Scaling the 300 MB Twitter dataset ${scaling_factor}x = $total_mem_mb MB..."

cmds="
cd /usr/src/memcached/memcached_client/;
cat /dev/null > docker_servers.txt;
for server in ${server_names[@]}; do echo \"\$server, 11211\" >> docker_servers.txt; done;
echo \"Scaling Twitter dataset ...\";
./loader -a ../twitter_dataset/twitter_dataset_unscaled \
-o ../twitter_dataset/twitter_dataset_${scaling_factor}x -s docker_servers.txt -w `nproc` \
-S ${scaling_factor} -D $server_mem_mb -j -T 1;
echo \"Running the benchmark with maximum throughput ...\";
./loader -a ../twitter_dataset/twitter_dataset_${scaling_factor}x \
-s docker_servers.txt -g 0.8 -T 1 -c 200 -w 8 | tee ./memcached-nservers-${N_SERVERS}-mem-${server_mem_mb}-MB.log
"

# the first call to ./loader creates the scaled file, and the second
# call runs the server

# TODO: determine rps, add [-r (0.9*rps)] to the last command, and run
# it again.

echo "cmds: $cmds"


#    -v $(pwd)/memcached-logs:/usr/src/memcached/memcached_client \
echo "Running dc-client ..."
docker run -it --name dc-client --net caching_network \
    cloudsuite/data-caching:client \
    bash -c "$cmds"
echo "...done."

# cleanup
