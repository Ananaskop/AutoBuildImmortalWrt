#!/bin/bash
# Log file for debugging
LOGFILE="/tmp/uci-defaults-log.txt"
{
echo "Starting 99-custom.sh at $(date)"
echo "编译固件大小为: $PROFILE MB"
echo "Include Docker: $INCLUDE_DOCKER"

# 修复步骤1：修正feed声明格式
echo "src-git nikki https://github.com/nikkinikki-org/OpenWrt-nikki.git main" >> "feeds.conf.default"

# 修复步骤2：预创建目录结构
mkdir -p ./package/feeds
rm -rf ./feeds/nikki* ./package/feeds/nikki

# 分步更新feed
echo "Step 1: 更新核心feed"
./scripts/feeds update -a >> $LOGFILE 2>&1

echo "Step 2: 安装基础包"
./scripts/feeds install -a -p nikki >> $LOGFILE 2>&1

# 修复步骤3：添加缺失的依赖feed
echo "src-git packages https://git.openwrt.org/feed/packages.git" >> feeds.conf.default
./scripts/feeds update packages >> $LOGFILE 2>&1
./scripts/feeds install \
    golang \
    libc \
    ca-bundle \
    curl \
    yq \
    firewall4 \
    ip-full \
    kmod-inet-diag \
    kmod-nft-socket \
    kmod-nft-tproxy \
    kmod-tun >> $LOGFILE 2>&1

echo "Create pppoe-settings"
mkdir -p  /home/build/immortalwrt/files/etc/config

cat << EOF > /home/build/immortalwrt/files/etc/config/pppoe-settings
enable_pppoe=${ENABLE_PPPOE}
pppoe_account=${PPPOE_ACCOUNT}
pppoe_password=${PPPOE_PASSWORD}
EOF

echo "cat pppoe-settings"
cat /home/build/immortalwrt/files/etc/config/pppoe-settings

# 定义所需安装的包列表
PACKAGES=""
PACKAGES="$PACKAGES curl"
PACKAGES="$PACKAGES luci-i18n-diskman-zh-cn"
PACKAGES="$PACKAGES luci-i18n-firewall-zh-cn"
PACKAGES="$PACKAGES luci-app-argon-config"
PACKAGES="$PACKAGES luci-i18n-argon-config-zh-cn"
PACKAGES="$PACKAGES luci-i18n-ttyd-zh-cn"
PACKAGES="$PACKAGES luci-app-openclash"
PACKAGES="$PACKAGES openssh-sftp-server"
PACKAGES="$PACKAGES snmpd"
PACKAGES="$PACKAGES socat"
PACKAGES="$PACKAGES luci-i18n-package-manager-zh-cn"
PACKAGES="$PACKAGES luci-compat"
PACKAGES="$PACKAGES openssl-util"
PACKAGES="$PACKAGES luci-mod-rpc"
PACKAGES="$PACKAGES luci-lib-ipkg"
PACKAGES="$PACKAGES luci-i18n-ddns-zh-cn"
PACKAGES="$PACKAGES ddns-scripts_aliyun"
PACKAGES="$PACKAGES ddns-scripts-cloudflare"
PACKAGES="$PACKAGES nginx-ssl-util"
PACKAGES="$PACKAGES nginx-full"
PACKAGES="$PACKAGES shadow-chsh"
PACKAGES="$PACKAGES luci-i18n-wechatpush-zh-cn"

# 修复步骤4：验证包名有效性
NIKKI_PACKAGES="luci-app-nikki nikki"
PACKAGES="$PACKAGES $NIKKI_PACKAGES"

# 必备组件
PACKAGES="$PACKAGES fdisk"
PACKAGES="$PACKAGES script-utils"
PACKAGES="$PACKAGES luci-i18n-samba4-zh-cn"

# Docker插件
if [ "$INCLUDE_DOCKER" = "yes" ]; then
    PACKAGES="$PACKAGES luci-i18n-dockerman-zh-cn"
    echo "Adding package: luci-i18n-dockerman-zh-cn"
fi

# 构建镜像
echo "$(date '+%Y-%m-%d %H:%M:%S') - 编译包列表:"
echo "$PACKAGES"

# 修复步骤5：增加编译线程控制
make image PROFILE="generic" \
    PACKAGES="$PACKAGES" \
    FILES="/home/build/immortalwrt/files" \
    ROOTFS_PARTSIZE=$PROFILE \
    -j$(nproc) V=s

if [ $? -ne 0 ]; then
    echo "$(date '+%Y-%m-%d %H:%M:%S') - 编译失败! 错误日志："
    tail -n 50 $LOGFILE
    exit 1
fi

echo "$(date '+%Y-%m-%d %H:%M:%S') - 编译成功"
} >> $LOGFILE 2>&1
