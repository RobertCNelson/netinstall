echo "Debug: running debian netinstall"
setenv dvimode 1280x720MR-16@60
setenv vram 12MB
setenv bootcmd 'fatload mmc 0:1 UIMAGE_ADDR uImage.net; fatload mmc 0:1 UINITRD_ADDR uInitrd.net; bootm UIMAGE_ADDR UINITRD_ADDR'
setenv bootargs console=tty0 root=/dev/ram0 rw vram=${vram} omapfb.mode=dvi:${dvimode} buddy=${buddy} mpurate=${mpurate}
boot

