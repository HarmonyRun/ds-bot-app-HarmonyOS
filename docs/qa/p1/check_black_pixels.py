#!/usr/bin/env python3
"""
量化验收脚本：统计指定区域内的「近黑像素」数量（头像黑边回归检查）。

用法：
    python3 docs/qa/p1/check_black_pixels.py <截图> [x0,y0,x1,y1[:标签]] ...

不带区域时只打印图片尺寸并给出提示；带区域时逐区域统计。

为什么要显式给区域（而不是自动分块）：
第一版用「扫描非背景像素并聚块」自动找头像，结果把标题栏的文字与深色图标一起框了进来，
得出「1.60% 近黑 → 有黑边」的**错误结论**。头像是否干净必须用精确区域来量；
区域从哪里来？用 `hdc shell "uitest dumpLayout"` 拿到节点 bounds 后填进来。

示例（坐标需按实际 dump 调整）：
    python3 docs/qa/p1/check_black_pixels.py docs/qa/p1/realdevice-home.jpeg \
        "70,990,240,1160:Chief 头像" "70,1320,240,1490:Searcher 头像"

口径：RGB 三通道都 < 40 视为近黑（容忍 JPEG 压缩与抗锯齿边缘）。
参考值（2026-10-15 模拟器修复后）：三个头像区域均为 0 近黑像素。
"""
import sys
from PIL import Image

NEAR_BLACK = 40


def parse_region(spec):
    if ':' in spec:
        coords, label = spec.split(':', 1)
    else:
        coords, label = spec, '区域'
    parts = [int(v) for v in coords.split(',')]
    if len(parts) != 4:
        raise ValueError(f'区域格式应为 x0,y0,x1,y1: {spec}')
    return parts, label


def count_black(im, box):
    crop = im.crop(box)
    total = black = 0
    for p in crop.getdata():
        total += 1
        if p[0] < NEAR_BLACK and p[1] < NEAR_BLACK and p[2] < NEAR_BLACK:
            black += 1
    return black, total


def main():
    if len(sys.argv) < 2:
        print(__doc__)
        return 2
    path = sys.argv[1]
    im = Image.open(path).convert('RGB')
    print(f'\n{path}  尺寸 {im.size[0]}x{im.size[1]}')
    specs = sys.argv[2:]
    if not specs:
        print('未指定区域；请用 uitest dumpLayout 取节点 bounds 后按 "x0,y0,x1,y1:标签" 传入。')
        return 0
    print(f"{'区域':<24} {'近黑像素':>9} {'总像素':>9} {'占比':>8}  结论")
    verdict_bad = 0
    for spec in specs:
        box, label = parse_region(spec)
        black, total = count_black(im, box)
        pct = 100.0 * black / total if total else 0.0
        ok = pct < 0.5
        if not ok:
            verdict_bad += 1
        print(f'{label:<24} {black:>9} {total:>9} {pct:>7.2f}%  {"干净" if ok else "疑似有黑边/深色元素"}')
    print(f'\n判定：{len(specs) - verdict_bad}/{len(specs)} 个区域通过（近黑占比 < 0.5%）')
    return 0 if verdict_bad == 0 else 1


if __name__ == '__main__':
    sys.exit(main())
