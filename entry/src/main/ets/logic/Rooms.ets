import { Bot, Room, RoomPatch } from '../model/Models';

/**
 * 群聊管理的**纯逻辑**（P2-6）。
 *
 * 这里处理三件容易出错的事：
 * 1. 编辑前后的**成员差异**（宿主接受全量 `members`，但"没有变化就别提交"）；
 * 2. 表单校验（名字长度、管理员必须是成员）；
 * 3. 把宿主的 `changes[]` 翻成中文。
 *
 * 抽出来的原因：成员集合运算与管理员约束是"错了会静默删人"的地方，
 * 必须能脱离设备验证。
 */

/** 群聊模式。 */
export type RoomMode = 'admin' | 'everyone';

/** 编辑表单。 */
export interface RoomForm {
  id: string;
  name: string;
  notice: string;
  mode: RoomMode;
  admin: string;
  members: string[];
}

/** 校验结果。 */
export interface RoomValidation {
  ok: boolean;
  error: string;
}

/** 群名长度上限（与宿主保持一致的习惯值）。 */
export const ROOM_NAME_MAX = 60;

/**
 * 校验群聊表单。
 *
 * 关键约束：**管理员必须是成员**——
 * 宿主允许把非成员设为管理员，但那样「everyone 模式下先问管理员」会指向一个不在群里的人。
 */
export function validateRoomForm(form: RoomForm): RoomValidation {
  const name = form.name.trim();
  if (name.length === 0) return { ok: false, error: '群名不能为空' };
  if (name.length > ROOM_NAME_MAX) return { ok: false, error: `群名请控制在 ${ROOM_NAME_MAX} 字以内` };
  if (form.members.length === 0) return { ok: false, error: '至少保留一个成员' };
  if (form.admin.length > 0 && !form.members.includes(form.admin)) {
    return { ok: false, error: '管理员必须在成员里' };
  }
  return { ok: true, error: '' };
}

/** 由 Room 生成表单。 */
export function formOfRoom(room: Room): RoomForm {
  return {
    id: room.id,
    name: room.name,
    notice: room.notice ?? '',
    mode: room.mode === 'everyone' ? 'everyone' : 'admin',
    admin: room.admin ?? '',
    members: room.members ?? []
  };
}

/** 比较两份成员列表：返回新增与移除。 */
export interface MemberDiff {
  added: string[];
  removed: string[];
}

export function diffMembers(before: string[], after: string[]): MemberDiff {
  const added: string[] = [];
  const removed: string[] = [];
  for (let i = 0; i < after.length; i++) {
    if (!before.includes(after[i])) added.push(after[i]);
  }
  for (let i = 0; i < before.length; i++) {
    if (!after.includes(before[i])) removed.push(before[i]);
  }
  return { added: added, removed: removed };
}

/**
 * 生成 `update-room` 的载荷。
 *
 * 只带**真正变化**的字段：宿主会用"字段是否出现"判断要不要改，
 * 全量提交会把没动过的字段也写一遍（并产生多余的变更记录）。
 * 没有变化时返回 `undefined`，调用方可直接跳过请求。
 */
export function buildRoomPatch(before: Room, form: RoomForm): RoomPatch | undefined {
  const patch = new RoomPatch(before.id);
  let dirty = false;

  const name = form.name.trim();
  if (name !== before.name) {
    patch.name = name;
    dirty = true;
  }
  const notice = form.notice.trim();
  if (notice !== (before.notice ?? '')) {
    patch.notice = notice;
    dirty = true;
  }
  const mode = form.mode;
  if (mode !== (before.mode === 'everyone' ? 'everyone' : 'admin')) {
    patch.mode = mode;
    dirty = true;
  }
  const admin = form.admin;
  if (admin !== (before.admin ?? '')) {
    patch.admin = admin;
    dirty = true;
  }
  const diff = diffMembers(before.members ?? [], form.members);
  if (diff.added.length > 0 || diff.removed.length > 0) {
    patch.members = form.members;
    dirty = true;
  }
  return dirty ? patch : undefined;
}

/** 模式的展示文案。 */
export function describeMode(mode: string | undefined): string {
  return mode === 'everyone' ? '成员轮流回答' : '管理员先回答';
}

/** 把宿主的英文变更说明翻成中文（未收录的原样返回）。 */
export function translateChanges(changes: string[] | undefined): string[] {
  const result: string[] = [];
  if (changes === undefined) return result;
  for (let i = 0; i < changes.length; i++) {
    const text = changes[i];
    if (text.includes('plain messages now go to the admin first')) result.push('消息改为先交给管理员');
    else if (text.includes('every member now replies in turn')) result.push('改为成员轮流回答');
    else if (text.includes('name')) result.push('群名已更新');
    else if (text.includes('notice')) result.push('公告已更新');
    else if (text.includes('member')) result.push('成员已更新');
    else if (text.includes('admin')) result.push('管理员已更新');
    else result.push(text);
  }
  return result;
}

/** Bot id → 显示名（成员列表渲染用）。 */
export function botNameOf(bots: Bot[], id: string): string {
  for (let i = 0; i < bots.length; i++) {
    if (bots[i].id === id) return bots[i].name;
  }
  return id;
}
