#!/bin/bash -e
#
# Copyright (c) 2009-2013 Robert Nelson <robertcnelson@gmail.com>
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
	minimal_boot="1"

	mkdir -p ${TEMPDIR}/dl/${DISTARCH}
	mkdir -p "${DIR}/dl/${DISTARCH}"

	wget --no-verbose --directory-prefix=${TEMPDIR}/dl/ ${bootloader_http}/${bootloader_latest_file}

	if [ ! -f ${TEMPDIR}/dl/${bootloader_latest_file} ] ; then
		echo "error: can't connect to rcn-ee.net, retry in a few minutes..."
		exit
	fi

	boot_version=$(cat ${TEMPDIR}/dl/${bootloader_latest_file} | grep "VERSION:" | awk -F":" '{print $2}')
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
		MLO=$(cat ${TEMPDIR}/dl/${bootloader_latest_file} | grep "${ABI}:${board}:SPL" | awk '{print $2}')
		wget --no-verbose --directory-prefix=${TEMPDIR}/dl/ ${MLO}
		MLO=${MLO##*/}
		echo "SPL Bootloader: ${MLO}"
	else
		unset MLO
	fi

	if [ "${boot_name}" ] ; then
		UBOOT=$(cat ${TEMPDIR}/dl/${bootloader_latest_file} | grep "${ABI}:${board}:BOOT" | awk '{print $2}')
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
		kernel_repo="TESTING"
	fi

	if [ "${EXPERIMENTAL_KERNEL}" ] ; then
		kernel_repo="EXPERIMENTAL"
	fi

	if [ ! "${KERNEL_DEB}" ] ; then
		wget --no-verbose --directory-prefix=${TEMPDIR}/dl/ ${MIRROR}/${DISTARCH}/LATEST-${kernel_subarch}

		FTP_DIR=$(cat ${TEMPDIR}/dl/LATEST-${kernel_subarch} | grep "ABI:1 ${kernel_repo}" | awk '{print $3}')

		#http://rcn-ee.net/deb/squeeze-armel/v3.2.6-x4/install-me.sh
		FTP_DIR=$(echo ${FTP_DIR} | awk -F'/' '{print $6}')

		KERNEL=$(echo ${FTP_DIR} | sed 's/v//')

		wget --no-verbose --directory-prefix=${TEMPDIR}/dl/ ${MIRROR}/${DISTARCH}/${FTP_DIR}/
		ACTUAL_DEB_FILE=$(cat ${TEMPDIR}/dl/index.html | grep linux-image)
		ACTUAL_DEB_FILE=$(echo ${ACTUAL_DEB_FILE} | awk -F ".deb" '{print $1}')
		ACTUAL_DEB_FILE=${ACTUAL_DEB_FILE##*linux-image-}
		ACTUAL_DEB_FILE="linux-image-${ACTUAL_DEB_FILE}.deb"

		wget -c --directory-prefix="${DIR}/dl/${DISTARCH}" ${MIRROR}/${DISTARCH}/v${KERNEL}/${ACTUAL_DEB_FILE}

		#http://rcn-ee.net/deb/wheezy-armhf/v3.8.0-rc5-bone1/3.8.0-rc5-bone1-firmware.tar.gz
		firmware_file=$(cat ${TEMPDIR}/dl/index.html | grep firmware.tar.gz | head -n 1)
		firmware_file=$(echo ${firmware_file} | awk -F "\"" '{print $2}')

		if [ "x${firmware_file}" != "x" ] ; then
			wget -c --directory-prefix="${DIR}/dl/${DISTARCH}" ${MIRROR}/${DISTARCH}/v${KERNEL}/${firmware_file}
		else
			unset firmware_file
		fi

		if [ "${need_dtbs}" ] || [ "${populate_dtbs}" ] ; then
			ACTUAL_DTB_FILE=$(cat ${TEMPDIR}/dl/index.html | grep dtbs.tar.gz | head -n 1)
			#<a href="3.5.0-imx2-dtbs.tar.gz">3.5.0-imx2-dtbs.tar.gz</a> 08-Aug-2012 21:34 8.7K
			ACTUAL_DTB_FILE=$(echo ${ACTUAL_DTB_FILE} | awk -F "\"" '{print $2}')
			#3.5.0-imx2-dtbs.tar.gz

			if [ "x${ACTUAL_DTB_FILE}" != "x" ] ; then
				wget -c --directory-prefix="${DIR}/dl/${DISTARCH}" ${MIRROR}/${DISTARCH}/v${KERNEL}/${ACTUAL_DTB_FILE}
			else
				unset ACTUAL_DTB_FILE
			fi
		fi

	else
		KERNEL=${external_deb_file}
		#Remove all "\" from file name.
		ACTUAL_DEB_FILE=$(echo ${external_deb_file} | sed 's!.*/!!' | grep linux-image)
		if [ -f "${DIR}/dl/${DISTARCH}/${ACTUAL_DEB_FILE}" ] ; then
			rm -rf "${DIR}/dl/${DISTARCH}/${ACTUAL_DEB_FILE}" || true
		fi
		cp -v ${external_deb_file} "${DIR}/dl/${DISTARCH}/"

		if [ "x${external_dtbs_file}" != "x" ] ; then
			ACTUAL_DTB_FILE=$(echo ${external_dtbs_file} | sed 's!.*/!!' | grep dtbs.tar.gz)
			if [ -f "${DIR}/dl/${DISTARCH}/${ACTUAL_DTB_FILE}" ] ; then
				rm -rf "${DIR}/dl/${DISTARCH}/${ACTUAL_DTB_FILE}" || true
			fi
			cp -v ${external_dtbs_file} "${DIR}/dl/${DISTARCH}/"
		fi

		if [ "x${external_firmware_file}" != "x" ] ; then
			firmware_file=$(echo ${external_firmware_file} | sed 's!.*/!!' | grep firmware.tar.gz)
			if [ -f "${DIR}/dl/${DISTARCH}/${firmware_file}" ] ; then
				rm -rf "${DIR}/dl/${DISTARCH}/${firmware_file}" || true
			fi
			cp -v ${external_firmware_file} "${DIR}/dl/${DISTARCH}/"
		fi

	fi
	echo "Using Kernel: ${ACTUAL_DEB_FILE}"
	if [ "${ACTUAL_DTB_FILE}" ] ; then
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

	##FIXME: "network-console" support...
	debian_boot="netboot"
	source "${DIR}"/lib/distro.conf

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
			conf_fdtfile=${conf_fdtfile}

		__EOF__

		cat >> ${TEMPDIR}/bootscripts/netinstall.cmd <<-__EOF__
			initrd_high=0xffffffff
			fdt_high=0xffffffff
			conf_fdtfile=${conf_fdtfile}

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

	__EOF__

	cat >> ${TEMPDIR}/bootscripts/netinstall.cmd <<-__EOF__
		console=DICONSOLE

		mmcroot=/dev/ram0 rw

	__EOF__

	if [ "${uboot_USE_MMC_DEFINES}" ] ; then
		cat >> ${TEMPDIR}/bootscripts/normal.cmd <<-__EOF__
			loadkernel=${uboot_CMD_LOAD} mmc \${mmcdev}:\${mmcpart} ${conf_loadaddr} \${kernel_file}
			loadinitrd=${uboot_CMD_LOAD} mmc \${mmcdev}:\${mmcpart} ${conf_initrdaddr} \${initrd_file}; setenv initrd_size \${filesize}
			loadftd=${uboot_CMD_LOAD} mmc \${mmcdev}:\${mmcpart} ${conf_fdtaddr} /dtbs/\${conf_fdtfile}

		__EOF__
		cat >> ${TEMPDIR}/bootscripts/netinstall.cmd <<-__EOF__
			loadkernel=${uboot_CMD_LOAD} mmc \${mmcdev}:\${mmcpart} ${conf_loadaddr} \${kernel_file}
			loadinitrd=${uboot_CMD_LOAD} mmc \${mmcdev}:\${mmcpart} ${conf_initrdaddr} \${initrd_file}; setenv initrd_size \${filesize}
			loadftd=${uboot_CMD_LOAD} mmc \${mmcdev}:\${mmcpart} ${conf_fdtaddr} /dtbs/\${conf_fdtfile}

		__EOF__
	else
		cat >> ${TEMPDIR}/bootscripts/normal.cmd <<-__EOF__
			loadkernel=${uboot_CMD_LOAD} mmc 0:1 ${conf_loadaddr} \${kernel_file}
			loadinitrd=${uboot_CMD_LOAD} mmc 0:1 ${conf_initrdaddr} \${initrd_file}; setenv initrd_size \${filesize}
			loadftd=${uboot_CMD_LOAD} mmc 0:1 ${conf_fdtaddr} /dtbs/\${conf_fdtfile}

		__EOF__
		cat >> ${TEMPDIR}/bootscripts/netinstall.cmd <<-__EOF__
			loadkernel=${uboot_CMD_LOAD} mmc 0:1 ${conf_loadaddr} \${kernel_file}
			loadinitrd=${uboot_CMD_LOAD} mmc 0:1 ${conf_initrdaddr} \${initrd_file}; setenv initrd_size \${filesize}
			loadftd=${uboot_CMD_LOAD} mmc 0:1 ${conf_fdtaddr} /dtbs/\${conf_fdtfile}

		__EOF__
	fi

	if [ "${SERIAL_MODE}" ] ; then
		cat >> ${TEMPDIR}/bootscripts/netinstall.cmd <<-__EOF__
			xyz_message=echo; echo Installer for [${DISTARCH}] is using the Serial Interface; echo;

		__EOF__
	else
		cat >> ${TEMPDIR}/bootscripts/netinstall.cmd <<-__EOF__
			xyz_message=echo; echo Installer for [${DISTARCH}] is using the Video Interface; echo Use [--serial-mode] to force Installing over the Serial Interface; echo;

		__EOF__
	fi

	if [ ! "${need_dtbs}" ] ; then
		cat >> ${TEMPDIR}/bootscripts/normal.cmd <<-__EOF__
			xyz_mmcboot=run loadkernel; run loadinitrd; echo Booting from mmc ...

		__EOF__

		cat >> ${TEMPDIR}/bootscripts/netinstall.cmd <<-__EOF__
			xyz_mmcboot=run xyz_message; run loadkernel; run loadinitrd; echo Booting from mmc ...

		__EOF__
	else
		cat >> ${TEMPDIR}/bootscripts/normal.cmd <<-__EOF__
			xyz_mmcboot=run loadkernel; run loadinitrd; run loadftd; echo Booting from mmc ...

		__EOF__

		cat >> ${TEMPDIR}/bootscripts/netinstall.cmd <<-__EOF__
			xyz_mmcboot=run xyz_message; run loadkernel; run loadinitrd; run loadftd; echo Booting from mmc ...

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
		__EOF__

		cat >> ${TEMPDIR}/bootscripts/netinstall.cmd <<-__EOF__
			expansion_args=setenv expansion buddy=\${buddy} buddy2=\${buddy2} musb_hdrc.fifo_mode=5
		__EOF__
		;;
	beagle_xm)
		cat >> ${TEMPDIR}/bootscripts/normal.cmd <<-__EOF__
			optargs=VIDEO_CONSOLE
			expansion_args=setenv expansion buddy=\${buddy} buddy2=\${buddy2}
		__EOF__

		cat >> ${TEMPDIR}/bootscripts/netinstall.cmd <<-__EOF__
			expansion_args=setenv expansion buddy=\${buddy} buddy2=\${buddy2}
		__EOF__
		;;
	crane|igepv2|mx53loco|panda|panda_es|panda_dtb|panda_es_dtb|mx51evk|mx6qsabrelite)
		cat >> ${TEMPDIR}/bootscripts/normal.cmd <<-__EOF__
			optargs=VIDEO_CONSOLE
			expansion_args=setenv expansion
		__EOF__

		cat >> ${TEMPDIR}/bootscripts/netinstall.cmd <<-__EOF__
			expansion_args=setenv expansion
		__EOF__
		;;
	bone|bone_dtb)
		cat >> ${TEMPDIR}/bootscripts/normal.cmd <<-__EOF__
			expansion_args=setenv expansion ip=\${ip_method}
		__EOF__

		cat >> ${TEMPDIR}/bootscripts/netinstall.cmd <<-__EOF__
			expansion_args=setenv expansion ip=\${ip_method}
		__EOF__
		;;
	*)
		cat >> ${TEMPDIR}/bootscripts/normal.cmd <<-__EOF__
			expansion_args=setenv expansion
		__EOF__

		cat >> ${TEMPDIR}/bootscripts/netinstall.cmd <<-__EOF__
			expansion_args=setenv expansion
		__EOF__
		;;
	esac

	if [ ! "${need_dtbs}" ] ; then
		cat >> ${TEMPDIR}/bootscripts/normal.cmd <<-__EOF__
			${uboot_SCRIPT_ENTRY}=run xyz_mmcboot; run device_args; ${boot_image} ${conf_loadaddr} ${conf_initrdaddr}:\${initrd_size}

		__EOF__

		cat >> ${TEMPDIR}/bootscripts/netinstall.cmd <<-__EOF__
			${uboot_SCRIPT_ENTRY}=run xyz_mmcboot; run device_args; ${boot_image} ${conf_loadaddr} ${conf_initrdaddr}:\${initrd_size}

		__EOF__
	else
		cat >> ${TEMPDIR}/bootscripts/normal.cmd <<-__EOF__
			${uboot_SCRIPT_ENTRY}=run xyz_mmcboot; run device_args; ${boot_image} ${conf_loadaddr} ${conf_initrdaddr}:\${initrd_size} ${conf_fdtaddr}

		__EOF__

		cat >> ${TEMPDIR}/bootscripts/netinstall.cmd <<-__EOF__
			${uboot_SCRIPT_ENTRY}=run xyz_mmcboot; run device_args; ${boot_image} ${conf_loadaddr} ${conf_initrdaddr}:\${initrd_size} ${conf_fdtaddr}

		__EOF__
	fi
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
			sed -i -e 's:VIDEO_DISPLAY::g' ${TEMPDIR}/bootscripts/${ALL}
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

function git_failure {
	echo "Unable to pull/clone git tree"
	exit
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
		git clone git://git.kernel.org/pub/scm/linux/kernel/git/firmware/linux-firmware.git || git_failure
	else
		cd "${DIR}/dl/linux-firmware"
		git pull || git_failure
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
		git clone git://arago-project.org/git/projects/am33x-cm3.git || git_failure
	else
		cd "${DIR}/dl/am33x-cm3"
		git pull || git_failure
	fi
	cd "${DIR}/"
}

function dl_device_firmware {
	mkdir -p ${TEMPDIR}/firmware/
	DL_WGET="wget --directory-prefix=${TEMPDIR}/firmware/"
	case "${SYSTEM}" in
	beagle_xm|panda|panda_dtb|panda_es|panda_es_dtb)
		dl_linux_firmware
		echo "-----------------------------"
		echo "Adding Firmware for onboard WiFi/Bluetooth module"
		echo "-----------------------------"
		cp -r "${DIR}/dl/linux-firmware/ti-connectivity" ${TEMPDIR}/firmware/
		#${DL_WGET}ti-connectivity http://rcn-ee.net/firmware/ti/7.6.15_ble/WL1271L_BLE_Enabled_BTS_File/115K/TIInit_7.6.15.bts
		;;
	esac

	if [ "${need_am335x_firmware}" ] ; then
		dl_am335_firmware
		echo "-----------------------------"
		echo "Adding pre-built Firmware for am335x powermanagment"
		echo "SRC: http://arago-project.org/git/projects/?p=am33x-cm3.git;a=summary"
		echo "-----------------------------"
		cp -v "${DIR}/dl/am33x-cm3/bin/am335x-pm-firmware.bin" ${TEMPDIR}/firmware/

		if [ "${firmware_file}" ] ; then
			#Cape Firmware
			mkdir -p "${TEMPDIR}/cape-firmware/"
			tar xf "${DIR}/dl/${DISTARCH}/${firmware_file}" -C "${TEMPDIR}/cape-firmware/"
			cp -v "${TEMPDIR}/cape-firmware"/*.dtbo ${TEMPDIR}/firmware/ || true
		fi
	fi
}

function initrd_add_firmware {
	DL_WGET="wget --directory-prefix=${TEMPDIR}/firmware/"
	echo ""
	echo "NetInstall: Adding Firmware"
	echo "-----------------------------"
	echo "Adding: OpenSource Firmware"
	echo "-----------------------------"
	${DL_WGET} http://rcn-ee.net/firmware/carl9170/1.9.6/carl9170-1.fw
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
	rm -rf ${TEMPDIR}/initrd-tree/lib/modules/*-mx5 || true
	rm -rf ${TEMPDIR}/initrd-tree/lib/firmware/*-versatile/ || true
}

function flash_kernel {
	cat > ${TEMPDIR}/initrd-tree/etc/flash-kernel.conf <<-__EOF__
		#!/bin/sh -e
		UBOOT_PART=/dev/mmcblk0p1

		echo "flash-kernel stopped by: /etc/flash-kernel.conf"
		USE_CUSTOM_KERNEL=1

		if [ "\${USE_CUSTOM_KERNEL}" ] ; then
		        DIST=\$(lsb_release -cs)

		        case "\${DIST}" in
		        oneiric|precise|quantal|raring)
		                FLASH_KERNEL_SKIP=yes
		                ;;
		        esac
		fi

	__EOF__
}

function flash_kernel_base_installer {
	#All this crap, is just to make "flash-kernel-installer" happy...
	cat > ${TEMPDIR}/initrd-tree/usr/lib/post-base-installer.d/00flash-kernel <<-__EOF__
		#!/bin/sh -e
		#BusyBox: http://linux.die.net/man/1/busybox

		cp /etc/flash-kernel.conf /target/etc/flash-kernel.conf
		zcat /proc/config.gz > /target/boot/config-\$(uname -r)

		mkdir -p /target/boot/uboot || true
		mkdir -p /target/lib/modules/\$(uname -r) || true

		mount /dev/mmcblk0p1 /target/boot/uboot

		#z = gzip (busybox tar)
		tar -xzv -f /target/boot/uboot/\$(uname -r)-modules.tar.gz -C /target/lib/modules/\$(uname -r)

		mount -o bind /sys /target/sys
		cat /proc/mounts > /target/mounts
		chroot /target update-initramfs -c -k \$(uname -r)
		rm -f /target/mounts || true
		umount /target/sys

		cp /target/boot/uboot/${fki_vmlinuz} /target/boot/${fki_vmlinuz}
		cp /target/boot/initrd.img-\$(uname -r) /target/boot/${fki_initrd}
		sync
		umount /target/boot/uboot

		export FLASH_KERNEL_SKIP=true

	__EOF__

	chmod a+x ${TEMPDIR}/initrd-tree/usr/lib/post-base-installer.d/00flash-kernel
}

function finish_installing_device {
	cat > ${TEMPDIR}/initrd-tree/usr/lib/finish-install.d/08rcn-ee-finish-installing-device <<-__EOF__
		#!/bin/sh -e
		cp /etc/finish-install.sh /target/etc/finish-install.sh
		chmod a+x /target/etc/finish-install.sh

		if [ -f /etc/rcn.conf ]; then
		        mkdir -p /target/boot/uboot || true
		        mount /dev/mmcblk0p1 /target/boot/uboot

		        if [ -d /lib/firmware/ ] ; then
		                cp -rf /lib/firmware/ /target/lib/ || true
		        fi

		        rm -f /etc/rcn.conf

		        mount -o bind /sys /target/sys
		        cat /proc/mounts > /target/mounts

		        mkdir -p /target/etc/hwpack/
		        cp /etc/hwpack/SOC.sh /target/etc/hwpack/

		        chroot /target /bin/bash /etc/finish-install.sh

		        rm -f /target/mounts || true

		        cat /proc/mounts > /target/boot/uboot/backup/proc_mounts
		        cat /var/log/syslog > /target/boot/uboot/backup/syslog.log

		        umount /target/sys
		        sync
		        umount /target/boot/uboot
		fi

	__EOF__

	chmod a+x ${TEMPDIR}/initrd-tree/usr/lib/finish-install.d/08rcn-ee-finish-installing-device
}

setup_parition_recipe () {
	#This (so far) has been leaving the first Partition Alone...
	cat > ${TEMPDIR}/initrd-tree/partition_recipe <<-__EOF__
		        500 10000 -1 ext4
		                method{ format }
		                format{ }
		                use_filesystem{ }
		                filesystem{ ext4 }
		                mountpoint{ / } .
		 
		        128 64 512 300% linux-swap
		                method{ swap }
		                format{ } .

	__EOF__
}

function initrd_preseed_settings {
	echo "NetInstall: Adding Distro Tweaks and Preseed Configuration"
	cd ${TEMPDIR}/initrd-tree/
	case "${DIST}" in
	oneiric|precise|quantal|raring)
		cp -v "${DIR}/lib/ubuntu-finish.sh" ${TEMPDIR}/initrd-tree/etc/finish-install.sh
		flash_kernel
		flash_kernel_base_installer
		;;
	squeeze|wheezy)
		cp -v "${DIR}/lib/debian-finish.sh" ${TEMPDIR}/initrd-tree/etc/finish-install.sh
		;;
	esac

	finish_installing_device
	setup_parition_recipe
	cp -v "${DIR}/lib/${DIST}-preseed.cfg" ${TEMPDIR}/initrd-tree/preseed.cfg

	if [ "${SERIAL_MODE}" ] ; then
		#Squeeze: keymaps aren't an issue with serial mode so disable preseed workaround:
		sed -i -e 's:d-i console-tools:#d-i console-tools:g' ${TEMPDIR}/initrd-tree/preseed.cfg
		sed -i -e 's:d-i debian-installer:#d-i debian-installer:g' ${TEMPDIR}/initrd-tree/preseed.cfg
		sed -i -e 's:d-i console-keymaps-at:#d-i console-keymaps-at:g' ${TEMPDIR}/initrd-tree/preseed.cfg
	fi

	cd "${DIR}"/
}

function extract_zimage {
	echo "NetInstall: Extracting Kernel Boot Image"
	dpkg -x "${DIR}/dl/${DISTARCH}/${ACTUAL_DEB_FILE}" ${TEMPDIR}/kernel
}

package_modules () {
	echo "NetInstall: Packaging Modules for later use"
	linux_version=$(ls ${TEMPDIR}/kernel/boot/vmlinuz-* | awk -F'vmlinuz-' '{print $2}')
	cd ${TEMPDIR}/kernel/lib/modules/${linux_version}
	tar czf ${TEMPDIR}/kernel/${linux_version}-modules.tar.gz *
	cd "${DIR}"/
}

function initrd_device_settings {
	echo "NetInstall: Adding Device Tweaks"
	touch ${TEMPDIR}/initrd-tree/etc/rcn.conf

	#work around for the kevent smsc95xx issue
	touch ${TEMPDIR}/initrd-tree/etc/sysctl.conf
	if [ "${usbnet_mem}" ] ; then
		echo "vm.min_free_kbytes = ${usbnet_mem}" >> ${TEMPDIR}/initrd-tree/etc/sysctl.conf
	fi

	mkdir -p ${TEMPDIR}/initrd-tree/etc/hwpack/

	#This should be compatible with hwpacks variable names..
	#https://code.launchpad.net/~linaro-maintainers/linaro-images/
	cat > ${TEMPDIR}/initrd-tree/etc/hwpack/SOC.sh <<-__EOF__
		#!/bin/sh
		format=1.0
		board=${board}

		bootloader_location=${bootloader_location}
		dd_spl_uboot_seek=${dd_spl_uboot_seek}
		dd_spl_uboot_bs=${dd_spl_uboot_bs}
		dd_uboot_seek=${dd_uboot_seek}
		dd_uboot_bs=${dd_uboot_bs}

		boot_image=${boot_image}
		boot_script=${boot_script}
		boot_fstype=${boot_fstype}

		serial_tty=${SERIAL}
		conf_loadaddr=${conf_loadaddr}
		conf_initrdaddr=${conf_initrdaddr}
		conf_zreladdr=${conf_zreladdr}
		conf_fdtaddr=${conf_fdtaddr}
		conf_fdtfile=${conf_fdtfile}

		usbnet_mem=${usbnet_mem}

	__EOF__
}

function recompress_initrd {
	echo "NetInstall: Compressing initrd image"
	cd ${TEMPDIR}/initrd-tree/
	find . | cpio -o -H newc | gzip -9 > ${TEMPDIR}/initrd.mod.gz
	cd "${DIR}/"
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
	extract_zimage
	package_modules
	initrd_device_settings
	recompress_initrd
}

function drive_error_ro {
	echo "-----------------------------"
	echo "Error: [LC_ALL=C parted --script ${MMC} mklabel msdos] failed..."
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

	echo "Zeroing out Partition Table"
	dd if=/dev/zero of=${MMC} bs=1024 count=1024
	sync
	LC_ALL=C parted --script ${MMC} mklabel msdos || drive_error_ro
}

function fatfs_boot_error {
	echo "Failure: [parted --script ${MMC} set 1 boot on]"
	exit
}

function fatfs_boot {
	#For: TI: Omap/Sitara Devices
	echo ""
	echo "Using fdisk to create an omap compatible fatfs BOOT partition"
	echo "-----------------------------"

	fdisk ${MMC} <<-__EOF__
		n
		p
		1

		+${boot_partition_size}M
		t
		e
		p
		w
	__EOF__

	sync

	echo "Setting Boot Partition's Boot Flag"
	echo "-----------------------------"
	LC_ALL=C parted --script ${MMC} set 1 boot on || fatfs_boot_error
}

function dd_uboot_boot {
	#For: Freescale: i.mx5/6 Devices
	echo ""
	echo "Using dd to place bootloader on drive"
	echo "-----------------------------"
	dd if=${TEMPDIR}/dl/${UBOOT} of=${MMC} seek=${dd_uboot_seek} bs=${dd_uboot_bs}
	bootloader_installed=1
}

function dd_spl_uboot_boot {
	#For: Samsung: Exynos 4 Devices
	echo ""
	echo "Using dd to place bootloader on drive"
	echo "-----------------------------"
	dd if=${TEMPDIR}/dl/${UBOOT} of=${MMC} seek=${dd_spl_uboot_seek} bs=${dd_spl_uboot_bs}
	dd if=${TEMPDIR}/dl/${UBOOT} of=${MMC} seek=${dd_uboot_seek} bs=${dd_uboot_bs}
	bootloader_installed=1
}

function format_partition_error {
	echo "Failure: formating partition"
	exit
}

function format_boot_partition {
	echo "Formating Boot Partition"
	echo "-----------------------------"
	partprobe ${MMC}
	LC_ALL=C ${mkfs} ${MMC}${PARTITION_PREFIX}1 ${mkfs_label} || format_partition_error
}

function create_partitions {
	unset bootloader_installed

	if [ "x${boot_fstype}" == "xfat" ] ; then
		parted_format="fat16"
		mount_partition_format="vfat"
		mkfs="mkfs.vfat -F 16"
		mkfs_label="-n ${BOOT_LABEL}"
	else
		parted_format="ext2"
		mount_partition_format="ext2"
		mkfs="mkfs.ext2"
		mkfs_label="-L ${BOOT_LABEL}"
	fi

	if [ "${boot_startmb}" ] ; then
		let boot_endmb=${boot_startmb}+${boot_partition_size}
	fi

	case "${bootloader_location}" in
	fatfs_boot)
		fatfs_boot
		;;
	dd_uboot_boot)
		dd_uboot_boot
		LC_ALL=C parted --script ${PARTED_ALIGN} ${MMC} mkpart primary ${parted_format} ${boot_startmb} ${boot_endmb}
		;;
	dd_spl_uboot_boot)
		dd_spl_uboot_boot
		LC_ALL=C parted --script ${PARTED_ALIGN} ${MMC} mkpart primary ${parted_format} ${boot_startmb} ${boot_endmb}
		;;
	*)
		LC_ALL=C parted --script ${PARTED_ALIGN} ${MMC} mkpart primary ${parted_format} ${boot_startmb} ${boot_endmb}
		;;
	esac
	format_boot_partition
}

function populate_boot {
	echo "Populating Boot Partition"
	echo "-----------------------------"

	partprobe ${MMC}
	if [ ! -d ${TEMPDIR}/disk ] ; then
		mkdir -p ${TEMPDIR}/disk
	fi

	if mount -t ${mount_partition_format} ${MMC}${PARTITION_PREFIX}1 ${TEMPDIR}/disk; then
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

		if [ -f ${TEMPDIR}/kernel/boot/vmlinuz-* ] ; then
			LINUX_VER=$(ls ${TEMPDIR}/kernel/boot/vmlinuz-* | awk -F'vmlinuz-' '{print $2}')
			if [ "${USE_UIMAGE}" ] ; then
				echo "Using mkimage to create uImage"
				mkimage -A arm -O linux -T kernel -C none -a ${conf_zreladdr} -e ${conf_zreladdr} -n ${LINUX_VER} -d ${TEMPDIR}/kernel/boot/vmlinuz-* ${TEMPDIR}/disk/uImage.net
				echo "-----------------------------"
			else
				echo "Copying Kernel image:"
				cp -v ${TEMPDIR}/kernel/boot/vmlinuz-* ${TEMPDIR}/disk/zImage.net
				cp -v ${TEMPDIR}/kernel/boot/vmlinuz-* ${TEMPDIR}/disk/${fki_vmlinuz}
				echo "-----------------------------"
			fi
		fi

		if [ -f ${TEMPDIR}/initrd.mod.gz ] ; then
			if [ "${USE_UIMAGE}" ] ; then
				echo "Using mkimage to create uInitrd"
				mkimage -A arm -O linux -T ramdisk -C none -a 0 -e 0 -n initramfs -d ${TEMPDIR}/initrd.mod.gz ${TEMPDIR}/disk/uInitrd.net
				echo "-----------------------------"
			else
				echo "Copying Kernel initrd:"
				cp -v ${TEMPDIR}/initrd.mod.gz ${TEMPDIR}/disk/initrd.net
				echo "-----------------------------"
			fi
		fi

		if [ "${ACTUAL_DTB_FILE}" ] ; then
			echo "Copying Device Tree Files:"
			if [ "x${boot_fstype}" == "xfat" ] ; then
				tar xfvo "${DIR}/dl/${DISTARCH}/${ACTUAL_DTB_FILE}" -C ${TEMPDIR}/disk/dtbs
			else
				tar xfv "${DIR}/dl/${DISTARCH}/${ACTUAL_DTB_FILE}" -C ${TEMPDIR}/disk/dtbs
			fi
			cp -v "${DIR}/dl/${DISTARCH}/${ACTUAL_DTB_FILE}" ${TEMPDIR}/disk/
			echo "-----------------------------"
		fi

		if [ "${boot_scr_wrapper}" ] ; then
			cat > ${TEMPDIR}/bootscripts/loader.cmd <<-__EOF__
				echo "boot.scr -> uEnv.txt wrapper..."
				${uboot_CMD_LOAD} mmc \${mmcdev}:\${mmcpart} \${loadaddr} uEnv.txt
				env import -t \${loadaddr} \${filesize}
				run ${uboot_SCRIPT_ENTRY}
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
		cp -v ${TEMPDIR}/kernel/${linux_version}-modules.tar.gz ${TEMPDIR}/disk/

		#This should be compatible with hwpacks variable names..
		#https://code.launchpad.net/~linaro-maintainers/linaro-images/
		cat > ${TEMPDIR}/disk/SOC.sh <<-__EOF__
			#!/bin/sh
			format=1.0
			board=${board}

			bootloader_location=${bootloader_location}
			dd_spl_uboot_seek=${dd_spl_uboot_seek}
			dd_spl_uboot_bs=${dd_spl_uboot_bs}
			dd_uboot_seek=${dd_uboot_seek}
			dd_uboot_bs=${dd_uboot_bs}

			boot_image=${boot_image}
			boot_script=${boot_script}
			boot_fstype=${boot_fstype}

			serial_tty=${SERIAL}
			conf_loadaddr=${conf_loadaddr}
			conf_initrdaddr=${conf_initrdaddr}
			conf_zreladdr=${conf_zreladdr}
			conf_fdtaddr=${conf_fdtaddr}
			conf_fdtfile=${conf_fdtfile}

			usbnet_mem=${usbnet_mem}

		__EOF__

		echo "Debug:"
		cat ${TEMPDIR}/disk/SOC.sh

		echo "Debug: Adding Useful scripts from: https://github.com/RobertCNelson/tools"
		echo "-----------------------------"
		mkdir -p ${TEMPDIR}/disk/tools
		git clone git://github.com/RobertCNelson/tools.git ${TEMPDIR}/disk/tools || true
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
	echo "Note: Ubuntu Releases"
	echo "During Install, after proxy setup, there seems to be a LONG delay..."
	echo "(worst case 5 minutes on my Beagle xM)..."
	echo "Currently Investigating..."
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
		if which lsblk > /dev/null ; then
			echo "lsblk:"
			lsblk | grep -v sr0
		else
			echo "mount:"
			mount | grep -v none | grep "/dev/" --color=never
		fi
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

check_dtb_board () {
	invalid_dtb=1
	dtb_board=$(echo ${dtb_board} | awk -F ".conf" '{print $1}')
	if [ -f "${DIR}"/hwpack/${dtb_board}.conf ] ; then
		source "${DIR}"/hwpack/${dtb_board}.conf
		populate_dtbs=1
		unset invalid_dtb
	else
		cat <<-__EOF__
			-----------------------------
			ERROR: This script does not currently recognize the selected: [--dtb ${dtb_board}] option..
			Please rerun $(basename $0) with a valid [--dtb <device>] option from the list below:
			-----------------------------
		__EOF__
		cat "${DIR}"/hwpack/*.conf | grep supported
		echo "-----------------------------"
		exit
	fi
}

function is_omap {
	IS_OMAP=1

	bootloader_location="fatfs_boot"
	spl_name="MLO"
	boot_name="u-boot.img"

	kernel_subarch="omap"

	conf_loadaddr="0x80300000"
	conf_initrdaddr="0x81600000"
	conf_zreladdr="0x80008000"
	conf_fdtaddr="0x815f0000"
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

function convert_uboot_to_dtb_board {
	populate_dtbs=1
}

function check_uboot_type {
	#New defines for hwpack:
	bootloader_http="http://rcn-ee.net/deb/tools/latest/"
	bootloader_latest_file="bootloader-ng"

	unset IN_VALID_UBOOT
	unset USE_UIMAGE
	unset USE_KMS
	unset conf_fdtfile
	unset need_dtbs
	kernel_repo="STABLE"

	boot_image="bootz"
	unset spl_name
	unset boot_name
	unset bootloader_location
	unset dd_spl_uboot_seek
	unset dd_spl_uboot_bs
	unset dd_uboot_seek
	unset dd_uboot_bs

	unset boot_scr_wrapper
	unset usbnet_mem
	boot_partition_size="100"

	case "${UBOOT_TYPE}" in
	beagle_bx)
		uboot_SCRIPT_ENTRY="loaduimage"
		uboot_CMD_LOAD="fatload"
		SYSTEM="beagle_bx"
		board="BEAGLEBOARD_BX"
		is_omap
		#conf_fdtfile="omap3-beagle.dtb"
		usbnet_mem="8192"
		echo "-----------------------------"
		echo "Warning: Support for the Original BeagleBoard Ax/Bx is broken.. (board locks up during hardware detect)"
		echo "Please use the Demo Images Instead"
		echo "-----------------------------"
		;;
	beagle_cx)
		uboot_SCRIPT_ENTRY="loaduimage"
		uboot_CMD_LOAD="fatload"
		SYSTEM="beagle_cx"
		board="BEAGLEBOARD_CX"
		is_omap
		#conf_fdtfile="omap3-beagle.dtb"
		usbnet_mem="8192"
		echo "-----------------------------"
		echo "Warning: Support for the BeagleBoard C1/C2 is broken.. (board locks up during hardware detect)"
		echo "Please use the Demo Images Instead"
		echo "BeagleBoard: C4/C5 Users, can ignore this message.."
		echo "-----------------------------"
		;;
	beagle_xm)
		echo "Note: [--dtb omap3-beagle-xm] now replaces [--uboot beagle_xm]"
		source "${DIR}"/hwpack/omap3-beagle-xm.conf
		convert_uboot_to_dtb_board
		;;
	bone)
		need_am335x_firmware="1"
		uboot_SCRIPT_ENTRY="loaduimage"
		uboot_CMD_LOAD="fatload"
		SYSTEM="bone"
		board="BEAGLEBONE_A"
		is_omap
		SERIAL="ttyO0"
		SERIAL_CONSOLE="${SERIAL},115200n8"

		kernel_subarch="omap-psp"

		SERIAL_MODE=1

		unset HAS_OMAPFB_DSS2
		unset KMS_VIDEOA

		#just to disable the omapfb stuff..
		USE_KMS=1
		;;
	bone_dtb)
		echo "Note: [--dtb am335x-bone-serial] now replaces [--uboot bone_dtb]"
		source "${DIR}"/hwpack/am335x-bone-serial.conf
		convert_uboot_to_dtb_board
		;;
	igepv2)
		uboot_SCRIPT_ENTRY="loaduimage"
		SYSTEM="igepv2"
		board="IGEP00X0"
		is_omap

		SERIAL_MODE=1
		;;
	panda)
		echo "Note: [--dtb omap4-panda] now replaces [--uboot panda]"
		source "${DIR}"/hwpack/omap4-panda.conf
		convert_uboot_to_dtb_board
		;;
	panda_dtb)
		uboot_SCRIPT_ENTRY="loaduimage"
		uboot_CMD_LOAD="fatload"
		SYSTEM="panda_dtb"
		board="PANDABOARD"
		is_omap
		VIDEO_OMAP_RAM="16MB"
		KMS_VIDEOB="video=HDMI-A-1"
		usbnet_mem="32768"

		conf_fdtfile="omap4-panda.dtb"
		EXPERIMENTAL_KERNEL=1
		need_dtbs=1
		;;
	panda_es)
		uboot_SCRIPT_ENTRY="loaduimage"
		uboot_CMD_LOAD="fatload"
		SYSTEM="panda_es"
		board="PANDABOARD_ES"
		is_omap
		#conf_fdtfile="omap4-panda.dtb"
		VIDEO_OMAP_RAM="16MB"
		KMS_VIDEOB="video=HDMI-A-1"
		usbnet_mem="32768"
		;;
	panda_es_dtb)
		uboot_SCRIPT_ENTRY="loaduimage"
		uboot_CMD_LOAD="fatload"
		SYSTEM="panda_es_dtb"
		board="PANDABOARD_ES"
		is_omap
		VIDEO_OMAP_RAM="16MB"
		KMS_VIDEOB="video=HDMI-A-1"
		usbnet_mem="32768"

		conf_fdtfile="omap4-pandaES.dtb"
		need_dtbs=1
		;;
	panda_es_kms)
		uboot_SCRIPT_ENTRY="loaduimage"
		uboot_CMD_LOAD="fatload"
		SYSTEM="panda_es"
		board="PANDABOARD_ES"
		is_omap
		#conf_fdtfile="omap4-panda.dtb"

		USE_KMS=1
		unset HAS_OMAPFB_DSS2
		KMS_VIDEOB="video=HDMI-A-1"
		usbnet_mem="32768"

		kernel_repo="TESTING"
		;;
	crane)
		uboot_SCRIPT_ENTRY="loaduimage"
		uboot_CMD_LOAD="fatload"
		SYSTEM="crane"
		board="CRANEBOARD"
		is_omap

		kernel_repo="TESTING"
		SERIAL_MODE=1
		;;
	mx51evk)
		echo "Note: [--dtb imx51-babbage] now replaces [--uboot mx51evk]"
		source "${DIR}"/hwpack/imx51-babbage.conf
		convert_uboot_to_dtb_board
		;;
	mx53loco)
		echo "Note: [--dtb imx53-qsb] now replaces [--uboot mx53loco]"
		source "${DIR}"/hwpack/imx53-qsb.conf
		convert_uboot_to_dtb_board
		;;
	mx6qsabrelite)
		echo "Note: [--dtb imx6q-sabrelite] now replaces [--uboot mx6qsabrelite]"
		source "${DIR}"/hwpack/imx6q-sabrelite.conf
		convert_uboot_to_dtb_board
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
	ARCH="armel"
	fki_vmlinuz="vmlinuz"
	fki_initrd="initrd.img"

	case "${DISTRO_TYPE}" in
	oneiric)
		DIST="oneiric"
		;;
	precise-armel)
		DIST="precise"
		;;
	precise-armhf)
		DIST="precise"
		ARCH="armhf"
		;;
	quantal|quantal-armhf)
		DIST="quantal"
		ARCH="armhf"
		fki_vmlinuz="vmlinuz-"
		fki_initrd="initrd.img-"
		;;
	raring|raring-armhf)
		DIST="raring"
		ARCH="armhf"
		fki_vmlinuz="vmlinuz-"
		fki_initrd="initrd.img-"
		cat <<-__EOF__
			-----------------------------
			WARNING: RARING is BROKEN SEE: https://bugs.launchpad.net/bugs/1161912
			-----------------------------
		__EOF__

		read -p "Are you 100% sure on still trying to install [${DIST}] (y/n)? "
		[ "${REPLY}" == "y" ] || exit

		;;
	squeeze)
		DIST="squeeze"
		;;
	wheezy-armel)
		DIST="wheezy"
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
			                squeeze <default> (armv4)
			                wheezy-armel <beta: may fail during install> (armv4)
			                wheezy-armhf <beta: may fail during install> (armv7-a)
			        Ubuntu:
			                oneiric (11.10 - End Of Life: April 2013) (armv7-a)
			                precise-armel (12.04) (armv7-a)
			                precise-armhf (12.04) (armv7-a)
			                quantal (12.10) (armv7-a)
			                raring (13.04) (armv7-a) <BROKEN SEE: https://bugs.launchpad.net/bugs/1161912>
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
			                mx6qsabrelite - <http://boundarydevices.com/products/sabre-lite-imx6-sbc/>

			Optional:
			--distro <distro>
			        Debian:
			                squeeze <default> (armv4)
			                wheezy-armel <beta: may fail during install> (armv4)
			                wheezy-armhf <beta: may fail during install> (armv7-a)
			        Ubuntu:
			                oneiric (11.10 - End Of Life: April 2013) (armv7-a)
			                precise-armel (12.04) (armv7-a)
			                precise-armhf (12.04) (armv7-a)
			                quantal (12.10) (armv7-a)
			                raring (13.04) (armv7-a) <BROKEN SEE: https://bugs.launchpad.net/bugs/1161912>

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
		external_deb_file="$2"
		DEB_FILE="${external_deb_file}"
		KERNEL_DEB=1
		;;
	--dtbs-file)
		checkparm $2
		external_dtbs_file="$2"
		KERNEL_DEB=1
		;;
	--firmware-file)
		checkparm $2
		external_firmware_file="$2"
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

if [ "${invalid_dtb}" ] ; then
	if [ "${IN_VALID_UBOOT}" ] ; then
		echo "ERROR: --uboot undefined"
		usage
	fi
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

