# archlinux setup script

关于arch安装的一个脚本

### Download
```
dhcpcd
wget raw.githubusercontent.com/xylzq/arch/master/setup.sh
```

### Usage
- 执行 bash setup.sh
- 脚本运行前可根据需要更改分区位置大小格式及启动项等.
- 脚本运行中需要确定是否更新，填写域名，用户名及密码等.
- 脚本运行结束后重启即可基本使用.
- 桌面环境可重启后根据需要自行安装
- 内核安装的是linux-lts，可根据需求自行更改，在安装基本系统处

### 几个桌面环境安装方法
- KDE：
```
pacman -S kf5 kf5-aids plasma kdebase kdegraphics kde-l10n-zh_cn sddm
systemctl enable sddm
```
- Gnome：
```
pacman -S gnome gnome-terminal gnome-tweak-tool chrome-gnome-shell gdm
systemctl enable gdm
```
- Xfce：
```
pacman -S xfce4 xfce4-goodies sddm
systemctl enable sddm 
```
- Deepin：
```
pacman -S deepin deepin-extra deepin-terminal lightdm lightdm-gtk-greeter
systemctl enable lightdm
nano /etc/lightdm/lightdm.conf
# 将greeter-session=example-gtk-gnome改为greeter-session=lightdm-deepin-greeter
```

# archlinux config script

关于arch配置美化的一个脚本

### Download
```
sudo pacman -S wget git
wget raw.githubusercontent.com/xylzq/arch/master/config.sh
```

### explain
- 主要配置有，添加archlinuxcn等源
- 桌面环境汉化及中文输入法
- 一些基本主题美化，如zsh，图标主题包等
- 一些必要软件如压缩，挂载，声音管理器
- 一些实用软件如文档管理器，播放器，网易云音乐，wps,火狐浏览器等
- 大家可根据需要自由增减
- 安装完zsh后脚本会自动退出，所以zsh的配置脚本无法运行，大家可以手动操作脚本的内容


# 安装完archlinux后要做的几件事

1.更换内核(linux比较激进，不够稳定)
```
sudo pacman -S linux-lts
sudo grub-mkconfig -o /boot/grub/grub.cfg 
# 安装内核头文件（某些软件需要，如virtualbox）
# sudo pacman -S linux-lts-headers 
sudo pacman -Rs linux
```

2.安装微代码microcode（可修正cpu硬件错误）
```
# intel
sudo pacman -S intel-ucode
# amd
sudo pacman -S amd-ucode
sudo grub-mkconfig -o /boot/grub/grub.cfg 
```

3.安装防火墙
```
sudo pacman -S ufw
sudo ufw enable
sudo ufw status verbose
sudo systemctl enable ufw.service
```

4.加密家目录
```
# 使用eCryptFS
# 重启进入tty2
# root进入查看$home进程（如果有程序为活跃状态，则杀死它）
ps -U $home
# 安装必要安装包
pacman -S rsync lsof ecryptfs-utils
modprobe ecryptfs
ecryptfs-migrate-home -u $username
exit
ls
cat README.txt
ecryptfs-mount-private
ecryptfs-unwrap-passphrase
# 然后配置
```

5.删除孤立的包
```
sudo pacman -Rns $(pacman -Qtdq)
```

6.提高数据库访问速度(固态硬盘不可使用)
```
sudo pacman-optimize && sync
```
7.检查系统文件错误
```
sudo systemctl --failed
sudo journalctl -p 3 -xb
```
8.多系统管理

- 生成多系统引导程序
```
# 探寻其他系统
sudo pacman -S os-prober
# 生成配置文件
sudo grub-mkconfig -o /boot/grub/grub.cf
```
- 多系统时间同步
```
# 安装 Windows 和 Linux 系统后 Windows 的时间会比慢8个小时
————————————————
# 原因：

# 电脑系统中有两个时间：
# 硬件时间：保存在主板中，信息比较少没时区、夏令时的概念
# 系统时间：又系统维护，独立于硬件时间，拥有时区、夏令时等信息
# 系统时间又因为系统的不同使用了两种时间管理办法：
# localtime：本地时间，目前只有 Windows 在使用。
# UTC：是一种世界标准时间，Linux 这类类 UNIX 多数会使用，UTC 加减时区之后才是本地时间。
# Windows 认为硬件时间就是本地时间，所以会直接把主板中的时间拿来当做当前的时间。设置或同步时间后也会把“正确”的时间写入主板
# Linux 认为硬件时间是 UTC 标准时间，Linux 时间同步后会把“正确”的时间 -8 之后作为标准 UTC 标准时间写入主板
————————————————
# 解决办法：

# windows:
# 以管理员身份使用运行
reg add "HKEY_LOCAL_MACHINE\System\CurrentControlSet\Control\TimeZoneInformation" /v RealTimeIsUniversal /d 1 /t REG_DWORD /f
# 以上方法无效或64位系统：
reg add "HKEY_LOCAL_MACHINE\System\CurrentControlSet\Control\TimeZoneInformation" /v RealTimeIsUniversal /d 1 /t REG_QWORD /f
————————————————
# linux：
sudo timedatectl set-local-rtc true
```
- 将其他系统(分区)自动挂载到家目录
```
# 在家目录创建挂载点（挂载点最好为空文件夹，非空文件夹文件在挂载后将不会显示，除非卸载此挂载点）
mkdir win7
# 查看挂载分区uuid
sudo blkid
# 查看挂载分区类型
sudo fdisk -l
# 将挂载信息填入fstab文件（除了结尾的00之间使用空格，其他全部用跳格tab分割）

sudo nano /etc/fstab
----------------------------------------------------------------------
# /dev/sdb3
UUID=xxxxxxxx   /home/$username/win7  ntfs    defaults        0 0

```
**9.备份！！！**

# archlinux application

关于arch的一些实用软件

1.录屏软件
```
sudo pacman -S simplescreenrecorder
```
2.显示按键软件
```
sudo pacman -S screenkey
```
3.剪辑视频软件
```
sudo pacman -S kdenlive
```
4.修图软件
```
sudo pacman -S gimp
```
5.vmware
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
6.邮件
```
sudo pacman -S thunderbird
```
7.下载器
```
sudo pacman -S transmission-qt 或者 transmission-gtk
sudo pacman -S qbittorrent
```
8.游戏管理器lutris
```
# 安装必备驱动：
# 进入官网https://github.com/lutris/docs/blob/master/InstallingDrivers.md按照提示根据系统下载相应驱动：
sudo pacman -S nvidia-dkms nvidia-utils lib32-nvidia-utils nvidia-settings vulkan-icd-loader lib32-vulkan-icd-loader
（lts内核再安装 pacman -S nvidia-lts ）

# 安装安装litris和它相关的包：
sudo pacman -S dxvk wine-staging lutris

# 安装wine-staging的可选依赖（为了完整运行window程序，最好都安装好）：
# 进入官网https://github.com/lutris/docs/blob/master/WineDependencies.md按照提示根据系统下载相应依赖：
sudo pacman -S wine-staging giflib lib32-giflib libpng lib32-libpng libldap lib32-libldap gnutls lib32-gnutls mpg123 lib32-mpg123 openal lib32-openal v4l-utils lib32-v4l-utils libpulse lib32-libpulse libgpg-error lib32-libgpg-error alsa-plugins lib32-alsa-plugins alsa-lib lib32-alsa-lib libjpeg-turbo lib32-libjpeg-turbo sqlite lib32-sqlite libxcomposite lib32-libxcomposite libxinerama lib32-libgcrypt libgcrypt lib32-libxinerama ncurses lib32-ncurses opencl-icd-loader lib32-opencl-icd-loader libxslt lib32-libxslt libva lib32-libva gtk3 lib32-gtk3 gst-plugins-base-libs lib32-gst-plugins-base-libs vulkan-icd-loader lib32-vulkan-icd-loader

# 提升游戏性能的程序：
yaourt -S gamemod lib32-gamemode
# 配置gamemode：
一、查找gamemode路径
find /usr -iname 'libgamemodeauto*' 
二、复制路径 
/usr/lib/libgamemodeauto.so.0
三、添加路径
运行lutris，点击preferences中的system options里面的add，
key输入LD_PRELOAD，Value输入上述路径/usr/lib/libgamemodeauto.so.0，save。
# 继续提升性能：
参照 https://github.com/lutris/https://github.com/lutris/docs/blob/master/Performance-Tweaks.md 最下面
其中，NIVDIA可按照上述添加路径的方法，
key输入__GL_THREADED_OPTIMIZATION，Value输入1;
AMD可可按照上述添加路径的方法，
key输入mesa_glthread，Value输入true，save。

# 继续提升性能：
使用带tkg的wine版本，manager version，因为带tkg的wine都启用了ESyns,对性能的提升极大;
但是要发挥ESyns的效果，需要优化内核：
sudo pacman -S ulimit
ulimit -Hn
若出现的数字比524288大（不小于就行），就不用配置了，若没有，则继续：
sudo nano /etc/systemd/system.conf
将 DefaultLimitNOFILE 前面的#去掉，= 后面的数字改为524288；
sudo nano /etc/systemd/user.conf
将 DefaultLimitNOFILE 前面的#去掉，= 后面的数字改为524288.

# 其他配置可参照https://github.com/lutris/lutris/wiki/ 修改。
