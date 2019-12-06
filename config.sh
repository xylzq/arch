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

 #配置汉化
configure_Chinese(){
	print_title "configure_Chinese"
        pacman -S archlinuxcn-keyring
        echo "[archlinuxcn]\nServer = https://mirrors.tuna.tsinghua.edu.cn/archlinuxcn/\$arch" >> /etc/pacman.conf
        pacman -Syy
        pacman -S --noconfirm archlinuxcn-keyring -y
        sed -i 's/\# \[multilib]/\[multilib]/g' /etc/pacman.conf
        sed -i 's/\# \Include = /etc/pacman.d/mirrorlist/\Include = /etc/pacman.d/mirrorlist/g' /etc/pacman.conf
        pacman -Syu --noconfirm
        #echo "LANG=zh_CN.UTF-8" >> /etc/locale.conf
        echo "export LANG=zh_CN.UTF-8\nexport LANGUAGE=zh_CN:en_US" >> ~/.xprofile
 }
 
  #安装基本软件
 add_baseapplication(){
       print_title "add_baseapplication"(){
       pacman -S --noconfirm pavucontrol alsa-utils pulseaudio pulseaudio-alsa -y
       pacman -S --noconfirm nano gvfs ntfs-3g gvfs-mtp p7zip file-roller unrar netease-cloud-music wps-office ttf-wps-fonts leafpad -y
       pacman -S --noconfirm vlc ark -y
       pacman -S --noconfirm firefox firefox-i18n-zh-cn -y
       pacman -S --noconfirm git wget yaourt yay fakeroot -y
       systemctl start alsa-state.service
       systemctl enable alsa-state.service
 }
 
   #安装中文输入法
  add_ChineseInput(){
       print_title "add_baseapplication"
       pacman -S --noconfirm fcitx fcitx-im fcitx-configtool -y
       echo "export GTK_IM_MODULE=fcitx\nexport QT_IM_MODULE=fcitx\nexport XMODIFIERS=“@im=fcitx”" >> ~/.xprofile
       echo "export GTK_IM_MODULE=fcitx\nexport QT_IM_MODULE=fcitx\nexport XMODIFIERS=“@im=fcitx”" >> ~/.bashrc
  } 
   
   #安装zsh
  add_zsh(){
      print_title "add_zsh"
      sh -c "$(wget https://raw.githubusercontent.com/robbyrussell/oh-my-zsh/master/tools/install.sh -O -)"
      cd ~/.oh-my-zsh/custom/plugins/
      git clone https://github.com/zsh-users/zsh-syntax-highlighting.git
      git clone https://github.com/zsh-users/zsh-autosuggestions
      cd
      zsh
  }  
   
   #安装系统图标字体主题包
  add_theme(){
      print_title "add_theme"
      yaourt -S --noconfirm gtk-theme-arc-git numix-circle-icon-theme-git
      git clone https://github.com/powerline/fonts.git --depth=1
      mv fonts source-code-pro-medium-italic
      mv source-code-pro-medium-italic /usr/share/fonts/
      cd /usr/share/fonts/source-code-pro-medium-italic
      bash install.sh
      cd
      umount -R /mnt
      clear
      print_title "config has been.please reboot ."
  } 
  
  configure_Chinese
  add_baseapplication
  add_ChineseInput
  add_zsh
  add_theme
