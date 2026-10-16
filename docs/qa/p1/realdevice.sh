#!/usr/bin/env bash
# 真机（HUAWEI Pura X Max，折叠屏，API 26）实测取证据脚本。
#
# 用法：
#   bash docs/qa/p1/realdevice.sh [设备号]
# 默认设备号：6HQ0226401001596
#
# 产出：在脚本同目录生成 realdevice-*.jpeg 截图，并把关键布局节点的 bounds 打印出来。
# 设计意图：真机与模拟器的差异主要是「窗口尺寸/密度/折叠态」，
# 所以这里固定采集「截图 + UI 布局 dump」两类证据，便于和模拟器的结果并排比对。
set -u

DEV="${1:-6HQ0226401001596}"
HERE="$(cd "$(dirname "$0")" && pwd)"
HDC="${HDC:-$(command -v hdc || echo /Applications/DevEco-Studio.app/Contents/sdk/default/openharmony/toolchains/hdc)}"
TMP=/data/local/tmp

if ! "$HDC" list targets | tr -d '\r' | grep -q "^${DEV}$"; then
  echo "设备 ${DEV} 未连接。当前设备："
  "$HDC" list targets
  exit 1
fi

shot() { # shot <名字>
  "$HDC" -t "$DEV" shell "snapshot_display -f ${TMP}/$1.jpeg" >/dev/null 2>&1
  "$HDC" -t "$DEV" file recv "${TMP}/$1.jpeg" "${HERE}/realdevice-$1.jpeg" >/dev/null 2>&1
  echo "  截图 → docs/qa/p1/realdevice-$1.jpeg"
}

dump() { # dump <名字>；打印所有非空文本与交互控件的 bounds
  "$HDC" -t "$DEV" shell "uitest dumpLayout -p ${TMP}/$1.json" >/dev/null 2>&1
  "$HDC" -t "$DEV" file recv "${TMP}/$1.json" "${HERE}/realdevice-$1.json" >/dev/null 2>&1
  python3 - "$HERE/realdevice-$1.json" <<'PY'
import json, sys
d = json.load(open(sys.argv[1]))
rows = []
def walk(n):
    a = n.get('attributes', {})
    t = a.get('text', '') or ''
    ty = a.get('type', '') or ''
    if t or ty in ('Button', 'TextArea', 'TextInput'):
        rows.append((a.get('bounds', ''), ty, t[:28]))
    for c in n.get('children', []):
        walk(c)
walk(d)
for b, ty, t in rows[:40]:
    print(f'    {b:24s} {ty:9s} {t!r}')
PY
}

echo "=== 设备信息 ==="
"$HDC" -t "$DEV" shell "param get const.product.model; param get const.ohos.apiversion" 2>&1 | tr -d '\r' | sed 's/^/  /'

echo "=== 应用是否已安装 ==="
if "$HDC" -t "$DEV" shell "bm dump -a 2>/dev/null" | tr -d '\r' | grep -q "app.dsbot.harmony"; then
  echo "  已安装 app.dsbot.harmony"
else
  echo "  未安装 —— 需要先在 DevEco 里 Run 一次（真机不接受未签名 HAP）"
  exit 2
fi

echo "=== 启动 ==="
"$HDC" -t "$DEV" shell "aa force-stop app.dsbot.harmony" >/dev/null 2>&1
sleep 1
"$HDC" -t "$DEV" shell "aa start -a EntryAbility -b app.dsbot.harmony" >/dev/null 2>&1
sleep 10

echo "=== 采集首屏 ==="
shot home
dump home

echo "=== 提示 ==="
echo "  1) 真机是 2584x1828 横屏（约 861vp 宽），会走 windowWidth>=600 的多栏布局。"
echo "  2) 折叠/展开或旋转后，重跑本脚本即可采集第二组证据对比。"
echo "  3) 头像黑边复核：先 dump 出头像节点 bounds，再跑"
echo "     python3 docs/qa/p1/check_black_pixels.py docs/qa/p1/realdevice-home.jpeg \""
echo "         \"x0,y0,x1,y1:标签\" ..."
echo "     （不要用自动分块口径：它会把标题栏文字/图标算进来）"
