#!/bin/bash
host=$(grep "vcenter" -A 5 configuration.json | grep host | sed  's:.*"\(.*\)",:\1:')
vcenter=$(grep "vcenter" -A 5 configuration.json | grep ip | sed  's:.*"\(.*\)",:\1:')

pwsh -File ./shutdown-vms.ps1

echo "Stopping the vCenter $vcenter"
id=$(ssh -o StrictHostKeyChecking=no root@$host "vim-cmd vmsvc/getallvms" | grep Embedded | cut -d ' ' -f1)
echo "Stopping the VM with the id $id"
ssh -o StrictHostKeyChecking=no root@$host "vim-cmd vmsvc/power.off $id"
ping -c 1 -W 3 $vcenter
result=$?
while [ $result -eq 0 ]; do
  sleep 10
  ping -c 1 -W 3 $vcenter
  result=$?
done

echo "Power off $host"
ssh -o StrictHostKeyChecking=no root@$host "poweroff"