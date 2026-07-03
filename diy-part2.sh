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
# -----------------------------------------------------------------
BUILD_DATE=$(date +"%Y.%m.%d")
STATUS_JS=$(find ./feeds/luci/modules/luci-mod-status/ -type f -name "10_system.js" 2>/dev/null | head -1)
if [ -n "$STATUS_JS" ]; then
    sed -i "s/\(luciversion || ''\)/\\1) + (' \/ UFI001C-${BUILD_DATE}')/g" "$STATUS_JS"
    echo "✅ 编译日期标识已注入: UFI001C-${BUILD_DATE}"
else
    echo "⚠️ 10_system.js 未找到，跳过日期标识注入"
fi

# 3.TurboAcc 加速脚本（含备用源容错）
echo ">>> 执行 TurboAcc 安装脚本..."
# 检查 curl 命令是否存在
if ! command -v curl &> /dev/null
then
    echo "⚠️ curl 命令不存在，跳过TurboAcc下载"
else
    echo "🚀 尝试下载 TurboAcc 安装脚本..."
    curl -sSL https://raw.githubusercontent.com/mufeng05/turboacc/main/add_turboacc.sh -o add_turboacc.sh 2>/dev/null || \
    (echo "⚠️ 备用源下载失败，尝试其他源..." && curl -sSL https://raw.githubusercontent.com/chenmozhijin/turboacc/luci/add_turboacc.sh -o add_turboacc.sh 2>/dev/null) || \
    { echo "⚠️ TurboAcc 所有源均失败，跳过"; exit 0; }

    if [ -f "add_turboacc.sh" ]; then
        bash add_turboacc.sh \
            && echo "✅ TurboAcc 脚本执行完成" \
            || echo "⚠️ TurboAcc 脚本执行失败，跳过"
    else
        echo "⚠️ add_turboacc.sh 文件未成功下载，跳过执行"
    fi
fi

# -----------------------------------------------------------------
# 4. BBR 设为系统默认拥塞控制算法
# ✅ 修正：if/else 两个分支都确保写入 fq 和 bbr 两条配置
# -----------------------------------------------------------------
SYSCTL_FILE="package/base-files/files/etc/sysctl.conf"
mkdir -p package/base-files/files/etc

if [ -f "$SYSCTL_FILE" ]; then
    # 文件已存在，幂等写入（避免重复）
    grep -q 'tcp_congestion_control' "$SYSCTL_FILE" || \
        echo "net.ipv4.tcp_congestion_control=bbr" >> "$SYSCTL_FILE"
    grep -q 'default_qdisc' "$SYSCTL_FILE" || \
        echo "net.core.default_qdisc=fq" >> "$SYSCTL_FILE"
    echo "✅ BBR + fq 已写入已有 sysctl.conf"
else
    # 文件不存在，创建并写入
    echo "net.ipv4.tcp_congestion_control=bbr" >> "$SYSCTL_FILE"
    echo "net.core.default_qdisc=fq" >> "$SYSCTL_FILE"
    echo "✅ sysctl.conf 已创建并写入 BBR + fq 配置"
fi

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

echo ""
echo "✅ diy-part2.sh 全部执行完成"
