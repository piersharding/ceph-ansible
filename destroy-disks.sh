#!/bin/sh

set -x


# delete wal disks
for i in 0 1 2
do
  sudo umount /dev/ceph_wal${i}/ceph_wal${i}
  sudo lvremove ceph_wal${i} -y
  sudo vgremove ceph_wal${i}
  sudo pvremove /dev/loop11${i}
  sudo losetup -d /dev/loop11${i}
  sudo rm /cephfs/vdisk_wal${i}.img
done

# delete data disks
for i in 0 1 2
do
  sudo umount /dev/ceph_data${i}/ceph_data${i}
  sudo lvremove ceph_data${i} -y
  sudo vgremove ceph_data${i}
  sudo pvremove /dev/loop11${i}
  sudo losetup -d /dev/loop12${i}
  sudo rm /cephfs/vdisk_data${i}.img
done

sudo lsblk
sudo lvdisplay
sudo vgdisplay
sudo pvdisplay
