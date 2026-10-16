import { Attachment, Author, Message, MobileEvent, SystemEvent, ToolActivity } from '../model/Models';

/*
 * Port of the pure functions `mergeMessages` / `applyConversationEvent` from
 * packages/mobile-sdk/index.js (upstream QingJ01/ds-bot-app).
 *
 * ArkTS forbids object spread over interfaces, so every structural merge below is
 * written as an explicit field-by-field copy. The semantics intentionally match the
 * upstream spread order:
 *   non-stale: { ...previous, ...message }  -> `message` wins
 *   stale:     { ...message, ...previous }  -> `previous` wins
 * A field counts as "present" when its value is not `undefined`; frames arriving over
 * the wire are JSON, so absent optional keys are simply missing.
 */

function isFiniteNumber(value: number | undefined): boolean {
  return value !== undefined && Number.isFinite(value);
}

function timestamp(value: number | string): number {
  if (typeof value === 'number') {
    return value;
  }
  return Date.parse(value);
}

function cloneTool(tool: ToolActivity): ToolActivity {
  const out: ToolActivity = {
    callId: tool.callId,
    name: tool.name,
    state: tool.state
  };
  if (tool.durationMs !== undefined) {
    out.durationMs = tool.durationMs;
  }
  if (tool.input !== undefined) {
    out.input = tool.input;
  }
  if (tool.output !== undefined) {
    out.output = tool.output;
  }
  if (tool.isError !== undefined) {
    out.isError = tool.isError;
  }
  if (tool.truncated !== undefined) {
    out.truncated = tool.truncated;
  }
  return out;
}

function cloneSystemEvent(event: SystemEvent): SystemEvent {
  const out: SystemEvent = { kind: event.kind };
  if (event.name !== undefined) {
    out.name = event.name;
  }
  return out;
}

function cloneAttachment(attachment: Attachment): Attachment {
  const out: Attachment = { name: attachment.name };
  if (attachment.id !== undefined) {
    out.id = attachment.id;
  }
  if (attachment.type !== undefined) {
    out.type = attachment.type;
  }
  if (attachment.receiptId !== undefined) {
    out.receiptId = attachment.receiptId;
  }
  if (attachment.mediaType !== undefined) {
    out.mediaType = attachment.mediaType;
  }
  if (attachment.size !== undefined) {
    out.size = attachment.size;
  }
  if (attachment.sessionId !== undefined) {
    out.sessionId = attachment.sessionId;
  }
  return out;
}

export function cloneMessage(message: Message): Message {
  const out: Message = {
    id: message.id,
    sessionId: message.sessionId,
    seq: message.seq,
    role: message.role,
    text: message.text,
    createdAt: message.createdAt
  };
  if (message.reasoning !== undefined) {
    out.reasoning = message.reasoning;
  }
  if (message.interrupted !== undefined) {
    out.interrupted = message.interrupted;
  }
  if (message.pending !== undefined) {
    out.pending = message.pending;
  }
  if (message.tool !== undefined) {
    out.tool = cloneTool(message.tool);
  }
  if (message.turn !== undefined) {
    out.turn = message.turn;
  }
  if (message.step !== undefined) {
    out.step = message.step;
  }
  if (message.requestId !== undefined) {
    out.requestId = message.requestId;
  }
  if (message.updatedSeq !== undefined) {
    out.updatedSeq = message.updatedSeq;
  }
  if (message.streamIndex !== undefined) {
    out.streamIndex = message.streamIndex;
  }
  if (message.attemptId !== undefined) {
    out.attemptId = message.attemptId;
  }
  if (message.systemEvent !== undefined) {
    out.systemEvent = cloneSystemEvent(message.systemEvent);
  }
  if (message.attachments !== undefined) {
    const attachments: Attachment[] = [];
    for (let i = 0; i < message.attachments.length; i++) {
      attachments.push(cloneAttachment(message.attachments[i]));
    }
    out.attachments = attachments;
  }
  if (message.author !== undefined) {
    // 深拷贝：`author` 是对象（`{ id, name }`），浅拷贝会让副本与原消息共享同一引用，
    // 调用方改副本会污染缓存里的消息。2026-10-15 由单测发现。
    const author: Author = {};
    if (message.author.id !== undefined) author.id = message.author.id;
    if (message.author.name !== undefined) author.name = message.author.name;
    out.author = author;
  }
  return out;
}

/** Fills fields that are missing on `out` from the lower-priority `low` message. */
function fillFromLow(out: Message, low: Message): void {
  if (out.reasoning === undefined && low.reasoning !== undefined) {
    out.reasoning = low.reasoning;
  }
  if (out.interrupted === undefined && low.interrupted !== undefined) {
    out.interrupted = low.interrupted;
  }
  if (out.pending === undefined && low.pending !== undefined) {
    out.pending = low.pending;
  }
  if (out.tool === undefined && low.tool !== undefined) {
    out.tool = cloneTool(low.tool);
  }
  if (out.turn === undefined && low.turn !== undefined) {
    out.turn = low.turn;
  }
  if (out.step === undefined && low.step !== undefined) {
    out.step = low.step;
  }
  if (out.requestId === undefined && low.requestId !== undefined) {
    out.requestId = low.requestId;
  }
  if (out.updatedSeq === undefined && low.updatedSeq !== undefined) {
    out.updatedSeq = low.updatedSeq;
  }
  if (out.streamIndex === undefined && low.streamIndex !== undefined) {
    out.streamIndex = low.streamIndex;
  }
  if (out.attemptId === undefined && low.attemptId !== undefined) {
    out.attemptId = low.attemptId;
  }
  if (out.systemEvent === undefined && low.systemEvent !== undefined) {
    out.systemEvent = cloneSystemEvent(low.systemEvent);
  }
  if (out.attachments === undefined && low.attachments !== undefined) {
    const attachments: Attachment[] = [];
    for (let i = 0; i < low.attachments.length; i++) {
      attachments.push(cloneAttachment(low.attachments[i]));
    }
    out.attachments = attachments;
  }
  if (out.author === undefined && low.author !== undefined) {
    out.author = low.author;
  }
}

/** `{ ...low, ...high }` for Message interfaces, without object spread. */
function combineMessages(low: Message | undefined, high: Message): Message {
  const out: Message = cloneMessage(high);
  if (low !== undefined) {
    fillFromLow(out, low);
  }
  return out;
}

/** `{ ...low, ...high }` for ToolActivity interfaces, without object spread. */
function combineTools(low: ToolActivity, high: ToolActivity): ToolActivity {
  const out: ToolActivity = {
    callId: high.callId !== undefined ? high.callId : low.callId,
    name: high.name !== undefined ? high.name : low.name,
    state: high.state !== undefined ? high.state : low.state
  };
  if (high.durationMs !== undefined) {
    out.durationMs = high.durationMs;
  } else if (low.durationMs !== undefined) {
    out.durationMs = low.durationMs;
  }
  if (high.input !== undefined) {
    out.input = high.input;
  } else if (low.input !== undefined) {
    out.input = low.input;
  }
  if (high.output !== undefined) {
    out.output = high.output;
  } else if (low.output !== undefined) {
    out.output = low.output;
  }
  if (high.isError !== undefined) {
    out.isError = high.isError;
  } else if (low.isError !== undefined) {
    out.isError = low.isError;
  }
  if (high.truncated !== undefined) {
    out.truncated = high.truncated;
  } else if (low.truncated !== undefined) {
    out.truncated = low.truncated;
  }
  return out;
}

export function mergeMessages(existing: Message[], incoming: Message[]): Message[] {
  const merged: Map<string, Message> = new Map<string, Message>();
  const all: Message[] = [];
  for (let i = 0; i < existing.length; i++) {
    all.push(existing[i]);
  }
  for (let i = 0; i < incoming.length; i++) {
    all.push(incoming[i]);
  }
  for (let i = 0; i < all.length; i++) {
    const candidate: Message | null | undefined = all[i];
    if (candidate === undefined || candidate === null || typeof candidate.id !== 'string') {
      continue;
    }
    const message: Message = candidate;
    const previous: Message | undefined = merged.get(message.id);
    const previousVersion: number | undefined =
      previous === undefined ? undefined : (previous.updatedSeq !== undefined ? previous.updatedSeq : previous.seq);
    const incomingVersion: number = message.updatedSeq !== undefined ? message.updatedSeq : message.seq;
    const stale: boolean = previous !== undefined && previousVersion !== undefined &&
      Number.isFinite(previousVersion) && Number.isFinite(incomingVersion) && incomingVersion < previousVersion;
    // Spread order: stale keeps the already stored message, otherwise incoming wins.
    const value: Message = stale && previous !== undefined
      ? combineMessages(message, previous)
      : combineMessages(previous, message);
    if (previous !== undefined && previous.tool !== undefined && message.tool !== undefined) {
      const previousTool: ToolActivity = previous.tool;
      const messageTool: ToolActivity = message.tool;
      const mergedTool: ToolActivity = stale
        ? combineTools(messageTool, previousTool)
        : combineTools(previousTool, messageTool);
      value.tool = mergedTool;
      if (mergedTool.name === 'Tool') {
        let known: ToolActivity | undefined = undefined;
        if (previousTool.name !== 'Tool') {
          known = previousTool;
        } else if (messageTool.name !== 'Tool') {
          known = messageTool;
        }
        if (known !== undefined) {
          mergedTool.name = known.name;
          value.text = known.name;
        }
      }
      // A later page may find the call before an already-received result.
      if (isFiniteNumber(previous.seq) && isFiniteNumber(message.seq)) {
        const first: Message = previous.seq <= message.seq ? previous : message;
        value.seq = first.seq;
        value.createdAt = first.createdAt;
      }
    }
    merged.set(message.id, value);
  }
  const result: Message[] = [];
  merged.forEach((value: Message) => {
    result.push(value);
  });
  result.sort((a: Message, b: Message): number => {
    // 本地未确认的乐观消息没有真实 seq，排在有真实顺序的消息之后；
    // 但两个 pending 之间按 createdAt 排序，否则「用户消息」会一直漂在
    // 助手回复下面（上游只在没有真实 seq 时才依赖这个分支）。
    if (Boolean(a.pending) !== Boolean(b.pending)) {
      return a.pending ? 1 : -1;
    }
    if (a.pending === true && b.pending === true) {
      const pendingDifference: number = timestamp(a.createdAt) - timestamp(b.createdAt);
      if (Number.isFinite(pendingDifference) && pendingDifference !== 0) return pendingDifference;
    }
    if (a.sessionId === b.sessionId && isFiniteNumber(a.seq) && isFiniteNumber(b.seq)) {
      return a.seq - b.seq;
    }
    const difference: number = timestamp(a.createdAt) - timestamp(b.createdAt);
    return Number.isFinite(difference) ? difference : 0;
  });
  return result;
}

export function applyConversationEvent(messages: Message[], event: MobileEvent): Message[] {
  if (event.type === 'reset') {
    const kept: Message[] = [];
    for (let i = 0; i < messages.length; i++) {
      if (!messages[i].pending) {
        kept.push(messages[i]);
      }
    }
    const snapshot: Message[] = event.messages !== undefined ? event.messages : [];
    return mergeMessages(kept, snapshot);
  }
  if (event.type === 'delta' && typeof event.attemptId === 'string' && typeof event.text === 'string') {
    const sessionId: string = event.sessionId !== undefined ? event.sessionId : '';
    const attemptId: string = event.attemptId;
    const index: number | undefined = event.index;
    const id: string = 'stream:' + sessionId + ':' + attemptId;
    let previous: Message | undefined = undefined;
    for (let i = 0; i < messages.length; i++) {
      if (messages[i].id === id) {
        previous = messages[i];
        break;
      }
    }
    // Cumulative snapshots can be delivered twice when a transport retries.
    if (previous !== undefined && previous.streamIndex !== undefined && index !== undefined &&
      Number.isFinite(index) && index < previous.streamIndex) {
      return messages;
    }
    const built: Message = {
      id: id,
      sessionId: sessionId,
      seq: Number.MAX_SAFE_INTEGER,
      role: 'assistant',
      text: event.text,
      createdAt: previous !== undefined ? previous.createdAt : Date.now(),
      pending: true,
      attemptId: attemptId
    };
    if (index !== undefined) {
      built.streamIndex = index;
    }
    if (typeof event.reasoning === 'string') {
      built.reasoning = event.reasoning;
    } else if (previous !== undefined && previous.reasoning !== undefined) {
      built.reasoning = previous.reasoning;
    }
    return mergeMessages(messages, [built]);
  }
  if (event.type === 'message' && event.message !== undefined) {
    const incoming: Message = event.message;
    const remaining: Message[] = [];
    for (let i = 0; i < messages.length; i++) {
      const message: Message = messages[i];
      const replaced: boolean = message.pending === true && event.replaceAttemptId !== undefined &&
        message.attemptId === event.replaceAttemptId;
      if (!replaced) {
        remaining.push(message);
      }
    }
    return mergeMessages(remaining, [incoming]);
  }
  if (event.type === 'status' && event.clearAttempt === true) {
    const remaining: Message[] = [];
    for (let i = 0; i < messages.length; i++) {
      const message: Message = messages[i];
      const cleared: boolean = message.pending === true && message.attemptId === event.attemptId;
      if (!cleared) {
        remaining.push(message);
      }
    }
    return remaining;
  }
  return messages;
}
