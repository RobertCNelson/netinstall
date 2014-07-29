#!/bin/bash

conf_smart_uboot="smart_DISABLED"

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

if [ ! "x${conf_smart_uboot}" = "xenable" ] ; then
	if [ -f "/boot/uboot/backup/boot.scr" ] ; then
		mv /boot/uboot/backup/boot.scr /boot/uboot/boot.scr
	else
		echo "WARN: [/boot/uboot/backup/boot.scr] was missing..." >> /var/log/netinstall.log
	fi
fi

if [ ! "x${conf_smart_uboot}" = "xenable" ] ; then
	if [ -f "/boot/uboot/backup/normal.txt" ] ; then
		sed -i -e 's:FINAL_PART:'$FINAL_PART':g' /boot/uboot/backup/normal.txt
		sed -i -e 's:FINAL_FSTYPE:'$FINAL_FSTYPE':g' /boot/uboot/backup/normal.txt
		mv /boot/uboot/backup/normal.txt /boot/uboot/uEnv.txt
	else
		echo "WARN: [/boot/uboot/backup/normal.txt] was missing..." >> /var/log/netinstall.log
	fi
fi

if [ "x${serial_tty}" != "x" ] ; then
	cat > /etc/init/${serial_tty}.conf <<-__EOF__
		start on stopped rc RUNLEVEL=[2345]
		stop on runlevel [!2345]

		respawn
		exec /sbin/getty 115200 ${serial_tty}

	__EOF__
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

cat > /etc/init/generic-boot-script.conf <<-__EOF__
start on runlevel 2

script

if [ -f /boot/SOC.sh ] ; then
        board=\$(grep board /boot/SOC.sh | awk -F"=" '{print \$2}')
        if [ -f "/opt/scripts/boot/\${board}.sh" ] ; then
                /bin/sh /opt/scripts/boot/\${board}.sh >/dev/null 2>&1 &
        fi
fi
end script

__EOF__

if [ ! "x${conf_smart_uboot}" = "xenable" ] ; then
	if [ -f /boot/vmlinuz-`uname -r` ] ; then
		cp /boot/vmlinuz-`uname -r` /boot/uboot/zImage
	else
		echo "ERROR: [/boot/vmlinuz-`uname -r`] missing" >> /var/log/netinstall.log
	fi

	if [ -f /boot/initrd.img-`uname -r` ] ; then
		cp /boot/initrd.img-`uname -r` /boot/uboot/initrd.img
	else
		echo "ERROR: [/boot/initrd.img-`uname -r`] missing" >> /var/log/netinstall.log
	fi
fi

	#Cleanup:
	mv /boot/uboot/bootdrive /boot/uboot/backup/ || true
	mv /boot/uboot/mounts /boot/uboot/backup/ || true

if [ ! "x${conf_smart_uboot}" = "xenable" ] ; then
	mkimage -A arm -O linux -T ramdisk -C none -a 0 -e 0 -n initramfs -d /boot/initrd.img-`uname -r` /boot/uboot/uInitrd
	if [ "${zreladdr}" ] ; then
		mkimage -A arm -O linux -T kernel -C none -a ${zreladdr} -e ${zreladdr} -n `uname -r` -d /boot/vmlinuz-`uname -r` /boot/uboot/uImage
	fi
fi

wfile="/boot/uEnv.txt"

if [ "x${conf_smart_uboot}" = "xenable" ] ; then
	rootdrive=$(echo ${FINAL_PART} | awk -F"p" '{print $1}' || true)
	if [ "x${bootdrive}" = "x${rootdrive}" ] ; then
		rm -f /boot/uboot/boot/uEnv.txt || true
		echo "uname_r=$(uname -r)" > ${wfile}
	else
		wfile="/boot/uboot/boot/uEnv.txt"
		echo "uname_r=current" > ${wfile}
		cp /boot/vmlinuz-`uname -r` /boot/uboot/boot/vmlinuz-current
		cp /boot/initrd.img-`uname -r` /boot/uboot/boot/initrd.img-current
	fi
else
	wfile="/boot/uboot/boot/uEnv.txt"
	echo "uname_r=current" > ${wfile}
	if [ "x${uboot_CONFIG_CMD_BOOTZ}" = "xenable" ] ; then
		cp /boot/vmlinuz-`uname -r` /boot/uboot/boot/vmlinuz-current
	else
		mkimage -A arm -O linux -T kernel -C none -a ${zreladdr} -e ${zreladdr} -n `uname -r` -d /boot/vmlinuz-`uname -r` /boot/uboot/boot/uImage
		echo "zreladdr=${zreladdr}" >> ${wfile}
	fi
	if [ "x${uboot_CONFIG_SUPPORT_RAW_INITRD}" = "xenable" ] ; then
		cp /boot/initrd.img-`uname -r` /boot/uboot/boot/initrd.img-current
	else
		mkimage -A arm -O linux -T ramdisk -C none -a 0 -e 0 -n initramfs -d /boot/initrd.img-`uname -r` /boot/uboot/boot/uInitrd
	fi
fi

echo "uuid=$(/sbin/blkid -c /dev/null -s UUID -o value ${FINAL_PART})" >> ${wfile}
if [ ! "x${dtb}" = "x" ] ; then
	echo "dtb=${dtb}" >>  ${wfile}
fi
if [ ! "x${optargs}" = "x" ] ; then
	echo "optargs=${optargs}" >>  ${wfile}
	if [ ! "x${video}" = "x" ] ; then
		echo "cmdline=video=${video}" >>  ${wfile}
	fi
fi

#
