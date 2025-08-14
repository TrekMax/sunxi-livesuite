#!/usr/bin/env bash
set -e

current_kernel=$(uname -r)

echo "=== 检查当前运行的内核版本 ==="
echo "当前内核: $current_kernel"
echo

echo "=== 检查内核头文件是否安装 ==="
if [ ! -d "/lib/modules/$current_kernel/build" ]; then
    echo "❌ 没找到对应的内核头文件，正在安装..."
    sudo apt update
    sudo apt install -y linux-headers-$current_kernel
else
    echo "✅ 已安装: /lib/modules/$current_kernel/build"
fi
echo

echo "=== 检查关键 CONFIG_* 配置一致性 ==="
config_runtime="/boot/config-$current_kernel"
config_build="/lib/modules/$current_kernel/build/.config"
need_reinstall=false

if [ -f "$config_runtime" ] && [ -f "$config_build" ]; then
    diff_lines=$(diff -u <(grep -E '^CONFIG_(PREEMPT|MODVERSIONS|MODULE_SIG)' "$config_runtime") \
                      <(grep -E '^CONFIG_(PREEMPT|MODVERSIONS|MODULE_SIG)' "$config_build") || true)
    if [ -n "$diff_lines" ]; then
        echo "⚠️ 检测到关键 CONFIG_* 配置不一致："
        echo "$diff_lines"
        echo "将重新安装 linux-headers-$current_kernel..."
        need_reinstall=true
    else
        echo "✅ 关键 CONFIG_* 配置一致"
    fi
else
    echo "⚠️ 无法找到内核配置文件，跳过 CONFIG_* 检查"
fi
echo

if [ "$need_reinstall" = true ]; then
    sudo apt install --reinstall -y linux-headers-$current_kernel
fi

echo "=== 检查 Makefile 中的 KDIR 设置 ==="
if [ -f Makefile ]; then
    kdir_line=$(grep -E "KDIR\s*:?=" Makefile || true)
    if [[ "$kdir_line" != *"/lib/modules/\$(shell uname -r)/build"* ]]; then
        echo "⚠️ Makefile 可能没有使用当前内核的 headers"
        echo "建议改为:"
        echo "    KDIR := /lib/modules/\$(shell uname -r)/build"
    else
        echo "✅ Makefile 中 KDIR 配置正确"
    fi
else
    echo "⚠️ 当前目录没有 Makefile，请确认你在模块源码目录"
fi
echo

echo "=== 清理旧编译并重新编译模块 ==="
if [ -f Makefile ]; then
    make clean
    make
    echo "✅ 模块已重新编译"
else
    echo "❌ 没找到 Makefile，无法编译模块"
    exit 1
fi
echo

echo "=== 检查编译出来的 vermagic 是否匹配 ==="
ko_file=$(find . -maxdepth 1 -name "*.ko" | head -n 1 || true)
if [ -n "$ko_file" ]; then
    vermagic=$(modinfo "$ko_file" | awk '/vermagic/ {print $2}')
    echo "模块 vermagic: $vermagic"
    if [[ "$vermagic" != "$current_kernel" ]]; then
        echo "❌ vermagic 与当前内核不匹配！"
        echo "   当前内核: $current_kernel"
        echo "   模块 vermagic: $vermagic"
        echo "已尝试修复，但依然不匹配，请检查 KDIR 设置"
        exit 1
    else
        echo "✅ vermagic 与当前内核匹配"
    fi
else
    echo "❌ 没找到 .ko 文件"
    exit 1
fi
echo

echo "=== 检查系统中是否已加载旧版 awusb 模块 ==="
if lsmod | grep -q "^awusb"; then
    echo "⚠️ 检测到旧版 awusb 已加载，正在卸载..."
    sudo rmmod awusb || { echo "❌ 卸载失败"; exit 1; }
    echo "✅ 已卸载旧模块"
else
    echo "✅ 系统中未加载 awusb"
fi
echo

read -p "是否直接加载新编译的模块 $ko_file ? [y/N]: " load_now
if [[ "$load_now" =~ ^[Yy]$ ]]; then
    sudo insmod "$ko_file" && echo "✅ 模块已加载成功" || echo "❌ 模块加载失败"
fi

echo "=== 完成 ==="
