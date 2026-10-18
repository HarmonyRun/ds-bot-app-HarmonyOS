import { Bot, BotPatch } from '../model/Models';

/**
 * Bot 管理的**纯逻辑**（P2-5）。
 *
 * 这里处理三类容易出错的事：
 * 1. **只提交变化字段**（宿主按"字段是否出现"决定改不改）；
 * 2. 名字/角色长度与重名（宿主会拒绝，但提前拦下能少一次往返）；
 * 3. **思考等级依赖模型**——宿主明确要求"先选模型再选思考档位"。
 *
 * 抽出来的原因：这些都是"错了会在主机侧静默失败或被拒"的地方，
 * 必须能脱离设备验证。
 */

/**
 * 头像 data URL 长度上限（宿主 `MAX_AVATAR_IMAGE = 160_000`，单位是**字符串长度**）。
 *
 * 注意这是 base64 字符串长度，不是原始字节：160000 字符约对应 120KB 原图。
 */
export const AVATAR_DATA_URL_MAX = 160000;

/** 允许的头像图片类型（宿主 `cleanAvatar` 的正则）。 */
const AVATAR_TYPES: string[] = ['image/png', 'image/jpeg', 'image/webp', 'image/gif'];

/** 把图片字节转成宿主接受的 data URL；类型不支持或超长时返回空串。 */
export function avatarDataUrl(mediaType: string, base64: string): string {
  if (!AVATAR_TYPES.includes(mediaType)) return '';
  if (base64.length === 0) return '';
  const url = `data:${mediaType};base64,${base64}`;
  if (url.length > AVATAR_DATA_URL_MAX) return '';
  return url;
}

/** 头像用什么类型（不支持的图片类型给出提示）。 */
export function avatarTypeProblem(mediaType: string): string {
  return AVATAR_TYPES.includes(mediaType) ? '' : '头像只支持 PNG / JPEG / WebP / GIF';
}

/** 名字长度上限（宿主 `updateBot` 会 slice 到 40，这里提前提示）。 */
export const BOT_NAME_MAX = 40;
/** 角色长度上限（宿主 slice 到 24）。 */
export const BOT_ROLE_MAX = 24;

/** 编辑表单。 */
export interface BotForm {
  id: string;
  name: string;
  role: string;
  instructions: string;
  /** 模型 ref；空串表示"跟随默认" */
  model: string;
  /** 思考档位 id；空串表示未设置 */
  effort: string;
  /** 头像 data URL；空串表示用默认矢量头像 */
  avatarImage: string;
}

/** 校验结果。 */
export interface BotValidation {
  ok: boolean;
  error: string;
}

/** 由 Bot 生成表单。 */
export function formOfBot(bot: Bot): BotForm {
  return {
    id: bot.id,
    name: bot.name,
    role: bot.role ?? '',
    instructions: bot.instructions ?? '',
    model: bot.model ?? '',
    effort: bot.effort ?? '',
    avatarImage: bot.avatar?.image ?? ''
  };
}

/**
 * 校验表单。
 *
 * `others` 是同队其它 Bot（用于重名检查）——宿主也会查，但提前提示体验更好。
 */
export function validateBotForm(form: BotForm, others: Bot[]): BotValidation {
  const name = form.name.trim();
  if (name.length === 0) return { ok: false, error: '名字不能为空' };
  if (name.length > BOT_NAME_MAX) return { ok: false, error: `名字请控制在 ${BOT_NAME_MAX} 字以内` };
  for (let i = 0; i < others.length; i++) {
    if (others[i].id !== form.id && others[i].name === name) {
      return { ok: false, error: `名字「${name}」已被使用` };
    }
  }
  if (form.role.trim().length > BOT_ROLE_MAX) {
    return { ok: false, error: `角色请控制在 ${BOT_ROLE_MAX} 字以内` };
  }
  // 思考档位必须有模型可依附
  if (form.effort.length > 0 && form.model.length === 0) {
    return { ok: false, error: '先选择模型，才能设置思考档位' };
  }
  return { ok: true, error: '' };
}

/**
 * 生成 `update-bot` 载荷。
 *
 * 只带真正变化的字段；没有变化返回 `undefined`（调用方跳过请求）。
 * `workDir` / `avatar` / `color` 需要系统选择器，本轮不做，因此不出现在载荷里。
 */
export function buildBotPatch(before: Bot, form: BotForm): BotPatch | undefined {
  const patch = new BotPatch(before.id);
  let dirty = false;

  const name = form.name.trim();
  if (name !== before.name) {
    patch.name = name;
    dirty = true;
  }
  const role = form.role.trim();
  if (role !== (before.role ?? '')) {
    patch.role = role;
    dirty = true;
  }
  const instructions = form.instructions.trim();
  if (instructions !== (before.instructions ?? '')) {
    patch.instructions = instructions;
    dirty = true;
  }
  const model = form.model;
  if (model !== (before.model ?? '')) {
    patch.model = model;
    dirty = true;
  }
  const effort = form.effort;
  if (effort !== (before.effort ?? '')) {
    patch.effort = effort;
    dirty = true;
  }
  // 头像变化：宿主用 `avatar` 整体替换（没有 shape 时保留矢量默认）
  const beforeImage = before.avatar?.image ?? '';
  if (form.avatarImage !== beforeImage) {
    patch.avatarImage = form.avatarImage;
    dirty = true;
  }
  return dirty ? patch : undefined;
}

/** Bot 卡片上的一行摘要（模型 / 思考档位）。 */
export function describeBotSummary(bot: Bot, modelName: string, effortName: string): string {
  const model = bot.model === undefined || bot.model.length === 0
    ? (modelName.length > 0 ? modelName : '默认模型')
    : modelName;
  if (bot.effort !== undefined && bot.effort.length > 0) {
    return `${model} · ${effortName.length > 0 ? effortName : bot.effort}`;
  }
  return model;
}

/** 是否是主 Bot。 */
export function isMainBot(botId: string, mainBotIds: string[]): boolean {
  return mainBotIds.includes(botId);
}

/** 名字是否合法（给独立的重命名入口用）。 */
export function nameProblem(name: string, others: Bot[], selfId: string): string {
  const trimmed = name.trim();
  if (trimmed.length === 0) return '名字不能为空';
  if (trimmed.length > BOT_NAME_MAX) return `名字请控制在 ${BOT_NAME_MAX} 字以内`;
  for (let i = 0; i < others.length; i++) {
    if (others[i].id !== selfId && others[i].name === trimmed) return `名字「${trimmed}」已被使用`;
  }
  return '';
}
