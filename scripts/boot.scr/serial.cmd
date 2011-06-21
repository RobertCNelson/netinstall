echo "Debug: running debian netinstall"
setenv bootcmd 'fatload mmc 0:1 UIMAGE_ADDR uImage.net; fatload mmc 0:1 UINITRD_ADDR uInitrd.net; bootm UIMAGE_ADDR UINITRD_ADDR'
setenv bootargs console=SERIAL_CONSOLE root=/dev/ram0 rw buddy=${buddy} mpurate=${mpurate}
boot

