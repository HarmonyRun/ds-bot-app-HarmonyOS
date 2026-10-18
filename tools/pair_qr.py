#!/usr/bin/env python3
"""
把配对 JSON 渲染成二维码图片，供手机「扫码连接主机」使用。

## 为什么需要它

主机端（DS Bot 桌面版）目前只在「设置 → 移动设备」里给出**配对 JSON 文本**，
不显示二维码；而手机端已支持扫码。这个脚本补上「显示」这一环：

    # 1) 从桌面版复制配对 JSON 到剪贴板后
    pbpaste | python3 tools/pair_qr.py -o /tmp/pair.png
    open /tmp/pair.png          # 在 Mac 屏幕上打开，用手机扫

    # 2) 或者直接给 JSON
    python3 tools/pair_qr.py '{"url":"...","code":"...","serverId":"..."}' -o /tmp/pair.png

二维码内容就是配对 JSON 原文，与手动粘贴完全等价，因此手机端复用同一条配对流程。

## 依赖

    pip3 install qrcode pillow

## 注意

配对 JSON 含短期配对码，属于敏感信息。不要把生成的图片提交到仓库或发到公开渠道。
"""
import argparse
import json
import sys


def main() -> int:
    parser = argparse.ArgumentParser(description='把 DS Bot 配对 JSON 渲染成二维码')
    parser.add_argument('json_text', nargs='?', help='配对 JSON（省略则从标准输入读取）')
    parser.add_argument('-o', '--output', default='/tmp/dsbot-pair-qr.png', help='输出 PNG 路径')
    parser.add_argument('--box-size', type=int, default=10, help='每个码元的像素大小')
    parser.add_argument('--border', type=int, default=4, help='静区宽度（码元数）')
    args = parser.parse_args()

    raw = args.json_text if args.json_text else sys.stdin.read()
    raw = raw.strip()
    if not raw:
        print('错误：没有收到配对 JSON', file=sys.stderr)
        return 2

    # 先校验字段，避免生成一个扫了也没用的二维码
    try:
        value = json.loads(raw)
    except json.JSONDecodeError as error:
        print(f'错误：不是合法 JSON（{error}）', file=sys.stderr)
        return 2
    for key in ('url', 'code', 'serverId'):
        if not isinstance(value.get(key), str) or not value[key].strip():
            print(f'错误：配对 JSON 缺少字段 {key}', file=sys.stderr)
            return 2

    try:
        import qrcode
    except ImportError:
        print('错误：缺少 qrcode，请先 pip3 install qrcode pillow', file=sys.stderr)
        return 2

    image = qrcode.make(raw, box_size=args.box_size, border=args.border)
    image.save(args.output)
    print(f'二维码已生成：{args.output}')
    print(f'  主机：{value["url"]}')
    print(f'  服务器 ID：{value["serverId"]}')
    print('用手机打开 DS Bot 配对页 → 扫码连接主机，对准此图即可。')
    return 0


if __name__ == '__main__':
    sys.exit(main())
