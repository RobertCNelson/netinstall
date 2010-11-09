echo "Debug: NetInstall"
if test "${beaglerev}" = "xMA"; then
echo "Kernel is not ready for 1Ghz limiting to 800Mhz"
setenv mpurate 800
fi
if test "${beaglerev}" = "xMB"; then
echo "Kernel is not ready for 1Ghz limiting to 800Mhz"
setenv mpurate 800
fi
setenv dvimode 1280x720MR-16@60
setenv vram 12MB
setenv bootcmd 'mmc init; fatload mmc 0:1 0x80300000 uImage; fatload mmc 0:1 0x81600000 uInitrd; bootm 0x80300000 0x81600000'
setenv bootargs console=tty0 root=/dev/ram0 rw vram=${vram} omapfb.mode=dvi:${dvimode} buddy=${buddy} mpurate=${mpurate}
boot

