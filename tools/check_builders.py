#!/usr/bin/env python3
"""
自检：找出「看起来是 @Builder 但没被装饰」的方法。

背景：本项目里 `@Builder` 一旦丢失，编译**不一定报错**，而是在运行时
把组件当普通类调用，抛
`TypeError: class constructor cannot called without 'new'` 直接崩掉。
2026-10-17～10-18 期间因为脚本化插入/替换，这个坑反复出现 6 次。

规则：名字形如 `xxxPage` / `xxxSheet` / `xxxBuilder` / `xxxCard` / `xxxView`
且没有修饰符的 private 方法，几乎都应该有 `@Builder`。

用法：python3 tools/check_builders.py [文件...]
"""
import re
import sys
from pathlib import Path

PATTERNS = (
    'Page', 'Sheet', 'Builder', 'Card', 'View', 'Section', 'Row', 'Chip', 'Pill', 'List',
    'Body', 'Tile', 'Overlay', 'SheetBuilder', 'Slot'
)


def is_ui_file(text: str) -> bool:
    """只检查真正的 UI 文件；service/logic 里的同名方法不是 builder。"""
    return '@Component' in text or '@Entry' in text


def first_statement(lines: list[str], start: int) -> str:
    """取方法体的第一条语句（用于区分 builder 与普通方法）。"""
    probe = start + 1
    while probe < len(lines):
        text = lines[probe].strip()
        if text == '' or text.startswith('//') or text.startswith('*') or text.startswith('/*'):
            probe += 1
            continue
        return text
    return ''


def looks_like_builder(lines: list[str], start: int) -> bool:
    """
    判断方法体第一条语句是否是「渲染 UI」。

    规则：
    - 大写开头的调用 = 组件（`Column() {` / `MessageActionSheet({`）；
    - `this.xxx(...)` 只有 xxx 名字像 builder（`*Page/*Card/*Sheet/...`）才算，
      否则普通方法里调用别的普通方法会被误判（2026-10-18 的 `openBotCard()` 就是这种）。
    - 赋值 / await / return / 控制流一律不是 builder。
    """
    statement = first_statement(lines, start)
    if statement == '':
        return False
    if statement.startswith('this.') and '=' in statement.split('(')[0]:
        return False
    for keyword in ('await ', 'return ', 'const ', 'let ', 'if (', 'for (', 'try'):
        if statement.startswith(keyword):
            return False
    if re.match(r'^[A-Z]\w*\s*\(', statement):        # 组件调用
        return True
    call = re.match(r'^this\.(\w+)\s*\(', statement)  # 调用自身的 builder
    if call:
        callee = call.group(1)
        return any(callee.endswith(suffix) for suffix in PATTERNS)
    return False


def check(path: Path) -> list[str]:
    problems = []
    content = path.read_text(encoding='utf-8')
    if not is_ui_file(content):
        return problems
    lines = content.split('\n')
    for index, line in enumerate(lines):
        match = re.match(r'^  (?:private |async private |private async )?([a-zA-Z0-9_]+)\((.*)\)\s*(?::\s*\S+)?\s*\{\s*$', line)
        if not match:
            continue
        name = match.group(1)
        if not any(name.endswith(suffix) or name.startswith('private ' + suffix) for suffix in PATTERNS):
            continue
        # 往上跳过空行与注释，找最近的装饰器
        probe = index - 1
        decorated = False
        while probe >= 0:
            text = lines[probe].strip()
            if text.startswith('*') or text.startswith('/*') or text.startswith('//') or text.startswith('/**'):
                probe -= 1
                continue
            if text == '':
                probe -= 1
                continue
            decorated = text.startswith('@Builder') or text.startswith('@BuilderParam')
            break
        if not decorated and looks_like_builder(lines, index):
            problems.append(f'{path}:{index + 1}  {name}() 缺少 @Builder')
    return problems


def main() -> int:
    targets = [Path(arg) for arg in sys.argv[1:]]
    if not targets:
        root = Path(__file__).resolve().parent.parent
        targets = sorted((root / 'entry/src/main/ets').rglob('*.ets'))
    problems = []
    for target in targets:
        if target.is_file():
            problems.extend(check(target))
    if problems:
        print('发现缺少 @Builder 的方法：')
        for problem in problems:
            print('  ' + problem)
        return 1
    print('OK：未发现缺少 @Builder 的疑似 builder 方法')
    return 0


if __name__ == '__main__':
    raise SystemExit(main())
