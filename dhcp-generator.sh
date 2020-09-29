#!/bin/bash
for i in $(seq 1 200); do
    hexa=$(printf '%02x' $i)
    dec=$(printf '%03d' $i)
    echo "                static-mapping vesx$dec {"
    echo "                    ip-address 192.168.3.$i"
    echo "                    mac-address 00:50:56:a1:4b:$hexa"
    echo "                }"
done
