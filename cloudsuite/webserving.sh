#!/bin/sh

# http://cloudsuite.ch/pages/benchmarks/webserving/

# Web Serving is a main service in the cloud. Traditional web services with
# dynamic and static content are moved into the cloud to provide
# fault-tolerance and dynamic scalability by bringing up the needed number of
# servers behind a load balancer. Although many variants of the traditional web
# stack are used in the cloud (e.g., substituting Apache with other web server
# software or using other language interpreters in place of PHP), the
# underlying service architecture remains unchanged. Independent client
# requests are accepted by a stateless web server process which either directly
# serves static files from disk or passes the request to a stateless middleware
# script, written in a high-level interpreted or byte-code compiled language,
# which is then responsible for producing dynamic content. All the state
# information is stored by the middleware in backend databases such as cloud
# NoSQL data stores or traditional relational SQL servers supported by
# key-value cache servers to achieve high throughput and low latency. This
# benchmark includes a social networking engine (Elgg) and a client implemented
# using the Faban workload generator.

source ./basic.sh

retvals=()

# pull resources
echo "Getting resources ..."

docker pull cloudsuite/web-serving:db_server
retvals+=($?)

docker pull cloudsuite/web-serving:memcached_server
retvals+=($?)

docker pull cloudsuite/web-serving:web_server
retvals+=($?)

docker pull cloudsuite/web-serving:faban_client
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

device=wlp6s0       # change this depending on the hardware on your system
ip_info=$(ip addr show dev ${device} | grep 'inet ')

if [ "$?" -ne "0" ]; then
    exit 1
fi

WEB_SERVER_IP=$(echo $ip_info | grep 'inet ' | awk '{print $2}' \
    | sed 's/\(\([[:digit:]]\{1,3\}\.\)\{3\}[[:digit:]]\{1,3\}\)\(\/.*\)\?/\1/g')
DATABASE_SERVER_IP=127.0.0.1
MEMCACHED_SERVER_IP=127.0.0.1
MAX_PM_CHILDREN=80          # default = 80
LOAD_SCALE=7                # default = 7

echo "Web server IP is $WEB_SERVER_IP"

echo "Starting server containers..."
containers+=( $(docker run -dt --net=host --name=mysql_server cloudsuite/web-serving:db_server ${WEB_SERVER_IP}) )

if [ "$?" -ne "0" ]; then
    exit 1
fi

containers+=( $(docker run -dt --net=host --name=memcache_server cloudsuite/web-serving:memcached_server) )

if [ "$?" -ne "0" ]; then
    exit 1
fi

containers+=( $(docker run -dt --net=host --name=web_server cloudsuite/web-serving:web_server \
    /etc/bootstrap.sh ${DATABASE_SERVER_IP} ${MEMCACHED_SERVER_IP} ${MAX_PM_CHILDREN}) )

if [ "$?" -ne "0" ]; then
    exit 1
fi

echo "... done."

echo "Running client ..."
containers+=(faban_client)
docker run --net=host --name=faban_client -v $(pwd)/webserving-output:/faban/output \
    cloudsuite/web-serving:faban_client \
    ${WEB_SERVER_IP} ${LOAD_SCALE}

# cleanup
