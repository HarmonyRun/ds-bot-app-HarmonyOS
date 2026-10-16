import {
  BotWork,
  MemberWork,
  RoomRound,
  RoundReply,
  TeamWork,
  WorkApproval
} from '../model/Models';

function recordOf(value: Object): Record<string, Object> | undefined {
  if (value === null || typeof value !== 'object' || Array.isArray(value)) return undefined;
  return value as Record<string, Object>;
}

function text(source: Record<string, Object>, key: string): string | undefined {
  const value = source[key];
  return typeof value === 'string' ? value : undefined;
}

function numberValue(source: Record<string, Object>, key: string): number | undefined {
  const value = source[key];
  return typeof value === 'number' && Number.isFinite(value) ? value : undefined;
}

function flag(source: Record<string, Object>, key: string): boolean | undefined {
  const value = source[key];
  return typeof value === 'boolean' ? value : undefined;
}

function toMemberWork(value: Object): MemberWork | undefined {
  const source = recordOf(value);
  if (source === undefined) return undefined;
  const botId = text(source, 'botId');
  if (botId === undefined || botId.length === 0) return undefined;
  const work: MemberWork = { botId: botId };
  work.since = numberValue(source, 'since');
  work.tool = text(source, 'tool');
  work.speaking = flag(source, 'speaking');
  return work;
}

function toBotWork(value: Object): BotWork | undefined {
  const source = recordOf(value);
  if (source === undefined) return undefined;
  const work: BotWork = {};
  work.since = numberValue(source, 'since');
  work.tool = text(source, 'tool');
  work.roomId = text(source, 'roomId');
  work.speaking = flag(source, 'speaking');
  return work;
}

function toWorkApproval(value: Object): WorkApproval | undefined {
  const source = recordOf(value);
  if (source === undefined) return undefined;
  const id = text(source, 'id');
  const botId = text(source, 'botId');
  if (id === undefined || botId === undefined) return undefined;
  const approval: WorkApproval = { id: id, botId: botId };
  approval.roomId = text(source, 'roomId');
  approval.sessionId = text(source, 'sessionId');
  approval.answerable = flag(source, 'answerable');
  return approval;
}

/** 把 `/state.work` 的松散 JSON 收口为界面可安全使用的结构。 */
export function toTeamWork(value: object | undefined): TeamWork | undefined {
  if (value === undefined) return undefined;
  const source = recordOf(value);
  if (source === undefined) return undefined;
  const result: TeamWork = { bots: {}, rooms: {}, approvals: [] };

  const rawBots = recordOf(source['bots']);
  if (rawBots !== undefined) {
    for (const id of Object.keys(rawBots)) {
      const work = toBotWork(rawBots[id]);
      if (work !== undefined) result.bots[id] = work;
    }
  }

  const rawRooms = recordOf(source['rooms']);
  if (rawRooms !== undefined) {
    for (const roomId of Object.keys(rawRooms)) {
      const rawMembers = rawRooms[roomId];
      if (!Array.isArray(rawMembers)) continue;
      const members: MemberWork[] = [];
      for (const rawMember of rawMembers as Object[]) {
        const member = toMemberWork(rawMember);
        if (member !== undefined) members.push(member);
      }
      result.rooms[roomId] = members;
    }
  }

  const rawApprovals = source['approvals'];
  if (Array.isArray(rawApprovals)) {
    for (const rawApproval of rawApprovals as Object[]) {
      const approval = toWorkApproval(rawApproval);
      if (approval !== undefined) result.approvals.push(approval);
    }
  }
  return result;
}

function toReply(value: Object): RoundReply | undefined {
  const source = recordOf(value);
  if (source === undefined) return undefined;
  const botId = text(source, 'botId');
  if (botId === undefined) return undefined;
  const reply: RoundReply = { botId: botId };
  reply.kind = text(source, 'kind');
  return reply;
}

/** 过滤 `room-progress` 中缺少 callId/replies 的畸形轮次。 */
export function toRoomRounds(value: Object): RoomRound[] {
  if (!Array.isArray(value)) return [];
  const rounds: RoomRound[] = [];
  for (const rawRound of value as Object[]) {
    const source = recordOf(rawRound);
    if (source === undefined || !Array.isArray(source['replies'])) continue;
    const callId = text(source, 'callId');
    if (callId === undefined) continue;
    const replies: RoundReply[] = [];
    for (const rawReply of source['replies'] as Object[]) {
      const reply = toReply(rawReply);
      if (reply !== undefined) replies.push(reply);
    }
    const round: RoomRound = { callId: callId, replies: replies };
    const speaking = source['speaking'];
    if (typeof speaking === 'string') round.speaking = speaking;
    rounds.push(round);
  }
  return rounds;
}

export function memberWork(teamWork: TeamWork | undefined, roomId: string, botId: string): MemberWork | BotWork | undefined {
  const roomWork = teamWork?.rooms[roomId]?.find((item: MemberWork) => item.botId === botId);
  if (roomWork !== undefined) return roomWork;
  const botWork = teamWork?.bots[botId];
  return botWork?.roomId === roomId ? botWork : undefined;
}

export function memberWaits(teamWork: TeamWork | undefined, roomId: string, botId: string): boolean {
  return teamWork?.approvals.some((item: WorkApproval) => item.roomId === roomId && item.botId === botId) ?? false;
}

export interface MemberProgress {
  status: string;
  speaking: boolean;
  failed: boolean;
  working: boolean;
}

/** 与上游 GroupProgress 相同的状态优先级：审批 > 输入 > 失败/查找/回复 > 工作中。 */
export function memberProgress(botId: string, roomId: string, rounds: RoomRound[], teamWork: TeamWork | undefined): MemberProgress {
  let speaking = false;
  let latest: RoundReply | undefined = undefined;
  for (const round of rounds) {
    if (round.speaking === botId) speaking = true;
    for (const reply of round.replies) {
      if (reply.botId === botId) latest = reply;
    }
  }
  const doing = memberWork(teamWork, roomId, botId);
  if (doing?.speaking === true) speaking = true;
  const waiting = memberWaits(teamWork, roomId, botId);
  let status = '';
  if (waiting) status = '等待审批';
  else if (speaking) status = '正在输入…';
  else if (latest?.kind === 'failed') status = '未能回答';
  else if (latest?.kind === 'lookup') status = '正在回看聊天';
  else if (latest !== undefined) status = '已回复';
  else if (doing !== undefined) status = '工作中';
  return { status: status, speaking: speaking, failed: latest?.kind === 'failed' && !speaking, working: doing !== undefined };
}

export function busyMemberIds(memberIds: string[], roomId: string, teamWork: TeamWork | undefined): string[] {
  return memberIds.filter((id: string) => memberWork(teamWork, roomId, id) !== undefined || memberWaits(teamWork, roomId, id));
}
