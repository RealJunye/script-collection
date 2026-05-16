#!/bin/bash

# 磁盘自动挂载脚本 v3.1 - 修复版
# 支持新硬盘极速模式 + 已有数据磁盘安全模式

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m'

# 全局变量
declare -g DISK_HAS_DATA=false
declare -g DISK_HAS_PARTITIONS=false
declare -g DISK_IS_MOUNTED=false
declare -g DISK_HAS_FILESYSTEM=false

# 检查是否为root用户
check_root() {
    if [[ $EUID -ne 0 ]]; then
        echo -e "${RED}错误: 此脚本需要root权限运行${NC}"
        echo "请使用: sudo $0"
        exit 1
    fi
}

# 打印带颜色的信息
print_info() {
    echo -e "${BLUE}[信息]${NC} $1"
}

print_success() {
    echo -e "${GREEN}[成功]${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}[警告]${NC} $1"
}

print_error() {
    echo -e "${RED}[错误]${NC} $1"
}

print_danger() {
    echo -e "${RED}${BOLD}[危险]${NC} $1"
}

# 显示分隔线
print_separator() {
    echo -e "${BLUE}========================================${NC}"
}

# 安全确认函数
safe_confirm() {
    local prompt=$1
    local confirm_word=${2:-"YES"}
    
    echo ""
    print_danger "$prompt"
    read -p "请输入 '$confirm_word' 确认操作: " user_input
    
    if [[ "$user_input" != "$confirm_word" ]]; then
        print_info "操作已取消"
        return 1
    fi
    return 0
}

# 检测系统中的磁盘
detect_disks() {
    print_separator
    print_info "正在检测系统磁盘..."
    print_separator
    
    mapfile -t DISKS < <(lsblk -nd -o NAME,SIZE,TYPE | grep disk | awk '{print "/dev/"$1}')
    
    if [ ${#DISKS[@]} -eq 0 ]; then
        print_error "未检测到任何磁盘！"
        exit 1
    fi
    
    echo ""
    echo "检测到以下磁盘："
    echo ""
    printf "%-6s %-15s %-10s %-15s %-12s %-10s\n" "序号" "设备名" "大小" "型号" "挂载状态" "分区数"
    echo "------------------------------------------------------------------------"
    
    local index=1
    declare -g -A DISK_INFO
    declare -g -A DISK_DETAILS
    
    for disk in "${DISKS[@]}"; do
        local size=$(lsblk -nd -o SIZE "$disk" 2>/dev/null)
        local model=$(lsblk -nd -o MODEL "$disk" 2>/dev/null | xargs)
        local mounted=$(lsblk -n -o MOUNTPOINT "$disk" 2>/dev/null | grep -v "^$" | head -1)
        local part_count=$(lsblk -ln -o NAME "$disk" | tail -n +2 | wc -l)
        
        # 检查是否为系统盘
        local is_system=""
        if mount | grep -q "^${disk}.*on / "; then
            is_system=" ${RED}[系统盘]${NC}"
            mounted="${mounted} (系统)"
        fi
        
        if [ -z "$mounted" ]; then
            mounted="未挂载"
        fi
        
        printf "%-6s %-15s %-10s %-15s %-12s %-10s" "[$index]" "$disk" "$size" "${model:0:15}" "$mounted" "$part_count"
        echo -e "$is_system"
        
        DISK_INFO[$index]="$disk"
        DISK_DETAILS[$disk]="size:$size,model:$model,mounted:$mounted,partitions:$part_count"
        ((index++))
    done
    
    echo ""
}

# 选择磁盘 - 修复版
select_disk() {
    local disk_count=${#DISK_INFO[@]}
    
    while true; do
        read -p "请选择要操作的磁盘序号 [1-$disk_count] (输入 q 退出): " choice
        
        if [[ "$choice" == "q" ]] || [[ "$choice" == "Q" ]]; then
            print_info "用户取消操作"
            exit 0
        fi
        
        # 检查是否为数字
        if ! [[ "$choice" =~ ^[0-9]+$ ]]; then
            print_error "请输入有效的数字！"
            continue
        fi
        
        # 检查范围
        if [ "$choice" -ge 1 ] && [ "$choice" -le "$disk_count" ]; then
            SELECTED_DISK=${DISK_INFO[$choice]}
            print_success "已选择磁盘: $SELECTED_DISK"
            return 0
        else
            print_error "无效的选择，请输入 1-$disk_count 之间的数字！"
        fi
    done
}

# 深度分析磁盘状态
analyze_disk() {
    local disk=$1
    
    print_separator
    print_info "正在深度分析磁盘: $disk"
    print_separator
    echo ""
    
    # 1. 检查是否为系统盘
    if mount | grep -q "^${disk}.*on / "; then
        print_danger "这是系统盘！禁止操作！"
        exit 1
    fi
    
    # 2. 检查挂载状态
    local mounted_partitions=$(mount | grep "^${disk}" | awk '{print $1}')
    if [ -n "$mounted_partitions" ]; then
        DISK_IS_MOUNTED=true
        print_warning "磁盘有分区已挂载："
        mount | grep "^${disk}" | while read line; do
            echo "  → $line"
        done
        echo ""
    else
        print_success "✓ 磁盘未挂载"
        DISK_IS_MOUNTED=false
    fi
    
    # 3. 检查分区
    local partitions=$(lsblk -ln -o NAME "$disk" | tail -n +2)
    if [ -n "$partitions" ]; then
        DISK_HAS_PARTITIONS=true
        local part_count=$(echo "$partitions" | wc -l)
        print_warning "磁盘有 $part_count 个分区："
        lsblk "$disk" -o NAME,SIZE,FSTYPE,LABEL,MOUNTPOINT
        echo ""
    else
        print_success "✓ 磁盘无分区（全新磁盘）"
        DISK_HAS_PARTITIONS=false
    fi
    
    # 4. 检查文件系统
    local has_fs=false
    if blkid "$disk" >/dev/null 2>&1; then
        has_fs=true
    else
        # 检查分区
        for part in ${disk}*; do
            if [ -b "$part" ] && [ "$part" != "$disk" ]; then
                if blkid "$part" >/dev/null 2>&1; then
                    has_fs=true
                    break
                fi
            fi
        done
    fi
    
    if [ "$has_fs" = true ]; then
        DISK_HAS_FILESYSTEM=true
        print_warning "磁盘或分区有文件系统："
        blkid | grep "$disk" | while read line; do
            echo "  → $line"
        done
        echo ""
    else
        print_success "✓ 无文件系统（未格式化）"
        DISK_HAS_FILESYSTEM=false
    fi
    
    # 5. 尝试检测数据（简单检查）
    print_info "检查磁盘数据..."
    
    # 读取磁盘前几个扇区检查是否为空
    local first_sectors=$(dd if="$disk" bs=512 count=100 2>/dev/null | od -An -tx1 | tr -d ' \n')
    local zero_pattern=$(printf '%0100d' 0 | tr '0' '00')
    
    if [ "$first_sectors" = "$zero_pattern" ] || [ -z "$first_sectors" ]; then
        print_success "✓ 磁盘为空（全新磁盘）"
        DISK_HAS_DATA=false
    else
        if [ "$DISK_HAS_FILESYSTEM" = true ] || [ "$DISK_HAS_PARTITIONS" = true ]; then
            print_warning "磁盘可能包含数据"
            DISK_HAS_DATA=true
        else
            print_info "磁盘有写入痕迹，但无法识别数据"
            DISK_HAS_DATA=false
        fi
    fi
    
    echo ""
    print_separator
    print_info "磁盘状态汇总"
    print_separator
    
    echo -e "${CYAN}磁盘路径:${NC} $disk"
    echo -e "${CYAN}磁盘大小:${NC} $(lsblk -nd -o SIZE $disk)"
    echo -e "${CYAN}是否挂载:${NC} $([ "$DISK_IS_MOUNTED" = true ] && echo -e "${RED}是${NC}" || echo -e "${GREEN}否${NC}")"
    echo -e "${CYAN}有无分区:${NC} $([ "$DISK_HAS_PARTITIONS" = true ] && echo -e "${YELLOW}是${NC}" || echo -e "${GREEN}否${NC}")"
    echo -e "${CYAN}有无文件系统:${NC} $([ "$DISK_HAS_FILESYSTEM" = true ] && echo -e "${YELLOW}是${NC}" || echo -e "${GREEN}否${NC}")"
    echo -e "${CYAN}可能有数据:${NC} $([ "$DISK_HAS_DATA" = true ] && echo -e "${RED}是${NC}" || echo -e "${GREEN}否${NC}")"
    echo ""
    
    # 判断磁盘类型
    if [ "$DISK_HAS_DATA" = false ] && [ "$DISK_HAS_PARTITIONS" = false ] && [ "$DISK_HAS_FILESYSTEM" = false ]; then
        echo -e "${GREEN}${BOLD}→ 这是一块全新硬盘，可以使用极速模式！${NC}"
        DISK_TYPE="new"
    else
        echo -e "${YELLOW}${BOLD}→ 这是一块已使用的磁盘，将使用安全模式！${NC}"
        DISK_TYPE="used"
    fi
    
    echo ""
}

# 安全确认（根据磁盘状态）
safety_confirmation() {
    local disk=$1
    
    print_separator
    print_warning "操作确认"
    print_separator
    echo ""
    
    if [ "$DISK_TYPE" = "new" ]; then
        print_info "检测到这是一块新硬盘"
        echo ""
        read -p "确认要对 $disk 进行分区和格式化吗？ [yes/no]: " confirm
        
        if [[ "$confirm" != "yes" ]]; then
            print_info "操作已取消"
            exit 0
        fi
    else
        print_danger "警告：检测到磁盘已被使用！"
        echo ""
        
        if [ "$DISK_IS_MOUNTED" = true ]; then
            print_danger "磁盘有分区正在挂载中！"
        fi
        
        if [ "$DISK_HAS_DATA" = true ]; then
            print_danger "磁盘可能包含重要数据！"
        fi
        
        echo ""
        echo -e "${RED}${BOLD}继续操作将：${NC}"
        echo "  1. 删除所有分区"
        echo "  2. 清除所有数据"
        echo "  3. 重新格式化磁盘"
        echo ""
        
        if ! safe_confirm "这将永久删除磁盘上的所有数据！" "DELETE"; then
            exit 0
        fi
        
        echo ""
        print_warning "最后确认：请再次输入磁盘路径确认操作"
        read -p "请输入 '$disk': " disk_confirm
        
        if [[ "$disk_confirm" != "$disk" ]]; then
            print_info "输入不匹配，操作已取消"
            exit 0
        fi
    fi
    
    print_success "确认通过，开始操作..."
    echo ""
}

# 卸载磁盘
unmount_disk() {
    local disk=$1
    
    if [ "$DISK_IS_MOUNTED" = false ]; then
        return 0
    fi
    
    print_separator
    print_info "卸载磁盘分区..."
    print_separator
    
    # 获取所有挂载的分区
    local mounted_parts=$(mount | grep "^${disk}" | awk '{print $1}')
    
    for part in $mounted_parts; do
        print_info "卸载: $part"
        umount "$part" 2>/dev/null
        
        if [ $? -eq 0 ]; then
            print_success "已卸载: $part"
        else
            print_warning "强制卸载: $part"
            umount -l "$part" 2>/dev/null
        fi
    done
    
    # 等待卸载完成
    sleep 1
    
    # 验证卸载
    if mount | grep -q "^${disk}"; then
        print_error "卸载失败！请手动卸载后重试"
        exit 1
    fi
    
    print_success "所有分区已卸载"
    echo ""
}

# 清除分区表
wipe_disk() {
    local disk=$1
    
    print_separator
    print_info "清除旧分区表..."
    print_separator
    
    # 使用wipefs清除所有文件系统签名
    if command -v wipefs &> /dev/null; then
        wipefs -a "$disk" >/dev/null 2>&1
    fi
    
    # 清除分区表
    dd if=/dev/zero of="$disk" bs=512 count=1 conv=notrunc 2>/dev/null
    
    # 清除GPT备份表（在磁盘末尾）
    dd if=/dev/zero of="$disk" bs=512 count=1 seek=$(($(blockdev --getsz "$disk") - 1)) 2>/dev/null
    
    # 通知内核
    partprobe "$disk" 2>/dev/null
    sleep 1
    
    print_success "分区表已清除"
    echo ""
}

# 极速分区
fast_partition() {
    local disk=$1
    
    print_separator
    print_info "创建新分区..."
    print_separator
    
    # 优先使用sgdisk
    if command -v sgdisk &> /dev/null; then
        print_info "使用 sgdisk（快速模式）"
        sgdisk -Z "$disk" >/dev/null 2>&1
        sgdisk -n 1:0:0 -t 1:8300 "$disk" >/dev/null 2>&1
    else
        print_info "使用 parted"
        parted -s "$disk" mklabel gpt
        parted -s "$disk" mkpart primary 0% 100%
    fi
    
    if [ $? -ne 0 ]; then
        print_error "分区创建失败！"
        return 1
    fi
    
    # 通知内核
    partprobe "$disk" 2>/dev/null
    sleep 2
    
    # 等待设备节点出现
    local max_wait=10
    local waited=0
    while [ ! -b "${disk}1" ] && [ $waited -lt $max_wait ]; do
        sleep 1
        ((waited++))
    done
    
    if [ ! -b "${disk}1" ]; then
        print_error "分区设备节点未出现！"
        return 1
    fi
    
    print_success "分区创建成功: ${disk}1"
    echo ""
}

# 选择格式化模式
select_format_mode() {
    if [ "$DISK_TYPE" = "new" ]; then
        print_separator
        print_info "选择格式化模式："
        print_separator
        echo "1) 极速模式 - 最快，适合新硬盘（推荐）"
        echo "2) 标准模式 - 常规格式化"
        echo ""
        
        while true; do
            read -p "请选择 [1-2, 默认1]: " mode_choice
            mode_choice=${mode_choice:-1}
            
            case $mode_choice in
                1)
                    FORMAT_SPEED="ultra"
                    print_success "已选择: 极速模式"
                    break
                    ;;
                2)
                    FORMAT_SPEED="standard"
                    print_success "已选择: 标准模式"
                    break
                    ;;
                *)
                    print_error "无效选择"
                    ;;
            esac
        done
    else
        FORMAT_SPEED="standard"
        print_info "使用标准格式化模式"
    fi
    echo ""
}

# 选择文件系统
select_filesystem() {
    print_separator
    print_info "选择文件系统类型："
    print_separator
    echo "1) ext4 - 通用，稳定可靠（推荐）"
    echo "2) xfs  - 大文件性能优秀"
    echo "3) ext3 - 传统文件系统"
    echo ""
    
    while true; do
        read -p "请选择 [1-3, 默认1]: " fs_choice
        fs_choice=${fs_choice:-1}
        
        case $fs_choice in
            1)
                FS_TYPE="ext4"
                break
                ;;
            2)
                FS_TYPE="xfs"
                break
                ;;
            3)
                FS_TYPE="ext3"
                break
                ;;
            *)
                print_error "无效选择"
                ;;
        esac
    done
    
    print_success "文件系统: $FS_TYPE"
    echo ""
}

# 格式化磁盘
format_disk() {
    local device=$1
    
    print_separator
    print_info "开始格式化: $device"
    print_separator
    echo ""
    
    local disk_size=$(lsblk -nd -o SIZE "$device" 2>/dev/null | xargs)
    print_info "设备: $device"
    print_info "大小: $disk_size"
    print_info "文件系统: $FS_TYPE"
    print_info "模式: $FORMAT_SPEED"
    echo ""
    
    print_info "格式化中，请稍候..."
    
    case $FS_TYPE in
        ext4)
            if [ "$FORMAT_SPEED" = "ultra" ]; then
                # 极速模式
                mkfs.ext4 -F \
                    -E nodiscard \
                    -E lazy_itable_init=1,lazy_journal_init=1 \
                    -m 0 \
                    "$device" 2>&1 | grep -E "(Creating|Writing)" | while read line; do
                        echo "  $line"
                    done
            else
                # 标准模式
                mkfs.ext4 -F -E nodiscard "$device" 2>&1 | grep -v "Discarding"
            fi
            ;;
        xfs)
            if [ "$FORMAT_SPEED" = "ultra" ]; then
                mkfs.xfs -f -K -l lazy-count=1 "$device" 2>&1
            else
                mkfs.xfs -f -K "$device" 2>&1
            fi
            ;;
        ext3)
            mkfs.ext3 -F -E nodiscard "$device" 2>&1 | grep -v "Discarding"
            ;;
    esac
    
    local exit_code=$?
    echo ""
    
    if [ $exit_code -eq 0 ]; then
        print_success "格式化完成！"
        FORMATTED_DEVICE="$device"
        return 0
    else
        print_error "格式化失败！"
        return 1
    fi
}

# 选择挂载点
select_mount_point() {
    print_separator
    print_info "配置挂载点"
    print_separator
    
    echo "常用挂载点："
    echo "1) /data       - 推荐"
    echo "2) /mnt/data"
    echo "3) /home/data"
    echo "4) /opt/data"
    echo "5) 自定义路径"
    echo ""
    
    while true; do
        read -p "请选择 [1-5, 默认1]: " mount_choice
        mount_choice=${mount_choice:-1}
        
        case $mount_choice in
            1)
                MOUNT_POINT="/data"
                break
                ;;
            2)
                MOUNT_POINT="/mnt/data"
                break
                ;;
            3)
                MOUNT_POINT="/home/data"
                break
                ;;
            4)
                MOUNT_POINT="/opt/data"
                break
                ;;
            5)
                read -p "请输入自定义路径: " custom_path
                if [[ "$custom_path" =~ ^/[a-zA-Z0-9/_-]+$ ]]; then
                    MOUNT_POINT="$custom_path"
                    break
                else
                    print_error "无效的路径格式！"
                fi
                ;;
            *)
                print_error "无效选择"
                ;;
        esac
    done
    
    print_success "挂载点: $MOUNT_POINT"
    echo ""
}

# 挂载磁盘
mount_disk_now() {
    local device=$1
    local mount_point=$2
    
    print_separator
    print_info "挂载磁盘..."
    print_separator
    
    # 创建挂载点
    if [ ! -d "$mount_point" ]; then
        mkdir -p "$mount_point"
        print_info "已创建挂载点: $mount_point"
    fi
    
    # 挂载
    mount "$device" "$mount_point"
    
    if [ $? -eq 0 ]; then
        print_success "挂载成功！"
        
        # 设置权限
        chmod 755 "$mount_point"
        print_info "已设置目录权限: 755"
        
        echo ""
        return 0
    else
        print_error "挂载失败！"
        return 1
    fi
}

# 配置自动挂载
setup_auto_mount() {
    local device=$1
    local mount_point=$2
    
    print_separator
    print_info "配置开机自动挂载"
    print_separator
    
    read -p "是否配置开机自动挂载？ [Y/n]: " auto_mount
    auto_mount=${auto_mount:-Y}
    
    if [[ "$auto_mount" != "y" ]] && [[ "$auto_mount" != "Y" ]]; then
        print_info "跳过自动挂载配置"
        echo ""
        return 0
    fi
    
    # 获取UUID
    local uuid=$(blkid -s UUID -o value "$device")
    
    if [ -z "$uuid" ]; then
        print_error "无法获取UUID！"
        return 1
    fi
    
    print_info "UUID: $uuid"
    
    # 备份fstab
    local backup_file="/etc/fstab.backup.$(date +%Y%m%d_%H%M%S)"
    cp /etc/fstab "$backup_file"
    print_info "已备份 fstab 到: $backup_file"
    
    # 删除可能的旧条目（根据UUID或挂载点）
    sed -i "/$uuid/d" /etc/fstab 2>/dev/null
    sed -i "\|$mount_point|d" /etc/fstab 2>/dev/null
    
    # 添加新条目（使用noatime提升性能）
    local fstab_entry="UUID=$uuid  $mount_point  $FS_TYPE  defaults,noatime  0  2"
    echo "$fstab_entry" >> /etc/fstab
    
    print_success "已添加到 /etc/fstab"
    echo "  → $fstab_entry"
    
    # 测试fstab
    print_info "测试 fstab 配置..."
    mount -a
    
    if [ $? -eq 0 ]; then
        print_success "fstab 配置测试通过！"
    else
        print_error "fstab 配置有误！已回滚"
        mv "$backup_file" /etc/fstab
        return 1
    fi
    
    echo ""
    return 0
}

# 显示最终结果
show_final_result() {
    print_separator
    echo -e "${GREEN}${BOLD}✓ 磁盘挂载成功！${NC}"
    print_separator
    echo ""
    
    echo -e "${CYAN}${BOLD}挂载信息：${NC}"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo -e "  设备路径    : ${GREEN}$FORMATTED_DEVICE${NC}"
    echo -e "  挂载点      : ${GREEN}$MOUNT_POINT${NC}"
    echo -e "  文件系统    : ${GREEN}$FS_TYPE${NC}"
    echo -e "  UUID        : ${GREEN}$(blkid -s UUID -o value $FORMATTED_DEVICE)${NC}"
    echo -e "  磁盘大小    : ${GREEN}$(lsblk -nd -o SIZE $FORMATTED_DEVICE)${NC}"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo ""
    
    print_separator
    print_info "当前磁盘使用情况"
    print_separator
    df -h | head -1
    df -h | grep "$MOUNT_POINT"
    echo ""
    
    print_separator
    print_info "所有磁盘分区信息"
    print_separator
    lsblk -o NAME,SIZE,FSTYPE,LABEL,MOUNTPOINT | grep -A20 "$(basename $SELECTED_DISK)"
    echo ""
    
    print_separator
    print_success "操作完成！磁盘已就绪！"
    print_separator
    
    echo ""
    print_info "提示："
    echo "  • 挂载点: $MOUNT_POINT"
    echo "  • 开机自动挂载已配置"
    echo "  • 可以开始使用此磁盘了"
    echo ""
}

# 主函数
main() {
    clear
    echo -e "${GREEN}"
    cat << "EOF"
╔══════════════════════════════════════════════╗
║   Linux 磁盘智能挂载工具 v3.1               ║
║   Smart Disk Mount Script                    ║
║   • 支持新硬盘极速模式                       ║
║   • 支持已有数据磁盘安全模式                 ║
╚══════════════════════════════════════════════╝
EOF
    echo -e "${NC}"
    
    # 检查root权限
    check_root
    
    # 检查依赖工具
    print_info "检查系统工具..."
    local missing_tools=""
    
    if ! command -v sgdisk &> /dev/null; then
        missing_tools="gdisk"
    fi
    
    if [ -n "$missing_tools" ]; then
        print_warning "建议安装以下工具以获得更好性能："
        echo "  apt install $missing_tools -y"
        echo ""
        read -p "是否继续？ [Y/n]: " continue_anyway
        if [[ "$continue_anyway" == "n" ]] || [[ "$continue_anyway" == "N" ]]; then
            exit 0
        fi
    fi
    
    echo ""
    
    # 1. 检测磁盘
    detect_disks
    
    # 2. 选择磁盘
    select_disk
    
    # 3. 深度分析磁盘
    analyze_disk "$SELECTED_DISK"
    
    # 4. 安全确认
    safety_confirmation "$SELECTED_DISK"
    
    # 5. 卸载磁盘（如果已挂载）
    unmount_disk "$SELECTED_DISK"
    
    # 6. 清除旧分区表
    wipe_disk "$SELECTED_DISK"
    
    # 7. 创建新分区
    fast_partition "$SELECTED_DISK"
    if [ $? -ne 0 ]; then
        print_error "分区失败，退出"
        exit 1
    fi
    
    # 8. 选择格式化模式
    select_format_mode
    
    # 9. 选择文件系统
    select_filesystem
    
    # 10. 格式化
    format_disk "${SELECTED_DISK}1"
    if [ $? -ne 0 ]; then
        print_error "格式化失败，退出"
        exit 1
    fi
    
    # 11. 选择挂载点
    select_mount_point
    
    # 12. 挂载磁盘
    mount_disk_now "$FORMATTED_DEVICE" "$MOUNT_POINT"
    if [ $? -ne 0 ]; then
        print_error "挂载失败，退出"
        exit 1
    fi
    
    # 13. 配置自动挂载
    setup_auto_mount "$FORMATTED_DEVICE" "$MOUNT_POINT"
    
    # 14. 显示结果
    show_final_result
}

# 执行主函数
main
