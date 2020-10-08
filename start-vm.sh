#!/bin/bash

if [ -z "$1" ]; then
    echo "Start VM on ESXi"
    echo "Usage: ./start.sh esx_ip"
    exit 13
fi

host_ip="$1"
host_pwd=$(grep "\"ip\": \"$host_ip\"" -A 2 configuration.json | grep "pwd" | sed  's:.*"\(.*\)",:\1:')
numberRegEx="^[0-9]+$"

ping -c 1 -W 3 $host_ip &> /dev/null
result=$?
while [ $result -ne 0 ]; do
  sleep 10
  echo "Waiting for ESXi $host_ip"
  ping -c 1 -W 3 $host_ip &> /dev/null
  result=$?
done
echo "The ESXi $host_ip is running!"

while ! [[ $(nc -w 5 "$host_ip" 22 <<< "\0" ) =~ "OpenSSH" ]]; do
  echo "Waiting for the SSH Server"
  sleep 10
done
echo "The SSH server on $host_ip is running!"
echo "NOTE: You can copy your SSH keys with './copy-ssh-key.sh $host"

echo "Enter the password ($host_pwd) for $host_ip / List VM on the ESXi"
ssh -o StrictHostKeyChecking=no root@$host_ip "vim-cmd vmsvc/getallvms | grep ^[0-9]" | awk '{ print $1,$2}'
echo "Enter the Vmid of the VM to start"
echo -n "$ "
read id
echo "Starting the VM with the id $id"
echo "Enter the password ($host_pwd) for $host / Power on the VM"
echo "$ "
ssh -o StrictHostKeyChecking=no root@$host "vim-cmd vmsvc/power.on $id"
