#!/usr/bin/env node
/**
 * 受控模拟主机（DS Bot `/mobile/v1`），用于手机端 UI 的**可重复**端到端验证。
 *
 * ## 为什么放进仓库
 *
 * 这个脚本此前一直放在 `/tmp` 里，被系统清理过两次（每次都要重写）。
 * 它是所有手机端功能验证的基础设施，应该跟代码一起版本化。
 *
 * ## 用法
 *
 * ```bash
 * node docs/qa/p1/mock-host.mjs questions     # 场景：questions | approvals | queue
 * # 另开一个终端，取配对 JSON 给手机扫码/粘贴
 * cat /tmp/dsbot-mock-pairing.json
 * ```
 *
 * 依赖宿主真实 TLS 证书（`~/.dsh/bot/mobile/tls/computer.crt|key`），
 * 因此手机端的 SPKI 钉扎与真实环境一致。
 *
 * ## 覆盖的协议面
 *
 * `/info` `/state` `/conversations` `/conversations/:id/messages` `/devices`
 * `/read-markers` `/pairings` `/pairings/complete` `/actions`（含 parts / earlier /
 * usage / schedules / memory / approvals / room-progress 等）以及 `/events` WebSocket。
 */
import { createServer } from 'node:https';
import { createHash, createPublicKey, randomUUID } from 'node:crypto';
import { readFileSync, writeFileSync } from 'node:fs';
import { homedir } from 'node:os';
import { join } from 'node:path';
import { URL } from 'node:url';

const PORT = Number(process.env.MOCK_PORT ?? 9443);
const SCENARIO = process.argv[2] ?? 'questions';
const CERT_DIR = join(homedir(), '.dsh/bot/mobile/tls');
const ACCESS_TOKEN = 'mock-access-' + 'a'.repeat(20);
const REFRESH_TOKEN = 'mock-refresh-' + 'b'.repeat(20);
const SERVER_ID = 'mock-server-0001';
const PAIRING_CODE = 'MOCKCODE1';

const cert = readFileSync(join(CERT_DIR, 'computer.crt'));
const key = readFileSync(join(CERT_DIR, 'computer.key'));

/**
 * TLS 钉扎值：`sha256:<hex>`，哈希对象是**公钥的 SPKI DER**（不是整张证书）。
 *
 * 格式必须与 App 侧的校验一致（`service/MobileApi.ets` 要求 `^sha256:[a-f0-9]{64}$`）。
 * 之前这里误把整张证书哈希后转 base64，导致手机端报
 * 「配对码中的电脑身份指纹无效」。
 */
const tlsPin = 'sha256:' + createHash('sha256')
  .update(createPublicKey(cert).export({ type: 'spki', format: 'der' }))
  .digest('hex');

const conversations = [
  { id: 'room-mock', kind: 'room', name: '研发小组', sessionId: 'session-mock-room', pinned: true },
  { id: 'session-mock-chief', kind: 'bot', name: 'Chief', sessionId: 'session-mock-chief', botId: 'bot-chief' },
  { id: 'session-mock-search', kind: 'bot', name: 'Searcher', sessionId: 'session-mock-search', botId: 'bot-searcher' }
];

/** 主机端头像（data URL）：用于验证「主机改了 → App 显示」这条链路 */
const hostAvatarImage = 'data:image/png;base64,' +
        'iVBORw0KGgoAAAANSUhEUgAAAGAAAABgCAIAAABt+uBvAAADNUlEQVR4nO3bTUgUcRzG8d/MzqxmYgVaQpIvhFZgRqmUWmII2Ytd' +
        'rLAXDIKILLolKOXBosPeKrEgOiQkUQpFWdGbEYIYEdqhTBAqKaMsX7B1d2Z2JwYDRXMfD4ooz+e2s8PAfuf3n51dGCW7yis0OTXE' +
        'e8RAGAMBDAQwEMBAAAMBDAQwEMBAAAMBDAQwEMBAAAMBDAQwEMBAAAMBDAQwEMBAAAMBDAQwEMBAAAMBDAQwEMBAAAMBDAQwEKDJ' +
        'lDWfXSDzSM654ansxgkCGAhgIICBAAYCGAhgIICBAAaavjvpEAo8vsdl4RNfNrYFGt5YuipmUPZmaNvTXCLS2RO88sK0AuJSpWK3' +
        'u+Nb8PZrS0TefQmuXeGcsKIMLW+1s+fIERrbLK8hpfl6ZpI6VwP9V2tX4EGbdemQOzJcGfLZp28ZMVFKeqJ64b7pKXYvjVJefghU' +
        'PzWritxbVjk5Cjy+6pKwsUfo99qP2q3qw2Hdv+yKO/6bx0fPwXwIVNdincjXI8MVEYkMV0rz9esvzfTEsL4/tuFMjOSkuJYsdN6d' +
        'zIDXmSZVkWWLlIFZeihpBgN97rWTY0cXRUqs+qnXFpFjW/XSG/5NK9Vtqdr6hFCrJj5aiY92hqvpfSA7WZ3DgcyAfbLWP/blxH1s' +
        'kZFp2ZHm2pyivuoIXnxi5qaoR3L1cXteazLbu4P7MrWRpfe1z65rsS6XuGXuBtJdytjLR4HHJyIJ0crH78HUuH9nvrMnmBij9Hvt' +
        '7t92apy6c50rO1ktueqfGOho3uiWYUMqG4zyQn1xRKjFOHNmcG4PZOk1z8whvzNNQz675rl5MEtXRCrrjR+DzsYBr3NxCXEEW+T8' +
        'PWP/Rm3N8lm7HZnBa1BmkvpzUDtVa+gu52t+T4a2IdH5nGW79DP1RpgmqirlhePHZ6yHbYHWrsDAsH33rRXhVjzFs7DKlKk/s9rM' +
        'fxRpIgYCGAhgIICBAAYCGAhgIICBAAaavt9iOVO7N59nOEEAAwEMBDAQwEAAAwEMBDAQwEAAAwEMBDAQwEAAAwEMBDAQwEAAAwEM' +
        'BDAQwEAAAwEMBDAQwEAAAwEMBDAQwEAAAwEMBDCQhPYX6inWQaeK3ScAAAAASUVORK5CYII=';

let bots = [
  { id: 'bot-chief', name: 'Chief', role: '团队总管', sessionId: 'session-mock-chief',
    model: 'mock/gpt-5', effort: 'high', instructions: '先给结论，再给细节。',
    avatar: { image: hostAvatarImage } },
  { id: 'bot-searcher', name: 'Searcher', role: '搜索', sessionId: 'session-mock-search',
    model: 'mock/gpt-5-mini', effort: 'low', instructions: '只做检索与摘要。' }
];
/** 主 Bot 列表（state.mainBotIds） */
let mainBotIds = ['bot-chief'];
/** 可用模型 */
// 故意给一份**较长**的模型列表：验证 Bot 编辑页的下拉能扛住真实规模
const modelCatalog = [
  { ref: 'mock/gpt-5', name: 'GPT-5' },
  { ref: 'mock/gpt-5-mini', name: 'GPT-5 mini' },
  { ref: 'mock/gpt-5-nano', name: 'GPT-5 nano' },
  { ref: 'mock/gpt-4.1', name: 'GPT-4.1' },
  { ref: 'mock/gpt-4.1-mini', name: 'GPT-4.1 mini' },
  { ref: 'mock/claude-opus', name: 'Claude Opus 4' },
  { ref: 'mock/claude-sonnet', name: 'Claude Sonnet 4' },
  { ref: 'mock/gemini-pro', name: 'Gemini 2.5 Pro' },
  { ref: 'mock/gemini-flash', name: 'Gemini 2.5 Flash' },
  { ref: 'mock/deepseek-v3', name: 'DeepSeek V3' },
  { ref: 'mock/qwen-max', name: 'Qwen Max' },
  { ref: 'mock/local-large', name: '本地大模型（长上下文）' }
];
/** 思考档位（按模型返回，P2-5） */
const effortCatalog = {
  'mock/gpt-5': [
    { id: 'low', name: '低', description: '更快' },
    { id: 'medium', name: '中' },
    { id: 'high', name: '高', description: '更深' }
  ],
  'mock/gpt-5-mini': [{ id: 'low', name: '低' }, { id: 'medium', name: '中' }]
};
let rooms = [{
  id: 'room-mock', name: '研发小组', sessionId: 'session-mock-room',
  members: ['bot-chief', 'bot-searcher'], admin: 'bot-chief',
  notice: '每日 10 点同步进展', mode: 'admin'
}];

/** 一轮历史消息（含表格/代码块/嵌套列表，用于渲染回归） */
function historyMessages() {
  const base = Date.now() - 600000;
  return [
    { id: 'm1', sessionId: 'session-mock-room', seq: 1, role: 'user', createdAt: base,
      text: '帮我看下 P1 还剩什么' },
    { id: 'm2', sessionId: 'session-mock-room', seq: 2, role: 'assistant', createdAt: base + 1000,
      reasoning: '用户在追问进度，我应该给出结构化清单并提议下一步。',
      text: '还剩三类界面要真机验收。\n\n- 提问卡\n- 审批卡\n- 排队面板\n\n需要我逐个触发吗？' },
    { id: 'm3', sessionId: 'session-mock-room', seq: 3, role: 'assistant', createdAt: base + 2000,
      text: '## 1) 代码块长行\n\n```typescript\nconst veryLongIdentifierName = someFunctionCall(argumentOne, argumentTwo, argumentThree, argumentFour);\n```\n\n## 2) 表格\n\n| 名称 | 说明 | 备注 |\n| --- | --- | --- |\n| averyveryverylongcellvaluewithoutspacesatall | 普通说明文字 | x |\n| b | inline_code_that_is_quite_long_without_spaces | y |\n\n## 3) 长引用\n\n> 这是一段很长的引用文字用来确认引用块的左侧竖线与右侧边界是否会被内容撑开导致溢出气泡外面去这是后半段继续加长\n\n## 4) 嵌套列表\n\n- 第一层项目符号内容也比较长需要换行处理确认缩进后的右边界是否仍然安全\n  - 第二层嵌套项目符号内容同样比较长需要换行处理确认右边界\n    - 第三层更深嵌套的项目符号内容继续加长确认最深层也不会溢出气泡\n\n## 5) 长行内代码\n\n`cccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccc`' },
    { id: 'm3b', sessionId: 'session-mock-room', seq: 5, role: 'user', createdAt: base + 2500,
      text: '这是一张截图',
      attachments: [{ id: 'att-1', type: 'image', name: 'screenshot.png', mediaType: 'image/png',
        size: 4096, width: 64, height: 64 }] },
    { id: 'm4', sessionId: 'session-mock-room', seq: 4, role: 'assistant', createdAt: base + 3000,
      tool: { name: 'web_search', status: 'ok', durationMs: 1287,
        input: '{"query":"HarmonyOS ArkUI Flex ItemAlign.Stretch 单元格等高","limit":5,"lang":"zh-CN"}' } }
  ];
}

/** 提交回执（requestId → 状态） */
const submissions = {};

/** 附件上传序号 */
let uploadSeq = 1;

/** Agent 会话改名记录（sessionId → 标题） */
const renamedTitles = {};

/** P2-9 DSH Agent（每个团队最多一个） */
let agents = [
  { id: 'agent-1', name: 'DSH Agent', sessions: ['session-agent-1', 'session-agent-2'], createdAt: Date.now() - 86400000 }
];

/** 通知中心（P3-4）：inbox + 偏好 + 已读游标 */
let notificationItems = [
  { id: 1, conversationId: 'room-mock', kind: 'reply', title: 'Chief 在「研发小组」里回复了你',
    body: '关于 P2 的进度：还差两类界面要验收', createdAt: Date.now() - 300000, read: false },
  { id: 2, conversationId: 'session-mock-search', kind: 'question', title: 'Searcher 有一个问题等你确认',
    body: '要检索的是 HarmonyOS ArkUI 文档吗？', createdAt: Date.now() - 1800000, read: false },
  { id: 3, conversationId: 'room-mock', kind: 'approval', title: '有一个操作等待审批',
    body: '写入 /tmp/report.md', createdAt: Date.now() - 86400000, read: true }
];
let notificationCursor = 3;
let notificationPrefs = { enabled: true, categories: ['reply', 'question', 'approval'], readThrough: 0 };

/** 连接器（工具与技能补全）：GitHub 一个，可连接/断开/重试 */
let connectors = [
  { id: 'github', name: 'GitHub', state: 'off', account: null }
];

/** P2-8 插件与插件包（内存副本，支持开关） */
const pluginEntries = [
  { entryId: 'ds-bot', moduleName: 'ds-bot', enabled: true, readOnlyReason: 'mobile-required' },
  { entryId: 'web-search', moduleName: 'web-search', enabled: true },
  { entryId: 'code-tools', moduleName: 'code-tools', enabled: false }
];
const bundleEntries = [
  { name: 'automation', version: '1.2.0', description: '自动化任务', enabled: true, installed: true, optional: true, removable: true },
  { name: 'lsp', version: '0.9.1', description: '语言服务', enabled: false, installed: true, optional: true, removable: true },
  { name: 'core', version: '2.0.0', description: '核心', enabled: true, installed: true, readOnlyReason: 'mobile-required' }
];

/** P2-7 能力库（团队级） */
const capabilityLibrary = [
  { name: 'web-search', kind: 'mcp', description: '联网搜索并提取网页内容', transport: 'stdio', approved: true },
  { name: 'file-tools', kind: 'mcp', description: '读写主机工作目录里的文件', transport: 'stdio', approved: true },
  { name: 'code-review', kind: 'skill', description: '按团队规范评审代码改动' },
  { name: 'release-notes', kind: 'skill', description: '从提交记录生成发布说明' },
  { name: 'starter-pack', kind: 'pack', description: '新人上手常用能力组合', items: ['web-search', 'code-review'] }
];
/** botId → 已挂载能力名 */
let botCapabilities = {
  'bot-chief': ['web-search', 'code-review'],
  'bot-searcher': ['web-search']
};
/** botId → 能力名 → 运行状态 */
let botCapabilityStatuses = {
  'bot-chief': { 'web-search': { state: 'ready' }, 'code-review': { state: 'ready' } },
  'bot-searcher': { 'web-search': { state: 'needs-approval', error: '等待主机批准' } }
};

/** P2-4 记忆条目 */
let memoryEntries = [
  { scope: 'own', topic: '工作方式', text: '先给结论再给细节', added: '2026-10-17', by: 'user', source: '对话' },
  { scope: 'own', topic: '语言', text: '偏好中文回答', added: '2026-10-16', by: 'user', source: '对话' },
  { scope: 'team', topic: '项目', text: '鸿蒙版移植正在推进', added: '2026-10-15', by: 'user', source: '对话' }
];

/** P2-3 定时任务 */
let scheduleTasks = [
  { id: 'task-seed-1', sessionId: 'session-mock-chief', title: '每日进展汇总', prompt: '汇总今天的进展',
    botId: 'bot-chief', kind: 'daily', time: '09:30', timeZone: 'Asia/Shanghai' },
  { id: 'task-seed-2', sessionId: 'session-mock-room', title: '每周复盘', prompt: '整理本周工作',
    roomId: 'room-mock', kind: 'weekly', time: '18:00', timeZone: 'Asia/Shanghai', weekdays: [5] }
];
let scheduleSeq = 3;
/** P2-10 设备 */
let devices = [
  { id: 'mock-device-1', name: '本机（模拟器）' },
  { id: 'mock-device-2', name: '旧的平板' }
];

function json(res, status, body) {
  const text = JSON.stringify(body);
  res.writeHead(status, { 'Content-Type': 'application/json; charset=utf-8', 'Content-Length': Buffer.byteLength(text) });
  res.end(text);
}

function memoryPayload() {
  const own = memoryEntries.filter(e => e.scope === 'own');
  const team = memoryEntries.filter(e => e.scope === 'team');
  return {
    botId: 'bot-chief',
    entries: memoryEntries,
    sizes: {
      own: own.reduce((n, e) => n + e.text.length, 0),
      team: team.reduce((n, e) => n + e.text.length, 0)
    },
    limits: { entry: 300, main: 4000, topic: 16000, topics: 40 },
    summary: { text: '用户偏好简洁、中文；团队正在做鸿蒙移植。', at: '2026-10-17' },
    fresh: true, summarizing: false, error: null
  };
}

function usagePayload() {
  const hour = Math.floor(Date.now() / 3600000);
  return {
    owners: [
      { owner: 'bot-chief', name: 'Chief', kind: 'bot' },
      { owner: 'bot-searcher', name: 'Searcher', kind: 'bot' },
      { owner: 'room-mock', name: '研发小组', kind: 'room' }
    ],
    models: [
      { key: 'p/m-1', provider: 'mock', model: 'gpt-5', name: 'GPT-5' },
      { key: 'p/m-2', provider: 'mock', model: 'gpt-5-mini', name: 'GPT-5 mini' }
    ],
    kinds: ['turn'], now: hour, scanning: false,
    rows: [
      [hour - 1, 0, 0, 0, 12000, 3000, 800, 4500, 6],
      [hour - 2, 1, 1, 0, 8000, 1500, 400, 2600, 4],
      [hour - 3, 2, 0, 0, 15000, 4000, 1200, 6000, 9],
      [hour - 30, 0, 1, 0, 5000, 800, 200, 1500, 3],
      [hour - 200, 1, 0, 0, 30000, 9000, 2000, 12000, 18]
    ]
  };
}

/** 处理一个 action，返回响应体 */
function handleAction(endpoint, args) {
  switch (endpoint) {
    case 'add-agent': {
      if (agents.length > 0) return { error: 'The team already has a DSH Agent' };
      const agent = { id: `agent-${Date.now()}`, name: 'DSH Agent',
        sessions: [`session-agent-${Date.now()}`], createdAt: Date.now() };
      agents.push(agent);
      console.log('[mock] ✅ 创建 DSH Agent');
      return agent;
    }
    case 'agent-rename': {
      const agent = agents.find(item => item.id === args.agentId);
      if (agent === undefined) return { error: 'no such agent' };
      agent.titles = Object.assign({}, agent.titles, { [args.sessionId]: args.title });
      renamedTitles[args.sessionId] = args.title;
      console.log(`[mock] ✅ Agent 会话改名 → ${args.title}`);
      return true;
    }
    case 'agent-archive': {
      const agent = agents.find(item => item.id === args.agentId);
      if (agent !== undefined) agent.sessions = agent.sessions.filter(id => id !== args.sessionId);
      console.log(`[mock] ✅ 归档 Agent 会话 ${args.sessionId}`);
      return true;
    }
    case 'remove-agent': {
      agents = agents.filter(item => item.id !== args.agentId);
      console.log('[mock] ✅ 移除 DSH Agent');
      return { bots, rooms, models: modelCatalog, mainBotId: 'bot-chief', mainBotIds,
        capabilities: capabilityLibrary, capabilityStatuses: botCapabilityStatuses,
        connectors, questions: {}, work: {} };
    }
    case 'notifications-list': {
      const items = notificationItems.map(item => ({
        id: item.id, conversationId: item.conversationId, kind: item.kind, title: item.title,
        body: item.body, createdAt: item.createdAt,
        read: item.id <= notificationPrefs.readThrough || item.read === true
      }));
      return { items: items.slice().reverse(), preferences: notificationPrefs,
        cursor: notificationCursor, pushRegistered: false, pushAvailable: false };
    }
    case 'notifications-read': {
      if (Array.isArray(args.ids) && args.ids.length > 0) {
        for (const item of notificationItems) if (args.ids.includes(item.id)) item.read = true;
        console.log(`[mock] ✅ 标记已读 ids=${JSON.stringify(args.ids)}`);
      } else {
        notificationPrefs = Object.assign({}, notificationPrefs, { readThrough: args.through });
        console.log(`[mock] ✅ 全部已读 through=${args.through}`);
      }
      return { ok: true };
    }
    case 'notifications-preferences': {
      notificationPrefs = Object.assign({}, notificationPrefs,
        { enabled: args.enabled === true, categories: args.categories ?? [] });
      console.log(`[mock] ✅ 通知偏好 enabled=${args.enabled} categories=${JSON.stringify(args.categories)}`);
      return { ok: true };
    }
    case 'connector-connect': {
      const token = String(args.token ?? '').trim();
      if (token === '') return { error: 'Paste a token first' };
      connectors = [{ id: 'github', name: 'GitHub', state: 'ready', account: 'mock-user' }];
      console.log('[mock] ✅ GitHub 连接成功');
      return { connectors };
    }
    case 'connector-retry': {
      connectors = [{ id: 'github', name: 'GitHub', state: 'ready', account: 'mock-user' }];
      console.log('[mock] ✅ GitHub 重试成功');
      return { connectors };
    }
    case 'connector-disconnect': {
      connectors = [{ id: 'github', name: 'GitHub', state: 'off', account: null }];
      console.log('[mock] ✅ GitHub 已断开');
      return { connectors };
    }
    case 'skills-list':
      return {
        available: true,
        skills: [
          { name: 'code-review', description: '按团队规范评审代码改动',
            whenToUse: '提交前自检', source: 'workspace',
            invocation: { modelInvocable: true, userInvocable: true } },
          { name: 'release-notes', description: '从提交记录生成发布说明',
            whenToUse: '发版时', source: 'workspace',
            invocation: { modelInvocable: false, userInvocable: true } },
          { name: 'auto-format', description: '自动格式化并检查风格',
            source: 'runtime',
            invocation: { modelInvocable: true, userInvocable: false } },
          { name: 'deep-research', description: '多轮检索并汇总成报告',
            whenToUse: '需要联网调研时', source: 'bundled',
            invocation: { modelInvocable: true, userInvocable: true } }
        ]
      };
    case 'skills-get': {
      const skill = {
        'code-review': '# 代码评审\n\n## 步骤\n\n1. 读 diff\n2. 检查边界\n3. 给结论\n',
        'release-notes': '# 发布说明\n\n按模块汇总提交记录。\n',
        'deep-research': '# 深度检索\n\n先列问题，再逐条检索，最后汇总。\n'
      }[args.name];
      if (skill === undefined) return { error: 'not found' };
      return { name: args.name, description: '示例技能', content: skill, truncated: false,
        source: 'workspace', provider: 'mock' };
    }
    case 'plugins-list':
      return {
        writable: true,
        plugins: pluginEntries,
        bundles: bundleEntries
      };
    case 'plugins-set-enabled': {
      const plugin = (pluginEntries ?? []).find(item => item.entryId === args.id);
      if (plugin !== undefined) plugin.enabled = args.enabled === true;
      console.log(`[mock] ✅ 插件 ${args.id} → ${args.enabled}`);
      return { ok: true };
    }
    case 'bundle-set-enabled': {
      const bundle = (bundleEntries ?? []).find(item => item.name === args.id);
      if (bundle !== undefined) bundle.enabled = args.enabled === true;
      console.log(`[mock] ✅ 插件包 ${args.id} → ${args.enabled}`);
      return { ok: true };
    }
    case 'efforts':
      return { efforts: effortCatalog[args.ref] ?? [], default: 'medium' };
    case 'update-bot': {
      const bot = bots.find(item => item.id === args.id);
      if (bot === undefined) return { error: 'no such bot' };
      for (const key of ['name', 'role', 'instructions', 'model', 'effort', 'color', 'avatar', 'workDir', 'permission']) {
        if (args[key] !== undefined) {
          if (args[key] === '') delete bot[key];
          else bot[key] = args[key];
        }
      }
      console.log(`[mock] ✅ 更新 Bot ${bot.name} 字段=${Object.keys(args).filter(k => k !== 'id').join(',')}`);
      return bot;
    }
    case 'duplicate-bot': {
      const source = bots.find(item => item.id === args.id);
      if (source === undefined) return { error: 'no such bot' };
      const copy = Object.assign({}, source, {
        id: `${source.id}-copy-${bots.length}`, name: `${source.name} 副本`,
        sessionId: `session-copy-${bots.length}`
      });
      bots.push(copy);
      console.log(`[mock] ✅ 复制 Bot → ${copy.name}`);
      return copy;
    }
    case 'delete-bot': {
      const removed = bots.find(item => item.id === args.id);
      bots = bots.filter(item => item.id !== args.id);
      mainBotIds = mainBotIds.filter(id => id !== args.id);
      console.log(`[mock] ✅ 删除 Bot ${removed ? removed.name : args.id}`);
      const botsWithCaps3 = bots.map(bot => Object.assign({}, bot, { capabilities: botCapabilities[bot.id] ?? [] }));
      return { bots: botsWithCaps3, rooms, models: modelCatalog, mainBotId: mainBotIds[0] ?? null,
        mainBotIds, capabilities: capabilityLibrary, capabilityStatuses: botCapabilityStatuses, questions: {}, work: {} };
    }
    case 'set-main': {
      if (args.main === false) mainBotIds = mainBotIds.filter(id => id !== args.id);
      else if (!mainBotIds.includes(args.id)) mainBotIds = [...mainBotIds, args.id];
      console.log(`[mock] ✅ 主 Bot 列表 → ${JSON.stringify(mainBotIds)}`);
      const botsWithCaps4 = bots.map(bot => Object.assign({}, bot, { capabilities: botCapabilities[bot.id] ?? [] }));
      return { bots: botsWithCaps4, rooms, models: modelCatalog, mainBotId: mainBotIds[0] ?? null,
        mainBotIds, capabilities: capabilityLibrary, capabilityStatuses: botCapabilityStatuses, questions: {}, work: {} };
    }
    case 'update-room': {
      const room = rooms.find(item => item.id === args.id);
      if (room === undefined) return { error: 'no such room' };
      const changes = [];
      if (typeof args.name === 'string' && args.name !== room.name) {
        changes.push(`renamed to ${args.name}`);
        room.name = args.name;
      }
      if (typeof args.notice === 'string' && args.notice !== room.notice) {
        changes.push('notice changed');
        room.notice = args.notice;
      }
      if (args.mode !== undefined && args.mode !== room.mode) {
        changes.push(args.mode === 'admin' ? 'plain messages now go to the admin first' : 'every member now replies in turn');
        room.mode = args.mode;
      }
      if (args.admin !== undefined && args.admin !== room.admin) {
        changes.push('admin changed');
        room.admin = args.admin;
      }
      if (Array.isArray(args.members)) {
        const before = room.members.join(',');
        room.members = args.members;
        if (room.members.join(',') !== before) changes.push('members changed');
      }
      console.log(`[mock] ✅ 更新群聊 ${room.name} changes=${changes.length}`);
      return { room, changes };
    }
    case 'delete-room': {
      const removed = rooms.find(item => item.id === args.id);
      rooms = rooms.filter(item => item.id !== args.id);
      console.log(`[mock] ✅ 删除群聊 ${removed ? removed.name : args.id}`);
      const botsWithCaps2 = bots.map(bot => Object.assign({}, bot, {
        capabilities: botCapabilities[bot.id] ?? []
      }));
      return { bots: botsWithCaps2, rooms, models: [], mainBotId: 'bot-chief',
        capabilities: capabilityLibrary, capabilityStatuses: botCapabilityStatuses,
        connectors, questions: {}, work: {} };
    }
    case 'bot-capability': {
      const botId = args.botId ?? '';
      const name = args.name ?? '';
      const attached = args.attached === true;
      const current = botCapabilities[botId] ?? [];
      botCapabilities[botId] = attached
        ? (current.includes(name) ? current : [...current, name])
        : current.filter(item => item !== name);
      console.log(`[mock] ✅ ${attached ? '挂载' : '卸载'} ${name} → ${botId}`);
      const botsWithCaps = bots.map(bot => Object.assign({}, bot, {
        capabilities: botCapabilities[bot.id] ?? []
      }));
      return { bots: botsWithCaps, rooms, models: [], mainBotId: 'bot-chief',
        capabilities: capabilityLibrary, capabilityStatuses: botCapabilityStatuses,
        connectors, questions: {}, work: {} };
    }
    case 'approvals':
      return SCENARIO === 'approvals'
        ? { requests: [{ id: 'ap-1', conversationId: 'room-mock', sessionId: 'session-mock-room',
            toolName: 'write_file', reason: '需要写入 /tmp/report.md（模拟的审批请求）',
            callId: 'call-1', createdAt: Date.now() }] }
        : { requests: [] };
    case 'approval-resolve': return { accepted: true };
    case 'queue-remove':
    case 'answer-question':
    case 'dismiss-question': return { ok: true };
    case 'room-progress':
      return { roomId: 'room-mock', currentSessionId: 'session-mock-room',
        rounds: [{ roundId: 'r1', startedAt: Date.now() - 40000,
          replies: [{ botId: 'bot-searcher', callId: 'c1', state: 'replying' }] }] };
    case 'parts':
      return { conversationId: args.conversationId ?? 'room-mock', currentSessionId: 'part-3',
        parts: [
          { sessionId: 'part-1', number: 1, current: false, cursor: 'p1-c0',
            startedAt: Date.now() - 86400000 * 3, endedAt: Date.now() - 86400000 * 2 },
          { sessionId: 'part-2', number: 2, current: false, cursor: 'p2-c0',
            startedAt: Date.now() - 86400000 * 2, endedAt: Date.now() - 86400000 },
          { sessionId: 'part-3', number: 3, current: true, cursor: '',
            startedAt: Date.now() - 86400000, endedAt: Date.now() }
        ] };
    case 'earlier': {
      const sessionId = args.sessionId ?? 'part-1';
      const cursor = args.cursor ?? '';
      const first = { id: `${sessionId}:m1`, sessionId, seq: 1, role: 'user',
        text: `${sessionId} 的第一条历史消息`, createdAt: Date.now() - 86400000 * 3 };
      const second = { id: `${sessionId}:m2`, sessionId, seq: 2, role: 'assistant',
        text: `这是 ${sessionId} 的回复。用于验证历史分段视图与实时事件隔离。`, createdAt: Date.now() - 86400000 * 3 + 60000 };
      if (!cursor.endsWith('-older')) return { messages: [first, second], cursor: `${sessionId}-older`, sessionId };
      const older = { id: `${sessionId}:m0`, sessionId, seq: 0, role: 'user',
        text: `${sessionId} 更早的一条消息（第二次翻页）`, createdAt: Date.now() - 86400000 * 3 - 60000 };
      return { messages: [older], cursor: '', sessionId };
    }
    case 'usage': return usagePayload();
    case 'schedules': return { available: true, tasks: scheduleTasks };
    case 'schedule-create': {
      const task = {
        id: `task-${scheduleSeq++}`, sessionId: args.target ? `sess-${args.target}` : 'sess-bot',
        title: args.title ?? '未命名', prompt: args.prompt ?? '',
        botId: args.target, kind: args.when?.kind ?? 'daily',
        scheduledAt: args.when?.at, time: args.when?.time, timeZone: args.when?.timeZone,
        weekdays: args.when?.weekdays,
        everySeconds: args.when?.minutes ? args.when.minutes * 60 : undefined
      };
      scheduleTasks.push(task);
      console.log(`[mock] ✅ 创建任务 ${task.title} kind=${task.kind}`);
      return { available: true, tasks: scheduleTasks };
    }
    case 'schedule-delete':
      scheduleTasks = scheduleTasks.filter(t => t.id !== args.id);
      console.log(`[mock] ✅ 删除任务 ${args.id}`);
      return { available: true, tasks: scheduleTasks };
    case 'memory-view': return memoryPayload();
    case 'memory-forget':
      memoryEntries = memoryEntries.filter(e => !(e.scope === args.scope && e.text === args.text));
      console.log(`[mock] ✅ 删除记忆 scope=${args.scope} text=${String(args.text).slice(0, 20)}`);
      return memoryPayload();
    case 'memory-ask': {
      const text = String(args.text ?? '');
      const changes = [];
      if (text.includes('记住')) {
        const content = text.replace(/^.*记住/, '').trim() || '新的记忆';
        memoryEntries.push({ scope: 'own', topic: '用户偏好', text: content,
          added: '2026-10-17', by: 'user', source: 'memory panel' });
        changes.push({ op: 'add', scope: 'own', text: content, ok: true });
      } else if (text.includes('删')) {
        const target = memoryEntries[0];
        if (target !== undefined) {
          memoryEntries = memoryEntries.filter(e => e !== target);
          changes.push({ op: 'remove', scope: target.scope, text: target.text, ok: true });
        }
      }
      console.log(`[mock] ✅ 记忆问答 text=${text.slice(0, 20)} changes=${changes.length}`);
      return { reply: changes.length > 0 ? '已按你说的更新记忆。' : '没有需要修改的地方。',
        changes, view: memoryPayload() };
    }
    case 'usage-legacy': return { ok: true };
    default: return { ok: true };
  }
}

const server = createServer({ cert, key }, (req, res) => {
  let bodyText = '';
  req.on('data', chunk => { bodyText += chunk; });
  req.on('end', () => {
    const url = new URL(req.url ?? '/', 'https://mock');
    const path = url.pathname;
    const auth = req.headers.authorization ?? '';
    console.log(`[mock] ${req.method} ${path}${url.search}`);

    if (path === '/mobile/v1/info') {
      return json(res, 200, { serverId: SERVER_ID, name: 'Mock Host', version: '0.1.0' });
    }
    if (path === '/mobile/v1/pairings') {
      writeFileSync('/tmp/dsbot-mock-pairing.json', JSON.stringify({
        url: `https://${localAddress()}:${PORT}`, code: PAIRING_CODE,
        serverId: SERVER_ID, tlsPin
      }));
      return json(res, 200, { claimToken: 'mock-claim', requestId: randomUUID(), status: 'pending' });
    }
    if (path === '/mobile/v1/pairings/complete') {
      return json(res, 200, { status: 'approved', session: sessionPayload() });
    }
    if (auth !== `Bearer ${ACCESS_TOKEN}`) {
      return json(res, 401, { error: { code: 'unauthorized', message: 'invalid token' } });
    }
    if (path === '/mobile/v1/uploads' && req.method === 'POST') {
      const conversationId = url.searchParams.get('conversationId') ?? ''
      const sessionId = url.searchParams.get('sessionId') ?? ''
      const name = url.searchParams.get('name') ?? 'file'
      const mediaType = url.searchParams.get('mediaType') ?? 'application/octet-stream'
      const size = Buffer.byteLength(bodyText, 'binary')
      const receiptId = `receipt-${uploadSeq++}`
      console.log(`[mock] ✅ 上传附件 ${name} (${mediaType}, ${size} bytes) → ${receiptId}`);
      return json(res, 200, { receiptId, conversationId, sessionId, name, mediaType, size,
        expiresAt: Date.now() + 15 * 60_000 });
    }
    // 提交消息（P3-1：可能带附件 receiptId）
    if (path === '/mobile/v1/submissions' && req.method === 'POST') {
      let submitted = {};
      try { submitted = JSON.parse(bodyText); } catch { submitted = {}; }
      const attachments = Array.isArray(submitted.attachments) ? submitted.attachments : [];
      console.log(`[mock] ✅ 提交消息 text=${String(submitted.text ?? '').slice(0, 20)} 附件=${attachments.length} ${JSON.stringify(attachments)}`);
      submissions[submitted.requestId] = { status: 'accepted', conversationId: submitted.conversationId, sessionId: submitted.sessionId };
      return json(res, 200, { accepted: true, conversationId: submitted.conversationId,
        sessionId: submitted.sessionId, requestId: submitted.requestId });
    }
    if (path.startsWith('/mobile/v1/submissions/')) {
      const requestId = decodeURIComponent(path.substring('/mobile/v1/submissions/'.length));
      const record = submissions[requestId];
      return json(res, 200, record ?? { status: 'unknown' });
    }
    if (path === '/mobile/v1/state') {
      const botsWithCaps = bots.map(bot => Object.assign({}, bot, {
        capabilities: botCapabilities[bot.id] ?? []
      }));
      return json(res, 200, { bots: botsWithCaps, rooms, models: modelCatalog, mainBotId: 'bot-chief',
        mainBotIds,
        capabilities: capabilityLibrary, capabilityStatuses: botCapabilityStatuses,
        connectors,
        questions: SCENARIO === 'questions' ? questionPayload() : {},
        work: {}, readOnly: undefined });
    }
    if (path === '/mobile/v1/conversations') {
      const agentConversations = agents.flatMap(agent => agent.sessions.map((sessionId, index) => ({
        id: `agent:${agent.id}:${sessionId}`, kind: 'agent', agentId: agent.id,
        name: renamedTitles[sessionId] ?? (index === 0 ? '整理本周计划' : `DSH Agent · ${index + 1}`),
        role: 'DSH Agent', sessionId
      })));
      return json(res, 200, { conversations: [...conversations, ...agentConversations] });
    }
    // 发送前先取目标（会话当前 part 的 sessionId）
    // 附件下载（P3-1）：返回一张真实的 PNG（1x1 红点放大成渐变方块，便于肉眼确认）
    if (path.startsWith('/mobile/v1/attachments/')) {
      const id = decodeURIComponent(path.substring('/mobile/v1/attachments/'.length));
      // 240x140 纯色 PNG（带白条），确保在真机上一眼可见
      const png = Buffer.from(
        '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', 'base64');
      console.log(`[mock] ✅ 下载附件 ${id} (${png.length} bytes)`);
      res.writeHead(200, { 'Content-Type': 'image/png', 'Content-Length': png.length });
      res.end(png);
      return;
    }
    if (path.endsWith('/target')) {
      const conversationId = decodeURIComponent(path.substring('/mobile/v1/conversations/'.length, path.length - '/target'.length));
      const found = conversations.find(item => item.id === conversationId);
      return json(res, 200, { conversationId, sessionId: found ? found.sessionId : 'session-mock-room',
        eventSeq: 1 });
    }
    if (path.endsWith('/messages')) {
      return json(res, 200, { messages: historyMessages(), cursor: 'cursor-page-1', sessionId: 'session-mock-room' });
    }
    if (req.method === 'DELETE' && path.startsWith('/mobile/v1/devices/')) {
      const id = decodeURIComponent(path.substring('/mobile/v1/devices/'.length));
      devices = devices.filter(d => d.id !== id);
      console.log(`[mock] ✅ 撤销设备 ${id}`);
      return json(res, 200, {});
    }
    if (path === '/mobile/v1/devices') return json(res, 200, { devices, currentDeviceId: 'mock-device-1' });
    if (path === '/mobile/v1/read-markers') return json(res, 200, { ok: true });
    if (path === '/mobile/v1/actions') {
      let parsed = {};
      try { parsed = JSON.parse(bodyText); } catch { parsed = {}; }
      const endpoint = parsed.endpoint;
      const args = parsed.payload ?? {};
      console.log(`[mock]   action = ${endpoint} payload=${JSON.stringify(args)}`);
      // 让 schedule/memory 的移动端白名单字段也能被读到
      const merged = Object.assign({}, args, args.when !== undefined ? {} : {});
      return json(res, 200, handleAction(endpoint, merged));
    }
    return json(res, 404, { error: { code: 'not-found', message: `no mock route for ${path}` } });
  });
});

/** 本机局域网地址（用于配对 JSON 的 url） */
function localAddress() {
  return process.env.MOCK_HOST_IP ?? '192.168.3.54';
}

function sessionPayload() {
  return {
    accessToken: ACCESS_TOKEN, refreshToken: REFRESH_TOKEN,
    deviceId: 'mock-device-1', serverId: SERVER_ID,
    expiresAt: Date.now() + 86400000
  };
}

function questionPayload() {
  return {
    'q-1': {
      id: 'q-1', sessionId: 'session-mock-room', conversationId: 'room-mock',
      text: '下一步做哪个功能？', options: ['视图拆分', 'P2 设置页真实化', 'P3 附件与语音'],
      allowCustom: true, multiSelect: true, createdAt: Date.now()
    }
  };
}

/** 极简 WebSocket：完成握手后只推一帧 ready，之后保持连接（App 会退回轮询兜底） */
server.on('upgrade', (req, socket) => {
  const key = req.headers['sec-websocket-key'];
  if (typeof key !== 'string') { socket.destroy(); return; }
  const accept = createHash('sha1')
    .update(key + '258EAFA5-E914-47DA-95CA-C5AB0DC85B11').digest('base64');
  socket.write(
    'HTTP/1.1 101 Switching Protocols\r\n' +
    'Upgrade: websocket\r\nConnection: Upgrade\r\n' +
    `Sec-WebSocket-Accept: ${accept}\r\n\r\n`);
  const frame = (payload) => {
    const body = Buffer.from(payload, 'utf8');
    const header = body.length < 126
      ? Buffer.from([0x81, body.length])
      : Buffer.from([0x81, 126, body.length >> 8, body.length & 0xff]);
    socket.write(Buffer.concat([header, body]));
  };
  // 握手后立即推 ready，避免 App 认为事件流不可用
  frame(JSON.stringify({ type: 'ready', eventSeq: 1, snapshot: { messages: historyMessages() } }));
  socket.on('error', () => {});
  socket.on('close', () => {});
});

server.listen(PORT, () => {
  console.log(`[mock] 场景 = ${SCENARIO}，监听 ${PORT}`);
  console.log(`[mock] 配对 JSON：${JSON.stringify({
    url: `https://${localAddress()}:${PORT}`, code: PAIRING_CODE, serverId: SERVER_ID, tlsPin
  })}`);
});
