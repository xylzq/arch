#!/bin/bash

print_line() {
	printf "%$(tput cols)s\n"|tr ' ' '-'
}

print_title() {
	clear
	print_line
	echo -e "# ${Bold}$1${Reset}"
	print_line
	echo ""
}


#替换仓库列表
update_mirrorlist(){
	print_title "update_mirrorlist"
	tmpfile=$(mktemp --suffix=-mirrorlist)	
	url="https://www.archlinux.org/mirrorlist/?country=CN&protocol=http&protocol=https&ip_version=4"
	curl -so ${tmpfile} ${url} 
	sed -i 's/^#Server/Server/g' ${tmpfile}
	mv -f ${tmpfile} /etc/pacman.d/mirrorlist;
        pacman -Syy --noconfirm
}
#开始分区
create_partitions(){
	print_title "create_partitions"
	lvcreate -L 525M lv -n boot
	lvcreate -L 8G lv -n swap
	lvcreate -l +100%FREE lv -n root
}
#开始格式化
format_partitions(){
	print_title "format_partitions"
        modprobe dm-mod
        vgscan
        vgchange -ay
	mkfs.vfat -F32 /dev/mapper/lv-boot 
	mkswap /dev/mapper/lv-swap 
	mkfs.ext4 /dev/mapper/lv-root 
}
#挂载分区
mount_partitions(){
	print_title "mount_partitions"
	mount /dev/mapper/lv-root /mnt
        swapon /dev/mapper/lv-swap
        mkdir /mnt/boot
	mount /dev/mapper/lv-boot /mnt/boot
	lsblk
