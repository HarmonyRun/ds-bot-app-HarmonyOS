/**
 * 群聊头像叠加布局 + 主 Bot 判定的纯逻辑（抽自 `Index.ets`，P1 视图拆分）。
 *
 * 为什么值得单独成模块：这几个函数是**纯几何计算与推导**（给定尺寸与成员数返回位置/边长），
 * 却长期埋在 3000 行的页面里，既没法单测也无法复用。抽出来之后：
 * - 位置/边长可以直接写断言（不需要设备）；
 * - `roomAvatar` 只负责把结果画出来，不再自带布局算法。
 *
 * 上游规则（保持不变）：
 * - 最多叠加 4 个成员（超出只显示前 4 个）；
 * - 1 人铺满；2 人各 0.66 倍、对角摆放；3 人及以上 0.54 倍；
 * - 3 人呈「上中 + 左下 + 右下」，4 人为四角；
 * - 群成员列表为空时回退为该团队的第一个 Bot（上游同样如此）。
 */
import { Bot, Conversation, Room, TeamState } from '../model/Models';

/** 头像位置（vp，相对群头像外框左上角）。 */
export interface AvatarOffset {
  x: number;
  y: number;
}

/** 主 Bot id 列表：优先 `mainBotIds`，回退单个 `mainBotId`。 */
export function mainBotIdsOf(team: TeamState): string[] {
  if (team.mainBotIds !== undefined && team.mainBotIds.length > 0) return team.mainBotIds;
  if (team.mainBotId !== undefined && team.mainBotId.length > 0) return [team.mainBotId];
  return [];
}

/** 某个 Bot id 是否主 Bot。 */
export function isMainBotIdOf(team: TeamState, id: string): boolean {
  return mainBotIdsOf(team).includes(id);
}

/** 会话是否指向主 Bot（兼容 `bot:` 前缀的会话 id）。 */
export function isMainConversation(team: TeamState, item: Conversation): boolean {
  const ids = mainBotIdsOf(team);
  return ids.includes(item.id) || ids.some((id: string) => item.id === `bot:${id}`);
}

/** 会话对应的 Bot（兼容带前缀 id 与 sessionId 匹配）。 */
export function botOf(team: TeamState, item: Conversation): Bot | undefined {
  return team.bots.find((bot: Bot) =>
    bot.id === item.id || `bot:${bot.id}` === item.id || bot.sessionId === item.sessionId);
}

/**
 * 群聊成员列表。
 * 先按 Room.members 顺序解析；成员为空时回退为该团队第一个 Bot（上游规则）。
 */
export function roomMembersOf(team: TeamState, item: Conversation): Bot[] {
  const room: Room | undefined = team.rooms.find((value: Room) => value.id === item.id);
  if (room === undefined) return [];
  const members: Bot[] = [];
  for (const id of room.members) {
    const bot = team.bots.find((value: Bot) => value.id === id);
    if (bot !== undefined) members.push(bot);
  }
  if (members.length > 0) return members;
  return team.bots.slice(0, 1);
}

/** 叠加显示几个头像：1 人显示 1 个，最多 4 个。 */
export function memberSlotCount(team: TeamState, item: Conversation): number {
  const count = roomMembersOf(team, item).length;
  if (count <= 1) return 1;
  return count > 4 ? 4 : count;
}

/** 叠加头像的边长。 */
export function memberSlotSize(team: TeamState, item: Conversation, size: number): number {
  const count = memberSlotCount(team, item);
  if (count <= 1) return size;
  if (count === 2) return size * 0.66;
  return size * 0.54;
}

/** 第 index 个头像的位置。 */
export function memberSlotOffset(team: TeamState, item: Conversation, index: number, size: number): AvatarOffset {
  const count = memberSlotCount(team, item);
  const inner = memberSlotSize(team, item, size);
  if (count <= 1) return { x: 0, y: 0 };
  if (count === 2) {
    return index === 0 ? { x: 0, y: 0 } : { x: size - inner, y: size - inner };
  }
  if (count === 3) {
    if (index === 0) return { x: size * 0.23, y: 0 };
    if (index === 1) return { x: 0, y: size - inner };
    return { x: size - inner, y: size - inner };
  }
  if (index === 0) return { x: 0, y: 0 };
  if (index === 1) return { x: size - inner, y: 0 };
  if (index === 2) return { x: 0, y: size - inner };
  return { x: size - inner, y: size - inner };
}

/** 会话头像是否应显示主 Bot 星标。 */
export function isMainAvatar(team: TeamState, item: Conversation): boolean {
  const bot = botOf(team, item);
  return bot !== undefined ? isMainBotIdOf(team, bot.id) : isMainConversation(team, item);
}
