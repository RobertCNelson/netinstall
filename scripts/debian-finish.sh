#!/bin/bash

#Find Target Partition and FileSystem
if [ -f /etc/mtab ] ; then
 FINAL_PART=$(mount | grep /dev/ | grep -v devpts | grep " / " | awk '{print $1}')
 FINAL_FSTYPE=$(mount | grep /dev/ | grep -v devpts | grep " / " | awk '{print $5}')
else
 #Currently only Maverick, but log if something else does it..
 touch /boot/uboot/debug/no_mtab
 FINAL_PART=$(cat /proc/mounts | grep /dev/ | grep -v devpts | grep " / " | awk '{print $1}')
 FINAL_FSTYPE=$(cat /proc/mounts | grep /dev/ | grep -v devpts | grep " / " | awk '{print $3}')
fi

#Cleanup: NetInstall Files
rm -f /boot/uboot/uInitrd.net || true
rm -f /boot/uboot/uImage.net || true

#Cleanup: Initial Bootloader
rm -f /boot/uboot/boot.scr || true
rm -f /boot/uboot/uEnv.txt || true

#Next: are we using uEnv.txt or boot.scr boot files?
if [ -f "/boot/uboot/cus/use_uenv" ]; then
 if [ -f "/boot/uboot/cus/normal.txt" ]; then
  sed -i -e 's:FINAL_PART:'$FINAL_PART':g' /boot/uboot/cus/normal.txt
  sed -i -e 's:FINAL_FSTYPE:'$FINAL_FSTYPE':g' /boot/uboot/cus/normal.txt
  mv /boot/uboot/cus/normal.txt /boot/uboot/uEnv.txt
 fi
else
 sed -i -e 's:FINAL_PART:'$FINAL_PART':g' /boot/uboot/cus/boot.cmd
 sed -i -e 's:FINAL_FSTYPE:'$FINAL_FSTYPE':g' /boot/uboot/cus/boot.cmd
 mkimage -A arm -O linux -T script -C none -a 0 -e 0 -n "Boot" -d /boot/uboot/cus/boot.cmd /boot/uboot/boot.scr
 cp /boot/uboot/cus/boot.cmd /boot/uboot/boot.cmd
fi

#Install Correct Kernel Image:
dpkg -x /boot/uboot/linux-image-*_1.0*_arm*.deb /
update-initramfs -c -k `uname -r`
mkimage -A arm -O linux -T ramdisk -C none -a 0 -e 0 -n initramfs -d /boot/initrd.img-`uname -r` /boot/uboot/uInitrd
mkimage -A arm -O linux -T kernel -C none -a ZRELADD -e ZRELADD -n `uname -r` -d /boot/vmlinuz-`uname -r` /boot/uboot/uImage
rm -f /boot/uboot/linux-image-*_1.0*_arm*.deb || true

#Debug:
cat /proc/mounts > /boot/uboot/debug/proc_mounts.log
mount > /boot/uboot/debug/mount.log

