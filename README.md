# archlinux setup script

关于arch安装的一个脚本

## Download
```
dhcpcd
wget raw.githubusercontent.com/xylzq/arch/master/setup.sh
```

## Usage
- 执行 bash setup.sh
- 脚本运行前可根据需要更改分区位置大小格式及启动项等.
- 脚本运行中需要确定是否更新，填写域名，用户名及密码等.
- 脚本运行结束后重启即可基本使用.
- 桌面环境可重启后根据需要自行安装

## 几个桌面环境安装方法
### - KDE：
```
pacman -S kf5 kf5-aids plasma kdebase kdegraphics kde-l10n-zh_cn sddm
systemctl enable sddm
```
### - Gnome：
```
pacman -S gnome gnome-terminal gnome-tweak-tool chrome-gnome-shell gdm
systemctl enable gdm
```
### - Xfce：
```
pacman -S xfce4 xfce4-goodies sddm
systemctl enable sddm 
```
### - Deepin：
```
pacman -S deepin deepin-extra deepin-terminal lightdm lightdm-gtk-greeter
systemctl enable lightdm
nano /etc/lightdm/lightdm.conf
#将greeter-session=example-gtk-gnome改为greeter-session=lightdm-deepin-greeter
```

# archlinux config script

关于arch配置美化的一个脚本

## Download
```
sudo pacman -S wget git
wget raw.githubusercontent.com/xylzq/arch/master/config.sh
```

## explain
- 主要配置有，添加archlinuxcn等源
- 桌面环境汉化及中文输入法
- 一些基本主题美化，如zsh，图标主题包等
- 一些必要软件如压缩，挂载，声音管理器
- 一些实用软件如文档管理器，播放器，网易云音乐，wps,火狐浏览器等
- 大家可根据需要自由增减
- 安装完zsh后脚本会自动退出，所以zsh的配置脚本无法运行，大家可以手动操作脚本的内容

# archlinux application

关于arch的一些实用软件

## 录屏软件
```
sudo pacman -S simplescreenrecorder
```
## 显示按键软件
```
sudo pacman -S screenkey
```
## 剪辑视频软件
```
sudo pacman -S kdenlive
```
## 修图软件
```
sudo pacman -S gimp
```
## vmware
```
# 安装必要依赖
sudo pacman -S fuse2 gtkmm linux-headers pcsclite libcanberra
yay -S --noconfirm --needed ncurses5-compat-libs

# 安装虚拟机
yay -S --noconfirm --needed  vmware-workstation

# 根据需要，启用以下某些服务：
# 1]、用于访客网络访问的vmware-networks.service
# 2]、vmware-usbarbitrator.service用于将USB设备连接到guest虚拟机
# 3]、vmware-hostd.service用于共享虚拟机
sudo systemctl enable vmware-networks.service  vmware-usbarbitrator.service vmware-hostd.service
sudo systemctl start vmware-networks.service  vmware-usbarbitrator.service vmware-hostd.service
# 确认服务状态：
sudo systemctl status vmware-networks.service  vmware-usbarbitrator.service vmware-hostd.service
# 加载VMware模块：
sudo modprobe -a vmw_vmci vmmon

# 启动虚拟机，填写密钥
sudo vmware
```
## 邮件
```
sudo pacman -S thunderbird
```
## 下载器
```
sudo pacman -S transmission-qt 或者 transmission-gtk
sudo pacman -S qbittorrent
```
