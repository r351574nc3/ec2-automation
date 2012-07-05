#!/bin/bash 

cat <<EOF
################################################################################
# Starting Master to Slave Backup Sequence                                     #
################################################################################
EOF

echo -n Starting up...
EC2_PRIVATE_KEY=/home/ubuntu/.ssh/pk-7QMDI7QEWSI2MKKOA3GZSII4F54PW2TU.pem
EC2_CERT=/home/ubuntu/.ssh/cert-7QMDI7QEWSI2MKKOA3GZSII4F54PW2TU.pem  
JENKINS_HOME=/var/lib/jenkins
M2_REPO=$JENKINS_HOME/.m2/repository/
export EC2_PRIVATE_KEY EC2_CERT M2_REPO JENKINS_HOME

# commands
mount="sudo mount"
umount="sudo umount"
rsync="sudo -u jenkins rsync -az"

mountpoint=/mnt/slave
jenkins_remote=$mountpoint$JENKINS_HOME
old_image=$(ec2-describe-images --region us-east-1 -F tag:Active=Yes -F tag:Slave=Yes | head -1 | cut -f 2)

if [ "$old_image" == "" ]
then
    echo "No valid Slave Image found. Aborting..."
    exit 1
fi

aws_instance=$(wget -q -O- http://169.254.169.254/latest/meta-data/instance-id)
zone=$(ec2-describe-instances $aws_instance | grep '^INSTANCE' | cut -f 12)
old_snapshotid=$(ec2-describe-images --region us-east-1 -F tag:Active=Yes -F tag:Slave=Yes | grep BLOCKDEVICE | cut -f 4)
volumeid=$(ec2-describe-snapshots  $snapshotid | head -1| cut -f 3)
dt=$(date +%Y-%m-%d)
echo done

instanceid=$(ec2-run-instances  --availability-zone $zone $old_image -k kr-key -t t1.micro | grep INSTANCE | cut -f 2)
volumeid=$(ec2-describe-instances  $instanceid | egrep "^BLOCKDEVICE./dev/sda1" | cut -f3)
echo "Created instance $instanceid"

echo

cat <<EOF
Slave Image:      $old_image
Current Instance: $aws_instance
Old Snapshot:     $old_snapshotid
Volume:           $volumeid
Zone:             $zone
EOF

echo

while ! ec2-describe-instances $instanceid | grep -q running; do echo "Waiting for $instanceid to start"; sleep 1; done

ec2-stop-instances $instanceid

while ! ec2-describe-instances $instanceid | grep -q stopped; do echo "Waiting for $instanceid to stop"; sleep 1; done


# Detach from instances
while ! ec2-detach-volume  $volumeid; do echo "Waiting to detach $volumeid"; sleep 1; done

# Attach the old volume here
echo "Reattaching $volumeid to $aws_instance"
ec2-attach-volume   $volumeid -i $aws_instance -d /dev/sdf1
while ! ec2-describe-volumes  $volumeid | grep -q attached; do echo "Waiting to reattach $volumeid to $aws_instance"; sleep 1; done

# mount it
sudo mkdir -p $mountpoint
$mount /dev/xvdj1 $mountpoint

jobslist=$(sudo -u jenkins ssh -o StrictHostKeyChecking=no ci.rice.kuali.org find ./jobs -maxdepth 2 -name workspace)

# Copy jobs
for dir in $jobslist 
do 
    job=$(basename $(dirname $dir))
    source="ci.rice.kuali.org:jobs/$job/workspace/"
    dest="$jenkins_remote/workspace/$job/"
    command="$rsync  $source $dest"
    echo $source
    $command
done

# Copy tools
$rsync ci.rice.kuali.org:tools/ $jenkins_remote/tools/

# Cleanup M2_REPO
sudo rm -rf $mountpoint$M2_REPO/org/kuali

# Make sure we propogate ourselves
sudo cp -rf /home/ubuntu/bin/* $mountpoint$JENKINS_HOME/tools
sudo chown -R jenkins:nogroup $mountpoint$JENKINS_HOME/tools

# Propogate
mkdir -p $mountpoint/home/ubuntu/bin
cp -rf /home/ubuntu/bin/* $mountpoint/home/ubuntu/bin
mkdir -p $mountpoint/home/ubuntu/.ssh
chmod 700 $mountpoint/home/ubuntu/.ssh
cp /home/ubuntu/.ssh/*.pem $mountpoint/home/ubuntu/.ssh

# Unmount for clean detachment
$umount $mountpoint
ec2-detach-volume  $volumeid
while ! ec2-describe-volumes  $volumeid | grep -q available  ; do echo "Waiting to detach $volumeid"; sleep 1; done

ec2-attach-volume   $volumeid -i $instanceid -d /dev/sda1
while ! ec2-describe-volumes  $volumeid | grep -q attached; do echo "Waiting to reattach $volumeid to $instanceid"; sleep 1; done

echo "Starting up $instanceid"
ec2-start-instances  $instanceid
while ! ec2-describe-instances  $instanceid | grep -q running; do sleep 1; done
ec2-describe-instances $instanceid

ec2-delete-tags  $old_image --tag Active 
slave_image=$(ec2-create-image  $instanceid --name "ci-slave-$dt" --description "Continuous Integration Slave Image"|head -1 | cut -f 2)

echo "Activating Slave Image $ami"
ec2-create-tags  $slave_image --tag Active=Yes --tag Slave=Yes --tag Safe=No

while ! ec2-describe-images $slave_image | head -1 | grep -q available; do echo "Waiting for $slave_image to be ready for use"; sleep 600; done
ec2-describe-images  $slave_image

echo -n "Cleaning up..."
ec2-terminate-instances  $instanceid
echo "done"

echo "Resetting AMI on the master"
ssh -o StrictHostKeyChecking=no -i /home/ubuntu/kr-key.pem ci.rice.kuali.org sudo bin/update-ami.sh $old_image $slave_image

cat <<EOF
################################################################################
#   Ending Master to Slave Backup Sequence                                     #
################################################################################
EOF

