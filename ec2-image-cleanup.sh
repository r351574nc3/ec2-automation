#!/bin/bash

EC2_PRIVATE_KEY=/home/ubuntu/.ssh/pk-7QMDI7QEWSI2MKKOA3GZSII4F54PW2TU.pem
EC2_CERT=/home/ubuntu/.ssh/cert-7QMDI7QEWSI2MKKOA3GZSII4F54PW2TU.pem

master=$(ec2-describe-snapshots -F volume-size=128 -F tag:Name=continuous-integration-master | head -1 | cut -f 2);
snapshots=$(ec2-describe-snapshots -F volume-size=128 | grep -v $master | cut -f 2)

for snapshot in $snapshots
do
    for x in $(ec2-describe-volumes -F snapshot-id=$snapshot | cut -f 2); do ec2delvol $x;done
    
    volumes=$(ec2-describe-volumes -F snapshot-id=$snapshot | cut -f 2)
    if [ "$volumes" == "" ]
    then
        ec2-delete-snapshot $snapshot
    fi
done
