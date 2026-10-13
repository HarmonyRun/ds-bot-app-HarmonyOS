import assert from 'node:assert/strict'
import { test } from 'node:test'
import { Context } from '@deepseek-ai/cordis'
import SessionStore from '@deepseek-ai/dsh-session'
import ApprovalService from '@deepseek-ai/dsh-user-approval'
import { createApprovalBroker } from '../src/mobile/approvals.js'

const tick = () => new Promise(resolve => setImmediate(resolve))
function deferred() { let resolve; const promise = new Promise(done => { resolve = done }); return { promise, resolve } }

async function fixture(t, overrides = {}) {
  const ctx = new Context()
  const sessionsFiber = await ctx.plugin(SessionStore)
  const approvalFiber = await ctx.plugin(ApprovalService, { policy: overrides.policy ?? 'ask' })
  const session = ctx.sessions.create('mobile-approval-session')
  session.append('turn/start', { turn: 1 })
  const agent = { session }
  const devices = new Set(['phone-1', 'phone-2'])
  let downstream = 0
  const removeDefault = ctx.on('approval/request', () => { downstream++; return Promise.resolve('rejected') })
  const broker = createApprovalBroker({
    resolveConversation: sessionId => sessionId === session.id ? 'chief' : undefined,
    enabled: () => devices.size > 0,
    authorizeDevice: deviceId => devices.has(deviceId),
    ...overrides,
  })
  const removeBroker = ctx.on('approval/request', broker.handle, { prepend: true })
  t.after(async () => { removeBroker(); removeDefault(); broker.dispose(); await approvalFiber.dispose(); await sessionsFiber.dispose() })
  return { ctx, agent, session, broker, devices, downstream: () => downstream,
    request: (patch = {}) => ctx.approval.request({ agent, toolName: 'terminal', callId: 'tool-call-1', reason: 'Run the requested test command once', ...patch }),
    audit: () => session.snapshotEvents().filter(event => event.type.startsWith('approval/')),
  }
}

test('the public Cordis waterfall shares one pending request and accepts exactly one desktop/mobile answer', async t => {
  const f = await fixture(t)
  let executions = 0
  const decision = f.request().then(outcome => { if (outcome === 'allowed-once') executions++; return outcome })
  await tick()
  const view = f.broker.list().requests[0]
  assert.equal(view.conversationId, 'chief')
  assert.equal(view.sessionId, f.session.id)
  assert.equal(view.toolName, 'terminal')
  assert.equal(view.callId, 'tool-call-1')
  assert.equal(view.reason, 'Run the requested test command once')
  assert.equal(f.downstream(), 0)
  const answers = await Promise.allSettled([
    f.broker.resolveForDevice('phone-1', { id: view.id, decision: 'allowed-once' }),
    f.broker.resolveForDesktop({ id: view.id, decision: 'allowed-once' }),
  ])
  assert.equal(answers.filter(item => item.status === 'fulfilled').length, 1)
  assert.equal(answers.find(item => item.status === 'rejected').reason.code, 'APPROVAL_SETTLED')
  assert.equal(await decision, 'allowed-once')
  assert.equal(executions, 1)
  assert.deepEqual(f.broker.list(), { requests: [] })
  const audit = f.audit()
  assert.deepEqual(audit.map(event => event.type), ['approval/asked', 'approval/decided'])
  assert.equal(audit[0].data.id, audit[1].data.id)
  assert.notEqual(audit[0].data.id, view.id)
})

test('unconfigured, unpaired and unrelated requests delegate to the original desktop answerer', async t => {
  for (const overrides of [{ enabled: () => false }, { resolveConversation: () => undefined }]) {
    const f = await fixture(t, overrides)
    assert.equal(await f.request(), 'rejected')
    assert.equal(f.downstream(), 1)
    assert.deepEqual(f.broker.list().requests, [])
  }
  const f = await fixture(t)
  f.devices.clear()
  assert.equal(await f.request(), 'rejected')
  assert.equal(f.downstream(), 1)
})

test('the original never policy rejects before entering either answerer', async t => {
  const f = await fixture(t, { policy: 'never' })
  assert.equal(await f.request(), 'rejected')
  assert.equal(f.downstream(), 0)
  assert.deepEqual(f.broker.list().requests, [])
})

test('original cancellation removes the pending record and cannot grant a late answer', async t => {
  const f = await fixture(t)
  const controller = new AbortController()
  const decision = f.request({ signal: controller.signal })
  await tick()
  const { id } = f.broker.list().requests[0]
  controller.abort()
  assert.equal(await decision, 'cancelled')
  assert.deepEqual(f.broker.list().requests, [])
  await assert.rejects(f.broker.resolveForDevice('phone-1', { id, decision: 'allowed-once' }), { code: 'APPROVAL_SETTLED' })
  assert.equal(f.audit()[1].data.outcome, 'cancelled')
})

test('revoking a device while its answer is awaiting ownership cannot grant access', async t => {
  const gate = deferred()
  let checks = 0
  const f = await fixture(t, { resolveConversation: async () => { if (++checks > 1) await gate.promise; return 'chief' } })
  const decision = f.request()
  await tick()
  const { id } = f.broker.list().requests[0]
  const answer = f.broker.resolveForDevice('phone-1', { id, decision: 'allowed-once' })
  await tick()
  f.devices.delete('phone-1')
  gate.resolve()
  await assert.rejects(answer, { code: 'UNAUTHORIZED' })
  assert.equal(f.broker.list().requests.length, 1)
  await assert.rejects(f.broker.resolveForDevice(undefined, { id, decision: 'allowed-once' }), { code: 'UNAUTHORIZED' })
  await f.broker.resolveForDevice('phone-2', { id, decision: 'rejected' })
  assert.equal(await decision, 'rejected')
})

test('unsupported decisions and a removed conversation never become broader grants', async t => {
  let owned = true
  const f = await fixture(t, { resolveConversation: () => owned ? 'chief' : undefined })
  const decision = f.request()
  await tick()
  const { id } = f.broker.list().requests[0]
  await assert.rejects(f.broker.resolveForDesktop({ id, decision: 'always-allow' }), { code: 'INVALID_APPROVAL' })
  owned = false
  await assert.rejects(f.broker.resolveForDevice('phone-1', { id, decision: 'allowed-once' }), { code: 'APPROVAL_SCOPE_CHANGED' })
  assert.equal(await decision, 'cancelled')
  assert.deepEqual(f.broker.list().requests, [])
})

test('broker shutdown settles the borrowed request without leaking a desktop fallback pending', async t => {
  const f = await fixture(t)
  const decision = f.request()
  await tick()
  f.broker.dispose()
  assert.equal(await decision, 'unavailable')
  assert.equal(f.downstream(), 0)
  assert.deepEqual(f.broker.list().requests, [])
})

test('request views preserve localized scope, redact secrets and cannot mutate the pending decision', async t => {
  const f = await fixture(t, { redact: text => text.replaceAll('test-sensitive-value', '[redacted]') })
  const decision = f.request({ reason: 'Use test-sensitive-value once', displayReason: { en: 'One command', zh: '仅运行此命令' } })
  await tick()
  const first = f.broker.list().requests[0]
  first.displayReason.en = 'Different operation'
  first.reason = 'Different reason'
  const actual = f.broker.list().requests[0]
  assert.equal(actual.displayReason.en, 'One command')
  assert.equal(actual.displayReason.zh, '仅运行此命令')
  assert.equal(actual.reason, 'Use [redacted] once')
  await f.broker.resolveForDesktop({ id: actual.id, decision: 'rejected' })
  assert.equal(await decision, 'rejected')
})
