#!/bin/bash

#Find Target Partition and FileSystem
if [ -f /etc/mtab ] ; then
 FINAL_PART=$(mount | grep /dev/ | grep -v devpts | grep " / " | awk '{print $1}')
 FINAL_FSTYPE=$(mount | grep /dev/ | grep -v devpts | grep " / " | awk '{print $5}')
else
 #Currently only Maverick, but log if something else does it..
 touch /boot/uboot/backup/no_mtab
 FINAL_PART=$(cat /mounts | grep /dev/ | grep "/target " | awk '{print $1}')
 FINAL_FSTYPE=$(cat /mounts | grep /dev/ | grep "/target " | awk '{print $3}')
fi

#Cleanup: NetInstall Files
rm -f /boot/uboot/uInitrd.net || true
rm -f /boot/uboot/uImage.net || true
rm -f /boot/uboot/zImage.net || true
rm -f /boot/uboot/initrd.net || true

#Cleanup: Initial Bootloader
rm -f /boot/uboot/boot.scr || true
rm -f /boot/uboot/uEnv.txt || true

if [ -f "/boot/uboot/backup/normal.txt" ] ; then
	sed -i -e 's:FINAL_PART:'$FINAL_PART':g' /boot/uboot/backup/normal.txt
	sed -i -e 's:FINAL_FSTYPE:'$FINAL_FSTYPE':g' /boot/uboot/backup/normal.txt
	mv /boot/uboot/backup/normal.txt /boot/uboot/uEnv.txt
fi

#Install Correct Kernel Image:
dpkg -x /boot/uboot/linux-image-*_1.0*_arm*.deb /
update-initramfs -c -k `uname -r`

mkimage -A arm -O linux -T ramdisk -C none -a 0 -e 0 -n initramfs -d /boot/initrd.img-`uname -r` /boot/uboot/uInitrd
load_addr=$(cat /boot/uboot/SOC.sh | grep load_addr | awk -F"=" '{print $2}')
mkimage -A arm -O linux -T kernel -C none -a ${load_addr} -e ${load_addr} -n `uname -r` -d /boot/vmlinuz-`uname -r` /boot/uboot/uImage

cp /boot/vmlinuz-`uname -r` /boot/uboot/zImage
cp /boot/initrd.img-`uname -r` /boot/uboot/initrd.img

rm -f /boot/uboot/linux-image-*_1.0*_arm*.deb || true

#Debug:
mount > /boot/uboot/backup/mount.log

