#!/bin/bash

#################################################################
# 脚本名称: change_timezone.sh
# 功能描述: 交互式永久修改系统时区
# 作者: Junye
# 版本: v1.0
# 使用方法: sudo bash change_timezone.sh
#################################################################

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# 检查是否以root权限运行
check_root() {
    if [[ $EUID -ne 0 ]]; then
        echo -e "${RED}错误: 此脚本需要root权限运行${NC}"
        echo "请使用: sudo $0"
        exit 1
    fi
}

# 显示当前时区信息
show_current_timezone() {
    echo -e "\n${BLUE}========================================${NC}"
    echo -e "${BLUE}     当前系统时区信息${NC}"
    echo -e "${BLUE}========================================${NC}"
    
    if command -v timedatectl &> /dev/null; then
        echo -e "${GREEN}当前时区配置:${NC}"
        timedatectl | grep "Time zone"
        echo -e "\n${GREEN}当前系统时间:${NC}"
        date
    else
        echo -e "${GREEN}当前时区:${NC} $(cat /etc/timezone 2>/dev/null || readlink /etc/localtime | sed 's|/usr/share/zoneinfo/||')"
        echo -e "${GREEN}当前系统时间:${NC} $(date)"
    fi
    echo -e "${BLUE}========================================${NC}\n"
}

# 列出常用时区
list_common_timezones() {
    echo -e "${YELLOW}常用时区列表:${NC}"
    echo "1)  Asia/Shanghai       (中国 - 上海，UTC+8)"
    echo "2)  Asia/Hong_Kong      (中国 - 香港，UTC+8)"
    echo "3)  Asia/Tokyo          (日本 - 东京，UTC+9)"
    echo "4)  Asia/Seoul          (韩国 - 首尔，UTC+9)"
    echo "5)  Asia/Singapore      (新加坡，UTC+8)"
    echo "6)  Asia/Dubai          (阿联酋 - 迪拜，UTC+4)"
    echo "7)  Europe/London       (英国 - 伦敦，UTC+0)"
    echo "8)  Europe/Paris        (法国 - 巴黎，UTC+1)"
    echo "9)  Europe/Moscow       (俄罗斯 - 莫斯科，UTC+3)"
    echo "10) America/New_York    (美国 - 纽约，UTC-5)"
    echo "11) America/Chicago     (美国 - 芝加哥，UTC-6)"
    echo "12) America/Los_Angeles (美国 - 洛杉矶，UTC-8)"
    echo "13) UTC                 (协调世界时)"
    echo "14) 查看所有可用时区"
    echo "15) 手动输入时区"
    echo "0)  退出"
}

# 显示所有可用时区
show_all_timezones() {
    echo -e "\n${GREEN}所有可用时区:${NC}"
    if command -v timedatectl &> /dev/null; then
        timedatectl list-timezones | more
    else
        find /usr/share/zoneinfo/ -type f | sed 's|/usr/share/zoneinfo/||' | grep -v "posix\|right" | sort | more
    fi
}

# 设置时区
set_timezone() {
    local timezone=$1
    
    # 验证时区是否存在
    if [ ! -f "/usr/share/zoneinfo/$timezone" ]; then
        echo -e "${RED}错误: 时区 '$timezone' 不存在${NC}"
        return 1
    fi
    
    echo -e "${YELLOW}正在设置时区为: $timezone${NC}"
    
    # 使用timedatectl（systemd系统）
    if command -v timedatectl &> /dev/null; then
        timedatectl set-timezone "$timezone"
        if [ $? -eq 0 ]; then
            echo -e "${GREEN}✓ 使用timedatectl设置时区成功${NC}"
        else
            echo -e "${RED}✗ 使用timedatectl设置失败${NC}"
            return 1
        fi
    else
        # 传统方法
        # 备份原有配置
        if [ -f /etc/localtime ]; then
            cp /etc/localtime /etc/localtime.backup.$(date +%Y%m%d_%H%M%S)
            echo -e "${GREEN}✓ 已备份原时区配置${NC}"
        fi
        
        # 创建新的符号链接
        ln -sf /usr/share/zoneinfo/$timezone /etc/localtime
        if [ $? -eq 0 ]; then
            echo -e "${GREEN}✓ 更新 /etc/localtime 成功${NC}"
        else
            echo -e "${RED}✗ 更新 /etc/localtime 失败${NC}"
            return 1
        fi
        
        # 更新/etc/timezone（Debian/Ubuntu）
        if [ -f /etc/timezone ]; then
            echo "$timezone" > /etc/timezone
            echo -e "${GREEN}✓ 更新 /etc/timezone 成功${NC}"
        fi
    fi
    
    # 同步硬件时钟
    echo -e "${YELLOW}正在同步硬件时钟...${NC}"
    if command -v hwclock &> /dev/null; then
        hwclock --systohc
        if [ $? -eq 0 ]; then
            echo -e "${GREEN}✓ 硬件时钟同步成功${NC}"
        else
            echo -e "${YELLOW}⚠ 硬件时钟同步失败（可能需要检查）${NC}"
        fi
    fi
    
    return 0
}

# 验证时区设置
verify_timezone() {
    echo -e "\n${BLUE}========================================${NC}"
    echo -e "${BLUE}     验证新的时区设置${NC}"
    echo -e "${BLUE}========================================${NC}"
    
    if command -v timedatectl &> /dev/null; then
        timedatectl status
    else
        echo -e "${GREEN}当前时区:${NC} $(cat /etc/timezone 2>/dev/null || readlink /etc/localtime | sed 's|/usr/share/zoneinfo/||')"
        echo -e "${GREEN}当前时间:${NC} $(date)"
        echo -e "${GREEN}硬件时钟:${NC} $(hwclock --show 2>/dev/null || echo '无法读取')"
    fi
    echo -e "${BLUE}========================================${NC}\n"
}

# 主菜单循环
main_menu() {
    while true; do
        show_current_timezone
        list_common_timezones
        
        echo -e -n "\n${GREEN}请选择操作 [0-15]: ${NC}"
        read -r choice
        
        case $choice in
            1) selected_timezone="Asia/Shanghai" ;;
            2) selected_timezone="Asia/Hong_Kong" ;;
            3) selected_timezone="Asia/Tokyo" ;;
            4) selected_timezone="Asia/Seoul" ;;
            5) selected_timezone="Asia/Singapore" ;;
            6) selected_timezone="Asia/Dubai" ;;
            7) selected_timezone="Europe/London" ;;
            8) selected_timezone="Europe/Paris" ;;
            9) selected_timezone="Europe/Moscow" ;;
            10) selected_timezone="America/New_York" ;;
            11) selected_timezone="America/Chicago" ;;
            12) selected_timezone="America/Los_Angeles" ;;
            13) selected_timezone="UTC" ;;
            14)
                show_all_timezones
                continue
                ;;
            15)
                echo -e -n "${GREEN}请输入时区 (例如: Asia/Shanghai): ${NC}"
                read -r selected_timezone
                if [ -z "$selected_timezone" ]; then
                    echo -e "${RED}时区不能为空${NC}"
                    continue
                fi
                ;;
            0)
                echo -e "${GREEN}退出脚本${NC}"
                exit 0
                ;;
            *)
                echo -e "${RED}无效的选择，请重新输入${NC}"
                sleep 2
                continue
                ;;
        esac
        
        # 确认操作
        echo -e "\n${YELLOW}您选择的时区是: $selected_timezone${NC}"
        echo -e -n "${YELLOW}确认要修改吗? (y/n): ${NC}"
        read -r confirm
        
        if [[ $confirm =~ ^[Yy]$ ]]; then
            if set_timezone "$selected_timezone"; then
                verify_timezone
                echo -e "${GREEN}✓ 时区修改成功！${NC}"
                
                echo -e -n "\n${YELLOW}是否继续修改其他设置? (y/n): ${NC}"
                read -r continue_choice
                if [[ ! $continue_choice =~ ^[Yy]$ ]]; then
                    exit 0
                fi
            else
                echo -e "${RED}✗ 时区修改失败，请检查错误信息${NC}"
                sleep 3
            fi
        else
            echo -e "${YELLOW}取消操作${NC}"
            sleep 2
        fi
    done
}

# 主程序入口
main() {
    clear
    echo -e "${BLUE}"
    echo "╔════════════════════════════════════════╗"
    echo "║   系统时区永久修改脚本 v1.0          ║"
    echo "║   支持主流Linux发行版                ║"
    echo "╚════════════════════════════════════════╝"
    echo -e "${NC}"
    
    check_root
    main_menu
}

# 运行主程序
main
