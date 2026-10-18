/*
 * logic/Capabilities2.ets 的回归用例（P2-8 工具与技能）。
 *
 * 关键点：
 * - 宿主 `skills-get` 只允许 `userInvocable` 的技能，判断错会点了报错；
 * - 插件开关的可操作性由「主机是否只读」+「宿主 readOnlyReason」共同决定；
 * - bundle 未安装时不能切换。
 *
 * 规则来源：宿主 `src/mobile/management.js`（skills / plugin / bundle 映射）。
 * 直接运行：node entry/src/test/run.mjs
 */
import assert from 'node:assert/strict';
import {
  bundleStatus, canOpenSkill, canToggleBundle, canTogglePlugin, describeInvocation,
  describeSkillBadge, groupSkills, pluginLabel, pluginStatus, readOnlyNotice, skillsEmptyText,
  sourceLabel
} from '../main/ets/logic/Capabilities2.ets';

const tests = [];
function test(name, fn) {
  tests.push({ name, fn });
}

test('来源展示名', () => {
  assert.equal(sourceLabel('runtime'), '运行时');
  assert.equal(sourceLabel('workspace'), '工作区');
  assert.equal(sourceLabel('bundled'), '内置');
  assert.equal(sourceLabel(''), '其它');
  assert.equal(sourceLabel(undefined), '其它');
  assert.equal(sourceLabel('custom-src'), 'custom-src'); // 未收录原样显示
});

test('按来源分组且保持顺序', () => {
  const groups = groupSkills([
    { name: 'a', source: 'workspace' },
    { name: 'b', source: 'runtime' },
    { name: 'c', source: 'workspace' }
  ]);
  assert.equal(groups.length, 2);
  assert.equal(groups[0].source, '工作区');
  assert.equal(groups[0].skills.length, 2);
  assert.equal(groups[1].source, '运行时');
});

test('分组：空输入不崩', () => {
  assert.equal(groupSkills(undefined).length, 0);
  assert.equal(groupSkills([]).length, 0);
});

test('能否查看全文：只认 userInvocable', () => {
  assert.equal(canOpenSkill({ name: 'a', invocation: { userInvocable: true } }), true);
  assert.equal(canOpenSkill({ name: 'a', invocation: { modelInvocable: true } }), false);
  assert.equal(canOpenSkill({ name: 'a', invocation: {} }), false);
  assert.equal(canOpenSkill({ name: 'a' }), false);
});

test('调用方式文案', () => {
  assert.equal(describeInvocation({ name: 'a', invocation: { modelInvocable: true, userInvocable: true } }), '模型与用户都可调用');
  assert.equal(describeInvocation({ name: 'a', invocation: { modelInvocable: true } }), '仅模型可调用');
  assert.equal(describeInvocation({ name: 'a', invocation: { userInvocable: true } }), '仅用户点名');
  assert.equal(describeInvocation({ name: 'a' }), '不可调用');
});

test('不可查看的徽标', () => {
  assert.equal(describeSkillBadge({ name: 'a', invocation: { userInvocable: true } }), '');
  assert.equal(describeSkillBadge({ name: 'a', invocation: { modelInvocable: true } }), '不可查看');
});

test('技能空态文案区分「服务未开」与「确实没有」', () => {
  assert.equal(skillsEmptyText({ available: false, skills: [] }), '主机未启用技能服务。');
  assert.equal(skillsEmptyText({ available: true, skills: [] }), '没有可用的技能。');
});

test('插件可切换判断', () => {
  assert.equal(canTogglePlugin({ entryId: 'a', enabled: true }, true), true);
  assert.equal(canTogglePlugin({ entryId: 'a', enabled: true }, false), false);
  assert.equal(canTogglePlugin({ entryId: 'a', readOnlyReason: 'mobile-required' }, true), false);
  assert.equal(canTogglePlugin({ entryId: 'a', readOnlyReason: '' }, true), true);
});

test('插件包可切换判断：未安装/锁定都不行', () => {
  assert.equal(canToggleBundle({ name: 'b', installed: true, enabled: true }, true), true);
  assert.equal(canToggleBundle({ name: 'b', installed: false, enabled: false }, true), false);
  assert.equal(canToggleBundle({ name: 'b', installed: true, readOnlyReason: 'x' }, true), false);
  assert.equal(canToggleBundle({ name: 'b', installed: true }, false), false);
});

test('插件显示名与状态', () => {
  assert.equal(pluginLabel({ entryId: 'e1', moduleName: 'ds-bot' }), 'ds-bot');
  assert.equal(pluginLabel({ entryId: 'e1' }), 'e1');
  assert.equal(pluginStatus({ entryId: 'e1', enabled: true }), '已启用');
  assert.equal(pluginStatus({ entryId: 'e1', enabled: false }), '已停用');
  assert.equal(pluginStatus({ entryId: 'e1', readOnlyReason: 'mobile-required' }), '手机连接必需，不可修改');
  assert.equal(pluginStatus({ entryId: 'e1', readOnlyReason: 'other' }), '主机保护，不可修改');
});

test('插件包状态', () => {
  assert.equal(bundleStatus({ name: 'b', installed: true, enabled: true }), '已启用');
  assert.equal(bundleStatus({ name: 'b', installed: true, enabled: false }), '已停用');
  assert.equal(bundleStatus({ name: 'b', installed: false }), '未安装');
  assert.equal(bundleStatus({ name: 'b', readOnlyReason: 'x' }), '主机保护，不可修改');
});

test('只读提示', () => {
  assert.equal(readOnlyNotice(false), '主机处于只读状态，插件不能修改。');
  assert.equal(readOnlyNotice(true), '');
  assert.equal(readOnlyNotice(undefined), '');
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
