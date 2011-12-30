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

#Did: Ubuntu touch and backup scr boot file?
if [ -f "/boot/uboot/boot.scr.bak" ]; then
 rm -f /boot/uboot/boot.scr || true
 mv /boot/uboot/boot.scr.bak /boot/uboot/boot.scr
fi

#Did: Ubuntu touch and backup MLO Bootloader?
if [ -f "/boot/uboot/MLO.bak" ]; then
 rm -f /boot/uboot/MLO || true
 mv /boot/uboot/MLO.bak /boot/uboot/MLO
fi

#Did: Ubuntu touch and backup u-boot.bin Bootloader?
if [ -f "/boot/uboot/u-boot.bin.bak" ]; then
 rm -f /boot/uboot/u-boot.bin || true
 mv /boot/uboot/u-boot.bin.bak /boot/uboot/u-boot.bin
fi

#Next: are we using uEnv.txt or boot.scr boot files?
if [ -f "/boot/uboot/use_uenv" ]; then
 rm -f /boot/uboot/boot.scr || true 

 if [ -f "/boot/uboot/normal.txt" ]; then
  sed -i -e 's:FINAL_PART:'$FINAL_PART':g' /boot/uboot/normal.txt
  sed -i -e 's:FINAL_FSTYPE:'$FINAL_FSTYPE':g' /boot/uboot/normal.txt

  rm -f /boot/uboot/uEnv.txt || true
  mv /boot/uboot/normal.txt /boot/uboot/uEnv.txt
 fi
else
 if [ -f "/boot/uboot/boot.scr" ]; then
  sed -i -e 's:FINAL_PART:'$FINAL_PART':g' /boot/uboot/boot.cmd
  sed -i -e 's:FINAL_FSTYPE:'$FINAL_FSTYPE':g' /boot/uboot/boot.cmd

  rm -f /boot/uboot/boot.scr || true
  mkimage -A arm -O linux -T script -C none -a 0 -e 0 -n "Boot" -d /boot/uboot/boot.cmd /boot/uboot/boot.scr
 fi
fi

#Cleanup: some of Ubuntu's packages:
apt-get remove -y linux-image-omap* || true
apt-get remove -y linux-headers-omap* || true
apt-get remove -y u-boot-linaro* || true
apt-get remove -y x-loader-omap* || true
apt-get remove -y flash-kernel || true

#Install Correct Kernel Image:
dpkg -x /boot/uboot/linux-image-*_1.0*_arm*.deb /
update-initramfs -c -k `uname -r`
mkimage -A arm -O linux -T ramdisk -C none -a 0 -e 0 -n initramfs -d /boot/initrd.img-`uname -r` /boot/uboot/uInitrd
mkimage -A arm -O linux -T kernel -C none -a ZRELADD -e ZRELADD -n `uname -r` -d /boot/vmlinuz-`uname -r` /boot/uboot/uImage
rm -f /boot/uboot/linux-image-*_1.0*_arm*.deb || true
