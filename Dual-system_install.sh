#!/usr/bin/env bash
# =============================================================================
#  arch-install.sh — Arch Linux 自动安装脚本(单系统 / 双系统;VMware 与实体机)
#
#  ── 用法 ────────────────────────────────────────────────────────────────────
#   1) 单系统,整盘安装(会清空目标磁盘):
#        bash arch-install.sh
#
#   2) 双系统,Windows 在一块盘、Linux 装到另一块盘:
#        DISK=/dev/sdb bash arch-install.sh
#      (脚本会自动检测 Windows,并让 GRUB 去探测它的启动项)
#
#   3) 双系统,同一块盘上已有 Windows,Linux 装到另一个分区:
#        ROOT_PART=/dev/sda5 EFI_PART=/dev/sda1 INSTALL_MODE=alongside bash arch-install.sh
#      (分区要你自己先用 fdisk / parted / gparted 切好)
#
#  ── 两种安装模式 ────────────────────────────────────────────────────────────
#   INSTALL_MODE=wipe       整盘安装(默认):重建分区表,自动建 ESP/swap/root
#   INSTALL_MODE=alongside  并存安装:不动分区表,不动 Windows,只格式化你指定的分区
#
#  ── alongside 模式需要指定的分区 ────────────────────────────────────────────
#   ROOT_PART=/dev/sda5   Linux 根分区(会被格式化,其中数据全部丢失)
#   EFI_PART=/dev/sda1    UEFI 下必填:现有 EFI 系统分区,与 Windows 共用,不会被格式化
#   SWAP_PART=/dev/sda6   可选:现有 swap 分区(会被 mkswap)
#   BOOT_PART=            可选:单独挂 /boot 的分区(一般留空,内核放在根分区)
#
#  ── 运行中的交互(都可用环境变量预先给出以跳过)────────────────────────────
#   1) 主机名(Hostname)      —— 直接回车用 DEFAULT_HOSTNAME
#   2) 用户名(Username)      —— 直接回车用 DEFAULT_USER
#   3) 清空目标磁盘/根分区的确认 —— 必须输入 YES / 根分区路径
#   4) root 密码、普通用户密码 —— SKIP_PASSWD=1 可跳过(不推荐)
#
#  ── 运行前确认 ──────────────────────────────────────────────────────────────
#   1) 在 archiso live 环境里以 root 身份执行;
#   2) live 环境已联网(ping -c1 archlinux.org);
#   3) 双系统请务必备份 Windows 重要数据;
#   4) 固件类型(UEFI/BIOS)与 ISO 启动模式一致,Secure Boot 已关闭。
#
#  注意:运行期输出全部使用 ASCII。Linux 虚拟终端的内核点阵字体没有汉字字形,
#  在 archiso 控制台里输出中文只会显示成方块,因此 print_title 显示步骤名,
#  中文注释只留在源码里供阅读。
# =============================================================================

set -euo pipefail

# ----------------------------- 可调参数(环境变量可覆盖) ----------------------
INSTALL_MODE="${INSTALL_MODE:-wipe}"                # wipe | alongside
DISK="${DISK:-}"                                    # wipe 模式的目标磁盘,留空自动探测
ROOT_PART="${ROOT_PART:-}"                          # alongside 模式必填
EFI_PART="${EFI_PART:-}"                            # alongside + UEFI 必填
SWAP_PART="${SWAP_PART:-}"                          # alongside 可选
BOOT_PART="${BOOT_PART:-}"                          # alongside 可选
DUAL_BOOT="${DUAL_BOOT:-auto}"                      # auto | 1 | 0
ALLOW_WIPE_WINDOWS="${ALLOW_WIPE_WINDOWS:-0}"       # 1 = 允许清空含 Windows 分区的磁盘

TARGET_HOSTNAME="${TARGET_HOSTNAME:-}"              # 留空则运行中询问
TARGET_USER="${TARGET_USER:-}"                      # 留空则运行中询问
DEFAULT_HOSTNAME="${DEFAULT_HOSTNAME:-archlinux}"   # 直接回车时使用的主机名
DEFAULT_USER="${DEFAULT_USER:-archlinux}"           # 直接回车时使用的用户名
TIMEZONE="${TIMEZONE:-Asia/Shanghai}"               # 时区
SYS_LANG="${SYS_LANG:-en_US.UTF-8}"                 # 系统语言
EXTRA_LOCALE="${EXTRA_LOCALE:-zh_CN.UTF-8}"         # 额外生成的 locale,置空则不启用
KEYMAP="${KEYMAP:-us}"                              # 控制台键位
KERNEL_PKG="${KERNEL_PKG:-linux-lts}"               # 也可用 linux
BOOT_SIZE_MIB="${BOOT_SIZE_MIB:-512}"               # wipe 模式下 ESP 或 /boot 分区大小
SWAP_SIZE_MIB="${SWAP_SIZE_MIB:-4096}"              # wipe 模式下 swap 大小,0 表示不建
NOPASSWD_SUDO="${NOPASSWD_SUDO:-0}"                 # 1 = wheel 组免密 sudo(仅调试)
SKIP_PASSWD="${SKIP_PASSWD:-0}"                     # 1 = 跳过交互式设密码(不推荐)
AUTO_CONFIRM="${AUTO_CONFIRM:-0}"                   # 1 = 全非交互,用默认值/环境变量
ENABLE_LOG="${ENABLE_LOG:-1}"                       # 1 = 同时写日志文件

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

# 标题只显示步骤名(ASCII),避免控制台出现方块
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

# 某块盘上是否存在 Windows 特征的分区(NTFS 文件系统或微软的保留/数据分区标签)
has_windows() {
    local dev=$1
    if lsblk -rno FSTYPE "$dev" 2>/dev/null | grep -qxE 'ntfs|ntfs3'; then
        return 0
    fi
    if lsblk -rno PARTLABEL "$dev" 2>/dev/null | grep -qi 'microsoft'; then
        return 0
    fi
    return 1
}

# 判断机器上是否还有别的操作系统,决定要不要让 GRUB 去探测 Windows
# DUAL_BOOT=1 强制开启,=0 强制关闭,=auto 自动判断
detect_other_os() {
    case "$DUAL_BOOT" in
    1)
        DUAL_BOOT=1
        return
        ;;
    0)
        DUAL_BOOT=''
        return
        ;;
    esac

    DUAL_BOOT=''
    if lsblk -rno FSTYPE 2>/dev/null | grep -qxE 'ntfs|ntfs3'; then
        DUAL_BOOT=1
    fi
    if lsblk -rno PARTLABEL 2>/dev/null | grep -qi 'microsoft'; then
        DUAL_BOOT=1
    fi
}

# =============================================================================
#  各阶段
# =============================================================================

#环境检查 + 交互收集主机名/用户名
preflight() {
    print_title "preflight"

    [[ $EUID -eq 0 ]] || die "Run this script as root (the archiso live environment is root by default)."
    [[ -d /run/archiso ]] || warn "This does not look like an archiso live environment; continue only if you know what you are doing."

    case "$INSTALL_MODE" in
    wipe | alongside) ;;
    *)
        die "INSTALL_MODE must be 'wipe' or 'alongside' (got '${INSTALL_MODE}')."
        ;;
    esac

    if mountpoint -q "$MNT"; then
        die "${MNT} is already mounted; run 'umount -R ${MNT}' first."
    fi

    # 判断 live 环境的启动方式:有 /sys/firmware/efi 就是 UEFI
    if [[ -d /sys/firmware/efi ]]; then
        BOOT_MODE=uefi
    else
        BOOT_MODE=bios
    fi

    if [[ $INSTALL_MODE == alongside ]]; then
        check_alongside_targets
    else
        # --------------------- 整盘模式:选盘 + 防误删 ---------------------
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

        # 关键保护:目标盘上已经有 Windows 就不许整盘清空
        if has_windows "$DISK"; then
            if [[ $ALLOW_WIPE_WINDOWS != 1 ]]; then
                die "${DISK} contains Windows-like partitions (NTFS). Wiping it would destroy Windows.
  -> To install Linux on another disk: set DISK=/dev/sdX to that disk.
  -> To install Linux into a free partition of the same disk: use INSTALL_MODE=alongside with ROOT_PART=/dev/sdXN.
  -> To really wipe it anyway: set ALLOW_WIPE_WINDOWS=1."
            fi
            warn "ALLOW_WIPE_WINDOWS=1: ${DISK} contains Windows-like partitions and WILL BE DESTROYED."
        fi

        if lsblk -no MOUNTPOINT "$DISK" 2>/dev/null | grep -q '[^[:space:]]'; then
            die "${DISK} still has mounted partitions; unmount them first."
        fi
        if grep -q "^${DISK}" /proc/swaps 2>/dev/null; then
            die "${DISK} still has active swap; run swapoff first."
        fi

        PART_BOOT="$(part_path "$DISK" 1)"
        PART_SWAP="$(part_path "$DISK" 2)"
        PART_ROOT="$(part_path "$DISK" 3)"
    fi

    detect_other_os

    # ------------------------- 交互:主机名 -------------------------
    local ans
    if [[ -z $TARGET_HOSTNAME ]]; then
        if [[ $AUTO_CONFIRM == 1 ]]; then
            TARGET_HOSTNAME="$DEFAULT_HOSTNAME"
        else
            while true; do
                read -r -p "Hostname [ex: ${DEFAULT_HOSTNAME}]: " ans || die "Aborted."
                TARGET_HOSTNAME="${ans:-$DEFAULT_HOSTNAME}"
                if [[ $TARGET_HOSTNAME =~ ^[A-Za-z0-9]([A-Za-z0-9-]{0,61}[A-Za-z0-9])?$ ]]; then
                    break
                fi
                echo "  -> invalid hostname: letters, digits and '-' only, and it must not start or end with '-'."
            done
        fi
    fi
    [[ $TARGET_HOSTNAME =~ ^[A-Za-z0-9]([A-Za-z0-9-]{0,61}[A-Za-z0-9])?$ ]] \
        || die "Invalid hostname: ${TARGET_HOSTNAME}"

    # ------------------------- 交互:用户名 -------------------------
    if [[ -z $TARGET_USER ]]; then
        if [[ $AUTO_CONFIRM == 1 ]]; then
            TARGET_USER="$DEFAULT_USER"
        else
            while true; do
                read -r -p "Username [ex: ${DEFAULT_USER}]: " ans || die "Aborted."
                TARGET_USER="${ans:-$DEFAULT_USER}"
                if [[ $TARGET_USER =~ ^[a-z_][a-z0-9_-]*$ ]]; then
                    break
                fi
                echo "  -> invalid username: lowercase letters, digits, '_' and '-' only, starting with a letter or '_'."
            done
        fi
    fi
    [[ $TARGET_USER =~ ^[a-z_][a-z0-9_-]*$ ]] \
        || die "Invalid username (must start with a lowercase letter or underscore): ${TARGET_USER}"

    # ------------------------- 安装计划摘要 -------------------------
    echo
    echo "Install mode     : ${INSTALL_MODE}"
    echo "Live boot mode   : ${BOOT_MODE}"
    if [[ $INSTALL_MODE == alongside ]]; then
        echo "Disk of root     : ${DISK}"
        echo "Root partition   : ${ROOT_PART}   <== WILL BE FORMATTED (ext4)"
        if [[ $BOOT_MODE == uefi ]]; then
            echo "EFI partition    : ${EFI_PART}   (kept, shared with Windows)"
        fi
        if [[ -n $BOOT_PART ]]; then
            echo "Boot partition   : ${BOOT_PART}   (kept, mounted at /boot)"
        fi
        if [[ -n $SWAP_PART ]]; then
            echo "Swap partition   : ${SWAP_PART}   <== WILL BE mkswap'd"
        fi
    else
        echo "Target disk      : ${DISK}   <== WILL BE WIPED"
    fi
    echo "Kernel package   : ${KERNEL_PKG}"
    echo "Hostname / user  : ${TARGET_HOSTNAME} / ${TARGET_USER}"
    echo "Timezone / locale: ${TIMEZONE} / ${SYS_LANG}"
    if [[ $DUAL_BOOT == 1 ]]; then
        echo "Dual boot        : yes - an existing Windows/other OS was detected; GRUB will probe for it"
    fi
    echo "Log file         : ${LOG_FILE}"
    echo
    lsblk -f "$DISK" || true
    echo

    if [[ $BOOT_MODE == uefi ]]; then
        echo "Install mode: UEFI  -> GRUB(x86_64-efi)"
    else
        echo "Install mode: BIOS  -> GRUB(i386-pc)"
        warn "Make sure the machine really boots in BIOS/legacy mode. With UEFI firmware the installed system would not boot."
    fi
    echo

    # ------------------------- 交互:确认清空磁盘(整盘模式)-------------------------
    if [[ $INSTALL_MODE == wipe && $AUTO_CONFIRM != 1 ]]; then
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

# 双系统并存模式的参数校验:只允许格式化用户明确指定的分区
check_alongside_targets() {
    [[ -n $ROOT_PART ]] || die "INSTALL_MODE=alongside requires ROOT_PART=/dev/sdXN (the partition you prepared for Linux)."
    [[ -b $ROOT_PART ]] || die "ROOT_PART ${ROOT_PART} is not a block device."

    DISK="/dev/$(lsblk -no PKNAME "$ROOT_PART" | head -1)"
    [[ -b $DISK ]] || die "Could not determine which disk contains ${ROOT_PART}."

    if [[ $BOOT_MODE == uefi ]]; then
        [[ -n $EFI_PART ]] || die "UEFI install requires EFI_PART=/dev/sdXN (the existing EFI system partition shared with Windows)."
        [[ -b $EFI_PART ]] || die "EFI_PART ${EFI_PART} is not a block device."
        [[ "$(lsblk -rno FSTYPE "$EFI_PART" | head -1)" == vfat ]] \
            || warn "EFI_PART ${EFI_PART} is not FAT32; make sure it really is an EFI system partition."
    fi

    [[ -z $SWAP_PART || -b $SWAP_PART ]] || die "SWAP_PART ${SWAP_PART} is not a block device."
    [[ -z $BOOT_PART || -b $BOOT_PART ]] || die "BOOT_PART ${BOOT_PART} is not a block device."

    # 一个分区不能同时扮演两个角色
    local p
    for p in "$EFI_PART" "$SWAP_PART" "$BOOT_PART"; do
        if [[ -n $p && $p == "$ROOT_PART" ]]; then
            die "${p} is used for two roles; each partition must have a single purpose."
        fi
    done
    if [[ -n $EFI_PART && $EFI_PART == "$SWAP_PART" ]] || [[ -n $EFI_PART && $EFI_PART == "$BOOT_PART" ]] \
        || [[ -n $SWAP_PART && $SWAP_PART == "$BOOT_PART" ]]; then
        die "The optional partitions overlap; each partition must have a single purpose."
    fi

    # 根分区不能是 Windows 分区
    local fstype
    fstype="$(lsblk -rno FSTYPE "$ROOT_PART" | head -1)"
    if [[ $fstype == ntfs || $fstype == ntfs3 ]]; then
        die "ROOT_PART ${ROOT_PART} holds an NTFS filesystem (most likely Windows). Refusing to format it."
    fi

    # 参与安装的分区都不能处于挂载/激活状态
    for p in "$ROOT_PART" "$EFI_PART" "$SWAP_PART" "$BOOT_PART"; do
        [[ -z $p ]] && continue
        if lsblk -rno MOUNTPOINT "$p" | grep -q '[^[:space:]]'; then
            die "${p} is currently mounted; unmount it first."
        fi
        if grep -q "^${p}[[:space:]]" /proc/swaps; then
            die "${p} is active swap; run 'swapoff ${p}' first."
        fi
    done

    # 体积提醒
    local root_size
    root_size="$(lsblk -bdno SIZE "$ROOT_PART" | head -1)"
    if [[ -n $root_size && $root_size -lt $((20 * 1024 * 1024 * 1024)) ]]; then
        warn "Root partition is smaller than 20 GiB; a full desktop install may not fit."
    fi
}

#替换仓库列表
update_mirrorlist() {
    print_title "update_mirrorlist"

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

#开始分区(仅整盘模式;并存模式绝不碰分区表)
create_partitions() {
    print_title "create_partitions"

    local boot_end swap_end
    boot_end=$((1 + BOOT_SIZE_MIB))
    swap_end=$((boot_end + SWAP_SIZE_MIB))

    wipefs -a "$DISK"                        # 清掉旧的分区表和残留签名

    if [[ $BOOT_MODE == uefi ]]; then
        # UEFI:GPT 分区表 + ESP(fat32)
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
        # BIOS:MBR 分区表 + 带 boot 标志的 /boot
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

    partprobe "$DISK" 2>/dev/null || true   # 通知内核重读分区表
    udevadm settle 2>/dev/null || true
    sleep 1
    parted -s "$DISK" print
}

#开始格式化(并存模式只格式化你明确指定的根分区和 swap)
format_partitions() {
    print_title "format_partitions"

    local p

    if [[ $INSTALL_MODE == alongside ]]; then
        echo "Partitions that WILL be formatted (all data on them is lost):"
        echo "  root : ${ROOT_PART}"
        if [[ -n $SWAP_PART ]]; then
            echo "  swap : ${SWAP_PART}"
        fi
        echo "Partitions that will NOT be touched:"
        if [[ $BOOT_MODE == uefi ]]; then
            echo "  ESP  : ${EFI_PART}  (shared with Windows)"
        fi
        if [[ -n $BOOT_PART ]]; then
            echo "  boot : ${BOOT_PART}"
        fi
        echo

        # 二次确认:要求原样输入根分区路径,避免手误选错分区
        if [[ $AUTO_CONFIRM != 1 ]]; then
            local ans
            while true; do
                read -r -p "Type the root partition path (${ROOT_PART}) to confirm formatting: " ans || die "Aborted."
                if [[ $ans == "$ROOT_PART" ]]; then
                    break
                fi
                if [[ -z $ans ]]; then
                    echo "  -> type ${ROOT_PART} exactly, or press Ctrl-C to abort."
                    continue
                fi
                die "Confirmation did not match; nothing was formatted."
            done
        fi

        wipefs -a "$ROOT_PART" >/dev/null 2>&1 || true
        mkfs.ext4 -F -L root "$ROOT_PART"

        if [[ -n $SWAP_PART ]]; then
            wipefs -a "$SWAP_PART" >/dev/null 2>&1 || true
            mkswap -L swap "$SWAP_PART"
        fi
        return
    fi

    local parts=("$PART_BOOT" "$PART_ROOT")
    if [[ $SWAP_SIZE_MIB -gt 0 ]]; then
        parts+=("$PART_SWAP")
    fi

    for p in "${parts[@]}"; do
        [[ -b $p ]] || die "Partition ${p} does not exist; the partition table was probably not reloaded."
        wipefs -a "$p" >/dev/null 2>&1 || true
    done

    if [[ $BOOT_MODE == uefi ]]; then
        mkfs.fat -F32 -n ESP "$PART_BOOT"   # ESP 必须是 FAT32
    else
        mkfs.ext4 -F -L boot "$PART_BOOT"   # BIOS 下 /boot 用 ext4
    fi

    if [[ $SWAP_SIZE_MIB -gt 0 ]]; then
        mkswap -L swap "$PART_SWAP"
    fi
    mkfs.ext4 -F -L root "$PART_ROOT"
}

#挂载分区
mount_partitions() {
    print_title "mount_partitions"

    if [[ $INSTALL_MODE == alongside ]]; then
        # 并存模式:Windows 的 ESP 挂在 /boot/efi,内核仍然放在根分区的 /boot
        mount "$ROOT_PART" "$MNT"

        if [[ -n $BOOT_PART ]]; then
            mkdir -p "$MNT/boot"
            mount "$BOOT_PART" "$MNT/boot"
        fi

        if [[ $BOOT_MODE == uefi ]]; then
            mkdir -p "$MNT/boot/efi"
            mount "$EFI_PART" "$MNT/boot/efi"
            # ESP 上如果有 Microsoft 目录,说明确实是 Windows 在用这块 ESP
            if [[ -d "$MNT/boot/efi/EFI/Microsoft" ]]; then
                DUAL_BOOT=1
                echo "Found EFI/Microsoft on ${EFI_PART}: Windows bootloader will be preserved."
            fi
        fi

        if [[ -n $SWAP_PART ]]; then
            swapon "$SWAP_PART"
        fi
    else
        mount "$PART_ROOT" "$MNT"
        mkdir -p "$MNT/boot"
        mount "$PART_BOOT" "$MNT/boot"
        if [[ $SWAP_SIZE_MIB -gt 0 ]]; then
            swapon "$PART_SWAP"
        fi
    fi

    lsblk -f "$DISK"
}

#最小安装
install_base_system() {
    print_title "install_base_system"

    # 刷新同步数据库,避免 ISO 自带的 DB 过期导致下载 404
    pacman -Syy --noconfirm || warn "Could not refresh the package databases; continuing anyway."

    # 按 CPU 厂商自动选择微码包
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

#生成标卷文件表
generate_fstab() {
    print_title "generate_fstab"

    genfstab -U "$MNT" > "$MNT/etc/fstab"
    cat "$MNT/etc/fstab"
}

#配置系统时间,地区和语言
configure_system() {
    print_title "configure_system"

    in_chroot "ln -sf /usr/share/zoneinfo/${TIMEZONE} /etc/localtime"
    in_chroot "hwclock --systohc --utc"

    # 取消 locale.gen 里对应行的注释,再生成 locale
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

#安装驱动程序
install_drivers() {
    print_title "install_drivers"

    # 说明:xf86-video-vmware 已从 Arch 仓库移除,Xorg 现在用内置 modesetting 驱动
    # 配合内核里的 vmwgfx 即可,不需要额外装 DDX;这里只装输入设备驱动。
    local pkgs=(
        xorg-server xorg-xinit xorg-twm xorg-xclock
        mesa mesa-utils
        xf86-input-libinput xf86-input-vmmouse
    )

    # 个别可选包可能已从仓库移除,失败时降级为只装核心组件,避免整体中断
    if ! in_chroot "pacman -S --noconfirm --needed ${pkgs[*]}"; then
        warn "Some optional packages failed to install; retrying with the core set only."
        in_chroot "pacman -S --noconfirm --needed xorg-server xorg-xinit mesa xf86-input-libinput"
    fi
}

#安装网络管理程序
install_networkmanager() {
    print_title "install_networkmanager"

    local pkgs=(
        iw wireless_tools wpa_supplicant dialog netctl
        networkmanager network-manager-applet rp-pppoe net-tools
    )

    if ! in_chroot "pacman -S --noconfirm --needed ${pkgs[*]}"; then
        warn "Some optional packages failed to install; retrying with the core set only."
        in_chroot "pacman -S --noconfirm --needed networkmanager network-manager-applet net-tools iw wireless_tools wpa_supplicant"
    fi

    in_chroot "systemctl enable NetworkManager.service"
    in_chroot "systemctl enable systemd-timesyncd.service"
}

#安装配置引导程序(UEFI 用 x86_64-efi,BIOS 用 i386-pc;双系统自动探测 Windows)
configure_bootloader() {
    print_title "configure_bootloader"

    # ---- 双系统:装 os-prober,并打开 grub 的探测开关 ----
    if [[ $DUAL_BOOT == 1 ]]; then
        in_chroot "pacman -S --noconfirm --needed os-prober ntfs-3g"
        in_chroot "sed -i 's/^#GRUB_DISABLE_OS_PROBER=.*/GRUB_DISABLE_OS_PROBER=false/' /etc/default/grub"
        in_chroot "grep -q '^GRUB_DISABLE_OS_PROBER=false' /etc/default/grub || echo 'GRUB_DISABLE_OS_PROBER=false' >> /etc/default/grub"
    fi

    if [[ $INSTALL_MODE == alongside ]]; then
        # ---- 并存模式:绝不覆盖 Windows 的引导文件 ----
        if [[ $BOOT_MODE == uefi ]]; then
            in_chroot "pacman -S --noconfirm --needed grub efibootmgr"
            in_chroot "grub-install --target=x86_64-efi --efi-directory=/boot/efi --bootloader-id=GRUB --recheck"
            # 这里刻意不做 EFI/BOOT/BOOTX64.EFI 兜底,那个路径属于 Windows 的 fallback 引导
        else
            warn "On BIOS systems GRUB will be written into the MBR of ${DISK}, replacing the Windows boot code."
            warn "Windows stays installed and will be reachable from the GRUB menu, but keep a Windows rescue media at hand."
            in_chroot "pacman -S --noconfirm --needed grub"
            in_chroot "grub-install --target=i386-pc --recheck ${DISK}"
        fi

        in_chroot "grub-mkconfig -o /boot/grub/grub.cfg"

        if [[ $DUAL_BOOT == 1 ]] && ! grep -qi 'windows' "$MNT/boot/grub/grub.cfg"; then
            warn "os-prober did not find a Windows entry in grub.cfg."
            warn "Windows is still bootable from the firmware boot menu (Windows Boot Manager), or you can add an entry manually."
        fi
        return
    fi

    # ---- 整盘模式 ----
    if [[ $BOOT_MODE == uefi ]]; then
        # efibootmgr 是给固件 NVRAM 写启动项所必需的
        if ! mountpoint -q /sys/firmware/efi/efivars; then
            mount -t efivarfs efivarfs /sys/firmware/efi/efivars \
                || warn "Could not mount efivars; efibootmgr may fail to register a boot entry (the fallback path is created anyway)."
        fi

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

#添加本地域名(Hostname)与 root 密码
configure_hostname() {
    print_title "configure_hostname"

    echo "$TARGET_HOSTNAME" > "$MNT/etc/hostname"
    printf '127.0.0.1\tlocalhost\n::1\t\tlocalhost\n127.0.1.1\t%s.localdomain\t%s\n' \
        "$TARGET_HOSTNAME" "$TARGET_HOSTNAME" > "$MNT/etc/hosts"

    if [[ $SKIP_PASSWD != 1 ]]; then
        echo "Set the root password now:"
        arch-chroot "$MNT" passwd
    fi
}

#添加普通用户
configure_username() {
    print_title "configure_username"

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

#安装结果校验:任何一项不通过就直接报错,不等到重启才发现
verify_install() {
    print_title "verify_install"

    [[ -f "$MNT/etc/fstab" ]] || die "Missing /etc/fstab"
    [[ -f "$MNT/etc/hostname" ]] || die "Missing /etc/hostname"
    [[ -f "$MNT/etc/locale.gen" ]] || die "Missing /etc/locale.gen"
    [[ -f "$MNT/boot/grub/grub.cfg" ]] || die "Missing /boot/grub/grub.cfg; the bootloader config was not generated."
    grep -q 'vmlinuz' "$MNT/boot/grub/grub.cfg" || die "No kernel entry found in grub.cfg."
    [[ -f "$MNT/boot/vmlinuz-${KERNEL_PKG}" ]] || warn "Kernel image /boot/vmlinuz-${KERNEL_PKG} not found."

    if [[ $BOOT_MODE == uefi ]]; then
        if [[ $INSTALL_MODE == alongside ]]; then
            [[ -f "$MNT/boot/efi/EFI/GRUB/grubx64.efi" ]] || die "Missing /boot/efi/EFI/GRUB/grubx64.efi"
        else
            [[ -f "$MNT/boot/EFI/BOOT/BOOTX64.EFI" ]] || die "Missing fallback bootloader file EFI/BOOT/BOOTX64.EFI"
        fi
    fi

    echo
    echo "Install mode     : ${INSTALL_MODE}"
    echo "Hostname / user  : ${TARGET_HOSTNAME} / ${TARGET_USER}"
    echo
    lsblk -f "$DISK"
    echo
    echo "Boot entries found in grub.cfg:"
    grep -E '^menuentry' "$MNT/boot/grub/grub.cfg" | head -8
}

#收尾:卸载并给出重启前的检查清单
finish() {
    print_title "finish"

    if [[ $INSTALL_MODE == alongside ]]; then
        [[ -n $SWAP_PART ]] && swapoff "$SWAP_PART" 2>/dev/null || true
    else
        swapoff "$PART_SWAP" 2>/dev/null || true
    fi
    umount -R "$MNT" || warn "Unmounting ${MNT} reported problems; please check manually."

    cat <<EOF

Installation finished.
  Install mode : ${INSTALL_MODE}
  Hostname     : ${TARGET_HOSTNAME}
  User         : ${TARGET_USER}

Before rebooting, please make sure that:
  1) In the firmware boot order, the disk you just installed to comes before others
     (VMware: 'VM Settings -> CD/DVD', uncheck 'Connect at power on' if you still have the ISO attached);
  2) If the firmware is UEFI, 'Enable secure boot' is unchecked;
  3) Then run:  reboot
EOF

    if [[ $DUAL_BOOT == 1 ]]; then
        cat <<'EOF'

Dual boot notes:
  * Windows is expected to appear as a menu entry in GRUB.
  * If it is missing, boot Windows from the firmware boot menu
    ('Windows Boot Manager') and check os-prober output.
EOF
    fi

    echo
    echo "Log file: ${LOG_FILE}"
    sleep 0.3
}

main() {
    if [[ $ENABLE_LOG == 1 ]]; then
        exec > >(tee -a "$LOG_FILE") 2>&1
    fi

    preflight
    update_mirrorlist
    if [[ $INSTALL_MODE == wipe ]]; then
        create_partitions
    fi
    format_partitions
    mount_partitions
    install_base_system
    generate_fstab
    configure_system
    install_drivers
    install_networkmanager
    configure_bootloader
    configure_hostname
    configure_username
    verify_install
    finish
}

main "$@"
