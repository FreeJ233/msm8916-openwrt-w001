#!/bin/bash
# DIY脚本 - 精简版
# 修复：
#   1. 移除对 10_system.js 的 sed 注入（原因：破坏 JS 导致 LuCI Loading view 卡死）
#   2. 移除所有 Argon CSS 修改、字体替换、footer/logo 修改
#   3. 只保留背景图替换  → 已删除此功能
#   4. 加强默认中文写入方式

# -----------------------------------------------------------------
# 1. 修改默认IP地址
# -----------------------------------------------------------------
sed -i 's/192.168.1.1/192.168.2.1/g' package/base-files/files/bin/config_generate
echo "✅ 默认 IP 已改为 192.168.2.1"

# -----------------------------------------------------------------
# 2. 修改默认主题为 argon
# -----------------------------------------------------------------
sed -i 's/luci-theme-bootstrap/luci-theme-argon/g' \
    feeds/luci/collections/luci/Makefile 2>/dev/null || true
echo "✅ 默认主题已切换为 argon"

# -----------------------------------------------------------------
# 3. BBR + fq 配置（内核版本自适应）
#   6.6:  运行时会回退 cubic（上游 TCP_CONG_ADVANCED=n）
#   6.12/6.18: 可用
# -----------------------------------------------------------------
SYSCTL_FILE="package/base-files/files/etc/sysctl.conf"
mkdir -p package/base-files/files/etc

if [ -f "$SYSCTL_FILE" ]; then
    grep -q 'default_qdisc' "$SYSCTL_FILE" || \
        echo "net.core.default_qdisc=fq" >> "$SYSCTL_FILE"
    grep -q 'tcp_congestion_control' "$SYSCTL_FILE" || \
        echo "net.ipv4.tcp_congestion_control=bbr" >> "$SYSCTL_FILE"
else
    {
        echo "net.core.default_qdisc=fq"
        echo "net.ipv4.tcp_congestion_control=bbr"
    } >> "$SYSCTL_FILE"
fi
echo "✅ BBR + fq 已写入 sysctl.conf"

# =================================================================
# 4. 自定义包替换（helloworld + golang 1.23）
#    此部分必须在 feeds 更新并安装之后执行
# =================================================================
echo ""
echo ">>> 开始自定义包替换（helloworld + golang）..."

# 移除 feeds 中自带的 xray/v2ray/sing-box（与 helloworld 冲突）
rm -rf feeds/packages/net/{xray-core,v2ray-core,v2ray-geodata,sing-box}

# 克隆 helloworld 包（sbwml 维护版）到 package/ 目录
git clone https://github.com/sbwml/openwrt_helloworld package/helloworld

# 替换 golang 为 1.23.x 版本（sbwml 维护）
rm -rf feeds/packages/lang/golang
git clone https://github.com/sbwml/packages_lang_golang -b 23.x feeds/packages/lang/golang

echo "✅ 自定义包替换完成（helloworld + golang 1.23）"

# -----------------------------------------------------------------
echo ""
echo "✅ diy-part2.sh 全部执行完成"
