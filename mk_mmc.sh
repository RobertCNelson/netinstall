#!/bin/bash -e
#
# Copyright (c) 2009-2011 Robert Nelson <robertcnelson@gmail.com>
#
# Permission is hereby granted, free of charge, to any person obtaining a copy
# of this software and associated documentation files (the "Software"), to deal
# in the Software without restriction, including without limitation the rights
# to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
# copies of the Software, and to permit persons to whom the Software is
# furnished to do so, subject to the following conditions:
#
# The above copyright notice and this permission notice shall be included in
# all copies or substantial portions of the Software.
#
# THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
# IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
# FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
# AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
# LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
# OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN
# THE SOFTWARE.

#Notes: need to check for: parted, fdisk, wget, mkfs.*, mkimage, md5sum

unset MMC
unset FIRMWARE
unset SERIAL_MODE
unset BETA_BOOT
unset BETA_KERNEL
unset USB_ROOTFS
unset PRINTK

MIRROR="http://rcn-ee.net/deb/"
DIST=squeeze

BOOT_LABEL=boot
PARTITION_PREFIX=""

MAVERICK_MD5SUM="12c0f04da6b8fb118939489f237e4c86"

#SQUEEZE_NETIMAGE="current"
SQUEEZE_NETIMAGE="20110106+b1"
SQUEEZE_MD5SUM="87634ae94d83057d35407525aa68926f"

DIR=$PWD
TEMPDIR=$(mktemp -d)

#Software Qwerks
#fdisk 2.18.x/2.19.x, dos no longer default
unset FDISK_DOS

if fdisk -v | grep 2.1[8-9] >/dev/null ; then
 FDISK_DOS="-c=dos -u=cylinders"
fi

#Check for gnu-fdisk
#FIXME: GNU Fdisk seems to halt at "Using /dev/xx" when trying to script it..
if fdisk -v | grep "GNU Fdisk" >/dev/null ; then
 echo "Sorry, this script currently doesn't work with GNU Fdisk"
 exit
fi

function detect_software {

#Currently only Ubuntu and Debian..
#Working on Fedora...
unset DEB_PACKAGE
unset RPM_PACKAGE
unset NEEDS_PACKAGE

if [ ! $(which mkimage) ];then
 echo "Missing uboot-mkimage"
 DEB_PACKAGE="uboot-mkimage "
 RPM_PACKAGE="uboot-tools "
 NEEDS_PACKAGE=1
fi

if [ ! $(which wget) ];then
 echo "Missing wget"
 DEB_PACKAGE+="wget "
 RPM_PACKAGE+="wget "
 NEEDS_PACKAGE=1
fi

if [ ! $(which mkfs.vfat) ];then
 echo "Missing mkfs.vfat"
 DEB_PACKAGE+="dosfstools "
 RPM_PACKAGE+="dosfstools "
 NEEDS_PACKAGE=1
fi

if [ ! $(which parted) ];then
 echo "Missing parted"
 DEB_PACKAGE+="parted "
 RPM_PACKAGE+="parted "
 NEEDS_PACKAGE=1
fi

if [ "${NEEDS_PACKAGE}" ];then
 echo ""
 echo "Please Install Missing Dependencies"
 echo "Ubuntu/Debian: sudo apt-get install $DEB_PACKAGE"
 echo "Fedora: as root: yum install $RPM_PACKAGE"
 echo ""
 exit
fi

}

function set_defaults {

 if [ "$BETA_KERNEL" ];then
  KERNEL_REL=2.6.38-rc6
  KERNEL_PATCH=3
  KERNEL=${KERNEL_REL}-d${KERNEL_PATCH}
 else
  KERNEL_REL=2.6.37.2
  KERNEL_PATCH=3
  KERNEL=${KERNEL_REL}-x${KERNEL_PATCH}
 fi

 if [ "$USB_ROOTFS" ];then
  sed -i 's/mmcblk0p5/sda1/g' ${DIR}/scripts/dvi-normal-maverick.cmd
  sed -i 's/mmcblk0p5/sda1/g' ${DIR}/scripts/dvi-normal-squeeze.cmd

  sed -i 's/mmcblk0p5/sda1/g' ${DIR}/scripts/serial-normal-maverick.cmd
  sed -i 's/mmcblk0p5/sda1/g' ${DIR}/scripts/serial-normal-squeeze.cmd
 fi

 if [ "$PRINTK" ];then
  sed -i 's/bootargs/bootargs earlyprintk/g' ${DIR}/scripts/serial*.cmd
 fi

}

function dl_xload_uboot {

 echo ""
 echo "Downloading X-loader, Uboot, Kernel and Debian Installer"
 echo ""

 mkdir -p ${TEMPDIR}/dl/${DIST}
 mkdir -p ${DIR}/dl/${DIST}

 wget --no-verbose --directory-prefix=${TEMPDIR}/dl/ ${MIRROR}tools/latest/bootloader

 if [ "$BETA_BOOT" ];then
  ABI="ABX"
 else
  ABI="ABI"
 fi

case "$SYSTEM" in
    beagle)

 MLO=$(cat ${TEMPDIR}/dl/bootloader | grep "${ABI}:1:MLO" | awk '{print $2}')
 UBOOT=$(cat ${TEMPDIR}/dl/bootloader | grep "${ABI}:1:UBOOT" | awk '{print $2}')

        ;;
    panda)

 MLO=$(cat ${TEMPDIR}/dl/bootloader | grep "${ABI}:2:MLO" | awk '{print $2}')
 UBOOT=$(cat ${TEMPDIR}/dl/bootloader | grep "${ABI}:2:UBOOT" | awk '{print $2}')

        ;;
    touchbook)

 MLO=$(cat ${TEMPDIR}/dl/bootloader | grep "${ABI}:5:MLO" | awk '{print $2}')
 UBOOT=$(cat ${TEMPDIR}/dl/bootloader | grep "${ABI}:5:UBOOT" | awk '{print $2}')

        ;;
    crane)

 MLO=$(cat ${TEMPDIR}/dl/bootloader | grep "${ABI}:6:MLO" | awk '{print $2}')
 UBOOT=$(cat ${TEMPDIR}/dl/bootloader | grep "${ABI}:6:UBOOT" | awk '{print $2}')

        ;;
esac

 wget -c --no-verbose --directory-prefix=${TEMPDIR}/dl/ ${MLO}
 wget -c --no-verbose --directory-prefix=${TEMPDIR}/dl/ ${UBOOT}

 MLO=${MLO##*/}
 UBOOT=${UBOOT##*/}

case "$DIST" in
    maverick)
	TEST_MD5SUM=$MAVERICK_MD5SUM
	HTTP_IMAGE="http://ports.ubuntu.com/ubuntu-ports/dists"
        ;;
    squeeze)
	TEST_MD5SUM=$SQUEEZE_MD5SUM
	HTTP_IMAGE="http://ftp.debian.org/debian/dists"
        ;;
esac

if ls ${DIR}/dl/${DIST}/initrd.gz >/dev/null 2>&1;then
  MD5SUM=$(md5sum ${DIR}/dl/${DIST}/initrd.gz | awk '{print $1}')
  if [ "=$TEST_MD5SUM=" != "=$MD5SUM=" ]; then
    echo "possible new md5sum $MD5SUM"
    rm -f ${DIR}/dl/${DIST}/initrd.gz || true
    wget --directory-prefix=${DIR}/dl/${DIST} ${HTTP_IMAGE}/${DIST}/main/installer-armel/current/images/versatile/netboot/initrd.gz
  fi
else
  wget --directory-prefix=${DIR}/dl/${DIST} ${HTTP_IMAGE}/${DIST}/main/installer-armel/current/images/versatile/netboot/initrd.gz
fi

 wget -c --directory-prefix=${DIR}/dl/${DIST} ${MIRROR}${DIST}/v${KERNEL}/linux-image-${KERNEL}_1.0${DIST}_armel.deb

 wget -c --directory-prefix=${DIR}/dl/${DIST} ${MIRROR}${DIST}/v${KERNEL}/initrd.img-${KERNEL}

if [ "${FIRMWARE}" ] ; then

 echo ""
 echo "Downloading Firmware"
 echo ""

case "$DIST" in
    maverick)
	rm -f ${TEMPDIR}/dl/index.html || true
	wget --directory-prefix=${TEMPDIR}/dl/ http://ports.ubuntu.com/pool/main/l/linux-firmware/
	MAVERICK_FW=$(cat ${TEMPDIR}/dl/index.html | grep 1.38 | grep linux-firmware | grep _all.deb | head -1 | awk -F"\"" '{print $8}')
	wget -c --directory-prefix=${DIR}/dl/${DIST} http://ports.ubuntu.com/pool/main/l/linux-firmware/${MAVERICK_FW}
	MAVERICK_FW=${MAVERICK_FW##*/}

	rm -f ${TEMPDIR}/dl/index.html || true
	wget --directory-prefix=${TEMPDIR}/dl/ http://ports.ubuntu.com/pool/multiverse/l/linux-firmware-nonfree/
	MAVERICK_NONF_FW=$(cat ${TEMPDIR}/dl/index.html | grep 1.9 | grep linux-firmware-nonfree | grep _all.deb | head -1 | awk -F"\"" '{print $8}')
	wget -c --directory-prefix=${DIR}/dl/${DIST} http://ports.ubuntu.com/pool/multiverse/l/linux-firmware-nonfree/${MAVERICK_NONF_FW}
	MAVERICK_NONF_FW=${MAVERICK_NONF_FW##*/}
        ;;
    squeeze)
	#from: http://packages.debian.org/source/squeeze/firmware-nonfree

	#Atmel
	rm -f ${TEMPDIR}/dl/index.html || true
	wget --directory-prefix=${TEMPDIR}/dl/ ftp://ftp.us.debian.org/debian/pool/non-free/a/atmel-firmware/
	ATMEL_FW=$(cat ${TEMPDIR}/dl/index.html | grep atmel | grep -v diff.gz | grep -v .dsc | grep -v orig.tar.gz | tail -1 | awk -F"\"" '{print $2}')
	wget -c --directory-prefix=${DIR}/dl/${DIST} ${ATMEL_FW}
	ATMEL_FW=${ATMEL_FW##*/}

	#Ralink
	rm -f ${TEMPDIR}/dl/index.html || true
	wget --directory-prefix=${TEMPDIR}/dl/ ftp://ftp.us.debian.org/debian/pool/non-free/f/firmware-nonfree/
	RALINK_FW=$(cat ${TEMPDIR}/dl/index.html | grep ralink | grep -v lenny | tail -1 | awk -F"\"" '{print $2}')
	wget -c --directory-prefix=${DIR}/dl/${DIST} ${RALINK_FW}
	RALINK_FW=${RALINK_FW##*/}

	#libertas
	rm -f ${TEMPDIR}/dl/index.html || true
	wget --directory-prefix=${TEMPDIR}/dl/ ftp://ftp.us.debian.org/debian/pool/non-free/libe/libertas-firmware/
	LIBERTAS_FW=$(cat ${TEMPDIR}/dl/index.html | grep libertas | grep -v diff.gz | grep -v .dsc | grep -v orig.tar.gz | tail -1 | awk -F"\"" '{print $2}')
	wget -c --directory-prefix=${DIR}/dl/${DIST} ${LIBERTAS_FW}
	LIBERTAS_FW=${LIBERTAS_FW##*/}

	#zd1211
	rm -f ${TEMPDIR}/dl/index.html || true
	wget --directory-prefix=${TEMPDIR}/dl/ ftp://ftp.us.debian.org/debian/pool/non-free/z/zd1211-firmware/
	ZD1211_FW=$(cat ${TEMPDIR}/dl/index.html | grep zd1211 | grep -v diff.gz | grep -v tar.gz | grep -v .dsc | tail -1 | awk -F"\"" '{print $2}')
	wget -c --directory-prefix=${DIR}/dl/${DIST} ${ZD1211_FW}
	ZD1211_FW=${ZD1211_FW##*/}

	#ar9170
	wget -c --directory-prefix=${DIR}/dl/${DIST} http://www.kernel.org/pub/linux/kernel/people/chr/carl9170/fw/1.9.2/carl9170-1.fw
	AR9170_FW="carl9170-1.fw"
        ;;
esac

fi

}

function prepare_uimage {
 mkdir -p ${TEMPDIR}/kernel
 cd ${TEMPDIR}/kernel
 sudo dpkg -x ${DIR}/dl/${DIST}/linux-image-${KERNEL}_1.0${DIST}_armel.deb ${TEMPDIR}/kernel
 cd ${DIR}/
}

function prepare_initrd {
 mkdir -p ${TEMPDIR}/initrd-tree
 cd ${TEMPDIR}/initrd-tree
 sudo zcat ${DIR}/dl/${DIST}/initrd.gz | sudo cpio -i -d
 sudo dpkg -x ${DIR}/dl/${DIST}/linux-image-${KERNEL}_1.0${DIST}_armel.deb ${TEMPDIR}/initrd-tree
 cd ${DIR}/

 sudo mkdir -p ${TEMPDIR}/initrd-tree/lib/firmware/

if [ "${FIRMWARE}" ] ; then

case "$DIST" in
    maverick)
	sudo dpkg -x ${DIR}/dl/${DIST}/${MAVERICK_FW} ${TEMPDIR}/initrd-tree
	sudo dpkg -x ${DIR}/dl/${DIST}/${MAVERICK_NONF_FW} ${TEMPDIR}/initrd-tree
        ;;
    squeeze)
	#from: http://packages.debian.org/source/squeeze/firmware-nonfree
	sudo dpkg -x ${DIR}/dl/${DIST}/${ATMEL_FW} ${TEMPDIR}/initrd-tree
	sudo dpkg -x ${DIR}/dl/${DIST}/${RALINK_FW} ${TEMPDIR}/initrd-tree
	sudo dpkg -x ${DIR}/dl/${DIST}/${LIBERTAS_FW} ${TEMPDIR}/initrd-tree
	sudo dpkg -x ${DIR}/dl/${DIST}/${ZD1211_FW} ${TEMPDIR}/initrd-tree
	sudo cp -v ${DIR}/dl/${DIST}/${AR9170_FW} ${TEMPDIR}/initrd-tree/lib/firmware/
        ;;
esac

fi

 #Cleanup some of the extra space..
 sudo rm -f ${TEMPDIR}/initrd-tree/boot/*-${KERNEL} || true
 sudo rm -rfd ${TEMPDIR}/initrd-tree/lib/modules/${KERNEL}/kernel/drivers/media/ || true
 sudo rm -rfd ${TEMPDIR}/initrd-tree/lib/modules/${KERNEL}/kernel/drivers/usb/serial/ || true
 sudo rm -rfd ${TEMPDIR}/initrd-tree/lib/modules/${KERNEL}/kernel/drivers/usb/misc/ || true

 sudo rm -rfd ${TEMPDIR}/initrd-tree/lib/modules/${KERNEL}/kernel/drivers/net/bluetooth/ || true
 sudo rm -rfd ${TEMPDIR}/initrd-tree/lib/modules/${KERNEL}/kernel/drivers/net/irda/ || true
 sudo rm -rfd ${TEMPDIR}/initrd-tree/lib/modules/${KERNEL}/kernel/drivers/net/hamradio/ || true
 sudo rm -rfd ${TEMPDIR}/initrd-tree/lib/modules/${KERNEL}/kernel/drivers/net/can/ || true

 sudo rm -rfd ${TEMPDIR}/initrd-tree/lib/modules/${KERNEL}/kernel/drivers/misc || true

 sudo rm -rfd ${TEMPDIR}/initrd-tree/lib/modules/${KERNEL}/kernel/net/irda/ || true
 sudo rm -rfd ${TEMPDIR}/initrd-tree/lib/modules/${KERNEL}/kernel/net/decnet/ || true

 sudo rm -rfd ${TEMPDIR}/initrd-tree/lib/modules/${KERNEL}/kernel/fs/ || true
 sudo rm -rfd ${TEMPDIR}/initrd-tree/lib/modules/${KERNEL}/kernel/sound/ || true
 sudo rm -rfd ${TEMPDIR}/initrd-tree/lib/modules/*-versatile/ || true
 sudo rm -rfd ${TEMPDIR}/initrd-tree/lib/firmware/*-versatile/ || true

 #introduced with the big linux-firmware
 #http://packages.ubuntu.com/lucid/all/linux-firmware/filelist

 sudo rm -rfd ${TEMPDIR}/initrd-tree/lib/firmware/agere* || true
 sudo rm -rfd ${TEMPDIR}/initrd-tree/lib/firmware/bnx2x-* || true
 sudo rm -rfd ${TEMPDIR}/initrd-tree/lib/firmware/bcm700*fw.bin || true
 sudo rm -rfd ${TEMPDIR}/initrd-tree/lib/firmware/dvb-* || true
 sudo rm -rfd ${TEMPDIR}/initrd-tree/lib/firmware/ql2* || true
 sudo rm -rfd ${TEMPDIR}/initrd-tree/lib/firmware/whiteheat* || true
 sudo rm -rfd ${TEMPDIR}/initrd-tree/lib/firmware/v4l* || true

 sudo rm -rfd ${TEMPDIR}/initrd-tree/lib/firmware/3com/ || true
 sudo rm -rfd ${TEMPDIR}/initrd-tree/lib/firmware/acenic/ || true
 sudo rm -rfd ${TEMPDIR}/initrd-tree/lib/firmware/adaptec/ || true
 sudo rm -rfd ${TEMPDIR}/initrd-tree/lib/firmware/advansys/ || true
 sudo rm -rfd ${TEMPDIR}/initrd-tree/lib/firmware/asihpi/ || true
 sudo rm -rfd ${TEMPDIR}/initrd-tree/lib/firmware/bnx2/ || true
 sudo rm -rfd ${TEMPDIR}/initrd-tree/lib/firmware/cpia2/ || true
 sudo rm -rfd ${TEMPDIR}/initrd-tree/lib/firmware/ea/ || true
 sudo rm -rfd ${TEMPDIR}/initrd-tree/lib/firmware/emi26/ || true
 sudo rm -rfd ${TEMPDIR}/initrd-tree/lib/firmware/emi62/ || true
 sudo rm -rfd ${TEMPDIR}/initrd-tree/lib/firmware/ess/ || true
 sudo rm -rfd ${TEMPDIR}/initrd-tree/lib/firmware/korg/ || true
 sudo rm -rfd ${TEMPDIR}/initrd-tree/lib/firmware/matrox/ || true
 sudo rm -rfd ${TEMPDIR}/initrd-tree/lib/firmware/myricom/ || true
 sudo rm -rfd ${TEMPDIR}/initrd-tree/lib/firmware/qlogic/ || true
 sudo rm -rfd ${TEMPDIR}/initrd-tree/lib/firmware/r128/ || true
 sudo rm -rfd ${TEMPDIR}/initrd-tree/lib/firmware/radeon/ || true
 sudo rm -rfd ${TEMPDIR}/initrd-tree/lib/firmware/sb16/ || true
 sudo rm -rfd ${TEMPDIR}/initrd-tree/lib/firmware/slicoss/ || true
 sudo rm -rfd ${TEMPDIR}/initrd-tree/lib/firmware/sun/ || true
 sudo rm -rfd ${TEMPDIR}/initrd-tree/lib/firmware/sxg/ || true
 sudo rm -rfd ${TEMPDIR}/initrd-tree/lib/firmware/tehuti/ || true
 sudo rm -rfd ${TEMPDIR}/initrd-tree/lib/firmware/tigon/ || true
 sudo rm -rfd ${TEMPDIR}/initrd-tree/lib/firmware/vicam/ || true
 sudo rm -rfd ${TEMPDIR}/initrd-tree/lib/firmware/yam/ || true
 sudo rm -rfd ${TEMPDIR}/initrd-tree/lib/firmware/yamaha/ || true

#Help debug ${DIST}-tweaks.diff patch
#echo "cd ${TEMPDIR}/initrd-tree/"
#echo "sudo patch -p1 -s < ${DIR}/scripts/${DIST}-tweaks.diff"
#exit

 cd ${TEMPDIR}/initrd-tree/
 sudo patch -p1 < ${DIR}/scripts/${DIST}-tweaks.diff
 cd ${DIR}/

case "$DIST" in
    maverick)
	sudo cp -v ${DIR}/scripts/flash-kernel.conf ${TEMPDIR}/initrd-tree/etc/flash-kernel.conf
	sudo cp -v ${DIR}/scripts/ttyO2.conf ${TEMPDIR}/initrd-tree/etc/ttyO2.conf
	sudo chmod a+x ${TEMPDIR}/initrd-tree/usr/lib/finish-install.d/08rcn-omap
	sudo cp -v ${DIR}/scripts/${DIST}-preseed.cfg ${TEMPDIR}/initrd-tree/preseed.cfg
        ;;
    squeeze)
	sudo cp -v ${DIR}/scripts/e2fsck.conf ${TEMPDIR}/initrd-tree/etc/e2fsck.conf
	sudo chmod a+x ${TEMPDIR}/initrd-tree/usr/lib/finish-install.d/08rcn-omap
	sudo cp -v ${DIR}/scripts/${DIST}-preseed.cfg ${TEMPDIR}/initrd-tree/preseed.cfg
        ;;
esac

 sudo touch ${TEMPDIR}/initrd-tree/etc/rcn.conf
 cd ${TEMPDIR}/initrd-tree/
 find . | cpio -o -H newc | gzip -9 > ${TEMPDIR}/initrd.mod.gz
 cd ${DIR}/
}

function cleanup_sd {

 echo ""
 echo "Umounting Partitions"
 echo ""

NUM_MOUNTS=$(mount | grep -v none | grep "$MMC" | wc -l)

 for (( c=1; c<=$NUM_MOUNTS; c++ ))
 do
  DRIVE=$(mount | grep -v none | grep "$MMC" | tail -1 | awk '{print $1}')
  sudo umount ${DRIVE} &> /dev/null || true
 done

 sudo parted --script ${MMC} mklabel msdos
}

function create_partitions {

sudo fdisk ${FDISK_DOS} ${MMC} << END
n
p
1
1
+64M
t
e
p
w
END

sync

sudo parted --script ${MMC} set 1 boot on

echo ""
echo "Formating Boot Partition"
echo ""

sudo mkfs.vfat -F 16 ${MMC}${PARTITION_PREFIX}1 -n ${BOOT_LABEL}

mkdir ${TEMPDIR}/disk
sudo mount ${MMC}${PARTITION_PREFIX}1 ${TEMPDIR}/disk

sudo cp -v ${TEMPDIR}/dl/${MLO} ${TEMPDIR}/disk/MLO
sudo cp -v ${TEMPDIR}/dl/${UBOOT} ${TEMPDIR}/disk/u-boot.bin

echo "uInitrd Installer"
sudo mkimage -A arm -O linux -T ramdisk -C none -a 0 -e 0 -n initramfs -d ${TEMPDIR}/initrd.mod.gz ${TEMPDIR}/disk/uInitrd.net
echo "uInitrd Normal Boot"
sudo mkimage -A arm -O linux -T ramdisk -C none -a 0 -e 0 -n initramfs -d ${DIR}/dl/${DIST}/initrd.img-${KERNEL} ${TEMPDIR}/disk/uInitrd.end
echo "uImage"
sudo mkimage -A arm -O linux -T kernel -C none -a 0x80008000 -e 0x80008000 -n ${KERNEL} -d ${TEMPDIR}/kernel/boot/vmlinuz-* ${TEMPDIR}/disk/uImage.net

if [ "${SERIAL_MODE}" ] ; then
 sudo mkimage -A arm -O linux -T script -C none -a 0 -e 0 -n "Debian Installer" -d ${DIR}/scripts/serial.cmd ${TEMPDIR}/disk/boot.scr
 sudo mkimage -A arm -O linux -T script -C none -a 0 -e 0 -n "Boot" -d ${DIR}/scripts/serial-normal-${DIST}.cmd ${TEMPDIR}/disk/user.scr
 sudo cp -v ${DIR}/scripts/serial-normal-${DIST}.cmd ${TEMPDIR}/disk/boot.cmd
else
 sudo mkimage -A arm -O linux -T script -C none -a 0 -e 0 -n "Debian Installer" -d ${DIR}/scripts/dvi.cmd ${TEMPDIR}/disk/boot.scr
 sudo mkimage -A arm -O linux -T script -C none -a 0 -e 0 -n "Boot" -d ${DIR}/scripts/dvi-normal-${DIST}.cmd ${TEMPDIR}/disk/user.scr
 sudo cp -v ${DIR}/scripts/dvi-normal-${DIST}.cmd ${TEMPDIR}/disk/boot.cmd
fi

sudo cp -v ${DIR}/dl/${DIST}/linux-image-${KERNEL}_1.0${DIST}_armel.deb ${TEMPDIR}/disk/

cat > ${TEMPDIR}/readme.txt <<script_readme

These can be run from anywhere, but just in case change to "cd /boot/uboot"

Tools:

 "./tools/update_boot_files.sh"

Updated with a custom uImage and modules or modified the boot.cmd/user.com files with new boot args? Run "./tools/update_boot_files.sh" to regenerate all boot files...

 "./tools/fix_zippy2.sh"

Early zippy2 boards had the wrong id in eeprom (zippy1).. Put a jumper on eeprom pin and run "./tools/fix_zippy2.sh" to update the eeprom contents for zippy2.

Kernel:

 "./tools/latest_kernel.sh"

Update to the latest rcn-ee.net kernel.. still some bugs in running from /boot/uboot..

Applications:

 "./tools/minimal_xfce.sh"

Install minimal xfce shell, make sure to have network setup: "sudo ifconfig -a" then "sudo dhclient usb1" or "eth0/etc"

 "./tools/get_chrome.sh"

Install Google's Chrome web browswer.

DSP work in progress.

 /tools/dsp/*

script_readme

cat > ${TEMPDIR}/update_boot_files.sh <<update_boot_files
#!/bin/sh

cd /boot/uboot
sudo mount -o remount,rw /boot/uboot

if ! ls /boot/initrd.img-\$(uname -r) >/dev/null 2>&1;then
sudo update-initramfs -c -k \$(uname -r)
else
sudo update-initramfs -u -k \$(uname -r)
fi

if ls /boot/initrd.img-\$(uname -r) >/dev/null 2>&1;then
sudo mkimage -A arm -O linux -T ramdisk -C none -a 0 -e 0 -n initramfs -d /boot/initrd.img-\$(uname -r) /boot/uboot/uInitrd
fi

if ls /boot/uboot/boot.cmd >/dev/null 2>&1;then
sudo mkimage -A arm -O linux -T script -C none -a 0 -e 0 -n "Boot Script" -d /boot/uboot/boot.cmd /boot/uboot/boot.scr
fi
if ls /boot/uboot/serial.cmd >/dev/null 2>&1;then
sudo mkimage -A arm -O linux -T script -C none -a 0 -e 0 -n "Boot Script" -d /boot/uboot/serial.cmd /boot/uboot/boot.scr
fi
sudo cp /boot/uboot/boot.scr /boot/uboot/boot.ini
if ls /boot/uboot/user.cmd >/dev/null 2>&1;then
sudo mkimage -A arm -O linux -T script -C none -a 0 -e 0 -n "Reset Nand" -d /boot/uboot/user.cmd /boot/uboot/user.scr
fi

update_boot_files

cat > ${TEMPDIR}/fix_zippy2.sh <<fix_zippy2
#!/bin/sh
#based off a script from cwillu
#make sure to have a jumper on JP1 (write protect)

if sudo i2cdump -y 2 0x50 | grep "00: 00 01 00 01 01 00 00 00"; then
    sudo i2cset -y 2 0x50 0x03 0x02
fi

fix_zippy2

cat > ${TEMPDIR}/latest_kernel.sh <<latest_kernel
#!/bin/bash
DIST=\$(lsb_release -cs)

#enable testing
#TESTING=1

function run_upgrade {

 wget --no-verbose --directory-prefix=/tmp/ \${KERNEL_DL}

 if [ -f /tmp/install-me.sh ] ; then
  mv /tmp/install-me.sh ~/
 fi

echo "switch to home directory and run"
echo "cd ~/"
echo ". install-me.sh"

}

function check_latest {

 if [ -f /tmp/LATEST ] ; then
  rm -f /tmp/LATEST &> /dev/null
 fi

 wget --no-verbose --directory-prefix=/tmp/ http://rcn-ee.net/deb/\${DIST}/LATEST

 KERNEL_DL=\$(cat /tmp/LATEST | grep "ABI:1 STABLE" | awk '{print \$3}')

 if [ "\$TESTING" ] ; then
  KERNEL_DL=\$(cat /tmp/LATEST | grep "ABI:1 TESTING" | awk '{print \$3}')
 fi

 KERNEL_DL_VER=\$(echo \${KERNEL_DL} | awk -F'/' '{print \$6}')

 CURRENT_KER="v\$(uname -r)"

 if [ \${CURRENT_KER} != \${KERNEL_DL_VER} ]; then
  run_upgrade
 fi
}

check_latest

latest_kernel

cat > ${TEMPDIR}/minimal_xfce.sh <<basic_xfce
#!/bin/sh

sudo apt-get update
sudo apt-get -y install xfce4 gdm xubuntu-gdm-theme xubuntu-artwork xserver-xorg-video-omap3

basic_xfce

cat > ${TEMPDIR}/get_chrome.sh <<latest_chrome
#!/bin/sh

#setup libs

sudo apt-get update
sudo apt-get -y install libnss3-1d unzip libxss1

sudo ln -sf /usr/lib/libsmime3.so /usr/lib/libsmime3.so.12
sudo ln -sf /usr/lib/libnssutil3.so /usr/lib/libnssutil3.so.12
sudo ln -sf /usr/lib/libnss3.so /usr/lib/libnss3.so.12

sudo ln -sf /usr/lib/libplds4.so /usr/lib/libplds4.so.8
sudo ln -sf /usr/lib/libplc4.so /usr/lib/libplc4.so.8
sudo ln -sf /usr/lib/libnspr4.so /usr/lib/libnspr4.so.8

if [ -f /tmp/LATEST ] ; then
 rm -f /tmp/LATEST &> /dev/null
fi

if [ -f /tmp/chrome-linux.zip ] ; then
 rm -f /tmp/chrome-linux.zip &> /dev/null
fi

wget --no-verbose --directory-prefix=/tmp/ http://build.chromium.org/buildbot/snapshots/chromium-rel-arm/LATEST

CHROME_VER=\$(cat /tmp/LATEST)

wget --directory-prefix=/tmp/ http://build.chromium.org/buildbot/snapshots/chromium-rel-arm/\${CHROME_VER}/chrome-linux.zip

sudo mkdir -p /opt/chrome-linux/
sudo chown -R \$USER:\$USER /opt/chrome-linux/

if [ -f /tmp/chrome-linux.zip ] ; then
 unzip -o /tmp/chrome-linux.zip -d /opt/
fi

cat > /tmp/chrome.desktop <<chrome_launcher
[Desktop Entry]
Version=1.0
Type=Application
Encoding=UTF-8
Exec=/opt/chrome-linux/chrome %u
Icon=web-browser
StartupNotify=false
Terminal=false
Categories=X-XFCE;X-Xfce-Toplevel;
OnlyShowIn=XFCE;
Name=Chromium

chrome_launcher

sudo mv /tmp/chrome.desktop /usr/share/applications/chrome.desktop

latest_chrome

cat > ${TEMPDIR}/dsp-init <<dspscript
#!/bin/sh

case "\$1" in
	start)
		modprobe mailbox_mach
		modprobe bridgedriver base_img=/lib/dsp/baseimage.dof
		;;
esac

dspscript

cat > ${TEMPDIR}/install-dsp-init.sh <<installDSP
#!/bin/bash

DIR=\$PWD

if [ \$(uname -m) == "armv7l" ] ; then

# if [ -e  \${DIR}/dsp_libs.tar.gz ]; then

#  echo "Extracting target files to rootfs"
#  sudo tar xf dsp_libs.tar.gz -C /

  if which lsb_release >/dev/null 2>&1 && [ "\$(lsb_release -is)" = Ubuntu ]; then

    if [ \$(lsb_release -sc) == "jaunty" ]; then
      sudo cp /uboot/boot/tools/dsp/dsp-init /etc/rcS.d/S61dsp.sh
      sudo chmod +x /etc/rcS.d/S61dsp.sh
    else
      #karmic/lucid/maverick/etc
      sudo cp /uboot/boot/tools/dsp/dsp-init /etc/init.d/dsp
      sudo chmod +x /etc/init.d/dsp
      sudo update-rc.d dsp defaults
    fi

  else

    sudo cp /uboot/boot/tools/dsp/dsp-init /etc/init.d/dsp
    sudo chmod +x /etc/init.d/dsp
    sudo update-rc.d dsp defaults

  fi

# else
#  echo "dsp_libs.tar.gz is missing"
#  exit
# fi

else
 echo "This script is to be run on an armv7 platform"
 exit
fi

installDSP

cat > ${TEMPDIR}/install-gst-dsp.sh <<installgst
#!/bin/bash

DIR=\$HOME

function no_connection {

echo "setup internet connection before running.."
exit

}

ping -c 1 -w 100 www.google.com  | grep "ttl=" || no_connection

sudo apt-get -y install git-core pkg-config build-essential gstreamer-tools libgstreamer0.10-dev

mkdir -p \${DIR}/git/

if ! ls \${DIR}/git/gst-dsp >/dev/null 2>&1;then
cd \${DIR}/git/
git clone git://github.com/felipec/gst-dsp.git
fi

cd \${DIR}/git/gst-dsp
make clean
git pull
make CROSS_COMPILE= 
sudo make install
cd \${DIR}/

if ! ls \${DIR}/git/gst-omapfb >/dev/null 2>&1;then
cd \${DIR}/git/
git clone git://github.com/felipec/gst-omapfb.git
fi

cd \${DIR}/git/gst-omapfb
make clean
git pull
make CROSS_COMPILE= 
sudo make install
cd \${DIR}/

if ! ls \${DIR}/git/dsp-tools >/dev/null 2>&1;then
cd \${DIR}/git/
git clone git://github.com/felipec/dsp-tools.git
fi

cd \${DIR}/git/dsp-tools
make clean
git pull
make CROSS_COMPILE= 
sudo make install
cd \${DIR}/

installgst

 sudo mkdir -p ${TEMPDIR}/disk/tools/dsp
 sudo cp -v ${TEMPDIR}/readme.txt ${TEMPDIR}/disk/tools/readme.txt

 sudo cp -v ${TEMPDIR}/update_boot_files.sh ${TEMPDIR}/disk/tools/update_boot_files.sh
 sudo chmod +x ${TEMPDIR}/disk/tools/update_boot_files.sh

 sudo cp -v ${TEMPDIR}/fix_zippy2.sh ${TEMPDIR}/disk/tools/fix_zippy2.sh
 sudo chmod +x ${TEMPDIR}/disk/tools/fix_zippy2.sh

 sudo cp -v ${TEMPDIR}/latest_kernel.sh ${TEMPDIR}/disk/tools/latest_kernel.sh
 sudo chmod +x ${TEMPDIR}/disk/tools/latest_kernel.sh

 sudo cp -v ${TEMPDIR}/minimal_xfce.sh ${TEMPDIR}/disk/tools/minimal_xfce.sh
 sudo chmod +x ${TEMPDIR}/disk/tools/minimal_xfce.sh

 sudo cp -v ${TEMPDIR}/get_chrome.sh ${TEMPDIR}/disk/tools/get_chrome.sh
 sudo chmod +x ${TEMPDIR}/disk/tools/get_chrome.sh

 sudo cp -v ${TEMPDIR}/dsp-init ${TEMPDIR}/disk/tools/dsp/dsp-init
 sudo chmod +x ${TEMPDIR}/disk/tools/dsp/dsp-init

 sudo cp -v ${TEMPDIR}/install-dsp-init.sh ${TEMPDIR}/disk/tools/dsp/install-dsp-init.sh 
 sudo chmod +x ${TEMPDIR}/disk/tools/dsp/install-dsp-init.sh 

 sudo cp -v ${TEMPDIR}/install-gst-dsp.sh ${TEMPDIR}/disk/tools/dsp/install-gst-dsp.sh
 sudo chmod +x ${TEMPDIR}/disk/tools/dsp/install-gst-dsp.sh

cd ${TEMPDIR}/disk
sync
cd ${DIR}/
sudo umount ${TEMPDIR}/disk || true
echo "done"

}

function reset_scripts {

 if [ "$USB_ROOTFS" ];then
  sed -i 's/sda1/mmcblk0p5/g' ${DIR}/scripts/dvi-normal-maverick.cmd
  sed -i 's/sda1/mmcblk0p5/g' ${DIR}/scripts/dvi-normal-squeeze.cmd

  sed -i 's/sda1/mmcblk0p5/g' ${DIR}/scripts/serial-normal-maverick.cmd
  sed -i 's/sda1/mmcblk0p5/g' ${DIR}/scripts/serial-normal-squeeze.cmd
 fi

 if [ "$PRINTK" ];then
  sed -i 's/bootargs earlyprintk/bootargs/g' ${DIR}/scripts/serial*.cmd
 fi

}

function check_mmc {
 FDISK=$(sudo LC_ALL=C fdisk -l 2>/dev/null | grep "[Disk] ${MMC}" | awk '{print $2}')

 if test "-$FDISK-" = "-$MMC:-"
 then
  echo ""
  echo "I see..."
  echo "sudo fdisk -l:"
  sudo LC_ALL=C fdisk -l 2>/dev/null | grep "[Disk] /dev/" --color=never
  echo ""
  echo "mount:"
  mount | grep -v none | grep "/dev/" --color=never
  echo ""
  read -p "Are you 100% sure, on selecting [${MMC}] (y/n)? "
  [ "$REPLY" == "y" ] || exit
  echo ""
 else
  echo ""
  echo "Are you sure? I Don't see [${MMC}], here is what I do see..."
  echo ""
  echo "sudo fdisk -l:"
  sudo LC_ALL=C fdisk -l 2>/dev/null | grep "[Disk] /dev/" --color=never
  echo ""
  echo "mount:"
  mount | grep -v none | grep "/dev/" --color=never
  echo ""
  exit
 fi
}

function check_uboot_type {
 IN_VALID_UBOOT=1
 unset DO_UBOOT

case "$UBOOT_TYPE" in
    beagle)

 SYSTEM=beagle
 unset IN_VALID_UBOOT
 DO_UBOOT=1

        ;;
    panda)

 SYSTEM=panda
 unset IN_VALID_UBOOT
 DO_UBOOT=1

 #with the panda, we just need the beta kernel, both dvi and serial work..
 BETA_KERNEL=1

        ;;
    touchbook)

 SYSTEM=touchbook
 unset IN_VALID_UBOOT
 DO_UBOOT=1

 #with the panda, we need the beta kernel and serial-more
 BETA_KERNEL=1
 SERIAL_MODE=1

        ;;
    crane)

 SYSTEM=crane
 unset IN_VALID_UBOOT
 DO_UBOOT=1

 #with the crane, we need the beta kernel and serial-more
 SERIAL_MODE=1

        ;;

esac

 if [ "$IN_VALID_UBOOT" ] ; then
   usage
 fi
}

function check_distro {
 IN_VALID_DISTRO=1

 if test "-$DISTRO_TYPE-" = "-squeeze-"
 then
 DIST=squeeze
 unset IN_VALID_DISTRO
 fi

 if test "-$DISTRO_TYPE-" = "-maverick-"
 then
 DIST=maverick
 unset IN_VALID_DISTRO
 fi

# if test "-$DISTRO_TYPE-" = "-sid-"
# then
# DIST=sid
# unset IN_VALID_DISTRO
# fi

 if [ "$IN_VALID_DISTRO" ] ; then
   usage
 fi
}

function usage {
    echo "usage: $(basename $0) --mmc /dev/sdd"
cat <<EOF

Bugs: email "bugs at rcn-ee.com"

required options:
--mmc </dev/sdX>
    Unformated MMC Card

--uboot <dev board>
    beagle - <Bx, C2/C3/C4, xMA, xMB>
    panda - <dvi or serial>
    touchbook - <serial only>

--distro <distro>
    Debian:
      squeeze <default>
    Ubuntu
      maverick <works with all BeagleBoard's>

--firmware
    Add distro firmware

Optional:
--dvi-mode 
    <default>

--serial-mode

--usb-rootfs
    <root=/dev/sda1>

Additional/Optional options:
-h --help
    this help
EOF
exit
}

function checkparm {
    if [ "$(echo $1|grep ^'\-')" ];then
        echo "E: Need an argument"
        usage
    fi
}

# parse commandline options
while [ ! -z "$1" ]; do
    case $1 in
        -h|--help)
            usage
            MMC=1
            ;;
        --mmc)
            checkparm $2
            MMC="$2"
	    if [[ "${MMC}" =~ "mmcblk" ]]
            then
	        PARTITION_PREFIX="p"
            fi
            check_mmc 
            ;;
        --uboot)
            checkparm $2
            UBOOT_TYPE="$2"
            check_uboot_type
            ;;
        --distro)
            checkparm $2
            DISTRO_TYPE="$2"
            check_distro
            ;;
        --firmware)
            FIRMWARE=1
            ;;
        --dvi-mode)
            unset SERIAL_MODE
            ;;
        --serial-mode)
            SERIAL_MODE=1
            ;;
        --beta-kernel)
            BETA_KERNEL=1
            ;;
        --beta-boot)
            BETA_BOOT=1
            ;;
	--usb-rootfs)
            USB_ROOTFS=1
            ;;
	--earlyprintk)
            PRINTK=1
            ;;
    esac
    shift
done

if [ ! "${MMC}" ];then
    usage
fi

 detect_software
 set_defaults
 dl_xload_uboot
 prepare_initrd
 prepare_uimage
 cleanup_sd
 create_partitions
 reset_scripts

