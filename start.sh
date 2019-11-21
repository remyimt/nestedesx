#!/bin/bash
host=$(grep "vcenter" -A 5 configuration.json | grep host | sed  's:.*"\(.*\)",:\1:')
vcenter=$(grep "vcenter" -A 5 configuration.json | grep ip | sed  's:.*"\(.*\)",:\1:')

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
id=$(ssh -o StrictHostKeyChecking=no root@$host "vim-cmd vmsvc/getallvms" | grep Embedded | cut -d ' ' -f1)
echo "Starting the VM with the id $id"
ssh -o StrictHostKeyChecking=no root@$host "vim-cmd vmsvc/power.on $id"
echo "Waiting vCenter $vcenter"
ping -c 1 -W 3 $vcenter
result=$?
while [ $result -ne 0 ]; do
  sleep 10
  ping -c 1 -W 3 $vcenter
  result=$?
done
echo "Starting the NUC cluster"
pwsh -File ./deploy.ps1
