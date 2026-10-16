import { Conversation, Question, QuestionOption, TeamState } from '../model/Models';

export interface ConversationQuestion {
  sessionId: string;
  question: Question;
}

function recordOf(value: Object): Record<string, Object> | undefined {
  if (value === null || typeof value !== 'object' || Array.isArray(value)) return undefined;
  return value as Record<string, Object>;
}

function stringOf(source: Record<string, Object>, key: string): string | undefined {
  const value = source[key];
  return typeof value === 'string' ? value : undefined;
}

function booleanOf(source: Record<string, Object>, key: string): boolean | undefined {
  const value = source[key];
  return typeof value === 'boolean' ? value : undefined;
}

function optionOf(value: Object): QuestionOption | undefined {
  if (typeof value === 'string') return { label: value };
  const source = recordOf(value);
  if (source === undefined) return undefined;
  const label = stringOf(source, 'label') ?? stringOf(source, 'value');
  if (label === undefined || label.length === 0) return undefined;
  const option: QuestionOption = { label: label };
  option.value = stringOf(source, 'value');
  option.description = stringOf(source, 'description');
  return option;
}

function questionOf(value: Object, fallbackSessionId: string): Question | undefined {
  const source = recordOf(value);
  if (source === undefined) return undefined;
  const id = stringOf(source, 'id');
  if (id === undefined || id.length === 0) return undefined;
  const options: QuestionOption[] = [];
  const rawOptions = source['options'];
  if (Array.isArray(rawOptions)) {
    for (const raw of rawOptions as Object[]) {
      const option = optionOf(raw);
      if (option !== undefined) options.push(option);
    }
  }
  const question: Question = { id: id, options: options };
  question.sessionId = stringOf(source, 'sessionId') ?? fallbackSessionId;
  question.conversationId = stringOf(source, 'conversationId');
  question.question = stringOf(source, 'question');
  question.prompt = stringOf(source, 'prompt');
  question.text = stringOf(source, 'text');
  question.header = stringOf(source, 'header');
  question.detail = stringOf(source, 'detail');
  question.multiSelect = booleanOf(source, 'multiSelect');
  question.allowCustom = booleanOf(source, 'allowCustom');
  return question;
}

/** 把 `/state.questions` 的动态 sessionId 键投影成 ArkTS 强类型。 */
export function toQuestions(value: object | undefined): Record<string, Question> {
  const result: Record<string, Question> = {};
  if (value === undefined || value === null || typeof value !== 'object' || Array.isArray(value)) return result;
  const source = value as Record<string, Object>;
  for (const sessionId of Object.keys(source)) {
    const question = questionOf(source[sessionId], sessionId);
    if (question !== undefined) result[sessionId] = question;
  }
  return result;
}

/** 与上游 ChatScreen 相同的归属规则：conversationId 优先，旧主机回退 sessionId。 */
export function questionsForConversation(team: TeamState, conversation: Conversation | undefined): ConversationQuestion[] {
  if (conversation === undefined) return [];
  const bot = team.bots.find(item => item.id === conversation.id || `bot:${item.id}` === conversation.id ||
    item.sessionId === conversation.sessionId);
  const room = team.rooms.find(item => item.id === conversation.id || `room:${item.id}` === conversation.id);
  const ownerIds: string[] = [conversation.id];
  if (bot !== undefined) ownerIds.push(bot.id);
  if (room !== undefined) ownerIds.push(room.id);
  const rows: ConversationQuestion[] = [];
  const questions = team.questions ?? {};
  for (const sessionId of Object.keys(questions)) {
    const question = questions[sessionId];
    const belongs = question.conversationId !== undefined ? ownerIds.includes(question.conversationId) :
      (question.sessionId ?? sessionId) === conversation.sessionId;
    if (belongs) rows.push({ sessionId: question.sessionId ?? sessionId, question: question });
  }
  return rows;
}
