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
error_invalid_uboot_dtb=1

DIST=wheezy
ARCH=armhf
DISTARCH="${DIST}-${ARCH}"

DIR="$PWD"
TEMPDIR=$(mktemp -d)

is_element_of () {
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

is_valid_addon () {
	if is_element_of $1 "${VALID_ADDONS}" ] ; then
		return 0
	else
		return 1
	fi
}

check_root () {
	if ! [ $(id -u) = 0 ] ; then
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
	check_for_command patch patch
	check_for_command mkimage u-boot-tools

	if [ "${NEEDS_COMMAND}" ] ; then
		echo ""
		echo "Your system is missing some dependencies"
		echo "Ubuntu/Debian: sudo apt-get install wget dosfstools u-boot-tools"
		echo "Fedora: as root: yum install wget dosfstools dpkg patch uboot-tools"
		echo "Gentoo: emerge wget dosfstools dpkg u-boot-tools"
		echo ""
		exit
	fi
}

local_bootloader () {
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

dl_bootloader () {
	echo ""
	echo "Downloading Device's Bootloader"
	echo "-----------------------------"
	minimal_boot="1"

	mkdir -p ${TEMPDIR}/dl/${DISTARCH}
	mkdir -p "${DIR}/dl/${DISTARCH}"

	wget --no-verbose --directory-prefix=${TEMPDIR}/dl/ ${conf_bl_http}/${conf_bl_listfile}

	if [ ! -f ${TEMPDIR}/dl/${conf_bl_listfile} ] ; then
		echo "error: can't connect to rcn-ee.net, retry in a few minutes..."
		exit
	fi

	boot_version=$(cat ${TEMPDIR}/dl/${conf_bl_listfile} | grep "VERSION:" | awk -F":" '{print $2}')
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
		MLO=$(cat ${TEMPDIR}/dl/${conf_bl_listfile} | grep "${ABI}:${conf_board}:SPL" | awk '{print $2}')
		wget --no-verbose --directory-prefix=${TEMPDIR}/dl/ ${MLO}
		MLO=${MLO##*/}
		echo "SPL Bootloader: ${MLO}"
	else
		unset MLO
	fi

	if [ "${boot_name}" ] ; then
		UBOOT=$(cat ${TEMPDIR}/dl/${conf_bl_listfile} | grep "${ABI}:${conf_board}:BOOT" | awk '{print $2}')
		wget --directory-prefix=${TEMPDIR}/dl/ ${UBOOT}
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

remove_uboot_wrapper () {
	echo "Note: NetInstall has u-boot header, removing..."
	echo "-----------------------------"
	dd if="${DIR}/dl/${DISTARCH}/${NETINSTALL}" bs=64 skip=1 of="${DIR}/dl/${DISTARCH}/initrd.gz"
	echo "-----------------------------"
	NETINSTALL="initrd.gz"
	unset UBOOTWRAPPER
}

actually_dl_netinstall () {
	wget --directory-prefix="${DIR}/dl/${DISTARCH}" ${HTTP_IMAGE}/${DIST}/main/installer-${ARCH}/${NETIMAGE}/images/${BASE_IMAGE}/${NETINSTALL}
	MD5SUM=$(md5sum "${DIR}/dl/${DISTARCH}/${NETINSTALL}" | awk '{print $1}')
	if [ "${UBOOTWRAPPER}" ] ; then
		remove_uboot_wrapper
	fi
}

check_dl_netinstall () {
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

dl_netinstall_image () {
	echo ""
	echo "Downloading NetInstall Image"
	echo "-----------------------------"

	##FIXME: "network-console" support...
	debian_boot="netboot"
	. "${DIR}"/lib/distro.conf

	if [ -f "${DIR}/dl/${DISTARCH}/${NETINSTALL}" ] ; then
		check_dl_netinstall
	else
		actually_dl_netinstall
	 fi
	echo "md5sum of NetInstall: ${MD5SUM}"
}

boot_uenv_txt_template () {
	#Start with a blank state:
	echo "#Normal Boot" > ${TEMPDIR}/bootscripts/normal.cmd
	echo "#Debian Installer only Boot" > ${TEMPDIR}/bootscripts/netinstall.cmd

	if [ "${need_dtbs}" ] && [ ! "${uboot_fdt_auto_detection}" ] ; then
		cat >> ${TEMPDIR}/bootscripts/normal.cmd <<-__EOF__
			initrd_high=0xffffffff
			fdt_high=0xffffffff
			fdtfile=${conf_fdtfile}

		__EOF__

		cat >> ${TEMPDIR}/bootscripts/netinstall.cmd <<-__EOF__
			initrd_high=0xffffffff
			fdt_high=0xffffffff
			fdtfile=${conf_fdtfile}

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
		kernel_file=${conf_normal_kernel_file}
		initrd_file=${conf_normal_initrd_file}

		console=SERIAL_CONSOLE

		mmcroot=FINAL_PART ro
		mmcrootfstype=FINAL_FSTYPE rootwait fixrtc

		loadkernel=${conf_fileload} mmc \${mmcdev}:\${mmcpart} ${conf_loadaddr} \${kernel_file}
		loadinitrd=${conf_fileload} mmc \${mmcdev}:\${mmcpart} ${conf_initrdaddr} \${initrd_file}; setenv initrd_size \${filesize}
		loadfdt=${conf_fileload} mmc \${mmcdev}:\${mmcpart} ${conf_fdtaddr} /dtbs/\${fdtfile}

		boot_classic=run loadkernel; run loadinitrd
		boot_fdt=run loadkernel; run loadinitrd; run loadfdt

	__EOF__

	cat >> ${TEMPDIR}/bootscripts/netinstall.cmd <<-__EOF__
		kernel_file=${conf_net_kernel_file}
		initrd_file=${conf_net_initrd_file}

		console=DICONSOLE

		mmcroot=/dev/ram0 rw

		loadkernel=${conf_fileload} mmc \${mmcdev}:\${mmcpart} ${conf_loadaddr} \${kernel_file}
		loadinitrd=${conf_fileload} mmc \${mmcdev}:\${mmcpart} ${conf_initrdaddr} \${initrd_file}; setenv initrd_size \${filesize}
		loadfdt=${conf_fileload} mmc \${mmcdev}:\${mmcpart} ${conf_fdtaddr} /dtbs/\${fdtfile}

		boot_classic=run loadkernel; run loadinitrd
		boot_fdt=run loadkernel; run loadinitrd; run loadfdt

	__EOF__

	if [ "${SERIAL_MODE}" ] ; then
		cat >> ${TEMPDIR}/bootscripts/netinstall.cmd <<-__EOF__
			xyz_message=echo; echo Installer for [${DISTARCH}] is using the Serial Interface; echo;

		__EOF__
	else
		cat >> ${TEMPDIR}/bootscripts/netinstall.cmd <<-__EOF__
			xyz_message=echo; echo Installer for [${DISTARCH}] is using the Video Interface; echo Use [--serial-mode] to force Installing over the Serial Interface; echo;

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
	beagle_bx|beagle_cx|beagle_xm)
		cat >> ${TEMPDIR}/bootscripts/normal.cmd <<-__EOF__
			optargs=VIDEO_CONSOLE
			expansion_args=setenv expansion buddy=\${buddy} buddy2=\${buddy2} camera=\${camera} \${musb}
		__EOF__

		cat >> ${TEMPDIR}/bootscripts/netinstall.cmd <<-__EOF__
			expansion_args=setenv expansion buddy=\${buddy} buddy2=\${buddy2} camera=\${camera} \${musb}
		__EOF__
		;;
	video|bone|bone_dtb|mx6qsabrelite)
		cat >> ${TEMPDIR}/bootscripts/normal.cmd <<-__EOF__
			optargs=VIDEO_CONSOLE
			expansion_args=setenv expansion
		__EOF__

		cat >> ${TEMPDIR}/bootscripts/netinstall.cmd <<-__EOF__
			optargs=${conf_optargs}
			expansion_args=setenv expansion
		__EOF__
		;;
	serial)
		cat >> ${TEMPDIR}/bootscripts/normal.cmd <<-__EOF__
			expansion_args=setenv expansion
		__EOF__

		cat >> ${TEMPDIR}/bootscripts/netinstall.cmd <<-__EOF__
			optargs=${conf_optargs}
			expansion_args=setenv expansion
		__EOF__
		;;
	*)
		cat >> ${TEMPDIR}/bootscripts/normal.cmd <<-__EOF__
			expansion_args=setenv expansion
		__EOF__

		cat >> ${TEMPDIR}/bootscripts/netinstall.cmd <<-__EOF__
			optargs=${conf_optargs}
			expansion_args=setenv expansion
		__EOF__
		;;
	esac

	if [ ! "${need_dtbs}" ] ; then
		cat >> ${TEMPDIR}/bootscripts/normal.cmd <<-__EOF__
			#Classic Board File Boot:
			${conf_entrypt}=run boot_classic; run device_args; ${conf_bootcmd} ${conf_loadaddr} ${conf_initrdaddr}:\${initrd_size}
			#New Device Tree Boot:
			#${conf_entrypt}=run boot_fdt; run device_args; ${conf_bootcmd} ${conf_loadaddr} ${conf_initrdaddr}:\${initrd_size} ${conf_fdtaddr}

		__EOF__

		cat >> ${TEMPDIR}/bootscripts/netinstall.cmd <<-__EOF__
			${conf_entrypt}=run xyz_message; run boot_classic; run device_args; ${conf_bootcmd} ${conf_loadaddr} ${conf_initrdaddr}:\${initrd_size}

		__EOF__
	else
		cat >> ${TEMPDIR}/bootscripts/normal.cmd <<-__EOF__
			#Classic Board File Boot:
			#${conf_entrypt}=run boot_classic; run device_args; ${conf_bootcmd} ${conf_loadaddr} ${conf_initrdaddr}:\${initrd_size}
			#New Device Tree Boot:
			${conf_entrypt}=run boot_fdt; run device_args; ${conf_bootcmd} ${conf_loadaddr} ${conf_initrdaddr}:\${initrd_size} ${conf_fdtaddr}

		__EOF__

		cat >> ${TEMPDIR}/bootscripts/netinstall.cmd <<-__EOF__
			${conf_entrypt}=run xyz_message; run boot_fdt; run device_args; ${conf_bootcmd} ${conf_loadaddr} ${conf_initrdaddr}:\${initrd_size} ${conf_fdtaddr}

		__EOF__
	fi
}

tweak_boot_scripts () {
	unset KMS_OVERRIDE

	if [ "x${ADDON}" = "xpico" ] ; then
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
		if [ "x${ADDON}" = "xpico" ] ; then
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
		sed -i -e 's:UENV_FB::g' ${TEMPDIR}/bootscripts/${ALL}
		sed -i -e 's:UENV_TIMING::g' ${TEMPDIR}/bootscripts/${ALL}

		#optargs=VIDEO_CONSOLE -> optargs=console=tty0
		sed -i -e 's:VIDEO_CONSOLE:console=tty0:g' ${TEMPDIR}/bootscripts/${ALL}

		#video=mxcfb0:dev=hdmi,1280x720@60,if=RGB565
		sed -i -e 's/VIDEO_DISPLAY/'${conf_imx_video}'/g' ${TEMPDIR}/bootscripts/${ALL}

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
			sed -i -e 's:UENV_FB::g' ${TEMPDIR}/bootscripts/${FINAL}
			sed -i -e 's:UENV_TIMING::g' ${TEMPDIR}/bootscripts/${FINAL}

			#optargs=VIDEO_CONSOLE -> optargs=console=tty0
			sed -i -e 's:VIDEO_CONSOLE:console=tty0:g' ${TEMPDIR}/bootscripts/${FINAL}

			#video=mxcfb0:dev=hdmi,1280x720@60,if=RGB565
			sed -i -e 's/VIDEO_DISPLAY/'${conf_imx_video}'/g' ${TEMPDIR}/bootscripts/${FINAL}
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

setup_bootscripts () {
	mkdir -p ${TEMPDIR}/bootscripts/
	boot_uenv_txt_template
	tweak_boot_scripts
}

extract_base_initrd () {
	echo "NetInstall: Extracting Base ${NETINSTALL}"
	cd ${TEMPDIR}/initrd-tree
	zcat "${DIR}/dl/${DISTARCH}/${NETINSTALL}" | cpio -i -d
	dpkg -x "${DIR}/dl/${DISTARCH}/${ACTUAL_DEB_FILE}" ${TEMPDIR}/initrd-tree
	cd "${DIR}/"
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

dl_am335_firmware () {
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

dl_device_firmware () {
	mkdir -p ${TEMPDIR}/firmware/
	DL_WGET="wget --directory-prefix=${TEMPDIR}/firmware/"

	if [ "${need_ti_connectivity_firmware}" ] ; then
		dl_linux_firmware
		echo "-----------------------------"
		echo "Adding Firmware for onboard WiFi/Bluetooth module"
		echo "-----------------------------"
		cp -r "${DIR}/dl/linux-firmware/ti-connectivity" ${TEMPDIR}/firmware/
	fi

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

initrd_add_firmware () {
	DL_WGET="wget --directory-prefix=${TEMPDIR}/firmware/"
	echo ""
	echo "NetInstall: Adding Firmware"
	echo "-----------------------------"

	echo "Adding: Firmware from linux-firmware.git"
	echo "-----------------------------"
	dl_linux_firmware

	#Atheros:
	cp "${DIR}"/dl/linux-firmware/ath3k-1.fw ${TEMPDIR}/initrd-tree/lib/firmware/
	cp -r "${DIR}/dl/linux-firmware/ar3k/" ${TEMPDIR}/initrd-tree/lib/firmware/
	cp "${DIR}/dl/linux-firmware/carl9170-1.fw" ${TEMPDIR}/initrd-tree/lib/firmware/
	cp "${DIR}/dl/linux-firmware/htc_9271.fw" ${TEMPDIR}/initrd-tree/lib/firmware/

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

initrd_cleanup () {
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
	rm -rf ${TEMPDIR}/initrd-tree/lib/modules/*-generic || true
	rm -rf ${TEMPDIR}/initrd-tree/lib/firmware/*-versatile/ || true
}

flash_kernel_base_installer () {
	#All this crap, is just to make "flash-kernel-installer" happy...
	cat > ${TEMPDIR}/initrd-tree/usr/lib/post-base-installer.d/00flash-kernel <<-__EOF__
		#!/bin/sh -e
		#BusyBox: http://linux.die.net/man/1/busybox

		cp /etc/flash-kernel.conf /target/etc/flash-kernel.conf
		zcat /proc/config.gz > /target/boot/config-\$(uname -r)

		mkdir -p /target/boot/uboot || true
		mkdir -p /target/lib/modules/\$(uname -r) || true

		#Some devices may have mmc cards in both slots...
		unset got_boot_drive

		if [ ! \${got_boot_drive} ] ; then
			if [ -b /dev/mmcblk0p1 ] ; then
				mount /dev/mmcblk0p1 /target/boot/uboot
				if [ -f /target/boot/uboot/SOC.sh ] ; then
					got_boot_drive=1
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
				else
					umount /target/boot/uboot
				fi
			fi
		fi

		if [ \${got_boot_drive} ] ; then
			#z = gzip (busybox tar)
			tar -xzv -f /target/boot/uboot/\$(uname -r)-modules.tar.gz -C /target/lib/modules/\$(uname -r)

			mount -o bind /sys /target/sys
			cat /proc/mounts > /target/mounts

			#patch ubuntu's linux-version:
			if [ -f /fixes/linux-version ] ; then
				chroot /target apt-get -y --force-yes install linux-base
				mv /target/usr/bin/linux-version /target/usr/bin/linux-version.broken
				cp /fixes/linux-version /target/usr/bin/linux-version
			fi

			chroot /target update-initramfs -c -k \$(uname -r)
			rm -f /target/mounts || true
			umount /target/sys

			cp /target/boot/uboot/${fki_vmlinuz} /target/boot/${fki_vmlinuz}
			cp /target/boot/initrd.img-\$(uname -r) /target/boot/${fki_initrd}

			#needed with patched linux-version
			cp /target/boot/uboot/${fki_vmlinuz} /target/boot/vmlinuz-\$(uname -r)

			sync
			umount /target/boot/uboot

			export FLASH_KERNEL_SKIP=true
		fi

	__EOF__

	chmod a+x ${TEMPDIR}/initrd-tree/usr/lib/post-base-installer.d/00flash-kernel
}

flash_kernel_broken () {
	cat > ${TEMPDIR}/initrd-tree/fixes/fix_flash-kernel.sh <<-__EOF__
		#!/bin/sh -e

		#WorkAround for: https://bugs.launchpad.net/bugs/1161912
		#after error switch to either: shell/ctrl-alt-f2:
		#/bin/sh /fixes/fix_flash-kernel.sh

		file="/var/lib/dpkg/info/flash-kernel.postinst"
		sed -i 's/update-initramfs -c -k \$latest_version/update-initramfs -c -k \$(uname -r)/g' \${file}

	__EOF__

	chmod a+x ${TEMPDIR}/initrd-tree/fixes/fix_flash-kernel.sh
}

patch_linux_version () {
	cat > ${TEMPDIR}/initrd-tree/fixes/linux-version <<-__EOF__
		#!/bin/sh -e

		/usr/bin/linux-version.broken "\$@"

		#fixme: we could check if [/usr/bin/linux-version.broken list] works:
		echo \$(uname -r)

	__EOF__

	chmod a+x ${TEMPDIR}/initrd-tree/fixes/linux-version
}

finish_installing_device () {
	cat > ${TEMPDIR}/initrd-tree/usr/lib/finish-install.d/08rcn-ee-finish-installing-device <<-__EOF__
		#!/bin/sh -e
		cp /usr/bin/finish-install.sh /target/usr/bin/finish-install.sh
		chmod a+x /target/usr/bin/finish-install.sh

		if [ -f /etc/rcn.conf ]; then
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

		        if [ -d /lib/firmware/ ] ; then
		                cp -rf /lib/firmware/ /target/lib/ || true
		        fi

		        rm -f /etc/rcn.conf

		        mount -o bind /sys /target/sys

		        #Needed by finish-install.sh to determine root file system location
		        cat /proc/mounts > /target/boot/uboot/mounts

		        mkdir -p /target/etc/hwpack/
		        cp /etc/hwpack/SOC.sh /target/etc/hwpack/

		        chroot /target /bin/bash /usr/bin/finish-install.sh

		        rm -f /target/mounts || true

		        cat /proc/mounts > /target/boot/uboot/backup/proc_mounts
		        cat /var/log/syslog > /target/boot/uboot/backup/syslog.log

		        umount /target/sys
		        sync
		        umount /target/boot/uboot
		fi

		rm -rf /target/usr/bin/finish-install.sh || true

	__EOF__

	chmod a+x ${TEMPDIR}/initrd-tree/usr/lib/finish-install.d/08rcn-ee-finish-installing-device
}

setup_parition_recipe () {
	if [ ! "${conf_swapsize_mb}" ] ; then
		conf_swapsize_mb=1024
	fi
	#This (so far) has been leaving the first Partition Alone...
	cat > ${TEMPDIR}/initrd-tree/partition_recipe <<-__EOF__
		        500 1000 -1 ext4
		                method{ format } format{ }
		                use_filesystem{ } filesystem{ ext4 }
		                mountpoint{ / } label{ rootfs }
		                options/noatime{ noatime } .
		 
		        128 1200 ${conf_swapsize_mb} linux-swap
		                method{ swap }
		                format{ } .

	__EOF__
}

initrd_preseed_settings () {
	echo "NetInstall: Adding Distro Tweaks and Preseed Configuration"
	cd ${TEMPDIR}/initrd-tree/
	case "${DIST}" in
	oneiric|precise|quantal)
		cp -v "${DIR}/lib/ubuntu-finish.sh" ${TEMPDIR}/initrd-tree/usr/bin/finish-install.sh
		cp -v "${DIR}/lib/flash_kernel/flash-kernel.conf" ${TEMPDIR}/initrd-tree/etc/flash-kernel.conf
		flash_kernel_base_installer
		;;
	raring|saucy)
		cp -v "${DIR}/lib/ubuntu-finish.sh" ${TEMPDIR}/initrd-tree/usr/bin/finish-install.sh
		cp -v "${DIR}/lib/flash_kernel/flash-kernel.conf" ${TEMPDIR}/initrd-tree/etc/flash-kernel.conf
		flash_kernel_base_installer
		flash_kernel_broken
		patch_linux_version
		;;
	wheezy)
		cp -v "${DIR}/lib/debian-finish.sh" ${TEMPDIR}/initrd-tree/usr/bin/finish-install.sh
		;;
	esac

	finish_installing_device
	setup_parition_recipe
	cp -v "${DIR}/lib/${DIST}-preseed.cfg" ${TEMPDIR}/initrd-tree/preseed.cfg

	cd "${DIR}"/
}

extract_zimage () {
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

initrd_device_settings () {
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
		board=${conf_board}

		bootloader_location=${bootloader_location}
		dd_spl_uboot_seek=${dd_spl_uboot_seek}
		dd_spl_uboot_bs=${dd_spl_uboot_bs}
		dd_uboot_seek=${dd_uboot_seek}
		dd_uboot_bs=${dd_uboot_bs}

		conf_bootcmd=${conf_bootcmd}
		boot_fstype=${conf_boot_fstype}

		serial_tty=${SERIAL}
		loadaddr=${conf_loadaddr}
		initrdaddr=${conf_initrdaddr}
		zreladdr=${conf_zreladdr}
		fdtaddr=${conf_fdtaddr}
		fdtfile=${conf_fdtfile}

		usbnet_mem=${usbnet_mem}

	__EOF__
}

recompress_initrd () {
	echo "NetInstall: Compressing initrd image"
	cd ${TEMPDIR}/initrd-tree/
	find . | cpio -o -H newc | gzip -9 > ${TEMPDIR}/initrd.mod.gz
	cd "${DIR}/"
}

create_custom_netinstall_image () {
	echo ""
	echo "NetInstall: Creating Custom Image"
	echo "-----------------------------"
	mkdir -p ${TEMPDIR}/kernel
	mkdir -p ${TEMPDIR}/initrd-tree/lib/firmware/
	mkdir -p ${TEMPDIR}/initrd-tree/fixes

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

	NUM_MOUNTS=$(mount | grep -v none | grep "$MMC" | wc -l)

##	for (i=1;i<=${NUM_MOUNTS};i++)
	for ((i=1;i<=${NUM_MOUNTS};i++ ))
	do
		DRIVE=$(mount | grep -v none | grep "$MMC" | tail -1 | awk '{print $1}')
		umount ${DRIVE} >/dev/null 2>&1 || true
	done

	echo "Zeroing out Partition Table"
	dd if=/dev/zero of=${MMC} bs=1M count=16 || drive_error_ro
	sync
}

sfdisk_boot_partition () {
	#Generic boot partition created by sfdisk
	echo ""
	echo "Using sfdisk to create BOOT partition"
	echo "-----------------------------"

	LC_ALL=C sfdisk --in-order --Linux --unit M "${MMC}" <<-__EOF__
		${conf_boot_startmb},${conf_boot_endmb},${sfdisk_fstype},*
	__EOF__

	sync
}

dd_uboot_boot () {
	#For: Freescale: i.mx5/6 Devices
	echo ""
	echo "Using dd to place bootloader on drive"
	echo "-----------------------------"
	dd if=${TEMPDIR}/dl/${UBOOT} of=${MMC} seek=${dd_uboot_seek} bs=${dd_uboot_bs}
}

dd_spl_uboot_boot () {
	#For: Samsung: Exynos 4 Devices
	echo ""
	echo "Using dd to place bootloader on drive"
	echo "-----------------------------"
	dd if=${TEMPDIR}/dl/${UBOOT} of=${MMC} seek=${dd_spl_uboot_seek} bs=${dd_spl_uboot_bs}
	dd if=${TEMPDIR}/dl/${UBOOT} of=${MMC} seek=${dd_uboot_seek} bs=${dd_uboot_bs}
	bootloader_installed=1
}

format_partition_error () {
	echo "Failure: formating partition"
	exit
}

format_boot_partition () {
	echo "Formating Boot Partition"
	echo "-----------------------------"
	partprobe ${MMC}
	LC_ALL=C ${mkfs} ${MMC}${PARTITION_PREFIX}1 ${mkfs_label} || format_partition_error
}

create_partitions () {
	unset bootloader_installed

	if [ "x${conf_boot_fstype}" = "xfat" ] ; then
		mount_partition_format="vfat"
		mkfs="mkfs.vfat -F 16"
		mkfs_label="-n ${BOOT_LABEL}"
	else
		mount_partition_format="ext2"
		mkfs="mkfs.ext2"
		mkfs_label="-L ${BOOT_LABEL}"
	fi

	case "${bootloader_location}" in
	fatfs_boot)
		sfdisk_boot_partition
		;;
	dd_uboot_boot)
		dd_uboot_boot
		sfdisk_boot_partition
		;;
	dd_spl_uboot_boot)
		dd_spl_uboot_boot
		sfdisk_boot_partition
		;;
	*)
		sfdisk_boot_partition
		;;
	esac
	format_boot_partition
	echo "Final Created Partition:"
	LC_ALL=C fdisk -l ${MMC}
	echo "-----------------------------"
}

populate_boot () {
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

			if [ "${boot_name}" ] ; then
				if [ -f ${TEMPDIR}/dl/${UBOOT} ] ; then
					cp -v ${TEMPDIR}/dl/${UBOOT} ${TEMPDIR}/disk/${boot_name}
					cp -v ${TEMPDIR}/dl/${UBOOT} ${TEMPDIR}/disk/backup/${boot_name}
					echo "-----------------------------"
				fi
			fi
		fi

		if [ -f ${TEMPDIR}/kernel/boot/vmlinuz-* ] ; then
			LINUX_VER=$(ls ${TEMPDIR}/kernel/boot/vmlinuz-* | awk -F'vmlinuz-' '{print $2}')
			echo "Copying Kernel images:"
			mkimage -A arm -O linux -T kernel -C none -a ${conf_zreladdr} -e ${conf_zreladdr} -n ${LINUX_VER} -d ${TEMPDIR}/kernel/boot/vmlinuz-* ${TEMPDIR}/disk/uImage.net
			cp -v ${TEMPDIR}/kernel/boot/vmlinuz-* ${TEMPDIR}/disk/zImage.net
			cp -v ${TEMPDIR}/kernel/boot/vmlinuz-* ${TEMPDIR}/disk/${fki_vmlinuz}
			echo "-----------------------------"
		fi

		if [ -f ${TEMPDIR}/initrd.mod.gz ] ; then
			#This is 20+ MB in size, just copy one..
			echo "Copying Kernel initrds:"
			if [ ${mkimage_initrd} ] ; then
				mkimage -A arm -O linux -T ramdisk -C none -a 0 -e 0 -n initramfs -d ${TEMPDIR}/initrd.mod.gz ${TEMPDIR}/disk/uInitrd.net
			else
				cp -v ${TEMPDIR}/initrd.mod.gz ${TEMPDIR}/disk/initrd.net
			fi
			echo "-----------------------------"
		fi

		if [ "${ACTUAL_DTB_FILE}" ] ; then
			echo "Copying Device Tree Files:"
			if [ "x${conf_boot_fstype}" = "xfat" ] ; then
				tar xfvo "${DIR}/dl/${DISTARCH}/${ACTUAL_DTB_FILE}" -C ${TEMPDIR}/disk/dtbs
			else
				tar xfv "${DIR}/dl/${DISTARCH}/${ACTUAL_DTB_FILE}" -C ${TEMPDIR}/disk/dtbs
			fi
			cp -v "${DIR}/dl/${DISTARCH}/${ACTUAL_DTB_FILE}" ${TEMPDIR}/disk/
			echo "-----------------------------"
		fi

		if [ "${conf_uboot_bootscript}" ] ; then
			cat > ${TEMPDIR}/bootscripts/loader.cmd <<-__EOF__
				echo "${conf_uboot_bootscript} -> uEnv.txt wrapper..."
				#boundarydevices.com uses disk over mmcdev
				if test -n \$disk; then
					setenv mmcdev \$disk
					setenv mmcpart 1
				fi
				${conf_fileload} mmc \${mmcdev}:\${mmcpart} \${loadaddr} uEnv.txt
				env import -t \${loadaddr} \${filesize}
				run uenvcmd
			__EOF__
			cat ${TEMPDIR}/bootscripts/loader.cmd
			echo "-----------------------------"
			mkimage -A arm -O linux -T script -C none -a 0 -e 0 -n "wrapper" -d ${TEMPDIR}/bootscripts/loader.cmd ${TEMPDIR}/disk/${conf_uboot_bootscript}
			cp -v ${TEMPDIR}/disk/${conf_uboot_bootscript} ${TEMPDIR}/disk/backup/${conf_uboot_bootscript}
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
			board=${conf_board}

			bootloader_location=${bootloader_location}
			dd_spl_uboot_seek=${dd_spl_uboot_seek}
			dd_spl_uboot_bs=${dd_spl_uboot_bs}
			dd_uboot_seek=${dd_uboot_seek}
			dd_uboot_bs=${dd_uboot_bs}

			conf_bootcmd=${conf_bootcmd}
			boot_fstype=${conf_boot_fstype}

			serial_tty=${SERIAL}
			loadaddr=${conf_loadaddr}
			initrdaddr=${conf_initrdaddr}
			zreladdr=${conf_zreladdr}
			fdtaddr=${conf_fdtaddr}
			fdtfile=${conf_fdtfile}

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
	echo "Note: with Ubuntu Releases"
	echo "During Install, after proxy setup, there seems to be a VERY LONG delay..."
	echo "(on average it seems to be taking anywhere between 10-20 Minutes)..."
	echo "In the background: Ubuntu is trying really-really hard to find a compatible kernel..."
	echo "-----------------------------"
	if [ "${conf_note}" ] ; then
		echo ${conf_note}
		echo "-----------------------------"
	fi
	if [ "${conf_note_bootloader}" ] ; then
		echo "This script requires the bootloader to be already installed, see:"
		echo ${conf_note_bootloader}
		echo "-----------------------------"
	fi
	echo "Reporting Bugs:"
	echo "https://github.com/RobertCNelson/netinstall/issues"
	echo "Please include: /var/log/netinstall.log from RootFileSystem"
	echo "-----------------------------"
}

check_mmc () {
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
		unset response
		echo -n "Are you 100% sure, on selecting [${MMC}] (y/n)? "
		read response
		if [ "x${response}" != "xy" ] ; then
			exit
		fi
		echo ""
	else
		echo ""
		echo "Are you sure? I Don't see [${MMC}], here is what I do see..."
		echo ""
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
		exit
	fi
}

uboot_dtb_error () {
		echo "old: --uboot (board file)"
		cat <<-__EOF__
			-----------------------------
			ERROR: This script does not currently recognize the selected: [--uboot ${UBOOT_TYPE}] option..
			Please rerun $(basename $0) with a valid [--uboot <device>] option from the list below:
			-----------------------------
			        TI:
			                beagle_bx - <BeagleBoard Ax/Bx>
			                beagle_cx - <BeagleBoard Cx>
			-----------------------------
		__EOF__

		echo "OR: new: --dtb (device tree) (it's the future)"

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
	echo ${conf_warning}
	echo "-----------------------------"
	echo "Alternate install:"
	echo "http://elinux.org/BeagleBoardUbuntu#Demo_Image"
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

	if [ ! "${conf_boot_fstype}" ] ; then
		echo "Error: [conf_boot_fstype] not defined, stopping..."
		exit
	else
		case "${conf_boot_fstype}" in
		fat)
			sfdisk_fstype="0xE"
			;;
		ext2|ext3|ext4)
			sfdisk_fstype="0x83"
			;;
		*)
			echo "Error: [conf_boot_fstype] not recognized, stopping..."
			exit
			;;
		esac
	fi

	if [ ! "${conf_boot_startmb}" ] ; then
		echo "Warning: [conf_boot_startmb] was undefined setting as: 1"
		conf_boot_startmb="1"
	fi

	if [ ! "${conf_boot_endmb}" ] ; then
		echo "Warning: [conf_boot_endmb] was undefined setting as: 96"
		conf_boot_endmb="96"
	fi

	if [ "${conf_uboot_CONFIG_CMD_BOOTZ}" ] ; then
		conf_bootcmd="bootz"
		conf_normal_kernel_file=zImage
		conf_net_kernel_file=zImage.net
	else
		conf_bootcmd="bootm"
		conf_normal_kernel_file=uImage
		conf_net_kernel_file=uImage.net
	fi

	if [ "${conf_uboot_CONFIG_SUPPORT_RAW_INITRD}" ] ; then
		conf_normal_initrd_file=initrd.img
		conf_net_initrd_file=initrd.net
	else
		mkimage_initrd=1
		conf_normal_initrd_file=uInitrd
		conf_net_initrd_file=uInitrd.net
	fi

	if [ "${conf_uboot_CONFIG_CMD_FS_GENERIC}" ] ; then
		conf_fileload="load"
	else
		if [ "x${conf_boot_fstype}" = "xfat" ] ; then
			conf_fileload="fatload"
		else
			conf_fileload="ext2load"
		fi
	fi

	if [ "${conf_uboot_use_uenvcmd}" ] ; then
		conf_entrypt="uenvcmd"
	else
		conf_entrypt="${conf_uboot_no_uenvcmd}"
	fi
}

check_dtb_board () {
	error_invalid_uboot_dtb=1

	#/hwpack/${dtb_board}.conf
	unset leading_slash
	leading_slash=$(echo ${dtb_board} | grep "/" || unset leading_slash)
	if [ "${leading_slash}" ] ; then
		dtb_board=$(echo "${leading_slash##*/}")
	fi

	#${dtb_board}.conf
	dtb_board=$(echo ${dtb_board} | awk -F ".conf" '{print $1}')
	if [ -f "${DIR}"/hwpack/${dtb_board}.conf ] ; then
		. "${DIR}"/hwpack/${dtb_board}.conf
		populate_dtbs=1
		unset error_invalid_uboot_dtb
		process_dtb_conf
	else
		uboot_dtb_error
		exit
	fi
}

is_omap () {
	IS_OMAP=1

	bootloader_location="fatfs_boot"
	spl_name="MLO"
	boot_name="u-boot.img"

	kernel_subarch="omap"

	conf_loadaddr="0x80300000"
	conf_initrdaddr="0x81600000"
	conf_zreladdr="0x80008000"
	conf_fdtaddr="0x815f0000"

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

convert_uboot_to_dtb_board () {
	populate_dtbs=1
	process_dtb_conf
}

check_uboot_type () {
	#New defines for hwpack:
	conf_bl_http="http://rcn-ee.net/deb/tools/latest"
	conf_bl_listfile="bootloader-ng"

	unset error_invalid_uboot_dtb
	unset USE_KMS
	unset conf_fdtfile
	unset need_dtbs
	kernel_repo="STABLE"

	unset spl_name
	unset boot_name
	unset bootloader_location
	unset dd_spl_uboot_seek
	unset dd_spl_uboot_bs
	unset dd_uboot_seek
	unset dd_uboot_bs

	unset boot_scr_wrapper
	unset usbnet_mem

	case "${UBOOT_TYPE}" in
	beagle_bx)
		. "${DIR}"/hwpack/omap3-beagle-xm.conf
		convert_uboot_to_dtb_board
		SYSTEM="beagle_bx"
		usbnet_mem="8192"
		;;
	beagle_cx)
		. "${DIR}"/hwpack/omap3-beagle-xm.conf
		convert_uboot_to_dtb_board
		SYSTEM="beagle_cx"
		usbnet_mem="8192"
		;;
	beagle_xm)
		echo "Note: [--dtb omap3-beagle-xm] now replaces [--uboot beagle_xm]"
		. "${DIR}"/hwpack/omap3-beagle-xm.conf
		convert_uboot_to_dtb_board
		;;
	bone-serial|bone)
		#Bootloader Partition:
		conf_boot_fstype="fat"
		conf_boot_startmb="1"
		conf_boot_endmb="96"

		need_am335x_firmware="1"
		conf_entrypt="uenvcmd"
		SYSTEM="bone"
		conf_board="BEAGLEBONE_A"
		is_omap
		SERIAL="ttyO0"
		SERIAL_CONSOLE="${SERIAL},115200n8"

		kernel_subarch="omap-psp"

		SERIAL_MODE=1

		unset HAS_OMAPFB_DSS2
		unset KMS_VIDEOA

		#just to disable the omapfb stuff..
		USE_KMS=1
		conf_note="Note: During the install use a 5Volt DC power supply as USB does not always provide enough power. If board locks up on boot run [sudo ifconfig usb0 up] on host."
		conf_uboot_CONFIG_CMD_BOOTZ=1
		conf_uboot_CONFIG_CMD_FS_GENERIC=1
		conf_uboot_use_uenvcmd=1
		convert_uboot_to_dtb_board
		;;
	bone-video)
		#Bootloader Partition:
		conf_boot_fstype="fat"
		conf_boot_startmb="1"
		conf_boot_endmb="96"

		need_am335x_firmware="1"
		conf_entrypt="uenvcmd"
		SYSTEM="bone"
		conf_board="BEAGLEBONE_A"
		is_omap
		SERIAL="ttyO0"
		SERIAL_CONSOLE="${SERIAL},115200n8"

		kernel_subarch="omap-psp"

		unset HAS_OMAPFB_DSS2
		unset KMS_VIDEOA

		#just to disable the omapfb stuff..
		USE_KMS=1
		conf_note="Note: During the install use a 5Volt DC power supply as USB does not always provide enough power. If board locks up on boot run [sudo ifconfig usb0 up] on host."
		conf_uboot_CONFIG_CMD_BOOTZ=1
		conf_uboot_CONFIG_CMD_FS_GENERIC=1
		conf_uboot_use_uenvcmd=1
		convert_uboot_to_dtb_board
		;;
	bone_dt|bone_dtb)
		echo "Note: [--dtb am335x-bone-serial] now replaces [--uboot bone_dtb]"
		. "${DIR}"/hwpack/am335x-bone-serial.conf
		dtb_board="am335x-bone-serial"
		convert_uboot_to_dtb_board
		;;
	panda)
		echo "Note: [--dtb omap4-panda] now replaces [--uboot panda]"
		. "${DIR}"/hwpack/omap4-panda.conf
		convert_uboot_to_dtb_board
		;;
	panda_dtb)
		echo "Note: [--dtb omap4-panda-v3.9-dt] now replaces [--uboot panda_dtb]"
		. "${DIR}"/hwpack/omap4-panda-v3.9-dt.conf
		convert_uboot_to_dtb_board
		;;
	panda_es)
		echo "Note: [--dtb omap4-panda-es] now replaces [--uboot panda_es]"
		. "${DIR}"/hwpack/omap4-panda-es.conf
		convert_uboot_to_dtb_board
		;;
	*)
		error_invalid_uboot_dtb=1
		uboot_dtb_error
		exit
		;;
	esac
}

check_distro () {
	unset IN_VALID_DISTRO
	ARCH="armhf"
	fki_vmlinuz="vmlinuz-"
	fki_initrd="initrd.img-"

	case "${DISTRO_TYPE}" in
	oneiric)
		DIST="oneiric"
		ARCH="armel"
		fki_vmlinuz="vmlinuz"
		fki_initrd="initrd.img"
		;;
	precise|precise-armhf)
		DIST="precise"
		fki_vmlinuz="vmlinuz"
		fki_initrd="initrd.img"
		;;
	quantal|quantal-armhf)
		DIST="quantal"
		;;
	raring|raring-armhf)
		DIST="raring"
		;;
	saucy|saucy-armhf)
		DIST="saucy"
		;;
	wheezy-armel)
		DIST="wheezy"
		ARCH="armel"
		;;
	wheezy-armhf)
		DIST="wheezy"
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
			                wheezy-armel
			                wheezy-armhf <default> (armv7-a)
			        Ubuntu:
			                oneiric (11.10 - End Of Life: April 2013) (armv7-a)
			                precise-armhf (12.04) (armv7-a)
			                quantal (12.10) (armv7-a)
			                raring (13.04) (armv7-a)
			                saucy (13.10) (armv7-a) (beta)
			-----------------------------
		__EOF__
		exit
		;;
	esac
	DISTARCH="${DIST}-${ARCH}"
}

usage () {
	echo "usage: sudo $(basename $0) --mmc /dev/sdX --uboot <dev board>"
	#tabed to match 
		cat <<-__EOF__
			Script Version git: ${GIT_VERSION}
			-----------------------------
			Bugs email: "bugs at rcn-ee.com"

			Required Options:
			--mmc </dev/sdX>

			--dtb <dev board>
			        Freescale:
			                imx51-babbage
			                imx53-qsb
			                imx6q-sabrelite
			                imx6q-sabresd
			        TI:
			                am335x-bone-serial
			                am335x-bone-video
			                am335x-boneblack
			                omap3-beagle-xm
			                omap4-panda
			                omap4-panda-a4
			                omap4-panda-es
			        Wandboard:
			                wandboard-solo
			                wandboard-dl

			Optional:
			--distro <distro>
			        Debian:
			                wheezy-armel
			                wheezy-armhf <default> (armv7-a)
			        Ubuntu:
			                oneiric (11.10 - End Of Life: April 2013) (armv7-a)
			                precise-armhf (12.04) (armv7-a)
			                quantal (12.10) (armv7-a)
			                raring (13.04) (armv7-a)
			                saucy (13.10) (armv7-a) (beta)

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

checkparm () {
	if [ "$(echo $1|grep ^'\-')" ] ; then
		echo "E: Need an argument"
		usage
	fi
}

error_invalid_uboot_dtb=1

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
		unset PARTITION_PREFIX
		echo ${MMC} | grep mmcblk >/dev/null && PARTITION_PREFIX="p"
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

if [ "${error_invalid_uboot_dtb}" ] ; then
	echo "-----------------------------"
	echo "ERROR: --uboot/--dtb undefined"
	echo "-----------------------------"
	uboot_dtb_error
	exit
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

if [ ! "${conf_bootloader_in_flash}" ] ; then
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
