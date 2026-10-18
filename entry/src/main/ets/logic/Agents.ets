import { Conversation } from '../model/Models';

/**
 * Agent 管理的**纯逻辑**（P2-9）。
 *
 * DSH Agent 与 Bot 不同：它**每个团队最多一个**，且可以有多个会话（sessions）。
 * 宿主把每个 Agent 会话当成一条 `kind: 'agent'` 的会话下发，
 * 所以界面上「Agent 的会话列表」= 本地会话里 kind 为 agent 的那些。
 *
 * 抽出来的原因：标题校验、按 agentId 过滤、以及"能不能再建一个"的判断
 * 都是错了会直接报错或被主机拒绝的地方。
 */

/** 会话标题长度上限（宿主会 trim，这里提前提示）。 */
export const AGENT_TITLE_MAX = 60;

/** 该会话是否是 Agent 会话。 */
export function isAgentConversation(conversation: Conversation): boolean {
  return conversation.kind === 'agent';
}

/**
 * 取出所有 Agent 会话。
 *
 * 同时返回出现的 agentId 去重列表——界面用它判断"团队是否已有 Agent"，
 * 不依赖额外的 state 字段（宿主 state 的 `agents` 我们没投影）。
 */
export interface AgentGroups {
  agentIds: string[];
  conversations: Conversation[];
}

export function groupAgentConversations(all: Conversation[]): AgentGroups {
  const conversations: Conversation[] = [];
  const agentIds: string[] = [];
  for (let i = 0; i < all.length; i++) {
    const item = all[i];
    if (!isAgentConversation(item)) continue;
    conversations.push(item);
    const agentId = item.agentId ?? '';
    if (agentId.length > 0 && !agentIds.includes(agentId)) agentIds.push(agentId);
  }
  return { agentIds: agentIds, conversations: conversations };
}

/** 校验会话标题。 */
export function titleProblem(title: string): string {
  const trimmed = title.trim();
  if (trimmed.length === 0) return '标题不能为空';
  if (trimmed.length > AGENT_TITLE_MAX) return `标题请控制在 ${AGENT_TITLE_MAX} 字以内`;
  return '';
}

/** 能否创建 Agent：团队已有则不能再建。 */
export function canAddAgent(agentIds: string[]): boolean {
  return agentIds.length === 0;
}

/** 不能创建时的说明。 */
export function addAgentBlockedReason(agentIds: string[]): string {
  if (agentIds.length === 0) return '';
  return '每个团队只能有一个 DSH Agent。';
}

/** 归档确认文案。 */
export function archivePrompt(conversation: Conversation): string {
  return `将归档「${conversation.name}」。归档后它会从 Agent 的会话列表里移除。`;
}

/** 移除 Agent 的确认文案。 */
export function removePrompt(agentIds: string[]): string {
  return agentIds.length === 0
    ? '团队还没有 DSH Agent。'
    : '将移除这个 DSH Agent。它名下的会话会被归档。';
}
