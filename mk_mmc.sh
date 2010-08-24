#!/bin/bash -e

#Notes: need to check for: parted, fdisk, wget, mkfs.*, mkimage, md5sum

MIRROR="http://rcn-ee.net/deb/"
DIST=squeeze
KERNEL_REL=2.6.35.3
KERNEL_PATCH=1

unset MMC
unset FIRMWARE
unset SERIAL_MODE

BOOT_LABEL=boot
PARTITION_PREFIX=""

DIR=$PWD

function dl_xload_uboot {
# sudo rm -rfd ${DIR}/deploy/ || true
 mkdir -p ${DIR}/deploy/

 echo ""
 echo "Downloading X-loader, Uboot, Kernel and Debian Installer"
 echo ""

 rm -f ${DIR}/deploy/bootloader || true
 wget -c --no-verbose --directory-prefix=${DIR}/deploy/ ${MIRROR}tools/latest/bootloader

 MLO=$(cat ${DIR}/deploy/bootloader | grep "ABI:1 MLO" | awk '{print $3}')
 UBOOT=$(cat ${DIR}/deploy/bootloader | grep "ABI:1 UBOOT" | awk '{print $3}')

 wget -c --no-verbose --directory-prefix=${DIR}/deploy/ ${MLO}
 wget -c --no-verbose --directory-prefix=${DIR}/deploy/ ${UBOOT}

 MLO=${MLO##*/}
 UBOOT=${UBOOT##*/}

 if test "-$DIST-" = "-lucid-"
 then
  KERNEL=${KERNEL_REL}-l${KERNEL_PATCH}
  rm -f ${DIR}/deploy/initrd.gz || true
  wget -c --directory-prefix=${DIR}/deploy/ http://ports.ubuntu.com/ubuntu-ports/dists/${DIST}/main/installer-armel/current/images/versatile/netboot/initrd.gz
  wget -c --directory-prefix=${DIR}/deploy/ http://ports.ubuntu.com/pool/universe/m/mtd-utils/mtd-utils_20090606-1_armel.deb
 else
  KERNEL=${KERNEL_REL}-x${KERNEL_PATCH}
  rm -f ${DIR}/deploy/initrd.gz || true
  wget -c --directory-prefix=${DIR}/deploy/ http://ftp.debian.org/debian/dists/${DIST}/main/installer-armel/current/images/versatile/netboot/initrd.gz
 fi

 wget -c --directory-prefix=${DIR}/deploy/ ${MIRROR}${DIST}/v${KERNEL}/linux-image-${KERNEL}_1.0${DIST}_armel.deb

 wget -c --directory-prefix=${DIR}/deploy/ ${MIRROR}${DIST}/v${KERNEL}/initrd.img-${KERNEL}

if [ "${FIRMWARE}" ] ; then

 echo ""
 echo "Downloading Firmware"
 echo ""

 if test "-$DIST-" = "-lucid-"
 then
  wget -c --directory-prefix=${DIR}/deploy/ http://ports.ubuntu.com/pool/main/l/linux-firmware/linux-firmware_1.34_all.deb
  wget -c --directory-prefix=${DIR}/deploy/ http://ports.ubuntu.com/pool/multiverse/l/linux-firmware-nonfree/linux-firmware-nonfree_1.8_all.deb
 else
  #from: http://packages.debian.org/source/squeeze/firmware-nonfree

  #Atmel
  rm -f ${DIR}/deploy/index.html
  wget --directory-prefix=${DIR}/deploy/ ftp://ftp.us.debian.org/debian/pool/non-free/a/atmel-firmware/
  ATMEL_FW=$(cat ${DIR}/deploy/index.html | grep atmel | grep -v diff.gz | grep -v .dsc | grep -v orig.tar.gz | tail -1 | awk -F"\"" '{print $2}')
  wget -c --directory-prefix=${DIR}/deploy/ ${ATMEL_FW}
  ATMEL_FW=${ATMEL_FW##*/}

  #Ralink
  rm -f ${DIR}/deploy/index.html
  wget --directory-prefix=${DIR}/deploy/ ftp://ftp.us.debian.org/debian/pool/non-free/f/firmware-nonfree/
  RALINK_FW=$(cat ${DIR}/deploy/index.html | grep ralink | grep -v lenny | tail -1 | awk -F"\"" '{print $2}')
  wget -c --directory-prefix=${DIR}/deploy/ ${RALINK_FW}
  RALINK_FW=${RALINK_FW##*/}

  #libertas
  rm -f ${DIR}/deploy/index.html
  wget --directory-prefix=${DIR}/deploy/ ftp://ftp.us.debian.org/debian/pool/non-free/libe/libertas-firmware/
  LIBERTAS_FW=$(cat ${DIR}/deploy/index.html | grep libertas | grep -v diff.gz | grep -v .dsc | grep -v orig.tar.gz | tail -1 | awk -F"\"" '{print $2}')
  wget -c --directory-prefix=${DIR}/deploy/ ${LIBERTAS_FW}
  LIBERTAS_FW=${LIBERTAS_FW##*/}

  #zd1211
  rm -f ${DIR}/deploy/index.html
  wget --directory-prefix=${DIR}/deploy/ ftp://ftp.us.debian.org/debian/pool/non-free/z/zd1211-firmware/
  ZD1211_FW=$(cat ${DIR}/deploy/index.html | grep zd1211 | grep -v diff.gz | grep -v tar.gz | grep -v .dsc | tail -1 | awk -F"\"" '{print $2}')
  wget -c --directory-prefix=${DIR}/deploy/ ${ZD1211_FW}
  ZD1211_FW=${ZD1211_FW##*/}
 fi
fi

}

function prepare_uimage {
 sudo rm -rfd ${DIR}/kernel || true
 mkdir -p ${DIR}/kernel
 cd ${DIR}/kernel
 sudo dpkg -x ${DIR}/deploy/linux-image-${KERNEL}_1.0${DIST}_armel.deb ${DIR}/kernel
}

function prepare_initrd {
 sudo rm -rfd ${DIR}/initrd-tree || true
 mkdir -p ${DIR}/initrd-tree
 cd ${DIR}/initrd-tree
 sudo zcat ${DIR}/deploy/initrd.gz | sudo cpio -i -d
 sudo dpkg -x ${DIR}/deploy/linux-image-${KERNEL}_1.0${DIST}_armel.deb ${DIR}/initrd-tree

if [ "${FIRMWARE}" ] ; then
 if test "-$DIST-" = "-lucid-"
 then
  sudo dpkg -x ${DIR}/deploy/linux-firmware_1.34_all.deb ${DIR}/initrd-tree
  sudo dpkg -x ${DIR}/deploy/linux-firmware-nonfree_1.8_all.deb ${DIR}/initrd-tree
 else
 #from: http://packages.debian.org/source/squeeze/firmware-nonfree
  sudo dpkg -x ${DIR}/deploy/${ATMEL_FW} ${DIR}/initrd-tree
  sudo dpkg -x ${DIR}/deploy/${RALINK_FW} ${DIR}/initrd-tree
  sudo dpkg -x ${DIR}/deploy/${LIBERTAS_FW} ${DIR}/initrd-tree
  sudo dpkg -x ${DIR}/deploy/${ZD1211_FW} ${DIR}/initrd-tree
 fi
fi

 #Cleanup some of the extra space..
 sudo rm -f ${DIR}/initrd-tree/boot/*-${KERNEL} || true
 sudo rm -rfd ${DIR}/initrd-tree/lib/modules/${KERNEL}/kernel/drivers/media/ || true
 sudo rm -rfd ${DIR}/initrd-tree/lib/modules/${KERNEL}/kernel/drivers/usb/serial/ || true
 sudo rm -rfd ${DIR}/initrd-tree/lib/modules/${KERNEL}/kernel/drivers/usb/misc/ || true

 sudo rm -rfd ${DIR}/initrd-tree/lib/modules/${KERNEL}/kernel/drivers/net/irda/ || true
 sudo rm -rfd ${DIR}/initrd-tree/lib/modules/${KERNEL}/kernel/drivers/net/hamradio/ || true
 sudo rm -rfd ${DIR}/initrd-tree/lib/modules/${KERNEL}/kernel/drivers/net/can/ || true

 sudo rm -rfd ${DIR}/initrd-tree/lib/modules/${KERNEL}/kernel/drivers/misc || true

 sudo rm -rfd ${DIR}/initrd-tree/lib/modules/${KERNEL}/kernel/net/irda/ || true
 sudo rm -rfd ${DIR}/initrd-tree/lib/modules/${KERNEL}/kernel/net/decnet/ || true

 sudo rm -rfd ${DIR}/initrd-tree/lib/modules/${KERNEL}/kernel/fs/ || true
 sudo rm -rfd ${DIR}/initrd-tree/lib/modules/${KERNEL}/kernel/sound/ || true
 sudo rm -rfd ${DIR}/initrd-tree/lib/modules/*-versatile/ || true
 sudo rm -rfd ${DIR}/initrd-tree/lib/firmware/*-versatile/ || true

 #introduced with the big linux-firmware
 #http://packages.ubuntu.com/lucid/all/linux-firmware/filelist

 sudo rm -rfd ${DIR}/initrd-tree/lib/firmware/agere* || true
 sudo rm -rfd ${DIR}/initrd-tree/lib/firmware/bnx2x-* || true
 sudo rm -rfd ${DIR}/initrd-tree/lib/firmware/dvb-* || true
 sudo rm -rfd ${DIR}/initrd-tree/lib/firmware/ql2* || true
 sudo rm -rfd ${DIR}/initrd-tree/lib/firmware/v4l* || true

 sudo rm -rfd ${DIR}/initrd-tree/lib/firmware/3com/ || true
 sudo rm -rfd ${DIR}/initrd-tree/lib/firmware/acenic/ || true
 sudo rm -rfd ${DIR}/initrd-tree/lib/firmware/adaptec/ || true
 sudo rm -rfd ${DIR}/initrd-tree/lib/firmware/advansys/ || true
 sudo rm -rfd ${DIR}/initrd-tree/lib/firmware/bnx2/ || true
 sudo rm -rfd ${DIR}/initrd-tree/lib/firmware/ea/ || true
 sudo rm -rfd ${DIR}/initrd-tree/lib/firmware/matrox/ || true
 sudo rm -rfd ${DIR}/initrd-tree/lib/firmware/qlogic/ || true
 sudo rm -rfd ${DIR}/initrd-tree/lib/firmware/r128/ || true
 sudo rm -rfd ${DIR}/initrd-tree/lib/firmware/radeon/ || true
 sudo rm -rfd ${DIR}/initrd-tree/lib/firmware/slicoss/ || true
 sudo rm -rfd ${DIR}/initrd-tree/lib/firmware/tigon/ || true

 sudo patch -p1 -s < ${DIR}/scripts/${DIST}-tweaks.diff

 if test "-$DIST-" = "-lucid-"
 then
   #sudo cp -v ${DIR}/scripts/e2fsck.conf ${DIR}/initrd-tree/etc/e2fsck.conf
   sudo cp -v ${DIR}/scripts/flash-kernel.conf ${DIR}/initrd-tree/etc/flash-kernel.conf
   sudo cp -v ${DIR}/scripts/ttyS2.conf ${DIR}/initrd-tree/etc/ttyS2.conf
   sudo dpkg -x ${DIR}/deploy/mtd-utils_20090606-1_armel.deb ${DIR}/initrd-tree
 fi

 if test "-$DIST-" = "-squeeze-"
 then
   sudo cp -v ${DIR}/scripts/e2fsck.conf ${DIR}/initrd-tree/etc/e2fsck.conf
 fi

 sudo touch ${DIR}/initrd-tree/etc/rcn.conf

 find . | cpio -o -H newc | gzip -9 > ${DIR}/initrd.mod.gz
 cd ${DIR}/
 sudo rm -f ${DIR}/initrd.mod || true
 sudo gzip -d ${DIR}/initrd.mod.gz
}

function cleanup_sd {

 echo ""
 echo "Umounting Partitions"
 echo ""

 sudo umount ${MMC}${PARTITION_PREFIX}1 &> /dev/null || true
 sudo umount ${MMC}${PARTITION_PREFIX}2 &> /dev/null || true

 sudo parted -s ${MMC} mklabel msdos
}

function create_partitions {

sudo fdisk -H 255 -S 63 ${MMC} << END
n
p
1
1
+64M
a
1
t
e
p
w
END

echo ""
echo "Formating Boot Partition"
echo ""

sudo mkfs.vfat -F 16 ${MMC}${PARTITION_PREFIX}1 -n ${BOOT_LABEL} &> ${DIR}/sd.log

sudo rm -rfd ${DIR}/disk || true

mkdir ${DIR}/disk
sudo mount ${MMC}${PARTITION_PREFIX}1 ${DIR}/disk

sudo cp -v ${DIR}/deploy/${MLO} ${DIR}/disk/MLO
sudo cp -v ${DIR}/deploy/${UBOOT} ${DIR}/disk/u-boot.bin

sudo mkimage -A arm -O linux -T ramdisk -C none -a 0 -e 0 -n initramfs -d ${DIR}/initrd.mod ${DIR}/disk/uInitrd
sudo mkimage -A arm -O linux -T ramdisk -C none -a 0 -e 0 -n initramfs -d ${DIR}/deploy/initrd.img-${KERNEL} ${DIR}/disk/uInitrd.final
sudo mkimage -A arm -O linux -T kernel -C none -a 0x80008000 -e 0x80008000 -n ${KERNEL} -d ${DIR}/kernel/boot/vmlinuz-* ${DIR}/disk/uImage

if [ "${SERIAL_MODE}" ] ; then
 sudo mkimage -A arm -O linux -T script -C none -a 0 -e 0 -n "Debian Installer" -d ${DIR}/scripts/serial.cmd ${DIR}/disk/boot.scr
 sudo mkimage -A arm -O linux -T script -C none -a 0 -e 0 -n "Boot" -d ${DIR}/scripts/serial-normal-${DIST}.cmd ${DIR}/disk/normal.scr
 sudo cp -v ${DIR}/scripts/serial-normal-${DIST}.cmd ${DIR}/disk/boot.cmd
else
 sudo mkimage -A arm -O linux -T script -C none -a 0 -e 0 -n "Debian Installer" -d ${DIR}/scripts/dvi.cmd ${DIR}/disk/boot.scr
 sudo mkimage -A arm -O linux -T script -C none -a 0 -e 0 -n "Boot" -d ${DIR}/scripts/dvi-normal-${DIST}.cmd ${DIR}/disk/normal.scr
 sudo cp -v ${DIR}/scripts/dvi-normal-${DIST}.cmd ${DIR}/disk/boot.cmd
fi

cat > /tmp/user.cmd <<beagle_user_cmd

if test "\${beaglerev}" = "xMA"; then
echo "Kernel is not ready for 1Ghz limiting to 800Mhz"
setenv dvimode 1280x720MR-16@60
setenv vram 12MB
setenv bootcmd 'mmc init; fatload mmc 0:1 0x80300000 uImage; fatload mmc 0:1 0x81600000 uInitrd; bootm 0x80300000 0x81600000'
setenv bootargs console=ttyS2,115200n8 console=tty0 root=/dev/mmcblk0p2 rootwait ro vram=\${vram} omapfb.mode=dvi:\${dvimode} fixrtc buddy=\${buddy} mpurate=800
boot
else
echo "Starting NAND UPGRADE, do not REMOVE SD CARD or POWER till Complete"
fatload mmc 0:1 0x80200000 MLO
nandecc hw
nand erase 0 80000
nand write 0x80200000 0 20000
nand write 0x80200000 20000 20000
nand write 0x80200000 40000 20000
nand write 0x80200000 60000 20000

fatload mmc 0:1 0x80300000 u-boot.bin
nandecc sw
nand erase 80000 160000
nand write 0x80300000 80000 160000
nand erase 260000 20000
echo "UPGRADE Complete, REMOVE SD CARD and DELETE this boot.scr"
exit
fi

beagle_user_cmd

 sudo mkimage -A arm -O linux -T script -C none -a 0 -e 0 -n "Reset Nand" -d /tmp/user.cmd ${DIR}/disk/user.scr
 sudo cp /tmp/user.cmd ${DIR}/disk/user.cmd

cat > /tmp/rebuild_uinitrd.sh <<rebuild_uinitrd
#!/bin/sh

cd /boot/uboot
sudo mount -o remount,rw /boot/uboot
sudo update-initramfs -u -k \$(uname -r)
sudo mkimage -A arm -O linux -T ramdisk -C none -a 0 -e 0 -n initramfs -d /boot/initrd.img-\$(uname -r) /boot/uboot/uInitrd

rebuild_uinitrd

cat > /tmp/boot_scripts.sh <<rebuild_scripts
#!/bin/sh

cd /boot/uboot
sudo mount -o remount,rw /boot/uboot
sudo mkimage -A arm -O linux -T script -C none -a 0 -e 0 -n "Boot Script" -d /boot/uboot/boot.cmd /boot/uboot/boot.scr
sudo cp /boot/uboot/boot.scr /boot/uboot/boot.ini
sudo mkimage -A arm -O linux -T script -C none -a 0 -e 0 -n "Reset Nand" -d /boot/uboot/user.cmd /boot/uboot/user.scr

rebuild_scripts

cat > /tmp/fix_zippy2.sh <<fix_zippy2
#!/bin/sh
#based off a script from cwillu
#make sure to have a jumper on JP1 (write protect)

if sudo i2cdump -y 2 0x50 | grep "00: 00 01 00 01 01 00 00 00"; then
    sudo i2cset -y 2 0x50 0x03 0x02
fi

fix_zippy2

cat > /tmp/latest_kernel.sh <<latest_kernel
#!/bin/bash
DIST=\$(lsb_release -cs)

#enable testing
#TESTING=1

function run_upgrade {

 wget --no-verbose --directory-prefix=/tmp/ \${KERNEL_DL}

 if [ -f /tmp/install-me.sh ] ; then
  . /tmp/install-me.sh
 fi

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

 sudo mkdir -p ${DIR}/disk/tools
 sudo cp -v /tmp/rebuild_uinitrd.sh ${DIR}/disk/tools/rebuild_uinitrd.sh
 sudo chmod +x ${DIR}/disk/tools/rebuild_uinitrd.sh

 sudo cp -v /tmp/boot_scripts.sh ${DIR}/disk/tools/boot_scripts.sh
 sudo chmod +x ${DIR}/disk/tools/boot_scripts.sh

 sudo cp -v /tmp/fix_zippy2.sh ${DIR}/disk/tools/fix_zippy2.sh
 sudo chmod +x ${DIR}/disk/tools/fix_zippy2.sh

 sudo cp -v /tmp/latest_kernel.sh ${DIR}/disk/tools/latest_kernel.sh
 sudo chmod +x ${DIR}/disk/tools/latest_kernel.sh

cd ${DIR}/disk
sync
cd ${DIR}/
sudo umount ${DIR}/disk || true
echo "done"

}

function check_mmc {
 DISK_NAME="Disk|Platte|Disco"
 FDISK=$(sudo fdisk -l 2>/dev/null | grep "[${DISK_NAME}] ${MMC}" | awk '{print $2}')

 if test "-$FDISK-" = "-$MMC:-"
 then
  echo ""
  echo "I see..."
  echo "sudo fdisk -l:"
  sudo fdisk -l 2>/dev/null | grep "[${DISK_NAME}] /dev/" --color=never
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
  sudo fdisk -l 2>/dev/null | grep "[${DISK_NAME}] /dev/" --color=never
  echo ""
  echo "mount:"
  mount | grep -v none | grep "/dev/" --color=never
  echo ""
  exit
 fi
}

function check_distro {
 IN_VALID_DISTRO=1

 if test "-$DISTRO_TYPE-" = "-squeeze-"
 then
 read -p "Squeeze is still in ALPHA/BETA and is not currently released, are you 100% sure you want to try to install it... (y/n)? "
 [ "$REPLY" == "y" ] || exit
 DIST=squeeze
 unset IN_VALID_DISTRO
 fi

 if test "-$DISTRO_TYPE-" = "-lucid-"
 then
 DIST=lucid
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

required options:
--mmc </dev/sdX>
    Unformated MMC Card

--distro <distro>
    Debian:
      squeeze <default>
    Ubuntu
      lucid

--firmware
    Add distro firmware

Optional:
--dvi-mode 
    <default>

--serial-mode

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
    esac
    shift
done

if [ ! "${MMC}" ];then
    usage
fi

 dl_xload_uboot
 prepare_initrd
 prepare_uimage
 cleanup_sd
 create_partitions

