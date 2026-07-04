#!/bin/bash
# DIY脚本
# https://github.com/P3TERX/Actions-OpenWrt
# 文件名: diy-part2.sh
# 功能说明: OpenWrt DIY脚本第2部分（更新feeds之后）
# 版权: (c) 2019-2024 P3TERX <https://p3terx.com>
# 基于 MIT 开源协议，详见 /LICENSE

# 修改默认IP地址
sed -i 's/192.168.1.1/192.168.2.1/g' package/base-files/files/bin/config_generate

# -----------------------------------------------------------------
# 1. 修改默认主题为 argon
# -----------------------------------------------------------------
sed -i 's/luci-theme-bootstrap/luci-theme-argon/g' \
    feeds/luci/collections/luci/Makefile 2>/dev/null || true
echo "✅ 默认主题已切换为 argon"

# -----------------------------------------------------------------
# 2. 添加编译日期标识到 LuCI 状态页
# ✅ 修复: 原 sed 正则在部分上下文中会造成括号不匹配
# 改用追加方式，安全注入版本标识字符串，不依赖原有括号结构
# -----------------------------------------------------------------
BUILD_DATE=$(date +"%Y.%m.%d")
STATUS_JS=$(find ./feeds/luci/modules/luci-mod-status/ -type f -name "10_system.js" 2>/dev/null | head -1)
if [ -n "$STATUS_JS" ]; then
    # 幂等写入：避免多次执行重复注入
    if ! grep -q "UFI001C-${BUILD_DATE}" "$STATUS_JS"; then
        sed -i "s/\(luciversion\s*||\s*''\)/\1 + ' \/ UFI001C-${BUILD_DATE}'/g" "$STATUS_JS"
        echo "✅ 编译日期标识已注入: UFI001C-${BUILD_DATE}"
    else
        echo "✅ 编译日期标识已存在，跳过注入"
    fi
else
    echo "⚠️ 10_system.js 未找到，跳过日期标识注入"
fi

# -----------------------------------------------------------------
# ✅ 修复: 第3节 TurboAcc 已移除
# 原因: TurboAcc 安装由 Workflow 中用户选择 luci-app-turboacc 时触发
# 此处无条件执行会与 Workflow 的额外包步骤重复，造成冲突
# 如需 TurboAcc，请在触发编译时的"额外包"输入框中填写 luci-app-turboacc
# -----------------------------------------------------------------

# -----------------------------------------------------------------
# 4. BBR 配置（内核版本自适应）
# ✅ 对照上游：
#   6.6:  TCP_CONG_ADVANCED=n → BBR 不可用，写入 sysctl 但运行时会回退 cubic
#   6.12: TCP_CONG_BBR=m      → BBR 可用，kmod-tcp-bbr 加载后生效
#   6.18: TCP_CONG_BBR=m      → BBR 可用，kmod-tcp-bbr 加载后生效
# -----------------------------------------------------------------
SYSCTL_FILE="package/base-files/files/etc/sysctl.conf"
mkdir -p package/base-files/files/etc

# fq 队列调度器三个版本均支持，无条件写入
if [ -f "$SYSCTL_FILE" ]; then
    grep -q 'default_qdisc' "$SYSCTL_FILE" || \
        echo "net.core.default_qdisc=fq" >> "$SYSCTL_FILE"
    grep -q 'tcp_congestion_control' "$SYSCTL_FILE" || \
        echo "net.ipv4.tcp_congestion_control=bbr" >> "$SYSCTL_FILE"
    echo "✅ BBR + fq 已写入已有 sysctl.conf"
else
    {
        echo "net.core.default_qdisc=fq"
        echo "net.ipv4.tcp_congestion_control=bbr"
    } >> "$SYSCTL_FILE"
    echo "✅ sysctl.conf 已创建并写入 fq + BBR 配置"
fi
echo "ℹ️ 注意：Linux 6.6 内核 TCP_CONG_ADVANCED=n，BBR sysctl 在 6.6 上运行时会回退到 cubic"

# -----------------------------------------------------------------
# 5. Argon 主题美化
# -----------------------------------------------------------------
ARGON_BASE="./feeds/luci/themes/luci-theme-argon"
ARGON_CSS="${ARGON_BASE}/htdocs/luci-static/argon/css/cascade.css"
ARGON_FONTS="${ARGON_BASE}/htdocs/luci-static/argon/fonts"
ARGON_IMG="${ARGON_BASE}/htdocs/luci-static/argon/img"

echo ""
echo ">>> 检查 Argon 主题..."

if [ ! -d "${ARGON_BASE}" ]; then
    echo "  ⚠ luci-theme-argon 未找到，跳过"
    echo "    预期路径：$(pwd)/${ARGON_BASE}"
else
    echo "  ✓ Argon 主题目录已找到：$(pwd)/${ARGON_BASE}"

    # 5.1 背景图 & 字体（来自仓库 argon/ 目录）
    if [ -d "${GITHUB_WORKSPACE}/argon" ]; then
        echo ">>> 复制自定义资源..."
        [ -f "${GITHUB_WORKSPACE}/argon/bg1.jpg" ] && \
        [ -d "${ARGON_IMG}" ] && {
            cp -f "${GITHUB_WORKSPACE}/argon/bg1.jpg" "${ARGON_IMG}/bg1.jpg"
            echo "  ✓ 背景图已替换"
        }
        [ -d "${GITHUB_WORKSPACE}/argon/fonts" ] && \
        [ -d "${ARGON_FONTS}" ] && {
            rm -f "${ARGON_FONTS}/TypoGraphica"*
            cp -f "${GITHUB_WORKSPACE}/argon/fonts/"* "${ARGON_FONTS}/"
            echo "  ✓ 字体已替换"
        }
    else
        echo "  - 仓库中无 argon/ 自定义资源目录，跳过"
    fi

    # 5.2 CSS 修改
    if [ ! -f "${ARGON_CSS}" ]; then
        echo "  ⚠ cascade.css 未找到，跳过 CSS 修改"
    else
        echo ">>> 修改 Argon CSS..."

        # shine 动画关键帧（幂等写入）
        if ! grep -q "@keyframes shine" "${ARGON_CSS}"; then
            sed -i '/@keyframes anim-fade-in/i\
@keyframes shine {\
  0% { background-position: -200% center; }\
  100% { background-position: 200% center; }\
}\
' "${ARGON_CSS}"
            echo "  ✓ shine 关键帧已注入"
        fi

        # 侧边栏 Brand 渐变
        sed -i '/\.main-left \.sidenav-header \.brand {/,/}/c\
.main-left .sidenav-header .brand {\
  display: block; margin: 0; font-size: 1.8rem;\
  font-family: "TypoGraphica"; text-decoration: none;\
  text-align: center; cursor: default;\
  background: linear-gradient(120deg,#00fff7,#007cf0,#ff4ecd,#00fff7);\
  background-size: 300% 300%; -webkit-background-clip: text;\
  -webkit-text-fill-color: transparent;\
  animation: shine 5s linear infinite;\
}' "${ARGON_CSS}"
        echo "  ✓ 侧边栏 Brand 渐变已注入"

        # Brand margin 居中
        sed -i '/\.brand {/,/}/ s/margin: 50px auto 100px 50px;/margin: 50px auto 100px auto;/' \
            "${ARGON_CSS}"
        echo "  ✓ Brand margin 居中"

        # 删除登录页图标样式
        sed -i '/^.login-page .login-container .login-form .brand .icon {/,/^}/d' \
            "${ARGON_CSS}"
        echo "  ✓ 登录页图标样式已删除"

        # 登录页 Brand 文字渐变
        sed -i '/\.login-page \.login-container \.login-form \.brand \.brand-text {/,/}/c\
.login-page .login-container .login-form .brand .brand-text {\
  margin-right: 0px; font-size: 2.6rem; font-weight: 400;\
  font-family: "TypoGraphica", sans-serif; word-break: break-word;\
  background: linear-gradient(120deg,#00fff7,#007cf0,#ff4ecd,#00fff7);\
  background-size: 300% 300%; -webkit-background-clip: text;\
  -webkit-text-fill-color: transparent;\
  animation: shine 5s linear infinite;\
}' "${ARGON_CSS}"
        echo "  ✓ 登录页 Brand 文字渐变已注入"

        # 登录按钮样式
        sed -i '/\.login-page \.login-container \.login-form \.cbi-button-apply {/,/}/c\
.login-page .login-container .login-form .cbi-button-apply {\
  width: 100% !important; min-height: 45px; margin: 30px 0 100px;\
  padding: 10px 0; font-size: 15px; font-weight: 600;\
  text-align: center; letter-spacing: .35rem;\
  background: rgba(0,0,0,0); backdrop-filter: blur(8px);\
  border: none; border-radius: 9999px; outline: none;\
  cursor: pointer; transition: all 0.25s ease; position: relative;\
}' "${ARGON_CSS}"
        echo "  ✓ 登录按钮样式已注入"

        # 登录按钮 Hover
        sed -i '/\.login-page \.login-container \.login-form \.cbi-button-apply:hover {/,/}/c\
.login-page .login-container .login-form .cbi-button-apply:hover {\
  box-shadow: 0 0 0 2px rgba(255,255,255,0.5);\
}' "${ARGON_CSS}"
        echo "  ✓ 登录按钮 Hover 样式已注入"

        # 链接激活颜色
        sed -i '/a:active {/,/}/ s/var(--primary)/#dddddd/g' "${ARGON_CSS}"
        echo "  ✓ 链接激活颜色已修改"

        echo "  ✓ CSS 修改全部完成"
    fi

    # 5.3 Footer 链接删除
    FOOTER_LOGIN="${ARGON_BASE}/ucode/template/themes/argon/footer_login.ut"
    [ -f "${FOOTER_LOGIN}" ] && {
        sed -i '/<footer/,/<\/footer>/ { /<a class="luci-link"/d }' \
            "${FOOTER_LOGIN}"
        echo "  ✓ Footer 链接已删除"
    }

    # 5.4 SVG Logo 删除
    SYSAUTH="${ARGON_BASE}/ucode/template/themes/argon/sysauth.ut"
    [ -f "${SYSAUTH}" ] && {
        sed -i 's#<img src="{{ media }}/img/argon.svg" class="icon">##g' \
            "${SYSAUTH}"
        echo "  ✓ SVG 图标已删除"
    }
fi

# -----------------------------------------------------------------
# 第6节：设置 LuCI 默认语言为简体中文
# 两种方式互为补充：
#   方式A：预置 files/etc/config/luci（编译时直接打包进固件）
#   方式B：uci-defaults 脚本（首次开机时写入，覆盖方式A）
# -----------------------------------------------------------------
echo ""
echo ">>> 设置 LuCI 默认简体中文..."

# ---------------------------
# 方式A：预置 /etc/config/luci
# ---------------------------
mkdir -p package/base-files/files/etc/config

cat > package/base-files/files/etc/config/luci << 'EOF'
config core 'main'
	option lang zh_Hans
	option mediaurlbase '/luci-static/argon'

config extern 'flash_keep'
	option uci '/etc/config/uci'
EOF

echo "  ✓ 方式A：/etc/config/luci 已预置（lang=zh_Hans，theme=argon）"

# ---------------------------
# 方式B：uci-defaults 脚本
# ---------------------------
mkdir -p package/base-files/files/etc/uci-defaults

cat > package/base-files/files/etc/uci-defaults/99-luci-language << 'EOF'
#!/bin/sh
# 首次开机自动执行：强制写入 LuCI 默认语言和主题
# 即使方式A的配置文件被 flash_keep 覆盖，此脚本仍可兜底

uci -q batch << 'UCIEOF'
set luci.main=core
set luci.main.lang=zh_Hans
set luci.main.mediaurlbase=/luci-static/argon
UCIEOF

uci commit luci

exit 0
EOF

chmod +x package/base-files/files/etc/uci-defaults/99-luci-language
echo "  ✓ 方式B：uci-defaults/99-luci-language 已写入（首次开机兜底）"

echo ""
echo "✅ diy-part2.sh 全部执行完成"
