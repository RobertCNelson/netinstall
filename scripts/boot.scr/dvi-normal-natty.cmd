echo "Debug: Natty DVI"
setenv dvimode 1280x720MR-16@60
setenv vram 12MB
setenv bootcmd 'fatload mmc 0:1 UIMAGE_ADDR uImage; fatload mmc 0:1 UINITRD_ADDR uInitrd; bootm UIMAGE_ADDR UINITRD_ADDR'
setenv bootargs console=SERIAL_CONSOLE console=tty0 root=/dev/mmcblk0p5 ro vram=${vram} omapfb.mode=dvi:${dvimode} fixrtc buddy=${buddy} mpurate=${mpurate}
boot

