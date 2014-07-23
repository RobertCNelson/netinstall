#!/bin/bash

if [ ! -f /var/log/netinstall.log ] ; then
	touch /var/log/netinstall.log
	echo "NetInstall Log:" >> /var/log/netinstall.log
fi

#Device Configuration:
if [ ! -f /boot/uboot/SOC.sh ] ; then
	cp /etc/hwpack/SOC.sh /boot/uboot/SOC.sh
	echo "ERROR: [boot/uboot/SOC.sh] was missing..." >> /var/log/netinstall.log
fi
. /boot/uboot/SOC.sh

if [ -f /boot/uboot/bootdrive ] ; then
	bootdrive=$(cat /boot/uboot/bootdrive)
else
	bootdrive=/dev/mmcblk0
fi

if [ ! -d /boot/uboot/backup/ ] ; then
	mkdir -p /boot/uboot/backup/
fi
ls -lh /boot/uboot/* >/boot/uboot/backup/file_list.log

echo "fdisk -l..." >> /var/log/netinstall.log
fdisk -l >> /var/log/netinstall.log

#Set boot flag on: /dev/mmcblk0:
if [ -f /sbin/parted ] ; then
	/sbin/parted ${bootdrive} set 1 boot on || true
else
	echo "ERROR: [/sbin/parted ${bootdrive} set 1 boot on] failed" >> /var/log/netinstall.log
fi

#Find Target Partition and FileSystem
if [ -f /boot/uboot/mounts ] ; then
	echo "cat /boot/uboot/mounts..." >> /var/log/netinstall.log
	cat /boot/uboot/mounts >> /var/log/netinstall.log
	FINAL_PART=$(cat /boot/uboot/mounts | grep /dev/ | grep "/target " | awk '{print $1}')
	FINAL_FSTYPE=$(cat /boot/uboot/mounts | grep /dev/ | grep "/target " | awk '{print $3}')
else
	echo "ERROR: [/boot/uboot/mounts] was missing..." >> /var/log/netinstall.log
fi

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
else
	echo "WARN: [/boot/uboot/backup/boot.scr] was missing..." >> /var/log/netinstall.log
fi

if [ -f "/boot/uboot/backup/normal.txt" ] ; then
	sed -i -e 's:FINAL_PART:'$FINAL_PART':g' /boot/uboot/backup/normal.txt
	sed -i -e 's:FINAL_FSTYPE:'$FINAL_FSTYPE':g' /boot/uboot/backup/normal.txt
	mv /boot/uboot/backup/normal.txt /boot/uboot/uEnv.txt
else
	echo "WARN: [/boot/uboot/backup/normal.txt] was missing..." >> /var/log/netinstall.log
fi

if [ "x${serial_tty}" != "x" ] ; then
	cp /etc/inittab /boot/uboot/backup/inittab
	serial_num=$(echo -n "${serial_tty}"| tail -c -1)

	#By default: Debian seems to be automatically modifying the first #T0 line:
	#T0:23:respawn:/sbin/getty -L ttyS0 9600 vt100

	#Convert #T0: -> T${serial_num}:
	sed -i -e "s/#T0:23:respawn/T${serial_num}:23:respawn/g" /etc/inittab

	#Convert ttyS0 9600 vt100 -> ${serial_tty} 115200 vt102
	sed -i -e "s/ttyS0 9600 vt100/${serial_tty} 115200 vt102/g" /etc/inittab
else
	echo "WARN: [serial_tty] was undefined..." >> /var/log/netinstall.log
fi

if [ "x${boot_fstype}" = "xfat" ] ; then
	echo "${bootdrive}p1  /boot/uboot  auto  defaults  0  0" >> /etc/fstab
else
	echo "${bootdrive}p1  /boot/uboot  ${boot_fstype}  defaults  0  2" >> /etc/fstab
fi

if [ "x${usbnet_mem}" != "x" ] ; then
	echo "vm.min_free_kbytes = ${usbnet_mem}" >> /etc/sysctl.conf
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
	        if [ -f /boot/uboot/SOC.sh ] && [ -f /boot/uboot/run_boot-scripts ] ; then
	                if [ -f "/opt/boot-scripts/set_date.sh" ] ; then
	                        /bin/sh /opt/boot-scripts/set_date.sh >/dev/null 2>&1 &
	                fi
	                board=\$(cat /boot/uboot/SOC.sh | grep "board" | awk -F"=" '{print \$2}')
	                if [ -f "/opt/boot-scripts/\${board}.sh" ] ; then
	                        /bin/sh /opt/boot-scripts/\${board}.sh >/dev/null 2>&1 &
	                fi
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

#Install Correct Kernel Image: (this will fail if the boot partition was re-formated)
if [ -f /boot/uboot/linux-image-*arm*.deb ] ; then
	dpkg -x /boot/uboot/linux-image-*arm*.deb /
	update-initramfs -c -k `uname -r`
	cp /boot/vmlinuz-`uname -r` /boot/uboot/zImage
	cp /boot/initrd.img-`uname -r` /boot/uboot/initrd.img
	rm -f /boot/uboot/linux-image-*arm*.deb || true
	if [ -f /boot/uboot/vmlinuz- ] ; then
		rm -f /boot/uboot/vmlinuz- || true
	fi

	#Cleanup:
	mv /boot/uboot/bootdrive /boot/uboot/backup/ || true
	mv /boot/uboot/mounts /boot/uboot/backup/ || true

	#FIXME: Also reinstall these:
	rm -f /boot/uboot/*dtbs.tar.gz || true
	rm -f /boot/uboot/*modules.tar.gz || true

	touch /boot/uboot/run_boot-scripts || true

	mkimage -A arm -O linux -T ramdisk -C none -a 0 -e 0 -n initramfs -d /boot/initrd.img-`uname -r` /boot/uboot/uInitrd
	if [ "${zreladdr}" ] ; then
		mkimage -A arm -O linux -T kernel -C none -a ${zreladdr} -e ${zreladdr} -n `uname -r` -d /boot/vmlinuz-`uname -r` /boot/uboot/uImage
	fi
else
	echo "ERROR: [/boot/uboot/linux-image-*.deb] missing" >> /var/log/netinstall.log
fi
