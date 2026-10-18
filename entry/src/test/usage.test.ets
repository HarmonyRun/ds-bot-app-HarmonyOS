/*
 * logic/Usage.ets 的回归用例（P2-2 用量面板）。
 *
 * 主机把用量压成扁平行：
 *   rows[i] = [hour, ownerIndex, modelIndex, kindIndex, input, cacheRead, cacheWrite, output, calls]
 *
 * 这里的索引一旦理解错（比如把 cacheRead 当成 output），面板上所有数字都会错，
 * 而且看起来"很像对的"。所以必须用测试锁死列含义与窗口裁剪。
 *
 * 直接运行：node entry/src/test/run.mjs
 */
import assert from 'node:assert/strict';
import { barRatio, formatTokens, summarizeUsage, windowHours } from '../main/ets/logic/Usage.ets';

const tests = [];
function test(name, fn) {
  tests.push({ name, fn });
}

/** 造一份最小可用数据：2 个归属者、2 个模型。 */
function samplePage() {
  return {
    owners: [{ owner: 'bot-a', name: 'Chief' }, { owner: 'bot-b', name: 'Searcher' }],
    models: [{ model: 'gpt-x', name: 'GPT-X' }, { model: 'gpt-y', name: 'GPT-Y' }],
    kinds: ['turn'],
    now: 1000,
    rows: [
      // hour, owner, model, kind, input, cacheRead, cacheWrite, output, calls
      [999, 0, 0, 0, 100, 10, 5, 50, 2],
      [998, 1, 1, 0, 200, 20, 10, 100, 3],
      // 超出 24h 窗口（now=1000，窗口 24h → cutoff=976）
      [900, 0, 0, 0, 9999, 9999, 9999, 9999, 99]
    ]
  };
}

test('列含义正确：input/cacheRead/cacheWrite/output/calls 各归各位', () => {
  const s = summarizeUsage(samplePage(), '24h');
  // 窗口内：100+200 input，10+20 cacheRead，5+10 cacheWrite，50+100 output，2+3 calls
  assert.equal(s.input, 300);
  assert.equal(s.cacheRead, 30);
  assert.equal(s.cacheWrite, 15);
  assert.equal(s.output, 150);
  assert.equal(s.calls, 5);
  // total 只算 input+output（不含缓存）
  assert.equal(s.total, 450);
});

test('24h 窗口会裁掉过期行', () => {
  const s = summarizeUsage(samplePage(), '24h');
  assert.equal(s.calls, 5); // 不是 104
  const all = summarizeUsage(samplePage(), 'all');
  assert.equal(all.calls, 104);
  assert.equal(all.input, 300 + 9999);
});

test('按归属者聚合且按 total 降序', () => {
  const s = summarizeUsage(samplePage(), '24h');
  assert.equal(s.owners.length, 2);
  // Searcher: 200+100=300；Chief: 100+50=150
  assert.equal(s.owners[0].name, 'Searcher');
  assert.equal(s.owners[0].total, 300);
  assert.equal(s.owners[1].name, 'Chief');
  assert.equal(s.owners[1].total, 150);
});

test('按模型聚合且按 total 降序', () => {
  const s = summarizeUsage(samplePage(), '24h');
  assert.equal(s.models.length, 2);
  assert.equal(s.models[0].name, 'GPT-Y');
  assert.equal(s.models[0].total, 300);
  assert.equal(s.models[1].name, 'GPT-X');
});

test('空数据不崩、不显示 undefined', () => {
  assert.equal(summarizeUsage({}, '24h').empty, true);
  assert.equal(summarizeUsage({ rows: [] }, '24h').empty, true);
  assert.equal(summarizeUsage({ rows: undefined }, '24h').owners.length, 0);
});

test('字典缺失时用稳定占位而不是 undefined', () => {
  const s = summarizeUsage({ rows: [[999, 0, 0, 0, 10, 0, 0, 5, 1]], now: 1000 }, '24h');
  assert.equal(s.owners[0].name, '未归属');
  assert.equal(s.models[0].name, '未知模型');
});

test('残缺行被跳过而不是算成 NaN', () => {
  const page = { rows: [[999, 0, 0, 0, 10], [999, 0, 0, 0, 20, 0, 0, 10, 1]], now: 1000, owners: [], models: [] };
  const s = summarizeUsage(page, '24h');
  assert.equal(s.input, 20);
  assert.equal(s.calls, 1);
  assert.equal(s.empty, false);
});

test('行里有非数字时按 0 处理', () => {
  // 用类型断言把「坏值」塞进 number 列，模拟主机返回残缺数据；
  // 直接写字面量会让 tsc 报 TS2345，把整个测试run 拦下来。
  const bad = 'bad' as unknown as number;
  const missing = null as unknown as number;
  const page = {
    rows: [[999, 0, 0, 0, bad, missing, undefined as unknown as number, 10, 1]],
    now: 1000, owners: [], models: []
  };
  const s = summarizeUsage(page, '24h');
  assert.equal(s.input, 0);
  assert.equal(s.output, 10);
  assert.equal(s.calls, 1);
});

test('没有 now 时不裁剪（保守统计全部）', () => {
  const page = { rows: [[1, 0, 0, 0, 10, 0, 0, 5, 1]], owners: [], models: [] };
  assert.equal(summarizeUsage(page, '24h').calls, 1);
});

test('窗口小时数换算', () => {
  assert.equal(windowHours('24h'), 24);
  assert.equal(windowHours('7d'), 168);
  assert.equal(windowHours('30d'), 720);
  assert.equal(windowHours('all'), 0);
});

test('token 格式化', () => {
  assert.equal(formatTokens(0), '0');
  assert.equal(formatTokens(999), '999');
  assert.equal(formatTokens(1500), '1.5k');
  assert.equal(formatTokens(2500000), '2.5M');
});

test('条形图比例不越界', () => {
  assert.equal(barRatio(5, 10), 0.5);
  assert.equal(barRatio(20, 10), 1);
  assert.equal(barRatio(5, 0), 0);
});

// ---- 运行器 ----
const passed = [];
const failed = [];
for (const { name, fn } of tests) {
  try {
    fn();
    passed.push(name);
    console.log(`  ✓ ${name}`);
  } catch (error) {
    failed.push(name);
    console.log(`  ✗ ${name}`);
    console.log(`     ${error.message}`);
  }
}
console.log(`\n${passed.length} passed / ${failed.length} failed`);
if (failed.length > 0) process.exitCode = 1;
export { tests };
