#!/bin/bash
host=$(grep "vcenter" -A 5 configuration.json | grep host | sed  's:.*"\(.*\)",:\1:')
vcenter=$(grep "vcenter" -A 5 configuration.json | grep ip | sed  's:.*"\(.*\)",:\1:')
numberRegEx="^[0-9]+$"
HTML_FILE="vcenter.html"

echo "Waiting ESXi $host"
ping -c 1 -W 3 $host
result=$?
while [ $result -ne 0 ]; do
  sleep 10
  ping -c 1 -W 3 $host
  result=$?
done
sleep 20
echo "Starting vCenter $vcenter"
echo "Enter the password for $host"
id=$(ssh -o StrictHostKeyChecking=no root@$host "vim-cmd vmsvc/getallvms" | grep Embedded | cut -d ' ' -f1)
if ! [[ $id =~ $numberRegEx ]]; then
  echo "Failed to retrieve the ID of the VM with the vCenter"
  exit 13
fi
echo "Starting the VM with the id $id"
echo "Enter the password for $host"
ssh -o StrictHostKeyChecking=no root@$host "vim-cmd vmsvc/power.on $id"
echo "Waiting vCenter $vcenter"
ping -c 1 -W 3 $vcenter
result=$?
while [ $result -ne 0 ]; do
  sleep 10
  ping -c 1 -W 3 $vcenter
  result=$?
done
echo "Waiting for the vSphere web service"
wget https://$vcenter/ui/ --no-check-certificate -O $HTML_FILE &> /dev/null
res=$(grep "initializing" $HTML_FILE)
while [ ! -z "$res" ]; do
  echo "Waiting for the web service"
  sleep 30
  wget https://$vcenter/ui/ --no-check-certificate -O $HTML_FILE &> /dev/null
  res=$(grep "initializing" $HTML_FILE)
done
rm $HTML_FILE

echo "Starting the NUC cluster"
pwsh -File ./deploy.ps1
