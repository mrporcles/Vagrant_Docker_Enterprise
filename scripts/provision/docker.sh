#!/usr/bin/env bash

set -e

# Create defaults docker file
echo "Adding DOCKER_OPTS (/etc/docker/daemon.json)"

mkdir -p /etc/docker
touch /etc/docker/daemon.json
sudo cat <<EOF | sudo dd of=/etc/docker/daemon.json status=none
{
	"hosts": ["unix://var/run/docker.sock","tcp://0.0.0.0:2375"],
	"insecure-registries": ["harbor.local:80"]
}
EOF

# Enable docker service
echo "Permanently enabling docker service"
sudo systemctl enable docker > /dev/null 2>&1
echo "Starting docker service"
sudo systemctl start docker
