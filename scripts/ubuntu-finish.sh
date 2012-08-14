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

#Cleanup: Ubuntu's mess of backup files
rm -f /boot/uboot/uInitrd || true
rm -f /boot/uboot/uInitrd.bak || true
rm -f /boot/uboot/uImage || true
rm -f /boot/uboot/uImage.bak || true

#Cleanup: Initial Bootloader
rm -f /boot/uboot/boot.scr || true
rm -f /boot/uboot/boot.scr.bak || true
rm -f /boot/uboot/uEnv.txt || true
rm -f /boot/uboot/uEnv.txt.bak || true

#Restore backup MLO (SPL) Bootloader?
rm -f /boot/uboot/MLO || true
rm -f /boot/uboot/MLO.bak || true

if [ -f /boot/uboot/backup/MLO ] ; then
	mv /boot/uboot/backup/MLO /boot/uboot/MLO
fi

#Restore, backup u-boot Bootloader?
rm -f /boot/uboot/u-boot.bin || true
rm -f /boot/uboot/u-boot.bin.bak || true
rm -f /boot/uboot/u-boot.img || true
rm -f /boot/uboot/u-boot.img.bak || true

if [ -f /boot/uboot/backup/u-boot.img ] ; then
	mv /boot/uboot/backup/u-boot.img /boot/uboot/u-boot.img
fi

if [ -f /boot/uboot/backup/u-boot.bin ] ; then
	mv /boot/uboot/backup/u-boot.bin /boot/uboot/u-boot.bin
fi

if [ -f /boot/uboot/backup/u-boot.imx ] ; then
	dd if=/boot/uboot/backup/u-boot.imx of=/dev/mmcblk0 seek=1 bs=1024
fi

if [ -f "/boot/uboot/backup/boot.scr" ] ; then
	mv /boot/uboot/backup/boot.scr /boot/uboot/boot.scr
fi

if [ -f "/boot/uboot/backup/normal.txt" ] ; then
	sed -i -e 's:FINAL_PART:'$FINAL_PART':g' /boot/uboot/backup/normal.txt
	sed -i -e 's:FINAL_FSTYPE:'$FINAL_FSTYPE':g' /boot/uboot/backup/normal.txt
	mv /boot/uboot/backup/normal.txt /boot/uboot/uEnv.txt
fi

#Cleanup: some of Ubuntu's packages:
apt-get remove -y linux-image-omap* || true
apt-get remove -y linux-headers-omap* || true
apt-get remove -y u-boot-linaro* || true
apt-get remove -y x-loader-omap* || true
apt-get remove -y flash-kernel || true
apt-get -y autoremove || true

#Install Correct Kernel Image:
dpkg -x /boot/uboot/linux-image-*_1.0*_arm*.deb /
update-initramfs -c -k `uname -r`

boot_image=$(cat /boot/uboot/SOC.sh | grep boot_image | awk -F"=" '{print $2}')
if [ "x${boot_image}" == "xbootm" ] ; then
	mkimage -A arm -O linux -T ramdisk -C none -a 0 -e 0 -n initramfs -d /boot/initrd.img-`uname -r` /boot/uboot/uInitrd
	load_addr=$(cat /boot/uboot/SOC.sh | grep load_addr | awk -F"=" '{print $2}')
	mkimage -A arm -O linux -T kernel -C none -a ${load_addr} -e ${load_addr} -n `uname -r` -d /boot/vmlinuz-`uname -r` /boot/uboot/uImage
fi

cp /boot/vmlinuz-`uname -r` /boot/uboot/zImage
cp /boot/initrd.img-`uname -r` /boot/uboot/initrd.img

rm -f /boot/uboot/linux-image-*_1.0*_arm*.deb || true

#Debug:
mount > /boot/uboot/backup/mount.log

