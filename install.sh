#!/usr/bin/env bash
# =============================================================================
#  arch-install.sh — Arch Linux 自动安装脚本(单系统 / 双系统;VMware 与实体机)
#
#  ── 用法 ────────────────────────────────────────────────────────────────────
#   最简单的方式:直接运行,脚本会先问属于哪种情况:
#        bash arch-install.sh
#
#   启动菜单(选项 1 / 2 / 3):
#     1) 单系统,整盘安装         —— 清空指定磁盘,自动建 ESP/swap/Btrfs
#     2) 双系统,装到另一块盘     —— Windows 在一块盘,Linux 装到另一块盘(会列出所有磁盘供选)
#     3) 双系统,装到同盘分区     —— 保留 Windows,Linux 装到同一块盘的另一个分区
#                                  (会列出所有分区,分别询问 /、ESP、/home、/boot、swap)
#
#   选项 1 / 2 还会先问分区布局与各分区大小(在询问主机名之前),默认方案来自
#   arch.icekylin.online 的基础安装教程:
#       1) 一个 Btrfs 分区里用子卷 @ 和 @home 分别承载 / 和 /home(教程默认,
#          timeshift 只认这种子卷布局)
#          ——注意:这两个子卷共享整个分区,你输入的是「两者合计」的大小;
#             若确实要给每个子卷一个上限,可以在询问时选 btrfs quota,
#             脚本会 btrfs quota enable + btrfs qgroup limit 给 @ 和 @home 各设上限
#       2) / 和 /home 各自独立分区(共四个分区:ESP、swap、/、/home),
#          这样就能像 /boot 和 swap 一样,分别给 / 和 /home 指定大小
#       /boot 是 EFI 分区(FAT32,挂载在 /boot),swap 默认取内存的 60%
#
#   也可以用环境变量跳过菜单(适合脚本化/无人值守):
#        DISK=/dev/sdb bash arch-install.sh                     # 等价于选项 2
#        INSTALL_MODE=alongside ROOT_PART=/dev/sda5 EFI_PART=/dev/sda1 \
#            bash arch-install.sh                                # 等价于选项 3
#
#  ── 两种安装模式 ────────────────────────────────────────────────────────────
#   INSTALL_MODE=wipe       整盘安装(默认):重建分区表,自动建 ESP/swap/root
#   INSTALL_MODE=alongside  并存安装:不动分区表,不动 Windows,只格式化你指定的分区
#
#  ── alongside 模式需要指定的分区 ────────────────────────────────────────────
#   ROOT_PART=/dev/sda5   Linux 根分区(会被格式化,其中数据全部丢失)
#   EFI_PART=/dev/sda1    UEFI 下必填:现有 EFI 系统分区,与 Windows 共用,不会被格式化
#   HOME_PART=/dev/sda7   可选:独立的 /home 分区;留空则与 / 共用 Btrfs 子卷布局
#   SWAP_PART=/dev/sda6   可选:现有 swap 分区(会被 mkswap)
#   BOOT_PART=            可选:单独挂 /boot 的分区(一般留空,内核放在根分区)
#
#  ── 文件系统与容量(可环境变量指定,留空则交互询问)──────────────────────────
#   FS_TYPE=btrfs         btrfs(默认,含 compress=zstd)或 ext4
#   LAYOUT=subvol         subvol(默认,/ 与 /home 同一分区)/ split(两个独立分区)
#   BOOT_SIZE_MIB=512     ESP 大小;SWAP_SIZE_MIB=8192 swap 大小(0=不建)
#   ROOT_SIZE_MIB=51200   / 大小;HOME_SIZE_MIB=131072  /home 大小(仅 split)
#   BTRFS_COMPRESS=zstd   透明压缩,置空则关闭
#
#  ── 双系统推荐布局(同一块盘,保留 Windows)─────────────────────────────────
#   复用 Windows 的 ESP(不格式化),在空闲空间里再切四块:
#       /boot    1G    ext4   —— 内核与 initramfs 单独放这里
#       /       60G    btrfs  子卷 @
#       /home   40G    btrfs  子卷 @home
#       swap     8G    —— 建议不小于内存的 60%
#   然后在选项 3 里依次指定这四块即可(见下面的交互顺序)。
#   为什么推荐单独切 /boot:GRUB 读内核和 grub.cfg 时只碰 ext4,完全不用解析
#   带 zstd 压缩的 Btrfs,兼容性最好;Windows 那块 260M 的小 ESP 也不会被塞满。
#   注意:MBR(msdos)分区表最多 4 个主分区;若 Windows 已占满 4 个,新建的 Linux
#   分区需要建成扩展分区里的逻辑分区(用 gparted / cfdisk 操作即可,脚本不关心)。
#
#  ── 运行中的交互(都可用环境变量预先给出以跳过)────────────────────────────
#   1) 分区布局(Btrfs 子卷 / 两个独立分区)
#   2) ESP、swap、/、/home 各自的大小(支持 512M / 4G / 64G 写法)
#   3) 主机名(Hostname)      —— 直接回车用 DEFAULT_HOSTNAME
#   4) 用户名(Username)      —— 直接回车用 DEFAULT_USER
#   5) 清空目标磁盘/根分区的确认 —— 必须输入 YES / 根分区路径
#   6) root 密码、普通用户密码 —— SKIP_PASSWD=1 可跳过(不推荐)
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
INSTALL_MODE="${INSTALL_MODE:-}"                    # 留空则启动时交互选择;wipe | alongside
DISK="${DISK:-}"                                    # wipe 模式的目标磁盘,留空自动探测
ROOT_PART="${ROOT_PART:-}"                          # alongside 模式必填
EFI_PART="${EFI_PART:-}"                            # alongside + UEFI 必填
SWAP_PART="${SWAP_PART:-}"                          # alongside 可选
BOOT_PART="${BOOT_PART:-}"                          # alongside 可选
HOME_PART="${HOME_PART:-}"                          # alongside 可选:独立的 /home 分区
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
LAYOUT="${LAYOUT:-}"                                # 留空则询问;subvol | split
FS_TYPE="${FS_TYPE:-btrfs}"                         # btrfs | ext4
BOOT_SIZE_MIB="${BOOT_SIZE_MIB:-}"                  # ESP(/boot)大小,留空则整盘安装时询问
SWAP_SIZE_MIB="${SWAP_SIZE_MIB:-}"                  # swap 大小,留空则询问;0 = 不建 swap
ROOT_SIZE_MIB="${ROOT_SIZE_MIB:-}"                  # / 大小,留空则询问
HOME_SIZE_MIB="${HOME_SIZE_MIB:-}"                  # /home 独立分区大小(仅 split 布局)
ROOT_QUOTA_MIB="${ROOT_QUOTA_MIB:-}"                # 可选:子卷 @ 的 qgroup 上限(仅 subvol 布局)
HOME_QUOTA_MIB="${HOME_QUOTA_MIB:-}"                # 可选:子卷 @home 的 qgroup 上限(仅 subvol 布局)
BTRFS_COMPRESS="${BTRFS_COMPRESS:-zstd}"            # Btrfs 透明压缩,置空则不启用
BOOTLOADER_ID="${BOOTLOADER_ID:-ARCH}"              # 与教程一致
GRUB_CMDLINE="${GRUB_CMDLINE:-loglevel=5 nowatchdog}"   # 教程推荐的 GRUB 内核参数
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

# ---- 磁盘 / 分区扫描(供交互选择使用)-----------------------------------------
DISK_CANDIDATES=()
PART_CANDIDATES=()
USED_PARTS=()

# 扫描所有物理磁盘
scan_disks() {
    DISK_CANDIDATES=()
    local name
    for name in $(lsblk -dno NAME,TYPE 2>/dev/null | awk '$2=="disk"{print $1}'); do
        case "$name" in
        loop* | zram* | sr* | fd* | ram*) continue ;;
        esac
        DISK_CANDIDATES+=("/dev/$name")
    done
}

# 扫描所有分区
scan_parts() {
    PART_CANDIDATES=()
    local name
    for name in $(lsblk -rno NAME,TYPE 2>/dev/null | awk '$2=="part"{print $1}'); do
        PART_CANDIDATES+=("/dev/$name")
    done
}

# 列出磁盘:编号、设备、容量、型号,并标出含 Windows 的盘
show_disks() {
    if [[ ${#DISK_CANDIDATES[@]} -eq 0 ]]; then
        scan_disks
    fi
    printf '  %-4s %-14s %-9s %s\n' "No." "DEVICE" "SIZE" "MODEL / NOTE"
    local i dev size model note
    for i in "${!DISK_CANDIDATES[@]}"; do
        dev="${DISK_CANDIDATES[$i]}"
        size="$(lsblk -drno SIZE "$dev" 2>/dev/null | head -1)"
        model="$(lsblk -dno MODEL "$dev" 2>/dev/null | head -1)"
        note=""
        if has_windows "$dev"; then
            note="<== contains Windows: do NOT choose this one"
        fi
        printf '  %-4s %-14s %-9s %s %s\n' "$((i + 1))" "$dev" "${size:-?}" "$model" "$note"
    done
}

# 列出分区:编号、设备、容量、文件系统,并标出用途倾向
show_parts() {
    if [[ ${#PART_CANDIDATES[@]} -eq 0 ]]; then
        scan_parts
    fi
    printf '  %-4s %-14s %-8s %-9s %s\n' "No." "DEVICE" "SIZE" "FSTYPE" "NOTE"
    local i dev size fstype label mnt note
    for i in "${!PART_CANDIDATES[@]}"; do
        dev="${PART_CANDIDATES[$i]}"
        size="$(lsblk -drno SIZE "$dev" 2>/dev/null | head -1)"
        fstype="$(lsblk -drno FSTYPE "$dev" 2>/dev/null | head -1)"
        label="$(lsblk -drno LABEL "$dev" 2>/dev/null | head -1)"
        mnt="$(lsblk -no MOUNTPOINT "$dev" 2>/dev/null | head -1)"
        case "$fstype" in
        ntfs | ntfs3)
            note="Windows (NTFS) - do NOT use"
            ;;
        vfat)
            note="FAT32 - likely the EFI system partition"
            ;;
        "")
            note="no filesystem - good target for /"
            ;;
        *)
            note="$fstype"
            ;;
        esac
        if [[ -n $label ]]; then
            note="${note}; label=${label}"
        fi
        if [[ -n $mnt ]]; then
            note="${note}; mounted at ${mnt}"
        fi
        printf '  %-4s %-14s %-8s %-9s %s\n' "$((i + 1))" "$dev" "${size:-?}" "${fstype:-none}" "$note"
    done
}

# 把用户输入(列表编号或设备路径)换算成设备路径
resolve_choice() {
    local ans=$1
    shift
    local -a cands=("$@")
    if [[ $ans =~ ^[0-9]+$ ]]; then
        if ((ans >= 1 && ans <= ${#cands[@]})); then
            printf '%s' "${cands[$((ans - 1))]}"
            return 0
        fi
        return 1
    fi
    printf '%s' "$ans"
}

# 交互选择装到哪块整盘
ask_disk() {
    scan_disks
    [[ ${#DISK_CANDIDATES[@]} -gt 0 ]] || die "No disk found on this machine."
    show_disks
    echo
    local ans dev
    while true; do
        read -r -p "Install Arch Linux on which disk? [number or /dev/...]: " ans || die "Aborted."
        if [[ -z $ans ]]; then
            echo "  -> enter a number from the list above, or a device path such as /dev/sdb."
            continue
        fi
        if ! dev="$(resolve_choice "$ans" "${DISK_CANDIDATES[@]}")"; then
            echo "  -> no such entry in the list above."
            continue
        fi
        if [[ ! -b $dev ]]; then
            echo "  -> ${dev} is not a block device."
            continue
        fi
        if [[ "$(lsblk -drno TYPE "$dev" 2>/dev/null | head -1)" != disk ]]; then
            echo "  -> ${dev} is not a whole disk. This mode installs Arch onto a whole disk."
            continue
        fi
        DISK="$dev"
        break
    done
    echo "Selected disk: ${DISK}"
    if has_windows "$DISK"; then
        warn "The selected disk contains Windows-like partitions. Wiping it will destroy Windows."
    fi
}

# 交互选择某个角色用哪个分区,结果写回 $2 指定的变量
ask_partition() {
    local role="$1" varname="$2" allow_empty="$3"
    local ans dev fstype u dup
    while true; do
        if [[ $allow_empty == 1 ]]; then
            read -r -p "${role} [number or /dev/...; Enter = skip]: " ans || die "Aborted."
        else
            read -r -p "${role} [number or /dev/...]: " ans || die "Aborted."
        fi

        if [[ -z $ans ]]; then
            if [[ $allow_empty == 1 ]]; then
                printf -v "$varname" '%s' ''
                return 0
            fi
            echo "  -> this partition is required."
            continue
        fi

        if ! dev="$(resolve_choice "$ans" "${PART_CANDIDATES[@]}")"; then
            echo "  -> no such entry in the list above."
            continue
        fi
        if [[ ! -b $dev ]]; then
            echo "  -> ${dev} is not a block device."
            continue
        fi
        if [[ "$(lsblk -drno TYPE "$dev" 2>/dev/null | head -1)" != part ]]; then
            echo "  -> ${dev} is a whole disk, not a partition. Create the partitions first (fdisk / parted / gparted)."
            continue
        fi

        fstype="$(lsblk -drno FSTYPE "$dev" 2>/dev/null | head -1)"

        # 先看这个分区是不是已经分配给别的角色了
        dup=''
        for u in "${USED_PARTS[@]}"; do
            if [[ -n $u && $u == "$dev" ]]; then
                dup=1
            fi
        done
        if [[ -n $dup ]]; then
            echo "  -> ${dev} is already used for another role."
            continue
        fi

        if [[ $varname == ROOT_PART ]]; then
            if [[ $fstype == ntfs || $fstype == ntfs3 ]]; then
                echo "  -> ${dev} contains NTFS (probably Windows); refusing to use it as root."
                continue
            fi
        fi
        if [[ $varname == EFI_PART ]]; then
            if [[ $fstype != vfat ]]; then
                echo "  -> ${dev} is not FAT32. The EFI system partition must be FAT32 (usually the one Windows uses)."
                continue
            fi
        fi

        printf -v "$varname" '%s' "$dev"
        USED_PARTS+=("$dev")
        echo "  -> ${role}: ${dev}"
        return 0
    done
}

# ---- 容量换算 + 分区规划 ------------------------------------------------------
# 把 512M / 4G / 64 / 1T 换算成 MiB
to_mib() {
    local v="${1^^}" num unit
    if [[ ! $v =~ ^([0-9]+)([KMGTP]I?B?)?$ ]]; then
        return 1
    fi
    num="${BASH_REMATCH[1]}"
    unit="${BASH_REMATCH[2]}"
    case "$unit" in
    '' | M | MI | MB | MIB)
        printf '%s' "$num"
        ;;
    K | KI | KB | KIB)
        printf '%s' "$((num / 1024))"
        ;;
    G | GI | GB | GIB)
        printf '%s' "$((num * 1024))"
        ;;
    T | TI | TB | TIB)
        printf '%s' "$((num * 1024 * 1024))"
        ;;
    *)
        return 1
        ;;
    esac
}

# MiB 换成人看的单位
mib_human() {
    local mib=$1
    if ((mib >= 1048576)); then
        printf '%s TiB' "$((mib / 1048576))"
    elif ((mib >= 1024)); then
        printf '%s GiB' "$((mib / 1024))"
    else
        printf '%s MiB' "$mib"
    fi
}

# 询问容量,提示走 stderr,数值走 stdout
ask_size() {
    local prompt="$1" default_mib="$2" max_mib="${3:-}" ans mib
    while true; do
        printf '%s [%s]: ' "$prompt" "$(mib_human "$default_mib")" >&2
        read -r ans || die "Aborted."
        ans="${ans:-$default_mib}"
        if ! mib="$(to_mib "$ans")"; then
            echo "  -> cannot parse '${ans}'. Use 512M, 4G, 64G or a plain number of MiB." >&2
            continue
        fi
        if [[ -n $max_mib && $mib -gt $max_mib ]]; then
            echo "  -> too large: at most $(mib_human "$max_mib") is available here." >&2
            continue
        fi
        printf '%s' "$mib"
        return 0
    done
}

# Btrfs 挂载参数:子卷 + 可选透明压缩
btrfs_opts() {
    local o="subvol=/$1"
    if [[ -n $BTRFS_COMPRESS ]]; then
        o="$o,compress=$BTRFS_COMPRESS"
    fi
    printf '%s' "$o"
}

# 整盘安装:在询问主机名之前,先问布局并分配各分区大小
ask_layout_and_sizes() {
    print_title "disk layout"

    local total_mib usable
    total_mib=$(( $(lsblk -bdno SIZE "$DISK" 2>/dev/null) / 1048576 ))
    ((total_mib > 0)) || die "Could not read the size of ${DISK}."
    usable=$((total_mib - 2))

    local ram_mib swap_default
    ram_mib=$(( $(awk '/^MemTotal:/{print $2}' /proc/meminfo) / 1024 ))
    swap_default=$(( (ram_mib * 6 / 10 + 255) / 256 * 256 ))    # 教程:不小于内存的 60%
    ((swap_default > 0)) || swap_default=4096

    echo "Target disk : ${DISK}  ($(mib_human "$total_mib"))"
    echo "Filesystem  : ${FS_TYPE}   (set FS_TYPE=ext4 to use ext4)"
    echo "Memory      : $(mib_human "$ram_mib")"
    echo
    echo "The guide (arch.icekylin.online) recommends:"
    echo "  /boot  ESP   256M-512M (FAT32, mounted at /boot)"
    echo "  swap         >= 60% of the RAM (so hibernation can work)"
    echo "  / + /home    one Btrfs partition with the subvolumes @ and @home"
    echo "               (timeshift only supports that subvolume layout)"
    echo

    local ans
    if [[ -z $LAYOUT ]]; then
        echo "How should / and /home be laid out? NOTE: they cannot share one Btrfs"
        echo "partition and have separate fixed sizes - pick 2 if you want that."
        echo "  1) one Btrfs partition with subvolumes @ and @home   (guide default)"
        echo "     / and /home SHARE this partition; the size you type below is the"
        echo "     total for both of them (optionally capped with btrfs quota later)"
        echo "  2) two separate Btrfs partitions for / and /home     (four partitions)"
        echo "     you give / and /home their own sizes, just like /boot and swap"
        echo
        while true; do
            read -r -p "Type 1 or 2 [1]: " ans || die "Aborted."
            case "${ans:-1}" in
            1)
                LAYOUT=subvol
                break
                ;;
            2)
                LAYOUT=split
                break
                ;;
            *)
                echo "  -> please type 1 or 2."
                ;;
            esac
        done
        echo
    fi

    if [[ -z $BOOT_SIZE_MIB ]]; then
        BOOT_SIZE_MIB="$(ask_size "EFI partition (/boot) size" 512)"
    fi
    if [[ -z $SWAP_SIZE_MIB ]]; then
        SWAP_SIZE_MIB="$(ask_size "swap partition size (0 = no swap)" "$swap_default")"
    fi

    local rest=$((usable - BOOT_SIZE_MIB - SWAP_SIZE_MIB))
    ((rest > 4096)) || die "Not enough space left for / (only $(mib_human "$rest"))."

    if [[ $LAYOUT == subvol ]]; then
        if [[ -z $ROOT_SIZE_MIB ]]; then
            ROOT_SIZE_MIB="$(ask_size "Btrfs partition size (TOTAL for / and /home)" "$rest" "$rest")"
        fi
        HOME_SIZE_MIB=0
        # 可选:用 btrfs qgroup 给两个子卷各设一个上限(默认不设,共享整个分区)
        if [[ -z $ROOT_QUOTA_MIB && -z $HOME_QUOTA_MIB && $AUTO_CONFIRM != 1 ]]; then
            echo
            echo "  / and /home share all $(mib_human "$ROOT_SIZE_MIB") of this partition."
            echo "  You can either leave it shared (default), or put a size cap on each"
            echo "  subvolume with btrfs quota."
            local q
            read -r -p "  Cap / and /home individually with btrfs quota? [y/N]: " q || die "Aborted."
            case "${q,,}" in
            y | yes)
                ROOT_QUOTA_MIB="$(ask_size "  size cap for /" "$((ROOT_SIZE_MIB / 2))" "$ROOT_SIZE_MIB")"
                HOME_QUOTA_MIB="$(ask_size "  size cap for /home" "$((ROOT_SIZE_MIB - ROOT_QUOTA_MIB))" "$((ROOT_SIZE_MIB - ROOT_QUOTA_MIB))")"
                ;;
            esac
        fi
    else
        local root_default
        if ((rest >= 262144)); then
            root_default=131072        # 教程:日常使用给 / 128G 就够
        else
            root_default=$((rest / 2))
        fi
        if [[ -z $ROOT_SIZE_MIB ]]; then
            ROOT_SIZE_MIB="$(ask_size "root (/) partition size" "$root_default" "$((rest - 4096))")"
        fi
        if [[ -z $HOME_SIZE_MIB ]]; then
            HOME_SIZE_MIB="$(ask_size "/home partition size" "$((rest - ROOT_SIZE_MIB))" "$((rest - ROOT_SIZE_MIB))")"
        fi
    fi

    echo
    echo "Planned partitions on ${DISK}:"
    echo "  /boot  ESP     $(mib_human "$BOOT_SIZE_MIB")   fat32"
    if [[ $SWAP_SIZE_MIB -gt 0 ]]; then
        echo "  swap           $(mib_human "$SWAP_SIZE_MIB")   (60% of RAM = $(mib_human "$swap_default"))"
    else
        echo "  swap           none"
    fi
    if [[ $HOME_SIZE_MIB -gt 0 ]]; then
        echo "  /              $(mib_human "$ROOT_SIZE_MIB")   ${FS_TYPE}, subvol @"
        echo "  /home          $(mib_human "$HOME_SIZE_MIB")   ${FS_TYPE}, subvol @home"
    else
        echo "  / + /home      $(mib_human "$ROOT_SIZE_MIB")   ${FS_TYPE}, one partition with subvols @ and @home"
        if [[ -n $ROOT_QUOTA_MIB || -n $HOME_QUOTA_MIB ]]; then
            echo "                 quota caps: / = $(mib_human "${ROOT_QUOTA_MIB:-0}"), /home = $(mib_human "${HOME_QUOTA_MIB:-0}")"
        else
            echo "                 no per-subvolume cap: / and /home share the whole partition"
        fi
    fi
    echo
}

# 整盘安装:按实际存在的分区给设备名赋值(顺序:/boot、swap?、/、/home?)
assign_wipe_parts() {
    local n=0
    n=$((n + 1))
    PART_BOOT="$(part_path "$DISK" "$n")"
    if [[ $SWAP_SIZE_MIB -gt 0 ]]; then
        n=$((n + 1))
        PART_SWAP="$(part_path "$DISK" "$n")"
    else
        PART_SWAP=''
    fi
    n=$((n + 1))
    PART_ROOT="$(part_path "$DISK" "$n")"
    if [[ $HOME_SIZE_MIB -gt 0 ]]; then
        n=$((n + 1))
        PART_HOME="$(part_path "$DISK" "$n")"
    else
        PART_HOME=''
    fi
}

# 启动时询问属于哪种安装情况
choose_install_mode() {
    print_title "choose_install_mode"
    cat <<'EOF'
Which situation are you in?

  1) Single system : wipe one whole disk and install Arch Linux on it
                     (everything on that disk will be erased)

  2) Dual boot     : Windows is on one disk, install Arch Linux on ANOTHER disk
                     (the Windows disk is left untouched)

  3) Dual boot     : Windows already occupies part of a disk, install Arch Linux
                     into another partition of the SAME disk
                     (create that partition with fdisk / parted / gparted first)

EOF
    local ans
    while true; do
        read -r -p "Type 1, 2 or 3: " ans || die "Aborted."
        case "$ans" in
        1)
            INSTALL_MODE=wipe
            scan_disks
            if [[ ${#DISK_CANDIDATES[@]} -eq 1 ]]; then
                DISK="${DISK_CANDIDATES[0]}"
                echo "Only one disk found (${DISK}); using it."
            elif [[ ${#DISK_CANDIDATES[@]} -eq 0 ]]; then
                die "No disk found on this machine."
            else
                ask_disk
            fi
            break
            ;;
        2)
            INSTALL_MODE=wipe
            echo
            echo "Available disks (the one holding Windows is marked - do not choose it):"
            ask_disk
            break
            ;;
        3)
            INSTALL_MODE=alongside
            echo
            echo "Available partitions:"
            show_parts
            echo
            echo "   root (/)      : will be FORMATTED as ${FS_TYPE} - all data on it is lost"
            echo "   EFI partition : the EXISTING EFI system partition, shared with Windows, never formatted"
            echo "   /home, /boot, swap : optional, press Enter to skip"
            echo "   If you skip /home and the filesystem is btrfs, / and /home will share the"
            echo "   root partition through the subvolumes @ and @home (guide layout)."
            echo
            ask_partition "root (/)" ROOT_PART 0
            if [[ $BOOT_MODE == uefi ]]; then
                ask_partition "EFI partition (/boot/efi)" EFI_PART 0
            fi
            ask_partition "/home partition" HOME_PART 1
            ask_partition "/boot partition" BOOT_PART 1
            ask_partition "swap partition" SWAP_PART 1
            break
            ;;
        *)
            echo "  -> please type 1, 2 or 3."
            ;;
        esac
    done
}

# =============================================================================
#  各阶段
# =============================================================================

#环境检查 + 交互收集主机名/用户名
preflight() {
    print_title "preflight"

    [[ $EUID -eq 0 ]] || die "Run this script as root (the archiso live environment is root by default)."
    [[ -d /run/archiso ]] || warn "This does not look like an archiso live environment; continue only if you know what you are doing."

    if mountpoint -q "$MNT"; then
        die "${MNT} is already mounted; run 'umount -R ${MNT}' first."
    fi

    # 判断 live 环境的启动方式:有 /sys/firmware/efi 就是 UEFI
    if [[ -d /sys/firmware/efi ]]; then
        BOOT_MODE=uefi
    else
        BOOT_MODE=bios
    fi

    # 选择安装类型:环境变量已给出 INSTALL_MODE 时直接采用,不再询问
    if [[ -z $INSTALL_MODE ]]; then
        if [[ $AUTO_CONFIRM == 1 ]]; then
            INSTALL_MODE=wipe
        else
            choose_install_mode
        fi
    fi

    case "$INSTALL_MODE" in
    wipe | alongside) ;;
    *)
        die "INSTALL_MODE must be 'wipe' or 'alongside' (got '${INSTALL_MODE}')."
        ;;
    esac

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

        # 交互规划分区:先选布局,再分配各分区大小(在询问主机名之前)
        ask_layout_and_sizes
        assign_wipe_parts
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
    [[ -z $HOME_PART || -b $HOME_PART ]] || die "HOME_PART ${HOME_PART} is not a block device."

    # 一个分区不能同时扮演两个角色
    local i j
    local -a roles=("$ROOT_PART" "$EFI_PART" "$SWAP_PART" "$BOOT_PART" "$HOME_PART")
    for i in "${!roles[@]}"; do
        for j in "${!roles[@]}"; do
            if [[ $i -lt $j && -n ${roles[$i]} && ${roles[$i]} == "${roles[$j]}" ]]; then
                die "${roles[$i]} is used for two roles; each partition must have a single purpose."
            fi
        done
    done

    # 根分区不能是 Windows 分区
    local fstype
    fstype="$(lsblk -rno FSTYPE "$ROOT_PART" | head -1)"
    if [[ $fstype == ntfs || $fstype == ntfs3 ]]; then
        die "ROOT_PART ${ROOT_PART} holds an NTFS filesystem (most likely Windows). Refusing to format it."
    fi

    # 参与安装的分区都不能处于挂载/激活状态
    local p
    for p in "$ROOT_PART" "$EFI_PART" "$SWAP_PART" "$BOOT_PART" "$HOME_PART"; do
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

    # 分区顺序:/boot、swap(可选)、/(可选再跟一个独立的 /home)
    # 说明:这里传给 parted 的文件系统名只决定分区表里的类型码,btrfs 与 ext4
    # 在 GPT 上都属于 Linux filesystem,所以统一写 ext4,真正的格式在下一步做。
    local boot_start=1
    local boot_end=$((boot_start + BOOT_SIZE_MIB))
    local swap_start=$boot_end
    local swap_end=$((swap_start + SWAP_SIZE_MIB))
    local root_start=$swap_end          # 没有 swap 时 SWAP_SIZE_MIB=0,起点正好接上
    local root_end=$((root_start + ROOT_SIZE_MIB))
    local home_start=$root_end

    wipefs -a "$DISK"                        # 清掉旧的分区表和残留签名

    local idx=0
    if [[ $BOOT_MODE == uefi ]]; then
        # UEFI:GPT 分区表 + ESP(fat32)
        parted -s "$DISK" mklabel gpt
        idx=1
        parted -s "$DISK" mkpart ESP fat32 "${boot_start}MiB" "${boot_end}MiB"
        parted -s "$DISK" set "$idx" esp on
    else
        # BIOS:MBR 分区表 + 带 boot 标志的 /boot
        parted -s "$DISK" mklabel msdos
        idx=1
        parted -s "$DISK" mkpart primary ext4 "${boot_start}MiB" "${boot_end}MiB"
        parted -s "$DISK" set "$idx" boot on
    fi

    if [[ $SWAP_SIZE_MIB -gt 0 ]]; then
        idx=$((idx + 1))
        if [[ $BOOT_MODE == uefi ]]; then
            parted -s "$DISK" mkpart swap linux-swap "${swap_start}MiB" "${swap_end}MiB"
        else
            parted -s "$DISK" mkpart primary linux-swap "${swap_start}MiB" "${swap_end}MiB"
        fi
    fi

    if [[ $HOME_SIZE_MIB -gt 0 ]]; then
        # 四分区方案:/ 与 /home 各自独立,最后一个分区用满剩余空间
        idx=$((idx + 1))
        if [[ $BOOT_MODE == uefi ]]; then
            parted -s "$DISK" mkpart root ext4 "${root_start}MiB" "${root_end}MiB"
        else
            parted -s "$DISK" mkpart primary ext4 "${root_start}MiB" "${root_end}MiB"
        fi
        if [[ $BOOT_MODE == uefi ]]; then
            parted -s "$DISK" mkpart home ext4 "${home_start}MiB" 100%
        else
            parted -s "$DISK" mkpart primary ext4 "${home_start}MiB" 100%
        fi
    else
        # 三分区方案(教程默认):Btrfs 分区同时承载 / 和 /home
        if [[ $BOOT_MODE == uefi ]]; then
            parted -s "$DISK" mkpart root ext4 "${root_start}MiB" 100%
        else
            parted -s "$DISK" mkpart primary ext4 "${root_start}MiB" 100%
        fi
    fi

    partprobe "$DISK" 2>/dev/null || true   # 通知内核重读分区表
    udevadm settle 2>/dev/null || true
    sleep 1
    parted -s "$DISK" print
}

# 在分区上创建文件系统;btrfs 时顺带创建子卷
# $1=分区 $2=卷标 $3=要创建的子卷(空格分隔,可为空)
make_linux_fs() {
    local part=$1 label=$2 subvols=$3 sv
    if [[ $FS_TYPE == btrfs ]]; then
        mkfs.btrfs -f -L "$label" "$part"
        if [[ -n $subvols ]]; then
            mount "$part" "$MNT"          # 这时 $MNT 还是干净的挂载点
            for sv in $subvols; do
                btrfs subvolume create "$MNT/$sv"
            done

            # 可选:给子卷设 qgroup 上限(只有用户显式要求时才做)
            local quota_needed=0
            for sv in $subvols; do
                if [[ $sv == "@" && -n $ROOT_QUOTA_MIB ]]; then
                    quota_needed=1
                fi
                if [[ $sv == "@home" && -n $HOME_QUOTA_MIB ]]; then
                    quota_needed=1
                fi
            done
            if [[ $quota_needed == 1 ]]; then
                btrfs quota enable "$MNT"
                for sv in $subvols; do
                    if [[ $sv == "@" && -n $ROOT_QUOTA_MIB ]]; then
                        btrfs qgroup limit "${ROOT_QUOTA_MIB}M" "$MNT/@"
                    fi
                    if [[ $sv == "@home" && -n $HOME_QUOTA_MIB ]]; then
                        btrfs qgroup limit "${HOME_QUOTA_MIB}M" "$MNT/@home"
                    fi
                done
            fi

            umount "$MNT"
        fi
    else
        mkfs.ext4 -F -L "$label" "$part"
    fi
}

#开始格式化(并存模式只格式化你明确指定的根分区、/home 和 swap)
format_partitions() {
    print_title "format_partitions"

    local p

    # 是否把 / 和 /home 放在同一个 Btrfs 分区上(教程默认布局)
    SHARED_BTRFS=0
    if [[ $FS_TYPE == btrfs ]]; then
        if [[ $INSTALL_MODE == alongside ]]; then
            if [[ -z $HOME_PART ]]; then
                SHARED_BTRFS=1
            fi
        else
            if [[ -z $PART_HOME ]]; then
                SHARED_BTRFS=1
            fi
        fi
    fi

    if [[ $INSTALL_MODE == alongside ]]; then
        # /boot 单独分区时:并存场景下它通常是新切出来的分区,默认格式化
        # (统一用 ext4,这样 GRUB 读内核和 grub.cfg 完全不用碰 Btrfs 及其压缩)
        local format_boot=0
        if [[ -n $BOOT_PART ]]; then
            if [[ $AUTO_CONFIRM == 1 ]]; then
                format_boot="${FORMAT_BOOT:-1}"
            else
                local b
                read -r -p "Format the separate /boot partition ${BOOT_PART} as ext4? [Y/n]: " b || die "Aborted."
                case "${b,,}" in
                n | no) format_boot=0 ;;
                *) format_boot=1 ;;
                esac
            fi
        fi

        echo "Partitions that WILL be formatted (all data on them is lost):"
        echo "  root : ${ROOT_PART}   (${FS_TYPE})"
        if [[ -n $HOME_PART ]]; then
            echo "  home : ${HOME_PART}   (${FS_TYPE})"
        fi
        if [[ -n $SWAP_PART ]]; then
            echo "  swap : ${SWAP_PART}"
        fi
        if [[ -n $BOOT_PART && $format_boot == 1 ]]; then
            echo "  boot : ${BOOT_PART}   (ext4)"
        fi
        echo "Partitions that will NOT be touched:"
        if [[ $BOOT_MODE == uefi ]]; then
            echo "  ESP  : ${EFI_PART}  (shared with Windows; only EFI/${BOOTLOADER_ID} is added)"
        fi
        if [[ -n $BOOT_PART && $format_boot != 1 ]]; then
            echo "  boot : ${BOOT_PART}  (kept as is)"
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
        if [[ $SHARED_BTRFS == 1 ]]; then
            make_linux_fs "$ROOT_PART" root "@ @home"
        else
            make_linux_fs "$ROOT_PART" root "@"
        fi

        if [[ -n $HOME_PART ]]; then
            wipefs -a "$HOME_PART" >/dev/null 2>&1 || true
            make_linux_fs "$HOME_PART" home "@home"
        fi

        if [[ -n $SWAP_PART ]]; then
            wipefs -a "$SWAP_PART" >/dev/null 2>&1 || true
            mkswap -L swap "$SWAP_PART"
        fi

        if [[ -n $BOOT_PART && $format_boot == 1 ]]; then
            wipefs -a "$BOOT_PART" >/dev/null 2>&1 || true
            mkfs.ext4 -F -L boot "$BOOT_PART"
        fi
        return
    fi

    local parts=("$PART_BOOT" "$PART_ROOT")
    if [[ -n $PART_SWAP ]]; then
        parts+=("$PART_SWAP")
    fi
    if [[ -n $PART_HOME ]]; then
        parts+=("$PART_HOME")
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

    if [[ -n $PART_SWAP ]]; then
        mkswap -L swap "$PART_SWAP"
    fi

    if [[ $SHARED_BTRFS == 1 ]]; then
        make_linux_fs "$PART_ROOT" root "@ @home"
    else
        make_linux_fs "$PART_ROOT" root "@"
    fi

    if [[ -n $PART_HOME ]]; then
        make_linux_fs "$PART_HOME" home "@home"
    fi
}

#挂载分区(按教程的顺序:/ → /home → /boot → swap)
mount_partitions() {
    print_title "mount_partitions"

    if [[ $INSTALL_MODE == alongside ]]; then
        # 并存模式:与 Windows 共用磁盘,ESP 挂在 /boot/efi,内核仍然放在根分区
        if [[ $FS_TYPE == btrfs ]]; then
            mount -t btrfs -o "$(btrfs_opts @)" "$ROOT_PART" "$MNT"
        else
            mount "$ROOT_PART" "$MNT"
        fi

        if [[ -n $HOME_PART ]]; then
            mkdir -p "$MNT/home"
            if [[ $FS_TYPE == btrfs ]]; then
                mount -t btrfs -o "$(btrfs_opts @home)" "$HOME_PART" "$MNT/home"
            else
                mount "$HOME_PART" "$MNT/home"
            fi
        elif [[ $SHARED_BTRFS == 1 ]]; then
            mkdir -p "$MNT/home"
            mount -t btrfs -o "$(btrfs_opts @home)" "$ROOT_PART" "$MNT/home"
        fi

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
        # 整盘安装:ESP 挂在 /boot
        if [[ $FS_TYPE == btrfs ]]; then
            mount -t btrfs -o "$(btrfs_opts @)" "$PART_ROOT" "$MNT"
        else
            mount "$PART_ROOT" "$MNT"
        fi

        if [[ -n $PART_HOME ]]; then
            mkdir -p "$MNT/home"
            if [[ $FS_TYPE == btrfs ]]; then
                mount -t btrfs -o "$(btrfs_opts @home)" "$PART_HOME" "$MNT/home"
            else
                mount "$PART_HOME" "$MNT/home"
            fi
        elif [[ $SHARED_BTRFS == 1 ]]; then
            mkdir -p "$MNT/home"
            mount -t btrfs -o "$(btrfs_opts @home)" "$PART_ROOT" "$MNT/home"
        fi

        mkdir -p "$MNT/boot"
        mount "$PART_BOOT" "$MNT/boot"

        if [[ -n $PART_SWAP ]]; then
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
        vim nano sudo zsh zsh-completions
        wqy-zenhei wqy-microhei ttf-dejavu adobe-source-code-pro-fonts
    )
    if [[ -n $ucode ]]; then
        pkgs+=("$ucode")
    fi
    if [[ $FS_TYPE == btrfs ]]; then
        pkgs+=(btrfs-progs)      # 教程:使用 Btrfs 必须装上 btrfs-progs
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

# 按教程调整 /etc/default/grub:去掉 quiet、提高日志级别、加 nowatchdog
tune_grub_defaults() {
    in_chroot "sed -i 's|^GRUB_CMDLINE_LINUX_DEFAULT=.*|GRUB_CMDLINE_LINUX_DEFAULT=\"${GRUB_CMDLINE}\"|' /etc/default/grub"
}

#安装配置引导程序(UEFI 用 x86_64-efi,BIOS 用 i386-pc;双系统自动探测 Windows)
configure_bootloader() {
    print_title "configure_bootloader"

    # ---- 双系统:装 os-prober,并打开 grub 的探测开关 ----
    if [[ $DUAL_BOOT == 1 ]]; then
        in_chroot "pacman -S --noconfirm --needed os-prober ntfs-3g"
        in_chroot "sed -i 's/^#GRUB_DISABLE_OS_PROBER=.*/GRUB_DISABLE_OS_PROBER=false/' /etc/default/grub"
        in_chroot "grep -q '^GRUB_DISABLE_OS_PROBER=false' /etc/default/grub || echo 'GRUB_DISABLE_OS_PROBER=false' >> /etc/default/grub"
        # 先单独跑一次 os-prober,把它的输出打出来,便于判断有没有识别到 Windows
        echo "Looking for other operating systems (os-prober):"
        in_chroot "os-prober" || warn "os-prober returned a non-zero status."
    fi

    if [[ $INSTALL_MODE == alongside ]]; then
        # ---- 并存模式:绝不覆盖 Windows 的引导文件 ----
        if [[ $BOOT_MODE == uefi ]]; then
            in_chroot "pacman -S --noconfirm --needed grub efibootmgr"
            in_chroot "grub-install --target=x86_64-efi --efi-directory=/boot/efi --bootloader-id=${BOOTLOADER_ID} --recheck"
            # 这里刻意不做 EFI/BOOT/BOOTX64.EFI 兜底,那个路径属于 Windows 的 fallback 引导
        else
            warn "On BIOS systems GRUB will be written into the MBR of ${DISK}, replacing the Windows boot code."
            warn "Windows stays installed and will be reachable from the GRUB menu, but keep a Windows rescue media at hand."
            in_chroot "pacman -S --noconfirm --needed grub"
            in_chroot "grub-install --target=i386-pc --recheck ${DISK}"
        fi

        tune_grub_defaults
        in_chroot "grub-mkconfig -o /boot/grub/grub.cfg"
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
        in_chroot "grub-install --target=x86_64-efi --efi-directory=/boot --bootloader-id=${BOOTLOADER_ID} --recheck"

        # 兜底:固件在 NVRAM 里找不到启动项时会自动读这个固定路径
        in_chroot "mkdir -p /boot/EFI/BOOT && cp -f /boot/EFI/${BOOTLOADER_ID}/grubx64.efi /boot/EFI/BOOT/BOOTX64.EFI"

        tune_grub_defaults
        in_chroot "grub-mkconfig -o /boot/grub/grub.cfg"

        if ! in_chroot "efibootmgr -v | grep -qi grub"; then
            warn "efibootmgr did not register a boot entry; the EFI/BOOT/BOOTX64.EFI fallback was installed and should still boot."
        fi
    else
        in_chroot "pacman -S --noconfirm --needed grub"
        in_chroot "grub-install --target=i386-pc --recheck ${DISK}"
        tune_grub_defaults
        in_chroot "grub-mkconfig -o /boot/grub/grub.cfg"
    fi

    # 双系统:确认 Windows 条目真的进了 grub.cfg
    if [[ $DUAL_BOOT == 1 ]] && ! grep -qi 'windows' "$MNT/boot/grub/grub.cfg"; then
        warn "os-prober did not find a Windows entry in grub.cfg."
        warn "This is a known limitation of running os-prober inside a chroot."
        warn "After the first boot into Arch, run:  sudo os-prober && sudo grub-mkconfig -o /boot/grub/grub.cfg"
        warn "Windows also stays bootable from the firmware boot menu (Windows Boot Manager)."
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
            [[ -f "$MNT/boot/efi/EFI/${BOOTLOADER_ID}/grubx64.efi" ]] || die "Missing /boot/efi/EFI/${BOOTLOADER_ID}/grubx64.efi"
        else
            [[ -f "$MNT/boot/EFI/BOOT/BOOTX64.EFI" ]] || die "Missing fallback bootloader file EFI/BOOT/BOOTX64.EFI"
        fi
    fi

    # Btrfs 子卷要真的写进 fstab,否则重启后挂载不到 / 和 /home
    if [[ $FS_TYPE == btrfs ]]; then
        grep -q 'btrfs' "$MNT/etc/fstab" || die "No btrfs entry in /etc/fstab"
        grep -q 'subvol=/@' "$MNT/etc/fstab" || warn "No 'subvol=/@' entry in /etc/fstab; check the mount options."
        if [[ -d "$MNT/home" ]]; then
            mountpoint -q "$MNT/home" || warn "/home is not a separate mount point (it will just be a directory on /)."
        fi
        if [[ -n $ROOT_QUOTA_MIB || -n $HOME_QUOTA_MIB ]]; then
            echo
            echo "btrfs quota limits:"
            in_chroot "btrfs qgroup show -reF /" 2>/dev/null | sed 's/^/  /' || true
        fi
    fi

    echo
    echo "Install mode     : ${INSTALL_MODE}   (btrfs layout: ${LAYOUT})"
    echo "Hostname / user  : ${TARGET_HOSTNAME} / ${TARGET_USER}"
    echo
    lsblk -f "$DISK"
    echo
    echo "Mounted filesystems:"
    df -h "$MNT" "$MNT/boot" 2>/dev/null | sed 's/^/  /'
    if mountpoint -q "$MNT/home"; then
        df -h "$MNT/home" 2>/dev/null | sed 's/^/  /'
    fi
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
