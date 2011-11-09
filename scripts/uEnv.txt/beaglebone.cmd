bootfile=uImage.net
address_uimage=0x80007fc0
address_uinitrd=0x80807fc0
bootargs=earlyprintk console=ttyO0,115200n8 root=/dev/ram0 rw
mmc_load_uimage_deb=fatload mmc ${mmc_dev} ${address_uimage} ${bootfile}
mmc_load_uinitrd_deb=fatload mmc ${mmc_dev} ${address_uinitrd} uInitrd.net
mmc_load_uimage=run mmc_load_uimage_deb; run mmc_load_uinitrd_deb; run mmc_args; bootm ${address_uimage} ${address_uinitrd}
