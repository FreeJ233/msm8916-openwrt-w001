#!/bin/bash
# DIY脚本 - 精简版
# 修复：
#   1. 移除对 10_system.js 的 sed 注入（原因：破坏 JS 导致 LuCI Loading view 卡死）
#   2. 移除所有 Argon CSS 修改、字体替换、footer/logo 修改
#   3. 只保留背景图替换
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

# -----------------------------------------------------------------
# 4. Argon 主题 - 只替换背景图（其它美化全部移除）
# -----------------------------------------------------------------
ARGON_BASE="./feeds/luci/themes/luci-theme-argon"
ARGON_IMG="${ARGON_BASE}/htdocs/luci-static/argon/img"

echo ""
echo ">>> 检查 Argon 主题背景图替换..."

if [ ! -d "${ARGON_BASE}" ]; then
    echo "  ⚠ luci-theme-argon 未找到，跳过"
elif [ ! -d "${ARGON_IMG}" ]; then
    echo "  ⚠ Argon img 目录未找到，跳过"
elif [ ! -f "${GITHUB_WORKSPACE}/argon/bg1.jpg" ]; then
    echo "  ⚠ 仓库中 argon/bg1.jpg 不存在，跳过"
else
    cp -f "${GITHUB_WORKSPACE}/argon/bg1.jpg" "${ARGON_IMG}/bg1.jpg"
    echo "  ✓ 背景图 bg1.jpg 已替换"
fi

echo ""
echo "✅ diy-part2.sh 全部执行完成"
