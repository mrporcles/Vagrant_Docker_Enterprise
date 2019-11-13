#!/usr/bin/env bash

set -e

# User defined variables
admiral_version="1.5.2"
harbor_version="1.9.2"
docker_compose_version="1.24.1"

# Check for first argument (must be node name to map containers)
function check_first_arg {
	if [ -z $1 ]
	then
		echo "No node name given, exiting."
		exit 0
	fi
}

# Install VMware Admiral Container Management (https://vmware.github.io/admiral/)
function install_admiral {
	if [ $1 == "admiral" ]
	then
		echo "We need jq, installing..."
		sudo tdnf install jq -y
		if [ $? -ne 0 ]; then
			echo "Could not install jq (tdnf), exiting."
			exit 1
		fi
		echo "We need admiral cli, fetching"
		sudo curl -sL https://github.com/mrporcles/admiral/raw/master/bin/admiral -o /usr/local/bin/admiral && sudo chmod +x /usr/local/bin/admiral
		if [ $? -ne 0 ]; then
			echo "Could not install admiral cli, exiting."
			exit 1
		fi
		echo "Fetching VMware Admiral Container Image and starting container (ports 8282:8282)"
		sudo docker pull vmware/admiral:v${admiral_version}
		# TODO Fix static IP
		sudo docker run -d -p 8282:8282 --add-host="harbor.local:192.168.33.102" --name admiral -u root vmware/admiral:v${admiral_version}
		if [ $? -ne 0 ]; then
			echo "Something went wrong starting VMware Admiral, exiting"
			exit 1
		fi
    echo "Starting VMware Admiral Configuration"
		sudo docker exec admiral sh -c "echo allow.registry.plain.http.connection=true >> /admiral/config/dist_configuration.properties"
		if [ $? -ne 0 ]; then
			echo "Something went wrong configuring VMware Admiral, exiting"
			exit 1
		fi
		echo "Restarting Admiral to refresh configuration"
		sudo docker stop admiral && sudo docker start admiral
		if [ $? -ne 0 ]; then
			echo "Something went wrong restarting VMware Admiral, exiting"
			exit 1
		fi
		echo "Waiting 20s for Admiral to restart"
		sleep 20s
		echo "Adding Docker Hosts to VMware Admiral"
		sudo curl -s -X POST http://192.168.33.101:8282/resources/clusters -H "x-project: /projects/default-project" -H "Content-Type: application/json" -d '{"hostState":{"address":"http://192.168.33.103:2375","customProperties":{"__containerHostType":"DOCKER","__adapterDockerType":"API","__clusterName":"docker-cluster"}},"acceptCertificate":true}' && cluster=$(sudo curl -s -X GET http://192.168.33.101:8282/resources/clusters |jq -r '.documentLinks | .[]') && sudo curl -s -X POST http://192.168.33.101:8282$cluster/hosts -H "x-project: /projects/default-project" -H "Content-Type: application/json" -d '{"hostState":{"address":"http://192.168.33.104:2375","customProperties":{"__containerHostType":"DOCKER","__adapterDockerType":"API"}},"acceptCertificate":false}'
		if [ $? -ne 0 ]; then
			echo "Something went wrong adding Docker Hosts to VMware Admiral, exiting"
			exit 1
		fi
		echo "Adding Harbor Registry to VMware Admiral"
		sudo curl -s -X POST http://192.168.33.101:8282/core/auth/credentials -H "x-project: /projects/default-project" -H "Content-Type: application/json" -d '{"type":"Password","userEmail":"admin","privateKey":"Harbor12345","customProperties":{"__authCredentialsName":"harbor-admin"}}' && credential=$(sudo curl -s -X GET http://192.168.33.101:8282/core/auth/credentials |jq '.documentLinks | .[]' |grep -v cert) && payload="{\"hostState\":{\"address\":\"http://harbor.local:80\",\"name\":\"Harbor\",\"endpointType\":\"container.docker.registry\",\"authCredentialsLink\":$credential}}" && sudo curl -s -X PUT http://192.168.33.101:8282/config/registry-spec -H "Content-Type: application/json" -d $payload
		if [ $? -ne 0 ]; then
			echo "Something went wrong adding Harbor Registry to VMware Admiral, exiting"
			exit 1
		fi
	fi
}

# Install VMware Harbor Container Management (https://vmware.github.io/harbor/)
function install_harbor {
	if [ $1 == "harbor" ]
	then
		echo "Cleaning up and fetching VMware Harbor Release (version ${harbor_version})"
		sudo rm -rf /opt/harbor*
		sudo curl -o /opt/harbor.tar.gz -Ls https://github.com/goharbor/harbor/releases/download/v${harbor_version}/harbor-online-installer-v${harbor_version}.tgz
		if [ $? -ne 0 ]; then
			echo "Error retrieving file from the web"
			exit 1
		fi

		echo "We need python2, tar and awk, installing..."
		sudo tdnf install python2 tar gawk -y
		if [ $? -ne 0 ]; then
			echo "Could not install python2 (tdnf), exiting."
			exit 1
		fi

		echo "We also need docker-compose, fetching ${docker_compose_version}"
		sudo curl -sL https://github.com/docker/compose/releases/download/${docker_compose_version}/docker-compose-`uname -s`-`uname -m` -o /usr/local/bin/docker-compose
		if [ $? -ne 0 ]; then
			echo "Could not install docker-compose, exiting."
			exit 1
		fi

		sudo chmod +x /usr/local/bin/docker-compose

		echo "Unpacking and configuring VMware Harbor"
		sudo mkdir /opt/harbor && sudo tar -xzf /opt/harbor.tar.gz -C /opt
                sudo sed -i "s/reg\.mydomain\.com/${1}.local/" /opt/harbor/harbor.yml
								cd /opt/harbor; sudo ./prepare --with-clair --with-chartmuseum; sudo chmod -R 755 common; sudo chmod -R 755 /data;
		#						sudo docker-compose -f docker-compose.yml -f docker-compose.clair.yml -f docker-compose.chartmuseum.yml up -d
		echo "Calling docker-compose up"
								sudo docker-compose up -d
    #           sudo /usr/local/bin/docker-compose -f /tmp/harbor/docker-compose.yml up -d

		if [ $? -eq 0 ]; then
                        echo "Successfully started VMware Harbor..."
                fi
	fi
}

# Call functions
check_first_arg $1
install_admiral $1
install_harbor $1
