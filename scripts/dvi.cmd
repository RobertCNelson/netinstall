setenv bootcmd 'mmc init; fatload mmc 0:1 0x80300000 uImage; fatload mmc 0:1 0x81600000 uInitrd; bootm 0x80300000 0x81600000'
setenv bootargs console=tty0 root=/dev/ram0 rw omapfb.mode=dvi:1280x720MR-16@60 buddy=${buddy} mpurate=${mpurate}
boot

