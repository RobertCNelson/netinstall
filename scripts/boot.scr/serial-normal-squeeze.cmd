echo "Debug: Squeeze Serial"
setenv bootcmd 'fatload mmc 0:1 UIMAGE_ADDR uImage; fatload mmc 0:1 UINITRD_ADDR uInitrd; bootm UIMAGE_ADDR UINITRD_ADDR'
setenv bootargs console=SERIAL_CONSOLE root=/dev/mmcblk0p5 ro buddy=${buddy} mpurate=${mpurate}
boot

