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

# 网络配置部分：使用标记文件判断是否已配置网络
NETWORK_CONFIG_MARKER="/etc/.network_configured"
if [ -f "$NETWORK_CONFIG_MARKER" ]; then
    echo "Network configuration already applied. Skipping network configuration." >> $LOGFILE
    exit 0  # 直接退出脚本，避免对 network 进行任何修改
else
    echo "No network configuration marker found. Proceeding with network configuration." >> $LOGFILE
fi

# 计算物理网卡数量和名称（排除回环和无线设备）
count=0
ifnames=""
for iface in /sys/class/net/*; do
  iface_name=$(basename "$iface")
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
   echo "Single interface detected. Setting LAN to DHCP." >> $LOGFILE
elif [ "$count" -gt 1 ]; then
   # 多网口设备配置：第一个接口作为 WAN，其他接口分配给 LAN
   wan_ifname=$(echo "$ifnames" | awk '{print $1}')
   lan_ifnames=$(echo "$ifnames" | cut -d ' ' -f2-)
   
   # 设置 WAN 口
   uci set network.wan=interface
   uci set network.wan.device="$wan_ifname"
   uci set network.wan.proto='dhcp'
   
   # 设置 WAN6 口绑定到 WAN
   uci set network.wan6=interface
   uci set network.wan6.device="$wan_ifname"
   
   # 更新 LAN 口的接口成员：查找 br-lan 对应的 section
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
   
   # LAN 口设置静态 IP
   uci set network.lan.proto='static'
   uci set network.lan.ipaddr='192.168.11.1'
   uci set network.lan.netmask='255.255.255.0'
   echo "Set LAN IP to 192.168.11.1 at $(date)" >> $LOGFILE
   
   # 判断是否启用 PPPoE
   if [ "$enable_pppoe" = "yes" ]; then
      echo "PPPoE is enabled at $(date)" >> $LOGFILE
      uci set network.wan.proto='pppoe'
      uci set network.wan.username="$pppoe_account"
      uci set network.wan.password="$pppoe_password"
      uci set network.wan.peerdns='1'
      uci set network.wan.auto='1'
      uci set network.wan6.proto='none'
      echo "PPPoE configuration completed." >> $LOGFILE
   else
      echo "PPPoE is not enabled. Skipping PPPoE configuration." >> $LOGFILE
   fi
fi

# 配置完成后，创建标记文件以防止后续覆盖
touch "$NETWORK_CONFIG_MARKER"
echo "Network configuration completed at $(date)." >> $LOGFILE

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
    echo "Modifying root shell to bash..." >> $LOGFILE
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