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

#配置系统时间,地区和语言
configure_system(){
	print_title "configure_system"
	ln -sf /usr/share/zoneinfo/Asia/Shanghai /etc/localtime
	hwclock --systohc --utc
	echo "en_US.UTF-8 UTF-8" >> /mnt/etc/locale.gen
	echo "zh_CN.UTF-8 UTF-8" >> /mnt/etc/locale.gen
	locale-gen
	echo "LANG=en_US.UTF-8" > /mnt/etc/locale.conf
}

#安装驱动程序
configrue_drive(){
	print_title "configrue_drive"
        pacman -S --noconfirm xorg-server xorg-twm xorg-xclock xorg-server -y
	pacman -S --noconfirm bumblebee -y
        systemctl enable bumblebeed
        pacman -S --noconfirm nvidia xf86-input-synaptics -y       
        pacman -S --noconfirm nvidia linux-lts intel-ucode linux-headers -y
}

#安装网络管理程序
configrue_networkmanager(){
       print_title "configrue_networkmanager"
       pacman -S --noconfirm iw wireless_tools wpa_supplicant dialog netctl networkmanager networkmanager-openconnect rp-pppoe network-manager-applet net-tools -y
       systemctl enable NetworkManager.service      
}


#添加本地域名
configure_hostname(){
	print_title "configure_hostname"
	read -p "Hostname [ex: archlinux]: " host_name
	echo "$host_name" > /etc/hostname
	if [[ ! -f /etc/hosts.aui ]]; then
	cp /etc/hosts /etc/hosts.aui
	else
	cp /etc/hosts.aui /etc/hosts
	fi
	sed -i '/127.0.0.1/s/$/ '${host_name}'/' /etc/hosts
	sed -i '/::1/s/$/ '${host_name}'/' /etc/hosts
	passwd
  }
  
#添加本地域名
configure_username(){
        print_title "configure_username"
        read -p "Username [ex: archlinux]: " User
        pacman -S --noconfirm sudo zsh -y
        useradd -m -g users -G wheel -s /bin/zsh $User
        passwd $User
        sed -i 's/\# \%wheel ALL=(ALL) ALL/\%wheel ALL=(ALL) ALL/g' /etc/sudoers
	sed -i 's/\# \%wheel ALL=(ALL) NOPASSWD: ALL/\%wheel ALL=(ALL) NOPASSWD: ALL/g' /etc/sudoers
	print_title "install has been.please reboot ."
}



configure_system
configrue_drive
configrue_networkmanager
configure_hostname
configure_username
