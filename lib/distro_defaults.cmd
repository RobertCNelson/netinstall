echo "distro_defaults: boot.scr/uEnv.txt wrapper..."
load ${devtype} ${devnum}:${bootpart} ${scriptaddr} /boot/uEnv.txt
env import -t ${scriptaddr} ${filesize}
run uenvcmd
