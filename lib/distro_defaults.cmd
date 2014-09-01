echo ; echo Searching for: /boot/uEnv.txt ...;
for i in 1 2 3 4 5 6 7 ; do
	setenv bootpart ${i};
	echo Trying: ${devtype} ${devnum}:${bootpart} ...;
	if test -e ${devtype} ${devnum}:${bootpart} /boot/uEnv.txt; then
		echo Found: /boot/uEnv.txt on [${devtype} ${devnum}:${bootpart}] ...;
		load ${devtype} ${devnum}:${bootpart} ${scriptaddr} /boot/uEnv.txt
		env import -t ${scriptaddr} ${filesize}

		if test -n ${dtb}; then
			setenv fdtfile ${dtb};
			echo Using: [dtb=${fdtfile}] ...;
		fi;

		if test -n ${uname_r}; then
			echo Using: [uname_r=${uname_r}] ...;
		fi;

		if test -n ${uuid}; then
			echo Using: [uuid=${uuid}] ...;
		else
			echo Warning: [uuid] is not set in /boot/uEnv.txt ...;
			echo Using: [root=${mmcroot} ro] ...;
		fi;

		if test -n ${uname_r}; then
			setenv bootdir /boot;
			setenv bootfile vmlinuz-${uname_r};
			echo ; echo Searching for: Linux Kernel [vmlinuz-${uname_r}] ...;
			echo Trying: ${bootdir}/${bootfile} ...;
			if test -e ${devtype} ${devnum}:${bootpart} ${bootdir}/${bootfile}; then
				echo Found: ${bootdir}/${bootfile} ...;
				load ${devtype} ${devnum}:${bootpart} ${kernel_addr_r} ${bootdir}/${bootfile}
				echo ; echo Searching for: Device Tree Blob [${fdtfile}] ...;
				setenv fdtdir /boot/dtbs/${uname_r};
				echo Trying: ${fdtdir}/${fdtfile} ...;
				if test -e ${devtype} ${devnum}:${bootpart} ${fdtdir}/${fdtfile}; then
					echo Found: ${fdtdir}/${fdtfile} ...;
					load ${devtype} ${devnum}:${bootpart} ${fdt_addr_r} ${fdtdir}/${fdtfile}
				else
					setenv fdtdir /usr/lib/linux-image-${uname_r};
					echo Trying: ${fdtdir}/${fdtfile} ...;
					if test -e ${devtype} ${devnum}:${bootpart} ${fdtdir}/${fdtfile}; then
						echo Found: ${fdtdir}/${fdtfile} ...;
						load ${devtype} ${devnum}:${bootpart} ${fdt_addr_r} ${fdtdir}/${fdtfile}
					else
						setenv fdtdir /lib/firmware/${uname_r}/device-tree;
						echo Trying: ${fdtdir}/${fdtfile} ...;
						if test -e ${devtype} ${devnum}:${bootpart} ${fdtdir}/${fdtfile}; then
							echo Found: ${fdtdir}/${fdtfile} ...;
							load ${devtype} ${devnum}:${bootpart} ${fdt_addr_r} ${fdtdir}/${fdtfile}
						else
							setenv fdtdir /boot/dtb-${uname_r};
							echo Trying: ${fdtdir}/${fdtfile} ...;
							if test -e ${devtype} ${devnum}:${bootpart} ${fdtdir}/${fdtfile}; then
								echo Found: ${fdtdir}/${fdtfile} ...;
								load ${devtype} ${devnum}:${bootpart} ${fdt_addr_r} ${fdtdir}/${fdtfile}
							fi
						fi;
					fi;
				fi;
				setenv rdfile initrd.img-${uname_r};
				echo ; echo Searching for: Linux initial RAM disk [initrd.img-${uname_r}] ...;
				echo Trying: ${bootdir}/${rdfile} ...;
				if test -e ${devtype} ${devnum}:${bootpart} ${bootdir}/${rdfile}; then
					echo Found: ${bootdir}/${rdfile} ...;
					load ${devtype} ${devnum}:${bootpart} ${ramdisk_addr_r} ${bootdir}/${rdfile}; setenv initrd_size ${filesize}
					if test -n ${uuid}; then
						setenv root UUID=${uuid} ro;
					fi;
					if test -n ${mmcargs}; then
						run mmcargs;
					fi;
					if test -n ${set_boot_args}; then
						run set_boot_args;
					fi;
					echo debug: [${bootargs}] ... ;
					echo debug: [bootz ${kernel_addr_r} ${ramdisk_addr_r}:${initrd_size} ${fdt_addr_r}] ... ;
					bootz ${kernel_addr_r} ${ramdisk_addr_r}:${initrd_size} ${fdt_addr_r}
				else
					echo Not using Linux initial RAM disk: [initrd.img-${uname_r}] ...;
					if test -n ${mmcargs}; then
						run mmcargs;
					fi;
					if test -n ${set_boot_args}; then
						run set_boot_args;
					fi;
					echo debug: [${bootargs}] ... ;
					echo debug: [bootz ${kernel_addr_r} - ${fdt_addr_r}] ... ;
					bootz ${kernel_addr_r} - ${fdt_addr_r}
				fi;
			fi;
		fi;
	fi;
done;

