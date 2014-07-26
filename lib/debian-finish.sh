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

cat > /etc/init.d/generic-boot-script.sh <<-__EOF__
#!/bin/sh -e
### BEGIN INIT INFO
# Provides:          generic-boot-script.sh
# Required-Start:    \$local_fs
# Required-Stop:     \$local_fs
# Default-Start:     2 3 4 5
# Default-Stop:      0 1 6
# Short-Description: Start daemon at boot time
# Description:       Enable service provided by daemon.
### END INIT INFO

case "\$1" in
start|reload|force-reload|restart)
        if [ -f /boot/SOC.sh ] ; then
                board=\$(grep board /boot/SOC.sh | awk -F"=" '{print \$2}')
                if [ -f "/opt/scripts/boot/\${board}.sh" ] ; then
                        /bin/sh /opt/scripts/boot/\${board}.sh >/dev/null 2>&1 &
                fi
        fi
        ;;
stop)
        exit 0
        ;;
*)
        echo "Usage: /etc/init.d/generic-boot-script.sh {start|stop|reload|restart|force-reload}"
        exit 1
        ;;
esac

exit 0

__EOF__

chmod u+x /etc/init.d/generic-boot-script.sh
insserv generic-boot-script.sh || true

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
	else
		wfile="/boot/uboot/boot/uEnv.txt"

		cp /boot/vmlinuz-`uname -r` /boot/uboot/boot/vmlinuz-current
		cp /boot/initrd.img-`uname -r` /boot/uboot/boot/initrd.img-current
	fi
fi

echo "uname_r=$(uname -r)" > ${wfile}
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
