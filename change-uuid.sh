#!/bin/bash


for h in $(cat uuid-hosts.txt); do
    echo "#### $h"
    ssh -o StrictHostKeyChecking="no" root@$h "esxcli vsan cluster get"
    #ssh -o StrictHostKeyChecking="no" root@$h "sed -i '/system.uuid/d' /etc/vmware/esx.conf; reboot"
done
