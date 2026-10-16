import { Approval, Avatar, Bot, Conversation, ModelOption, Room, TeamState } from '../model/Models';
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
  return bot;
}

export function toRoom(value: object): Room | undefined {
  const source = asRecord(value);
  const id = text(source, 'id');
  if (id === undefined) return undefined;
  const room: Room = { id: id, name: text(source, 'name') ?? id, members: strings(source, 'members') ?? [] };
  room.admin = text(source, 'admin');
  room.notice = text(source, 'notice');
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
