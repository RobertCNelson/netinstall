#!/bin/bash
#
# Copyright (c) 2009-2012 Robert Nelson <robertcnelson@gmail.com>
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

MIRROR="http://rcn-ee.net/deb"
BACKUP_MIRROR="http://rcn-ee.homeip.net:81/dl/mirrors/deb"

BOOT_LABEL="boot"
PARTITION_PREFIX=""

unset MMC
unset USE_BETA_BOOTLOADER
unset USE_LOCAL_BOOT
unset LOCAL_BOOTLOADER
unset ADDON

unset FIRMWARE
unset SERIAL_MODE
unset BETA_KERNEL
unset EXPERIMENTAL_KERNEL
unset KERNEL_DEB

GIT_VERSION=$(git rev-parse --short HEAD)
IN_VALID_UBOOT=1

DIST=squeeze
ARCH=armel
DISTARCH="${DIST}-${ARCH}"

#06-Oct-2010
#http://ports.ubuntu.com/dists/maverick/main/installer-armel/
MAVERICK_NETIMAGE="current"
MAVERICK_MD5SUM="12c0f04da6b8fb118939489f237e4c86"

#21-Apr-2011
#http://ports.ubuntu.com/dists/natty/main/installer-armel/
NATTY_NETIMAGE="current"
NATTY_MD5SUM="a88f348be5c94873be0d67a9ce8e485e"

#08-Oct-2011
#http://ports.ubuntu.com/dists/oneiric/main/installer-armel/
ONEIRIC_NETIMAGE="current"
ONEIRIC_MD5SUM="3a8978191d7a0544e229de54e4cc8e76"

#23-Apr-2012
#http://ports.ubuntu.com/dists/precise/main/installer-armel/
PRECISE_ARMEL_NETIMAGE="20101020ubuntu136"
PRECISE_ARMEL_MD5SUM="8e1f3d4a0df6bcf816f516e2226ba7f3"

#23-Apr-2012
#http://ports.ubuntu.com/dists/precise/main/installer-armhf/
PRECISE_ARMHF_NETIMAGE="20101020ubuntu136"
PRECISE_ARMHF_MD5SUM="2b8a00ada904f3b2b72f3d92ccbaa830"

#27-Aug-2012
#http://ports.ubuntu.com/dists/quantal/main/installer-armhf/
QUANTAL_ARMHF_NETIMAGE="20101020ubuntu169"
QUANTAL_ARMHF_MD5SUM="e4c3de2e7f6a3dfd8b3233840398ed90"

#03-May-2012: 6.0.4+b1
#http://ftp.us.debian.org/debian/dists/squeeze/main/installer-armel/
SQUEEZE_NETIMAGE="20110106+squeeze4+b1"
SQUEEZE_MD5SUM="03a43fb3440e01aeba1b4c9d2dbd946a"

#12-Jul-2012
#http://ftp.us.debian.org/debian/dists/wheezy/main/installer-armel/
WHEEZY_ARMEL_NETIMAGE="20120712"
WHEEZY_ARMEL_MD5SUM="ae0a65fdb30565c6dcfe582f3483a7ce"

#12-Jul-2012
#http://ftp.us.debian.org/debian/dists/wheezy/main/installer-armhf/
WHEEZY_ARMHF_NETIMAGE="20120712"
WHEEZY_ARMHF_MD5SUM="16b5148acb0b0b80b76f8791c6ece9f6"

DIR="$PWD"
TEMPDIR=$(mktemp -d)

function is_element_of {
	testelt=$1
	for validelt in $2 ; do
		[ $testelt = $validelt ] && return 0
	done
	return 1
}

#########################################################################
#
#  Define valid "--addon" values.
#
#########################################################################

VALID_ADDONS="pico"

function is_valid_addon {
	if is_element_of $1 "${VALID_ADDONS}" ] ; then
		return 0
	else
		return 1
	fi
}

function check_root {
	if [[ ${UID} -ne 0 ]] ; then
		echo "$0 must be run as sudo user or root"
		exit
	fi
}

function check_for_command {
	if ! which "$1" > /dev/null ; then
		echo -n "You're missing command $1"
		NEEDS_COMMAND=1
		if [ -n "$2" ] ; then
			echo -n " (consider installing package $2)"
		fi
		echo
	fi
}

function detect_software {
	unset NEEDS_COMMAND

	check_for_command mkfs.vfat dosfstools
	check_for_command wget wget
	check_for_command parted parted
	check_for_command dpkg dpkg
	check_for_command patch patch

	if [ "${NEEDS_COMMAND}" ] ; then
		echo ""
		echo "Your system is missing some dependencies"
		echo "Ubuntu/Debian: sudo apt-get install wget dosfstools parted"
		echo "Fedora: as root: yum install wget dosfstools parted dpkg patch"
		echo "Gentoo: emerge wget dosfstools parted dpkg"
		echo ""
		exit
	fi

	#Check for gnu-fdisk
	#FIXME: GNU Fdisk seems to halt at "Using /dev/xx" when trying to script it..
	if fdisk -v | grep "GNU Fdisk" >/dev/null ; then
		echo "Sorry, this script currently doesn't work with GNU Fdisk."
		echo "Install the version of fdisk from your distribution's util-linux package."
		exit
	fi

	unset PARTED_ALIGN
	if parted -v | grep parted | grep 2.[1-3] >/dev/null ; then
		PARTED_ALIGN="--align cylinder"
	fi
}

function rcn-ee_down_use_mirror {
	echo "rcn-ee.net down, switching to slower backup mirror"
	echo "-----------------------------"
	MIRROR=${BACKUP_MIRROR}
	RCNEEDOWN=1
}

function local_bootloader {
	echo ""
	echo "Using Locally Stored Device Bootloader"
	echo "-----------------------------"
	mkdir -p ${TEMPDIR}/dl/

	if [ "${spl_name}" ] ; then
		cp ${LOCAL_SPL} ${TEMPDIR}/dl/
		MLO=${LOCAL_SPL##*/}
		echo "SPL Bootloader: ${MLO}"
	fi

	if [ "${boot_name}" ] ; then
		cp ${LOCAL_BOOTLOADER} ${TEMPDIR}/dl/
		UBOOT=${LOCAL_BOOTLOADER##*/}
		echo "UBOOT Bootloader: ${UBOOT}"
	fi
}

function dl_bootloader {
	echo ""
	echo "Downloading Device's Bootloader"
	echo "-----------------------------"
	unset disable_mirror

	mkdir -p ${TEMPDIR}/dl/${DISTARCH}
	mkdir -p "${DIR}/dl/${DISTARCH}"

	unset RCNEEDOWN
	if [ "${disable_mirror}" ] ; then
		wget --no-verbose --directory-prefix=${TEMPDIR}/dl/ ${MIRROR}/tools/latest/bootloader
	else
		echo "attempting to use rcn-ee.net for dl files [10 second time out]..."
		wget -T 10 -t 1 --no-verbose --directory-prefix=${TEMPDIR}/dl/ ${MIRROR}/tools/latest/bootloader
	fi

	if [ ! -f ${TEMPDIR}/dl/bootloader ] ; then
		if [ "${disable_mirror}" ] ; then
			echo "error: can't connect to rcn-ee.net, retry in a few minutes (backup mirror down)"
			exit
		else
			rcn-ee_down_use_mirror
			wget --no-verbose --directory-prefix=${TEMPDIR}/dl/ ${MIRROR}/tools/latest/bootloader
		fi
	fi

	if [ "${RCNEEDOWN}" ] ; then
		sed -i -e "s/rcn-ee.net/rcn-ee.homeip.net:81/g" ${TEMPDIR}/dl/bootloader
		sed -i -e 's:81/deb/:81/dl/mirrors/deb/:g' ${TEMPDIR}/dl/bootloader
	fi

	if [ "${USE_BETA_BOOTLOADER}" ] ; then
		ABI="ABX2"
	else
		ABI="ABI2"
	fi

	if [ "${spl_name}" ] ; then
		MLO=$(cat ${TEMPDIR}/dl/bootloader | grep "${ABI}:${BOOTLOADER}:SPL" | awk '{print $2}')
		wget --no-verbose --directory-prefix=${TEMPDIR}/dl/ ${MLO}
		MLO=${MLO##*/}
		echo "SPL Bootloader: ${MLO}"
	else
		unset MLO
	fi

	if [ "${boot_name}" ] ; then
		UBOOT=$(cat ${TEMPDIR}/dl/bootloader | grep "${ABI}:${BOOTLOADER}:BOOT" | awk '{print $2}')
		wget --directory-prefix=${TEMPDIR}/dl/ ${UBOOT}
		UBOOT=${UBOOT##*/}
		echo "UBOOT Bootloader: ${UBOOT}"
	else
		unset UBOOT
	fi
}

function dl_kernel_image {
	echo ""
	echo "Downloading Device's Kernel Image"
	echo "-----------------------------"

	if [ "${BETA_KERNEL}" ] ; then
		KERNEL_SEL="TESTING"
	fi

	if [ "${EXPERIMENTAL_KERNEL}" ] ; then
		KERNEL_SEL="EXPERIMENTAL"
	fi

	if [ ! "${KERNEL_DEB}" ] ; then
		wget --no-verbose --directory-prefix=${TEMPDIR}/dl/ ${MIRROR}/${DISTARCH}/LATEST-${SUBARCH}

		if [ "$RCNEEDOWN" ] ; then
			sed -i -e "s/rcn-ee.net/rcn-ee.homeip.net:81/g" ${TEMPDIR}/dl/LATEST-${SUBARCH}
			sed -i -e 's:81/deb/:81/dl/mirrors/deb/:g' ${TEMPDIR}/dl/LATEST-${SUBARCH}
		fi

		FTP_DIR=$(cat ${TEMPDIR}/dl/LATEST-${SUBARCH} | grep "ABI:1 ${KERNEL_SEL}" | awk '{print $3}')
		if [ "$RCNEEDOWN" ] ; then
			#http://rcn-ee.homeip.net:81/dl/mirrors/deb/squeeze-armel/v3.2.6-x4/install-me.sh
			FTP_DIR=$(echo ${FTP_DIR} | awk -F'/' '{print $8}')
		else
			#http://rcn-ee.net/deb/squeeze-armel/v3.2.6-x4/install-me.sh
			FTP_DIR=$(echo ${FTP_DIR} | awk -F'/' '{print $6}')
		fi
		KERNEL=$(echo ${FTP_DIR} | sed 's/v//')

		wget --no-verbose --directory-prefix=${TEMPDIR}/dl/ ${MIRROR}/${DISTARCH}/${FTP_DIR}/
		ACTUAL_DEB_FILE=$(cat ${TEMPDIR}/dl/index.html | grep linux-image)
		ACTUAL_DEB_FILE=$(echo ${ACTUAL_DEB_FILE} | awk -F ".deb" '{print $1}')
		ACTUAL_DEB_FILE=${ACTUAL_DEB_FILE##*linux-image-}
		ACTUAL_DEB_FILE="linux-image-${ACTUAL_DEB_FILE}.deb"

		wget -c --directory-prefix="${DIR}/dl/${DISTARCH}" ${MIRROR}/${DISTARCH}/v${KERNEL}/${ACTUAL_DEB_FILE}

		if [ "${need_dtbs}" ] ; then
			ACTUAL_DTB_FILE=$(cat ${TEMPDIR}/dl/index.html | grep dtbs.tar.gz)
			#<a href="3.5.0-imx2-dtbs.tar.gz">3.5.0-imx2-dtbs.tar.gz</a> 08-Aug-2012 21:34 8.7K
			ACTUAL_DTB_FILE=$(echo ${ACTUAL_DTB_FILE} | awk -F ">" '{print $2}')
			#3.5.0-imx2-dtbs.tar.gz</a
			ACTUAL_DTB_FILE=$(echo ${ACTUAL_DTB_FILE} | awk -F ".gz" '{print $1}')
			ACTUAL_DTB_FILE="${ACTUAL_DTB_FILE}.gz"

			wget -c --directory-prefix="${DIR}/dl/${DISTARCH}" ${MIRROR}/${DISTARCH}/v${KERNEL}/${ACTUAL_DTB_FILE}
		fi

	else
		KERNEL=${DEB_FILE}
		#Remove all "\" from file name.
		ACTUAL_DEB_FILE=$(echo ${DEB_FILE} | sed 's!.*/!!' | grep linux-image)
		cp -v ${DEB_FILE} "${DIR}/dl/${DISTARCH}/"
	fi
	echo "Using Kernel: ${ACTUAL_DEB_FILE}"
	if [ "${need_dtbs}" ] ; then
		echo "Using DTBS: ${ACTUAL_DTB_FILE}"
	fi
}

function remove_uboot_wrapper {
	echo "Note: NetInstall has u-boot header, removing..."
	echo "-----------------------------"
	dd if="${DIR}/dl/${DISTARCH}/${NETINSTALL}" bs=64 skip=1 of="${DIR}/dl/${DISTARCH}/initrd.gz"
	echo "-----------------------------"
	NETINSTALL="initrd.gz"
	unset UBOOTWRAPPER
}

function actually_dl_netinstall {
	wget --directory-prefix="${DIR}/dl/${DISTARCH}" ${HTTP_IMAGE}/${DIST}/main/installer-${ARCH}/${NETIMAGE}/images/${BASE_IMAGE}/${NETINSTALL}
	MD5SUM=$(md5sum "${DIR}/dl/${DISTARCH}/${NETINSTALL}" | awk '{print $1}')
	if [ "${UBOOTWRAPPER}" ] ; then
		remove_uboot_wrapper
	fi
}

function check_dl_netinstall {
	MD5SUM=$(md5sum "${DIR}/dl/${DISTARCH}/${NETINSTALL}" | awk '{print $1}')
	if [ "x${TEST_MD5SUM}" != "x${MD5SUM}" ] ; then
		echo "Note: NetInstall md5sum has changed: ${MD5SUM}"
		echo "-----------------------------"
		rm -f "${DIR}/dl/${DISTARCH}/${NETINSTALL}" || true
		actually_dl_netinstall
	else
		if [ "${UBOOTWRAPPER}" ] ; then
			remove_uboot_wrapper
		fi
	fi
}

function dl_netinstall_image {
	echo ""
	echo "Downloading NetInstall Image"
	echo "-----------------------------"

	unset UBOOTWRAPPER
	case "${DISTARCH}" in
	maverick-armel)
		TEST_MD5SUM=$MAVERICK_MD5SUM
		NETIMAGE=$MAVERICK_NETIMAGE
		HTTP_IMAGE="http://ports.ubuntu.com/ubuntu-ports/dists"
		BASE_IMAGE="versatile/netboot"
		NETINSTALL="initrd.gz"
		;;
	natty-armel)
		TEST_MD5SUM=$NATTY_MD5SUM
		NETIMAGE=$NATTY_NETIMAGE
		HTTP_IMAGE="http://ports.ubuntu.com/ubuntu-ports/dists"
		BASE_IMAGE="versatile/netboot"
		NETINSTALL="initrd.gz"
		;;
	oneiric-armel)
		TEST_MD5SUM=$ONEIRIC_MD5SUM
		NETIMAGE=$ONEIRIC_NETIMAGE
		HTTP_IMAGE="http://ports.ubuntu.com/ubuntu-ports/dists"
		BASE_IMAGE="linaro-vexpress/netboot"
		NETINSTALL="initrd.gz"
		;;
	precise-armel)
		TEST_MD5SUM=$PRECISE_ARMEL_MD5SUM
		NETIMAGE=$PRECISE_ARMEL_NETIMAGE
		HTTP_IMAGE="http://ports.ubuntu.com/ubuntu-ports/dists"
		BASE_IMAGE="linaro-vexpress/netboot"
		NETINSTALL="initrd.gz"
		;;
	precise-armhf)
		TEST_MD5SUM=$PRECISE_ARMHF_MD5SUM
		NETIMAGE=$PRECISE_ARMHF_NETIMAGE
		HTTP_IMAGE="http://ports.ubuntu.com/ubuntu-ports/dists"
		BASE_IMAGE="omap/netboot"
		UBOOTWRAPPER=1
		NETINSTALL="uInitrd"
		;;
	quantal-armhf)
		TEST_MD5SUM="${QUANTAL_ARMHF_MD5SUM}"
		NETIMAGE="${QUANTAL_ARMHF_NETIMAGE}"
		HTTP_IMAGE="http://ports.ubuntu.com/ubuntu-ports/dists"
		BASE_IMAGE="omap/netboot"
		UBOOTWRAPPER=1
		NETINSTALL="uInitrd"
		;;
	squeeze-armel)
		TEST_MD5SUM=$SQUEEZE_MD5SUM
		NETIMAGE=$SQUEEZE_NETIMAGE
		HTTP_IMAGE="http://ftp.debian.org/debian/dists"
		BASE_IMAGE="versatile/netboot"
		NETINSTALL="initrd.gz"
		;;
	wheezy-armel)
		TEST_MD5SUM=$WHEEZY_ARMEL_MD5SUM
		NETIMAGE=$WHEEZY_ARMEL_NETIMAGE
		HTTP_IMAGE="http://ftp.debian.org/debian/dists"
		BASE_IMAGE="versatile/netboot"
		NETINSTALL="initrd.gz"
		;;
	wheezy-armhf)
		TEST_MD5SUM="${WHEEZY_ARMHF_MD5SUM}"
		NETIMAGE="${WHEEZY_ARMHF_NETIMAGE}"
		HTTP_IMAGE="http://ftp.debian.org/debian/dists"
		BASE_IMAGE="mx5/netboot/efikamx"
		UBOOTWRAPPER=1
		NETINSTALL="uInitrd"
		;;
	esac

	if [ -f "${DIR}/dl/${DISTARCH}/${NETINSTALL}" ] ; then
		check_dl_netinstall
	else
		actually_dl_netinstall
	 fi
	echo "md5sum of NetInstall: ${MD5SUM}"
}

function boot_uenv_txt_template {
	if [ "${USE_UIMAGE}" ] ; then
		cat > ${TEMPDIR}/bootscripts/normal.cmd <<-__EOF__
			kernel_file=uImage
			initrd_file=uInitrd

		__EOF__

		cat > ${TEMPDIR}/bootscripts/netinstall.cmd <<-__EOF__
			kernel_file=uImage.net
			initrd_file=uInitrd.net

		__EOF__
	else
		cat > ${TEMPDIR}/bootscripts/normal.cmd <<-__EOF__
			kernel_file=zImage
			initrd_file=initrd.img

		__EOF__

		cat > ${TEMPDIR}/bootscripts/netinstall.cmd <<-__EOF__
			kernel_file=zImage.net
			initrd_file=initrd.net

		__EOF__
	fi

	if [ "${need_dtbs}" ] ; then
		cat >> ${TEMPDIR}/bootscripts/normal.cmd <<-__EOF__
			initrd_high=0xffffffff
			fdt_high=0xffffffff

		__EOF__

		cat >> ${TEMPDIR}/bootscripts/netinstall.cmd <<-__EOF__
			initrd_high=0xffffffff
			fdt_high=0xffffffff

		__EOF__
	fi

	if [ ! "${USE_KMS}" ] ; then
		cat >> ${TEMPDIR}/bootscripts/normal.cmd <<-__EOF__
			#Video: Uncomment to override U-Boots value:
			UENV_FB
			UENV_TIMING
			UENV_VRAM

		__EOF__

		cat >> ${TEMPDIR}/bootscripts/netinstall.cmd <<-__EOF__
			#Video: Uncomment to override U-Boots value:
			UENV_FB
			UENV_TIMING
			UENV_VRAM

		__EOF__
	fi

	cat >> ${TEMPDIR}/bootscripts/normal.cmd <<-__EOF__
		console=SERIAL_CONSOLE

		mmcroot=FINAL_PART ro
		mmcrootfstype=FINAL_FSTYPE rootwait fixrtc

		boot_fstype=${boot_fstype}
		xyz_load_image=\${boot_fstype}load mmc 0:1 ${kernel_addr} \${kernel_file}
		xyz_load_initrd=\${boot_fstype}load mmc 0:1 ${initrd_addr} \${initrd_file}; setenv initrd_size \${filesize}
		xyz_load_dtb=\${boot_fstype}load mmc 0:1 ${dtb_addr} /dtbs/\${dtb_file}

	__EOF__

	cat >> ${TEMPDIR}/bootscripts/netinstall.cmd <<-__EOF__
		console=DICONSOLE

		mmcroot=/dev/ram0 rw

		boot_fstype=${boot_fstype}
		xyz_load_image=\${boot_fstype}load mmc 0:1 ${kernel_addr} \${kernel_file}
		xyz_load_initrd=\${boot_fstype}load mmc 0:1 ${initrd_addr} \${initrd_file}; setenv initrd_size \${filesize}
		xyz_load_dtb=\${boot_fstype}load mmc 0:1 ${dtb_addr} /dtbs/\${dtb_file}

	__EOF__

	if [ ! "${need_dtbs}" ] ; then
		cat >> ${TEMPDIR}/bootscripts/normal.cmd <<-__EOF__
			xyz_mmcboot=run xyz_load_image; run xyz_load_initrd; echo Booting from mmc ...

		__EOF__

		cat >> ${TEMPDIR}/bootscripts/netinstall.cmd <<-__EOF__
			xyz_mmcboot=run xyz_load_image; run xyz_load_initrd; echo Booting from mmc ...

		__EOF__
	else
		cat >> ${TEMPDIR}/bootscripts/normal.cmd <<-__EOF__
			xyz_mmcboot=run xyz_load_image; run xyz_load_initrd; run xyz_load_dtb; echo Booting from mmc ...

		__EOF__

		cat >> ${TEMPDIR}/bootscripts/netinstall.cmd <<-__EOF__
			xyz_mmcboot=run xyz_load_image; run xyz_load_initrd; run xyz_load_dtb; echo Booting from mmc ...

		__EOF__
	fi

	cat >> ${TEMPDIR}/bootscripts/normal.cmd <<-__EOF__
		video_args=setenv video VIDEO_DISPLAY
		device_args=run video_args; run expansion_args; run mmcargs
		mmcargs=setenv bootargs console=\${console} \${optargs} \${video} root=\${mmcroot} rootfstype=\${mmcrootfstype} \${expansion}

	__EOF__

	cat >> ${TEMPDIR}/bootscripts/netinstall.cmd <<-__EOF__
		video_args=setenv video VIDEO_DISPLAY
		device_args=run video_args; run expansion_args; run mmcargs
		mmcargs=setenv bootargs console=\${console} \${optargs} \${video} root=\${mmcroot} \${expansion}

	__EOF__

	case "${SYSTEM}" in
	beagle_bx|beagle_cx)
		cat >> ${TEMPDIR}/bootscripts/normal.cmd <<-__EOF__
			optargs=VIDEO_CONSOLE
			expansion_args=setenv expansion buddy=\${buddy} buddy2=\${buddy2} musb_hdrc.fifo_mode=5
			loaduimage=run xyz_mmcboot; run device_args; ${boot} ${kernel_addr} ${initrd_addr}:\${initrd_size}

		__EOF__

		cat >> ${TEMPDIR}/bootscripts/netinstall.cmd <<-__EOF__
			expansion_args=setenv expansion buddy=\${buddy} buddy2=\${buddy2} musb_hdrc.fifo_mode=5
			loaduimage=run xyz_mmcboot; run device_args; ${boot} ${kernel_addr} ${initrd_addr}:\${initrd_size}
		__EOF__
		;;
	beagle_xm)
		cat >> ${TEMPDIR}/bootscripts/normal.cmd <<-__EOF__
			optargs=VIDEO_CONSOLE
			expansion_args=setenv expansion buddy=\${buddy} buddy2=\${buddy2}
			loaduimage=run xyz_mmcboot; run device_args; ${boot} ${kernel_addr} ${initrd_addr}:\${initrd_size}

		__EOF__

		cat >> ${TEMPDIR}/bootscripts/netinstall.cmd <<-__EOF__
			expansion_args=setenv expansion buddy=\${buddy} buddy2=\${buddy2}
			loaduimage=run xyz_mmcboot; run device_args; ${boot} ${kernel_addr} ${initrd_addr}:\${initrd_size}

		__EOF__
		;;
	crane|igepv2|mx51evk|mx53loco)
		cat >> ${TEMPDIR}/bootscripts/normal.cmd <<-__EOF__
			optargs=VIDEO_CONSOLE
			expansion_args=setenv expansion
			loaduimage=run xyz_mmcboot; run device_args; ${boot} ${kernel_addr} ${initrd_addr}:\${initrd_size}

		__EOF__

		cat >> ${TEMPDIR}/bootscripts/netinstall.cmd <<-__EOF__
			expansion_args=setenv expansion
			loaduimage=run xyz_mmcboot; run device_args; ${boot} ${kernel_addr} ${initrd_addr}:\${initrd_size}

		__EOF__
		;;
	panda|panda_es)
		cat >> ${TEMPDIR}/bootscripts/normal.cmd <<-__EOF__
			optargs=VIDEO_CONSOLE
			expansion_args=setenv expansion buddy=\${buddy} buddy2=\${buddy2}
			loaduimage=run xyz_mmcboot; run device_args; ${boot} ${kernel_addr} ${initrd_addr}:\${initrd_size}

		__EOF__

		cat >> ${TEMPDIR}/bootscripts/netinstall.cmd <<-__EOF__
			expansion_args=setenv expansion buddy=\${buddy} buddy2=\${buddy2}
			loaduimage=run xyz_mmcboot; run device_args; ${boot} ${kernel_addr} ${initrd_addr}:\${initrd_size}

		__EOF__
		;;
	mx51evk_dtb|mx53loco_dtb)
		cat >> ${TEMPDIR}/bootscripts/normal.cmd <<-__EOF__
			optargs=VIDEO_CONSOLE
			expansion_args=setenv expansion
			loaduimage=run xyz_mmcboot; run device_args; ${boot} ${kernel_addr} ${initrd_addr}:\${initrd_size} ${dtb_addr}

		__EOF__

		cat >> ${TEMPDIR}/bootscripts/netinstall.cmd <<-__EOF__
			expansion_args=setenv expansion
			loaduimage=run xyz_mmcboot; run device_args; ${boot} ${kernel_addr} ${initrd_addr}:\${initrd_size} ${dtb_addr}

		__EOF__
		;;
	bone)
		cat >> ${TEMPDIR}/bootscripts/normal.cmd <<-__EOF__
			expansion_args=setenv expansion ip=\${ip_method}
			mmc_load_uimage=run xyz_mmcboot; run bootargs_defaults; run device_args; ${boot} ${kernel_addr} ${initrd_addr}

		__EOF__

		cat >> ${TEMPDIR}/bootscripts/netinstall.cmd <<-__EOF__
			expansion_args=setenv expansion ip=\${ip_method}
			mmc_load_uimage=run xyz_mmcboot; run bootargs_defaults; run device_args; ${boot} ${kernel_addr} ${initrd_addr}

		__EOF__
		;;
	bone_zimage)
		cat >> ${TEMPDIR}/bootscripts/normal.cmd <<-__EOF__
			expansion_args=setenv expansion ip=\${ip_method}
			mmc_load_uimage=run xyz_mmcboot; run bootargs_defaults; run device_args; ${boot} ${kernel_addr} ${initrd_addr}
			loaduimage=run xyz_mmcboot; run device_args; ${boot} ${kernel_addr} ${initrd_addr}:\${initrd_size}

		__EOF__

		cat >> ${TEMPDIR}/bootscripts/netinstall.cmd <<-__EOF__
			expansion_args=setenv expansion ip=\${ip_method}
			mmc_load_uimage=run xyz_mmcboot; run bootargs_defaults; run device_args; ${boot} ${kernel_addr} ${initrd_addr}
			loaduimage=run xyz_mmcboot; run device_args; ${boot} ${kernel_addr} ${initrd_addr}:\${initrd_size}

		__EOF__
		;;
	mx6qsabrelite)
		cat >> ${TEMPDIR}/bootscripts/normal.cmd <<-__EOF__
			optargs=VIDEO_CONSOLE
			expansion_args=setenv expansion
			loaduimage=run xyz_mmcboot; run device_args; ${boot} ${kernel_addr} ${initrd_addr}:\${initrd_size} ${dtb_addr}

		__EOF__

		cat >> ${TEMPDIR}/bootscripts/netinstall.cmd <<-__EOF__
			expansion_args=setenv expansion
			loaduimage=run xyz_mmcboot; run device_args; ${boot} ${kernel_addr} ${initrd_addr}:\${initrd_size} ${dtb_addr}

		__EOF__
		;;
	esac
}

function tweak_boot_scripts {
	unset KMS_OVERRIDE

	if [ "x${ADDON}" == "xpico" ] ; then
		VIDEO_TIMING="640x480MR-16@60"
		KMS_OVERRIDE=1
		KMS_VIDEOA="video=DVI-D-1"
		KMS_VIDEO_RESOLUTION="640x480"
	fi

	if [ "${SVIDEO_NTSC}" ] ; then
		VIDEO_TIMING="ntsc"
		VIDEO_OMAPFB_MODE="tv"
		##FIXME need to figure out KMS Options
	fi

	if [ "${SVIDEO_PAL}" ] ; then
		VIDEO_TIMING="pal"
		VIDEO_OMAPFB_MODE="tv"
		##FIXME need to figure out KMS Options
	fi

	ALL="*.cmd"
	NET="netinstall.cmd"
	FINAL="normal.cmd"
	#Set the Serial Console
	sed -i -e 's:SERIAL_CONSOLE:'$SERIAL_CONSOLE':g' ${TEMPDIR}/bootscripts/${ALL}

	if [ "${HAS_OMAPFB_DSS2}" ] && [ ! "${SERIAL_MODE}" ] ; then
		#UENV_VRAM -> vram=12MB
		sed -i -e 's:UENV_VRAM:#vram=VIDEO_OMAP_RAM:g' ${TEMPDIR}/bootscripts/${ALL}
		sed -i -e 's:VIDEO_OMAP_RAM:'$VIDEO_OMAP_RAM':g' ${TEMPDIR}/bootscripts/${ALL}

		#UENV_FB -> defaultdisplay=dvi
		sed -i -e 's:UENV_FB:#defaultdisplay=VIDEO_OMAPFB_MODE:g' ${TEMPDIR}/bootscripts/${ALL}
		sed -i -e 's:VIDEO_OMAPFB_MODE:'$VIDEO_OMAPFB_MODE':g' ${TEMPDIR}/bootscripts/${ALL}

		#UENV_TIMING -> dvimode=1280x720MR-16@60
		if [ "x${ADDON}" == "xpico" ] ; then
			sed -i -e 's:UENV_TIMING:dvimode=VIDEO_TIMING:g' ${TEMPDIR}/bootscripts/${ALL}
		else
			sed -i -e 's:UENV_TIMING:#dvimode=VIDEO_TIMING:g' ${TEMPDIR}/bootscripts/${ALL}
		fi
		sed -i -e 's:VIDEO_TIMING:'$VIDEO_TIMING':g' ${TEMPDIR}/bootscripts/${ALL}

		#optargs=VIDEO_CONSOLE -> optargs=console=tty0
		sed -i -e 's:VIDEO_CONSOLE:console=tty0:g' ${TEMPDIR}/bootscripts/${ALL}

		#Setting up:
		#vram=\${vram} omapfb.mode=\${defaultdisplay}:\${dvimode} omapdss.def_disp=\${defaultdisplay}
		sed -i -e 's:VIDEO_DISPLAY:TMP_VRAM TMP_OMAPFB TMP_OMAPDSS:g' ${TEMPDIR}/bootscripts/${ALL}
		sed -i -e 's:TMP_VRAM:'vram=\${vram}':g' ${TEMPDIR}/bootscripts/${ALL}
		sed -i -e 's/TMP_OMAPFB/'omapfb.mode=\${defaultdisplay}:\${dvimode}'/g' ${TEMPDIR}/bootscripts/${ALL}
		sed -i -e 's:TMP_OMAPDSS:'omapdss.def_disp=\${defaultdisplay}':g' ${TEMPDIR}/bootscripts/${ALL}

		#Debian Installer console
		sed -i -e 's:DICONSOLE:tty0:g' ${TEMPDIR}/bootscripts/${NET}
	fi

	if [ "${HAS_IMX_BLOB}" ] && [ ! "${SERIAL_MODE}" ] ; then
		#not used:
		sed -i -e 's:UENV_VRAM::g' ${TEMPDIR}/bootscripts/${ALL}

		#framebuffer=VIDEO_FB
		sed -i -e 's:UENV_FB:framebuffer=VIDEO_FB:g' ${TEMPDIR}/bootscripts/${ALL}
		sed -i -e 's:VIDEO_FB:'$VIDEO_FB':g' ${TEMPDIR}/bootscripts/${ALL}

		#dvimode=VIDEO_TIMING
		sed -i -e 's:UENV_TIMING:dvimode=VIDEO_TIMING:g' ${TEMPDIR}/bootscripts/${ALL}
		sed -i -e 's:VIDEO_TIMING:'$VIDEO_TIMING':g' ${TEMPDIR}/bootscripts/${ALL}

		#optargs=VIDEO_CONSOLE -> optargs=console=tty0
		sed -i -e 's:VIDEO_CONSOLE:console=tty0:g' ${TEMPDIR}/bootscripts/${ALL}

		#video=\${framebuffer}:${dvimode}
		sed -i -e 's/VIDEO_DISPLAY/'video=\${framebuffer}:\${dvimode}'/g' ${TEMPDIR}/bootscripts/${ALL}

		#Debian Installer console
		sed -i -e 's:DICONSOLE:tty0:g' ${TEMPDIR}/bootscripts/${NET}
	fi

	if [ "${USE_KMS}" ] && [ ! "${SERIAL_MODE}" ] ; then
		#optargs=VIDEO_CONSOLE
		sed -i -e 's:VIDEO_CONSOLE:console=tty0:g' ${TEMPDIR}/bootscripts/${ALL}

		if [ "${KMS_OVERRIDE}" ] ; then
			sed -i -e 's/VIDEO_DISPLAY/'${KMS_VIDEOA}:${KMS_VIDEO_RESOLUTION}'/g' ${TEMPDIR}/bootscripts/${ALL}
		else
			sed -i -e 's:VIDEO_DISPLAY ::g' ${TEMPDIR}/bootscripts/${ALL}
		fi

		#Debian Installer console
		sed -i -e 's:DICONSOLE:tty0:g' ${TEMPDIR}/bootscripts/${NET}
	fi

	if [ "${SERIAL_MODE}" ] ; then
		echo "NetInstall: Setting up to use Serial Port: [${SERIAL}]"
		#In pure serial mode, remove all traces of VIDEO
		if [ ! "${USE_KMS}" ] ; then
			sed -i -e 's:UENV_VRAM::g' ${TEMPDIR}/bootscripts/${NET}
			sed -i -e 's:UENV_FB::g' ${TEMPDIR}/bootscripts/${NET}
			sed -i -e 's:UENV_TIMING::g' ${TEMPDIR}/bootscripts/${NET}
		fi
		sed -i -e 's:VIDEO_DISPLAY ::g' ${TEMPDIR}/bootscripts/${NET}

		#Debian Installer console
		sed -i -e 's:DICONSOLE:'$SERIAL_CONSOLE':g' ${TEMPDIR}/bootscripts/${NET}

		#Unlike the debian-installer, normal boot will boot fine with the display enabled...
		if [ "${HAS_OMAPFB_DSS2}" ] ; then
			#UENV_VRAM -> vram=12MB
			sed -i -e 's:UENV_VRAM:#vram=VIDEO_OMAP_RAM:g' ${TEMPDIR}/bootscripts/${FINAL}
			sed -i -e 's:VIDEO_OMAP_RAM:'$VIDEO_OMAP_RAM':g' ${TEMPDIR}/bootscripts/${FINAL}

			#UENV_FB -> defaultdisplay=dvi
			sed -i -e 's:UENV_FB:#defaultdisplay=VIDEO_OMAPFB_MODE:g' ${TEMPDIR}/bootscripts/${FINAL}
			sed -i -e 's:VIDEO_OMAPFB_MODE:'$VIDEO_OMAPFB_MODE':g' ${TEMPDIR}/bootscripts/${FINAL}

			#UENV_TIMING -> dvimode=1280x720MR-16@60
			sed -i -e 's:UENV_TIMING:#dvimode=VIDEO_TIMING:g' ${TEMPDIR}/bootscripts/${FINAL}
			sed -i -e 's:VIDEO_TIMING:'$VIDEO_TIMING':g' ${TEMPDIR}/bootscripts/${FINAL}

			#optargs=VIDEO_CONSOLE -> optargs=console=tty0
			sed -i -e 's:VIDEO_CONSOLE:console=tty0:g' ${TEMPDIR}/bootscripts/${FINAL}

			#Setting up:
			#vram=\${vram} omapfb.mode=\${defaultdisplay}:\${dvimode} omapdss.def_disp=\${defaultdisplay}
			sed -i -e 's:VIDEO_DISPLAY:TMP_VRAM TMP_OMAPFB TMP_OMAPDSS:g' ${TEMPDIR}/bootscripts/${FINAL}
			sed -i -e 's:TMP_VRAM:'vram=\${vram}':g' ${TEMPDIR}/bootscripts/${FINAL}
			sed -i -e 's/TMP_OMAPFB/'omapfb.mode=\${defaultdisplay}:\${dvimode}'/g' ${TEMPDIR}/bootscripts/${FINAL}
			sed -i -e 's:TMP_OMAPDSS:'omapdss.def_disp=\${defaultdisplay}':g' ${TEMPDIR}/bootscripts/${FINAL}
		fi

		if [ "${HAS_IMX_BLOB}" ] ; then
			#not used:
			sed -i -e 's:UENV_VRAM::g' ${TEMPDIR}/bootscripts/${FINAL}

			#framebuffer=VIDEO_FB
			sed -i -e 's:UENV_FB:framebuffer=VIDEO_FB:g' ${TEMPDIR}/bootscripts/${FINAL}
			sed -i -e 's:VIDEO_FB:'$VIDEO_FB':g' ${TEMPDIR}/bootscripts/${FINAL}

			#dvimode=VIDEO_TIMING
			sed -i -e 's:UENV_TIMING:dvimode=VIDEO_TIMING:g' ${TEMPDIR}/bootscripts/${FINAL}
			sed -i -e 's:VIDEO_TIMING:'$VIDEO_TIMING':g' ${TEMPDIR}/bootscripts/${FINAL}

			#optargs=VIDEO_CONSOLE -> optargs=console=tty0
			sed -i -e 's:VIDEO_CONSOLE:console=tty0:g' ${TEMPDIR}/bootscripts/${FINAL}

			#video=\${framebuffer}:${dvimode}
			sed -i -e 's/VIDEO_DISPLAY/'video=\${framebuffer}:\${dvimode}'/g' ${TEMPDIR}/bootscripts/${FINAL}
		fi

		if [ "${USE_KMS}" ] ; then
			#optargs=VIDEO_CONSOLE
			sed -i -e 's:VIDEO_CONSOLE:console=tty0:g' ${TEMPDIR}/bootscripts/${FINAL}

			if [ "${KMS_OVERRIDE}" ] ; then
				sed -i -e 's/VIDEO_DISPLAY/'${KMS_VIDEOA}:${KMS_VIDEO_RESOLUTION}'/g' ${TEMPDIR}/bootscripts/${FINAL}
			else
				sed -i -e 's:VIDEO_DISPLAY ::g' ${TEMPDIR}/bootscripts/${FINAL}
			fi
		fi
	fi
}

function setup_bootscripts {
	mkdir -p ${TEMPDIR}/bootscripts/
	boot_uenv_txt_template
	tweak_boot_scripts
}

function extract_base_initrd {
	echo "NetInstall: Extracting Base ${NETINSTALL}"
	cd ${TEMPDIR}/initrd-tree
	zcat "${DIR}/dl/${DISTARCH}/${NETINSTALL}" | cpio -i -d
	dpkg -x "${DIR}/dl/${DISTARCH}/${ACTUAL_DEB_FILE}" ${TEMPDIR}/initrd-tree
	cd "${DIR}/"
}

function dl_linux_firmware {
	echo ""
	echo "Clone/Pulling linux-firmware.git"
	echo "-----------------------------"
	if [ ! -f "${DIR}/dl/linux-firmware/.git/config" ] ; then
		cd "${DIR}/dl/"
		if [ -d "${DIR}/dl/linux-firmware/" ] ; then
			rm -rf "${DIR}/dl/linux-firmware/" || true
		fi
		git clone git://git.kernel.org/pub/scm/linux/kernel/git/firmware/linux-firmware.git
	else
		cd "${DIR}/dl/linux-firmware"
		git pull
	fi
	cd "${DIR}/"
}

function dl_am335_firmware {
	echo ""
	echo "Clone/Pulling am33x-cm3.git"
	echo "-----------------------------"
	if [ ! -f "${DIR}/dl/am33x-cm3/.git/config" ] ; then
		cd "${DIR}/dl/"
		if [ -d "${DIR}/dl/am33x-cm3/" ] ; then
			rm -rf "${DIR}/dl/am33x-cm3/" || true
		fi
		git clone git://arago-project.org/git/projects/am33x-cm3.git
	else
		cd "${DIR}/dl/am33x-cm3"
		git pull
	fi
	cd "${DIR}/"
}

function dl_device_firmware {
	mkdir -p ${TEMPDIR}/firmware/
	DL_WGET="wget --directory-prefix=${TEMPDIR}/firmware/"
	case "${SYSTEM}" in
	beagle_xm|panda|panda_es)
		dl_linux_firmware
		echo "-----------------------------"
		echo "Adding Firmware for onboard WiFi/Bluetooth module"
		echo "-----------------------------"
		cp -r "${DIR}/dl/linux-firmware/ti-connectivity" ${TEMPDIR}/firmware/
		${DL_WGET}ti-connectivity/ http://rcn-ee.net/firmware/ti/TIInit_7.6.15.bts
		;;
	bone|bone_zimage)
		dl_am335_firmware
		echo "-----------------------------"
		echo "Adding pre-built Firmware for am335x powermanagment"
		echo "SRC: http://arago-project.org/git/projects/?p=am33x-cm3.git;a=summary"
		echo "-----------------------------"
		cp -v "${DIR}/dl/am33x-cm3/bin/am335x-pm-firmware.bin" ${TEMPDIR}/firmware/
		;;
	esac
}

function initrd_add_firmware {
	DL_WGET="wget --directory-prefix=${TEMPDIR}/firmware/"
	echo ""
	echo "NetInstall: Adding Firmware"
	echo "-----------------------------"
	echo "Adding: OpenSource Firmware"
	echo "-----------------------------"
	${DL_WGET} http://rcn-ee.net/firmware/carl9170/1.9.4/carl9170-1.fw
	cp ${TEMPDIR}/firmware/carl9170-1.fw ${TEMPDIR}/initrd-tree/lib/firmware/
	echo "-----------------------------"

	echo "Adding: Firmware from linux-firmware.git"
	echo "-----------------------------"
	dl_linux_firmware
	#Driver: ath3k - DFU Driver for Atheros bluetooth chipset AR3011
	cp "${DIR}"/dl/linux-firmware/ath3k-1.fw ${TEMPDIR}/initrd-tree/lib/firmware/
	#Driver: Atheros AR300x UART HCI Bluetooth
	cp -r "${DIR}/dl/linux-firmware/ar3k/" ${TEMPDIR}/initrd-tree/lib/firmware/
	#Libertas
	cp -r "${DIR}/dl/linux-firmware/libertas/" ${TEMPDIR}/initrd-tree/lib/firmware/
	#Ralink
	cp -r "${DIR}"/dl/linux-firmware/rt*.bin ${TEMPDIR}/initrd-tree/lib/firmware/
	#Realtek
	cp -r "${DIR}/dl/linux-firmware/rtlwifi/" ${TEMPDIR}/initrd-tree/lib/firmware/
	echo "-----------------------------"

	echo "Adding: NonFree Firmwares"
	echo "-----------------------------"
	${DL_WGET} http://rcn-ee.net/firmware/atmel-firmware/atmel-firmware_1.3-4_all.deb
	dpkg -x ${TEMPDIR}/firmware/atmel-firmware_1.3-4_all.deb ${TEMPDIR}/initrd-tree

	${DL_WGET} http://rcn-ee.net/firmware/zd1211-firmware/zd1211-firmware_2.21.0.0-1_all.deb
	dpkg -x ${TEMPDIR}/firmware/zd1211-firmware_2.21.0.0-1_all.deb ${TEMPDIR}/initrd-tree

	echo "-----------------------------"
}

function initrd_cleanup {
	echo "NetInstall: Removing Optional Stuff to Save RAM Space"
	#Cleanup some of the extra space..
	rm -f ${TEMPDIR}/initrd-tree/boot/*-${KERNEL} || true
	rm -rf ${TEMPDIR}/initrd-tree/lib/modules/${KERNEL}/kernel/drivers/media/ || true
	rm -rf ${TEMPDIR}/initrd-tree/lib/modules/${KERNEL}/kernel/drivers/usb/serial/ || true

	rm -rf ${TEMPDIR}/initrd-tree/lib/modules/${KERNEL}/kernel/drivers/net/bluetooth/ || true
	rm -rf ${TEMPDIR}/initrd-tree/lib/modules/${KERNEL}/kernel/drivers/net/irda/ || true
	rm -rf ${TEMPDIR}/initrd-tree/lib/modules/${KERNEL}/kernel/drivers/net/hamradio/ || true
	rm -rf ${TEMPDIR}/initrd-tree/lib/modules/${KERNEL}/kernel/drivers/net/can/ || true

	rm -rf ${TEMPDIR}/initrd-tree/lib/modules/${KERNEL}/kernel/net/irda/ || true
	rm -rf ${TEMPDIR}/initrd-tree/lib/modules/${KERNEL}/kernel/net/decnet/ || true

	rm -rf ${TEMPDIR}/initrd-tree/lib/modules/${KERNEL}/kernel/fs/ || true
	rm -rf ${TEMPDIR}/initrd-tree/lib/modules/${KERNEL}/kernel/sound/ || true
	rm -rf ${TEMPDIR}/initrd-tree/lib/modules/*-versatile/ || true
	rm -rf ${TEMPDIR}/initrd-tree/lib/modules/*-omap || true
	rm -rf ${TEMPDIR}/initrd-tree/lib/firmware/*-versatile/ || true
}

function initrd_preseed_settings {
	echo "NetInstall: Adding Distro Tweaks and Preseed Configuration"
	cd ${TEMPDIR}/initrd-tree/
	case "${DIST}" in
	maverick|natty|oneiric|precise|quantal)
		patch -p1 < "${DIR}/scripts/ubuntu-tweaks.diff"
		cp -v "${DIR}/scripts/ubuntu-finish.sh" ${TEMPDIR}/initrd-tree/etc/finish-install.sh
		;;
	squeeze|wheezy)
		patch -p1 < "${DIR}/scripts/debian-tweaks.diff"
		cp -v "${DIR}/scripts/debian-finish.sh" ${TEMPDIR}/initrd-tree/etc/finish-install.sh
		;;
	esac

	chmod a+x ${TEMPDIR}/initrd-tree/usr/lib/finish-install.d/08rcn-ee-finish-installing-device
	cp -v "${DIR}/scripts/${DIST}-preseed.cfg" ${TEMPDIR}/initrd-tree/preseed.cfg

	if [ "${SERIAL_MODE}" ] ; then
		#Squeeze/Wheezy: keymaps aren't an issue with serial mode so disable preseed workaround:
		sed -i -e 's:d-i console-tools:#d-i console-tools:g' ${TEMPDIR}/initrd-tree/preseed.cfg
		sed -i -e 's:d-i debian-installer:#d-i debian-installer:g' ${TEMPDIR}/initrd-tree/preseed.cfg
		sed -i -e 's:d-i console-keymaps-at:#d-i console-keymaps-at:g' ${TEMPDIR}/initrd-tree/preseed.cfg
	fi

	cd "${DIR}"/
}

function initrd_fixes {
	echo "NetInstall: Adding Device Tweaks"
	touch ${TEMPDIR}/initrd-tree/etc/rcn.conf

	#work around for the kevent smsc95xx issue
	touch ${TEMPDIR}/initrd-tree/etc/sysctl.conf
	if [ "${smsc95xx_mem}" ] ; then
		echo "vm.min_free_kbytes = ${smsc95xx_mem}" >> ${TEMPDIR}/initrd-tree/etc/sysctl.conf
	fi
}

function recompress_initrd {
	echo "NetInstall: Compressing initrd image"
	cd ${TEMPDIR}/initrd-tree/
	find . | cpio -o -H newc | gzip -9 > ${TEMPDIR}/initrd.mod.gz
	cd "${DIR}/"
}

function extract_zimage {
	echo "NetInstall: Extracting Kernel Boot Image"
	dpkg -x "${DIR}/dl/${DISTARCH}/${ACTUAL_DEB_FILE}" ${TEMPDIR}/kernel
}

function create_custom_netinstall_image {
	echo ""
	echo "NetInstall: Creating Custom Image"
	echo "-----------------------------"
	mkdir -p ${TEMPDIR}/kernel
	mkdir -p ${TEMPDIR}/initrd-tree/lib/firmware/

	extract_base_initrd

	#Copy Device Firmware
	cp -r ${TEMPDIR}/firmware/ ${TEMPDIR}/initrd-tree/lib/

	if [ "${FIRMWARE}" ] ; then
		initrd_add_firmware
	fi

	initrd_cleanup
	initrd_preseed_settings
	initrd_fixes
	recompress_initrd
	extract_zimage
}

function drive_error_ro {
	echo "-----------------------------"
	echo "Error: for some reason your SD card is not writable..."
	echo "Check: is the write protect lever set the locked position?"
	echo "Check: do you have another SD card reader?"
	echo "-----------------------------"
	echo "Script gave up..."

	exit
}

function unmount_all_drive_partitions {
	echo ""
	echo "Unmounting Partitions"
	echo "-----------------------------"

	NUM_MOUNTS=$(mount | grep -v none | grep "$MMC" | wc -l)

	for (( c=1; c<=$NUM_MOUNTS; c++ ))
	do
		DRIVE=$(mount | grep -v none | grep "$MMC" | tail -1 | awk '{print $1}')
		umount ${DRIVE} &> /dev/null || true
	done

	LC_ALL=C parted --script ${MMC} mklabel msdos | grep "Error:" && drive_error_ro
}

function omap_fatfs_boot_part {
	echo ""
	echo "Using fdisk to create an omap compatible fatfs BOOT partition"
	echo "-----------------------------"

	fdisk ${MMC} <<-__EOF__
		n
		p
		1

		+64M
		t
		e
		p
		w
	__EOF__

	sync

	echo "Setting Boot Partition's Boot Flag"
	echo "-----------------------------"
	parted --script ${MMC} set 1 boot on
}

function dd_to_drive {
	echo ""
	echo "Using dd to place bootloader on drive"
	echo "-----------------------------"
	dd if=${TEMPDIR}/dl/${UBOOT} of=${MMC} seek=${dd_seek} bs=${dd_bs}
	bootloader_installed=1

	echo "Using parted to create BOOT Partition"
	echo "-----------------------------"
	if [ "x${boot_fstype}" == "xfat" ] ; then
		parted --script ${PARTED_ALIGN} ${MMC} mkpart primary fat16 ${boot_startmb} ${boot_endmb}
	else
		parted --script ${PARTED_ALIGN} ${MMC} mkpart primary ext2 ${boot_startmb} ${boot_endmb}
	fi
}

function no_boot_on_drive {
	echo "Using parted to create BOOT Partition"
	echo "-----------------------------"
	if [ "x${boot_fstype}" == "xfat" ] ; then
		parted --script ${PARTED_ALIGN} ${MMC} mkpart primary fat16 ${boot_startmb} ${boot_endmb}
	else
		parted --script ${PARTED_ALIGN} ${MMC} mkpart primary ext2 ${boot_startmb} ${boot_endmb}
	fi
}

function format_boot_partition {
	echo "Formating Boot Partition"
	echo "-----------------------------"
	if [ "x${boot_fstype}" == "xfat" ] ; then
		boot_part_format="vfat"
		mkfs.vfat -F 16 ${MMC}${PARTITION_PREFIX}1 -n ${BOOT_LABEL}
	else
		boot_part_format="ext2"
		mkfs.ext2 ${MMC}${PARTITION_PREFIX}1 -L ${BOOT_LABEL}
	fi
}

function create_partitions {
	unset bootloader_installed
	case "${bootloader_location}" in
	omap_fatfs_boot_part)
		omap_fatfs_boot_part
		;;
	dd_to_drive)
		let boot_endmb=${boot_startmb}+${boot_partition_size}
		dd_to_drive
		;;
	*)
		let boot_endmb=${boot_startmb}+${boot_partition_size}
		no_boot_on_drive
		;;
	esac
	format_boot_partition
}

function populate_boot {
	echo "Populating Boot Partition"
	echo "-----------------------------"

	if [ ! -d ${TEMPDIR}/disk ] ; then
		mkdir -p ${TEMPDIR}/disk
	fi

	if mount -t ${boot_part_format} ${MMC}${PARTITION_PREFIX}1 ${TEMPDIR}/disk; then
		mkdir -p ${TEMPDIR}/disk/backup
		mkdir -p ${TEMPDIR}/disk/dtbs

		if [ ! "${bootloader_installed}" ] ; then
			if [ "${spl_name}" ] ; then
				if [ -f ${TEMPDIR}/dl/${MLO} ] ; then
					cp -v ${TEMPDIR}/dl/${MLO} ${TEMPDIR}/disk/${spl_name}
					cp -v ${TEMPDIR}/dl/${MLO} ${TEMPDIR}/disk/backup/${spl_name}
					echo "-----------------------------"
				fi
			fi

			if [ "${boot_name}" ] && [ ! "${IS_IMX}" ] ; then
				if [ -f ${TEMPDIR}/dl/${UBOOT} ] ; then
					cp -v ${TEMPDIR}/dl/${UBOOT} ${TEMPDIR}/disk/${boot_name}
				fi
			fi

			if [ "${boot_name}" ] ; then
				if [ -f ${TEMPDIR}/dl/${UBOOT} ] ; then
					cp -v ${TEMPDIR}/dl/${UBOOT} ${TEMPDIR}/disk/backup/${boot_name}
					echo "-----------------------------"
				fi
			fi
		fi

		VMLINUZ="vmlinuz-*"
		UIMAGE="uImage.net"
		if [ -f ${TEMPDIR}/kernel/boot/${VMLINUZ} ] ; then
			LINUX_VER=$(ls ${TEMPDIR}/kernel/boot/${VMLINUZ} | awk -F'vmlinuz-' '{print $2}')
			if [ "${USE_UIMAGE}" ] ; then
				echo "Using mkimage to create uImage"
				mkimage -A arm -O linux -T kernel -C none -a ${load_addr} -e ${load_addr} -n ${LINUX_VER} -d ${TEMPDIR}/kernel/boot/${VMLINUZ} ${TEMPDIR}/disk/${UIMAGE}
				echo "-----------------------------"
			else
				echo "Copying Kernel image:"
				cp -v ${TEMPDIR}/kernel/boot/${VMLINUZ} ${TEMPDIR}/disk/zImage.net
				echo "-----------------------------"
			fi
		fi

		INITRD="initrd.mod.gz"
		UINITRD="uInitrd.net"
		if [ -f ${TEMPDIR}/${INITRD} ] ; then
			if [ "${USE_UIMAGE}" ] ; then
				echo "Using mkimage to create uInitrd"
				mkimage -A arm -O linux -T ramdisk -C none -a 0 -e 0 -n initramfs -d ${TEMPDIR}/${INITRD} ${TEMPDIR}/disk/${UINITRD}
				echo "-----------------------------"
			else
				echo "Copying Kernel initrd:"
				cp -v ${TEMPDIR}/${INITRD} ${TEMPDIR}/disk/initrd.net
				echo "-----------------------------"
			fi
		fi

		if [ "${need_dtbs}" ] ; then
			echo "Copying Device Tree Files:"
			if [ "x${boot_fstype}" == "xfat" ] ; then
				tar xfvo "${DIR}/dl/${DISTARCH}/${ACTUAL_DTB_FILE}" -C ${TEMPDIR}/disk/dtbs
			else
				tar xfv "${DIR}/dl/${DISTARCH}/${ACTUAL_DTB_FILE}" -C ${TEMPDIR}/disk/dtbs
			fi
			echo "-----------------------------"
		fi

		if [ "${boot_scr_wrapper}" ] ; then
			cat > ${TEMPDIR}/bootscripts/loader.cmd <<-__EOF__
				echo "boot.scr -> uEnv.txt wrapper..."
				setenv boot_fstype ${boot_fstype}
				\${boot_fstype}load mmc \${mmcdev}:\${mmcpart} \${loadaddr} uEnv.txt
				env import -t \${loadaddr} \${filesize}
				run loaduimage
			__EOF__
			mkimage -A arm -O linux -T script -C none -a 0 -e 0 -n "wrapper" -d ${TEMPDIR}/bootscripts/loader.cmd ${TEMPDIR}/disk/boot.scr
			cp -v ${TEMPDIR}/disk/boot.scr ${TEMPDIR}/disk/backup/boot.scr
		fi

		echo "Copying uEnv.txt based boot scripts to Boot Partition"
		echo "Net Install Boot Script:"
		cp -v ${TEMPDIR}/bootscripts/netinstall.cmd ${TEMPDIR}/disk/uEnv.txt
		echo "-----------------------------"
		cat ${TEMPDIR}/bootscripts/netinstall.cmd
		rm -rf ${TEMPDIR}/bootscripts/netinstall.cmd || true
		echo "-----------------------------"
		echo "Normal Boot Script:"
		cp -v ${TEMPDIR}/bootscripts/normal.cmd ${TEMPDIR}/disk/backup/normal.txt
		echo "-----------------------------"
		cat ${TEMPDIR}/bootscripts/normal.cmd
		rm -rf ${TEMPDIR}/bootscripts/normal.cmd || true
		echo "-----------------------------"

		cp -v "${DIR}/dl/${DISTARCH}/${ACTUAL_DEB_FILE}" ${TEMPDIR}/disk/

		#This should be compatible with hwpacks variable names..
		#https://code.launchpad.net/~linaro-maintainers/linaro-images/
		cat > ${TEMPDIR}/disk/SOC.sh <<-__EOF__
			#!/bin/sh
			format=1.0
			board=${BOOTLOADER}
			bootloader_location=${bootloader_location}
			dd_seek=${dd_seek}
			dd_bs=${dd_bs}

			boot_image=${boot}
			boot_script=${boot_script}
			boot_fstype=${boot_fstype}

			serial_tty=${SERIAL}
			kernel_addr=${kernel_addr}
			initrd_addr=${initrd_addr}
			load_addr=${load_addr}
			dtb_addr=${dtb_addr}
			dtb_file=${dtb_file}

			smsc95xx_mem=${smsc95xx_mem}

		__EOF__

		echo "Debug:"
		cat ${TEMPDIR}/disk/SOC.sh

		echo "Debug: Adding Useful scripts from: https://github.com/RobertCNelson/tools"
		echo "-----------------------------"
		mkdir -p ${TEMPDIR}/disk/tools
		git clone git://github.com/RobertCNelson/tools.git ${TEMPDIR}/disk/tools
		echo "-----------------------------"

		cd ${TEMPDIR}/disk
		sync
		cd "${DIR}"/

		echo "Debug: Contents of Boot Partition"
		echo "-----------------------------"
		ls -lh ${TEMPDIR}/disk/
		echo "-----------------------------"

		umount ${TEMPDIR}/disk || true

		echo "Finished populating Boot Partition"
		echo "-----------------------------"
	else
		echo "-----------------------------"
		echo "Unable to mount ${MMC}${PARTITION_PREFIX}1 at ${TEMPDIR}/disk to complete populating Boot Partition"
		echo "Please retry running the script, sometimes rebooting your system helps."
		echo "-----------------------------"
		exit
	fi
	echo "mk_mmc.sh script complete"
	echo "Script Version git: ${GIT_VERSION}"
	echo "-----------------------------"
}

function check_mmc {
	FDISK=$(LC_ALL=C fdisk -l 2>/dev/null | grep "Disk ${MMC}" | awk '{print $2}')

	if [ "x${FDISK}" = "x${MMC}:" ] ; then
		echo ""
		echo "I see..."
		echo "fdisk -l:"
		LC_ALL=C fdisk -l 2>/dev/null | grep "Disk /dev/" --color=never
		echo ""
		echo "mount:"
		mount | grep -v none | grep "/dev/" --color=never
		echo ""
		read -p "Are you 100% sure, on selecting [${MMC}] (y/n)? "
		[ "${REPLY}" == "y" ] || exit
		echo ""
	else
		echo ""
		echo "Are you sure? I Don't see [${MMC}], here is what I do see..."
		echo ""
		echo "fdisk -l:"
		LC_ALL=C fdisk -l 2>/dev/null | grep "Disk /dev/" --color=never
		echo ""
		echo "mount:"
		mount | grep -v none | grep "/dev/" --color=never
		echo ""
		exit
	fi
}

function is_omap {
	IS_OMAP=1

	bootloader_location="omap_fatfs_boot_part"
	spl_name="MLO"
	boot_name="u-boot.img"

	SUBARCH="omap"

	kernel_addr="0x80300000"
	initrd_addr="0x81600000"
	load_addr="0x80008000"
	dtb_addr="0x815f0000"
	boot_script="uEnv.txt"

	boot_fstype="fat"

	SERIAL="ttyO2"
	SERIAL_CONSOLE="${SERIAL},115200n8"

	VIDEO_CONSOLE="console=tty0"

	#Older DSS2 omapfb framebuffer driver:
	HAS_OMAPFB_DSS2=1
	VIDEO_DRV="omapfb.mode=dvi"
	VIDEO_OMAP_RAM="12MB"
	VIDEO_OMAPFB_MODE="dvi"
	VIDEO_TIMING="1280x720MR-16@60"

	#KMS Video Options (overrides when edid fails)
	# From: ls /sys/class/drm/
	# Unknown-1 might be s-video..
	KMS_VIDEO_RESOLUTION="1280x720"
	KMS_VIDEOA="video=DVI-D-1"
	unset KMS_VIDEOB
}

function is_imx {
	IS_IMX=1

	bootloader_location="dd_to_drive"
	unset spl_name
	boot_name="u-boot.imx"
	dd_seek="1"
	dd_bs="1024"
	boot_startmb="2"

	SUBARCH="imx"

	SERIAL="ttymxc0"
	SERIAL_CONSOLE="${SERIAL},115200"

	boot_script="uEnv.txt"

	boot_fstype="ext2"

	VIDEO_CONSOLE="console=tty0"
	HAS_IMX_BLOB=1
	VIDEO_FB="mxcdi1fb"
	VIDEO_TIMING="RGB24,1280x720M@60"
}

function check_uboot_type {
	unset IN_VALID_UBOOT
	unset USE_UIMAGE
	unset USE_KMS
	unset dtb_file

	unset bootloader_location
	unset spl_name
	unset boot_name
	unset need_dtbs
	KERNEL_SEL="STABLE"
	boot="bootz"
	unset boot_scr_wrapper
	unset smsc95xx_mem
	unset dd_seek
	unset dd_bs
	boot_partition_size="50"

	case "${UBOOT_TYPE}" in
	beagle_bx)
		SYSTEM="beagle_bx"
		BOOTLOADER="BEAGLEBOARD_BX"
		is_omap
		#dtb_file="omap3-beagle.dtb"
		echo "-----------------------------"
		echo "Warning: Support for the Original BeagleBoard Ax/Bx is broken.. (board locks up during hardware detect)"
		echo "Please use the Demo Images Instead"
		echo "-----------------------------"
		;;
	beagle_cx)
		SYSTEM="beagle_cx"
		BOOTLOADER="BEAGLEBOARD_CX"
		is_omap
		#dtb_file="omap3-beagle.dtb"
		echo "-----------------------------"
		echo "Warning: Support for the BeagleBoard C1/C2 is broken.. (board locks up during hardware detect)"
		echo "Please use the Demo Images Instead"
		echo "BeagleBoard: C4/C5 Users, can ignore this message.."
		echo "-----------------------------"
		;;
	beagle_xm)
		SYSTEM="beagle_xm"
		BOOTLOADER="BEAGLEBOARD_XM"
		is_omap
		smsc95xx_mem="16384"
		#dtb_file="omap3-beagle.dtb"
		;;
	beagle_xm_kms)
		SYSTEM="beagle_xm"
		BOOTLOADER="BEAGLEBOARD_XM"
		is_omap
		smsc95xx_mem="16384"
		#dtb_file="omap3-beagle.dtb"

		USE_KMS=1
		unset HAS_OMAPFB_DSS2

		KERNEL_SEL="TESTING"
		;;
	bone)
		boot="bootm"
		SYSTEM="bone"
		BOOTLOADER="BEAGLEBONE_A"
		is_omap
		SERIAL="ttyO0"
		SERIAL_CONSOLE="${SERIAL},115200n8"

		USE_UIMAGE=1

		SUBARCH="omap-psp"

		SERIAL_MODE=1

		unset HAS_OMAPFB_DSS2
		unset KMS_VIDEOA
		;;
	bone_zimage)
		SYSTEM="bone_zimage"
		BOOTLOADER="BEAGLEBONE_A"
		is_omap
		SERIAL="ttyO0"
		SERIAL_CONSOLE="${SERIAL},115200n8"

		USE_BETA_BOOTLOADER=1

		SUBARCH="omap-psp"

		SERIAL_MODE=1

		unset HAS_OMAPFB_DSS2
		unset KMS_VIDEOA
		;;
	igepv2)
		SYSTEM="igepv2"
		BOOTLOADER="IGEP00X0"
		is_omap

		SERIAL_MODE=1
		;;
	panda)
		SYSTEM="panda"
		BOOTLOADER="PANDABOARD"
		is_omap
		#dtb_file="omap4-panda.dtb"
		VIDEO_OMAP_RAM="16MB"
		KMS_VIDEOB="video=HDMI-A-1"
		smsc95xx_mem="16384"
		;;
	panda_es)
		SYSTEM="panda_es"
		BOOTLOADER="PANDABOARD_ES"
		is_omap
		#dtb_file="omap4-panda.dtb"
		VIDEO_OMAP_RAM="16MB"
		KMS_VIDEOB="video=HDMI-A-1"
		smsc95xx_mem="32768"
		;;
	panda_kms)
		SYSTEM="panda_es"
		BOOTLOADER="PANDABOARD_ES"
		is_omap
		#dtb_file="omap4-panda.dtb"

		USE_KMS=1
		unset HAS_OMAPFB_DSS2
		KMS_VIDEOB="video=HDMI-A-1"
		smsc95xx_mem="32768"

		KERNEL_SEL="TESTING"
		;;
	crane)
		SYSTEM="crane"
		BOOTLOADER="CRANEBOARD"
		is_omap

		KERNEL_SEL="TESTING"
		SERIAL_MODE=1
		;;
	mx51evk)
		SYSTEM="mx51evk"
		BOOTLOADER="MX51EVK"
		is_imx
		kernel_addr="0x90010000"
		initrd_addr="0x92000000"
		load_addr="0x90008000"
		dtb_addr="0x91ff0000"
		dtb_file="imx51-babbage.dtb"
		SERIAL_MODE=1
		;;
	mx51evk_dtb)
		SYSTEM="mx51evk_dtb"
		BOOTLOADER="MX51EVK"
		is_imx
		kernel_addr="0x90010000"
		initrd_addr="0x92000000"
		load_addr="0x90008000"
		dtb_addr="0x91ff0000"
		dtb_file="imx51-babbage.dtb"
		KERNEL_SEL="TESTING"
		SERIAL_MODE=1
		need_dtbs=1
		;;
	mx53loco)
		SYSTEM="mx53loco"
		BOOTLOADER="MX53LOCO"
		is_imx
		kernel_addr="0x70010000"
		initrd_addr="0x72000000"
		load_addr="0x70008000"
		dtb_addr="0x71ff0000"
		dtb_file="imx53-qsb.dtb"
		SERIAL_MODE=1
		;;
	mx53loco_dtb)
		SYSTEM="mx53loco_dtb"
		BOOTLOADER="MX53LOCO"
		is_imx
		kernel_addr="0x70010000"
		initrd_addr="0x72000000"
		load_addr="0x70008000"
		dtb_addr="0x71ff0000"
		dtb_file="imx53-qsb.dtb"
		KERNEL_SEL="TESTING"
		SERIAL_MODE=1
		need_dtbs=1
		;;
	mx6qsabrelite)
		SYSTEM="mx6qsabrelite"
		BOOTLOADER="MX6QSABRELITE_D"
		is_imx
		SERIAL="ttymxc1"
		SERIAL_CONSOLE="${SERIAL},115200"
		boot="bootm"
		USE_UIMAGE=1
		dd_seek="2"
		dd_bs="512"
		kernel_addr="0x10000000"
		initrd_addr="0x12000000"
		load_addr="0x10008000"
		dtb_addr="0x11ff0000"
		dtb_file="imx6q-sabrelite.dtb"
		KERNEL_SEL="TESTING"
		SERIAL_MODE=1
		need_dtbs=1
		boot_scr_wrapper=1
		;;
	*)
		IN_VALID_UBOOT=1
		cat <<-__EOF__
			-----------------------------
			ERROR: This script does not currently recognize the selected: [--uboot ${UBOOT_TYPE}] option..
			Please rerun $(basename $0) with a valid [--uboot <device>] option from the list below:
			-----------------------------
			        TI:
			                beagle_bx - <BeagleBoard Ax/Bx>
			                beagle_cx - <BeagleBoard Cx>
			                beagle_xm - <BeagleBoard xMA/B/C>
			                bone - <BeagleBone Ax>
			                igepv2 - <serial mode only>
			                panda - <PandaBoard Ax>
			                panda_es - <PandaBoard ES>
			        Freescale:
			                mx51evk - <i.MX51 "Babbage" Development Board>
			                mx53loco - <i.MX53 Quick Start Development Board>
			                mx51evk_dtb - <i.MX51 "Babbage" Development Board>
			                mx53loco_dtb - <i.MX53 Quick Start Development Board>
			                mx6qsabrelite - <http://boundarydevices.com/products/sabre-lite-imx6-sbc/>
			-----------------------------
		__EOF__
		exit
		;;
	esac

	if [ "${USE_UIMAGE}" ] ; then
		unset NEEDS_COMMAND
		check_for_command mkimage uboot-mkimage

		if [ "${NEEDS_COMMAND}" ] ; then
			echo ""
			echo "Your system is missing the mkimage dependency needed for this particular target."
			echo "Ubuntu/Debian: sudo apt-get install uboot-mkimage"
			echo "Fedora: as root: yum install uboot-tools"
			echo "Gentoo: emerge u-boot-tools"
			echo ""
			exit
		fi
	fi
}

function check_distro {
	unset IN_VALID_DISTRO
	case "${DISTRO_TYPE}" in
	maverick)
		DIST="maverick"
		ARCH="armel"
		;;
	natty)
		DIST="natty"
		ARCH="armel"
		;;
	oneiric)
		DIST="oneiric"
		ARCH="armel"
		;;
	precise-armel)
		DIST="precise"
		ARCH="armel"
		;;
	precise-armhf)
		DIST="precise"
		ARCH="armhf"
		;;
	quantal-armhf)
		DIST="quantal"
		ARCH="armhf"
		;;
	squeeze)
		DIST="squeeze"
		ARCH="armel"
		;;
	wheezy-armel)
		DIST="wheezy"
		ARCH="armel"
		;;
	wheezy-armhf)
		DIST="wheezy"
		ARCH="armhf"
		;;
	*)
		IN_VALID_DISTRO=1
		cat <<-__EOF__
			-----------------------------
			ERROR: This script does not currently recognize the selected: [--distro ${DISTRO_TYPE}] option..
			Please rerun $(basename $0) with a valid [--distro <distro>] option from the list below:
			-----------------------------
			--distro <distro>
			        Debian:
			                squeeze <default>
			                wheezy-armel <beta: may fail during install>
			                wheezy-armhf <beta: may fail during install>
			        Ubuntu:
			                maverick (10.10 - End Of Life: April 2012)
			                natty (11.04 - End Of Life: October 2012)
			                oneiric (11.10 - End Of Life: April 2013)
			                precise-armel (12.04)
			                precise-armhf (12.04)
			                quantal-armhf (12.10 <beta>)
			-----------------------------
		__EOF__
		exit
		;;
	esac
	DISTARCH="${DIST}-${ARCH}"
}

function usage {
	echo "usage: sudo $(basename $0) --mmc /dev/sdX --uboot <dev board>"
	#tabed to match 
		cat <<-__EOF__
			Script Version git: ${GIT_VERSION}
			-----------------------------
			Bugs email: "bugs at rcn-ee.com"

			Required Options:
			--mmc </dev/sdX>

			--uboot <dev board>
			        TI:
			                beagle_bx - <BeagleBoard Ax/Bx>
			                beagle_cx - <BeagleBoard Cx>
			                beagle_xm - <BeagleBoard xMA/B/C>
			                bone - <BeagleBone Ax>
			                igepv2 - <serial mode only>
			                panda - <PandaBoard Ax>
			                panda_es - <PandaBoard ES>
			        Freescale:
			                mx51evk - <i.MX51 "Babbage" Development Board>
			                mx53loco - <i.MX53 Quick Start Development Board>
			                mx51evk_dtb - <i.MX51 "Babbage" Development Board>
			                mx53loco_dtb - <i.MX53 Quick Start Development Board>
			                mx6qsabrelite - <http://boundarydevices.com/products/sabre-lite-imx6-sbc/>

			Optional:
			--distro <distro>
			        Debian:
			                squeeze <default>
			                wheezy-armel <beta: may fail during install>
			                wheezy-armhf <beta: may fail during install>
			        Ubuntu:
			                maverick (10.10 - End Of Life: April 2012)
			                natty (11.04 - End Of Life: October 2012)
			                oneiric (11.10 - End Of Life: April 2013)
			                precise-armel (12.04)
			                precise-armhf (12.04)
			                quantal-armhf (12.10 <beta>)

			--addon <additional peripheral device>
			        pico

			--firmware
			        <include all firmwares from linux-firmware git repo>

			--serial-mode
			        <use the serial to run the netinstall (video ouputs will remain blank till final reboot)>

			--svideo-ntsc
			        <force ntsc mode for S-Video>

			--svideo-pal
			        <force pal mode for S-Video>

			Additional Options:
			        -h --help

			--probe-mmc
			        <list all partitions: sudo ./mk_mmc.sh --probe-mmc>

			__EOF__
	exit
}

function checkparm {
	if [ "$(echo $1|grep ^'\-')" ] ; then
		echo "E: Need an argument"
		usage
	fi
}

IN_VALID_UBOOT=1

# parse commandline options
while [ ! -z "$1" ] ; do
	case $1 in
	-h|--help)
		usage
		MMC=1
		;;
	--probe-mmc)
		MMC="/dev/idontknow"
		check_root
		check_mmc
		;;
	--mmc)
		checkparm $2
		MMC="$2"
		if [[ "${MMC}" =~ "mmcblk" ]] ; then
			PARTITION_PREFIX="p"
		fi
		check_root
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
	--serial-mode)
		SERIAL_MODE=1
		;;
	--addon)
		checkparm $2
		ADDON=$2
		;;
	--svideo-ntsc)
		SVIDEO_NTSC=1
		;;
	--svideo-pal)
		SVIDEO_PAL=1
		;;
	--deb-file)
		checkparm $2
		DEB_FILE="$2"
		KERNEL_DEB=1
		;;
	--use-beta-kernel)
		BETA_KERNEL=1
		;;
	--use-experimental-kernel)
		EXPERIMENTAL_KERNEL=1
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

if [ ! "${MMC}" ] ; then
	echo "ERROR: --mmc undefined"
	usage
fi

if [ "${IN_VALID_UBOOT}" ] ; then
	echo "ERROR: --uboot undefined"
	usage
fi

if [ -n "${ADDON}" ] ; then
	if ! is_valid_addon ${ADDON} ; then
		echo "ERROR: ${ADDON} is not a valid addon type"
		echo "-----------------------------"
		echo "Supported --addon options:"
		echo "    pico"
		exit
	fi
fi

echo ""
echo "Script Version git: ${GIT_VERSION}"
echo "-----------------------------"

check_root
detect_software

if [ "${spl_name}" ] || [ "${boot_name}" ] ; then
	if [ "${USE_LOCAL_BOOT}" ] ; then
		local_bootloader
	else
		dl_bootloader
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

