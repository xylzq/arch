# archlinux setup script

关于arch安装的一个脚本

## Download
- dhcpcd
- wget raw.githubusercontent.com/xylzq/archlinux/master/setup.sh

## Usage
- 执行 bash setup.sh
- 脚本运行前可根据需要更改分区位置大小格式及启动项等.
- 脚本运行中需要确定是否更新，填写域名，用户名及密码等.
- 脚本运行结束后重启即可基本使用.
- 桌面环境可重启后根据需要自行安装

## 几个桌面环境安装方法
### - KDE：
- pacman -S kf5 kf5-aids plasma kdebase kdegraphics kde-l10n-zh_cn sddm
- systemctl enable sddm
### - Gnome：
- pacman -S gnome gnome-terminal
- systemctl enable gdm
### - Xfce：
- pacman -S xfce4 xfce4-goodies sddm
- systemctl enable sddm 
### - Deepin：
- pacman -S deepin deepin-extra deepin-terminal lightdm lightdm-gtk-greeter
- systemctl enable lightdm
- nano /etc/lightdm/lightdm.conf
- 将greeter-session=example-gtk-gnome改为greeter-session=lightdm-deepin-greeter
