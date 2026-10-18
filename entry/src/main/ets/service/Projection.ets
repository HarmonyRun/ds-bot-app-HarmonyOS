import { Capability, CapabilityStatus, Connector, Approval, Avatar, Bot, Conversation, ModelOption, Room, TeamState } from '../model/Models';
import { RawApprovalList, RawConversationList, RawDeviceList, RawServerInfo, RawState } from './MobileClient';
import { DeviceListItem } from '../model/Models';
import { toQuestions } from '../logic/Questions';
import { toTeamWork } from '../logic/GroupProgress';

/**
 * 把传输层的原始 JSON（`RawState` / `RawConversationList` …）投影成界面用的强类型模型。
 *
 * 为什么需要这一层：
 * - ArkTS **不支持结构类型**（arkts-no-structural-typing），`object` / `Record` 不能直接赋给
 *   `Bot` / `Conversation` 这类 interface，必须显式构造；
 * - 主机返回的字段比界面需要的多（`input`、`provider`、`contextWindow`…），逐字段挑选可以
 *   让「主机协议变化」只影响这一个文件。
 *
 * 约定：所有函数都对缺字段容错，返回 `undefined` 表示该条目不可用（由调用方过滤）。
 */

function text(source: Record<string, Object>, key: string): string | undefined {
  const value = source[key];
  return typeof value === 'string' ? value : undefined;
}

function flag(source: Record<string, Object>, key: string): boolean | undefined {
  const value = source[key];
  return typeof value === 'boolean' ? value : undefined;
}

function stamp(source: Record<string, Object>, key: string): number | string | undefined {
  const value = source[key];
  if (typeof value === 'number' || typeof value === 'string') return value;
  return undefined;
}

function strings(source: Record<string, Object>, key: string): string[] | undefined {
  const value = source[key];
  if (!Array.isArray(value)) return undefined;
  const items = value as Object[];
  const result: string[] = [];
  for (const item of items) {
    if (typeof item === 'string') result.push(item);
  }
  return result;
}

function avatarOf(source: Record<string, Object>): Avatar | undefined {
  const raw = source['avatar'];
  if (raw === undefined || raw === null || typeof raw !== 'object') return undefined;
  const value: Record<string, Object> = raw as Record<string, Object>;
  const avatar: Avatar = {};
  const shape = text(value, 'shape');
  const image = text(value, 'image');
  const color = text(value, 'color');
  if (shape !== undefined) avatar.shape = shape;
  if (image !== undefined) avatar.image = image;
  if (color !== undefined) avatar.color = color;
  return avatar;
}

function asRecord(value: object): Record<string, Object> {
  const record: Record<string, Object> = value as Record<string, Object>;
  return record;
}

export function toBot(value: object): Bot | undefined {
  const source = asRecord(value);
  const id = text(source, 'id');
  if (id === undefined) return undefined;
  const bot: Bot = { id: id, name: text(source, 'name') ?? id };
  bot.role = text(source, 'role');
  bot.color = text(source, 'color');
  bot.instructions = text(source, 'instructions');
  bot.model = text(source, 'model');
  bot.effort = text(source, 'effort');
  bot.sessionId = text(source, 'sessionId');
  bot.waiting = flag(source, 'waiting');
  bot.avatar = avatarOf(source);
  bot.workDir = text(source, 'workDir');
  bot.pinned = flag(source, 'pinned');
  bot.hidden = flag(source, 'hidden');
  bot.capabilities = strings(source, 'capabilities');
  return bot;
}

export function toRoom(value: object): Room | undefined {
  const source = asRecord(value);
  const id = text(source, 'id');
  if (id === undefined) return undefined;
  const room: Room = { id: id, name: text(source, 'name') ?? id, members: strings(source, 'members') ?? [] };
  room.admin = text(source, 'admin');
  room.notice = text(source, 'notice');
  room.mode = text(source, 'mode');
  room.pinned = flag(source, 'pinned');
  room.hidden = flag(source, 'hidden');
  return room;
}

function toModel(value: object): ModelOption | undefined {
  const source = asRecord(value);
  const ref = text(source, 'ref');
  if (ref === undefined) return undefined;
  const model: ModelOption = { ref: ref, name: text(source, 'name') ?? ref };
  model.providerName = text(source, 'providerName');
  return model;
}

export function toConversation(value: object): Conversation | undefined {
  const source = asRecord(value);
  const id = text(source, 'id');
  if (id === undefined) return undefined;
  const conversation: Conversation = {
    id: id,
    kind: text(source, 'kind') ?? 'bot',
    name: text(source, 'name') ?? id,
    sessionId: text(source, 'sessionId') ?? ''
  };
  conversation.role = text(source, 'role');
  const waiting = source['waiting'];
  if (typeof waiting === 'string') conversation.waiting = waiting;
  else if (waiting === true) conversation.waiting = 'waiting';
  conversation.pinned = flag(source, 'pinned');
  conversation.hidden = flag(source, 'hidden');
  conversation.updatedAt = stamp(source, 'updatedAt');
  conversation.agentId = text(source, 'agentId');
  conversation.mode = text(source, 'mode');
  conversation.notice = text(source, 'notice');
  conversation.admin = text(source, 'admin');
  conversation.parts = strings(source, 'parts');
  return conversation;
}

export function toTeamState(raw: RawState): TeamState {
  const bots: Bot[] = [];
  for (const value of raw.bots ?? []) {
    const bot = toBot(value);
    if (bot !== undefined) bots.push(bot);
  }
  const rooms: Room[] = [];
  for (const value of raw.rooms ?? []) {
    const room = toRoom(value);
    if (room !== undefined) rooms.push(room);
  }
  const models: ModelOption[] = [];
  for (const value of raw.models ?? []) {
    const model = toModel(value);
    if (model !== undefined) models.push(model);
  }
  const state: TeamState = { bots: bots, rooms: rooms, models: models };
  state.capabilities = toCapabilities(raw.capabilities);
  state.connectors = toConnectors(raw.connectors);
  state.capabilityStatuses = toCapabilityStatuses(raw.capabilityStatuses);
  state.mainBotId = raw.mainBotId;
  state.mainBotIds = raw.mainBotIds;
  state.questions = toQuestions(raw.questions);
  state.work = toTeamWork(raw.work);
  // 上游可返回 null；界面统一用 undefined 表示可写，避免 null 被误判成只读。
  state.readOnly = typeof raw.readOnly === 'string' ? raw.readOnly : undefined;
  return state;
}

export function toConversations(raw: RawConversationList): Conversation[] {
  const result: Conversation[] = [];
  for (const value of raw.conversations) {
    const conversation = toConversation(value);
    if (conversation !== undefined) result.push(conversation);
  }
  return result;
}

/**
 * 解析能力库（P2-7）。
 *
 * 只保留宿主认可的三种 `kind`，并丢掉没有名字的条目——
 * 名字是后续「挂载 / 卸载」的唯一键，缺了就没法操作。
 */
/**
 * 解析连接器列表。
 *
 * 宿主结构是 `{ id, name, state, account, error? }`；
 * 没有 `id` 的条目直接丢弃（后续 connect/disconnect 都要用它当键）。
 */
export function toConnectors(raw: object[] | undefined): Connector[] {
  const result: Connector[] = [];
  if (raw === undefined) return result;
  for (let i = 0; i < raw.length; i++) {
    const source = asRecord(raw[i]);
    const id = text(source, 'id');
    if (id === undefined) continue;
    const connector: Connector = {
      id: id,
      name: text(source, 'name') ?? id,
      state: text(source, 'state') ?? 'off'
    };
    const account = source['account'];
    connector.account = typeof account === 'string' ? account : null;
    connector.error = text(source, 'error');
    result.push(connector);
  }
  return result;
}

export function toCapabilities(raw: object[] | undefined): Capability[] {
  const result: Capability[] = [];
  if (raw === undefined) return result;
  for (let i = 0; i < raw.length; i++) {
    const source = asRecord(raw[i]);
    const name = text(source, 'name');
    const kind = text(source, 'kind');
    if (name === undefined || kind === undefined) continue;
    if (kind !== 'mcp' && kind !== 'skill' && kind !== 'pack') continue;
    const capability: Capability = { name: name, kind: kind };
    capability.description = text(source, 'description');
    capability.transport = text(source, 'transport');
    capability.approved = flag(source, 'approved');
    capability.items = strings(source, 'items');
    result.push(capability);
  }
  return result;
}

/**
 * 解析「每个 Bot 上每个能力的运行状态」。
 *
 * 宿主结构是 `botId → 能力名 → { state, error }`；
 * ArkTS 不允许索引签名，因此这里显式遍历两层 `Record` 并重建，
 * 同时过滤掉不认识的 state（避免 UI 显示未知状态）。
 */
export function toCapabilityStatuses(
  raw: Record<string, Object> | undefined): Record<string, Record<string, CapabilityStatus>> {
  const result: Record<string, Record<string, CapabilityStatus>> = {};
  if (raw === undefined) return result;
  const botIds = Object.keys(raw);
  for (let i = 0; i < botIds.length; i++) {
    const botId = botIds[i];
    const inner = raw[botId];
    if (inner === null || typeof inner !== 'object') continue;
    const statuses = asRecord(inner as object);
    const names = Object.keys(statuses);
    const entry: Record<string, CapabilityStatus> = {};
    for (let j = 0; j < names.length; j++) {
      const name = names[j];
      const value = statuses[name];
      if (value === null || typeof value !== 'object') continue;
      const source = asRecord(value as object);
      const state = text(source, 'state');
      if (state === undefined) continue;
      if (state !== 'ready' && state !== 'connecting' && state !== 'needs-approval' && state !== 'error') continue;
      const status: CapabilityStatus = { state: state };
      status.error = text(source, 'error');
      entry[name] = status;
    }
    result[botId] = entry;
  }
  return result;
}

export function toDeviceList(raw: RawDeviceList): DeviceListItem[] {
  const result: DeviceListItem[] = [];
  for (const value of raw.devices) {
    const source = asRecord(value);
    const id = text(source, 'id');
    if (id === undefined) continue;
    const device: DeviceListItem = { id: id };
    device.name = text(source, 'name');
    device.deviceName = text(source, 'deviceName');
    result.push(device);
  }
  return result;
}

/** `/info` 的展示名，缺省给一个可读值。 */
export function serverNameOf(info: RawServerInfo): string {
  const name = info.name;
  return name === undefined || name.length === 0 ? 'DSH 主机' : name;
}

/** `/actions approvals` 的投影。 */
export function toApprovals(raw: RawApprovalList): Approval[] {
  const result: Approval[] = [];
  for (const value of raw.requests) {
    const source = asRecord(value);
    const id = text(source, 'id');
    if (id === undefined) continue;
    const approval: Approval = {
      id: id,
      conversationId: text(source, 'conversationId') ?? '',
      sessionId: text(source, 'sessionId') ?? '',
      toolName: text(source, 'toolName') ?? '工具操作'
    };
    approval.reason = text(source, 'reason');
    approval.callId = text(source, 'callId');
    const createdAt = source['createdAt'];
    if (typeof createdAt === 'number') approval.createdAt = createdAt;
    approval.answerable = flag(source, 'answerable');
    result.push(approval);
  }
  return result;
}
