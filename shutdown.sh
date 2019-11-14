#!/bin/bash
ESX="192.168.1.11 192.168.1.12 192.168.1.13 192.168.1.14"
pwsh -File ./shutdown-vms.ps1
for $e in $ESX; do
  echo $e
  ping -c 1 -W 3 $e
  if [ $? -eq 0 ]; then
    echo "Shutdown $e"
    ssh root@$e "poweroff"
  else
    echo "Offline $e"
  fi
done

