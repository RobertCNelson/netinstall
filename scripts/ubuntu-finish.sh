#!/bin/bash

#Find Target Partition and FileSystem
FINAL_PART=$(mount | grep /dev/ | grep -v devpts | awk '{print $1}')
FINAL_FSTYPE=$(mount | grep /dev/ | grep -v devpts | awk '{print $5}')

#Cleanup: NetInstall Files
rm -f /boot/uboot/uInitrd.net || true
rm -f /boot/uboot/uImage.net || true

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

if [ -f /boot/uboot/cus/MLO ] ; then
 mv /boot/uboot/cus/MLO /boot/uboot/MLO
fi

#Restore, backup u-boot Bootloader?
rm -f /boot/uboot/u-boot.bin || true
rm -f /boot/uboot/u-boot.bin.bak || true
rm -f /boot/uboot/u-boot.img || true
rm -f /boot/uboot/u-boot.img.bak || true

if [ -f /boot/uboot/cus/u-boot.img ] ; then
  mv /boot/uboot/cus/u-boot.img /boot/uboot/u-boot.img
fi

if [ -f /boot/uboot/cus/u-boot.bin ] ; then
  mv /boot/uboot/cus/u-boot.bin /boot/uboot/u-boot.bin
fi

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
mkimage -A arm -O linux -T ramdisk -C none -a 0 -e 0 -n initramfs -d /boot/initrd.img-`uname -r` /boot/uboot/uInitrd
mkimage -A arm -O linux -T kernel -C none -a ZRELADD -e ZRELADD -n `uname -r` -d /boot/vmlinuz-`uname -r` /boot/uboot/uImage
rm -f /boot/uboot/linux-image-*_1.0*_arm*.deb || true

#Debug:
mount > /boot/uboot/debug/mount.log

