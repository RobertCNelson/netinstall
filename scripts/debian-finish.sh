#!/bin/bash

#Find Target Partition and FileSystem
FINAL_PART=$(mount | grep /dev/ | grep -v devpts | awk '{print $1}')
FINAL_FSTYPE=$(mount | grep /dev/ | grep -v devpts | awk '{print $5}')

#Cleanup: NetInstall Files
rm -f /boot/uboot/uInitrd.net || true
rm -f /boot/uboot/uImage || true

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

#Process Correct Kernel Image:
update-initramfs -c -k `uname -r`
mkimage -A arm -O linux -T ramdisk -C none -a 0 -e 0 -n initramfs -d /boot/initrd.img-`uname -r` /boot/uboot/uInitrd
mkimage -A arm -O linux -T kernel -C none -a ZRELADD -e ZRELADD -n `uname -r` -d /boot/vmlinuz-`uname -r` /boot/uboot/uImage
