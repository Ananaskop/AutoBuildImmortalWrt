#!/bin/sh
# 99-custom.sh 是 ImmortalWRT 固件首次启动时运行的脚本，位于 /etc/uci-defaults/99-custom.sh

# 日志文件用于调试
LOGFILE="/tmp/uci-defaults-log.txt"
echo "Starting 99-custom.sh at $(date)" >> $LOGFILE

# 设置默认防火墙规则，方便虚拟机首次访问 WebUI
uci set firewall.@zone[1].input='ACCEPT'

# 设置主机名映射，解决安卓原生 TV 无法联网的问题
uci add dhcp domain
uci set "dhcp.@domain[-1].name=time.android.com"
uci set "dhcp.@domain[-1].ip=203.107.6.88"

# 检查 PPPoE 配置文件是否存在，该文件由 build.sh 动态生成
SETTINGS_FILE="/etc/config/pppoe-settings"
if [ ! -f "$SETTINGS_FILE" ]; then
    echo "PPPoE settings file not found. Skipping." >> $LOGFILE
else
   . "$SETTINGS_FILE"
fi

# 检查是否已存在网络配置文件，若存在则跳过网络配置
NETWORK_FILE="/etc/config/network"
if [ -f "$NETWORK_FILE" ]; then
    echo "Network configuration file exists. Skipping network configuration." >> $LOGFILE
else
    # 计算网卡数量
    count=0
    ifnames=""
    for iface in /sys/class/net/*; do
      iface_name=$(basename "$iface")
      # 仅统计物理网卡（排除回环设备和无线设备）
      if [ -e "$iface/device" ] && echo "$iface_name" | grep -Eq '^eth|^en'; then
        count=$((count + 1))
        ifnames="$ifnames $iface_name"
      fi
    done
    # 删除多余空格
    ifnames=$(echo "$ifnames" | awk '{$1=$1};1')

    if [ "$count" -eq 1 ]; then
       # 单网口设备，使用 DHCP 获取 IP
       uci set network.lan.proto='dhcp'
    elif [ "$count" -gt 1 ]; then
       # 提取第一个接口作为 WAN
       wan_ifname=$(echo "$ifnames" | awk '{print $1}')
       # 剩余接口分配给 LAN
       lan_ifnames=$(echo "$ifnames" | cut -d ' ' -f2-)
       
       # 设置 WAN 口
       uci set network.wan=interface
       uci set network.wan.device="$wan_ifname"
       uci set network.wan.proto='dhcp'
       
       # 设置 WAN6 口绑定到 WAN
       uci set network.wan6=interface
       uci set network.wan6.device="$wan_ifname"
       
       # 更新 LAN 口的接口成员
       section=$(uci show network | awk -F '[.=]' '/\.\@?device\[\d+\]\.name=.br-lan.$/ {print $2; exit}')
       if [ -z "$section" ]; then
          echo "error：cannot find device 'br-lan'." >> $LOGFILE
       else
          # 删除原来的端口列表
          uci -q delete "network.$section.ports"
          for port in $lan_ifnames; do
             uci add_list "network.$section.ports"="$port"
          done
          echo "ports of device 'br-lan' are updated." >> $LOGFILE
       fi
       
       # LAN 口设置静态 IP
       uci set network.lan.proto='static'
       uci set network.lan.ipaddr='192.168.11.1'
       uci set network.lan.netmask='255.255.255.0'
       echo "set 192.168.11.1 at $(date)" >> $LOGFILE
       
       # 判断是否启用 PPPoE
       if [ "$enable_pppoe" = "yes" ]; then
          echo "PPPoE is enabled at $(date)" >> $LOGFILE
          uci set network.wan.proto='pppoe'
          uci set network.wan.username=$pppoe_account
          uci set network.wan.password=$pppoe_password
          uci set network.wan.peerdns='1'
          uci set network.wan.auto='1'
          uci set network.wan6.proto='none'
          echo "PPPoE configuration completed successfully." >> $LOGFILE
       else
          echo "PPPoE is not enabled. Skipping configuration." >> $LOGFILE
       fi
    fi
fi

# 允许所有网口访问网页终端
uci delete ttyd.@ttyd[0].interface

# 允许所有网口连接 SSH
uci set dropbear.@dropbear[0].Interface=''
uci commit

# 修改编译者信息
FILE_PATH="/etc/openwrt_release"
NEW_DESCRIPTION="Compiled by Ananaskop"
sed -i "s/DISTRIB_DESCRIPTION='[^']*'/DISTRIB_DESCRIPTION='$NEW_DESCRIPTION'/" "$FILE_PATH"

# 检查 /bin/bash 是否存在，防止未安装 bash 时出错
if [ -x "/bin/bash" ]; then
    echo "Start modifying root shell to bash..." >> $LOGFILE
    grep -qxF '/bin/bash' /etc/shells || echo "/bin/bash" >> /etc/shells
    sed -i 's|^root:[^:]*:[^:]*:[^:]*:[^:]*:[^:]*:.*$|root:x:0:0:root:/root:/bin/bash|' /etc/passwd
    [ -L /bin/sh ] && rm -f /bin/sh
    ln -sf /bin/bash /bin/sh
    echo "Current root shell: $(grep ^root /etc/passwd | cut -d: -f7)" >> $LOGFILE
    echo "sh link status: $(ls -l /bin/sh)" >> $LOGFILE
else
    echo "ERROR: /bin/bash not found! Check bash installation." >> $LOGFILE
fi

exit 0