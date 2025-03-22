#!/bin/sh
# 99-custom.sh 是 ImmortalWRT 固件首次启动时运行的脚本，位于 /etc/uci-defaults/99-custom.sh

LOGFILE="/tmp/uci-defaults-log.txt"
echo "Starting 99-custom.sh at $(date)" >> $LOGFILE

# 网络配置部分
NETWORK_CONFIG_MARKER="/opt/.network_configured"

if [ -f "$NETWORK_CONFIG_MARKER" ]; then
    echo "Network configuration already applied. Skipping network configuration." >> $LOGFILE
else
    echo "No network configuration marker found. Proceeding with network configuration." >> $LOGFILE

    # 计算物理网卡数量（排除回环和无线设备）
    count=0
    ifnames=""
    for iface in /sys/class/net/*; do
        iface_name=$(basename "$iface")
        if [ -e "$iface/device" ] && echo "$iface_name" | grep -Eq '^eth|^en'; then
            count=$((count + 1))
            ifnames="$ifnames $iface_name"
        fi
    done
    ifnames=$(echo "$ifnames" | awk '{$1=$1};1')  # 清除多余空格

    if [ "$count" -eq 1 ]; then
        # 单网口设备，首次安装时使用 DHCP
        uci set network.lan.proto='dhcp'
        echo "Single interface detected. Setting LAN to DHCP." >> $LOGFILE
    elif [ "$count" -gt 1 ]; then
        # 多网口设备：第一个接口作为 WAN，其余接口为 LAN
        wan_ifname=$(echo "$ifnames" | awk '{print $1}')
        lan_ifnames=$(echo "$ifnames" | cut -d ' ' -f2-)

        # 配置 WAN
        uci set network.wan=interface
        uci set network.wan.device="$wan_ifname"
        uci set network.wan.proto='dhcp'

        # 配置 WAN6（IPv6）
        uci set network.wan6=interface
        uci set network.wan6.device="$wan_ifname"

        # 更新 LAN（br-lan 设备）
        brlan_section=$(uci show network | grep -E "network\..*\.device='br-lan'" | cut -d'.' -f2 | head -n1)
        if [ -z "$brlan_section" ]; then
            echo "Error: cannot find device 'br-lan'." >> $LOGFILE
        else
            uci -q delete "network.$brlan_section.ports"
            for port in $lan_ifnames; do
                uci add_list "network.$brlan_section.ports"="$port"
            done
            echo "Ports of device 'br-lan' updated: $lan_ifnames" >> $LOGFILE
        fi

        # 设置 LAN 静态 IP
        uci set network.lan.proto='static'
        uci set network.lan.ipaddr='192.168.11.1'
        uci set network.lan.netmask='255.255.255.0'
        echo "Set LAN IP to 192.168.11.1" >> $LOGFILE
    fi

    # 处理 PPPoE 配置
    SETTINGS_FILE="/etc/config/pppoe-settings"
    if [ -f "$SETTINGS_FILE" ]; then
        . "$SETTINGS_FILE"  # 加载 PPPoE 账号配置
        if [ "$enable_pppoe" = "yes" ]; then
            uci set network.wan.proto='pppoe'
            uci set network.wan.username="$pppoe_account"
            uci set network.wan.password="$pppoe_password"
            uci set network.wan.peerdns='1'
            uci set network.wan.auto='1'
            uci set network.wan6.proto='none'
            echo "PPPoE configuration applied." >> $LOGFILE
        else
            echo "PPPoE not enabled. Skipping." >> $LOGFILE
        fi
    else
        echo "PPPoE settings file not found. Skipping PPPoE configuration." >> $LOGFILE
    fi

    # 标记网络已配置，避免升级时重复执行
    touch "$NETWORK_CONFIG_MARKER"
    echo "Network configuration completed." >> $LOGFILE
fi

# 允许所有网口访问 Web 终端 (ttyd)
uci delete ttyd.@ttyd[0].interface

# 允许所有网口连接 SSH
uci set dropbear.@dropbear[0].Interface=''
uci commit

# 修改编译者信息
FILE_PATH="/etc/openwrt_release"
NEW_DESCRIPTION="Compiled by Ananaskop"
sed -i "s/DISTRIB_DESCRIPTION='[^']*'/DISTRIB_DESCRIPTION='$NEW_DESCRIPTION'/" "$FILE_PATH"

chsh -s /usr/bin/zsh

# 增加zsh历史记录配置
configure_zsh() {
    ZSHRC_FILE="/root/.zshrc"
    ZSH_HISTORY_FILE="/root/.zsh_history"
    if [ ! -f "$ZSHRC_FILE" ]; then
        echo "Creating $ZSHRC_FILE..." >> $LOGFILE
        # <修改> 删除 PROMPT 和颜色配置
        cat << EOF > "$ZSHRC_FILE"
# 启用历史记录
HISTFILE=~/.zsh_history
HISTSIZE=1000
SAVEHIST=1000
setopt appendhistory

# 启用 Git 信息提示
autoload -Uz vcs_info
precmd_vcs_info() { vcs_info }
precmd_functions+=( precmd_vcs_info )
setopt prompt_subst
zstyle ':vcs_info:git:*' formats ' (%b)'

# 定义 PROMPT
PROMPT='%F{green}➜%f %F{blue}%1~%f%F{red}${vcs_info_msg_0_}%f %# '

# 增加banner显示
if [[ -t 1 ]]; then
  echo "Welcome to Zsh! $(date '+%Y-%m-%d %H:%M:%S')"
fi

EOF
        chmod 600 "$ZSHRC_FILE"
        echo "ZSH configuration applied." >> $LOGFILE
    fi
    # 确保历史文件存在
    if [ ! -f "$ZSH_HISTORY_FILE" ]; then
        touch "$ZSH_HISTORY_FILE"
        chmod 600 "$ZSH_HISTORY_FILE"
        echo "Created $ZSH_HISTORY_FILE." >> $LOGFILE
    fi
}
configure_zsh

exit 0
