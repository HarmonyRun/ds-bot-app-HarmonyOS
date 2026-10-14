import assert from 'node:assert/strict'
import { test } from 'node:test'
import { createTextAccumulator, projectEvent, projectQueue, projectRecords } from '../src/mobile/projection.js'
import { applyConversationEvent, mergeMessages } from '../../packages/mobile-sdk/index.js'

const event = (type, seq, data) => ({ type, seq, time: 1000 + seq, data })
const record = value => ({ type: 'event', event: value })
const call = (seq = 2, patch = {}) => event('tool/call', seq, { callId: 'read-1', name: 'read', arguments: '{"path":"README.md"}', turn: 1, step: 0, ...patch })
const result = (seq = 4, patch = {}) => event('tool/result', seq, { turn: 1, step: 0, message: { toolCallId: 'read-1', content: [{ type: 'text', text: 'Project setup instructions' }], isError: false }, ...patch })

test('PTC sub-calls keep stable live cards, redaction, failures and hidden parent boundaries', () => {
  const calls = new Map(), options = { sessionId: 's1', calls, hiddenTurns: [7] }
  projectEvent(call(1, { callId: 'root', name: 'run_code', turn: 2 }), options)
  const data = { rootCallId: 'root', parentCallId: 'root', subCallId: 'root:ptc:1', name: 'read', arguments: { path: 'README.md', token: 'fixture-private' } }
  const running = projectEvent(event('tool/ptc-dispatch-start', 2, data), options)[0]
  const completed = projectEvent(event('tool/ptc-dispatch', 4, { ...data, content: [{ type: 'text', text: 'Not found' }], isError: true }), options)[0]
  assert.equal(completed.id, running.id); assert.equal(completed.seq, 2); assert.equal(completed.turn, 2)
  assert.equal(completed.tool.state, 'error'); assert.equal(completed.tool.durationMs, 2)
  assert.equal(completed.tool.input.includes('fixture-private'), false)
  assert.deepEqual(projectEvent(event('tool/ptc-dispatch', 5, { ...data, rootCallId: 'missing' }), options), [])
  projectEvent(call(6, { callId: 'hidden', name: 'run_code', turn: 7 }), options)
  assert.deepEqual(projectEvent(event('tool/ptc-dispatch', 7, { ...data, rootCallId: 'hidden' }), options), [])
})

test('snapshot PTC calls retain their identity when a live result arrives', () => {
  const calls = new Map(), options = { sessionId: 's1', calls }
  const data = { rootCallId: 'root', parentCallId: 'root', subCallId: 'child', name: 'read', arguments: { path: 'README.md' } }
  const page = projectRecords([call(1, { callId: 'root', name: 'run_code' }), event('tool/ptc-dispatch-start', 2, data)].map(record), options)
  const next = projectEvent(event('tool/ptc-dispatch', 3, { ...data, content: [{ type: 'text', text: 'Ready' }], isError: false }), options)[0]
  const merged = mergeMessages(page, [next]); assert.equal(merged.length, 2)
  assert.equal(merged.find(row => row.tool.callId === 'child').tool.state, 'completed')
})

test('delivery and change cards select bounded display data without internal paths or snapshots', () => {
  const options = { sessionId: 's1', hiddenTurns: [7], changesSummary: () => ({ cwd: 'private-host-directory', snapshot: { before: 'private-tree' }, total: 1, files: [{ path: 'result.txt', display: 'result.txt', added: 4, deleted: 2 }] }) }
  const delivered = projectEvent(event('deliverables/presented', 1, { turn: 2, callId: 'p1', files: [{ path: 'result.txt', description: 'Report' }] }), options)[0]
  assert.equal(JSON.parse(delivered.tool.output).files[0].path, 'result.txt')
  const changed = projectEvent(event('workspace/changes', 2, { turn: 2 }), options)[0]
  assert.deepEqual(JSON.parse(changed.tool.output).files, [{ path: 'result.txt', added: 4, deleted: 2 }])
  assert.doesNotMatch(JSON.stringify(changed), /private-host-directory|private-tree/)
  assert.deepEqual(projectEvent(event('deliverables/presented', 3, { turn: 7, files: [{ path: 'hidden.txt' }] }), options), [])
  assert.deepEqual(projectEvent(event('workspace/changes', 4, { turn: 2 }), { sessionId: 's1' }), [])
})

test('tool call and result become one stable card at the original call position', () => {
  const calls = new Map()
  const running = projectEvent(call(), { sessionId: 's1', calls })[0]
  const completed = projectEvent(result(), { sessionId: 's1', calls })[0]
  assert.equal(running.tool.state, 'running')
  assert.equal(completed.id, running.id)
  assert.equal(completed.seq, 2)
  assert.equal(completed.updatedSeq, 4)
  assert.equal(completed.createdAt, 1002)
  assert.equal(completed.tool.state, 'completed')
  assert.equal(completed.tool.output, 'Project setup instructions')
  assert.equal(completed.tool.input.includes('README.md'), true)
  const page = projectRecords([call(), result()].map(record), { sessionId: 's1' })
  assert.equal(page.length, 1)
  assert.deepEqual(page[0], completed)
})

test('failed tool results retain a distinct error state on the same call', () => {
  const page = projectRecords([record(call()), record(result(5, { message: { source: { callId: 'read-1' }, isError: true, content: [{ type: 'text', text: 'File was not found.' }] } }))], { sessionId: 's1' })
  assert.equal(page[0].tool.state, 'error')
  assert.equal(page[0].tool.isError, true)
  assert.equal(page[0].updatedSeq, 5)
})

test('tool detail redacts credential fields, known secret values and authorization text', () => {
  const marker = 'test-only-sensitive-value'
  const args = { path: 'README.md', nested: { apiKey: marker, headers: { Authorization: `Bearer ${marker}` } }, note: marker }
  const calls = new Map()
  const options = { sessionId: 's1', calls, redact: text => text.replaceAll(marker, '[redacted]') }
  const pending = projectEvent(call(2, { arguments: JSON.stringify(args) }), options)[0]
  const final = projectEvent(result(4, { message: { toolCallId: 'read-1', content: [{ type: 'text', text: 'access_token=example-private-value\nAuthorization: Bearer other-private-value' }] } }), options)[0]
  assert.equal(JSON.stringify(pending).includes(marker), false)
  assert.equal(JSON.stringify(final).includes('example-private-value'), false)
  assert.equal(JSON.stringify(final).includes('other-private-value'), false)
  assert.equal(pending.tool.input.includes('README.md'), true)
})

test('credential tools expose status but withhold raw inputs and outputs', () => {
  const records = [record(call(2, { name: 'read_secret', arguments: 'unstructured sensitive input' })), record(result(3, { message: { toolCallId: 'read-1', content: [{ type: 'text', text: 'unstructured sensitive output' }] } }))]
  const tool = projectRecords(records, { sessionId: 's1' })[0].tool
  assert.equal(tool.name, 'read_secret')
  assert.equal(tool.state, 'completed')
  assert.equal(tool.input, '[Sensitive tool details omitted]')
  assert.equal(tool.output, '[Sensitive tool details omitted]')
})

test('tool detail is bounded and visibly marked when large strings or structures are clipped', () => {
  const page = projectRecords([record(call(2, { arguments: JSON.stringify({ paths: Array.from({ length: 120 }, (_, i) => `file-${i}`) }) })), record(result(3, { message: { toolCallId: 'read-1', content: [{ type: 'text', text: 'x'.repeat(50000) }] } }))], { sessionId: 's1' })
  assert.equal(page[0].tool.truncated, true)
  assert.ok(page[0].tool.output.length < 12100)
  assert.equal(page[0].tool.input.includes('file-119'), false)
})

test('hidden exchange turns suppress their tool calls, results and reasoning', () => {
  const records = [record(call(2, { turn: 7 })), record(result(3, { turn: 7 })), record(event('assistant/message', 4, { turn: 7, message: { content: [{ type: 'reasoning', text: 'Internal exchange' }, { type: 'text', text: 'Internal reply' }] } }))]
  assert.deepEqual(projectRecords(records, { sessionId: 's1', hiddenTurns: [7] }), [])
  const calls = new Map()
  projectEvent(call(2, { turn: 7 }), { sessionId: 's1', calls, hiddenTurns: [7] })
  assert.deepEqual(projectEvent(result(3), { sessionId: 's1', calls, hiddenTurns: [7] }), [])
})

test('group relay projects only public replies and never its internal input or tool output', () => {
  const records = [record(call(2, { name: 'group_relay', arguments: 'Internal coordination' })), record(result(3, { message: { source: { callId: 'read-1' }, content: [{ type: 'text', text: JSON.stringify({ internal: 'Private routing state', replies: [{ botId: 'b1', name: 'Writer', text: 'Public reply' }] }) }] } }))]
  const messages = projectRecords(records, { sessionId: 'room', kind: 'room' })
  assert.deepEqual(messages.map(message => [message.role, message.text]), [['assistant', 'Public reply']])
  assert.equal(JSON.stringify(messages).includes('Internal coordination'), false)
  assert.equal(JSON.stringify(messages).includes('Private routing state'), false)
  assert.deepEqual(projectRecords(records, { sessionId: 'bot', kind: 'bot' }), [])
  assert.deepEqual(projectRecords([record(call()), record(result())], { sessionId: 'room', kind: 'room' }), [])
})

test('assistant history retains reasoning, interruption, step and attachment metadata', () => {
  const message = projectEvent(event('assistant/message', 8, { turn: 2, step: 3, interrupted: true, message: { content: [
    { type: 'reasoning', text: 'Visible model reasoning' }, { type: 'text', text: 'Partial answer' },
    { type: 'image', attachment: { attachmentId: 'sha256:image', name: 'result.png', mediaType: 'image/png', bytes: 20 } },
  ] } }), { sessionId: 's1' })[0]
  assert.equal(message.reasoning, 'Visible model reasoning')
  assert.equal(message.interrupted, true)
  assert.equal(message.turn, 2)
  assert.equal(message.step, 3)
  assert.equal(message.attachments[0].id, 'sha256:image')
  assert.equal(projectEvent(event('assistant/message', 9, { message: { content: [{ type: 'reasoning', text: 'Reasoning before interruption' }] } }), { sessionId: 's1' })[0].text, '')
})

test('reasoning reconnect baselines and authoritative block ends stay separate from answer text', () => {
  const accumulator = createTextAccumulator([
    { type: 'reasoning-chunks', index: 0, texts: ['Plan', ' first'] },
    { type: 'text-chunks', index: 1, texts: ['Answer'] },
  ])
  accumulator.accept({ type: 'reasoning-delta', index: 0, text: ' draft' })
  assert.equal(accumulator.reasoning(), 'Plan first draft')
  accumulator.accept({ type: 'block-end', index: 0, block: { type: 'reasoning', text: 'Checked plan' } })
  assert.equal(accumulator.reasoning(), 'Checked plan')
  assert.equal(accumulator.text(), 'Answer')
})

test('an older history page enriches an orphan tool result without reverting its completed status', () => {
  const completed = projectRecords([record(result())], { sessionId: 's1' })
  const oldPage = projectRecords([record(call())], { sessionId: 's1' })
  const merged = mergeMessages(completed, oldPage)
  assert.equal(merged.length, 1)
  assert.equal(merged[0].seq, 2)
  assert.equal(merged[0].createdAt, 1002)
  assert.equal(merged[0].updatedSeq, 4)
  assert.equal(merged[0].tool.state, 'completed')
  assert.equal(merged[0].tool.name, 'read')
  assert.equal(merged[0].tool.output, 'Project setup instructions')
  assert.equal(merged[0].tool.input.includes('README.md'), true)
  assert.deepEqual(applyConversationEvent(merged, { type: 'reset', messages: oldPage }), merged)
})

test('live reasoning survives repeated frames until its matching durable assistant message arrives', () => {
  const wire = { type: 'delta', sessionId: 's1', attemptId: 'attempt-1', text: '', reasoning: 'Visible reasoning', index: 1 }
  let messages = applyConversationEvent([], wire)
  messages = applyConversationEvent(messages, { ...wire, text: 'Answer', index: 2 })
  messages = applyConversationEvent(messages, { ...wire, index: 0, reasoning: 'Stale' })
  assert.equal(messages.length, 1)
  assert.equal(messages[0].reasoning, 'Visible reasoning')
  assert.equal(messages[0].text, 'Answer')
  const final = projectEvent(event('assistant/message', 5, { turn: 1, message: { content: [
    { type: 'reasoning', text: 'Visible reasoning' }, { type: 'text', text: 'Answer' },
  ] } }), { sessionId: 's1' })[0]
  messages = applyConversationEvent(messages, { type: 'message', message: final, replaceAttemptId: 'attempt-1' })
  assert.deepEqual(messages, [final])
})

test('durable history, reconnect pages, public group replies and queued text redact known secret values', () => {
  const marker = 'ds-bot-test-known-sensitive-value'
  const redact = text => text.replaceAll(marker, '[redacted]')
  const content = [{ type: 'text', text: `Message ${marker}` }, { type: 'reasoning', text: `Reasoning ${marker}` },
    { type: 'file', attachment: { attachmentId: 'opaque-file', name: `${marker}.txt` } }]
  const assistant = event('assistant/message', 7, { message: { content } })
  const records = [record(event('user/message', 6, { source: { kind: 'user' }, content })), record(assistant)]
  const page = projectRecords(records, { sessionId: 's1', redact })
  assert.equal(JSON.stringify(page).includes(marker), false)
  assert.equal(page[1].text, 'Message [redacted]')
  assert.equal(page[1].reasoning, 'Reasoning [redacted]')
  let messages = applyConversationEvent([], { type: 'delta', sessionId: 's1', attemptId: 'a1', index: 1, text: redact(`Message ${marker}`), reasoning: redact(`Reasoning ${marker}`) })
  messages = applyConversationEvent(messages, { type: 'reset', messages: page })
  assert.equal(JSON.stringify(messages).includes(marker), false)
  assert.equal(messages.some(message => message.pending), false)
  const group = projectRecords([record(call(1, { name: 'group_relay' })), record(result(2, { message: { toolCallId: 'read-1', content: [
    { type: 'text', text: JSON.stringify({ replies: [{ name: marker, text: `Public ${marker}` }] }) },
  ] } }))], { sessionId: 'room', kind: 'room', redact })
  assert.equal(group[0].text, 'Public [redacted]')
  assert.equal(JSON.stringify(group).includes(marker), false)
  const queued = projectQueue({ 'next-turn': [{ id: 'inbox-1', source: { kind: 'user' }, content }] }, { redact })
  assert.equal(queued[0].text, 'Message [redacted]')
  assert.equal(JSON.stringify(queued).includes(marker), false)
})
