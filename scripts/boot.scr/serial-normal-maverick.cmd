echo "Debug: Maverick Serial"
setenv bootcmd 'fatload mmc 0:1 UIMAGE_ADDR uImage; fatload mmc 0:1 UINITRD_ADDR uInitrd; bootm UIMAGE_ADDR UINITRD_ADDR'
setenv bootargs console=ttyO2,115200n8 root=/dev/mmcblk0p5 ro fixrtc buddy=${buddy} mpurate=${mpurate}
boot

