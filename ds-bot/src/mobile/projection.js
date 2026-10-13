const textOf = content => (Array.isArray(content) ? content : []).filter(block => block?.type === 'text').map(block => block.text ?? '').join('\n')
const reasoningOf = content => (Array.isArray(content) ? content : []).filter(block => block?.type === 'reasoning').map(block => block.text ?? '').join('\n')
const privateKey = /token|password|passwd|secret|api[_-]?key|authorization|cookie|credential|private[_-]?key/i
const INTERNAL_TOOLS = new Set(['group_relay'])

function cleanObject(value, state, depth = 0) {
  if (depth > 8) { state.truncated = true; return '[Nested detail omitted]' }
  if (Array.isArray(value)) {
    if (value.length > 100) state.truncated = true
    return value.slice(0, 100).map(item => cleanObject(item, state, depth + 1))
  }
  if (!value || typeof value !== 'object') return value
  const entries = Object.entries(value)
  if (entries.length > 100) state.truncated = true
  return Object.fromEntries(entries.slice(0, 100).map(([key, item]) => [key, privateKey.test(key) ? '[redacted]' : cleanObject(item, state, depth + 1)]))
}

export function detail(value, limit, redact = text => text) {
  let parsed = value
  if (typeof value === 'string') { try { parsed = JSON.parse(value) } catch {} }
  const state = { truncated: false }
  const safe = typeof parsed === 'object' && parsed !== null ? JSON.stringify(cleanObject(parsed, state), null, 2) : String(parsed ?? '')
  const cleaned = String(redact(safe))
    .replace(/-----BEGIN [^-]*PRIVATE KEY-----[\s\S]*?-----END [^-]*PRIVATE KEY-----/g, '[Private key omitted]')
    .replace(/\b(Bearer|Basic)\s+[A-Za-z0-9+/_.=-]+/gi, '$1 [redacted]')
    .replace(/\b((?:api[_-]?key|access[_-]?token|refresh[_-]?token|password|passwd|secret|authorization|cookie)\s*[:=]\s*)(?:"[^"\n]*"|'[^'\n]*'|[^\s,;&]+)/gi, '$1[redacted]')
  return { text: cleaned.length > limit ? `${cleaned.slice(0, limit)}\n[Detail truncated]` : cleaned, truncated: state.truncated || cleaned.length > limit }
}

function storedCall(value) {
  if (typeof value === 'string') return { name: value }
  const event = value?.event ?? value
  return event?.data ? { ...event.data, seq: event.seq, time: event.time, hidden: event.hidden } : event
}

const attachmentsOf = (content, redact = text => text) => (Array.isArray(content) ? content : []).flatMap(block => {
  const ref = block?.type === 'image' || block?.type === 'file' ? block.attachment : undefined
  if (typeof ref?.attachmentId !== 'string') return []
  return [{ id: ref.attachmentId, type: block.type, name: String(redact(ref.name ?? (block.type === 'image' ? 'Image' : 'File'))), size: ref.bytes,
    ...(ref.mediaType ? { mediaType: ref.mediaType } : {}), ...(ref.width ? { width: ref.width, height: ref.height } : {}) }]
})

// The mobile transcript retains append-origin conversation messages. Compaction
// replacements are model context, not new messages from the user or the Bot.
export function projectEvent(event, { sessionId, kind = 'bot', hiddenTurns = [], calls = new Map(), redact } = {}) {
  if (!event || !Number.isSafeInteger(event.seq)) return []
  const data = event.data ?? {}
  const visible = value => typeof redact === 'function' ? String(redact(value)) : value
  if (event.type === 'tool/call') {
    calls.set(data.callId, { ...event, hidden: hiddenTurns.includes(data.turn) })
  }
  if (typeof event.surfaceOp === 'object' && event.surfaceOp?.op === 'replace') return []
  if (hiddenTurns.includes(data.turn)) return []
  const base = { id: `${sessionId}:${event.seq}`, sessionId, seq: event.seq, createdAt: event.time ?? 0 }
  if (event.type === 'tool/result' && kind === 'room') {
    const callId = data.message?.source?.callId ?? data.message?.toolCallId
    const call = storedCall(calls.get(callId))
    if (call?.name !== 'group_relay' || call.hidden || hiddenTurns.includes(call.turn)) return []
    let result
    try { result = JSON.parse(textOf(data.message?.content)) } catch { return [] }
    return (Array.isArray(result?.replies) ? result.replies : []).flatMap((reply, index) => {
      if (typeof reply?.text !== 'string' || reply.text === '') return []
      return [{ ...base, id: `${base.id}:reply:${index}`, role: reply.kind ? 'system' : 'assistant', text: visible(reply.text),
        createdAt: reply.time ?? base.createdAt, author: { id: reply.botId ?? '', name: visible(reply.name ?? 'Bot') } }]
    })
  }
  if (event.type === 'tool/call' || event.type === 'tool/result') {
    if (kind === 'room') return []
    const callId = data.callId ?? data.message?.source?.callId ?? data.message?.toolCallId
    if (typeof callId !== 'string' || !callId) return []
    const call = storedCall(calls.get(callId))
    if (call?.hidden || hiddenTurns.includes(call?.turn) || INTERNAL_TOOLS.has(call?.name)) return []
    const name = typeof call?.name === 'string' ? call.name : 'Tool'
    const sensitive = privateKey.test(name)
    const input = detail(sensitive ? '[Sensitive tool details omitted]' : call?.arguments ?? '', 6000, redact)
    const completed = event.type === 'tool/result'
    const output = completed ? detail(sensitive ? '[Sensitive tool details omitted]' : textOf(data.message?.content), 12000, redact) : undefined
    return [{ ...base, id: `${sessionId}:tool:${callId}`, seq: Number.isSafeInteger(call?.seq) ? call.seq : event.seq,
      createdAt: call?.time ?? base.createdAt, updatedSeq: event.seq, role: 'tool', text: name,
      ...(Number.isInteger(data.turn) ? { turn: data.turn } : {}), ...(Number.isInteger(data.step) ? { step: data.step } : {}),
      tool: { callId, name, ...(completed && Number.isFinite(new Date(call?.time).getTime()) && Number.isFinite(new Date(event.time).getTime()) && new Date(event.time).getTime() >= new Date(call.time).getTime() ? { durationMs: new Date(event.time).getTime() - new Date(call.time).getTime() } : {}), state: completed ? data.message?.isError ? 'error' : 'completed' : 'running',
        ...(input.text ? { input: input.text } : {}), ...(output ? { output: output.text, isError: data.message?.isError === true } : {}),
        ...(input.truncated || output?.truncated ? { truncated: true } : {}) } }]
  }
  if (event.type === 'assistant/message') {
    const text = visible(textOf(data.message?.content))
    const reasoning = visible(reasoningOf(data.message?.content))
    const attachments = attachmentsOf(data.message?.content, visible)
    return text || reasoning || attachments.length ? [{ ...base, role: 'assistant', text, ...(reasoning ? { reasoning } : {}),
      ...(attachments.length ? { attachments } : {}),
      ...(data.interrupted ? { interrupted: true } : {}), ...(Number.isInteger(data.turn) ? { turn: data.turn } : {}),
      ...(Number.isInteger(data.step) ? { step: data.step } : {}) }] : []
  }
  if (event.type !== 'user/message') return []
  const source = data.source ?? {}
  const attachments = attachmentsOf(data.content, visible)
  let text = textOf(data.content)
  if (kind === 'room' && source.kind === 'bot' && source.role === 'post') {
    text = text.replace(/^\[Group post from [^\]]*\]\n?/, '')
    return text ? [{ ...base, role: 'assistant', text: visible(text), author: { id: source.senderSessionId ?? '', name: visible(source.senderName ?? 'Bot') } }] : []
  }
  if (source.kind === 'user-question-reply') {
    try {
      const answer = JSON.parse(text)
      text = (answer.questions ?? []).map(question => {
        const reply = (answer.answers ?? []).find(item => item.id === question.id)
        return `${question.question}\n${[...(reply?.selected ?? []), reply?.custom].filter(Boolean).join(', ')}`
      }).join('\n\n')
    } catch { return [] }
  } else if (source.kind !== 'user') return []
  if (!text && attachments.length === 0) return []
  return [{ ...base, role: 'user', text: visible(text), ...(typeof source.rpcId === 'string' ? { requestId: source.rpcId } : {}),
    ...(attachments.length ? { attachments } : {}) }]
}

export function projectRecords(records, options) {
  const calls = new Map()
  const messages = new Map()
  for (const record of records ?? []) for (const message of projectEvent(record.event, { ...options, calls })) {
    messages.set(message.id, message)
  }
  return [...messages.values()]
}

export function projectQueue(inbox = {}, { redact = text => text } = {}) {
  return ['next-turn', 'next-step'].flatMap(target => (inbox[target] ?? []).flatMap(message => {
    if (message?.source?.kind !== 'user' || typeof message.id !== 'string') return []
    const attachments = attachmentsOf(message.content, redact)
    return [{ id: message.id, target, text: String(redact(textOf(message.content))),
      ...(typeof message.source.rpcId === 'string' ? { requestId: message.source.rpcId } : {}),
      ...(attachments.length ? { attachments } : {}) }]
  }))
}

// Use cumulative text frames so retries, duplicate transport frames and block-end
// corrections cannot append the same text twice on a phone.
export function createTextAccumulator(records = []) {
  const blocks = new Map()
  const reasoning = new Map()
  function accept(chunk) {
    if (!chunk || !Number.isInteger(chunk.index)) return
    if (chunk.type === 'text-delta') blocks.set(chunk.index, (blocks.get(chunk.index) ?? '') + (chunk.text ?? ''))
    if (chunk.type === 'reasoning-delta') reasoning.set(chunk.index, (reasoning.get(chunk.index) ?? '') + (chunk.text ?? ''))
    if (chunk.type === 'block-end' && chunk.block?.type === 'text') blocks.set(chunk.index, chunk.block.text ?? '')
    if (chunk.type === 'block-end' && chunk.block?.type === 'reasoning') reasoning.set(chunk.index, chunk.block.text ?? '')
  }
  for (const record of records) {
    if (record?.type === 'text-chunks') accept({ type: 'text-delta', index: record.index, text: (record.texts ?? []).join('') })
    else if (record?.type === 'reasoning-chunks') accept({ type: 'reasoning-delta', index: record.index, text: (record.texts ?? []).join('') })
    else if (record?.type === 'chunk') accept(record.chunk)
  }
  const joined = values => [...values].sort(([a], [b]) => a - b).map(([, text]) => text).join('\n')
  return { accept, text: () => joined(blocks), reasoning: () => joined(reasoning) }
}
