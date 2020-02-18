## 安装NVIDIA驱动注意事项



### -笔记本电脑

#### 1.安装x环境
```
pacman -S xorg-xinit xorg-server
```

#### 2.安装多显卡显卡管理程序
- 大黄蜂方案（不支持DXVK）
```
pacman -S nvidia
pacman -S bumblebee
systemctl enable bumblebeed
```
- bbswitch方案
```
pacman -S nvidia bbswitch optimus-manager-qt
# 自定义内核则：
pacman -S nvidia-dkms bbswitch-dkms optimus-manager-qt
# KDE桌面
pacman -S nvidia-dkms bbswitch-dkms optimus-manager-qt-kde
```




### -台式电脑

#### 1.安装x环境
```
pacman -S xorg-xinit xorg-server 
```

#### 2.安装闭源驱动
```
pacman -S nvidia nvidia-utils nvidia-settings
```

#### 3.查看n卡的BusID
```
$ lspci | egrep 'VGA|3D'
出现如下格式：
----------------------------------------------------------------------
00:02.0 VGA compatible controller: Intel Corporation UHD Graphics 630 (Desktop)
01:00.0 VGA compatible controller: NVIDIA Corporation GP107M [GeForce GTX 1050 Ti Mobile] (rev a1)
```

#### 4.自动生成配置文件
```
$ nvidia-xconfig
```

#### 5.启动脚本配置
- LightDM
```
$ nano /etc/lightdm/display_setup.sh
----------------------------------------------------------------------
#!/bin/sh
xrandr --setprovideroutputsource modesetting NVIDIA-0
xrandr --auto
----------------------------------------------------------------------
$ chmod +x /etc/lightdm/display_setup.sh
$ nano /etc/lightdm/lightdm.conf
----------------------------------------------------------------------
[Seat:*]
display-setup-script=/etc/lightdm/display_setup.sh
```

- SDDM
```
$ nano /usr/share/sddm/scripts/Xsetup
----------------------------------------------------------------------
xrandr --setprovideroutputsource modesetting NVIDIA-0
xrandr --auto
```

- GDM
```
创建两个桌面文件
/usr/share/gdm/greeter/autostart/optimus.desktop
/etc/xdg/autostart/optimus.desktop
----------------------------------------------------------------------
[Desktop Entry]
Type=Application
Name=Optimus
Exec=sh -c "xrandr --setprovideroutputsource modesetting NVIDIA-0; xrandr --auto"
NoDisplay=true
X-GNOME-Autostart-Phase=DisplayServer
```

#### 6.修改配置文件
```
$ nano /etc/X11/xorg.conf
----------------------------------------------------------------------
Section "Module"                                                      #此部分可能没有，自行添加
    load "modesetting"
EndSection

Section "Device"
    Identifier     "Device0"
    Driver         "nvidia"
    VendorName     "NVIDIA Corporation"
    BusID          "1:0:0"                                            #此处填刚刚查询到的BusID
    Option         "AllowEmptyInitialConfiguration"
EndSection
```

#### 7.解决画面撕裂问题
```
$ nano /etc/mkinitcpio.conf
----------------------------------------------------------------------
MODULES=(nvidia nvidia_modeset nvidia_uvm nvidia_drm)
----------------------------------------------------------------------

$ nano /etc/default/grub                                              # 此处必须是grub引导，其他引导自行百度
----------------------------------------------------------------------
GRUB_CMDLINE_LINUX_DEFAULT="quiet nvidia-drm.modeset=1"               #此处加nvidia-drm.modeset=1参数
----------------------------------------------------------------------

$ grub-mkconfig -o /boot/grub/grub.cfg                                # 就算grub引导，配置文件也可能不在一个地方，请查看清楚
```

#### 8.nvidia升级时自动更新initramfs
```
$ mkdir /etc/pacman.d/hooks
$ nano /etc/pacman.d/hooks/nvidia.hook
-----------------------------------------------------------------
[Trigger]
Operation=Install
Operation=Upgrade
Operation=Remove
Type=Package
Target=nvidia
Target=linux
# Change the linux part above and in the Exec line if a different kernel is used

[Action]
Description=Update Nvidia module in initcpio
Depends=mkinitcpio
When=PostTransaction
NeedsTargets
Exec=/bin/sh -c 'while read -r trg; do case $trg in linux) exit 0; esac; done; /usr/bin/mkinitcpio -P'
```
