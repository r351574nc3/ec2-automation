#!/bin/bash

cat <<EOF
################################################################################
# Starting Snapshot and Volume Cleanup                                         #
################################################################################
EOF

export EC2_PRIVATE_KEY=/home/ubuntu/.ssh/pk-7QMDI7QEWSI2MKKOA3GZSII4F54PW2TU.pem
export EC2_CERT=/home/ubuntu/.ssh/cert-7QMDI7QEWSI2MKKOA3GZSII4F54PW2TU.pem

master="($(ec2-describe-images -F tag:Active=Yes -F tag:Slave=Yes | grep BLOCKDEVICE | cut -f 4 |tr [:space:] \|)snapshot)"
snapshots=$(ec2-describe-snapshots -F volume-size=128 | egrep -v "$master" | cut -f 2)
echo "Cleaning the following snapshots"
echo $snapshots

for snapshot in $snapshots
do
    for x in $(ec2-describe-volumes -F snapshot-id=$snapshot | cut -f 2); do ec2delvol $x;done
    
    volumes=$(ec2-describe-volumes -F snapshot-id=$snapshot | cut -f 2)
    if [ "$volumes" == "" ]
    then
        ec2-delete-snapshot $snapshot
    fi
done

cat <<EOF
################################################################################
#   Ending Snapshot and Volume Cleanup                                         #
################################################################################
EOF
