#!/bin/bash
host=$(grep "vcenter" -A 5 configuration.json | grep host | sed  's:.*"\(.*\)",:\1:')
vcenter=$(grep "vcenter" -A 5 configuration.json | grep ip | sed  's:.*"\(.*\)",:\1:')

pwsh -File ./shutdown-vms.ps1

ping -c 1 -W 3 $vcenter
result=$?
if [ $result -eq 0 ]; then
  echo "vCenter is running !"
  echo "Cancel the operation 'Power off $host'"
else
  echo "Power off $host"
  ssh root@$host "poweroff"
fi
