#!/bin/sh
# SIM 卡槽切换脚本
# 支持设备：UFI001C（4路 SIM 槽 GPIO 控制）
#
# ✅ 对照上游内核 config 的 modem 模块支持情况：
#   config-6.6 : CONFIG_QCOM_Q6V5_MSS=n → rmmod/modprobe 无效，改用 kmod-qcom-rproc-modem 路径
#   config-6.12: CONFIG_QCOM_Q6V5_MSS=n → 同上
#   config-6.18: CONFIG_QCOM_Q6V5_MSS=m → 可直接 rmmod/modprobe
#
# 用法：cardswitch.sh <1|2|3|4>

# ✅ 修复 Bug3：$1 加引号，修复 Bug2：-z 替代 [ ! $1 ]
if [ -z "$1" ]; then
    echo "用法: $(basename $0) <槽号>"
    echo "槽号范围: 1-4"
    exit 1
fi

# ✅ 修复 Bug5：先验证槽号合法性，非法值直接退出
case "$1" in
    1|2|3|4)
        ;;
    *)
        echo "❌ 错误：无效槽号 '$1'，仅支持 1-4"
        exit 1
        ;;
esac

LED_SEL="/sys/class/leds/sim:sel/brightness"
LED_EN="/sys/class/leds/sim:en/brightness"
LED_SEL2="/sys/class/leds/sim:sel2/brightness"
LED_EN2="/sys/class/leds/sim:en2/brightness"

# ✅ 修复 Bug6：写入前先验证所有 sysfs 节点存在
for node in "$LED_SEL" "$LED_EN" "$LED_SEL2" "$LED_EN2"; do
    if [ ! -f "$node" ]; then
        echo "❌ 错误：LED 节点不存在: $node"
        echo "   请确认设备为 UFI001C 且驱动已正确加载"
        exit 1
    fi
done

echo "🔄 切换到 SIM 槽 $1 ..."

# ✅ 修复 Bug2：[ ] 内使用 = 替代 ==（POSIX sh 规范）
# ✅ 修复 Bug3：$1 加引号
# ✅ 修复 Bug8：改用 case 替代多个独立 if，效率更高
case "$1" in
    1)
        echo 1 > "$LED_SEL"  && \
        echo 0 > "$LED_EN"   && \
        echo 0 > "$LED_SEL2" && \
        echo 0 > "$LED_EN2"  || { echo "❌ LED 写入失败，操作中止"; exit 1; }
        ;;
    2)
        echo 0 > "$LED_SEL"  && \
        echo 1 > "$LED_EN"   && \
        echo 0 > "$LED_SEL2" && \
        echo 0 > "$LED_EN2"  || { echo "❌ LED 写入失败，操作中止"; exit 1; }
        ;;
    3)
        echo 0 > "$LED_SEL"  && \
        echo 0 > "$LED_EN"   && \
        echo 1 > "$LED_SEL2" && \
        echo 0 > "$LED_EN2"  || { echo "❌ LED 写入失败，操作中止"; exit 1; }
        ;;
    4)
        echo 0 > "$LED_SEL"  && \
        echo 0 > "$LED_EN"   && \
        echo 0 > "$LED_SEL2" && \
        echo 1 > "$LED_EN2"  || { echo "❌ LED 写入失败，操作中止"; exit 1; }
        ;;
esac

echo "✅ SIM 槽 $1 LED 切换完成"

# ✅ 修复 Bug7：等待硬件 SIM 槽物理切换完成（300ms）
sleep 0.3

# ✅ 修复 Bug1 + Bug4：根据内核版本选择正确的 modem 重载方式
# 对照上游 config：
#   6.6 / 6.12: CONFIG_QCOM_Q6V5_MSS=n → 模块不存在，通过 init.d 服务重启
#   6.18:       CONFIG_QCOM_Q6V5_MSS=m → 可直接操作内核模块
echo "🔄 重载 modem 驱动..."

# 检测 qcom-q6v5-mss 模块是否可用（仅 6.18 内核存在）
if modinfo qcom-q6v5-mss > /dev/null 2>&1; then
    # 6.18 内核路径：直接操作内核模块
    echo "  检测到 qcom-q6v5-mss 模块（6.18 内核），执行 rmmod/modprobe..."
    rmmod qcom-q6v5-mss 2>/dev/null || true
    sleep 0.5
    modprobe qcom-q6v5-mss || { echo "❌ modprobe qcom-q6v5-mss 失败"; exit 1; }
    echo "  ✅ 内核模块重载完成"
else
    # 6.6 / 6.12 内核路径：通过 remoteproc sysfs 触发 modem 重启
    echo "  qcom-q6v5-mss 模块不可用（6.6/6.12 内核），通过 remoteproc 重启..."
    RPROC_PATH=$(find /sys/bus/platform/devices/ -name "*.mss" -type d 2>/dev/null | head -1)
    if [ -n "$RPROC_PATH" ]; then
        REMOTEPROC=$(find "$RPROC_PATH" -name "remoteproc*" -type d 2>/dev/null | head -1)
        if [ -n "$REMOTEPROC" ] && [ -f "${REMOTEPROC}/state" ]; then
            echo "stop"  > "${REMOTEPROC}/state" 2>/dev/null || true
            sleep 0.5
            echo "start" > "${REMOTEPROC}/state" 2>/dev/null || true
            echo "  ✅ remoteproc 重启完成"
        else
            echo "  ⚠️ remoteproc 节点未找到，跳过 modem 重启"
        fi
    else
        echo "  ⚠️ MSS 设备节点未找到，跳过 modem 重启"
    fi
fi

# ✅ 修复 Bug4：service → /etc/init.d/（OpenWrt procd 规范）
echo "🔄 重启相关服务..."

if [ -x "/etc/init.d/rmtfs" ]; then
    /etc/init.d/rmtfs restart 2>/dev/null && \
        echo "  ✅ rmtfs 重启完成" || \
        echo "  ⚠️ rmtfs 重启失败（服务可能未运行）"
else
    echo "  ⚠️ rmtfs 服务不存在，跳过"
fi

if [ -x "/etc/init.d/modemmanager" ]; then
    /etc/init.d/modemmanager restart 2>/dev/null && \
        echo "  ✅ modemmanager 重启完成" || \
        echo "  ⚠️ modemmanager 重启失败（服务可能未运行）"
else
    echo "  ⚠️ modemmanager 服务不存在，跳过"
fi

echo ""
echo "✅ SIM 槽切换全部完成！当前槽号: $1"
echo "   请等待 10-30 秒让 modem 注册网络..."
