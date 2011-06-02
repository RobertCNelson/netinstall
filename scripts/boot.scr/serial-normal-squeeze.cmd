echo "Debug: Squeeze Serial"
if test "${beaglerev}" = "xMA"; then
echo "Kernel is not ready for 1Ghz limiting to 800Mhz"
setenv mpurate 800
fi
if test "${beaglerev}" = "xMB"; then
echo "Kernel is not ready for 1Ghz limiting to 800Mhz"
setenv mpurate 800
fi
if test "${beaglerev}" = "xMC"; then
echo "Kernel is not ready for 1Ghz limiting to 800Mhz"
setenv mpurate 800
fi
setenv bootcmd 'fatload mmc 0:1 0x80300000 uImage; fatload mmc 0:1 0x81600000 uInitrd; bootm 0x80300000 0x81600000'
setenv bootargs console=ttyO2,115200n8 root=/dev/mmcblk0p5 ro buddy=${buddy} mpurate=${mpurate}
boot

