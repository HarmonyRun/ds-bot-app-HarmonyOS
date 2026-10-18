/*
 * logic/Bots.ets 的回归用例（P2-5 Bot 管理）。
 *
 * 关键点：
 * - 只提交变化字段（宿主按"字段是否出现"决定改不改）；
 * - 名字重名与长度（宿主会拒绝，提前拦下少一次往返）；
 * - **思考档位依赖模型**（宿主明确要求"先选模型再选档位"）。
 *
 * 规则来源：宿主 `src/host/roster.js updateBot`（slice 40/24、重名检查、effort 依赖 model）。
 * 直接运行：node entry/src/test/run.mjs
 */
import assert from 'node:assert/strict';
import {
  AVATAR_DATA_URL_MAX, avatarDataUrl, avatarTypeProblem, BOT_NAME_MAX, BOT_ROLE_MAX,
  buildBotPatch, describeBotSummary, formOfBot, isMainBot, nameProblem, validateBotForm
} from '../main/ets/logic/Bots.ets';

const tests = [];
function test(name, fn) {
  tests.push({ name, fn });
}

function bot(overrides = {}) {
  return Object.assign({
    id: 'bot-a', name: 'Chief', role: '总管', instructions: '先给结论',
    model: 'mock/gpt-5', effort: 'high'
  }, overrides);
}

const others = [
  { id: 'bot-a', name: 'Chief' },
  { id: 'bot-b', name: 'Searcher' }
];

test('formOfBot：缺失字段补空串', () => {
  const form = formOfBot({ id: 'bot-a', name: 'Chief' });
  assert.equal(form.role, '');
  assert.equal(form.instructions, '');
  assert.equal(form.model, '');
  assert.equal(form.effort, '');
});

test('校验：空名/超长名/超长角色', () => {
  const form = formOfBot(bot());
  assert.equal(validateBotForm(Object.assign({}, form, { name: '  ' }), others).ok, false);
  assert.equal(validateBotForm(Object.assign({}, form, { name: 'x'.repeat(BOT_NAME_MAX + 1) }), others).ok, false);
  assert.equal(validateBotForm(Object.assign({}, form, { name: 'x'.repeat(BOT_NAME_MAX) }), others).ok, true);
  assert.equal(validateBotForm(Object.assign({}, form, { role: 'x'.repeat(BOT_ROLE_MAX + 1) }), others).ok, false);
});

test('校验：重名被拒，但自己不算重名', () => {
  const form = formOfBot(bot());
  assert.equal(validateBotForm(Object.assign({}, form, { name: 'Searcher' }), others).ok, false);
  assert.equal(validateBotForm(Object.assign({}, form, { name: 'Chief' }), others).ok, true);
});

test('校验：思考档位必须有模型', () => {
  const form = formOfBot(bot());
  const noModel = Object.assign({}, form, { model: '', effort: 'high' });
  assert.equal(validateBotForm(noModel, others).ok, false);
  assert.equal(validateBotForm(noModel, others).error, '先选择模型，才能设置思考档位');
  // 都没有也可以（都跟随默认）
  assert.equal(validateBotForm(Object.assign({}, form, { model: '', effort: '' }), others).ok, true);
});

test('没有变化时不生成载荷', () => {
  const before = bot();
  assert.equal(buildBotPatch(before, formOfBot(before)), undefined);
});

test('只提交变化字段', () => {
  const before = bot();
  const form = formOfBot(before);
  form.name = '新名字';
  const patch = buildBotPatch(before, form);
  assert.equal(patch.name, '新名字');
  assert.equal(patch.role, undefined);
  assert.equal(patch.instructions, undefined);
  assert.equal(patch.model, undefined);
  assert.equal(patch.effort, undefined);
});

test('清空模型/档位用空串表示', () => {
  const before = bot();
  const form = formOfBot(before);
  form.model = '';
  form.effort = '';
  const patch = buildBotPatch(before, form);
  assert.equal(patch.model, '');
  assert.equal(patch.effort, '');
});

test('改名去首尾空格', () => {
  const before = bot();
  const form = formOfBot(before);
  form.name = '  新名字  ';
  assert.equal(buildBotPatch(before, form).name, '新名字');
});

test('摘要文案', () => {
  assert.equal(describeBotSummary(bot({ model: 'mock/gpt-5', effort: 'high' }), 'GPT-5', '高'), 'GPT-5 · 高');
  assert.equal(describeBotSummary(bot({ effort: undefined }), 'GPT-5', ''), 'GPT-5');
  // 没设置模型时显示"默认模型"
  assert.equal(describeBotSummary(bot({ model: undefined, effort: undefined }), '', ''), '默认模型');
});

test('主 Bot 判断', () => {
  assert.equal(isMainBot('bot-a', ['bot-a']), true);
  assert.equal(isMainBot('bot-b', ['bot-a']), false);
  assert.equal(isMainBot('bot-a', []), false);
});

test('nameProblem 单独校验', () => {
  assert.equal(nameProblem('', others, 'bot-a'), '名字不能为空');
  assert.equal(nameProblem('Searcher', others, 'bot-a'), '名字「Searcher」已被使用');
  assert.equal(nameProblem('Chief', others, 'bot-a'), '');
  assert.equal(nameProblem('x'.repeat(41), others, 'bot-a').includes('40'), true);
});

test('头像 data URL：类型白名单与长度上限', () => {
  const ok = avatarDataUrl('image/png', 'iVBORw0KGgo=');
  assert.equal(ok.startsWith('data:image/png;base64,'), true);
  assert.equal(avatarDataUrl('image/svg+xml', 'abc'), '');   // 宿主不支持 SVG
  assert.equal(avatarDataUrl('image/png', ''), '');
  // 超过宿主上限（160000 字符）应被拒
  const huge = 'a'.repeat(AVATAR_DATA_URL_MAX);
  assert.equal(avatarDataUrl('image/png', huge), '');
});

test('头像类型提示', () => {
  assert.equal(avatarTypeProblem('image/png'), '');
  assert.equal(avatarTypeProblem('image/bmp').includes('PNG'), true);
});

test('头像变化会进 patch，未变化不进', () => {
  const before = { id: 'bot-a', name: 'A', role: '', instructions: '', model: '', effort: '',
    avatar: { image: 'data:image/png;base64,x' } };
  const same = formOfBot(before);
  assert.equal(buildBotPatch(before, same), undefined);
  const changed = formOfBot(before);
  changed.avatarImage = 'data:image/png;base64,y';
  assert.equal(buildBotPatch(before, changed).avatarImage, 'data:image/png;base64,y');
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
