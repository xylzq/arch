# rsync+btrfs+dm-crypt 备份整个系统

## 备份系统（可在图形界面进行）

### dm-crypt 加密备份盘

* 加载dm-crypt模块
* 初始化加密分区
  * /dev/sda1：预备的加密分区；该指令输入后需要设定密码
* 打开加密分区
  * LzqBackup：设定的加密分区名称；该指令下达后需要输入密码打开
* 建立文件系统
  * 将加密分区格式化为 btrfs 格式；主要借助其快照功能实现增量备份
* 挂载加密分区备用

```sudo modprobe dm-crypt
cryptsetup luksFormat /dev/sda1
cryptsetup open /dev/sda1 Backup
mkfs.btrfs /dev/mapper/Backup
sudo mount /dev/mapper/Backup /mnt
```

### 建立相应的目录和子卷结构

* 备份策略：备份数据放到 backup 目录下，/ 和主目录 /home/primary 分开备份。每个备份是使用日期和时间命名的快照子卷。除了用于每次同步的 current 目录外其它的子卷都是只读的，以免被意外修改。（在 run 目录下是用于直接运行的，可写。这些可以按需建立。）

```
  /mnt
  |-- backup(dir)
  |   |-- home(dir)
  |   |   |-- current (subvol, rw)
  |   |   |-- 20131016_1423 (subvol, ro)
  |   |   |-- 20131116_2012 (subvol, ro)
  |   |   |-- ...
  |   |-- root(dir)
  |       |-- current (subvol, rw)
  |   |   |-- 20131016_1423 (subvol, ro)
  |   |   |-- 20131116_2012 (subvol, ro)
  |   |   |-- ...
  |-- run，for boot up directly, with edited /etc/fstab (dir)
  |   |-- home (dir)
  |   |   |-- 20131116 (subvol, rw)
  |   |   |-- ...
  |   |-- root(dir)
  |   |   |-- 20131116 (subvol, rw)
  |   |   |-- ...
  |-- etc, store information and scripts (subvol, rw)
  ```

* 操作步骤

```
  sudo mkdir -p /mnt/backup/home
  sudo mkdir -p /mnt/backup/root
  sudo btrfs subvolume create /mnt/backup/home/current
  sudo btrfs subvolume create /mnt/backup/root/current
  # 可选：
  sudo mkdir -p /mnt/run/home
  sudo mkdir -p /mnt/run/root
  sudo btrfs subvolume create /mnt/etc
  ```

 ### 使用rysnc备份系统

  * 备份参数含义
    * --archive --acls --xattrs --hard-links --sparse --one-file-system 缩写：-aAXHSx
    * --archive: 组合选项，用于保留权限、所有者、时间戳和软链接等。通常用于制作备份。
    * --acls 和 --xattrs: 包含 ACL（访问控制列表）和扩展属性在传输中。
    * --hard-links: 保留硬链接。对于维护硬链接结构很重要。
    * --sparse: 高效处理稀疏文件（备份稀疏文件，例如虚拟磁盘、Docker 镜像）。
    * --one-file-system: 不越过文件系统边界。确保只同步挂载在 / 的文件系统（不要备份挂载点）。
    * --delete: 删除目标中在源中不存在的文件（多次备份时，删除不存在原系统的文件）。
    * --delete-excluded: 从目标中删除被排除的文件（多次备份时，删除被排除的文件）。
    * --numeric-ids: 不要通过用户/组名映射uid/gid值，使用数值ID（避免在跨系统使用时出差错）。
    * --progress: 在传输过程中显示进度（显示备份文件与进度）。
    * --info=progress2: 提供详细的进度信息（显示总备份进度）。
    * --human-readable: 使用人类可读的格式输出数字。
    * --itemize-changes: 输出所有更新的更改摘要。
    * --verbose: 增加详细信息。
    * --exclude={"/dev/*"}: 从同步中排除指定的目录

  * 运行备份程序
    * 可先模拟运行，加入以下指令：--dry-run

  ```
  # 根目录
  sudo rsync --archive --acls --xattrs --hard-links --sparse --one-file-system --delete --delete-excluded --numeric-ids --progress --info=progress2
  --human-readable --itemize-changes --verbose --exclude={"/dev/*","/proc/*","/sys/*","/tmp/*","/run/*","/mnt/*","/media/*","/lost+found","/home/*"} / /mnt/backup/root/current
  # 主目录
  sudo rsync --archive --acls --xattrs --hard-links --sparse --one-file-system --delete --delete-excluded --numeric-ids --progress --info=progress2
  --human-readable --itemize-changes --verbose --exclude={"Desktop","Documents","Downloads","Music","Pictures","Public","Templates","Videos"} /home/primary /mnt/backup/home/current
  ```

  ### 增量备份

  * 在/home目录下创建只读快照
  * 在/root目录下创建只读快照
  * 删除多余备份
  * 整理碎片(存疑)
  * 卸载备份盘

  ```
  cd /mnt/backup/home
  sudo btrfs subvolume snapshot -r current $(date +'%Y%m%d_%H%M')
  cd /mnt/backup/root
  sudo btrfs subvolume snapshot -r current $(date +'%Y%m%d_%H%M')
  sudo btrfs subvolume delete /mnt/backup/home/subvol_name
  sudo btrfs subvolume delete /mnt/backup/root/subvol_name
  sudo btrfs filesystem defragment /mnt/backup（存疑）
  sudo umount /mnt
  ```

## 还原（必须在live系统，chroot前进行同步还原）

### 挂载主系统文件系统与备份盘

* 挂载主系统文件系统
* 挂载备份盘
  * 加载 dm-crypt 模块
  * 解锁加密盘
  * 挂载解锁的设备

```
sudo mount /dev/sdb3 /mnt
sudo swapon /dev/sdb2
sudo mkdir /mnt/boot
sudo mount /dev/sdb1 /mnt/boot
sudo mkdir /mnt/home
sudo mount /dev/sdb4 /mnt/home
sudo modprobe dm-crypt
sudo cryptsetup luksOpen /dev/sda1 Backup
sudo mkdir /run/d1
sudo mount /dev/mapper/Backup /run/d1
```

### 同步还原系统

* 注意路径最后的斜杠
* 注意删除命令，防止误删
  * --delete						delete files that don't exist on the sending side
  * --delete-excluded       also delete excluded files on the receiving side
  * 在接收方删除存在于接收方但不存在于发送方的文件，同时也删除被excluded掉的文件(即使这些文件也存在于发送方)

```
# 根目录
rsync -aAXHSx --delete --numeric-ids --progress --info=progress2 --exclude={"/lost+found","/home/*"} /run/d1/backup/root/subvol_name/ /mnt/
# 主目录
rsync -aAXHSx --delete --numeric-ids --progress --info=progress2 --exclude={"Desktop","Documents","Downloads","Music","Pictures","Public","Templates","Videos"} /run/d1/backup/home/subvol_name/ /mnt/home/
```

### 删除与卸载备份盘

```
sudo umount /run/d1
sudo rm -r /run/d1
sudo cryptsetup luksClose /dev/mapper/Backup
```

### 之后需要完成的事项（很疑惑！！！）

* 重新生成 fstab
* 将根目录 / 改为 /mnt
* 编辑 /etc/mkinitcpio.conf，在 HOOKS 这一行加入以下模块
  * HOOKS=(base udev keyboard autodetect keymap modconf block encrypt filesystems resume fsck)
* 重装内核与 microcode
* 重新生成 initramfs
* 重新生成启动项
* 退出、卸载并重启

```
genfstab -U /mnt > /mnt/etc/fstab
arch-chroot /mnt
nano /etc/mkinitcpio.conf
HOOKS=(base udev keyboard autodetect keymap modconf block encrypt filesystems resume fsck)
pacman -Syu linux-firmware linux-zen linux-zen-headers amd-ucode
mkinitcpio -P
pacman -S grub os-prober efibootmgr
grub-install --target=x86_64-efi --efi-directory=/boot --bootloader-id=Arch
grub-mkconfig -o /boot/grub/grub.cfg
exit
umount -R /mnt
reboot
```

