#!/usr/bin/env node
/**
 * 纯函数测试执行器。
 *
 * 背景：ArkTS 的 `.ets` 文件不能直接被 Node 执行，但协议层（`logic/Merge.ets`、`model/Models.ets`）
 * 的逻辑是纯 JavaScript 语义。本脚本：
 *   1. 把被测 `.ets` 复制成 `.ts`，并把 `from '...Foo.ets'` 改写成 `from './Foo'`；
 *   2. 用 DevEco 自带的 typescript 编译器（`tsc`）擦除类型并输出 `.mjs`；
 *   3. 让 Node 执行 `entry/src/test/*.test.ets` 里的断言。
 *
 * 用法：
 *   node entry/src/test/run.mjs          # 运行全部测试
 *   VERBOSE=1 node entry/src/test/run.mjs  # 失败时打印堆栈
 *
 * 设计约束：
 * - **只读**项目源码；所有中间产物写在 `entry/.preview/arktest/`（已被 .gitignore 忽略）。
 * - 不引入 npm 依赖：使用 DevEco Studio 自带的 TypeScript（hvigor 的 node_modules 里）。
 *   若本机 DevEco 路径不同，设置环境变量 `TSC` 指向任意 `tsc.js`。
 */
import { cpSync, mkdirSync, readFileSync, writeFileSync, readdirSync, rmSync, existsSync } from 'node:fs';
import { dirname, join, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';
import { execFileSync } from 'node:child_process';

const here = dirname(fileURLToPath(import.meta.url));
const root = resolve(here, '../../..');                 // 项目根
const work = join(root, 'entry/.preview/arktest');
const srcDir = join(work, 'src');
const outDir = join(work, 'out');
const tsc = process.env.TSC ??
  '/Applications/DevEco-Studio.app/Contents/tools/hvigor/hvigor/node_modules/typescript/lib/tsc.js';

if (!existsSync(tsc)) {
  console.error(`找不到 TypeScript 编译器：${tsc}\n请用环境变量 TSC 指定 tsc.js 的绝对路径。`);
  process.exit(1);
}

rmSync(work, { recursive: true, force: true });
mkdirSync(srcDir, { recursive: true });
mkdirSync(outDir, { recursive: true });

/** 需要参与编译的源码模块（相对项目根）。按需增补。 */
/**
 * 被测源码。键 = 项目内路径，值 = 在临时 src 目录里的相对输出路径
 * （必须保持 `Merge.ets` 里 `from '../model/Models'` 的相对关系）。
 */
const modules = [
  ['entry/src/main/ets/model/Models.ets', 'model/Models.ts'],
  ['entry/src/main/ets/logic/Merge.ets', 'logic/Merge.ts'],
  ['entry/src/main/ets/logic/Markdown.ets', 'logic/Markdown.ts'],
  ['entry/src/main/ets/logic/Composer.ets', 'logic/Composer.ts'],
  ['entry/src/main/ets/logic/Questions.ets', 'logic/Questions.ts'],
  ['entry/src/main/ets/logic/GroupProgress.ets', 'logic/GroupProgress.ts'],
  ['entry/src/main/ets/logic/Efforts.ets', 'logic/Efforts.ts'],
  ['entry/src/main/ets/logic/ConversationAvatar.ets', 'logic/ConversationAvatar.ts'],
  ['entry/src/main/ets/logic/ViewUtil.ets', 'logic/ViewUtil.ts'],
  ['entry/src/main/ets/logic/CredentialCodec.ets', 'logic/CredentialCodec.ts'],
  ['entry/src/main/ets/logic/Usage.ets', 'logic/Usage.ts'],
  ['entry/src/main/ets/logic/Schedules.ets', 'logic/Schedules.ts'],
  ['entry/src/main/ets/logic/Memory.ets', 'logic/Memory.ts'],
  ['entry/src/main/ets/logic/Rooms.ets', 'logic/Rooms.ts'],
  ['entry/src/main/ets/logic/Bots.ets', 'logic/Bots.ts'],
  ['entry/src/main/ets/logic/Capabilities2.ets', 'logic/Capabilities2.ts'],
  ['entry/src/main/ets/logic/Export.ets', 'logic/Export.ts'],
  ['entry/src/main/ets/logic/Agents.ets', 'logic/Agents.ts'],
  ['entry/src/main/ets/logic/Connectors.ets', 'logic/Connectors.ts'],
  ['entry/src/main/ets/logic/Notifications.ets', 'logic/Notifications.ts'],
  ['entry/src/main/ets/logic/Attachments.ets', 'logic/Attachments.ts'],
  ['entry/src/main/ets/service/Projection.ets', 'service/Projection.ts'],
  ['entry/src/main/ets/service/Wire.ets', 'service/Wire.ts'],
  ['entry/src/main/ets/view/AvatarData.ets', 'view/AvatarData.ts']
];
// 注意：AvatarData.ets 由队友创建；若文件尚不存在，删掉上面这一行即可。
const testFiles = readdirSync(join(root, 'entry/src/test')).filter(name => name.endsWith('.test.ets'));

/** 把 `.ets` 复制成 `.ts`，并把 `from '.../Foo.ets'` 改成 `from './Foo'`。 */
function prepare(from, toName, options = {}) {
  const source = readFileSync(join(root, from), 'utf8');
  let text = source.replace(/from\s+['"]([^'"]+)\.ets['"]/g, (_, spec) => `from '${spec}'`);
  if (options.rewriteProjectPaths) {
    // 测试文件写在 entry/src/test 下，import 路径是相对项目根的 `../main/ets/...`；
    // 临时目录里被测模块位于 `logic/`、`model/`，这里做等价改写。
    text = text.replace(/from\s+['"]\.\.\/main\/ets\/logic\/([\w$]+)['"]/g, "from '../logic/$1'");
    text = text.replace(/from\s+['"]\.\.\/main\/ets\/model\/([\w$]+)['"]/g, "from '../model/$1'");
    text = text.replace(/from\s+['"]\.\.\/main\/ets\/view\/([\w$]+)['"]/g, "from '../view/$1'");
    text = text.replace(/from\s+['"]\.\.\/main\/ets\/service\/([\w$]+)['"]/g, "from '../service/$1'");
  }
  const destination = join(srcDir, toName);
  mkdirSync(dirname(destination), { recursive: true });
  writeFileSync(destination, text);
  return toName;
}

console.log('准备源码：');
for (const [from, to] of modules) {
  if (!existsSync(join(root, from))) {
    // 可选模块：文件还没建好时跳过（例如并行开发中的新模块），不阻塞已有测试。
    console.log(`  · 跳过（文件不存在）：${from}`);
    continue;
  }
  prepare(from, to);
  console.log(`  ↻ ${from} → .preview/arktest/src/${to}`);
}
for (const test of testFiles) {
  const to = `test/${test.replace(/\.ets$/, '.ts')}`;
  prepare(`entry/src/test/${test}`, to, { rewriteProjectPaths: true });
  console.log(`  ↻ entry/src/test/${test} → .preview/arktest/src/${to}`);
}

const tsFiles = [];
(function walk(dir) {
  for (const entry of readdirSync(dir, { withFileTypes: true })) {
    const full = join(dir, entry.name);
    if (entry.isDirectory()) walk(full);
    else if (entry.name.endsWith('.ts')) tsFiles.push(full);
  }
})(srcDir);
console.log(`\n用 tsc 擦除类型（${tsFiles.length} 个文件）…`);
try {
  execFileSync(process.execPath, [
    tsc, ...tsFiles,
    '--module', 'esnext', '--target', 'es2022', '--moduleResolution', 'node',
    '--skipLibCheck', '--noEmitOnError', 'false', '--outDir', outDir,
    '--rootDir', srcDir
  ], { stdio: ['ignore', 'pipe', 'pipe'], cwd: srcDir });
} catch (error) {
  // 测试文件用 node:assert / process，没有 @types/node 时会有 TS2307/TS2580 诊断，
  // 但 `--noEmitOnError false` 仍会产出可用 JS。只有产物缺失才算真失败。
  const diagnostics = `${error.stdout ?? ''}${error.stderr ?? ''}`;
  const blocking = diagnostics.split('\n').filter(line => line.trim() && !/TS2307|TS2580|TS2345/.test(line));
  if (blocking.length > 0) {
    console.error('tsc 失败：');
    console.error(diagnostics);
    process.exit(1);
  }
}

// tsc 会把所有输出平铺到 outDir；Node 需要 .mjs 扩展名才能按 ESM 运行。
(function rename(dir) {
  for (const entry of readdirSync(dir, { withFileTypes: true })) {
    const full = join(dir, entry.name);
    if (entry.isDirectory()) { rename(full); continue; }
    if (!entry.name.endsWith('.js')) continue;
    // Node ESM 要求相对导入带扩展名；tsc 不会补，这里补上 .mjs。
    const content = readFileSync(full, 'utf8')
      .replace(/from\s+(['"])(\.\.?\/[^'"]+)\1/g, (match, quote, spec) =>
        spec.endsWith('.mjs') ? match : `from ${quote}${spec}.mjs${quote}`);
    writeFileSync(full.replace(/\.js$/, '.mjs'), content);
    rmSync(full);
  }
})(outDir);

console.log(`\n运行 ${testFiles.length} 个测试文件…\n`);
let failed = false;
for (const test of testFiles) {
  const modulePath = join(outDir, 'test', test.replace(/\.ets$/, '.mjs'));
  try {
    await import(`file://${modulePath}`);
  } catch (error) {
    failed = true;
    console.error(` ✗ ${test} 执行失败：${error.message}`);
    if (process.env.VERBOSE) console.error(error.stack);
  }
}
process.exit(failed ? 1 : 0);
