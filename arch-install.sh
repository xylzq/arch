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
#
#  注意:运行期输出全部使用 ASCII。Linux 虚拟终端的内核点阵字体没有汉字字形,
#  在 archiso 控制台里输出中文只会显示成方块,所以脚本自身不打印任何非 ASCII 字符。
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
    echo "${BOLD}WARNING:${RESET} $*" >&2
}

die() {
    echo "${BOLD}ERROR:${RESET} $*" >&2
    exit 1
}

on_error() {
    local code=$1
    echo >&2
    print_line >&2
    echo "INSTALL FAILED (exit code ${code})" >&2
    echo "Failed command: ${BASH_COMMAND}" >&2
    echo "The target is still mounted at ${MNT}; fix the problem and re-run." >&2
    echo "Log file: ${LOG_FILE}" >&2
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
    print_title "Preflight checks"

    [[ $EUID -eq 0 ]] || die "Run this script as root (the archiso live environment is root by default)."
    [[ -d /run/archiso ]] || warn "This does not look like an archiso live environment; continue only if you know what you are doing."

    if mountpoint -q "$MNT"; then
        die "${MNT} is already mounted; run 'umount -R ${MNT}' first."
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
    [[ -n $DISK && -b $DISK ]] || die "No target disk found; specify one with DISK=/dev/sdX."

    if [[ -d /sys/firmware/efi ]]; then
        BOOT_MODE=uefi
    else
        BOOT_MODE=bios
    fi

    PART_BOOT="$(part_path "$DISK" 1)"
    PART_SWAP="$(part_path "$DISK" 2)"
    PART_ROOT="$(part_path "$DISK" 3)"

    if lsblk -no MOUNTPOINT "$DISK" 2>/dev/null | grep -q '[^[:space:]]'; then
        die "${DISK} still has mounted partitions; unmount them first."
    fi
    if grep -q "^${DISK}" /proc/swaps 2>/dev/null; then
        die "${DISK} still has active swap; run swapoff first."
    fi

    [[ $TARGET_HOSTNAME =~ ^[A-Za-z0-9]([A-Za-z0-9-]{0,61}[A-Za-z0-9])?$ ]] \
        || die "Invalid hostname: ${TARGET_HOSTNAME}"
    [[ $TARGET_USER =~ ^[a-z_][a-z0-9_-]*$ ]] \
        || die "Invalid username (must start with a lowercase letter or underscore): ${TARGET_USER}"

    echo "Live boot mode   : ${BOOT_MODE}"
    echo "Target disk      : ${DISK}"
    echo "Kernel package   : ${KERNEL_PKG}"
    echo "Hostname / user  : ${TARGET_HOSTNAME} / ${TARGET_USER}"
    echo "Timezone / locale: ${TIMEZONE} / ${SYS_LANG}"
    echo "Log file         : ${LOG_FILE}"
    echo
    lsblk "$DISK" || true
    echo

    if [[ $BOOT_MODE == uefi ]]; then
        echo "Install mode: UEFI  -> GPT + ESP(fat32) + GRUB(x86_64-efi)"
    else
        echo "Install mode: BIOS  -> MBR + GRUB(i386-pc)"
        warn "Make sure the VM firmware really is BIOS. If the VM uses UEFI firmware, the installed system will not boot."
        warn "In that case, restart the live environment via 'EFI ... CDROM' in the Boot Manager and run this script again."
    fi
    echo

    if [[ $AUTO_CONFIRM != 1 ]]; then
        local ans
        while true; do
            read -r -p "Wipe ALL data on ${DISK}? Type YES to continue: " ans || die "Aborted."
            case "${ans^^}" in
            YES)
                break
                ;;
            '')
                echo "  -> type YES (letters only) and press Enter, or press Ctrl-C to abort."
                ;;
            *)
                die "Aborted by user."
                ;;
            esac
        done
    fi
}

update_mirrorlist() {
    print_title "Configuring pacman mirrors"

    local tmpfile url
    tmpfile="$(mktemp --suffix=-mirrorlist)"
    url='https://archlinux.org/mirrorlist/?country=CN&protocol=https&ip_version=4'

    if curl -L --retry 3 --connect-timeout 10 -so "$tmpfile" "$url" \
        && grep -q '^#Server' "$tmpfile"; then
        sed -i 's/^#Server/Server/' "$tmpfile"
        cp -f "$tmpfile" /etc/pacman.d/mirrorlist
        echo "Enabled $(grep -c '^Server' /etc/pacman.d/mirrorlist) mirror(s) from the CN list"
    else
        warn "Could not fetch the mirror list; keeping the mirrorlist shipped with the live ISO."
    fi

    rm -f "$tmpfile"
}

create_partitions() {
    print_title "Creating partition table (${BOOT_MODE})"

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
    print_title "Formatting partitions"

    local parts=("$PART_BOOT" "$PART_ROOT")
    if [[ $SWAP_SIZE_MIB -gt 0 ]]; then
        parts+=("$PART_SWAP")
    fi

    local p
    for p in "${parts[@]}"; do
        [[ -b $p ]] || die "Partition ${p} does not exist; the partition table was probably not reloaded."
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
    print_title "Mounting partitions"

    mount "$PART_ROOT" "$MNT"
    mkdir -p "$MNT/boot"
    mount "$PART_BOOT" "$MNT/boot"
    if [[ $SWAP_SIZE_MIB -gt 0 ]]; then
        swapon "$PART_SWAP"
    fi
    lsblk -f "$DISK"
}

install_base() {
    print_title "Installing base system (pacstrap)"

    # 刷新同步数据库,避免 ISO 自带的 DB 过期导致下载 404
    pacman -Syy --noconfirm || warn "Could not refresh the package databases; continuing anyway."

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
    print_title "Generating fstab"

    genfstab -U "$MNT" > "$MNT/etc/fstab"
    cat "$MNT/etc/fstab"
}

configure_system() {
    print_title "Configuring timezone / locale / initramfs"

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
    print_title "Installing network and graphics packages"

    local pkgs=(
        networkmanager network-manager-applet
        iw wireless_tools wpa_supplicant dialog netctl rp-pppoe net-tools
        xorg-server xorg-xinit xorg-twm xorg-xclock
        xf86-video-vmware xf86-input-vmmouse
    )

    # 个别可选包可能已从仓库移除,失败时降级为只装核心组件,避免整体中断
    if ! in_chroot "pacman -S --noconfirm --needed ${pkgs[*]}"; then
        warn "Some optional packages failed to install; retrying with the core set only."
        in_chroot "pacman -S --noconfirm --needed networkmanager network-manager-applet net-tools iw wireless_tools wpa_supplicant xorg-server xorg-xinit"
    fi

    in_chroot "systemctl enable NetworkManager.service"
    in_chroot "systemctl enable systemd-timesyncd.service"
}

configure_bootloader() {
    print_title "Installing and configuring the bootloader (${BOOT_MODE})"

    if [[ $BOOT_MODE == uefi ]]; then
        if ! mountpoint -q /sys/firmware/efi/efivars; then
            mount -t efivarfs efivarfs /sys/firmware/efi/efivars \
                || warn "Could not mount efivars; efibootmgr may fail to register a boot entry (the fallback path is created anyway)."
        fi

        # efibootmgr 是给固件 NVRAM 写启动项所必需的,原脚本漏装
        in_chroot "pacman -S --noconfirm --needed grub efibootmgr"
        in_chroot "grub-install --target=x86_64-efi --efi-directory=/boot --bootloader-id=GRUB --recheck"

        # 兜底:固件在 NVRAM 里找不到启动项时会自动读这个固定路径
        in_chroot "mkdir -p /boot/EFI/BOOT && cp -f /boot/EFI/GRUB/grubx64.efi /boot/EFI/BOOT/BOOTX64.EFI"

        in_chroot "grub-mkconfig -o /boot/grub/grub.cfg"

        if ! in_chroot "efibootmgr -v | grep -qi grub"; then
            warn "efibootmgr did not register a boot entry; the EFI/BOOT/BOOTX64.EFI fallback was installed and should still boot."
        fi
    else
        in_chroot "pacman -S --noconfirm --needed grub"
        in_chroot "grub-install --target=i386-pc --recheck ${DISK}"
        in_chroot "grub-mkconfig -o /boot/grub/grub.cfg"
    fi
}

configure_identity() {
    print_title "Setting hostname and root password"

    echo "$TARGET_HOSTNAME" > "$MNT/etc/hostname"
    printf '127.0.0.1\tlocalhost\n::1\t\tlocalhost\n127.0.1.1\t%s.localdomain\t%s\n' \
        "$TARGET_HOSTNAME" "$TARGET_HOSTNAME" > "$MNT/etc/hosts"

    if [[ $SKIP_PASSWD != 1 ]]; then
        echo "Set the root password now:"
        arch-chroot "$MNT" passwd
    fi
}

configure_user() {
    print_title "Creating user ${TARGET_USER}"

    in_chroot "useradd -m -G wheel -s /bin/zsh ${TARGET_USER}"
    in_chroot "sed -i 's/^# %wheel ALL=(ALL:ALL) ALL/%wheel ALL=(ALL:ALL) ALL/' /etc/sudoers"

    if [[ $NOPASSWD_SUDO == 1 ]]; then
        warn "NOPASSWD_SUDO=1: passwordless sudo for the wheel group has been enabled."
        echo '%wheel ALL=(ALL:ALL) NOPASSWD: ALL' > "$MNT/etc/sudoers.d/10-wheel-nopasswd"
        chmod 440 "$MNT/etc/sudoers.d/10-wheel-nopasswd"
    fi

    in_chroot "visudo -c"

    if [[ $SKIP_PASSWD != 1 ]]; then
        echo "Set the password for ${TARGET_USER} now:"
        arch-chroot "$MNT" passwd "$TARGET_USER"
    fi
}

verify_install() {
    print_title "Verifying the installation"

    [[ -f "$MNT/etc/fstab" ]] || die "Missing /etc/fstab"
    [[ -f "$MNT/etc/hostname" ]] || die "Missing /etc/hostname"
    [[ -f "$MNT/etc/locale.gen" ]] || die "Missing /etc/locale.gen"
    [[ -f "$MNT/boot/grub/grub.cfg" ]] || die "Missing /boot/grub/grub.cfg; the bootloader config was not generated."
    grep -q 'vmlinuz' "$MNT/boot/grub/grub.cfg" || die "No kernel entry found in grub.cfg."
    [[ -f "$MNT/boot/vmlinuz-${KERNEL_PKG}" ]] || warn "Kernel image /boot/vmlinuz-${KERNEL_PKG} not found."

    if [[ $BOOT_MODE == uefi ]]; then
        [[ -f "$MNT/boot/EFI/BOOT/BOOTX64.EFI" ]] || die "Missing fallback bootloader file EFI/BOOT/BOOTX64.EFI"
    fi

    echo
    lsblk -f "$DISK"
    echo
    echo "Boot entries found in grub.cfg:"
    grep -E '^menuentry' "$MNT/boot/grub/grub.cfg" | head -6
}

finish() {
    print_title "Finishing up"

    swapoff "$PART_SWAP" 2>/dev/null || true
    umount -R "$MNT" || warn "Unmounting ${MNT} reported problems; please check manually."

    cat <<EOF

Installation finished. Before rebooting, please make sure that:
  1) In VMware: 'VM Settings -> CD/DVD', uncheck 'Connect at power on' (or remove the ISO);
  2) In the firmware boot order, the hard disk comes before the CD-ROM;
  3) If the firmware is UEFI, 'Enable secure boot' is unchecked;
  4) Then run:  reboot

Log file: ${LOG_FILE}
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
