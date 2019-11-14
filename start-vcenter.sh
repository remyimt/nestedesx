#!/bin/bash
ESX="192.168.1.13"
VCENTER="192.168.1.30"
result=1

echo "Waiting ESXi $ESX"
while [ $result -ne 0 ]; do
  sleep 10
  ping -c 1 -W 3 $ESX
  result=$?
done
echo "Starting vCenter $VCENTER"
ssh root@$ESX "vim-cmd vmsvc/power.on 1"
echo "Waiting vCenter $VCENTER"
result=1
while [ $result -ne 0 ]; do
  sleep 10
  ping -c 1 -W 3 $VCENTER
  result=$?
done
result=1
while [ $result -ne 0 ]; do
  pwsh -File ./vcenter-connect.ps1
  result=$?
done
echo "vCenter is up!"
