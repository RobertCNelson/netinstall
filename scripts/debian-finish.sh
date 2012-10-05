#!/bin/bash

ls -lh /boot/uboot/* >/boot/uboot/backup/file_list.log

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
mount > /boot/uboot/backup/mount.log

#Cleanup: NetInstall Files
rm -f /boot/uboot/uInitrd.net || true
rm -f /boot/uboot/uImage.net || true
rm -f /boot/uboot/zImage.net || true
rm -f /boot/uboot/initrd.net || true

#Cleanup: Initial Bootloader
rm -f /boot/uboot/boot.scr || true
rm -f /boot/uboot/uEnv.txt || true

if [ -f "/boot/uboot/backup/boot.scr" ] ; then
	mv /boot/uboot/backup/boot.scr /boot/uboot/boot.scr
fi

if [ -f "/boot/uboot/backup/normal.txt" ] ; then
	sed -i -e 's:FINAL_PART:'$FINAL_PART':g' /boot/uboot/backup/normal.txt
	sed -i -e 's:FINAL_FSTYPE:'$FINAL_FSTYPE':g' /boot/uboot/backup/normal.txt
	mv /boot/uboot/backup/normal.txt /boot/uboot/uEnv.txt
fi

#Install Correct Kernel Image:
dpkg -x /boot/uboot/linux-image-*_1.0*_arm*.deb /
update-initramfs -c -k `uname -r`
cp /boot/vmlinuz-`uname -r` /boot/uboot/zImage
cp /boot/initrd.img-`uname -r` /boot/uboot/initrd.img
rm -f /boot/uboot/linux-image-*_1.0*_arm*.deb || true

#Device Tweaks:
source /boot/uboot/SOC.sh
if [ "x${boot_image}" == "xbootm" ] ; then
	mkimage -A arm -O linux -T ramdisk -C none -a 0 -e 0 -n initramfs -d /boot/initrd.img-`uname -r` /boot/uboot/uInitrd
	mkimage -A arm -O linux -T kernel -C none -a ${load_addr} -e ${load_addr} -n `uname -r` -d /boot/vmlinuz-`uname -r` /boot/uboot/uImage
fi

if [ "x${serial_tty}" != "x" ] ; then
	cat /etc/inittab | grep -v '#' | grep ${serial_tty} || echo "T2:23:respawn:/sbin/getty -L ${serial_tty} 115200 vt102" >> /etc/inittab && echo "#" >> /etc/inittab
fi

if [ "x${boot_fstype}" == "xext2" ] ; then
	echo "/dev/mmcblk0p1    /boot/uboot    ext2    defaults    0    2" >> /etc/fstab
else
	echo "/dev/mmcblk0p1    /boot/uboot    auto    defaults    0    0" >> /etc/fstab
fi

if [ "x${smsc95xx_mem}" != "x" ] ; then
	echo "vm.min_free_kbytes = ${smsc95xx_mem}" >> /etc/sysctl.conf
fi

cat > /etc/e2fsck.conf <<-__EOF__
[options]

broken_system_clock = true

__EOF__

cat > /etc/init.d/board_tweaks.sh <<-__EOF__
	#!/bin/sh -e
	### BEGIN INIT INFO
	# Provides:          board_tweaks.sh
	# Required-Start:    \$local_fs
	# Required-Stop:     \$local_fs
	# Default-Start:     2 3 4 5
	# Default-Stop:      0 1 6
	# Short-Description: Start daemon at boot time
	# Description:       Enable service provided by daemon.
	### END INIT INFO

	case "\$1" in
	start|reload|force-reload|restart)
	        if [ -f /boot/uboot/SOC.sh ] ; then
	                board=\$(cat /boot/uboot/SOC.sh | grep "board" | awk -F"=" '{print \$2}')
	                case "\${board}" in
	                BEAGLEBONE_A)
	                        if [ -f /boot/uboot/tools/target/BeagleBone.sh ] ; then
	                                /bin/sh /boot/uboot/tools/target/BeagleBone.sh &> /dev/null &
	                        fi;;
	                esac
	        fi
	        ;;
	stop)
	        exit 0
	        ;;
	*)
	        echo "Usage: /etc/init.d/board_tweaks.sh {start|stop|reload|restart|force-reload}"
	        exit 1
	        ;;
	esac

	exit 0

__EOF__

chmod u+x /etc/init.d/board_tweaks.sh
insserv board_tweaks.sh || true

