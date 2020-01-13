#!/bin/bash
host=$(grep "vcenter" -A 5 configuration.json | grep host | sed  's:.*"\(.*\)",:\1:')
host_pwd=$(grep "\"ip\": \"$host" -A 3 configuration.json | grep pwd | sed  's:.*"\(.*\)",:\1:')
vcenter=$(grep "vcenter" -A 5 configuration.json | grep ip | sed  's:.*"\(.*\)",:\1:')
numberRegEx="^[0-9]+$"

pwsh -File ./shutdown-vms.ps1

echo "Stopping the vCenter $vcenter"
echo "Enter the password ($host_pwd) for $host / Get the VM ID"
echo "$ "
id=$(ssh -o StrictHostKeyChecking=no root@$host "vim-cmd vmsvc/getallvms" | grep Embedded | cut -d ' ' -f1)
if ! [[ $id =~ $numberRegEx ]]; then
  echo "Failed to retrieve the ID of the VM with the vCenter"
  exit 13
fi
echo "Stopping the VM with the id $id"
echo "Enter the password ($host_pwd) for $host / Power off the VM"
echo "$ "
ssh -o StrictHostKeyChecking=no root@$host "vim-cmd vmsvc/power.off $id"
ping -c 1 -W 3 $vcenter
result=$?
while [ $result -eq 0 ]; do
  sleep 10
  ping -c 1 -W 3 $vcenter
  result=$?
done

echo "Power off $host"
echo "Enter the password ($host_pwd) for $host / Power off the ESXi"
echo "$ "
ssh -o StrictHostKeyChecking=no root@$host "poweroff"
