#!/usr/bin/env python3
"""
量化验收：消息区所有文本是否越出**紧邻的容器**。

用法：
    hdc shell "uitest dumpLayout -p /data/local/tmp/x.json"
    hdc file recv /data/local/tmp/x.json /tmp/x.json
    python3 docs/qa/p1/check_text_bounds.py /tmp/x.json

## 为什么要有这个脚本

聊天文字溢出气泡这个问题修了四轮才收敛，核心教训是**验收口径不对**：

- 只跟「气泡右边界」比对 → 漏掉「工具卡越出气泡内边距」「嵌套列表越出**子**容器」这两类；
- 只测自己构造的用例 → 漏掉用户气泡、长 URL、表格、深层列表。

本脚本对**每个文本节点**都拿它与**最近的 Column/Row/Flex 祖先**比对右边界，
不管溢出发生在哪一层容器都会被抓到。表格列在横向 `Scroll` 里，越出表格可见区属设计行为，
用 `--ignore-table` 跳过（判定依据：祖先链里出现宽度≈444px 的固定列容器）。

退出码：0 全部在界内；1 有越出；2 用法错误。
"""
import json
import re
import sys

CONTAINER_TYPES = ('Column', 'Row', 'Flex')


def bounds_of(node):
    raw = node.get('attributes', {}).get('bounds', '') or ''
    nums = re.findall(r'-?\d+', raw)
    return tuple(map(int, nums)) if len(nums) == 4 else None


def collect(tree):
    """
    单遍遍历，返回 [(type, text, bounds, parent_container_type, parent_container_bounds)]。
    `parent_*` 是**最近的** Column/Row/Flex 祖先（不是直接父节点）。
    """
    out = []

    def walk(node, parent_type, parent_box):
        attrs = node.get('attributes', {})
        node_type = attrs.get('type', '') or ''
        text = attrs.get('text', '') or ''
        box = bounds_of(node)
        out.append((node_type, text, box, parent_type, parent_box))
        if node_type in CONTAINER_TYPES and box is not None:
            next_type, next_box = node_type, box
        else:
            next_type, next_box = parent_type, parent_box
        for child in node.get('children', []):
            walk(child, next_type, next_box)

    walk(tree, '', None)
    return out


def main():
    args = [a for a in sys.argv[1:] if not a.startswith('--')]
    ignore_table = '--ignore-table' in sys.argv
    if not args:
        print(__doc__)
        return 2
    tree = json.load(open(args[0], encoding='utf-8'))
    items = collect(tree)

    checked = 0
    bad = []
    for node_type, text, box, parent_type, parent_box in items:
        if node_type != 'Text' or not text or box is None:
            continue
        # 只检查消息区（跳过顶部标题栏与底部输入栏）
        if box[1] < 380 or box[3] > 2500:
            continue
        if parent_box is None:
            continue
        if ignore_table and (parent_box[2] - parent_box[0]) < 500 and parent_box[2] > box[2]:
            # 固定宽度的表格列容器：其内容在横向 Scroll 里，属设计行为
            continue
        checked += 1
        over = box[2] - parent_box[2]
        if over > 2:
            bad.append((text, box, parent_box, over))

    print(args[0])
    print(f'  消息区文本节点 {checked} 个；越出紧邻容器右边界 = {len(bad)}')
    for text, box, parent, over in bad[:12]:
        print(f'    ❌ x1={box[2]:>5} 父容器({parent[0]}-{parent[2]})右={parent[2]:>5} '
              f'超{over:>4}px  {text[:38]!r}')
    if not bad:
        print('    ✅ 全部在紧邻容器内')
    return 1 if bad else 0


if __name__ == '__main__':
    sys.exit(main())
