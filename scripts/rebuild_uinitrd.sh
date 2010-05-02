#!/bin/sh

echo "This script requires: uboot-mkimage and initramfs-tools installed"
DIR=$PWD
sudo update-initramfs -u -k $(uname -r)
sudo mkimage -A arm -O linux -T ramdisk -C none -a 0 -e 0 -n initramfs -d /boot/initrd.img-$(uname -r) ${DIR}/uInitrd

