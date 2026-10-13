import assert from 'node:assert/strict'
import { test } from 'node:test'
import { createAdapter } from '../src/mobile/adapter.js'
import { projectRecords } from '../src/mobile/projection.js'

function fixture() {
  const value = { bots: [{ id: 'chief', name: 'Chief', sessionId: 'chat', parts: [], capabilities: ['pack'] }, { id: 'peer', name: 'Peer', sessionId: 'peer-chat', parts: [] }],
    rooms: [{ id: 'room', name: 'Group', members: ['chief'], parts: [] }], models: [], questions: {},
    capabilities: [{ name: 'echo', kind: 'mcp', description: 'Echo fixture-private', command: 'private-command', args: ['private-argument'], env: { API_KEY: 'fixture-private' }, headers: { Authorization: 'fixture-private' }, url: 'private-url', content: 'private-body', approved: false, transport: 'stdio' },
      { name: 'pack', kind: 'pack', items: ['echo'] }],
    capabilityStatuses: { chief: { echo: { state: 'error', error: 'Failure fixture-private', token: 'fixture-private' }, unknown: { state: 'ready' } }, foreign: { echo: { state: 'ready' } } },
    work: { bots: {}, approvals: [], rooms: { room: [{ botId: 'chief', since: 10, tool: 'read fixture-private', speaking: true, private: 'fixture-private' }, { botId: 'peer' }, { botId: 'foreign' }], foreign: [{ botId: 'chief' }] } },
  }
  const calls = []
  let readOnly
  const rt = { state: { exchangeTurns: {} }, readOnly: () => readOnly, redactSecrets: text => String(text).replaceAll('fixture-private', '[redacted]'),
    teamCall: async (endpoint, body) => {
      if (endpoint === 'state') return { ok: true, value }
      calls.push([endpoint, body]); return { ok: true, value: true }
    }, ctx: { sessionController: { prompt: async request => { calls.push(['prompt', request]); return { accepted: true } } } },
  }
  const adapter = createAdapter(rt)
  return { value, calls, rt, adapter, setReadOnly: value => { readOnly = value } }
}

test('mobile exports capability metadata and group work without configuration or foreign scope', async () => {
  const { adapter } = fixture()
  const result = await adapter.state()
  assert.deepEqual(result.capabilities[0], { name: 'echo', kind: 'mcp', description: 'Echo [redacted]', transport: 'stdio', approved: false })
  assert.deepEqual(result.capabilityStatuses, { chief: { echo: { state: 'error', error: 'Failure [redacted]' } } })
  assert.deepEqual(result.work.rooms, { room: [{ botId: 'chief', since: 10, tool: 'read [redacted]', speaking: true }] })
  assert.equal(JSON.stringify(result).includes('private-command'), false)
  assert.equal(JSON.stringify(result).includes('fixture-private'), false)
})

test('mobile capability assignment is scoped and cannot approve or rewrite commands', async () => {
  const { adapter, calls } = fixture()
  await adapter.action('bot-capability', { botId: 'chief', name: 'echo', attached: true, approved: true, command: 'forged' })
  assert.deepEqual(calls, [['bot-capability', { botId: 'chief', name: 'echo', attached: true }]])
  await assert.rejects(adapter.action('bot-capability', { botId: 'foreign', name: 'echo', attached: true }), { status: 404 })
  await assert.rejects(adapter.action('bot-capability', { botId: 'chief', name: 'missing', attached: true }), { status: 404 })
  await assert.rejects(adapter.action('bot-capability', { botId: 'chief', name: 'echo', attached: 'true' }), { status: 400 })
  await assert.rejects(adapter.action('capability-save', { name: 'forged', kind: 'mcp' }), { status: 404 })
  await assert.rejects(adapter.action('capability-approve', { name: 'echo' }), { status: 404 })
  assert.equal(calls.length, 1)
})

test('stopping member work requires both an owned group and its current member', async () => {
  const { adapter, calls } = fixture()
  await adapter.action('stop-member-work', { roomId: 'room', botId: 'chief', sessionId: 'foreign' })
  assert.deepEqual(calls, [['stop-member-work', { roomId: 'room', botId: 'chief' }]])
  await assert.rejects(adapter.action('stop-member-work', { roomId: 'foreign', botId: 'chief' }), { status: 404 })
  await assert.rejects(adapter.action('stop-member-work', { roomId: 'room', botId: 'peer' }), { status: 404 })
  assert.equal(calls.length, 1)
})

test('mobile prompts prepare capabilities and recheck ownership, cancellation and read-only state afterwards', async () => {
  for (const change of ['success', 'move', 'cancel', 'read-only']) {
    const { adapter, rt, value, calls, setReadOnly } = fixture()
    const controller = new AbortController()
    rt.ensureCapabilities = async id => {
      assert.equal(id, 'chat')
      calls.push(['prepare', id])
      if (change === 'move') value.bots[0].sessionId = 'new-chat'
      if (change === 'cancel') controller.abort(new Error('cancelled'))
      if (change === 'read-only') setReadOnly('locked')
    }
    const submit = adapter.submit({ conversationId: 'chief', sessionId: 'chat', requestId: 'request', text: 'Check capabilities' }, controller.signal)
    if (change === 'success') {
      await submit
      assert.deepEqual(calls.map(call => call[0]), ['prepare', 'prompt'])
    } else {
      await assert.rejects(submit)
      assert.equal(calls.some(call => call[0] === 'prompt'), false)
    }
  }
})

test('group work and restart events appear without empty messages, retry prompts or duplicate post events', () => {
  const call = { type: 'event', event: { type: 'tool/call', seq: 1, data: { callId: 'call', name: 'group_relay', turn: 1 } } }
  const reply = { type: 'event', event: { type: 'tool/result', seq: 2, data: { message: { source: { callId: 'call' }, content: [{ type: 'text', text: JSON.stringify({ replies: ['working', 'approval', 'resumed', 'cut', 'stopped'].map(kind => ({ kind, name: 'Chief', botId: 'chief' })) }) }] } } } }
  const messages = projectRecords([call, reply], { sessionId: 'room', kind: 'room' })
  assert.equal(messages.length, 5)
  assert.deepEqual(messages.map(message => message.systemEvent.kind), ['working', 'approval', 'resumed', 'cut', 'stopped'])
  assert.ok(messages.every(message => message.role === 'system' && message.text))
  const event = source => [{ type: 'event', event: { type: 'user/message', seq: 3, data: { source, content: [{ type: 'text', text: 'Private retry instructions' }] } } }]
  const resumed = projectRecords(event({ kind: 'bot', role: 'resume' }), { sessionId: 'chat' })
  assert.equal(resumed[0].systemEvent.kind, 'resumed')
  assert.equal(resumed[0].text.includes('Private'), false)
  assert.equal(projectRecords(event({ kind: 'bot', role: 'post', stopped: true }), { sessionId: 'room', kind: 'room' }).length, 0)
})
