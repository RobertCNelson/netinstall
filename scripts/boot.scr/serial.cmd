echo "Debug: running debian netinstall"
setenv bootcmd 'fatload mmc 0:1 0x80300000 uImage.net; fatload mmc 0:1 0x81600000 uInitrd.net; bootm 0x80300000 0x81600000'
setenv bootargs console=ttyO2,115200n8 root=/dev/ram0 rw buddy=${buddy} mpurate=${mpurate}
boot

