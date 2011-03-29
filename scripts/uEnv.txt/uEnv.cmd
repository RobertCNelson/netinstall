bootenv=boot.scr
loaduimage=fatload mmc ${mmcdev} ${loadaddr} ${bootenv}
mmcboot=echo Running boot.scr script from mmc ...; source ${loadaddr}
