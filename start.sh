#!/bin/bash
host=$(grep "vcenter" -A 5 configuration.json | grep host | sed  's:.*"\(.*\)",:\1:')
host_pwd=$(grep "\"ip\": \"$host" -A 3 configuration.json | grep pwd | sed  's:.*"\(.*\)",:\1:')
vcenter=$(grep "vcenter" -A 5 configuration.json | grep ip | sed  's:.*"\(.*\)",:\1:')
numberRegEx="^[0-9]+$"
HTML_FILE="vcenter.html"

if [ "$1" = "web" ]; then
  echo "Wait for the vSphere Web Server before starting the deployment"
else
  if [ "$1" = "quick" ]; then
    echo "Start the deployment as soon as possible"
  else
    echo "Usage: ./start.sh web|quick"
    echo "  ./start.sh web: Wait for the vSphere Web Server before starting the deployment"
    echo "  ./start.sh quick: Start the deployment as soon as possible"
    exit 13
  fi
fi

echo "Waiting for ESXi $host"
ping -c 1 -W 3 $host &> /dev/null
result=$?
while [ $result -ne 0 ]; do
  sleep 10
  echo "Waiting for ESXi $host"
  ping -c 1 -W 3 $host &> /dev/null
  result=$?
done
echo "The ESXi $host is running!"

while ! [[ $(nc -w 5 "$host" 22 <<< "\0" ) =~ "OpenSSH" ]]; do
  echo "Waiting for the SSH Server"
  sleep 10
done
echo "The SSH server on $host is running!"
echo "NOTE: You can copy your SSH keys with './copy-ssh-key.sh $host"

echo "Starting vCenter $vcenter"
echo "Enter the password ($host_pwd) for $host"
id=$(ssh -o StrictHostKeyChecking=no root@$host "vim-cmd vmsvc/getallvms" | grep Embedded | cut -d ' ' -f1)
if ! [[ $id =~ $numberRegEx ]]; then
  echo "Failed to retrieve the ID of the VM with the vCenter"
  exit 13
fi
echo "Starting the VM with the id $id"
echo "Enter the password ($host_pwd) for $host"
ssh -o StrictHostKeyChecking=no root@$host "vim-cmd vmsvc/power.on $id"

echo "Waiting for the vCenter $vcenter"
ping -c 1 -W 3 $vcenter &> /dev/null
result=$?
while [ $result -ne 0 ]; do
  sleep 10
  echo "Waiting for the vCenter $vcenter"
  ping -c 1 -W 3 $vcenter &> /dev/null
  result=$?
done

if [ "$1" = "web" ]; then
  echo "Waiting for the vSphere web service"
  wget https://$vcenter/ui/ --no-check-certificate -O $HTML_FILE &> /dev/null
  while [ $(cat $HTML_FILE | wc -l) -eq 0 ]; do
    echo "No response from the vSphere web service. Waiting..."
    sleep 20
    wget https://$vcenter/ui/ --no-check-certificate -O $HTML_FILE &> /dev/null
  done
  result=$(grep "initializing" $HTML_FILE)
  while [ ! -z "$result" ]; do
    echo "Waiting for the vSphere web service..."
    sleep 20
    wget https://$vcenter/ui/ --no-check-certificate -O $HTML_FILE &> /dev/null
    result=$(grep "initializing" $HTML_FILE)
  done
  rm $HTML_FILE
fi

echo "Starting the NUC cluster"
pwsh -File ./deploy.ps1
