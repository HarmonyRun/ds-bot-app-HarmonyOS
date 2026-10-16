#!/usr/bin/env bash
# 设备侧 UI 回归门槛：把「启动应用 → 逐段滚动采集布局 → 逐层校验越界」串成一条命令。
#
# 用法：
#   bash docs/qa/p1/ui_regression.sh [选项]
#
# 选项：
#   -d <设备号>     默认 127.0.0.1:5555（模拟器）
#   -s <屏数>       向下滚动采集多少屏，默认 8
#   -o <输出目录>   中间产物（dump/截图）存放处，默认 /tmp/dsprobe/uireg
#   -b <baseline>   已知可接受清单（JSON）；只报告**新增**越出
#   --save-baseline 把本次全部越出写成清单（用于首次建立基线）
#   --enter-chat    启动后点击会话列表第一项进入聊天（手机单栏需要）
#   -h              帮助
#
# 退出码：0 无新增越出；1 有新增越出；2 环境/用法问题。
#
# ## 设计意图
#
# 聊天文字溢出气泡前后修了四轮，根因是**验收口径**：早期只量自己构造的用例、
# 只与「气泡右边界」比对，导致「工具卡越出内边距」「嵌套列表越出子容器」长期漏检。
# 本脚本把口径固定为「每个文本 vs 它紧邻的容器」，并覆盖整个会话（不只是当前屏），
# 让这类回归变成可自动判定的门槛，而不是靠人工发现。
#
# ## 前置条件
#
# - 应用已安装且**已配对**（未配对会停在连接页，脚本会提示）。
# - 设备可被 hdc 访问；`uitest` 可用。
#
# 想要可重复的受控数据，可先用 mock 主机（见 P1 报告 §9.1）：
#   node /tmp/dsprobe/mock-host.mjs questions
set -u

DEV="127.0.0.1:5555"
SCREENS=8
OUT=/tmp/dsprobe/uireg
BASELINE=""
SAVE_BASELINE=0
ENTER_CHAT=0
HERE="$(cd "$(dirname "$0")" && pwd)"
HDC="${HDC:-$(command -v hdc || echo /Applications/DevEco-Studio.app/Contents/sdk/default/openharmony/toolchains/hdc)}"
TMP=/data/local/tmp
PKG=app.dsbot.harmony

while getopts "d:s:o:b:h-:" opt; do
  case "$opt" in
    d) DEV="$OPTARG" ;;
    s) SCREENS="$OPTARG" ;;
    o) OUT="$OPTARG" ;;
    b) BASELINE="$OPTARG" ;;
    h) sed -n '2,40p' "$0"; exit 0 ;;
    -) case "$OPTARG" in
         save-baseline) SAVE_BASELINE=1 ;;
         enter-chat) ENTER_CHAT=1 ;;
         *) echo "未知选项 --$OPTARG"; exit 2 ;;
       esac ;;
    *) exit 2 ;;
  esac
done

mkdir -p "$OUT"

if ! "$HDC" list targets | tr -d '\r' | grep -q "^${DEV}$"; then
  echo "设备 ${DEV} 未连接。当前设备："
  "$HDC" list targets
  exit 2
fi

echo "=== 设备与安装状态 ==="
"$HDC" -t "$DEV" shell "param get const.product.model" 2>&1 | tr -d '\r' | sed 's/^/  /'
if ! "$HDC" -t "$DEV" shell "bm dump -a 2>/dev/null" | tr -d '\r' | grep -q "$PKG"; then
  echo "  ❌ 未安装 $PKG（真机需先签名安装，见 P1 报告 §8.1）"
  exit 2
fi
echo "  已安装 $PKG"

echo "=== 启动 ==="
"$HDC" -t "$DEV" shell "aa force-stop $PKG" >/dev/null 2>&1
sleep 1
"$HDC" -t "$DEV" shell "aa start -a EntryAbility -b $PKG" >/dev/null 2>&1
sleep 8

# 窗口宽度用于识别表格的横向 Scroll（自动豁免）
WIN="$("$HDC" -t "$DEV" shell "snapshot_display -f ${TMP}/_w.jpeg" >/dev/null 2>&1; \
       "$HDC" -t "$DEV" file recv "${TMP}/_w.jpeg" "$OUT/_w.jpeg" >/dev/null 2>&1; \
       python3 -c "from PIL import Image;print(Image.open('$OUT/_w.jpeg').size[0])" 2>/dev/null || echo 1320)"
echo "  窗口宽 ${WIN}px"

if [ "$ENTER_CHAT" = "1" ]; then
  echo "=== 进入聊天 ==="
  # 会话列表第一项的大致位置（手机单栏）；失败不致命，后续 dump 会体现出来
  "$HDC" -t "$DEV" shell "uitest uiInput click $((WIN / 2)) 830" >/dev/null 2>&1
  sleep 5
fi

echo "=== 逐段采集（$SCREENS 屏）==="
DUMPS=()
for i in $(seq 1 "$SCREENS"); do
  name="ui$i"
  "$HDC" -t "$DEV" shell "uitest dumpLayout -p ${TMP}/${name}.json" >/dev/null 2>&1
  "$HDC" -t "$DEV" file recv "${TMP}/${name}.json" "$OUT/${name}.json" >/dev/null 2>&1
  if [ -s "$OUT/${name}.json" ]; then
    DUMPS+=("$OUT/${name}.json")
  fi
  # 向下滚动一屏（部分重叠，避免漏掉边界内容）
  "$HDC" -t "$DEV" shell "uitest uiInput swipe $((WIN / 2)) 2100 $((WIN / 2)) 900 300" >/dev/null 2>&1
  sleep 1
done
echo "  采集到 ${#DUMPS[@]} 份布局 dump → $OUT"

if [ "${#DUMPS[@]}" = "0" ]; then
  echo "  ❌ 没采到 dump；应用可能停在连接页（需先配对）"
  exit 2
fi

# 是否停在连接页：出现「连接我的主机」即视为未配对
if grep -q "连接我的主机" "$OUT/ui1.json" 2>/dev/null; then
  echo "  ⚠️  应用停在连接页（未配对），本次结果只覆盖连接页布局"
fi

echo "=== 逐层越界校验 ==="
ARGS=(--window "$WIN")
if [ -n "$BASELINE" ]; then ARGS+=(--baseline "$BASELINE"); fi
if [ "$SAVE_BASELINE" = "1" ]; then ARGS+=(--save-baseline "$OUT/baseline.json"); fi
python3 "$HERE/ui_regression.py" "${DUMPS[@]}" "${ARGS[@]}"
RC=$?

echo "=== 截图存证 ==="
"$HDC" -t "$DEV" shell "snapshot_display -f ${TMP}/uireg.jpeg" >/dev/null 2>&1
"$HDC" -t "$DEV" file recv "${TMP}/uireg.jpeg" "$OUT/uireg.jpeg" >/dev/null 2>&1
echo "  $OUT/uireg.jpeg"

if [ "$SAVE_BASELINE" = "1" ]; then
  echo "  已写入基线：$OUT/baseline.json"
fi
exit $RC
