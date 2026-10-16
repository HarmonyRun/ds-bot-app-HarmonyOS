#!/usr/bin/env python3
"""
量化验收：表格同行单元格是否等高、等宽。

用法：
    # 1) 在设备上把表格滚到可见，然后 dump 布局
    hdc shell "uitest dumpLayout -p /data/local/tmp/t.json"
    hdc file recv /data/local/tmp/t.json /tmp/t.json

    # 2) 校验
    python3 docs/qa/p1/check_table_cells.py /tmp/t.json

背景（2026-10-16 用户报告「表格消息左右单元格高度值不统一」）：
`Row.alignItems` 只接受 `VerticalAlign`(Top/Center/Bottom)，**没有 Stretch**，
所以同排里内容少的单元格只按自身内容高度绘制，背景色与底边框只覆盖自身高度。
修法是改用 `Flex({ direction: FlexDirection.Row, alignItems: ItemAlign.Stretch })`，
让单元格在交叉轴拉伸到行高（`ItemAlign.Stretch` 是唯一支持拉伸的枚举）。

注意：**不要给单元格加 `height('100%')`**。在 `Scroll > Column > Flex` 这种
高度不确定的上下文里，`height('100%')` 会把单元格撑到容器全高（实测 1831px），
比不加更糟——拉伸交给 `ItemAlign.Stretch` 即可。

判定口径：同一行内所有单元格的高度必须两两相等（容差 0px）；
宽度也应相等（表格列宽固定 148vp）。
"""
import json
import re
import sys


def bounds_of(node):
    raw = node.get('attributes', {}).get('bounds', '') or ''
    nums = re.findall(r'-?\d+', raw)
    return tuple(map(int, nums)) if len(nums) == 4 else None


def collect_cells(tree):
    """单元格 = 父节点是 Flex（表格行）的 Column。"""
    cells = []

    def walk(node, parent_type):
        attrs = node.get('attributes', {})
        node_type = attrs.get('type', '') or ''
        box = bounds_of(node)
        if node_type == 'Column' and parent_type == 'Flex' and box is not None:
            cells.append(box)
        for child in node.get('children', []):
            walk(child, node_type)

    walk(tree, '')
    return cells


def main():
    if len(sys.argv) < 2:
        print(__doc__)
        return 2
    tree = json.load(open(sys.argv[1], encoding='utf-8'))
    cells = collect_cells(tree)
    if not cells:
        print('未找到表格单元格（父为 Flex 的 Column）。请确认表格已滚到可见后重新 dump。')
        return 2

    rows = {}
    for x0, y0, x1, y1 in cells:
        rows.setdefault(y0, []).append((x1 - x0, y1 - y0))

    print(f'{sys.argv[1]}  单元格 {len(cells)} 个，分 {len(rows)} 行\n')
    print(f"{'行 y0':>7} {'格数':>4} {'宽度':>22} {'高度':>22}  结论")
    bad = 0
    for y0 in sorted(rows):
        sizes = rows[y0]
        widths = sorted({w for w, _ in sizes})
        heights = sorted({h for _, h in sizes})
        ok = len(widths) == 1 and len(heights) == 1
        if not ok:
            bad += 1
        print(f'{y0:>7} {len(sizes):>4} {str(widths):>22} {str(heights):>22}  '
              f'{"✅ 等高" if ok else "❌ 不等高"}')

    print(f'\n判定：{len(rows) - bad}/{len(rows)} 行等高')
    return 1 if bad else 0


if __name__ == '__main__':
    sys.exit(main())
