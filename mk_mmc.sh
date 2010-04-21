#!/bin/bash -e

#Notes: need to check for: parted, fdisk, wget, mkfs.*, mkimage, md5sum

MIRROR="http://rcn-ee.net/deb/"
MLO="MLO-beagleboard-1.44+r10+gitr1c9276af4d6a5b7014a7630a1abeddf3b3177563-r10"
XLOAD="x-load-beagleboard-1.44+r10+gitr1c9276af4d6a5b7014a7630a1abeddf3b3177563-r10.bin.ift"
UBOOT="u-boot-beagleboard-2010.03-rc1+r44+gitr946351081bd14e8bf5816fc38b82e004a0e6b4fe-r44.bin"
DIST=squeeze
KERNEL_REL=2.6.32.11
KERNEL_PATCH=13

unset MMC
unset FIRMWARE
unset SERIAL_MODE

BOOT_LABEL=boot

DIR=$PWD

function dl_xload_uboot {

 mkdir -p ${DIR}/dl/

 echo ""
 echo "Downloading X-loader, Uboot, Kernel and Debian Installer"
 echo ""

 wget -c --no-verbose --directory-prefix=${DIR}/dl/ ${MIRROR}tools/${MLO}
 wget -c --no-verbose --directory-prefix=${DIR}/dl/ ${MIRROR}tools/${XLOAD}
 wget -c --no-verbose --directory-prefix=${DIR}/dl/ ${MIRROR}tools/${UBOOT}

 if test "-$DIST-" = "-lucid-"
 then
  KERNEL=${KERNEL_REL}-l${KERNEL_PATCH}
  rm -f ${DIR}/dl/initrd.gz || true
  wget -c --directory-prefix=${DIR}/dl/ http://ports.ubuntu.com/ubuntu-ports/dists/${DIST}/main/installer-armel/current/images/versatile/netboot/initrd.gz
  wget -c --directory-prefix=${DIR}/dl/ http://ports.ubuntu.com/pool/universe/m/mtd-utils/mtd-utils_20090606-1_armel.deb
 else
  KERNEL=${KERNEL_REL}-x${KERNEL_PATCH}
  rm -f ${DIR}/dl/initrd.gz || true
  wget -c --directory-prefix=${DIR}/dl/ http://ftp.debian.org/debian/dists/${DIST}/main/installer-armel/current/images/versatile/netboot/initrd.gz
 fi

 wget -c --directory-prefix=${DIR}/dl/ ${MIRROR}kernel/beagle/${DIST}/v${KERNEL}/linux-image-${KERNEL}_1.0${DIST}_armel.deb
 wget -c --directory-prefix=${DIR}/dl/ ${MIRROR}${DIST}/v${KERNEL}/initrd.img-${KERNEL}

if [ "${FIRMWARE}" ] ; then

 echo ""
 echo "Downloading Firmware"
 echo ""

 if test "-$DIST-" = "-lucid-"
 then
  wget -c --directory-prefix=${DIR}/dl/ http://ports.ubuntu.com/pool/multiverse/l/linux-firmware-nonfree/linux-firmware-nonfree_1.8_all.deb
 else
  #from: http://packages.debian.org/source/squeeze/firmware-nonfree
  wget -c --directory-prefix=${DIR}/dl/ http://ftp.us.debian.org/debian/pool/non-free/a/atmel-firmware/atmel-firmware_1.3-4_all.deb
  wget -c --directory-prefix=${DIR}/dl/ http://ftp.us.debian.org/debian/pool/non-free/f/firmware-nonfree/firmware-ralink_0.23_all.deb
  wget -c --directory-prefix=${DIR}/dl/ http://ftp.us.debian.org/debian/pool/non-free/libe/libertas-firmware/libertas-firmware_9.70.7.p0-1_all.deb
  wget -c --directory-prefix=${DIR}/dl/ http://ftp.us.debian.org/debian/pool/non-free/z/zd1211-firmware/zd1211-firmware_2.21.0.0-1_all.deb
 fi
fi

}

function prepare_uimage {
 sudo rm -rfd ${DIR}/kernel || true
 mkdir -p ${DIR}/kernel
 cd ${DIR}/kernel
 sudo dpkg -x ${DIR}/dl/linux-image-${KERNEL}_1.0${DIST}_armel.deb ${DIR}/kernel
}

function prepare_initrd {
 sudo rm -rfd ${DIR}/initrd-tree || true
 mkdir -p ${DIR}/initrd-tree
 cd ${DIR}/initrd-tree
 sudo zcat ${DIR}/dl/initrd.gz | sudo cpio -i -d
 sudo dpkg -x ${DIR}/dl/linux-image-${KERNEL}_1.0${DIST}_armel.deb ${DIR}/initrd-tree

if [ "${FIRMWARE}" ] ; then
 if test "-$DIST-" = "-lucid-"
 then
  sudo dpkg -x ${DIR}/dl/linux-firmware-nonfree_1.8_all.deb ${DIR}/initrd-tree
 else
 #from: http://packages.debian.org/source/squeeze/firmware-nonfree
  sudo dpkg -x ${DIR}/dl/atmel-firmware_1.3-4_all.deb ${DIR}/initrd-tree
  sudo dpkg -x ${DIR}/dl/firmware-ralink_0.23_all.deb ${DIR}/initrd-tree
  sudo dpkg -x ${DIR}/dl/libertas-firmware_9.70.7.p0-1_all.deb ${DIR}/initrd-tree
  sudo dpkg -x ${DIR}/dl/zd1211-firmware_2.21.0.0-1_all.deb ${DIR}/initrd-tree
 fi
fi

 #Cleanup some of the extra space..
 sudo rm -f ${DIR}/initrd-tree/boot/*-${KERNEL}
 sudo rm -rfd ${DIR}/initrd-tree/lib/modules/${KERNEL}/kernel/drivers/media/
 sudo rm -rfd ${DIR}/initrd-tree/lib/modules/${KERNEL}/kernel/drivers/usb/serial/
 sudo rm -rfd ${DIR}/initrd-tree/lib/modules/${KERNEL}/kernel/drivers/usb/misc/

 sudo rm -rfd ${DIR}/initrd-tree/lib/modules/${KERNEL}/kernel/drivers/net/irda/
 sudo rm -rfd ${DIR}/initrd-tree/lib/modules/${KERNEL}/kernel/drivers/net/hamradio/
 sudo rm -rfd ${DIR}/initrd-tree/lib/modules/${KERNEL}/kernel/drivers/net/can/

 sudo rm -rfd ${DIR}/initrd-tree/lib/modules/${KERNEL}/kernel/drivers/misc

 sudo rm -rfd ${DIR}/initrd-tree/lib/modules/${KERNEL}/kernel/net/irda/
 sudo rm -rfd ${DIR}/initrd-tree/lib/modules/${KERNEL}/kernel/net/decnet/

 sudo rm -rfd ${DIR}/initrd-tree/lib/modules/${KERNEL}/kernel/fs/
 sudo rm -rfd ${DIR}/initrd-tree/lib/modules/${KERNEL}/kernel/sound/
 sudo rm -rfd ${DIR}/initrd-tree/lib/modules/*-versatile/
 sudo rm -rfd ${DIR}/initrd-tree/lib/firmware/*-versatile/

 if test "-$DIST-" = "-lucid-"
 then
   sudo cp -v ${DIR}/scripts/flash-kernel.conf ${DIR}/initrd-tree/etc/flash-kernel.conf
   sudo patch -p1 -s < ${DIR}/scripts/beagle-copy-flash-kernel-override.diff
   sudo patch -p1 -s < ${DIR}/scripts/beagle-erase-nand-and-copy-new-scr.diff
   sudo patch -p1 -s < ${DIR}/scripts/lucid-copy-etc-e2fsck.conf.diff
   sudo patch -p1 -s < ${DIR}/scripts/lucid-copy-modules.diff
   sudo dpkg -x ${DIR}/dl/mtd-utils_20090606-1_armel.deb ${DIR}/initrd-tree
 fi

 sudo touch ${DIR}/initrd-tree/etc/rcn.conf
 sudo cp -v ${DIR}/scripts/e2fsck.conf ${DIR}/initrd-tree/etc/e2fsck.conf

 find . | cpio -o -H newc | gzip -9 > ${DIR}/initrd.mod.gz
 cd ${DIR}/
 sudo rm -f ${DIR}/initrd.mod || true
 sudo gzip -d ${DIR}/initrd.mod.gz
}

function cleanup_sd {

 echo ""
 echo "Umounting Partitions"
 echo ""

 sudo umount ${MMC}1 &> /dev/null || true
 sudo umount ${MMC}2 &> /dev/null || true

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

sudo mkfs.vfat -F 16 ${MMC}1 -n ${BOOT_LABEL}

sudo rm -rfd ${DIR}/disk || true

mkdir ${DIR}/disk
sudo mount ${MMC}1 ${DIR}/disk

sudo cp -v ${DIR}/dl/${MLO} ${DIR}/disk/MLO
sudo cp -v ${DIR}/dl/${XLOAD} ${DIR}/disk/x-load.bin.ift
sudo cp -v ${DIR}/dl/${UBOOT} ${DIR}/disk/u-boot.bin

sudo mkimage -A arm -O linux -T ramdisk -C none -a 0 -e 0 -n initramfs -d ${DIR}/initrd.mod ${DIR}/disk/uInitrd
sudo mkimage -A arm -O linux -T ramdisk -C none -a 0 -e 0 -n initramfs -d ${DIR}/dl/initrd.img-${KERNEL} ${DIR}/disk/uInitrd.final
sudo mkimage -A arm -O linux -T kernel -C none -a 0x80008000 -e 0x80008000 -n ${KERNEL} -d ${DIR}/kernel/boot/vmlinuz-* ${DIR}/disk/uImage

if [ "${SERIAL_MODE}" ] ; then
 sudo mkimage -A arm -O linux -T script -C none -a 0 -e 0 -n "Debian Installer" -d ${DIR}/scripts/serial.cmd ${DIR}/disk/boot.scr
 sudo mkimage -A arm -O linux -T script -C none -a 0 -e 0 -n "Boot" -d ${DIR}/scripts/serial-normal.cmd ${DIR}/disk/normal.scr
 sudo cp -v ${DIR}/scripts/serial-normal.cmd ${DIR}/disk/boot.cmd
else
 sudo mkimage -A arm -O linux -T script -C none -a 0 -e 0 -n "Debian Installer" -d ${DIR}/scripts/dvi.cmd ${DIR}/disk/boot.scr
 sudo mkimage -A arm -O linux -T script -C none -a 0 -e 0 -n "Boot" -d ${DIR}/scripts/dvi-normal.cmd ${DIR}/disk/normal.scr
 sudo cp -v ${DIR}/scripts/dvi-normal.cmd ${DIR}/disk/boot.cmd
fi

echo "#!/bin/sh" > /tmp/rebuild_uinitrd.sh
echo "" >> /tmp/rebuild_uinitrd.sh
echo "DIR=\$PWD" >> /tmp/rebuild_uinitrd.sh
echo "sudo mkimage -A arm -O linux -T ramdisk -C none -a 0 -e 0 -n initramfs -d /boot/initrd.img-\$(uname -r) \${DIR}/uInitrd" >> /tmp/rebuild_uinitrd.sh
echo "" >> /tmp/rebuild_uinitrd.sh

sudo cp -v /tmp/rebuild_uinitrd.sh ${DIR}/disk/rebuild_uinitrd.sh
sudo chmod +x ${DIR}/disk/rebuild_uinitrd.sh

cd ${DIR}/disk
sync
cd ${DIR}
sudo umount ${DIR}/disk || true
echo "done"

}

function check_mmc {
 FDISK=$(sudo fdisk -l | grep "Disk ${MMC}" | awk '{print $2}')

 if test "-$FDISK-" = "-$MMC:-"
 then
  echo ""
  echo "I see..."
  echo "sudo fdisk -l:"
  sudo fdisk -l | grep "Disk /dev/" --color=never
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
  sudo fdisk -l | grep "Disk /dev/" --color=never
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
 DIST=squeeze
 unset IN_VALID_DISTRO
 fi

 if test "-$DISTRO_TYPE-" = "-lucid-"
 then
 DIST=lucid
 unset IN_VALID_DISTRO
 fi

 if test "-$DISTRO_TYPE-" = "-sid-"
 then
 DIST=sid
 unset IN_VALID_DISTRO
 fi

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
      sid
    Ubuntu
      lucid

--firmware
    Add's debian non-free firmware, (increase's file size)

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



