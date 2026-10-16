#!/usr/bin/env python3
"""
设备侧 UI 回归门槛：扫描整个聊天会话，检查**每个文本节点是否越出它紧邻的容器**。

用法（通常由 `ui_regression.sh` 调用，也可单独用）：

    python3 docs/qa/p1/ui_regression.py <dump1.json> [dump2.json ...] [选项]

选项：
    --window <px>       窗口宽度（默认 1320），用于识别「横向 Scroll」并自动豁免
    --baseline <file>   已知可接受项清单（JSON）；存在时只报告**新增**越出
    --save-baseline <f> 把本次全部越出写入该文件（作为已知清单）
    --json              以 JSON 输出结果（便于 CI 消费）

## 为什么需要它

聊天文字溢出气泡这个问题前后修了四轮才收敛，根因是**验收口径**而非单个 bug：

1. 只测自己构造的用例 → 漏掉用户气泡、长 URL、表格、深层列表；
2. 改完没复测 → 报告了假数据（「170 行 → 4 行」）；
3. 只跟「气泡右边界」比 → 漏掉「工具卡越出气泡内边距」「嵌套列表越出**子**容器」。
   —— 第 3 条是最后才发现的，靠的就是本脚本的口径。

本脚本对**每一层容器**都比对，因此不论溢出发生在哪一层都会被抓住。

## 自动豁免

表格列放在横向 `Scroll` 里（宽度明显小于窗口、非聊天竖滚），
列内文本越出列宽是**设计行为**（横向可滚动）。识别方式见 `inside_horizontal_scroll()`，
不依赖硬编码坐标。

退出码：0 通过；1 有越出；2 用法/输入错误。
"""
import json
import re
import sys

CONTAINER_TYPES = ('Column', 'Row', 'Flex')
TOLERANCE = 2          # px：容忍抗锯齿/取整
TOP_SAFE = 380         # 跳过顶部标题栏
BOTTOM_SAFE = 2500     # 跳过底部输入栏


def bounds_of(node):
    raw = node.get('attributes', {}).get('bounds', '') or ''
    nums = re.findall(r'-?\d+', raw)
    return tuple(map(int, nums)) if len(nums) == 4 else None


def collect(tree):
    """
    单遍遍历，产出每个节点的
    (type, text, bounds, parent_container_type, parent_container_bounds, scroll_widths)
    `parent_*` 为**最近的** Column/Row/Flex 祖先；`scroll_widths` 为祖先 Scroll 的宽度集合。
    """
    out = []

    def walk(node, parent_type, parent_box, scroll_widths):
        attrs = node.get('attributes', {})
        node_type = attrs.get('type', '') or ''
        text = attrs.get('text', '') or ''
        box = bounds_of(node)
        out.append((node_type, text, box, parent_type, parent_box, scroll_widths))

        next_scrolls = scroll_widths
        if node_type == 'Scroll' and box is not None:
            next_scrolls = scroll_widths + (box[2] - box[0],)
        if node_type in CONTAINER_TYPES and box is not None:
            next_type, next_box = node_type, box
        else:
            next_type, next_box = parent_type, parent_box
        for child in node.get('children', []):
            walk(child, next_type, next_box, next_scrolls)

    walk(tree, '', None, ())
    return out


def inside_horizontal_scroll(scroll_widths, window_width):
    """祖先里是否存在「明显窄于窗口」的 Scroll —— 表格列的横向滚动容器。"""
    return any(w < window_width * 0.85 for w in scroll_widths)


def scan(path, window_width):
    """返回该 dump 中的越出项 [(text, x1, parent_right, over, parent_type)]。"""
    tree = json.load(open(path, encoding='utf-8'))
    bad = []
    for node_type, text, box, parent_type, parent_box, scroll_widths in collect(tree):
        if node_type != 'Text' or not text or box is None or parent_box is None:
            continue
        if box[1] < TOP_SAFE or box[3] > BOTTOM_SAFE:
            continue
        if inside_horizontal_scroll(scroll_widths, window_width):
            continue
        over = box[2] - parent_box[2]
        if over > TOLERANCE:
            bad.append((text, box[2], parent_box[2], over, parent_type))
    return bad


def key_of(item):
    return f'{item[0][:40]}|{item[1]}|{item[3]}'


def main():
    argv = sys.argv[1:]
    files = []
    window_width = 1320
    baseline_file = None
    save_file = None
    as_json = False
    i = 0
    while i < len(argv):
        arg = argv[i]
        if arg == '--window':
            i += 1
            window_width = int(argv[i])
        elif arg == '--baseline':
            i += 1
            baseline_file = argv[i]
        elif arg == '--save-baseline':
            i += 1
            save_file = argv[i]
        elif arg == '--json':
            as_json = True
        elif arg.startswith('--'):
            print(f'未知选项 {arg}')
            return 2
        else:
            files.append(arg)
        i += 1

    if not files:
        print(__doc__)
        return 2

    all_bad = []
    scanned = 0
    for path in files:
        bad = scan(path, window_width)
        scanned += 1
        for item in bad:
            all_bad.append(item)

    # 去重：同一文本在不同滚动位置会重复出现
    seen = set()
    unique = []
    for item in all_bad:
        k = key_of(item)
        if k in seen:
            continue
        seen.add(k)
        unique.append(item)

    known = set()
    if baseline_file:
        try:
            known = {entry['key'] for entry in json.load(open(baseline_file, encoding='utf-8'))}
        except FileNotFoundError:
            pass

    new_items = [it for it in unique if key_of(it) not in known]

    if save_file:
        json.dump(
            [{'key': key_of(it), 'text': it[0][:60], 'x1': it[1], 'parentRight': it[2], 'over': it[3]}
             for it in unique],
            open(save_file, 'w', encoding='utf-8'), ensure_ascii=False, indent=2)

    if as_json:
        print(json.dumps({
            'dumps': scanned,
            'overflowTotal': len(unique),
            'overflowNew': len(new_items),
            'items': [{'text': it[0][:60], 'x1': it[1], 'parentRight': it[2], 'over': it[3],
                       'parent': it[4]} for it in new_items]
        }, ensure_ascii=False, indent=2))
        return 1 if new_items else 0

    print(f'扫描 {scanned} 份布局 dump，窗口宽 {window_width}px')
    print(f'越出紧邻容器的文本（去重后）: {len(unique)}，其中新增 {len(new_items)}')
    for it in new_items[:15]:
        print(f'  ❌ x1={it[1]:>5} 父{it[4]}右={it[2]:>5} 超{it[3]:>4}px  {it[0][:40]!r}')
    if unique and not new_items:
        print('  （其余均在 baseline 已知清单内）')
    if not new_items:
        print('  ✅ 无新增越出')
    return 1 if new_items else 0


if __name__ == '__main__':
    sys.exit(main())
