setenv bootcmd 'mmc init; fatload mmc 0:1 0x80000000 uImage; fatload mmc 0:1 0x81600000 uInitrd; bootm 0x80000000 0x81600000'
setenv bootargs 'console=ttyS2,115200n8 root=/dev/mmcblk0p5 ro fixrtc'
boot

