#!/bin/bash

# 磁盘自动挂载脚本
# 作者: Junye
# 功能: 交互式检测、格式化、挂载磁盘

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

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

# 显示分隔线
print_separator() {
    echo -e "${BLUE}========================================${NC}"
}

# 检测系统中的磁盘
detect_disks() {
    print_separator
    print_info "正在检测系统磁盘..."
    print_separator
    
    # 获取所有块设备
    mapfile -t DISKS < <(lsblk -nd -o NAME,SIZE,TYPE | grep disk | awk '{print "/dev/"$1}')
    
    if [ ${#DISKS[@]} -eq 0 ]; then
        print_error "未检测到任何磁盘！"
        exit 1
    fi
    
    echo ""
    echo "检测到以下磁盘："
    echo ""
    printf "%-6s %-15s %-10s %-15s %-20s\n" "序号" "设备名" "大小" "类型" "挂载状态"
    echo "----------------------------------------------------------------"
    
    local index=1
    declare -g -A DISK_INFO
    
    for disk in "${DISKS[@]}"; do
        local size=$(lsblk -nd -o SIZE "$disk" 2>/dev/null)
        local model=$(lsblk -nd -o MODEL "$disk" 2>/dev/null | xargs)
        local mounted=$(lsblk -n -o MOUNTPOINT "$disk" 2>/dev/null | grep -v "^$" | head -1)
        
        if [ -z "$mounted" ]; then
            mounted="未挂载"
        fi
        
        printf "%-6s %-15s %-10s %-15s %-20s\n" "[$index]" "$disk" "$size" "$model" "$mounted"
        DISK_INFO[$index]="$disk"
        ((index++))
    done
    
    echo ""
}

# 检查磁盘是否已挂载
check_mounted() {
    local disk=$1
    if mount | grep -q "^${disk}"; then
        return 0
    else
        return 1
    fi
}

# 检查磁盘是否有文件系统
check_filesystem() {
    local disk=$1
    local fs_type=$(blkid -o value -s TYPE "${disk}" 2>/dev/null)
    
    if [ -n "$fs_type" ]; then
        echo "$fs_type"
        return 0
    else
        return 1
    fi
}

# 选择磁盘
select_disk() {
    local disk_count=${#DISK_INFO[@]}
    
    while true; do
        read -p "请选择要操作的磁盘序号 [1-$disk_count] (输入 q 退出): " choice
        
        if [[ "$choice" == "q" || "$choice" == "Q" ]]; then
            print_info "用户取消操作"
            exit 0
        fi
        
        if [[ "$choice" =~ ^[0-9]+$ ]] && [ "$choice" -ge 1 ] && [ "$choice" -le "$disk_count" ]; then
            SELECTED_DISK=${DISK_INFO[$choice]}
            print_success "已选择磁盘: $SELECTED_DISK"
            return 0
        else
            print_error "无效的选择，请重新输入！"
        fi
    done
}

# 检查磁盘状态
check_disk_status() {
    local disk=$1
    print_separator
    print_info "正在检查磁盘 $disk 的状态..."
    print_separator
    
    # 检查是否已挂载
    if check_mounted "$disk"; then
        print_warning "磁盘 $disk 或其分区已被挂载！"
        mount | grep "^${disk}"
        echo ""
        read -p "是否要继续操作此磁盘？这可能导致数据丢失！(yes/no): " confirm
        if [[ "$confirm" != "yes" ]]; then
            print_info "操作已取消"
            exit 0
        fi
    else
        print_success "磁盘未挂载，可以安全操作"
    fi
    
    # 检查分区
    local partitions=$(lsblk -ln -o NAME "$disk" | tail -n +2)
    if [ -n "$partitions" ]; then
        print_info "检测到以下分区："
        lsblk "$disk"
        echo ""
    else
        print_info "磁盘没有分区"
    fi
    
    # 检查文件系统
    if fs_type=$(check_filesystem "${disk}"); then
        print_info "磁盘文件系统: $fs_type"
        NEED_FORMAT=false
    else
        # 检查第一个分区
        local first_partition="${disk}1"
        if [ -b "$first_partition" ]; then
            if fs_type=$(check_filesystem "${first_partition}"); then
                print_info "分区 ${first_partition} 文件系统: $fs_type"
                NEED_FORMAT=false
            else
                print_warning "磁盘未格式化"
                NEED_FORMAT=true
            fi
        else
            print_warning "磁盘未分区且未格式化"
            NEED_FORMAT=true
        fi
    fi
    
    echo ""
}

# 创建分区
create_partition() {
    local disk=$1
    print_separator
    print_info "开始为磁盘 $disk 创建分区..."
    print_separator
    
    # 检查是否已有分区
    if [ -b "${disk}1" ]; then
        print_warning "检测到已存在分区，将跳过分区创建步骤"
        return 0
    fi
    
    print_info "使用 GPT 分区表创建分区..."
    
    # 使用 parted 创建分区
    parted -s "$disk" mklabel gpt
    if [ $? -ne 0 ]; then
        print_error "创建分区表失败！"
        return 1
    fi
    
    parted -s "$disk" mkpart primary ext4 0% 100%
    if [ $? -ne 0 ]; then
        print_error "创建分区失败！"
        return 1
    fi
    
    # 等待系统识别分区
    sleep 2
    partprobe "$disk"
    sleep 1
    
    print_success "分区创建完成: ${disk}1"
    return 0
}

# 格式化磁盘
format_disk() {
    local disk=$1
    
    print_separator
    print_info "选择文件系统类型："
    print_separator
    echo "1) ext4    - Linux默认，推荐"
    echo "2) xfs     - 高性能，适合大文件"
    echo "3) ext3    - 传统Linux文件系统"
    echo ""
    
    while true; do
        read -p "请选择文件系统 [1-3, 默认1]: " fs_choice
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
                print_error "无效的选择，请重新输入！"
                ;;
        esac
    done
    
    # 确定要格式化的设备
    if [ -b "${disk}1" ]; then
        local format_device="${disk}1"
    else
        local format_device="$disk"
    fi
    
    print_warning "即将格式化 $format_device 为 $FS_TYPE 文件系统"
    print_warning "此操作将清除磁盘上的所有数据！"
    echo ""
    read -p "确认格式化？请输入 'YES' 继续: " confirm
    
    if [[ "$confirm" != "YES" ]]; then
        print_info "操作已取消"
        exit 0
    fi
    
    print_info "正在格式化 $format_device 为 $FS_TYPE..."
    
    case $FS_TYPE in
        ext4)
            mkfs.ext4 -F "$format_device"
            ;;
        xfs)
            mkfs.xfs -f "$format_device"
            ;;
        ext3)
            mkfs.ext3 -F "$format_device"
            ;;
    esac
    
    if [ $? -eq 0 ]; then
        print_success "格式化完成！"
        FORMATTED_DEVICE="$format_device"
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
    echo "1) /mnt/data"
    echo "2) /data"
    echo "3) /home/data"
    echo "4) 自定义路径"
    echo ""
    
    while true; do
        read -p "请选择挂载点 [1-4]: " mount_choice
        
        case $mount_choice in
            1)
                MOUNT_POINT="/mnt/data"
                break
                ;;
            2)
                MOUNT_POINT="/data"
                break
                ;;
            3)
                MOUNT_POINT="/home/data"
                break
                ;;
            4)
                read -p "请输入自定义挂载路径 (如 /opt/storage): " custom_path
                if [[ "$custom_path" =~ ^/[a-zA-Z0-9/_-]+$ ]]; then
                    MOUNT_POINT="$custom_path"
                    break
                else
                    print_error "无效的路径格式！"
                fi
                ;;
            *)
                print_error "无效的选择，请重新输入！"
                ;;
        esac
    done
    
    print_success "挂载点设置为: $MOUNT_POINT"
}

# 挂载磁盘
mount_disk() {
    local device=$1
    local mount_point=$2
    
    print_separator
    print_info "开始挂载操作..."
    print_separator
    
    # 创建挂载点目录
    if [ ! -d "$mount_point" ]; then
        print_info "创建挂载点目录: $mount_point"
        mkdir -p "$mount_point"
        if [ $? -ne 0 ]; then
            print_error "创建挂载点目录失败！"
            return 1
        fi
    else
        print_info "挂载点目录已存在: $mount_point"
    fi
    
    # 挂载设备
    print_info "挂载 $device 到 $mount_point..."
    mount "$device" "$mount_point"
    
    if [ $? -eq 0 ]; then
        print_success "挂载成功！"
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
    
    read -p "是否设置开机自动挂载？(y/n): " auto_mount
    
    if [[ "$auto_mount" != "y" && "$auto_mount" != "Y" ]]; then
        print_info "跳过自动挂载配置"
        return 0
    fi
    
    # 获取UUID
    local uuid=$(blkid -s UUID -o value "$device")
    
    if [ -z "$uuid" ]; then
        print_error "无法获取设备UUID！"
        return 1
    fi
    
    print_info "设备UUID: $uuid"
    
    # 检查fstab中是否已存在该UUID
    if grep -q "$uuid" /etc/fstab; then
        print_warning "该设备已在 /etc/fstab 中配置"
        read -p "是否覆盖现有配置？(y/n): " overwrite
        if [[ "$overwrite" == "y" || "$overwrite" == "Y" ]]; then
            # 备份fstab
            cp /etc/fstab /etc/fstab.backup.$(date +%Y%m%d%H%M%S)
            print_info "已备份 /etc/fstab"
            
            # 删除旧条目
            sed -i "/$uuid/d" /etc/fstab
        else
            return 0
        fi
    fi
    
    # 添加到fstab
    local fstab_entry="UUID=$uuid  $mount_point  $FS_TYPE  defaults  0  2"
    echo "$fstab_entry" >> /etc/fstab
    
    print_success "已添加自动挂载配置到 /etc/fstab"
    print_info "配置内容: $fstab_entry"
    
    # 测试fstab配置
    print_info "测试 fstab 配置..."
    mount -a
    
    if [ $? -eq 0 ]; then
        print_success "fstab 配置测试通过！"
        return 0
    else
        print_error "fstab 配置测试失败！"
        print_warning "已回滚配置"
        sed -i "/$uuid/d" /etc/fstab
        return 1
    fi
}

# 显示磁盘使用情况
show_disk_usage() {
    print_separator
    print_info "当前系统磁盘使用情况"
    print_separator
    echo ""
    df -h
    echo ""
    print_separator
    print_info "详细分区信息"
    print_separator
    echo ""
    lsblk -f
    echo ""
}

# 主函数
main() {
    clear
    echo -e "${GREEN}"
    cat << "EOF"
╔═══════════════════════════════════════════╗
║   Linux 磁盘自动挂载工具 v1.0            ║
║   Disk Auto-Mount Script                  ║
╚═══════════════════════════════════════════╝
EOF
    echo -e "${NC}"
    
    # 检查root权限
    check_root
    
    # 检测磁盘
    detect_disks
    
    # 选择磁盘
    select_disk
    
    # 检查磁盘状态
    check_disk_status "$SELECTED_DISK"
    
    # 如果需要格式化
    if [ "$NEED_FORMAT" = true ]; then
        # 创建分区
        create_partition "$SELECTED_DISK"
        if [ $? -ne 0 ]; then
            print_error "分区创建失败，脚本退出"
            exit 1
        fi
        
        # 格式化磁盘
        format_disk "$SELECTED_DISK"
        if [ $? -ne 0 ]; then
            print_error "格式化失败，脚本退出"
            exit 1
        fi
    else
        # 使用现有文件系统
        if [ -b "${SELECTED_DISK}1" ]; then
            FORMATTED_DEVICE="${SELECTED_DISK}1"
        else
            FORMATTED_DEVICE="$SELECTED_DISK"
        fi
        print_info "使用现有设备: $FORMATTED_DEVICE"
    fi
    
    # 选择挂载点
    select_mount_point
    
    # 挂载磁盘
    mount_disk "$FORMATTED_DEVICE" "$MOUNT_POINT"
    if [ $? -ne 0 ]; then
        print_error "挂载失败，脚本退出"
        exit 1
    fi
    
    # 配置自动挂载
    setup_auto_mount "$FORMATTED_DEVICE" "$MOUNT_POINT"
    
    # 显示最终结果
    show_disk_usage
    
    print_separator
    print_success "所有操作完成！"
    print_separator
    print_info "挂载设备: $FORMATTED_DEVICE"
    print_info "挂载点: $MOUNT_POINT"
    print_info "文件系统: ${FS_TYPE:-$(blkid -o value -s TYPE $FORMATTED_DEVICE)}"
    print_separator
}

# 执行主函数
main
