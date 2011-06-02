echo "Debug: running debian netinstall"
setenv dvimode 1280x720MR-16@60
setenv vram 12MB
setenv bootcmd 'fatload mmc 0:1 0x80300000 uImage.net; fatload mmc 0:1 0x81600000 uInitrd.net; bootm 0x80300000 0x81600000'
setenv bootargs console=tty0 root=/dev/ram0 rw vram=${vram} omapfb.mode=dvi:${dvimode} buddy=${buddy} mpurate=${mpurate}
boot

