#!/bin/bash -e
#
# Copyright (c) 2009-2020 Robert Nelson <robertcnelson@gmail.com>
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
#
# Latest can be found at:
# http://github.com/RobertCNelson/netinstall/blob/master/mk_mmc.sh

#REQUIREMENTS:
#uEnv.txt bootscript support

MIRROR="https://rcn-ee.com/repos"

BOOT_LABEL="BOOT"
PARTITION_PREFIX=""

unset USE_BETA_BOOTLOADER
unset USE_LOCAL_BOOT
unset LOCAL_BOOTLOADER
unset ADDON

unset FIRMWARE
unset KERNEL_DEB

GIT_VERSION=$(git rev-parse --short HEAD)

DIST=buster
ARCH=armhf
DISTARCH="${DIST}-${ARCH}"
deb_distribution="debian"

DIR="$PWD"
TEMPDIR=$(mktemp -d)

is_element_of () {
	testelt=$1
	for validelt in $2 ; do
		[ "$testelt" = "$validelt" ] && return 0
	done
	return 1
}

check_root () {
	if ! [ "$(id -u)" = 0 ] ; then
		echo "$0 must be run as sudo user or root"
		exit 1
	fi
}

check_for_command () {
	if ! which "$1" > /dev/null ; then
		echo -n "You're missing command $1"
		NEEDS_COMMAND=1
		if [ -n "$2" ] ; then
			echo -n " (consider installing package $2)"
		fi
		echo
	fi
}

detect_software () {
	unset NEEDS_COMMAND

	check_for_command mkfs.vfat dosfstools
	check_for_command wget wget
	check_for_command dpkg dpkg
	check_for_command partprobe parted
	check_for_command patch patch
	check_for_command mkimage u-boot-tools

	if [ "${NEEDS_COMMAND}" ] ; then
		echo ""
		echo "Your system is missing some dependencies"
		echo "Ubuntu/Debian: sudo apt-get install wget dosfstools u-boot-tools parted"
		echo "Fedora: as root: yum install wget dosfstools dpkg patch uboot-tools parted"
		echo "Gentoo: emerge wget dosfstools dpkg u-boot-tools parted"
		echo ""
		exit
	fi

	unset test_sfdisk
	test_sfdisk=$(LC_ALL=C sfdisk -v 2>/dev/null | grep 2.17.2 | awk '{print $1}')
	if [ "x${test_sdfdisk}" = "xsfdisk" ] ; then
		echo ""
		echo "Detected known broken sfdisk:"
		echo "See: https://github.com/RobertCNelson/netinstall/issues/20"
		echo ""
		exit
	fi

	unset wget_version
	wget_version=$(LC_ALL=C wget --version | grep "GNU Wget" | awk '{print $3}' | awk -F '.' '{print $2}' || true)
	case "${wget_version}" in
	12|13)
		#wget before 1.14 in debian does not support sni
		echo "wget: [$(LC_ALL=C wget --version | grep \"GNU Wget\" | awk '{print $3}' || true)]"
		echo "wget: [this version of wget does not support sni, using --no-check-certificate]"
		echo "wget: [http://en.wikipedia.org/wiki/Server_Name_Indication]"
		dl="wget --no-check-certificate"
		;;
	*)
		dl="wget"
		;;
	esac

	dl_continue="${dl} -c"
	dl_quiet="${dl} --no-verbose"
}

local_bootloader () {
	echo ""
	echo "Using Locally Stored Device Bootloader"
	echo "-----------------------------"
	mkdir -p "${TEMPDIR}/dl/"

	if [ "${spl_name}" ] ; then
		cp "${LOCAL_SPL}" "${TEMPDIR}/dl/"
		SPL=${LOCAL_SPL##*/}
		echo "SPL Bootloader: ${SPL}"
	fi

	if [ "${boot_name}" ] ; then
		cp "${LOCAL_BOOTLOADER}" "${TEMPDIR}/dl/"
		UBOOT=${LOCAL_BOOTLOADER##*/}
		echo "UBOOT Bootloader: ${UBOOT}"
	fi
}

dl_bootloader () {
	echo ""
	echo "Downloading Device's Bootloader"
	echo "-----------------------------"
	minimal_boot="1"

	mkdir -p "${TEMPDIR}/dl/${DISTARCH}"
	mkdir -p "${DIR}/dl/${DISTARCH}"

	${dl_quiet} --directory-prefix="${TEMPDIR}/dl/" "${conf_bl_http}/${conf_bl_listfile}"

	if [ ! -f "${TEMPDIR}/dl/${conf_bl_listfile}" ] ; then
		echo "error: can't connect to rcn-ee.net, retry in a few minutes..."
		exit
	fi

	boot_version=$(cat "${TEMPDIR}/dl/${conf_bl_listfile}" | grep "VERSION:" | awk -F":" '{print $2}')
	if [ "x${boot_version}" != "x${minimal_boot}" ] ; then
		echo "Error: This script is out of date and unsupported..."
		echo "Please Visit: https://github.com/RobertCNelson to find updates..."
		exit
	fi

	if [ "${USE_BETA_BOOTLOADER}" ] ; then
		ABI="ABX2"
	else
		ABI="ABI2"
	fi

	if [ "${spl_name}" ] ; then
		SPL=$(cat "${TEMPDIR}/dl/${conf_bl_listfile}" | grep "${ABI}:${conf_board}:SPL" | awk '{print $2}')
		${dl_quiet} --directory-prefix="${TEMPDIR}/dl/" "${SPL}"
		SPL=${SPL##*/}
		echo "SPL Bootloader: ${SPL}"
	else
		unset SPL
	fi

	if [ "${boot_name}" ] ; then
		UBOOT=$(cat "${TEMPDIR}/dl/${conf_bl_listfile}" | grep "${ABI}:${conf_board}:BOOT" | awk '{print $2}')
		${dl} --directory-prefix="${TEMPDIR}/dl/" "${UBOOT}"
		UBOOT=${UBOOT##*/}
		echo "UBOOT Bootloader: ${UBOOT}"
	else
		unset UBOOT
	fi
}

dl_kernel_image () {
	echo ""
	echo "Downloading Device's Kernel Image"
	echo "-----------------------------"

	if [ "x${cmd_kernel_override}" = "xenable" ] ; then
		unset kernel_selected
		if [ "x${cmd_LTS41_KERNEL}" = "xenable" ] ; then
			kernel_repo="LTS41"
			kernel_selected="true"
		fi
		if [ "x${cmd_LTS44_KERNEL}" = "xenable" ] ; then
			kernel_repo="LTS44"
			kernel_selected="true"
		fi
		if [ "x${cmd_LTS49_KERNEL}" = "xenable" ] ; then
			kernel_repo="LTS49"
			kernel_selected="true"
		fi
		if [ "x${cmd_LTS414_KERNEL}" = "xenable" ] ; then
			kernel_repo="LTS414"
			kernel_selected="true"
		fi
		if [ "x${cmd_LTS419_KERNEL}" = "xenable" ] ; then
			kernel_repo="LTS419"
			kernel_selected="true"
		fi
		if [ "x${cmd_LTS54_KERNEL}" = "xenable" ] ; then
			kernel_repo="LTS54"
			kernel_selected="true"
		fi
		if [ "x${cmd_STABLE_KERNEL}" = "xenable" ] && [ "x${kernel_selected}" = "x" ] ; then
			kernel_repo="STABLE"
			kernel_selected="true"
		fi
		if [ "x${cmd_TESTING_KERNEL}" = "xenable" ] && [ "x${kernel_selected}" = "x" ] ; then
			kernel_repo="TESTING"
			kernel_selected="true"
		fi
		if [ "x${cmd_EXPERIMENTAL_KERNEL}" = "xenable" ] && [ "x${kernel_selected}" = "x" ] ; then
			kernel_repo="EXPERIMENTAL"
			kernel_selected="true"
		fi
	fi

	if [ ! "${KERNEL_DEB}" ] ; then
		${dl_quiet} --directory-prefix="${TEMPDIR}/dl/" "${MIRROR}/latest/${DISTARCH}/LATEST-${kernel_subarch}"
		echo "-----------------------------"
		echo "Kernel Options:"
		cat "${TEMPDIR}/dl/LATEST-${kernel_subarch}"
		echo "-----------------------------"
		#echo "LTS41: --use-lts-4_1-kernel"
		echo "LTS44: --use-lts-4_4-kernel"
		echo "LTS49: --use-lts-4_9-kernel"
		echo "LTS414: --use-lts-4_14-kernel"
		echo "LTS419: --use-lts-4_19-kernel"
		echo "STABLE: --use-stable-kernel"
		echo "TESTING: --use-testing-kernel"
		echo "EXPERIMENTAL: --use-experimental-kernel"

		echo "-----------------------------"

		FTP_DIR=$(cat "${TEMPDIR}/dl/LATEST-${kernel_subarch}" | grep "ABI:1 ${kernel_repo}" | awk '{print $3}')
		uname_r="${FTP_DIR}"

		ACTUAL_DEB_FILE=linux-image-${uname_r}_1${DIST}_${ARCH}.deb

		${dl_continue} --directory-prefix="${DIR}/dl/${DISTARCH}" "${MIRROR}/${deb_distribution}/pool/main/l/linux-upstream/${ACTUAL_DEB_FILE}"

	else

		KERNEL=${external_deb_file}
		#Remove all "\" from file name.
		ACTUAL_DEB_FILE=$(echo "${external_deb_file}" | sed 's!.*/!!' | grep linux-image)
		if [ -f "${DIR}/dl/${DISTARCH}/${ACTUAL_DEB_FILE}" ] ; then
			rm -rf "${DIR}/dl/${DISTARCH}/${ACTUAL_DEB_FILE}" || true
		fi
		cp -v "${external_deb_file}" "${DIR}/dl/${DISTARCH}/"

	fi
	echo "Using Kernel: ${ACTUAL_DEB_FILE}"
}

actually_dl_netinstall () {
	${dl} --directory-prefix="${DIR}/dl/${DISTARCH}" "http://ftp.debian.org/debian/dists/${DIST}/main/installer-${ARCH}/current/images/netboot/initrd.gz"
	MD5SUM=$(md5sum "${DIR}/dl/${DISTARCH}/initrd.gz" | awk '{print $1}')
}

dl_netinstall_image () {
	echo ""
	echo "Downloading NetInstall Image"
	echo "-----------------------------"

	if [ -f "${DIR}/dl/${DISTARCH}/initrd.gz" ] ; then
		rm -f "${DIR}/dl/${DISTARCH}/initrd.gz" || true
	fi
	actually_dl_netinstall

	echo "md5sum of NetInstall: ${MD5SUM}"
}

boot_uenv_txt_template () {
	#Start with a blank state:
	echo "#Normal Boot" > "${TEMPDIR}/bootscripts/normal.cmd"
	echo "#Debian Installer only Boot" > "${TEMPDIR}/bootscripts/netinstall.cmd"

	drm_device_identifier=${drm_device_identifier:-"HDMI-A-1"}
	uboot_fdt_variable_name=${uboot_fdt_variable_name:-"fdtfile"}

	conf_bootcmd=${conf_bootcmd:-"bootz"}
	kernel=${kernel:-"/boot/vmlinuz-current"}
	initrd=${initrd:-"/boot/initrd.img-current"}

	if [ "x${di_serial_mode}" = "xenable" ] ; then
		xyz_message="echo; echo Installer for [${DISTARCH}] is using the Serial Interface; echo;"
	else
		xyz_message="echo; echo Installer for [${DISTARCH}] is using the Video Interface; echo Use [--serial-mode] to force Installing over the Serial Interface; echo;"
	fi

	cat >> "${TEMPDIR}/bootscripts/normal.cmd" <<-__EOF__
		#fdtfile=${dtb}

		##Video: [ls /sys/class/drm/]
		##Docs: https://git.kernel.org/cgit/linux/kernel/git/torvalds/linux.git/tree/Documentation/fb/modedb.txt
		##Uncomment to override:
		#kms_force_mode=video=${drm_device_identifier}:1024x768@60e

		console=SERIAL_CONSOLE

		mmcroot=FINAL_PART ro
		mmcrootfstype=FINAL_FSTYPE rootwait fixrtc

		loadximage=${conf_fileload} mmc \${bootpart} ${conf_loadaddr} ${kernel}
		loadxfdt=${conf_fileload} mmc \${bootpart} ${conf_fdtaddr} /boot/dtbs/current/\${fdtfile}
		loadxrd=${conf_fileload} mmc \${bootpart} ${conf_initrdaddr} ${initrd}; setenv initrd_size \${filesize}

		loadall=run loadximage; run loadxfdt; run loadxrd;

		optargs=VIDEO_CONSOLE

		mmcargs=setenv bootargs console=\${console} \${optargs} \${kms_force_mode} root=\${mmcroot} rootfstype=\${mmcrootfstype}
		uenvcmd=run loadall; run mmcargs; ${conf_bootcmd} ${conf_loadaddr} ${conf_initrdaddr}:\${initrd_size} ${conf_fdtaddr}

	__EOF__

	cat >> "${TEMPDIR}/bootscripts/netinstall.cmd" <<-__EOF__
		#fdtfile=${dtb}

		##Video: [ls /sys/class/drm/]
		##Docs: https://git.kernel.org/cgit/linux/kernel/git/torvalds/linux.git/tree/Documentation/fb/modedb.txt
		##Uncomment to override:
		#kms_force_mode=video=${drm_device_identifier}:1024x768@60e

		console=DICONSOLE

		mmcroot=/dev/ram0 rw

		loadximage=${conf_fileload} mmc \${bootpart} ${conf_loadaddr} ${kernel}
		loadxfdt=${conf_fileload} mmc \${bootpart} ${conf_fdtaddr} /boot/dtbs/current/\${fdtfile}
		loadxrd=${conf_fileload} mmc \${bootpart} ${conf_initrdaddr} ${initrd}; setenv initrd_size \${filesize}

		loadall=run loadximage; run loadxfdt; run loadxrd;

		xyz_message=${xyz_message}

		optargs=${conf_optargs}
		mmcargs=setenv bootargs console=\${console} \${optargs} \${kms_force_mode} root=\${mmcroot}
		uenvcmd=run xyz_message; run loadall; run mmcargs; ${conf_bootcmd} ${conf_loadaddr} ${conf_initrdaddr}:\${initrd_size} ${conf_fdtaddr}

	__EOF__

	if [ ! "${uboot_fdt_auto_detection}" ] ; then
		sed -i -e 's:#fdtfile:fdtfile:g' "${TEMPDIR}"/bootscripts/*.cmd
	fi

	if [ "${uboot_fdt_variable_name}" ] ; then
		sed -i -e 's:fdtfile:'$uboot_fdt_variable_name':g' "${TEMPDIR}"/bootscripts/*.cmd
	fi

	if [ "x${drm_read_edid_broken}" = "xenable" ] ; then
		sed -i -e 's:#kms_force_mode:kms_force_mode:g' "${TEMPDIR}"/bootscripts/*.cmd
	fi

	if [ "x${di_serial_mode}" = "xenable" ] ; then
		sed -i -e 's:optargs=VIDEO_CONSOLE::g' "${TEMPDIR}/bootscripts/normal.cmd"
	fi
}

tweak_boot_scripts () {
	unset KMS_OVERRIDE

	ALL="*.cmd"
	NET="netinstall.cmd"
	FINAL="normal.cmd"
	#Set the Serial Console
	sed -i -e 's:SERIAL_CONSOLE:'$SERIAL_CONSOLE':g' "${TEMPDIR}"/bootscripts/${ALL}

	if [ "x${di_kms_mode}" = "xenable" ] && [ ! "x${di_serial_mode}" = "xenable" ] ; then
		#optargs=VIDEO_CONSOLE
		sed -i -e 's:VIDEO_CONSOLE:console=tty0:g' "${TEMPDIR}"/bootscripts/${ALL}

		#Debian Installer console
		sed -i -e 's:DICONSOLE:tty0:g' "${TEMPDIR}/bootscripts/${NET}"
	fi

	if [ "x${di_serial_mode}" = "xenable" ] ; then
		echo "NetInstall: Setting up to use Serial Port: [${SERIAL}]"
		#In pure serial mode, remove all traces of VIDEO
		sed -i -e 's:VIDEO_DISPLAY ::g' "${TEMPDIR}/bootscripts/${NET}"

		#Debian Installer console
		sed -i -e 's:DICONSOLE:'$SERIAL_CONSOLE':g' "${TEMPDIR}/bootscripts/${NET}"

		sed -i -e 's:kms_force_mode=:#kms_force_mode=:g' "${TEMPDIR}/bootscripts/${NET}"

		#Unlike the debian-installer, normal boot will boot fine with the display enabled...
		if [ "x${di_kms_mode}" = "xenable" ] ; then
			#optargs=VIDEO_CONSOLE
			sed -i -e 's:VIDEO_CONSOLE:console=tty0:g' "${TEMPDIR}/bootscripts/${FINAL}"
		fi
	fi
}

setup_bootscripts () {
	mkdir -p "${TEMPDIR}/bootscripts/"
	boot_uenv_txt_template
	tweak_boot_scripts
}

extract_base_initrd () {
	echo "NetInstall: Extracting Base initrd.gz"
	cd "${TEMPDIR}/initrd-tree" || exit
	zcat "${DIR}/dl/${DISTARCH}/initrd.gz" | cpio -i -d
	dpkg -x "${DIR}/dl/${DISTARCH}/${ACTUAL_DEB_FILE}" "${TEMPDIR}/initrd-tree"
	cd "${DIR}/" || exit
}

git_failure () {
	echo "Unable to pull/clone git tree"
	exit
}

dl_linux_firmware () {
	echo ""
	echo "Clone/Pulling linux-firmware.git"
	echo "-----------------------------"
	if [ ! -f "${DIR}/dl/linux-firmware/.git/config" ] ; then
		cd "${DIR}/dl/" || exit
		if [ -d "${DIR}/dl/linux-firmware/" ] ; then
			rm -rf "${DIR}/dl/linux-firmware/" || true
		fi
		git clone git://git.kernel.org/pub/scm/linux/kernel/git/firmware/linux-firmware.git || git_failure
	else
		cd "${DIR}/dl/linux-firmware" || exit
		git pull || git_failure
	fi
	cd "${DIR}/" || exit
}

dl_device_firmware () {
	mkdir -p "${TEMPDIR}/firmware/"
	DL_WGET="${dl_quiet} --directory-prefix=${TEMPDIR}/firmware/"

	if [ "${need_ti_connectivity_firmware}" ] ; then
		dl_linux_firmware
		echo "-----------------------------"
		echo "Adding Firmware for onboard WiFi/Bluetooth module"
		cp -rv "${DIR}/dl/linux-firmware/ti-connectivity" "${TEMPDIR}/firmware/"
		echo "-----------------------------"
	fi

	if [ "x${conf_board}" = "xwandboard" ] ; then
		dl_linux_firmware
		echo "-----------------------------"
		echo "Adding Firmware for onboard WiFi/Bluetooth module"
		echo "-----------------------------"
		mkdir -p "${TEMPDIR}/firmware/brcm/"
		if [ -f "${DIR}/dl/linux-firmware/brcm/brcmfmac4329-sdio.bin" ] ; then
			cp -v "${DIR}/dl/linux-firmware/brcm/brcmfmac4329-sdio.bin" "${TEMPDIR}/firmware/brcm/brcmfmac4329-sdio.bin"
		fi
		if [ -f "${DIR}/dl/linux-firmware/brcm/brcmfmac4330-sdio.bin" ] ; then
			cp -v "${DIR}/dl/linux-firmware/brcm/brcmfmac4330-sdio.bin" "${TEMPDIR}/firmware/brcm/brcmfmac4330-sdio.bin"
		fi
		wget_brcm="${dl_quiet} --directory-prefix=${TEMPDIR}/firmware/brcm/"
		http_brcm="https://rcn-ee.com/repos/git/meta-fsl-arm-extra/recipes-bsp/broadcom-nvram-config/files/wandboard"

		${wget_brcm} "${http_brcm}/brcmfmac4329-sdio.txt"
		${wget_brcm} "${http_brcm}/brcmfmac4330-sdio.txt"
	fi

	if [ "x${conf_board}" = "xudoo" ] ; then
		dl_linux_firmware
		echo "-----------------------------"
		echo "Adding Firmware for onboard WiFi/Bluetooth module"
		echo "-----------------------------"
		mkdir -p "${TEMPDIR}/firmware/"

		if [ -f "${DIR}/dl/linux-firmware/rt2870.bin" ] ; then
			cp -v "${DIR}/dl/linux-firmware/rt2870.bin" "${TEMPDIR}/firmware/rt2870.bin"
			echo "-----------------------------"
		fi
	fi

	case "${dtb}" in
	tegra124-jetson-tk1.dtb)
		dl_linux_firmware
		echo "-----------------------------"
		echo "Adding NVIDIA firmware:"
		cp -rv "${DIR}/dl/linux-firmware/nvidia" "${TEMPDIR}/firmware/"
		mkdir -p "${TEMPDIR}/firmware/rtl_nic/"
		cp -v "${DIR}/dl/linux-firmware/rtl_nic/rtl8168g-2.fw" "${TEMPDIR}/firmware/rtl_nic"
		echo "-----------------------------"
		;;
	esac
}

initrd_add_firmware () {
	DL_WGET="${dl_quiet} --directory-prefix=${TEMPDIR}/firmware/"
	echo ""
	echo "NetInstall: Adding Firmware"
	echo "-----------------------------"

	echo "Adding: Firmware from linux-firmware.git"
	echo "-----------------------------"
	dl_linux_firmware

	#Atheros:
	cp "${DIR}"/dl/linux-firmware/ath3k-1.fw "${TEMPDIR}/initrd-tree/lib/firmware/"
	cp -r "${DIR}/dl/linux-firmware/ar3k/" "${TEMPDIR}/initrd-tree/lib/firmware/"
	cp "${DIR}/dl/linux-firmware/carl9170-1.fw" "${TEMPDIR}/initrd-tree/lib/firmware/"
	cp "${DIR}/dl/linux-firmware/htc_9271.fw" "${TEMPDIR}/initrd-tree/lib/firmware/"

	#Libertas
	cp -r "${DIR}/dl/linux-firmware/libertas/" "${TEMPDIR}/initrd-tree/lib/firmware/"
	#Ralink
	cp -r "${DIR}"/dl/linux-firmware/rt*.bin "${TEMPDIR}/initrd-tree/lib/firmware/"
	#Realtek
	cp -r "${DIR}/dl/linux-firmware/rtlwifi/" "${TEMPDIR}/initrd-tree/lib/firmware/"
	echo "-----------------------------"
}

initrd_cleanup () {
	echo "NetInstall: Removing Optional Stuff to Save RAM Space"
	echo "NetInstall: Original size [$(du -ch ${TEMPDIR}/initrd-tree/ | grep total)]"
	#Cleanup some of the extra space..
	rm -f "${TEMPDIR}"/initrd-tree/boot/*-${KERNEL} || true
	rm -rf "${TEMPDIR}"/initrd-tree/lib/modules/*-versatile/ || true
	rm -rf "${TEMPDIR}"/initrd-tree/lib/modules/*-omap || true
	rm -rf "${TEMPDIR}"/initrd-tree/lib/modules/*-mx5 || true
	rm -rf "${TEMPDIR}"/initrd-tree/lib/modules/*-generic || true
	rm -rf "${TEMPDIR}"/initrd-tree/lib/firmware/*-versatile/ || true
	#jessie:
	rm -rf "${TEMPDIR}"/initrd-tree/lib/modules/*-armmp || true
	echo "${TEMPDIR}"

	echo "NetInstall: Final size [$(du -ch ${TEMPDIR}/initrd-tree/ | grep total)]"

	case "${DIST}" in
	xenial|bionic|stretch|buster)
		echo "uncompressing modules..."
		find "${TEMPDIR}"/initrd-tree/lib/modules/ -type f -name "*.xz" -exec unxz -d {} \;
		echo "NetInstall: Final size [$(du -ch ${TEMPDIR}/initrd-tree/ | grep total)]"
		;;
	esac
}

neuter_flash_kernel () {
	cp -v "${DIR}/lib/flash_kernel/rcn-ee.db" "${TEMPDIR}/initrd-tree/etc/rcn-ee.db"

	cat > "${TEMPDIR}/initrd-tree/usr/lib/post-base-installer.d/06neuter_flash_kernel" <<-__EOF__
		#!/bin/sh -ex
		#BusyBox: http://linux.die.net/man/1/busybox

		apt-install linux-base || true

		#work around: https://anonscm.debian.org/cgit/d-i/flash-kernel.git/commit/functions?id=808a0457400a1b301f2f61a4939e4a6f777a1beb
		apt-install initramfs-tools || true
		mkdir -p /target/lib/modules/\$(uname -r)/
		cp -rf /lib/modules/\$(uname -r)/ /target/lib/modules/\$(uname -r)/

		#ubuntu:
		#Nov 20 23:19:20 in-target: flash-kernel: installing version 4.4.33-armv7-x13
		#Nov 20 23:19:21 in-target: find: ��‘/lib/firmware/4.4.33-armv7-x13/device-tree/��’
		#Nov 20 23:19:21 in-target: : No such file or directory
		#Nov 20 23:19:21 flash-kernel-installer: error: flash-kernel failed
		#Nov 20 23:19:21 main-menu[897]: WARNING **: Configuring 'flash-kernel-installer' failed with error code 1
		#Nov 20 23:19:21 main-menu[897]: WARNING **: Menu item 'flash-kernel-installer' failed.
		mkdir -p /target/lib/firmware/\$(uname -r)/device-tree/
		cp -rf /boot/dtbs/\$(uname -r)/*.dtb /target/lib/firmware/\$(uname -r)/device-tree/

		chroot /target /bin/bash usr/sbin/update-initramfs -ck \$(uname -r)

		if [ -f /target/usr/share/flash-kernel/db/all.db ] ; then
			rm /target/usr/share/flash-kernel/db/all.db || true
		fi

		mkdir -p /target/usr/share/flash-kernel/db/ || true
		cp /etc/rcn-ee.db /target/usr/share/flash-kernel/db/rcn-ee.db

		if [ -f /target/etc/initramfs/post-update.d/flash-kernel ] ; then
			rm /target/etc/initramfs/post-update.d/flash-kernel || true
		fi

		if [ -f /target/etc/kernel/postinst.d/zz-flash-kernel ] ; then
			rm /target/etc/kernel/postinst.d/zz-flash-kernel || true
		fi

		if [ -f /target/etc/kernel/postrm.d/zz-flash-kernel ] ; then
			rm /target/etc/kernel/postrm.d/zz-flash-kernel || true
		fi

		mkdir -p /target/etc/dpkg/dpkg.cfg.d/ || true
		echo "# neuter flash-kernel" > /target/etc/dpkg/dpkg.cfg.d/01_noflash_kernel
		echo "path-exclude=/usr/share/flash-kernel/db/all.db" >> /target/etc/dpkg/dpkg.cfg.d/01_noflash_kernel
		echo "path-exclude=/etc/initramfs/post-update.d/flash-kernel" >> /target/etc/dpkg/dpkg.cfg.d/01_noflash_kernel
		echo "path-exclude=/etc/kernel/postinst.d/zz-flash-kernel" >> /target/etc/dpkg/dpkg.cfg.d/01_noflash_kernel
		echo "path-exclude=/etc/kernel/postrm.d/zz-flash-kernel" >> /target/etc/dpkg/dpkg.cfg.d/01_noflash_kernel
		echo ""  >> /target/etc/dpkg/dpkg.cfg.d/01_noflash_kernel

	__EOF__

	chmod a+x "${TEMPDIR}/initrd-tree/usr/lib/post-base-installer.d/06neuter_flash_kernel"
}

finish_installing_device () {
	cat > "${TEMPDIR}/initrd-tree/usr/lib/finish-install.d/08rcn-ee-finish-installing-device" <<-__EOF__
		#!/bin/sh -e
		cp /usr/bin/finish-install.sh /target/usr/bin/finish-install.sh
		chmod a+x /target/usr/bin/finish-install.sh

		mkdir -p /target/boot/uboot || true

		#Some devices may have mmc cards in both slots...
		unset got_boot_drive

		if [ ! \${got_boot_drive} ] ; then
			if [ -b /dev/mmcblk0p1 ] ; then
				mount /dev/mmcblk0p1 /target/boot/uboot
				if [ -f /target/boot/uboot/SOC.sh ] ; then
					got_boot_drive=1
					echo "/dev/mmcblk0" > /target/boot/uboot/bootdrive
				else
					umount /target/boot/uboot
				fi
			fi
		fi

		if [ ! \${got_boot_drive} ] ; then
			if [ -b /dev/mmcblk1p1 ] ; then
				mount /dev/mmcblk1p1 /target/boot/uboot
				if [ -f /target/boot/uboot/SOC.sh ] ; then
					got_boot_drive=1
					echo "/dev/mmcblk1" > /target/boot/uboot/bootdrive
				else
					umount /target/boot/uboot
				fi
			fi
		fi

		if [ ! \${got_boot_drive} ] ; then
			if [ -b /dev/mmcblk2p1 ] ; then
				mount /dev/mmcblk2p1 /target/boot/uboot
				if [ -f /target/boot/uboot/SOC.sh ] ; then
					got_boot_drive=1
					echo "/dev/mmcblk2" > /target/boot/uboot/bootdrive
				else
					umount /target/boot/uboot
				fi
			fi
		fi

		if [ ! \${got_boot_drive} ] ; then
			if [ -b /dev/mmcblk3p1 ] ; then
				mount /dev/mmcblk3p1 /target/boot/uboot
				if [ -f /target/boot/uboot/SOC.sh ] ; then
					got_boot_drive=1
					echo "/dev/mmcblk3" > /target/boot/uboot/bootdrive
				else
					umount /target/boot/uboot
				fi
			fi
		fi

		if [ -d /lib/firmware/ ] ; then
			cp -rf /lib/firmware/ /target/lib/ || true
		fi

		mount -o bind /sys /target/sys

		#Needed by finish-install.sh to determine root file system location
		cat /proc/mounts > /target/boot/uboot/mounts

		mkdir -p /target/etc/hwpack/
		cp /etc/hwpack/SOC.sh /target/etc/hwpack/
		cp /etc/hwpack/SOC.sh /target/boot/

		chroot /target /bin/bash /usr/bin/finish-install.sh

		cp /zz-uenv_txt /target/etc/kernel/postinst.d/
		chmod +x /target/etc/kernel/postinst.d/zz-uenv_txt

		rm -f /target/mounts || true

		cat /proc/mounts > /target/boot/uboot/backup/proc_mounts
		cat /var/log/syslog > /target/boot/uboot/backup/syslog.log

		umount /target/sys
		sync
		umount /target/boot/uboot

		rm -rf /target/usr/bin/finish-install.sh || true

	__EOF__

	chmod a+x "${TEMPDIR}/initrd-tree/usr/lib/finish-install.d/08rcn-ee-finish-installing-device"
}

setup_parition_recipe () {
	#This (so far) has been leaving the first Partition Alone...
	if [ "x${no_swap}" = "xenabled" ] ; then
	cat > "${TEMPDIR}/initrd-tree/partition_recipe" <<-__EOF__
		        500 1000 -1 ext4
		                method{ format } format{ }
		                use_filesystem{ } filesystem{ ext4 }
		                mountpoint{ / } label{ rootfs }
		                options/noatime{ noatime } .

	__EOF__
	else
		if [ ! "${conf_swapsize_mb}" ] ; then
			conf_swapsize_mb=1024
		fi
		
		cat > "${TEMPDIR}/initrd-tree/partition_recipe" <<-__EOF__
			        500 1000 -1 ext4
			                method{ format } format{ }
			                use_filesystem{ } filesystem{ ext4 }
			                mountpoint{ / } label{ rootfs }
			                options/noatime{ noatime } .
			 
			        128 1200 ${conf_swapsize_mb} linux-swap
			                method{ swap }
			                format{ } .

		__EOF__
	fi
}

initrd_preseed_settings () {
	echo "NetInstall: Adding Distro Tweaks and Preseed Configuration"
	cd "${TEMPDIR}/initrd-tree/" || exit

	cp -v "${DIR}/lib/${deb_distribution}-finish.sh" "${TEMPDIR}/initrd-tree/usr/bin/finish-install.sh"
	if [ "x${conf_smart_uboot}" = "xenable" ] ; then
		sed -i -e 's:smart_DISABLED:enable:g' "${TEMPDIR}/initrd-tree/usr/bin/finish-install.sh"
	fi

	neuter_flash_kernel

	finish_installing_device
	setup_parition_recipe
	cp -v "${DIR}/lib/shared/zz-uenv_txt" "${TEMPDIR}/initrd-tree/zz-uenv_txt"
	cp -v "${DIR}/lib/${DIST}-preseed.cfg" "${TEMPDIR}/initrd-tree/preseed.cfg"

	if [ ! "x${deb_not_in_repo}" = "xenable" ] ; then
		#repos.rcn-ee.com: add linux-image-${uname -r}
		sed -i -e 's:initramfs-tools:initramfs-tools linux-image-'$uname_r':g' "${TEMPDIR}/initrd-tree/preseed.cfg"
		cat "${TEMPDIR}/initrd-tree/preseed.cfg" | grep -v '#' | grep linux-image
	fi

	if [ ! "x${conf_smart_uboot}" = "xenable" ] ; then
		sed -i -e 's:initramfs-tools:initramfs-tools u-boot-tools:g' "${TEMPDIR}/initrd-tree/preseed.cfg"
	fi

	cd "${DIR}/" || true
}

extract_zimage () {
	echo "NetInstall: Extracting Kernel Boot Image"
	dpkg -x "${DIR}/dl/${DISTARCH}/${ACTUAL_DEB_FILE}" "${TEMPDIR}/kernel"
	cp -r "${TEMPDIR}/kernel/boot/dtbs/" "${TEMPDIR}"/initrd-tree/boot/ || true
}

generate_soc () {
	echo "#!/bin/sh" > "${wfile}"
	echo "format=1.0" >> "${wfile}"
	echo "" >> "${wfile}"
	if [ ! "x${conf_bootloader_in_flash}" = "xenable" ] ; then
		echo "board=${conf_board}" >> "${wfile}"
		echo "" >> "${wfile}"
		echo "bootloader_location=${bootloader_location}" >> "${wfile}"
		echo "" >> "${wfile}"
		echo "dd_spl_uboot_count=${dd_spl_uboot_count}" >> "${wfile}"
		echo "dd_spl_uboot_seek=${dd_spl_uboot_seek}" >> "${wfile}"
		echo "dd_spl_uboot_conf=${dd_spl_uboot_conf}" >> "${wfile}"
		echo "dd_spl_uboot_bs=${dd_spl_uboot_bs}" >> "${wfile}"
		echo "dd_spl_uboot_backup=${dd_spl_uboot_backup}" >> "${wfile}"
		echo "" >> "${wfile}"
		echo "dd_uboot_count=${dd_uboot_count}" >> "${wfile}"
		echo "dd_uboot_seek=${dd_uboot_seek}" >> "${wfile}"
		echo "dd_uboot_conf=${dd_uboot_conf}" >> "${wfile}"
		echo "dd_uboot_bs=${dd_uboot_bs}" >> "${wfile}"
		echo "dd_uboot_backup=${dd_uboot_backup}" >> "${wfile}"
	else
		if [ ! "x${conf_smart_uboot}" = "xenable" ] ; then
			echo "uboot_CONFIG_CMD_BOOTZ=${uboot_CONFIG_CMD_BOOTZ}" >> "${wfile}"
			echo "uboot_CONFIG_SUPPORT_RAW_INITRD=${uboot_CONFIG_SUPPORT_RAW_INITRD}" >> "${wfile}"
			echo "uboot_CONFIG_CMD_FS_GENERIC=${uboot_CONFIG_CMD_FS_GENERIC}" >> "${wfile}"
			echo "zreladdr=${conf_zreladdr}" >> "${wfile}"
		fi
	fi
	echo "" >> "${wfile}"
	echo "boot_fstype=${conf_boot_fstype}" >> "${wfile}"
	echo "" >> "${wfile}"
	echo "#Kernel" >> "${wfile}"
	echo "dtb=${dtb}" >> "${wfile}"
	echo "serial_tty=${SERIAL}" >> "${wfile}"
	echo "usbnet_mem=${usbnet_mem}" >> "${wfile}"

	if [ ! "x${di_serial_mode}" = "xenable" ] ; then
		echo "optargs=console=tty0" >> "${wfile}"
		if [ "x${drm_read_edid_broken}" = "xenable" ] ; then
			echo "video=${drm_device_identifier}:1024x768@60e" >> "${wfile}"
		fi
	fi

	echo "" >> "${wfile}"
}

initrd_device_settings () {
	echo "NetInstall: Adding Device Tweaks"

	#work around for the kevent smsc95xx issue
	touch "${TEMPDIR}/initrd-tree/etc/sysctl.conf"
	if [ "${usbnet_mem}" ] ; then
		echo "vm.min_free_kbytes = ${usbnet_mem}" >> "${TEMPDIR}/initrd-tree/etc/sysctl.conf"
	fi

	mkdir -p "${TEMPDIR}/initrd-tree/etc/hwpack/"

	wfile="${TEMPDIR}/initrd-tree/etc/hwpack/SOC.sh"
	generate_soc
}

recompress_initrd () {
	echo "NetInstall: Compressing initrd image"
	cd "${TEMPDIR}/initrd-tree/" || exit
	find . | cpio -o -H newc | gzip -9 > "${TEMPDIR}/initrd.mod.gz"
	cd "${DIR}/" || exit
}

create_custom_netinstall_image () {
	echo ""
	echo "NetInstall: Creating Custom Image"
	echo "-----------------------------"
	mkdir -p "${TEMPDIR}/kernel"
	mkdir -p "${TEMPDIR}/initrd-tree/lib/firmware/"
	mkdir -p "${TEMPDIR}/initrd-tree/fixes"

	extract_base_initrd

	#Copy Device Firmware
	cp -r "${TEMPDIR}/firmware/" "${TEMPDIR}/initrd-tree/lib/"

	if [ "${FIRMWARE}" ] ; then
		initrd_add_firmware
	fi

	initrd_cleanup
	initrd_preseed_settings
	extract_zimage
	initrd_device_settings
	recompress_initrd
}

drive_error_ro () {
	echo "-----------------------------"
	echo "Error: for some reason your SD card is not writable..."
	echo "Check: is the write protect lever set the locked position?"
	echo "Check: do you have another SD card reader?"
	echo "-----------------------------"
	echo "Script gave up..."

	exit
}

unmount_all_drive_partitions () {
	echo ""
	echo "Unmounting Partitions"
	echo "-----------------------------"

	NUM_MOUNTS=$(mount | grep -v none | grep "${media}" | wc -l)

##	for (i=1;i<=${NUM_MOUNTS};i++)
	for ((i=1;i<=${NUM_MOUNTS};i++))
	do
		DRIVE=$(mount | grep -v none | grep "${media}" | tail -1 | awk '{print $1}')
		umount ${DRIVE} >/dev/null 2>&1 || true
	done

	echo "Zeroing out Partition Table"
	echo "-----------------------------"
	dd if=/dev/zero of=${media} bs=1M count=50 || drive_error_ro
	sync
	dd if=${media} of=/dev/null bs=1M count=50
	sync
}

sfdisk_partition_layout () {
	sfdisk_options="--force --Linux --in-order --unit M"
	test_sfdisk=$(LC_ALL=C sfdisk --help | grep -m 1 -e "--in-order" || true)
	if [ "x${test_sfdisk}" = "x" ] ; then
		echo "sfdisk: 2.26.x or greater"
		sfdisk_options="--force"
		conf_boot_startmb="${conf_boot_startmb}M"
		conf_boot_endmb="${conf_boot_endmb}M"
	fi

	LC_ALL=C sfdisk ${sfdisk_options} "${media}" <<-__EOF__
		${conf_boot_startmb},${conf_boot_endmb},${sfdisk_fstype},*
	__EOF__

	sync
}

dd_uboot_boot () {
	unset dd_uboot
	if [ ! "x${dd_uboot_count}" = "x" ] ; then
		dd_uboot="${dd_uboot}count=${dd_uboot_count} "
	fi

	if [ ! "x${dd_uboot_seek}" = "x" ] ; then
		dd_uboot="${dd_uboot}seek=${dd_uboot_seek} "
	fi

	if [ ! "x${dd_uboot_conf}" = "x" ] ; then
		dd_uboot="${dd_uboot}conv=${dd_uboot_conf} "
	fi

	if [ ! "x${dd_uboot_bs}" = "x" ] ; then
		dd_uboot="${dd_uboot}bs=${dd_uboot_bs}"
	fi

	echo "${uboot_name}: dd if=${uboot_name} of=${media} ${dd_uboot}"
	echo "-----------------------------"
	dd if="${TEMPDIR}/dl/${UBOOT}" of=${media} ${dd_uboot}
	echo "-----------------------------"
}

dd_spl_uboot_boot () {
	unset dd_spl_uboot
	if [ ! "x${dd_spl_uboot_count}" = "x" ] ; then
		dd_spl_uboot="${dd_spl_uboot}count=${dd_spl_uboot_count} "
	fi

	if [ ! "x${dd_spl_uboot_seek}" = "x" ] ; then
		dd_spl_uboot="${dd_spl_uboot}seek=${dd_spl_uboot_seek} "
	fi

	if [ ! "x${dd_spl_uboot_conf}" = "x" ] ; then
		dd_spl_uboot="${dd_spl_uboot}conv=${dd_spl_uboot_conf} "
	fi

	if [ ! "x${dd_spl_uboot_bs}" = "x" ] ; then
		dd_spl_uboot="${dd_spl_uboot}bs=${dd_spl_uboot_bs}"
	fi

	echo "${spl_uboot_name}: dd if=${spl_uboot_name} of=${media} ${dd_spl_uboot}"
	echo "-----------------------------"
	dd if="${TEMPDIR}/dl/${SPL}" of=${media} ${dd_spl_uboot}
	echo "-----------------------------"
}

format_partition_error () {
	echo "LC_ALL=C ${mkfs} ${mkfs_partition} ${mkfs_label}"
	echo "Failure: formating partition"
	exit
}

format_partition () {
	echo "Formating with: [${mkfs} ${mkfs_partition} ${mkfs_label}]"
	echo "-----------------------------"
	LC_ALL=C ${mkfs} ${mkfs_partition} ${mkfs_label} || format_partition_error
	sync
}

format_boot_partition () {
	mkfs_partition="${media_prefix}${media_boot_partition}"

	if [ "x${conf_boot_fstype}" = "xfat" ] ; then
		mount_partition_format="vfat"
		mkfs="mkfs.vfat -F 16"
		mkfs_label="-n ${BOOT_LABEL}"
	else
		mount_partition_format="${conf_boot_fstype}"
		mkfs="mkfs.${conf_boot_fstype}"
		mkfs_label="-L ${BOOT_LABEL}"
	fi

	format_partition
}

create_partitions () {
	unset bootloader_installed

	media_boot_partition=1

	echo ""
	case "${bootloader_location}" in
	fatfs_boot)
		echo "Using sfdisk to create partition layout"
		echo "Version: `LC_ALL=C sfdisk --version`"
		echo "-----------------------------"
		sfdisk_partition_layout
		;;
	dd_uboot_boot)
		echo "Using dd to place bootloader on drive"
		echo "-----------------------------"
		dd_uboot_boot
		bootloader_installed=1
		sfdisk_partition_layout
		;;
	dd_spl_uboot_boot)
		echo "Using dd to place bootloader on drive"
		echo "-----------------------------"
		dd_spl_uboot_boot
		dd_uboot_boot
		bootloader_installed=1
		sfdisk_partition_layout
		;;
	*)
		echo "Using sfdisk to create partition layout"
		echo "Version: `LC_ALL=C sfdisk --version`"
		echo "-----------------------------"
		sfdisk_partition_layout
		;;
	esac

	echo "Partition Setup:"
	echo "-----------------------------"
	LC_ALL=C fdisk -l "${media}"
	echo "-----------------------------"

	format_boot_partition
}

populate_boot () {
	echo "Populating Boot Partition"
	echo "-----------------------------"

	if [ ! -d "${TEMPDIR}/disk" ] ; then
		mkdir -p "${TEMPDIR}/disk"
	fi

	#FIXME for some reason debian jessie, this failes now...
	partprobe ${media}
	if ! mount -t ${mount_partition_format} ${media_prefix}${media_boot_partition} "${TEMPDIR}/disk"; then

	echo "Mount Failure, trying 2nd time in 5 seconds..."
	partprobe ${media}
	sync
	sleep 5

		if ! mount -t ${mount_partition_format} ${media_prefix}${media_boot_partition} "${TEMPDIR}/disk"; then
			echo "-----------------------------"
			echo "Unable to mount ${media_prefix}${media_boot_partition} at ${TEMPDIR}/disk to complete populating Boot Partition"
			echo "Please retry running the script, sometimes rebooting your system helps."
			echo "-----------------------------"
			exit
		fi
	fi

	mkdir -p "${TEMPDIR}/disk/backup" || true
	mkdir -p "${TEMPDIR}/disk/boot/dtbs/current/" || true

	if [ "${spl_name}" ] ; then
		if [ -f "${TEMPDIR}/dl/${SPL}" ] ; then
			if [ ! "${bootloader_installed}" ] ; then
				cp -v "${TEMPDIR}/dl/${SPL}" "${TEMPDIR}/disk/${spl_name}"
				echo "-----------------------------"
			fi
			cp -v "${TEMPDIR}/dl/${SPL}" "${TEMPDIR}/disk/backup/${spl_name}"
			echo "-----------------------------"
		fi
	fi


	if [ "${boot_name}" ] ; then
		if [ -f "${TEMPDIR}/dl/${UBOOT}" ] ; then
			if [ ! "${bootloader_installed}" ] ; then
				cp -v "${TEMPDIR}/dl/${UBOOT}" "${TEMPDIR}/disk/${boot_name}"
				echo "-----------------------------"
			fi
			cp -v "${TEMPDIR}/dl/${UBOOT}" "${TEMPDIR}/disk/backup/${boot_name}"
			echo "-----------------------------"
		fi
	fi

	if [ -f "${TEMPDIR}"/kernel/boot/vmlinuz-* ] ; then
		LINUX_VER=$(ls ${TEMPDIR}/kernel/boot/vmlinuz-* | awk -F'vmlinuz-' '{print $2}')
		echo "Copying Kernel images:"
		cp -v "${TEMPDIR}"/kernel/boot/vmlinuz-* "${TEMPDIR}/disk/boot/vmlinuz-current"

		if [ ! "x${conf_config_distro_defaults}" = "xenable" ] ; then
			if [ ! "x${conf_smart_uboot}" = "xenable" ] ; then
				if [ ! "x${uboot_CONFIG_CMD_BOOTZ}" = "xenable" ] ; then
					mkimage -A arm -O linux -T kernel -C none -a ${conf_zreladdr} -e ${conf_zreladdr} -n ${LINUX_VER} -d "${TEMPDIR}"/kernel/boot/vmlinuz-* "${TEMPDIR}/disk/uImage.net"
				fi
			fi
		fi

		echo "-----------------------------"
	fi

	if [ -f "${TEMPDIR}/initrd.mod.gz" ] ; then
		#This is 20+ MB in size, just copy one..
		echo "Copying Kernel initrds:"
		cp -v "${TEMPDIR}/initrd.mod.gz" "${TEMPDIR}/disk/boot/initrd.img-current"

		if [ ! "x${conf_config_distro_defaults}" = "xenable" ] ; then
			if [ ! "x${conf_smart_uboot}" = "xenable" ] ; then
				if [ ! "x${uboot_CONFIG_SUPPORT_RAW_INITRD}" = "xenable" ] ; then
					mkimage -A arm -O linux -T ramdisk -C none -a 0 -e 0 -n initramfs -d "${TEMPDIR}/initrd.mod.gz" "${TEMPDIR}/disk/uInitrd.net"
				fi
			fi
		fi
		echo "-----------------------------"
	fi

	echo "Copying Device Tree Files:"
	if [ ! "x${deb_not_in_repo}" = "xenable" ] ; then
		cp "${TEMPDIR}"/kernel/boot/dtbs/${uname_r}/*.dtb "${TEMPDIR}/disk/boot/dtbs/current/"
	else
		cp "${TEMPDIR}"/kernel/boot/dtbs/${LINUX_VER}/*.dtb "${TEMPDIR}/disk/boot/dtbs/current/"
	fi

	if [ "x${conf_config_distro_defaults}" = "xenable" ] ; then
		mkimage -A arm -O linux -T script -C none -a 0 -e 0 -n "uEnv.txt" -d "${DIR}/lib/distro_defaults.cmd" "${TEMPDIR}/disk/boot/boot.scr"
	fi

	if [ "${conf_uboot_bootscript}" ] ; then
		case "${dtb}" in
		imx6q-nitrogen6x.dtb|imx6q-sabrelite.dtb)
			cat > "${TEMPDIR}/bootscripts/loader.cmd" <<-__EOF__
				echo "${conf_uboot_bootscript} -> uEnv.txt wrapper..."
				setenv bootpart \$disk:1
				${conf_fileload} mmc \${bootpart} \${loadaddr} uEnv.txt
				env import -t \${loadaddr} \${filesize}
				run uenvcmd
			__EOF__
			;;
		esac
		if [ -f "${TEMPDIR}/bootscripts/loader.cmd" ] ; then
			cat "${TEMPDIR}/bootscripts/loader.cmd"
			echo "-----------------------------"
			mkimage -A arm -O linux -T script -C none -a 0 -e 0 -n "wrapper" -d "${TEMPDIR}/bootscripts/loader.cmd" "${TEMPDIR}/disk/${conf_uboot_bootscript}"
			cp -v "${TEMPDIR}/disk/${conf_uboot_bootscript}" "${TEMPDIR}/disk/backup/${conf_uboot_bootscript}"
		else
			echo "Error: dtb not defined with conf_uboot_bootscript"
			exit 1
		fi
	fi

	echo "Copying uEnv.txt based boot scripts to Boot Partition"

	if [ "x${conf_smart_uboot}" = "xenable" ] ; then
		wfile="${TEMPDIR}/disk/boot/uEnv.txt"

		echo "uname_r=current" > "${wfile}"

		if [ ! "x${dtb}" = "x" ] ; then
			echo "dtb=${dtb}" >>  "${wfile}"
		else
			echo "#dtb=" >>  "${wfile}"
		fi

		mmcargs="mmcargs=run message; setenv bootargs console"

		if [ "x${di_serial_mode}" = "xenable" ] ; then
			echo "message=echo; echo Installer for [${DISTARCH}] is using the Serial Interface; echo;" >> "${wfile}"
			mmcargs="${mmcargs}=${SERIAL_CONSOLE} root=/dev/ram0 rw"
			netinstall_bootargs="console=${SERIAL_CONSOLE}"
		else
			echo "message=echo; echo Installer for [${DISTARCH}] is using the Video Interface; echo Use [--serial-mode] to force Installing over the Serial Interface; echo;" >> "${wfile}"
			mmcargs="${mmcargs}=tty0 root=/dev/ram0 rw"
			netinstall_bootargs="console=tty0"
		fi

		if [ "x${drm_read_edid_broken}" = "xenable" ] ; then
			mmcargs="${mmcargs} video=${drm_device_identifier}:1024x768@60e"
			netinstall_bootargs="${netinstall_bootargs} video=${drm_device_identifier}:1024x768@60e"
		fi

		if [ ! "x${cmdline}" = "x" ] ; then
			mmcargs="${mmcargs} ${cmdline}"
		fi

		if [ "x${conf_netinstall_enable}" = "xenable" ] ; then
			echo "netinstall_enable=enable" >> "${wfile}"
			echo "netinstall_bootargs=${netinstall_bootargs}" >> "${wfile}"
			echo "cmdline=${cmdline}" >> "${wfile}"
		else
			echo "${mmcargs}" >> "${wfile}"
		fi

		echo "Net Install Boot Script:"
		echo "-----------------------------"
		cat "${wfile}"
		echo "-----------------------------"

	else

		echo "Net Install Boot Script:"
		cp -v "${TEMPDIR}/bootscripts/netinstall.cmd" "${TEMPDIR}/disk/uEnv.txt"
		echo "-----------------------------"
		cat "${TEMPDIR}/bootscripts/netinstall.cmd"
		rm -rf "${TEMPDIR}/bootscripts/netinstall.cmd" || true
		echo "-----------------------------"
		echo "Normal Boot Script:"
		cp -v "${TEMPDIR}/bootscripts/normal.cmd" "${TEMPDIR}/disk/backup/normal.txt"
		echo "-----------------------------"
		cat "${TEMPDIR}/bootscripts/normal.cmd"
		rm -rf "${TEMPDIR}/bootscripts/normal.cmd" || true
		echo "-----------------------------"

	fi

	wfile="${TEMPDIR}/disk/SOC.sh"
	generate_soc

	cd "${TEMPDIR}/disk" || exit
	sync
	cd "${DIR}/" || exit

	echo "Debug: Contents of Boot Partition"
	echo "-----------------------------"
	ls -lh "${TEMPDIR}/disk/"
	du -sh "${TEMPDIR}/disk/"
	echo "-----------------------------"

	umount "${TEMPDIR}/disk" || true

	echo "Finished populating Boot Partition"
	echo "-----------------------------"

	echo "mk_mmc.sh script complete"
	echo "Script Version git: ${GIT_VERSION}"
	echo "-----------------------------"
	if [ "${conf_note}" ] ; then
		echo "${conf_note}"
		echo "-----------------------------"
	fi
	if [ "${conf_note_bootloader}" ] ; then
		echo "This script requires the bootloader to be already installed, see:"
		echo "${conf_note_bootloader}"
		echo "-----------------------------"
	fi
	echo "Reporting Bugs:"
	echo "https://github.com/RobertCNelson/netinstall/issues"
	echo "Please include: /var/log/netinstall.log from RootFileSystem"
	echo "-----------------------------"
}

check_mmc () {
	FDISK=$(LC_ALL=C fdisk -l 2>/dev/null | grep "Disk ${media}[^(a-z,A-Z,0-9)]" | awk '{print $2}')

	if [ "x${FDISK}" = "x${media}:" ] ; then
		echo ""
		echo "I see..."
		echo "lsblk:"
		lsblk | grep -v sr0
		echo ""
		unset response
		echo -n "Are you 100% sure, on selecting [${media}] (y/n)? "
		read response
		if [ "x${response}" != "xy" ] ; then
			exit
		fi
		echo ""
	else
		echo ""
		echo "Are you sure? I Don't see [${media}], here is what I do see..."
		echo ""
		echo "lsblk:"
		lsblk | grep -v sr0
		echo ""
		exit
	fi
}

uboot_dtb_error () {

	if [ "${tried_uboot}" ] ; then
		echo "-----------------------------"
		echo "[--uboot <board>] has been replaced by [--dtb <board>]"
		echo "see the list below..."
		echo "-----------------------------"
	fi

	echo "--dtb (device tree) options..."
	cat <<-__EOF__
		-----------------------------
		ERROR: This script does not currently recognize the selected: [--dtb ${dtb_board}] option..
		Please rerun $(basename $0) with a valid [--dtb <device>] option from the list below:
		-----------------------------
	__EOF__
	cat "${DIR}"/hwpack/*.conf | grep supported
	echo "-----------------------------"
}

show_board_warning () {
	echo "-----------------------------"
	echo "Warning: at this time, this board [${dtb_board}] has a few issues with the NetInstall"
	echo "-----------------------------"
	echo "${conf_warning}"
	echo "-----------------------------"
	echo "Alternate install:"
	echo "http://elinux.org/BeagleBoardDebian#Demo_Image"
	echo "-----------------------------"
	unset response
	echo -n "Knowing these issues, would you like to continue to install [${dtb_board}] (y/n)? "
	read response
	if [ "x${response}" != "xy" ] ; then
		exit
	fi
}

process_dtb_conf () {
	if [ "${conf_warning}" ] ; then
		show_board_warning
	fi

	echo "-----------------------------"

	#defaults, if not set...
	conf_boot_startmb=${conf_boot_startmb:-"4"}
	conf_boot_endmb=${conf_boot_endmb:-"144"}
	conf_root_device=${conf_root_device:-"/dev/mmcblk0"}

	#error checking...
	if [ ! "${conf_boot_fstype}" ] ; then
		echo "Error: [conf_boot_fstype] not defined, stopping..."
		exit
	else
		case "${conf_boot_fstype}" in
		fat)
			sfdisk_fstype="0xE"
			;;
		ext2|ext3|ext4)
			sfdisk_fstype="L"
			;;
		*)
			echo "Error: [conf_boot_fstype] not recognized, stopping..."
			exit
			;;
		esac
	fi

	if [ ! "x${conf_config_distro_defaults}" = "xenable" ] ; then
		if [ ! "x${uboot_CONFIG_CMD_BOOTZ}" = "xenable" ] ; then
			conf_bootcmd="bootm"
			kernel=/boot/uImage
		fi

		if [ ! "x${uboot_CONFIG_SUPPORT_RAW_INITRD}" = "xenable" ] ; then
			initrd=/boot/uInitrd
		fi

		if [ "x${uboot_CONFIG_CMD_FS_GENERIC}" = "xenable" ] ; then
			conf_fileload="load"
		else
			if [ "x${conf_boot_fstype}" = "xfat" ] ; then
				conf_fileload="fatload"
			else
				conf_fileload="ext2load"
			fi
		fi
	fi

	unset kernel_selected
	if [ ! "x${kernel_repo}" = "x" ] ; then
		kernel_selected="true"
	fi
}

check_dtb_board () {
	error_invalid_dtb=1

	#/hwpack/${dtb_board}.conf
	unset leading_slash
	leading_slash=$(echo "${dtb_board}" | grep "/" || unset leading_slash)
	if [ "${leading_slash}" ] ; then
		dtb_board=$(echo "${leading_slash##*/}")
	fi

	#${dtb_board}.conf
	dtb_board=$(echo "${dtb_board}" | awk -F ".conf" '{print $1}')
	if [ -f "${DIR}/hwpack/${dtb_board}.conf" ] ; then
		. "${DIR}/hwpack/${dtb_board}.conf"
		unset error_invalid_dtb
		process_dtb_conf
	else
		uboot_dtb_error
		exit
	fi
}

check_distro () {
	unset IN_VALID_DISTRO
	ARCH="armhf"

	case "${DISTRO_TYPE}" in
	stretch|stretch-armhf)
		DIST="stretch"
		deb_distribution="debian"
		;;
	buster|buster-armhf)
		DIST="buster"
		deb_distribution="debian"
		;;
	*)
		IN_VALID_DISTRO=1
		cat <<-__EOF__
			-----------------------------
			ERROR: This script does not currently recognize the selected: [--distro ${DISTRO_TYPE}] option..
			Please rerun $(basename $0) with a valid [--distro <distro>] option from the list below:
			-----------------------------
			--distro <distro>
			        stretch (Debian 9)
			        buster (Debian 10) <default>
			-----------------------------
		__EOF__
		exit
		;;
	esac
	DISTARCH="${DIST}-${ARCH}"
}

usage () {
	echo "usage: sudo $(basename $0) --mmc /dev/sdX --dtb <dev board>"
	#tabed to match 
		cat <<-__EOF__
			Script Version git: ${GIT_VERSION}
			-----------------------------
			Bugs email: "bugs at rcn-ee.com"

			Required Options:
			--mmc </dev/sdX>

			--dtb <dev board>
			        A10-OLinuXino-Lime
			        A20-OLinuXino-Lime
			        A20-OLinuXino-Lime2
			        am335x-boneblack
			        am335x-bone-serial
			        am335x-bone-video
			        imx51-babbage
			        imx53-qsb
			        imx6q-sabrelite
			        imx6q-sabresd
			        omap3-beagle
			        omap3-beagle-xm
			        omap4-panda
			        omap4-panda-a4
			        omap4-panda-es
			        omap4-panda-es-b3
			        omap5-uevm
			        tegra124-jetson-tk1
			        udoo
			        wandboard

			Optional:
			--distro <distro>
			        stretch (Debian 9)
			        buster (Debian 10) <default>

			--firmware
			        <include all firmwares from linux-firmware git repo>

			--serial-mode
			        <use the serial to run the netinstall (video ouputs will remain blank till final reboot)>

			Additional Options:
			        -h --help

			--probe-mmc
			        <list all partitions: sudo ./mk_mmc.sh --probe-mmc>

			__EOF__
	exit
}

checkparm () {
	if [ "$(echo $1|grep ^'\-')" ] ; then
		echo "E: Need an argument"
		usage
	fi
}

error_invalid_dtb=1
unset cmd_kernel_override

# parse commandline options
while [ ! -z "$1" ] ; do
	case $1 in
	-h|--help)
		usage
		media=1
		;;
	--probe-mmc)
		media="/dev/idontknow"
		check_root
		check_mmc
		;;
	--mmc)
		checkparm $2
		media="$2"
		media_prefix="${media}"
		echo ${media} | grep mmcblk >/dev/null && media_prefix="${media}p"
		check_root
		check_mmc
		;;
	--no-swap)
		no_swap="enabled"
		;;
	--uboot)
		checkparm $2
		UBOOT_TYPE="$2"
		unset dtb_board
		tried_uboot=1
		check_dtb_board
		;;
	--dtb)
		checkparm $2
		dtb_board="$2"
		check_dtb_board
		;;
	--distro)
		checkparm $2
		DISTRO_TYPE="$2"
		check_distro
		;;
	--firmware)
		FIRMWARE=1
		;;
	--serial-mode)
		di_serial_mode="enable"
		;;
	--deb-file)
		checkparm $2
		external_deb_file="$2"
		DEB_FILE="${external_deb_file}"
		KERNEL_DEB=1
		deb_not_in_repo="enable"
		;;
	--use-lts-kernel|--use-lts-4_1-kernel)
		cmd_LTS41_KERNEL="enable"
		cmd_kernel_override="enable"
		;;
	--use-lts-4_4-kernel)
		cmd_LTS44_KERNEL="enable"
		cmd_kernel_override="enable"
		;;
	--use-lts-4_9-kernel)
		cmd_LTS49_KERNEL="enable"
		cmd_kernel_override="enable"
		;;
	--use-stable-kernel)
		cmd_STABLE_KERNEL="enable"
		cmd_kernel_override="enable"
		;;
	--use-beta-kernel|--use-testing-kernel)
		cmd_TESTING_KERNEL="enable"
		cmd_kernel_override="enable"
		;;
	--use-experimental-kernel)
		cmd_EXPERIMENTAL_KERNEL="enable"
		cmd_kernel_override="enable"
		;;
	--spl)
		checkparm $2
		LOCAL_SPL="$2"
		USE_LOCAL_BOOT=1
		;;
	--bootloader)
		checkparm $2
		LOCAL_BOOTLOADER="$2"
		USE_LOCAL_BOOT=1
		;;
	--use-beta-bootloader)
		USE_BETA_BOOTLOADER=1
		;;
	esac
	shift
done

if [ ! "${media}" ] ; then
	echo "ERROR: --mmc undefined"
	usage
fi

if [ "${error_invalid_dtb}" ] ; then
	echo "-----------------------------"
	echo "ERROR: --dtb undefined"
	echo "-----------------------------"
	uboot_dtb_error
	exit
fi

echo ""
echo "Script Version git: ${GIT_VERSION}"
echo "-----------------------------"

check_root
detect_software

if [ ! "x${conf_bootloader_in_flash}" = "xenable" ] ; then
	if [ "${spl_name}" ] || [ "${boot_name}" ] ; then
		if [ "${USE_LOCAL_BOOT}" ] ; then
			local_bootloader
		else
			dl_bootloader
		fi
	fi
fi

dl_kernel_image
dl_netinstall_image

dl_device_firmware

setup_bootscripts
create_custom_netinstall_image

unmount_all_drive_partitions
create_partitions
populate_boot
