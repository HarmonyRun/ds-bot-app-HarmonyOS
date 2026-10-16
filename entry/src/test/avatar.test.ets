/*
 * AvatarData.ets 的纯函数测试（BotAvatarView 的矢量头像数据层）。
 *
 * 执行方式（与 logic.test.ets 同一个执行器，但走的是另一条路径映射）：
 *     node entry/src/test/run.mjs
 *     VERBOSE=1 node entry/src/test/run.mjs     # 失败时打印堆栈
 *
 * run.mjs 需要两条映射才能跑到本文件（已由 Lead 补上）：
 *   1. modules 里加 `['entry/src/main/ets/view/AvatarData.ets', 'view/AvatarData.ts']`
 *      （否则 `../main/ets/view/AvatarData.ets` 在临时目录里找不到，测试文件会执行失败）；
 *   2. rewriteProjectPaths 里加 `../main/ets/view/X` → `../view/X`。
 * 如果以后报 "Cannot find module .../view/AvatarData.mjs"，就是这两条之一丢了。
 *
 * 为什么测的是 AvatarData 而不是 BotAvatarView：`BotAvatarView.ets` 里有 `@Component`
 * 装饰器与 ArkUI 组件，Node 无法整体导入；纯逻辑（形状/颜色归一化、颜色查表、路径数值缩放）
 * 全部放在不依赖 ArkUI 的 `AvatarData.ets` 里，这里只导入它。
 *
 * 数据来源：本文件用 node:fs 直接读 `entry/src/main/resources/rawfile/characters.json`
 * （ArkUI 的 resourceManager 在 Node 里不可用），再用被测的 `parseAvatarCatalog` 解析后
 * 通过 `setAvatarCatalog` 注入，因此解析路径本身也被覆盖。
 *
 * 本文件保持「纯 JavaScript 语义」：无类型注解，只有 ESM import/export、函数与对象字面量。
 *
 * 约定的缺省回退（写死在 AvatarData.ets）：
 *   - 空 / 未知 shape → 'gumdrop'
 *   - 空 / 未知 color → 'blue'（= inks.blue = ['#2A92FE', '#0E74E0']）
 */

import assert from 'node:assert/strict';
import { existsSync, readFileSync } from 'node:fs';
import { dirname, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';
import {
  avatarColors,
  normalizeColor,
  normalizeShape,
  parseAvatarCatalog,
  scalePathCommands,
  setAvatarCatalog,
  shapePath
} from '../main/ets/view/AvatarData.ets';

const tests = [];
function test(name, fn) {
  tests.push({ name, fn });
}

/** 测试运行在 entry/.preview/arktest/out/test/ 下，产出物所在位置决定相对路径。 */
function charactersJsonPath() {
  const here = dirname(fileURLToPath(import.meta.url));
  const candidates = [
    resolve(here, '../../../../src/main/resources/rawfile/characters.json'),
    resolve(process.cwd(), 'entry/src/main/resources/rawfile/characters.json')
  ];
  for (const candidate of candidates) {
    if (existsSync(candidate)) return candidate;
  }
  throw new Error('找不到 characters.json，尝试过：' + candidates.join(' | '));
}

const catalog = parseAvatarCatalog(readFileSync(charactersJsonPath(), 'utf8'));
setAvatarCatalog(catalog);

/** 从 path 命令里取出所有数字 token（与 AvatarData 的扫描规则等价）。 */
function numbers(text) {
  const matched = text.match(/[-+]?(?:\d+\.?\d*|\.\d+)/g);
  return matched === null ? [] : matched.map((token) => Number(token));
}

/** 只保留命令字母，用来断言缩放不改动命令结构。 */
function letters(text) {
  return text.replace(/[^A-Za-z]/g, '');
}

/** 每个角色的 3 条主路径 + paints 路径。 */
function allShapePaths() {
  const out = [];
  for (const name of catalog.shapes) {
    const character = catalog.characters[name];
    out.push([`${name}.body`, character.body]);
    out.push([`${name}.shade`, character.shade]);
    out.push([`${name}.light`, character.light]);
    const paints = character.paints === undefined ? [] : character.paints;
    for (let i = 0; i < paints.length; i += 1) out.push([`${name}.paint${i}`, String(paints[i][0])]);
  }
  return out;
}

// 1. 数据规模：20 形状 / 12 颜色 / 19 套 ink（与上游 characterData.json 一致）。
test('catalog keeps 20 shapes, 12 colors and 19 inks', () => {
  assert.equal(catalog.shapes.length, 20);
  assert.equal(catalog.colors.length, 12);
  assert.equal(Object.keys(catalog.characters).length, 20);
  assert.equal(Object.keys(catalog.inks).length, 19);
  for (const name of catalog.shapes) {
    assert.notEqual(catalog.characters[name], undefined, `缺少角色 ${name}`);
  }
});

// 2. 20 个 shape 都能取到 body/shade/light 与 2 只眼睛。
test('every shape resolves to body/shade/light and 2 eyes', () => {
  for (const name of catalog.shapes) {
    const paths = shapePath(name, 1);
    assert.equal(paths.shape, name);
    assert.ok(paths.body.length > 0, `${name} body 为空`);
    assert.ok(paths.shade.length > 0, `${name} shade 为空`);
    assert.ok(paths.light.length > 0, `${name} light 为空`);
    assert.equal(paths.eyes.length, 2, `${name} 眼睛不是 2 个`);
    assert.equal(paths.body, catalog.characters[name].body, `${name} body 未原样返回`);
  }
});

// 3. 12 个 color 都能取到合法的 [主色, 深色] 二元组，且与 inks 完全一致。
test('every color resolves to a valid #RRGGBB pair', () => {
  const hex = /^#[0-9a-f]{6}$/i;
  for (const name of catalog.colors) {
    const ink = catalog.inks[name];
    assert.equal(ink.length, 2, `${name} 不是二元组`);
    const pair = avatarColors(name);
    assert.ok(hex.test(pair.main), `${name} 主色非法：${pair.main}`);
    assert.ok(hex.test(pair.dark), `${name} 深色非法：${pair.dark}`);
    assert.equal(pair.main, ink[0]);
    assert.equal(pair.dark, ink[1]);
  }
  // 19 套 ink 全部必须是合法的 #RRGGBB 二元组（含 deepseek/charcoal 等额外项）。
  for (const key of Object.keys(catalog.inks)) {
    const ink = catalog.inks[key];
    assert.equal(ink.length, 2, `${key} 不是二元组`);
    assert.ok(hex.test(ink[0]) && hex.test(ink[1]), `${key} 颜色非法：${ink.join(',')}`);
  }
});

// 4. 未知 / 空 shape 回退 gumdrop，未知 / 空 color 回退 blue。
test('unknown shape falls back to gumdrop, unknown color to blue', () => {
  assert.equal(normalizeShape(''), 'gumdrop');
  assert.equal(normalizeShape('not-a-shape'), 'gumdrop');
  assert.equal(normalizeShape('whale'), 'whale');
  assert.equal(normalizeColor(''), 'blue');
  assert.equal(normalizeColor('not-a-color'), 'blue');
  assert.equal(normalizeColor('red'), 'red');

  const fallback = shapePath('not-a-shape', 1);
  assert.equal(fallback.shape, 'gumdrop');
  assert.equal(fallback.body, catalog.characters.gumdrop.body);
  assert.equal(fallback.eyes.length, 2);

  const pair = avatarColors('not-a-color');
  assert.equal(pair.main, catalog.inks.blue[0]);
  assert.equal(pair.dark, catalog.inks.blue[1]);
  // 空字符串也必须安全（接线时可能传 '')。
  assert.equal(shapePath('', 1).shape, 'gumdrop');
  assert.equal(avatarColors('').main, catalog.inks.blue[0]);
});

// 5. 额外 ink（deepseek/charcoal/graphite/rose/sky/tangerine/cobalt）也认。
test('extra ink names outside the 12 colors are still accepted', () => {
  const extras = Object.keys(catalog.inks).filter((key) => catalog.colors.indexOf(key) < 0);
  assert.equal(extras.length, 7);
  for (const key of extras) {
    assert.equal(normalizeColor(key), key);
    assert.equal(avatarColors(key).main, catalog.inks[key][0]);
  }
});

// 6. scale = 1 时逐字符原样返回（20 个角色的全部路径，含 paints）。
test('scalePathCommands is an identity at scale 1', () => {
  for (const [label, path] of allShapePaths()) {
    assert.equal(scalePathCommands(path, 1), path, `${label} 在 scale=1 时被改动了`);
  }
  assert.equal(scalePathCommands('', 0.5), '');
  assert.equal(scalePathCommands('M0 0z', 1), 'M0 0z');
});

// 7. 负号、多位小数、连续小数（`l5.1 .1`）、整数与 `.5` 这种省略整数位都要正确减半。
test('scalePathCommands halves negative, decimal and dot-leading numbers', () => {
  assert.equal(scalePathCommands('M10 20l5.1 .1-.4 -3.25z', 0.5), 'M5 10l2.55 0.05-0.2 -1.625z');
  assert.equal(scalePathCommands('M38.7 4.5l4.4-.5 .8 1.9z', 0.5), 'M19.35 2.25l2.2-0.25 0.4 0.95z');
  // 命令字母必须一个不少、一个不多，且顺序不变。
  const source = 'M1.5-2.25l.5 .25-3 4z';
  assert.equal(letters(scalePathCommands(source, 0.5)), letters(source));
  // 非有限 scale 视为不缩放。
  assert.equal(scalePathCommands(source, Number.NaN), source);
});

// 8. 缩放是逐数字线性的：数据里每条路径的所有数字都等于原值 × scale。
test('every number in every path is scaled linearly', () => {
  for (const scale of [0.36, 0.5, 2, 0.01]) {
    for (const [label, path] of allShapePaths()) {
      const scaled = scalePathCommands(path, scale);
      const before = numbers(path);
      const after = numbers(scaled);
      assert.equal(after.length, before.length, `${label} scale=${scale} 数字个数变了`);
      assert.equal(letters(scaled), letters(path), `${label} scale=${scale} 命令字母变了`);
      for (let i = 0; i < before.length; i += 1) {
        assert.ok(
          Math.abs(after[i] - before[i] * scale) < 1e-6,
          `${label} scale=${scale} 第 ${i} 个数字：${before[i]} → ${after[i]}`
        );
      }
    }
  }
});

// 9. shapePath(name, size/100) 里眼睛的 x/y/宽/高已缩放，角度不缩放。
test('shapePath scales eye geometry but keeps the tilt angle', () => {
  for (const scale of [0.36, 0.5, 1]) {
    for (const name of catalog.shapes) {
      const raw = catalog.characters[name].eyes;
      const eyes = shapePath(name, scale).eyes;
      assert.equal(eyes.length, raw.length);
      for (let i = 0; i < raw.length; i += 1) {
        assert.ok(Math.abs(eyes[i].x - raw[i][0] * scale) < 1e-6, `${name} eye[${i}].x`);
        assert.ok(Math.abs(eyes[i].y - raw[i][1] * scale) < 1e-6, `${name} eye[${i}].y`);
        assert.ok(Math.abs(eyes[i].width - raw[i][2] * scale) < 1e-6, `${name} eye[${i}].width`);
        assert.ok(Math.abs(eyes[i].height - raw[i][3] * scale) < 1e-6, `${name} eye[${i}].height`);
        assert.equal(eyes[i].tilt, raw[i][4], `${name} eye[${i}].tilt 不应该被缩放`);
      }
    }
  }
});

// 10. 每个角色的 eyes 都是 2 × 5 个有限数值（x, y, 宽, 高, 角度），宽高为正。
test('every character has 2 eyes of 5 finite numbers each', () => {
  for (const name of catalog.shapes) {
    const eyes = catalog.characters[name].eyes;
    assert.equal(eyes.length, 2, `${name} 眼睛个数不是 2`);
    for (let i = 0; i < eyes.length; i += 1) {
      assert.equal(eyes[i].length, 5, `${name} eye[${i}] 不是 5 个数值`);
      for (const value of eyes[i]) {
        assert.equal(typeof value, 'number', `${name} eye[${i}] 含非数值`);
        assert.ok(Number.isFinite(value), `${name} eye[${i}] 含非有限值`);
      }
      assert.ok(eyes[i][2] > 0 && eyes[i][3] > 0, `${name} eye[${i}] 宽高必须为正`);
    }
  }
});

// 11. paints 只在 whale/moon/wave/zed 上出现，且 path 缩放、颜色/不透明度原样保留。
test('paints are carried over and scaled', () => {
  const withPaints = catalog.shapes.filter((name) => catalog.characters[name].paints !== undefined);
  assert.deepEqual(withPaints.sort(), ['moon', 'wave', 'whale', 'zed']);
  for (const name of withPaints) {
    const raw = catalog.characters[name].paints;
    const paints = shapePath(name, 0.5).paints;
    assert.equal(paints.length, raw.length);
    for (let i = 0; i < raw.length; i += 1) {
      assert.equal(paints[i].color, String(raw[i][1]));
      assert.equal(paints[i].opacity, Number(raw[i][2]));
      assert.equal(paints[i].path, scalePathCommands(String(raw[i][0]), 0.5));
      assert.equal(letters(paints[i].path), letters(String(raw[i][0])));
    }
  }
  const wave = shapePath('wave', 0.5).paints[0];
  assert.equal(wave.color, '#fff');
  assert.equal(wave.opacity, 0.4);
  assert.equal(shapePath('gumdrop', 0.5).paints.length, 0);
});

// 12. 路径确实是为 0 0 100 100 画布准备的：绝对坐标都落在 0..100 内。
test('absolute path coordinates stay inside the 0..100 viewBox', () => {
  for (const [label, path] of allShapePaths()) {
    // 数据里只有 M（绝对）/ l（相对）/ z，这里按 M + l 累加算绝对坐标。
    const tokens = path.match(/[A-Za-z]|[-+]?(?:\d+\.?\d*|\.\d+)/g);
    let x = 0;
    let y = 0;
    let command = '';
    let index = 0;
    while (index < tokens.length) {
      if (/^[A-Za-z]$/.test(tokens[index])) {
        command = tokens[index];
        index += 1;
        continue;
      }
      const values = [];
      while (index < tokens.length && !/^[A-Za-z]$/.test(tokens[index])) {
        values.push(Number(tokens[index]));
        index += 1;
      }
      for (let i = 0; i + 1 < values.length; i += 2) {
        if (command === 'l' || command === 'm') {
          x += values[i];
          y += values[i + 1];
        } else {
          x = values[i];
          y = values[i + 1];
        }
        assert.ok(x >= -1 && x <= 101, `${label} x=${x} 超出画布`);
        assert.ok(y >= -1 && y <= 101, `${label} y=${y} 超出画布`);
      }
    }
  }
});

let passed = 0;
const failures = [];
for (const entry of tests) {
  try {
    entry.fn();
    passed += 1;
    console.log('ok   ' + entry.name);
  } catch (error) {
    failures.push(entry);
    console.log('FAIL ' + entry.name);
    console.log('     ' + (error && error.message ? error.message : String(error)));
  }
}

console.log('');
console.log(passed + ' passed / ' + failures.length + ' failed');
if (failures.length > 0) {
  process.exitCode = 1;
}

export { tests };
