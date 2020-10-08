#!/bin/bash

if [ -z "$1" ]; then
    echo "Stop VM on ESXi, then, stop the ESXi"
    echo "Usage: ./start.sh esx_ip"
    exit 13
fi

host_ip="$1"
host_pwd=$(grep "\"ip\": \"$host_ip" -A 2 configuration.json | grep pwd | sed  's:.*"\(.*\)",:\1:')

if [ -z "$host_pwd" ]; then
    echo "The host $host_ip is not a physical ESXi (check your configuration.json)"
    exit 13
fi

pwsh -File ./shutdown-vms.ps1 $host_ip

echo "Power off $host_ip"
while ! [[ $(nc -w 5 "$host_ip" 22 <<< "\0" ) =~ "OpenSSH" ]]; do
  echo "Waiting for the SSH Server"
  sleep 10
done
echo "The SSH server on $host_ip is running!"
echo "Enter the password ($host_pwd) for $host_ip / Power off the ESXi"
ssh -o StrictHostKeyChecking=no root@$host_ip "poweroff"
