if [ "$UID" -ne "0" ]; then
    echo "Run this script as root."
    exit 1
fi

tries=0
while ! systemctl is-active --quiet docker; do
    if (( $tries >= 3 )); then
        echo "Quitting after three tries."
        exit 1
    fi
    echo "docker is not running! Starting docker ..."
    tries=$(( $tries + 1 ))
    systemctl start docker
done

