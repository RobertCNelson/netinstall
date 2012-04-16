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
unset DD_UBOOT
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

#13-Apr-2012
#http://ports.ubuntu.com/dists/precise/main/installer-armel/
PRECISE_ARMEL_NETIMAGE="20101020ubuntu133"
PRECISE_ARMEL_MD5SUM="1ccd4aa7e5c6bf1823234bfa0a57906a"

#13-Apr-2012
#http://ports.ubuntu.com/dists/precise/main/installer-armhf/
PRECISE_ARMHF_NETIMAGE="20101020ubuntu133"
PRECISE_ARMHF_MD5SUM="75db27857a1e7600f3a14ba2ac9cac01"

#22-Jan-2012: 6.0.4
#http://ftp.us.debian.org/debian/dists/squeeze/main/installer-armel/
SQUEEZE_NETIMAGE="20110106+squeeze4"
SQUEEZE_MD5SUM="f8d7e14b73c1cb89ff09c79a02694c22"

#http://ftp.us.debian.org/debian/dists/wheezy/main/installer-armel/
#http://ftp.us.debian.org/debian/dists/wheezy/main/installer-armhf/

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

VALID_ADDONS="pico ulcd"

function is_valid_addon {
	if is_element_of $1 "${VALID_ADDONS}" ] ; then
		return 0
	else
		return 1
	fi
}

function check_root {
if [[ $UID -ne 0 ]]; then
 echo "$0 must be run as sudo user or root"
 exit
fi
}

function find_issue {

check_root

#Software Qwerks

#Check for gnu-fdisk
#FIXME: GNU Fdisk seems to halt at "Using /dev/xx" when trying to script it..
if fdisk -v | grep "GNU Fdisk" >/dev/null ; then
 echo "Sorry, this script currently doesn't work with GNU Fdisk"
 exit
fi

unset PARTED_ALIGN
if parted -v | grep parted | grep 2.[1-3] >/dev/null ; then
 PARTED_ALIGN="--align cylinder"
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

	check_for_command mkimage uboot-mkimage
	check_for_command mkfs.vfat dosfstools
	check_for_command wget wget
	check_for_command parted parted
	check_for_command dpkg dpkg
	check_for_command patch patch

	if [ "${NEEDS_COMMAND}" ] ; then
		echo ""
		echo "Your system is missing some dependencies"
		echo "Ubuntu/Debian: sudo apt-get install uboot-mkimage wget dosfstools parted"
		echo "Fedora: as root: yum install uboot-tools wget dosfstools parted dpkg patch"
		echo "Gentoo: emerge u-boot-tools wget dosfstools parted dpkg"
		echo ""
		exit
	fi
}

function rcn-ee_down_use_mirror {
	echo "rcn-ee.net down, switching to slower backup mirror"
	echo "-----------------------------"
	MIRROR=${BACKUP_MIRROR}
	RCNEEDOWN=1
}

function dl_bootloader {
 echo ""
 echo "Downloading Device's Bootloader"
 echo "-----------------------------"

 mkdir -p ${TEMPDIR}/dl/${DISTARCH}
 mkdir -p "${DIR}/dl/${DISTARCH}"

	unset RCNEEDOWN
	echo "attempting to use rcn-ee.net for dl files [10 second time out]..."
	wget -T 10 -t 1 --no-verbose --directory-prefix=${TEMPDIR}/dl/ ${MIRROR}/tools/latest/bootloader

	if [ ! -f ${TEMPDIR}/dl/bootloader ] ; then
		rcn-ee_down_use_mirror
		wget --no-verbose --directory-prefix=${TEMPDIR}/dl/ ${MIRROR}/tools/latest/bootloader
	fi

	if [ "$RCNEEDOWN" ];then
		sed -i -e "s/rcn-ee.net/rcn-ee.homeip.net:81/g" ${TEMPDIR}/dl/bootloader
		sed -i -e 's:81/deb/:81/dl/mirrors/deb/:g' ${TEMPDIR}/dl/bootloader
	fi

 if [ "$USE_BETA_BOOTLOADER" ];then
  ABI="ABX2"
 else
  ABI="ABI2"
 fi

 if [ "${SPL_BOOT}" ] ; then
  MLO=$(cat ${TEMPDIR}/dl/bootloader | grep "${ABI}:${BOOTLOADER}:SPL" | awk '{print $2}')
  wget --no-verbose --directory-prefix=${TEMPDIR}/dl/ ${MLO}
  MLO=${MLO##*/}
  echo "SPL Bootloader: ${MLO}"
 fi

	UBOOT=$(cat ${TEMPDIR}/dl/bootloader | grep "${ABI}:${BOOTLOADER}:BOOT" | awk '{print $2}')
	wget --directory-prefix=${TEMPDIR}/dl/ ${UBOOT}
	UBOOT=${UBOOT##*/}
	echo "UBOOT Bootloader: ${UBOOT}"
}

function dl_kernel_image {
	echo ""
	echo "Downloading Device's Kernel Image"
	echo "-----------------------------"

	KERNEL_SEL="STABLE"

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
	else
		KERNEL=${DEB_FILE}
		#Remove all "\" from file name.
		ACTUAL_DEB_FILE=$(echo ${DEB_FILE} | sed 's!.*/!!' | grep linux-image)
		cp -v ${DEB_FILE} "${DIR}/dl/${DISTARCH}/"
	fi
	echo "Using: ${ACTUAL_DEB_FILE}"
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
 wget --directory-prefix="${DIR}/dl/${DISTARCH}" ${HTTP_IMAGE}/${DIST}/main/installer-${ARCH}/${NETIMAGE}/images/${BASE_IMAGE}/netboot/${NETINSTALL}
 MD5SUM=$(md5sum "${DIR}/dl/${DISTARCH}/${NETINSTALL}" | awk '{print $1}')
 if [ "${UBOOTWRAPPER}" ]; then
  remove_uboot_wrapper
 fi
}

function check_dl_netinstall {
 MD5SUM=$(md5sum "${DIR}/dl/${DISTARCH}/${NETINSTALL}" | awk '{print $1}')
 if [ "=$TEST_MD5SUM=" != "=$MD5SUM=" ]; then
  echo "Note: NetInstall md5sum has changed: $MD5SUM"
  echo "-----------------------------"
  rm -f "${DIR}/dl/${DISTARCH}/${NETINSTALL}" || true
  actually_dl_netinstall
 else
  if [ "${UBOOTWRAPPER}" ]; then
   remove_uboot_wrapper
  fi
 fi
}

function dl_netinstall_image {
 echo ""
 echo "Downloading NetInstall Image"
 echo "-----------------------------"

 unset UBOOTWRAPPER

case "$DISTARCH" in
    maverick-armel)
	TEST_MD5SUM=$MAVERICK_MD5SUM
	NETIMAGE=$MAVERICK_NETIMAGE
	HTTP_IMAGE="http://ports.ubuntu.com/ubuntu-ports/dists"
	BASE_IMAGE="versatile"
	NETINSTALL="initrd.gz"
        ;;
    natty-armel)
	TEST_MD5SUM=$NATTY_MD5SUM
	NETIMAGE=$NATTY_NETIMAGE
	HTTP_IMAGE="http://ports.ubuntu.com/ubuntu-ports/dists"
	BASE_IMAGE="versatile"
	NETINSTALL="initrd.gz"
        ;;
    oneiric-armel)
	TEST_MD5SUM=$ONEIRIC_MD5SUM
	NETIMAGE=$ONEIRIC_NETIMAGE
	HTTP_IMAGE="http://ports.ubuntu.com/ubuntu-ports/dists"
	BASE_IMAGE="linaro-vexpress"
	NETINSTALL="initrd.gz"
        ;;
    precise-armel)
	TEST_MD5SUM=$PRECISE_ARMEL_MD5SUM
	NETIMAGE=$PRECISE_ARMEL_NETIMAGE
	HTTP_IMAGE="http://ports.ubuntu.com/ubuntu-ports/dists"
	BASE_IMAGE="linaro-vexpress"
	NETINSTALL="initrd.gz"
        ;;
    precise-armhf)
	TEST_MD5SUM=$PRECISE_ARMHF_MD5SUM
	NETIMAGE=$PRECISE_ARMHF_NETIMAGE
	HTTP_IMAGE="http://ports.ubuntu.com/ubuntu-ports/dists"
	BASE_IMAGE="omap"
    UBOOTWRAPPER=1
	NETINSTALL="uInitrd"
        ;;
    squeeze-armel)
	TEST_MD5SUM=$SQUEEZE_MD5SUM
	NETIMAGE=$SQUEEZE_NETIMAGE
	HTTP_IMAGE="http://ftp.debian.org/debian/dists"
	BASE_IMAGE="versatile"
	NETINSTALL="initrd.gz"
        ;;
esac

 if [ -f "${DIR}/dl/${DISTARCH}/${NETINSTALL}" ]; then
  check_dl_netinstall
 else
  actually_dl_netinstall
 fi

 echo "md5sum of NetInstall: ${MD5SUM}"
}

function boot_uenv_txt_template {
	#(rcn-ee)in a way these are better then boot.scr
	#but each target is going to have a slightly different entry point..

	if [ ! "${USE_KMS}" ] ; then
		cat > ${TEMPDIR}/bootscripts/netinstall.cmd <<-__EOF__
			UENV_VRAM
			UENV_FB
			UENV_TIMING
		__EOF__

		cat >> ${TEMPDIR}/bootscripts/normal.cmd <<-__EOF__
			UENV_VRAM
			UENV_FB
			UENV_TIMING
		__EOF__
	fi

	if [ ! "${USE_ZIMAGE}" ] ; then
		cat >> ${TEMPDIR}/bootscripts/netinstall.cmd <<-__EOF__
			bootfile=uImage.net
			bootinitrd=uInitrd.net
			boot=bootm
		__EOF__

		cat >> ${TEMPDIR}/bootscripts/normal.cmd <<-__EOF__
			bootfile=uImage
			bootinitrd=uInitrd
			boot=bootm

		__EOF__
	else
		cat >> ${TEMPDIR}/bootscripts/netinstall.cmd <<-__EOF__
			bootfile=zImage.net
			bootinitrd=initrd.net
			boot=bootz
		__EOF__

		cat >> ${TEMPDIR}/bootscripts/normal.cmd <<-__EOF__
			bootfile=zImage
			bootinitrd=initrd.img
			boot=bootz

		__EOF__
	fi

	cat >> ${TEMPDIR}/bootscripts/netinstall.cmd <<-__EOF__
		address_image=IMAGE_ADDR
		address_initrd=INITRD_ADDR

		console=DICONSOLE

		mmcroot=/dev/ram0 rw

		xyz_load_image=fatload mmc 0:1 \${address_image} \${bootfile}
		xyz_load_initrd=fatload mmc 0:1 \${address_initrd} \${bootinitrd}

		xyz_mmcboot=run xyz_load_image; run xyz_load_initrd; echo Booting from mmc ...

		mmcargs=setenv bootargs console=\${console} \${optargs} VIDEO_DISPLAY root=\${mmcroot} \${device_args}

	__EOF__

	cat >> ${TEMPDIR}/bootscripts/normal.cmd <<-__EOF__
		address_image=IMAGE_ADDR
		address_initrd=INITRD_ADDR

		console=SERIAL_CONSOLE

		mmcroot=FINAL_PART ro
		mmcrootfstype=FINAL_FSTYPE rootwait fixrtc

		xyz_load_image=fatload mmc 0:1 \${address_image} \${bootfile}
		xyz_load_initrd=fatload mmc 0:1 \${address_initrd} \${bootinitrd}

		xyz_mmcboot=run xyz_load_image; run xyz_load_initrd; echo Booting from mmc ...

		mmcargs=setenv bootargs console=\${console} \${optargs} VIDEO_DISPLAY root=\${mmcroot} rootfstype=\${mmcrootfstype} \${device_args}

	__EOF__

	case "${SYSTEM}" in
	beagle_bx|beagle_cx)
		cat >> ${TEMPDIR}/bootscripts/netinstall.cmd <<-__EOF__
			deviceargs=setenv device_args mpurate=\${mpurate} buddy=\${buddy} buddy2=\${buddy2} musb_hdrc.fifo_mode=5
			loaduimage=run xyz_mmcboot; run deviceargs; run mmcargs; \${boot} \${address_image} \${address_initrd}:\${filesize}

		__EOF__

		cat >> ${TEMPDIR}/bootscripts/normal.cmd <<-__EOF__
			optargs=VIDEO_CONSOLE
			deviceargs=setenv device_args mpurate=\${mpurate} buddy=\${buddy} buddy2=\${buddy2} musb_hdrc.fifo_mode=5
			loaduimage=run xyz_mmcboot; run deviceargs; run mmcargs; \${boot} \${address_image} \${address_initrd}:\${filesize}

		__EOF__
		;;
	beagle_xm)
		cat >> ${TEMPDIR}/bootscripts/netinstall.cmd <<-__EOF__
			deviceargs=setenv device_args mpurate=\${mpurate} buddy=\${buddy} buddy2=\${buddy2}
			loaduimage=run xyz_mmcboot; run deviceargs; run mmcargs; \${boot} \${address_image} \${address_initrd}:\${filesize}

		__EOF__

		cat >> ${TEMPDIR}/bootscripts/normal.cmd <<-__EOF__
			optargs=VIDEO_CONSOLE
			deviceargs=setenv device_args mpurate=\${mpurate} buddy=\${buddy} buddy2=\${buddy2}
			loaduimage=run xyz_mmcboot; run deviceargs; run mmcargs; \${boot} \${address_image} \${address_initrd}:\${filesize}

		__EOF__
		;;
	crane|igepv2|mx51evk|mx53loco|panda|panda_es)
		cat >> ${TEMPDIR}/bootscripts/netinstall.cmd <<-__EOF__
			deviceargs=setenv device_args
			loaduimage=run xyz_mmcboot; run deviceargs; run mmcargs; \${boot} \${address_image} \${address_initrd}:\${filesize}

		__EOF__

		cat >> ${TEMPDIR}/bootscripts/normal.cmd <<-__EOF__
			optargs=VIDEO_CONSOLE
			deviceargs=setenv device_args
			loaduimage=run xyz_mmcboot; run deviceargs; run mmcargs; \${boot} \${address_image} \${address_initrd}:\${filesize}

		__EOF__
		;;
	bone)
		cat >> ${TEMPDIR}/bootscripts/netinstall.cmd <<-__EOF__
			deviceargs=setenv device_args ip=\${ip_method}
			mmc_load_uimage=run xyz_mmcboot; run bootargs_defaults; run deviceargs; run mmcargs; \${boot} \${address_image} \${address_initrd}

		__EOF__

		cat >> ${TEMPDIR}/bootscripts/normal.cmd <<-__EOF__
			deviceargs=setenv device_args ip=\${ip_method}
			mmc_load_uimage=run xyz_mmcboot; run bootargs_defaults; run deviceargs; run mmcargs; \${boot} \${address_image} \${address_initrd}

		__EOF__
		;;
	bone_zimage)
		cat >> ${TEMPDIR}/bootscripts/netinstall.cmd <<-__EOF__
			deviceargs=setenv device_args ip=\${ip_method}
			mmc_load_uimage=run xyz_mmcboot; run bootargs_defaults; run deviceargs; run mmcargs; \${boot} \${address_image} \${address_initrd}:\${filesize}
			loaduimage=run xyz_mmcboot; run deviceargs; run mmcargs; \${boot} \${address_image} \${address_initrd}:\${filesize}

		__EOF__

		cat >> ${TEMPDIR}/bootscripts/normal.cmd <<-__EOF__
			deviceargs=setenv device_args ip=\${ip_method}
			mmc_load_uimage=run xyz_mmcboot; run bootargs_defaults; run deviceargs; run mmcargs; \${boot} \${address_image} \${address_initrd}:\${filesize}
			loaduimage=run xyz_mmcboot; run deviceargs; run mmcargs; \${boot} \${address_image} \${address_initrd}:\${filesize}


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

	if [ "x${ADDON}" == "xulcd" ] ; then
		VIDEO_TIMING="800x480MR-16@60"
		KMS_OVERRIDE=1
		KMS_VIDEOA="video=DVI-D-1"
		KMS_VIDEO_RESOLUTION="800x480"
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
	#Set kernel boot address
	sed -i -e 's:IMAGE_ADDR:'$IMAGE_ADDR':g' ${TEMPDIR}/bootscripts/${ALL}

	#Set initrd boot address
	sed -i -e 's:INITRD_ADDR:'$INITRD_ADDR':g' ${TEMPDIR}/bootscripts/${ALL}

	#Set the Serial Console
	sed -i -e 's:SERIAL_CONSOLE:'$SERIAL_CONSOLE':g' ${TEMPDIR}/bootscripts/${ALL}

	if [ "${HAS_OMAPFB_DSS2}" ] && [ ! "${SERIAL_MODE}" ] ; then
		#UENV_VRAM -> vram=12MB
		sed -i -e 's:UENV_VRAM:vram=VIDEO_OMAP_RAM:g' ${TEMPDIR}/bootscripts/${ALL}
		sed -i -e 's:VIDEO_OMAP_RAM:'$VIDEO_OMAP_RAM':g' ${TEMPDIR}/bootscripts/${ALL}

		#UENV_FB -> defaultdisplay=dvi
		sed -i -e 's:UENV_FB:defaultdisplay=VIDEO_OMAPFB_MODE:g' ${TEMPDIR}/bootscripts/${ALL}
		sed -i -e 's:VIDEO_OMAPFB_MODE:'$VIDEO_OMAPFB_MODE':g' ${TEMPDIR}/bootscripts/${ALL}

		#UENV_TIMING -> dvimode=1280x720MR-16@60
		sed -i -e 's:UENV_TIMING:dvimode=VIDEO_TIMING:g' ${TEMPDIR}/bootscripts/${ALL}
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
			sed -i -e 's:UENV_VRAM:vram=VIDEO_OMAP_RAM:g' ${TEMPDIR}/bootscripts/${FINAL}
			sed -i -e 's:VIDEO_OMAP_RAM:'$VIDEO_OMAP_RAM':g' ${TEMPDIR}/bootscripts/${FINAL}

			#UENV_FB -> defaultdisplay=dvi
			sed -i -e 's:UENV_FB:defaultdisplay=VIDEO_OMAPFB_MODE:g' ${TEMPDIR}/bootscripts/${FINAL}
			sed -i -e 's:VIDEO_OMAPFB_MODE:'$VIDEO_OMAPFB_MODE':g' ${TEMPDIR}/bootscripts/${FINAL}

			#UENV_TIMING -> dvimode=1280x720MR-16@60
			sed -i -e 's:UENV_TIMING:dvimode=VIDEO_TIMING:g' ${TEMPDIR}/bootscripts/${FINAL}
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

 #Setup serial
 sed -i -e 's:SERIAL:'$SERIAL':g' "${DIR}/scripts/serial.conf"
 sed -i -e 's:SERIAL:'$SERIAL':g' "${DIR}/scripts/ubuntu-tweaks.diff"
 sed -i -e 's:SERIAL:'$SERIAL':g' "${DIR}/scripts/debian-tweaks.diff"

 #Setup Kernel Boot Address
 sed -i -e 's:ZRELADD:'$ZRELADD':g' "${DIR}/scripts/ubuntu-tweaks.diff"
 sed -i -e 's:ZRELADD:'$ZRELADD':g' "${DIR}/scripts/debian-tweaks.diff"
 sed -i -e 's:ZRELADD:'$ZRELADD':g' "${DIR}/scripts/ubuntu-finish.sh"
 sed -i -e 's:ZRELADD:'$ZRELADD':g' "${DIR}/scripts/debian-finish.sh"

 if [ "$SMSC95XX_MOREMEM" ];then
  sed -i 's/8192/16384/g' "${DIR}/scripts/ubuntu-tweaks.diff"
  sed -i 's/8192/16384/g' "${DIR}/scripts/debian-tweaks.diff"
 fi
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
	case "${SYSTEM}" in
	beagle_xm|panda|panda_es)
		dl_linux_firmware
		echo "-----------------------------"
		echo "Adding Firmware for onboard WiFi/Bluetooth module"
		echo "-----------------------------"
		cp -r "${DIR}/dl/linux-firmware/ti-connectivity" ${TEMPDIR}/firmware/
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
	maverick)
		patch -p1 < "${DIR}/scripts/ubuntu-tweaks.diff"
		;;
	natty)
		patch -p1 < "${DIR}/scripts/ubuntu-tweaks.diff"
		;;
	oneiric)
		patch -p1 < "${DIR}/scripts/ubuntu-tweaks.diff"
		;;
	precise)
		patch -p1 < "${DIR}/scripts/ubuntu-tweaks.diff"
		;;
	squeeze)
		patch -p1 < "${DIR}/scripts/debian-tweaks.diff"
		;;
	esac
	cd "${DIR}/"

case "$DIST" in
    maverick)
	 cp -v "${DIR}/scripts/flash-kernel.conf" ${TEMPDIR}/initrd-tree/etc/flash-kernel.conf
	 cp -v "${DIR}/scripts/serial.conf" ${TEMPDIR}/initrd-tree/etc/${SERIAL}.conf
	 chmod a+x ${TEMPDIR}/initrd-tree/usr/lib/finish-install.d/08rcn-ee-finish-installing-device
	 cp -v "${DIR}/scripts/${DIST}-preseed.cfg" ${TEMPDIR}/initrd-tree/preseed.cfg
	 cp -v "${DIR}/scripts/ubuntu-finish.sh" ${TEMPDIR}/initrd-tree/etc/finish-install.sh
        ;;
    natty)
	 cp -v "${DIR}/scripts/flash-kernel.conf" ${TEMPDIR}/initrd-tree/etc/flash-kernel.conf
	 cp -v "${DIR}/scripts/serial.conf" ${TEMPDIR}/initrd-tree/etc/${SERIAL}.conf
	 chmod a+x ${TEMPDIR}/initrd-tree/usr/lib/finish-install.d/08rcn-ee-finish-installing-device
	 cp -v "${DIR}/scripts/${DIST}-preseed.cfg" ${TEMPDIR}/initrd-tree/preseed.cfg
	 cp -v "${DIR}/scripts/ubuntu-finish.sh" ${TEMPDIR}/initrd-tree/etc/finish-install.sh
        ;;
    oneiric)
	 cp -v "${DIR}/scripts/flash-kernel.conf" ${TEMPDIR}/initrd-tree/etc/flash-kernel.conf
	 cp -v "${DIR}/scripts/serial.conf" ${TEMPDIR}/initrd-tree/etc/${SERIAL}.conf
	 chmod a+x ${TEMPDIR}/initrd-tree/usr/lib/finish-install.d/08rcn-ee-finish-installing-device
	 cp -v "${DIR}/scripts/${DIST}-preseed.cfg" ${TEMPDIR}/initrd-tree/preseed.cfg
	 cp -v "${DIR}/scripts/ubuntu-finish.sh" ${TEMPDIR}/initrd-tree/etc/finish-install.sh
        ;;
    precise)
	 cp -v "${DIR}/scripts/flash-kernel.conf" ${TEMPDIR}/initrd-tree/etc/flash-kernel.conf
	 cp -v "${DIR}/scripts/serial.conf" ${TEMPDIR}/initrd-tree/etc/${SERIAL}.conf
	 chmod a+x ${TEMPDIR}/initrd-tree/usr/lib/finish-install.d/08rcn-ee-finish-installing-device
	 cp -v "${DIR}/scripts/${DIST}-preseed.cfg" ${TEMPDIR}/initrd-tree/preseed.cfg
	 cp -v "${DIR}/scripts/ubuntu-finish.sh" ${TEMPDIR}/initrd-tree/etc/finish-install.sh
        ;;
    squeeze)
	 cp -v "${DIR}/scripts/e2fsck.conf" ${TEMPDIR}/initrd-tree/etc/e2fsck.conf
	 chmod a+x ${TEMPDIR}/initrd-tree/usr/lib/finish-install.d/08rcn-ee-finish-installing-device
	 cp -v "${DIR}/scripts/${DIST}-preseed.cfg" ${TEMPDIR}/initrd-tree/preseed.cfg
	 cp -v "${DIR}/scripts/debian-finish.sh" ${TEMPDIR}/initrd-tree/etc/finish-install.sh
        ;;
esac

if [ "$SERIAL_MODE" ];then
 #Squeeze: keymaps aren't an issue with serial mode so disable preseed workaround:
 sed -i -e 's:d-i console-tools:#d-i console-tools:g' ${TEMPDIR}/initrd-tree/preseed.cfg
 sed -i -e 's:d-i debian-installer:#d-i debian-installer:g' ${TEMPDIR}/initrd-tree/preseed.cfg
 sed -i -e 's:d-i console-keymaps-at:#d-i console-keymaps-at:g' ${TEMPDIR}/initrd-tree/preseed.cfg
fi
}

function initrd_fixes {
 echo "NetInstall: Adding Device Tweaks"
 touch ${TEMPDIR}/initrd-tree/etc/rcn.conf

 #work around for the kevent smsc95xx issue
 touch ${TEMPDIR}/initrd-tree/etc/sysctl.conf
 if [ "$SMSC95XX_MOREMEM" ];then
  echo "vm.min_free_kbytes = 16384" >> ${TEMPDIR}/initrd-tree/etc/sysctl.conf
 else
  echo "vm.min_free_kbytes = 8192" >> ${TEMPDIR}/initrd-tree/etc/sysctl.conf
 fi

 if [ "${SERIAL_MODE}" ] ; then
  if [ ! "${DD_UBOOT}" ] ; then
   #this needs more thought, need to disable the check for mx53loco, but maybe we don't need it for omap..
   touch ${TEMPDIR}/initrd-tree/etc/rcn-serial.conf
  fi
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

 parted --script ${MMC} mklabel msdos
}

function uboot_in_boot_partition {
 echo ""
 echo "Using fdisk to create BOOT Partition"
 echo "-----------------------------"
 echo "Debug: now using FDISK_FIRST_SECTOR over fdisk's depreciated method..."

 #With util-linux, 2.18+, the first sector is now 2048...
 FDISK_FIRST_SECTOR="1"
 if test $(fdisk -v | grep -o -E '2\.[0-9]+' | cut -d'.' -f2) -ge 18 ; then
  FDISK_FIRST_SECTOR="2048"
 fi

fdisk ${MMC} << END
n
p
1
${FDISK_FIRST_SECTOR}
+64M
t
e
p
w
END

 sync

 echo "Setting Boot Partition's Boot Flag"
 echo "-----------------------------"
 parted --script ${MMC} set 1 boot on

if [ "$FDISK_DEBUG" ];then
 echo "Debug: Partition 1 layout:"
 echo "-----------------------------"
 fdisk -l ${MMC}
 echo "-----------------------------"
fi
}

function dd_uboot_before_boot_partition {
 echo ""
 echo "Using dd to place bootloader before BOOT Partition"
 echo "-----------------------------"
 dd if=${TEMPDIR}/dl/${UBOOT} of=${MMC} seek=1 bs=1024

 #For now, lets default to fat16, but this could be ext2/3/4
 echo "Using parted to create BOOT Partition"
 echo "-----------------------------"
 parted --script ${PARTED_ALIGN} ${MMC} mkpart primary fat16 10 100
 #parted --script ${PARTED_ALIGN} ${MMC} mkpart primary ext3 10 100
}

function format_boot_partition {
 echo "Formating Boot Partition"
 echo "-----------------------------"
 mkfs.vfat -F 16 ${MMC}${PARTITION_PREFIX}1 -n ${BOOT_LABEL}
}

function create_partitions {

if [ "${DD_UBOOT}" ] ; then
 dd_uboot_before_boot_partition
else
 uboot_in_boot_partition
fi

 format_boot_partition
}

function populate_boot {
	echo "Populating Boot Partition"
	echo "-----------------------------"

	mkdir -p ${TEMPDIR}/disk

	if mount -t vfat ${MMC}${PARTITION_PREFIX}1 ${TEMPDIR}/disk; then

		mkdir -p ${TEMPDIR}/disk/backup
		if [ "${SPL_BOOT}" ] ; then
			if [ -f ${TEMPDIR}/dl/${MLO} ]; then
				cp -v ${TEMPDIR}/dl/${MLO} ${TEMPDIR}/disk/MLO
				cp -v ${TEMPDIR}/dl/${MLO} ${TEMPDIR}/disk/backup/MLO
				echo "-----------------------------"
			fi
		fi

		if [ ! "${DD_UBOOT}" ] ; then
			if [ -f ${TEMPDIR}/dl/${UBOOT} ]; then
				if echo ${UBOOT} | grep img > /dev/null 2>&1;then
					cp -v ${TEMPDIR}/dl/${UBOOT} ${TEMPDIR}/disk/u-boot.img
					cp -v ${TEMPDIR}/dl/${UBOOT} ${TEMPDIR}/disk/backup/u-boot.img
					echo "-----------------------------"
				else
					cp -v ${TEMPDIR}/dl/${UBOOT} ${TEMPDIR}/disk/u-boot.bin
					cp -v ${TEMPDIR}/dl/${UBOOT} ${TEMPDIR}/disk/backup/u-boot.bin
					echo "-----------------------------"
				fi
			fi
		fi

		VMLINUZ="vmlinuz-*"
		UIMAGE="uImage.net"
		if [ -f ${TEMPDIR}/kernel/boot/${VMLINUZ} ] ; then
			LINUX_VER=$(ls ${TEMPDIR}/kernel/boot/${VMLINUZ} | awk -F'vmlinuz-' '{print $2}')
			if [ ! "${USE_ZIMAGE}" ] ; then
				echo "Using mkimage to create uImage"
				mkimage -A arm -O linux -T kernel -C none -a ${ZRELADD} -e ${ZRELADD} -n ${LINUX_VER} -d ${TEMPDIR}/kernel/boot/${VMLINUZ} ${TEMPDIR}/disk/${UIMAGE}
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
			if [ ! "${USE_ZIMAGE}" ] ; then
				echo "Using mkimage to create uInitrd"
				mkimage -A arm -O linux -T ramdisk -C none -a 0 -e 0 -n initramfs -d ${TEMPDIR}/${INITRD} ${TEMPDIR}/disk/${UINITRD}
				echo "-----------------------------"
			else
				echo "Copying Kernel initrd:"
				cp -v ${TEMPDIR}/${INITRD} ${TEMPDIR}/disk/initrd.net
				echo "-----------------------------"
			fi
		fi

		echo "Copying uEnv.txt based boot scripts to Boot Partition"
		echo "Net Install Boot Script:"
		cp -v ${TEMPDIR}/bootscripts/netinstall.cmd ${TEMPDIR}/disk/uEnv.txt
		echo "-----------------------------"
		cat  ${TEMPDIR}/bootscripts/netinstall.cmd
		echo "-----------------------------"
		echo "Normal Boot Script:"
		cp -v ${TEMPDIR}/bootscripts/normal.cmd ${TEMPDIR}/disk/backup/normal.txt
		echo "-----------------------------"
		cat  ${TEMPDIR}/bootscripts/normal.cmd
		echo "-----------------------------"

cp -v "${DIR}/dl/${DISTARCH}/${ACTUAL_DEB_FILE}" ${TEMPDIR}/disk/

cat > ${TEMPDIR}/readme.txt <<script_readme

These can be run from anywhere, but just in case change to "cd /boot/uboot"

Tools:

 "./tools/update_boot_files.sh"

Updated with a custom uImage and modules or modified the boot.cmd/user.com files with new boot args? Run "./tools/update_boot_files.sh" to regenerate all boot files...

Applications:

 "./tools/minimal_xfce.sh"

Install minimal xfce shell, make sure to have network setup: "sudo ifconfig -a" then "sudo dhclient usb1" or "eth0/etc"

Drivers:
 "./build_omapdrm_drivers.sh"

omapdrm kms video driver, at some point this will be packaged by default for newer distro's at that time this script wont be needed...

script_readme

	cat > ${TEMPDIR}/update_boot_files.sh <<-__EOF__
		#!/bin/sh

		if ! id | grep -q root; then
		        echo "must be run as root"
		        exit
		fi

		cd /boot/uboot
		mount -o remount,rw /boot/uboot

		if [ ! -f /boot/initrd.img-\$(uname -r) ] ; then
		        update-initramfs -c -k \$(uname -r)
		else
		        update-initramfs -u -k \$(uname -r)
		fi

		if [ -f /boot/initrd.img-\$(uname -r) ] ; then
		        cp -v /boot/initrd.img-\$(uname -r) /boot/uboot/initrd.img
		fi

		#legacy uImage support:
		if [ -f /boot/uboot/uImage ] ; then
		        if [ -f /boot/initrd.img-\$(uname -r) ] ; then
		                mkimage -A arm -O linux -T ramdisk -C none -a 0 -e 0 -n initramfs -d /boot/initrd.img-\$(uname -r) /boot/uboot/uInitrd
		        fi
		        if [ -f /boot/uboot/boot.cmd ] ; then
		                mkimage -A arm -O linux -T script -C none -a 0 -e 0 -n "Boot Script" -d /boot/uboot/boot.cmd /boot/uboot/boot.scr
		                cp -v /boot/uboot/boot.scr /boot/uboot/boot.ini
		        fi
		        if [ -f /boot/uboot/serial.cmd ] ; then
		                mkimage -A arm -O linux -T script -C none -a 0 -e 0 -n "Boot Script" -d /boot/uboot/serial.cmd /boot/uboot/boot.scr
		        fi
		        if [ -f /boot/uboot/user.cmd ] ; then
		                mkimage -A arm -O linux -T script -C none -a 0 -e 0 -n "Reset Nand" -d /boot/uboot/user.cmd /boot/uboot/user.scr
		        fi
		fi

	__EOF__

cat > ${TEMPDIR}/minimal_xfce.sh <<basic_xfce
#!/bin/sh

sudo apt-get update
if lsb_release -c | grep -E 'oneiric|precise' ; then
sudo apt-get -y install xubuntu-desktop
else
sudo apt-get -y install xfce4 gdm xubuntu-gdm-theme xubuntu-artwork xserver-xorg-video-omap3 network-manager
fi

basic_xfce

	cat > ${TEMPDIR}/xorg.conf <<-__EOF__
		Section "Device"
		        Identifier      "omap"
		        Driver          "omap"
		EndSection

	__EOF__

	cat > ${TEMPDIR}/build_omapdrm_drivers.sh <<-__EOF__
		#!/bin/bash

		#package list from:
		#http://anonscm.debian.org/gitweb/?p=collab-maint/xf86-video-omap.git;a=blob;f=debian/control;hb=HEAD

		sudo apt-get update ; sudo apt-get -y install debhelper dh-autoreconf libdrm-dev libudev-dev libxext-dev pkg-config x11proto-core-dev x11proto-fonts-dev x11proto-gl-dev x11proto-xf86dri-dev xutils-dev xserver-xorg-dev

		if [ ! -f /home/\${USER}/git/xf86-video-omap/.git/config ] ; then
		        git clone git://github.com/robclark/xf86-video-omap.git /home/\${USER}/git/xf86-video-omap/
		fi

		if [ ! -f /home/\${USER}/git/libdrm/.git/config ] ; then
		        git clone git://anongit.freedesktop.org/mesa/drm /home/\${USER}/git/libdrm/
		fi

		DPKG_ARCH=\$(dpkg --print-architecture | grep arm)
		case "\${DPKG_ARCH}" in
		armel)
		        gnu="gnueabi"
		        ;;
		armhf)
		        gnu="gnueabihf"
		        ;;
		esac

		echo ""
		echo "Building omap libdrm"
		echo ""

		cd /home/\${USER}/git/libdrm/
		make distclean &> /dev/null
		git checkout master -f
		git pull
		git branch libdrm-build -D || true
		git checkout 2.4.33 -b libdrm-build

		./autogen.sh --prefix=/usr --libdir=/usr/lib/arm-linux-\${gnu} --disable-libkms --disable-intel --disable-radeon --enable-omap-experimental-api

		make
		sudo make install

		echo ""
		echo "Building omap DDX"
		echo ""

		cd /home/\${USER}/git/xf86-video-omap/
		make distclean &> /dev/null
		git checkout master -f
		git pull
		git branch omap-build -D || true
		git checkout origin/HEAD -b omap-build

		./autogen.sh --prefix=/usr
		make
		sudo make install

		sudo cp /boot/uboot/tools/xorg.conf /etc/X11/xorg.conf

	__EOF__

	cat > ${TEMPDIR}/suspend_mount_debug.sh <<-__EOF__
		#!/bin/bash

		if ! id | grep -q root; then
		        echo "must be run as root"
		        exit
		fi

		mkdir -p /debug
		mount -t debugfs debugfs /debug

	__EOF__

	cat > ${TEMPDIR}/suspend.sh <<-__EOF__
		#!/bin/bash

		if ! id | grep -q root; then
		        echo "must be run as root"
		        exit
		fi

		echo mem > /sys/power/state

	__EOF__

	mkdir -p ${TEMPDIR}/disk/tools
	cp -v ${TEMPDIR}/readme.txt ${TEMPDIR}/disk/tools/readme.txt

	cp -v ${TEMPDIR}/update_boot_files.sh ${TEMPDIR}/disk/tools/update_boot_files.sh
	chmod +x ${TEMPDIR}/disk/tools/update_boot_files.sh

 cp -v ${TEMPDIR}/minimal_xfce.sh ${TEMPDIR}/disk/tools/minimal_xfce.sh
 chmod +x ${TEMPDIR}/disk/tools/minimal_xfce.sh

	cp -v ${TEMPDIR}/xorg.conf ${TEMPDIR}/disk/tools/xorg.conf
	cp -v ${TEMPDIR}/build_omapdrm_drivers.sh ${TEMPDIR}/disk/tools/build_omapdrm_drivers.sh
	chmod +x ${TEMPDIR}/disk/tools/build_omapdrm_drivers.sh

	cp -v ${TEMPDIR}/suspend_mount_debug.sh ${TEMPDIR}/disk/tools/
	chmod +x ${TEMPDIR}/disk/tools/suspend_mount_debug.sh

	cp -v ${TEMPDIR}/suspend.sh ${TEMPDIR}/disk/tools/
	chmod +x ${TEMPDIR}/disk/tools/suspend.sh

cd ${TEMPDIR}/disk
sync
cd "${DIR}/"

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
}

function reset_scripts {

 #Setup serial
 sed -i -e 's:'$SERIAL':SERIAL:g' "${DIR}/scripts/serial.conf"
 sed -i -e 's:'$SERIAL':SERIAL:g' "${DIR}/scripts/ubuntu-tweaks.diff"
 sed -i -e 's:'$SERIAL':SERIAL:g' "${DIR}/scripts/debian-tweaks.diff"

 #Setup Kernel Boot Address
 sed -i -e 's:'$ZRELADD':ZRELADD:g' "${DIR}/scripts/ubuntu-tweaks.diff"
 sed -i -e 's:'$ZRELADD':ZRELADD:g' "${DIR}/scripts/debian-tweaks.diff"
 sed -i -e 's:'$ZRELADD':ZRELADD:g' "${DIR}/scripts/ubuntu-finish.sh"
 sed -i -e 's:'$ZRELADD':ZRELADD:g' "${DIR}/scripts/debian-finish.sh"

 if [ "$SMSC95XX_MOREMEM" ];then
  sed -i 's/16384/8192/g' "${DIR}/scripts/ubuntu-tweaks.diff"
  sed -i 's/16384/8192/g' "${DIR}/scripts/debian-tweaks.diff"
 fi

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
	SPL_BOOT=1
	SUBARCH="omap"

	IMAGE_ADDR="0x80300000"
	INITRD_ADDR="0x81600000"

	ZRELADD="0x80008000"

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
	SERIAL_CONSOLE="${SERIAL},115200"
	SUBARCH="imx"

	VIDEO_CONSOLE="console=tty0"
	HAS_IMX_BLOB=1v
	VIDEO_FB="mxcdi1fb"
	VIDEO_TIMING="RGB24,1280x720M@60"
}

function check_uboot_type {
	unset SPL_BOOT
	unset DO_UBOOT
	unset IN_VALID_UBOOT
	unset SMSC95XX_MOREMEM
	unset USE_ZIMAGE
	unset USE_KMS

	case "${UBOOT_TYPE}" in
	beagle_bx)
		SYSTEM="beagle_bx"
		DO_UBOOT=1
		BOOTLOADER="BEAGLEBOARD_BX"
		SERIAL="ttyO2"
		is_omap
		USE_ZIMAGE=1
		echo "-----------------------------"
		echo "Warning: Support for the Original BeagleBoard Ax/Bx is broken.. (board locks up during hardware detect)"
		echo "Please use the Demo Images Instead"
		echo "-----------------------------"
		;;
	beagle_cx)
		SYSTEM="beagle_cx"
		DO_UBOOT=1
		BOOTLOADER="BEAGLEBOARD_CX"
		SERIAL="ttyO2"
		is_omap
		USE_ZIMAGE=1
		echo "-----------------------------"
		echo "Warning: Support for the BeagleBoard C1/C2 is broken.. (board locks up during hardware detect)"
		echo "Please use the Demo Images Instead"
		echo "BeagleBoard: C4/C5 Users, can ignore this message.."
		echo "-----------------------------"
		;;
	beagle_xm)
		SYSTEM="beagle_xm"
		DO_UBOOT=1
		BOOTLOADER="BEAGLEBOARD_XM"
		SERIAL="ttyO2"
		is_omap
		USE_ZIMAGE=1
		;;
	beagle_xm_kms)
		SYSTEM="beagle_xm"
		DO_UBOOT=1
		BOOTLOADER="BEAGLEBOARD_XM"
		SERIAL="ttyO2"
		is_omap
		USE_ZIMAGE=1

		USE_KMS=1
		unset HAS_OMAPFB_DSS2

		BETA_KERNEL=1
		;;
	bone)
		SYSTEM="bone"
		DO_UBOOT=1
		BOOTLOADER="BEAGLEBONE_A"
		SERIAL="ttyO0"
		is_omap

		SUBARCH="omap-psp"

		SERIAL_MODE=1

		unset HAS_OMAPFB_DSS2
		unset KMS_VIDEOA
		;;
	bone_zimage)
		SYSTEM="bone_zimage"
		DO_UBOOT=1
		BOOTLOADER="BEAGLEBONE_A"
		SERIAL="ttyO0"
		is_omap
		USE_ZIMAGE=1

		USE_BETA_BOOTLOADER=1

		SUBARCH="omap-psp"

		SERIAL_MODE=1

		unset HAS_OMAPFB_DSS2
		unset KMS_VIDEOA
		;;
	igepv2)
		SYSTEM="igepv2"
		DO_UBOOT=1
		BOOTLOADER="IGEP00X0"
		SERIAL="ttyO2"
		is_omap
		USE_ZIMAGE=1

		SERIAL_MODE=1
		;;
	panda)
		SYSTEM="panda"
		DO_UBOOT=1
		BOOTLOADER="PANDABOARD"
		SMSC95XX_MOREMEM=1
		SERIAL="ttyO2"
		is_omap
		USE_ZIMAGE=1
		VIDEO_OMAP_RAM="16MB"
		KMS_VIDEOB="video=HDMI-A-1"
		;;
	panda_es)
		SYSTEM="panda_es"
		DO_UBOOT=1
		BOOTLOADER="PANDABOARD_ES"
		SMSC95XX_MOREMEM=1
		SERIAL="ttyO2"
		is_omap
		USE_ZIMAGE=1
		VIDEO_OMAP_RAM="16MB"
		KMS_VIDEOB="video=HDMI-A-1"
		;;
	panda_kms)
		SYSTEM="panda_es"
		DO_UBOOT=1
		BOOTLOADER="PANDABOARD_ES"
		SMSC95XX_MOREMEM=1
		SERIAL="ttyO2"
		is_omap
		USE_ZIMAGE=1

		USE_KMS=1
		unset HAS_OMAPFB_DSS2
		KMS_VIDEOB="video=HDMI-A-1"

		BETA_KERNEL=1
		;;
	crane)
		SYSTEM="crane"
		DO_UBOOT=1
		BOOTLOADER="CRANEBOARD"
		SERIAL="ttyO2"
		is_omap
		USE_ZIMAGE=1

		BETA_KERNEL=1
		SERIAL_MODE=1
		;;
	mx51evk)
		SYSTEM="mx51evk"
		DO_UBOOT=1
		DD_UBOOT=1
		BOOTLOADER="MX51EVK"
		SERIAL="ttymxc0"
		is_imx
		USE_ZIMAGE=1
		ZRELADD="0x90008000"
		IMAGE_ADDR="0x90800000"
		INITRD_ADDR="0x92100000"
		BETA_KERNEL=1
		SERIAL_MODE=1
		;;
	mx53loco)
		SYSTEM="mx53loco"
		DO_UBOOT=1
		DD_UBOOT=1
		BOOTLOADER="MX53LOCO"
		SERIAL="ttymxc0"
		is_imx
		USE_ZIMAGE=1
		ZRELADD="0x70008000"
		IMAGE_ADDR="0x70800000"
		INITRD_ADDR="0x72100000"
		BETA_KERNEL=1
		SERIAL_MODE=1
		;;
	*)
		IN_VALID_UBOOT=1
		cat <<-__EOF__
			-----------------------------
			ERROR: This script does not currently recognize the selected: [--uboot ${UBOOT_TYPE}] option..
			Please rerun $(basename $0) with a valid [--uboot <device>] option from the list below:
			-----------------------------
			-Supported TI Devices:-------
			beagle_bx - <BeagleBoard Ax/Bx>
			beagle_cx - <BeagleBoard Cx>
			beagle_xm - <BeagleBoard xMA/B/C>
			bone - <BeagleBone Ax>
			igepv2 - <serial mode only>
			panda - <PandaBoard Ax>
			panda_es - <PandaBoard ES>
			-Supported Freescale Devices:
			mx53loco - <Quick Start Board>
			-----------------------------
		__EOF__
		exit
		;;
	esac
}

function check_distro {
	unset IN_VALID_DISTRO

	case "${DISTRO_TYPE}" in
	natty)
		DIST=natty
		ARCH=armel
		;;
	maverick)
		DIST=maverick
		ARCH=armel
		;;
	oneiric)
		DIST=oneiric
		ARCH=armel
		;;
	precise-armel)
		DIST=precise
		ARCH=armel
		;;
	precise-armhf)
		DIST=precise
		ARCH=armhf
		;;
	squeeze)
		DIST=squeeze
		ARCH=armel
		;;
	*)
		IN_VALID_DISTRO=1
		usage
		;;
	esac

	DISTARCH="${DIST}-${ARCH}"
}

function usage {
    echo "usage: sudo $(basename $0) --mmc /dev/sdX --uboot <dev board>"
cat <<EOF

Script Version git: ${GIT_VERSION}
-----------------------------
Bugs email: "bugs at rcn-ee.com"

Required Options:
--mmc </dev/sdX>

--uboot <dev board>
    (omap)
    beagle_cx - <BeagleBoard C4/C5>
    beagle_xm - <BeagleBoard xMA/B/C>
    bone - <BeagleBone Ax>
    igepv2 - <serial mode only>
    panda - <PandaBoard Ax>
    panda_es - <PandaBoard ES>

    (freescale)
    mx53loco

Optional:
--distro <distro>
    Debian:
      squeeze <default>
    Ubuntu
      maverick (10.10 - End Of Life: April 2012)
      natty (11.04 - End Of Life: October 2012)
      oneiric (11.10 - End Of Life: April 2013)
      precise-armel (12.04)
      precise-armhf (12.04)

--addon <additional peripheral device>
    pico
    ulcd <beagle xm>

--firmware
    Add distro firmware

--serial-mode
    <force the Installer to use the serial port over the dvi/video outputs>

--svideo-ntsc
    force ntsc mode for svideo

--svideo-pal
    force pal mode for svideo

Additional Options:
-h --help
    this help

--probe-mmc
    List all partitions: sudo ./mk_mmc.sh --probe-mmc

Debug:

EOF
exit
}

function checkparm {
    if [ "$(echo $1|grep ^'\-')" ];then
        echo "E: Need an argument"
        usage
    fi
}

IN_VALID_UBOOT=1

# parse commandline options
while [ ! -z "$1" ]; do
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
	    if [[ "${MMC}" =~ "mmcblk" ]]
            then
	        PARTITION_PREFIX="p"
            fi
            find_issue
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

if [ "$IN_VALID_UBOOT" ] ; then
	echo "ERROR: --uboot undefined"
	usage
fi

if [ -n "${ADDON}" ] ; then
	if ! is_valid_addon ${ADDON} ; then
		echo "ERROR: ${ADDON} is not a valid addon type"
		echo "-----------------------------"
		echo "Supported --addon options:"
		echo "    pico"
		echo "    ulcd <for the beagleboard xm>"
		exit
	fi
fi

 echo ""
 echo "Script Version git: ${GIT_VERSION}"
 echo "-----------------------------"

 find_issue
 detect_software
 dl_bootloader
 dl_kernel_image
 dl_netinstall_image

dl_device_firmware

 setup_bootscripts
 create_custom_netinstall_image

 unmount_all_drive_partitions
 create_partitions
 populate_boot
 reset_scripts

