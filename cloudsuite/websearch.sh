#!/bin/sh

# http://cloudsuite.ch/pages/benchmarks/websearch/

# This repository contains the docker image for Cloudsuite’s Web Search
# benchmark.
# 
# The Web Search benchmark relies on the Apache Solr search engine framework.
# The benchmark includes a client machine that simulates real-world clients
# that send requests to the index nodes. The index nodes contain an index of
# the text and fields found in a set of crawled websites.

source ./basic.sh

retvals=()

# pull resources
echo "Getting resources ..."

docker pull cloudsuite/web-search:server
retvals+=($?)

docker pull cloudsuite/web-search:client
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
    echo "Removing network ..."
    docker network rm $network
    echo "Stopping containers..."
    docker stop ${containers[@]}
    echo "...done."
    echo "Removing ..."
    docker rm ${containers[@]}
    echo "...done."
}

trap "{ cleanup; exit; }" EXIT TERM QUIT INT

network=$(docker network create search_network)

containers+=(server)

docker run -it --name server --net search_network -p 8983:8983 cloudsuite/web-search:server 12g 1

if [ "$?" -ne "0" ]; then
    exit 1
fi


# credit: https://www.linuxjournal.com/content/validating-ip-address-bash-script
function valid_ip()
{
    local  ip=$1
    local  stat=1

    if [[ $ip =~ ^[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}$ ]]; then
        OIFS=$IFS
        IFS='.'
        ip=($ip)
        IFS=$OIFS
        [[ ${ip[0]} -le 255 && ${ip[1]} -le 255 \
            && ${ip[2]} -le 255 && ${ip[3]} -le 255 ]]
        stat=$?
    fi
    return $stat
}

server_ip_addr=

while ! valid_ip $server_ip_addr; do
    read -rp "Enter IP Address of server: " server_ip_addr
    if ! valid_ip $server_ip_addr; then
        echo "Invalid IP Address '$server_ip_addr'"
    fi
done

containers+=(client)

docker run -it --name client --net search_network \
    cloudsuite/web-search:client $server_ip_addr 50 90 60 60 

# cleanup
