#!/bin/bash
host_ip=$1
key="$HOME/.ssh/id_rsa.pub"

if [ -z "$1" ]; then
  echo "Usage: ./copy-ssh-key.sh 42.42.1.2"
  exit 13
fi

while [ ! -e $key ]; do
  echo "Path to your private SSH key:"
  read key
done
cat $key | ssh root@$host_ip 'cat >> /etc/ssh/keys-root/authorized_keys'
