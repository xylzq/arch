#!/usr/bin/env bash
# =============================================================================
#  arch-install.sh — Arch Linux 自动安装脚本(VMware / UEFI 与 BIOS 通用)
#
#  用法:
#      bash arch-install.sh
#      DISK=/dev/nvme0n1 KERNEL_PKG=linux bash arch-install.sh
#      AUTO_CONFIRM=1 TARGET_HOSTNAME=myarch DISK=/dev/sda bash arch-install.sh
#
#  运行前确认:
#      1) 在 archiso live 环境里以 root 身份执行;
#      2) live 环境已联网(ping -c1 archlinux.org);
#      3) 目标磁盘上的数据会被全部清除,且该磁盘未被挂载;
#      4) VMware 固件类型与 ISO 启动模式一致,Secure Boot 已关闭。
#
#  脚本会自行判断 live 环境是 UEFI 还是 BIOS 启动,并据此选择分区表与引导方式。
# =============================================================================

set -euo pipefail

# ----------------------------- 可调参数(环境变量可覆盖) ----------------------
DISK="${DISK:-}"                                # 留空则自动探测
TARGET_HOSTNAME="${TARGET_HOSTNAME:-arch}"
TARGET_USER="${TARGET_USER:-arch}"
TIMEZONE="${TIMEZONE:-Asia/Shanghai}"
SYS_LANG="${SYS_LANG:-en_US.UTF-8}"
EXTRA_LOCALE="${EXTRA_LOCALE:-zh_CN.UTF-8}"     # 置空则不启用
KEYMAP="${KEYMAP:-us}"
KERNEL_PKG="${KERNEL_PKG:-linux-lts}"           # 也可用 linux
BOOT_SIZE_MIB="${BOOT_SIZE_MIB:-512}"           # ESP 或 /boot 大小
SWAP_SIZE_MIB="${SWAP_SIZE_MIB:-4096}"          # swap 大小,0 表示不建 swap
NOPASSWD_SUDO="${NOPASSWD_SUDO:-0}"             # 1 = wheel 组免密 sudo(仅调试)
SKIP_PASSWD="${SKIP_PASSWD:-0}"                 # 1 = 跳过交互式设密码(不推荐)
AUTO_CONFIRM="${AUTO_CONFIRM:-0}"               # 1 = 跳过磁盘清空确认
ENABLE_LOG="${ENABLE_LOG:-1}"                   # 1 = 同时写日志文件

MNT=/mnt
LOG_FILE="${LOG_FILE:-/tmp/arch-install-$(date +%Y%m%d-%H%M%S).log}"

# ----------------------------- 输出辅助 --------------------------------------
if [[ -t 1 ]]; then
    BOLD=$'\033[1m'
    RESET=$'\033[0m'
else
    BOLD=''
    RESET=''
fi

print_line() {
    local cols
    cols="$(tput cols 2>/dev/null || echo 80)"
    printf -- '-%.0s' $(seq 1 "$cols")
    echo
}

print_title() {
    clear 2>/dev/null || true
    print_line
    echo -e "${BOLD}# $*${RESET}"
    print_line
    echo
}

warn() {
    echo "${BOLD}警告:${RESET} $*" >&2
}

die() {
    echo "${BOLD}错误:${RESET} $*" >&2
    exit 1
}

on_error() {
    local code=$1
    echo >&2
    print_line >&2
    echo "安装中断(退出码 ${code})" >&2
    echo "失败命令: ${BASH_COMMAND}" >&2
    echo "目标系统仍挂载在 ${MNT},可手动排查后重新运行;日志: ${LOG_FILE}" >&2
    print_line >&2
    exit "$code"
}
trap 'on_error $?' ERR

in_chroot() {
    arch-chroot "$MNT" /bin/bash -c "$1"
}

# /dev/sda -> /dev/sda1;/dev/nvme0n1 -> /dev/nvme0n1p1
part_path() {
    local disk=$1 num=$2
    if [[ $disk =~ [0-9]$ ]]; then
        printf '%sp%s' "$disk" "$num"
    else
        printf '%s%s' "$disk" "$num"
    fi
}

# ----------------------------- 各阶段 ----------------------------------------
preflight() {
    print_title "环境检查"

    [[ $EUID -eq 0 ]] || die "请以 root 身份运行(archiso 里默认就是 root)"
    [[ -d /run/archiso ]] || warn "看起来不是 archiso live 环境,继续前请自行确认"

    if mountpoint -q "$MNT"; then
        die "${MNT} 已被挂载,请先执行 umount -R ${MNT} 再运行本脚本"
    fi

    if [[ -z $DISK ]]; then
        local d
        for d in /dev/sda /dev/vda /dev/nvme0n1 /dev/sdb; do
            if [[ -b $d ]]; then
                DISK=$d
                break
            fi
        done
    fi
    [[ -n $DISK && -b $DISK ]] || die "找不到目标磁盘,可用 DISK=/dev/sdX 指定"

    if [[ -d /sys/firmware/efi ]]; then
        BOOT_MODE=uefi
    else
        BOOT_MODE=bios
    fi

    PART_BOOT="$(part_path "$DISK" 1)"
    PART_SWAP="$(part_path "$DISK" 2)"
    PART_ROOT="$(part_path "$DISK" 3)"

    if lsblk -no MOUNTPOINT "$DISK" 2>/dev/null | grep -q '[^[:space:]]'; then
        die "${DISK} 上还有分区处于挂载状态,请先全部卸载再运行"
    fi
    if grep -q "^${DISK}" /proc/swaps 2>/dev/null; then
        die "${DISK} 上还有激活的 swap,请先 swapoff 再运行"
    fi

    [[ $TARGET_HOSTNAME =~ ^[A-Za-z0-9]([A-Za-z0-9-]{0,61}[A-Za-z0-9])?$ ]] \
        || die "主机名不合法: ${TARGET_HOSTNAME}"
    [[ $TARGET_USER =~ ^[a-z_][a-z0-9_-]*$ ]] \
        || die "用户名不合法(须小写字母或下划线开头): ${TARGET_USER}"

    echo "live 启动模式 : ${BOOT_MODE}"
    echo "目标磁盘      : ${DISK}"
    echo "内核          : ${KERNEL_PKG}"
    echo "主机名 / 用户 : ${TARGET_HOSTNAME} / ${TARGET_USER}"
    echo "时区 / 语言   : ${TIMEZONE} / ${SYS_LANG}"
    echo "日志文件      : ${LOG_FILE}"
    echo
    lsblk "$DISK" || true
    echo

    if [[ $BOOT_MODE == uefi ]]; then
        echo "将以 UEFI 方式安装:GPT + ESP(fat32) + GRUB(x86_64-efi)"
    else
        echo "将以 BIOS 方式安装:MBR + GRUB(i386-pc)"
        warn "请确认 VMware 的固件类型就是 BIOS。若虚拟机是 UEFI 固件,重启后将无法引导,"
        warn "此时应在 Boot Manager 里用「EFI ... CDROM」重新启动 live 环境再运行本脚本。"
    fi
    echo

    if [[ $AUTO_CONFIRM != 1 ]]; then
        local ans
        read -r -p "确认清空 ${DISK} 上的全部数据?输入 YES 继续: " ans
        [[ $ans == YES ]] || die "用户取消操作"
    fi
}

update_mirrorlist() {
    print_title "配置 pacman 镜像源"

    local tmpfile url
    tmpfile="$(mktemp --suffix=-mirrorlist)"
    url='https://archlinux.org/mirrorlist/?country=CN&protocol=https&ip_version=4'

    if curl -L --retry 3 --connect-timeout 10 -so "$tmpfile" "$url" \
        && grep -q '^#Server' "$tmpfile"; then
        sed -i 's/^#Server/Server/' "$tmpfile"
        cp -f "$tmpfile" /etc/pacman.d/mirrorlist
        echo "已启用 $(grep -c '^Server' /etc/pacman.d/mirrorlist) 个国内镜像源"
    else
        warn "镜像列表获取失败,沿用 live 环境自带的 mirrorlist"
    fi

    rm -f "$tmpfile"
}

create_partitions() {
    print_title "创建分区表(${BOOT_MODE})"

    local boot_end swap_end
    boot_end=$((1 + BOOT_SIZE_MIB))
    swap_end=$((boot_end + SWAP_SIZE_MIB))

    wipefs -a "$DISK"

    if [[ $BOOT_MODE == uefi ]]; then
        parted -s "$DISK" mklabel gpt
        parted -s "$DISK" mkpart ESP fat32 1MiB "${boot_end}MiB"
        parted -s "$DISK" set 1 esp on
        if [[ $SWAP_SIZE_MIB -gt 0 ]]; then
            parted -s "$DISK" mkpart swap linux-swap "${boot_end}MiB" "${swap_end}MiB"
            parted -s "$DISK" mkpart root ext4 "${swap_end}MiB" 100%
        else
            parted -s "$DISK" mkpart root ext4 "${boot_end}MiB" 100%
        fi
    else
        parted -s "$DISK" mklabel msdos
        parted -s "$DISK" mkpart primary ext4 1MiB "${boot_end}MiB"
        parted -s "$DISK" set 1 boot on
        if [[ $SWAP_SIZE_MIB -gt 0 ]]; then
            parted -s "$DISK" mkpart primary linux-swap "${boot_end}MiB" "${swap_end}MiB"
            parted -s "$DISK" mkpart primary ext4 "${swap_end}MiB" 100%
        else
            parted -s "$DISK" mkpart primary ext4 "${boot_end}MiB" 100%
        fi
    fi

    partprobe "$DISK" 2>/dev/null || true
    udevadm settle 2>/dev/null || true
    sleep 1
    parted -s "$DISK" print
}

format_partitions() {
    print_title "格式化分区"

    local parts=("$PART_BOOT" "$PART_ROOT")
    if [[ $SWAP_SIZE_MIB -gt 0 ]]; then
        parts+=("$PART_SWAP")
    fi

    local p
    for p in "${parts[@]}"; do
        [[ -b $p ]] || die "分区 ${p} 不存在,分区表可能未生效"
        wipefs -a "$p" >/dev/null 2>&1 || true
    done

    if [[ $BOOT_MODE == uefi ]]; then
        mkfs.fat -F32 -n ESP "$PART_BOOT"
    else
        mkfs.ext4 -F -L boot "$PART_BOOT"
    fi

    if [[ $SWAP_SIZE_MIB -gt 0 ]]; then
        mkswap -L swap "$PART_SWAP"
    fi
    mkfs.ext4 -F -L root "$PART_ROOT"
}

mount_partitions() {
    print_title "挂载分区"

    mount "$PART_ROOT" "$MNT"
    mkdir -p "$MNT/boot"
    mount "$PART_BOOT" "$MNT/boot"
    if [[ $SWAP_SIZE_MIB -gt 0 ]]; then
        swapon "$PART_SWAP"
    fi
    lsblk -f "$DISK"
}

install_base() {
    print_title "安装基础系统(pacstrap)"

    # 刷新同步数据库,避免 ISO 自带的 DB 过期导致下载 404
    pacman -Syy --noconfirm || warn "刷新软件包数据库失败,继续尝试安装"

    local ucode=''
    if grep -qm1 'GenuineIntel' /proc/cpuinfo; then
        ucode=intel-ucode
    elif grep -qm1 'AuthenticAMD' /proc/cpuinfo; then
        ucode=amd-ucode
    fi

    local pkgs=(
        base base-devel
        "$KERNEL_PKG" "${KERNEL_PKG}-headers"
        linux-firmware
        man-db man-pages texinfo
        vim nano sudo zsh
        wqy-zenhei wqy-microhei ttf-dejavu adobe-source-code-pro-fonts
    )
    if [[ -n $ucode ]]; then
        pkgs+=("$ucode")
    fi

    pacstrap -K "$MNT" "${pkgs[@]}"
}

generate_fstab() {
    print_title "生成 fstab"

    genfstab -U "$MNT" > "$MNT/etc/fstab"
    cat "$MNT/etc/fstab"
}

configure_system() {
    print_title "配置时区 / 语言 / initramfs"

    in_chroot "ln -sf /usr/share/zoneinfo/${TIMEZONE} /etc/localtime"
    in_chroot "hwclock --systohc --utc"

    in_chroot "sed -i 's/^#\\(${SYS_LANG} UTF-8\\)/\\1/' /etc/locale.gen"
    if [[ -n $EXTRA_LOCALE ]]; then
        in_chroot "sed -i 's/^#\\(${EXTRA_LOCALE} UTF-8\\)/\\1/' /etc/locale.gen"
    fi
    in_chroot "locale-gen"

    echo "LANG=${SYS_LANG}" > "$MNT/etc/locale.conf"
    echo "KEYMAP=${KEYMAP}" > "$MNT/etc/vconsole.conf"

    # 重建所有已安装内核的 initramfs,不再写死内核名
    in_chroot "mkinitcpio -P"
}

install_extra_packages() {
    print_title "安装网络与图形基础组件"

    local pkgs=(
        networkmanager network-manager-applet
        iw wireless_tools wpa_supplicant dialog netctl rp-pppoe net-tools
        xorg-server xorg-xinit xorg-twm xorg-xclock
        xf86-video-vmware xf86-input-vmmouse
    )

    # 个别可选包可能已从仓库移除,失败时降级为只装核心组件,避免整体中断
    if ! in_chroot "pacman -S --noconfirm --needed ${pkgs[*]}"; then
        warn "部分可选包安装失败,改为只安装核心组件重试"
        in_chroot "pacman -S --noconfirm --needed networkmanager network-manager-applet net-tools iw wireless_tools wpa_supplicant xorg-server xorg-xinit"
    fi

    in_chroot "systemctl enable NetworkManager.service"
    in_chroot "systemctl enable systemd-timesyncd.service"
}

configure_bootloader() {
    print_title "安装并配置引导程序(${BOOT_MODE})"

    if [[ $BOOT_MODE == uefi ]]; then
        if ! mountpoint -q /sys/firmware/efi/efivars; then
            mount -t efivarfs efivarfs /sys/firmware/efi/efivars \
                || warn "efivars 挂载失败,efibootmgr 可能无法写入启动项(兜底路径仍会生成)"
        fi

        # efibootmgr 是给固件 NVRAM 写启动项所必需的,原脚本漏装
        in_chroot "pacman -S --noconfirm --needed grub efibootmgr"
        in_chroot "grub-install --target=x86_64-efi --efi-directory=/boot --bootloader-id=GRUB --recheck"

        # 兜底:固件在 NVRAM 里找不到启动项时会自动读这个固定路径
        in_chroot "mkdir -p /boot/EFI/BOOT && cp -f /boot/EFI/GRUB/grubx64.efi /boot/EFI/BOOT/BOOTX64.EFI"

        in_chroot "grub-mkconfig -o /boot/grub/grub.cfg"

        if ! in_chroot "efibootmgr -v | grep -qi grub"; then
            warn "efibootmgr 未能写入启动项,已用 EFI/BOOT/BOOTX64.EFI 兜底,通常仍可引导"
        fi
    else
        in_chroot "pacman -S --noconfirm --needed grub"
        in_chroot "grub-install --target=i386-pc --recheck ${DISK}"
        in_chroot "grub-mkconfig -o /boot/grub/grub.cfg"
    fi
}

configure_identity() {
    print_title "设置主机名与 root 密码"

    echo "$TARGET_HOSTNAME" > "$MNT/etc/hostname"
    printf '127.0.0.1\tlocalhost\n::1\t\tlocalhost\n127.0.1.1\t%s.localdomain\t%s\n' \
        "$TARGET_HOSTNAME" "$TARGET_HOSTNAME" > "$MNT/etc/hosts"

    if [[ $SKIP_PASSWD != 1 ]]; then
        echo "接下来设置 root 密码:"
        arch-chroot "$MNT" passwd
    fi
}

configure_user() {
    print_title "创建普通用户 ${TARGET_USER}"

    in_chroot "useradd -m -G wheel -s /bin/zsh ${TARGET_USER}"
    in_chroot "sed -i 's/^# %wheel ALL=(ALL:ALL) ALL/%wheel ALL=(ALL:ALL) ALL/' /etc/sudoers"

    if [[ $NOPASSWD_SUDO == 1 ]]; then
        warn "按 NOPASSWD_SUDO=1 为 wheel 组开启了免密 sudo"
        echo '%wheel ALL=(ALL:ALL) NOPASSWD: ALL' > "$MNT/etc/sudoers.d/10-wheel-nopasswd"
        chmod 440 "$MNT/etc/sudoers.d/10-wheel-nopasswd"
    fi

    in_chroot "visudo -c"

    if [[ $SKIP_PASSWD != 1 ]]; then
        echo "接下来设置 ${TARGET_USER} 的密码:"
        arch-chroot "$MNT" passwd "$TARGET_USER"
    fi
}

verify_install() {
    print_title "校验安装结果"

    [[ -f "$MNT/etc/fstab" ]] || die "缺少 /etc/fstab"
    [[ -f "$MNT/etc/hostname" ]] || die "缺少 /etc/hostname"
    [[ -f "$MNT/etc/locale.gen" ]] || die "缺少 /etc/locale.gen"
    [[ -f "$MNT/boot/grub/grub.cfg" ]] || die "缺少 /boot/grub/grub.cfg,引导配置未生成"
    grep -q 'vmlinuz' "$MNT/boot/grub/grub.cfg" || die "grub.cfg 中没有内核条目"
    [[ -f "$MNT/boot/vmlinuz-${KERNEL_PKG}" ]] || warn "没有找到 /boot/vmlinuz-${KERNEL_PKG}"

    if [[ $BOOT_MODE == uefi ]]; then
        [[ -f "$MNT/boot/EFI/BOOT/BOOTX64.EFI" ]] || die "缺少兜底引导文件 EFI/BOOT/BOOTX64.EFI"
    fi

    echo
    lsblk -f "$DISK"
    echo
    echo "grub.cfg 中识别到的启动项:"
    grep -E '^menuentry' "$MNT/boot/grub/grub.cfg" | head -6
}

finish() {
    print_title "收尾"

    swapoff "$PART_SWAP" 2>/dev/null || true
    umount -R "$MNT" || warn "卸载 ${MNT} 时出现问题,请手动检查"

    cat <<EOF

安装完成。重启前请确认:
  1) VMware「虚拟机设置 -> CD/DVD」取消勾选「启动时连接」(或移除 ISO);
  2) 固件启动顺序中硬盘排在光盘之前;
  3) 若使用 UEFI 固件,确认「启用安全引导」未勾选;
  4) 执行:  reboot

日志文件: ${LOG_FILE}
EOF
    sleep 0.3
}

main() {
    if [[ $ENABLE_LOG == 1 ]]; then
        exec > >(tee -a "$LOG_FILE") 2>&1
    fi

    preflight
    update_mirrorlist
    create_partitions
    format_partitions
    mount_partitions
    install_base
    generate_fstab
    configure_system
    install_extra_packages
    configure_bootloader
    configure_identity
    configure_user
    verify_install
    finish
}

main "$@"
