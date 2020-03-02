#!/bin/bash

echo "PKS-AUTOSCASLER PRE-REQ INSTALLER AND CHECKER"
echo " "
echo " "
echo "Make sure you are running this script on the OPSMANAGER..."

if command -v om >/dev/null 2>&1 ; then
  	echo "OM CLI installed. Skipping...."
else
  	echo "OM CLI not installed. Installing...."
	wget https://github.com/pivotal-cf/om/releases/download/4.5.0/om-linux-4.5.0
	chmod +x om-linux-4.5.0
  	sudo mv om-linux-4.5.0 /usr/local/bin/om
fi

sudo apt-get -y install bc jq
sudo apt-get -y install python-pip
sudo -H pip install yq

if command -v pks >/dev/null 2>&1 ; then
  	echo "PKS CLI installed. Skipping..."
else
	echo "ERROR!!!!"
  	echo "PKS CLI not found. Please download the latest binary locally from PIVNET, set the permissions to execute, and move it to /usr/local/bin"
	echo "Once installed, please re-run this script."
fi
