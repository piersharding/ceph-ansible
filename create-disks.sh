#!/bin/sh

DATA_SIZE=25G
WAL_SIZE=2G
set -x

sudo mkdir -p /cephfs

# create wal disks
for i in 0 1 2
do
  sudo fallocate -l ${WAL_SIZE} /cephfs/vdisk_wal${i}.img
  sudo losetup -l -P /dev/loop11${i} /cephfs/vdisk_wal${i}.img
  sudo wipefs -a /dev/loop11${i}
  sudo blkid -i /dev/loop11${i}
  sudo pvcreate /dev/loop11${i}
  sudo vgcreate ceph_wal${i} /dev/loop11${i}
  sudo lvcreate -l 100%FREE ceph_wal${i} -n ceph_wal${i}
done

# create data disks
for i in 0 1 2
do
  sudo fallocate -l ${DATA_SIZE} /cephfs/vdisk_data${i}.img
  sudo losetup -l -P /dev/loop12${i} /cephfs/vdisk_data${i}.img
  sudo wipefs -a /dev/loop12${i}
  sudo blkid -i /dev/loop12${i}
  sudo pvcreate /dev/loop12${i}
  sudo vgcreate ceph_data${i} /dev/loop12${i}
  sudo lvcreate -l 100%FREE ceph_data${i} -n ceph_data${i}
done

sudo lsblk
sudo lvdisplay
sudo vgdisplay
sudo pvdisplay
