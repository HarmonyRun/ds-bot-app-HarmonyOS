import assert from 'node:assert/strict'
import { test } from 'node:test'
import { fileURLToPath } from 'node:url'
import { runInNewContext } from 'node:vm'
import { build } from 'esbuild'

const bundle = await build({
  entryPoints: [fileURLToPath(new URL('../src/client/mobile-approvals.js', import.meta.url))],
  bundle: true, format: 'cjs', platform: 'node', write: false, external: ['react'],
})
const module = { exports: {} }
runInNewContext(bundle.outputFiles[0].text, {
  module, exports: module.exports, AbortController, AbortSignal,
  require: name => {
    assert.equal(name, 'react')
    return { createElement: (type, props, ...children) => ({ type, props: props ?? {}, children: children.flat(Infinity) }) }
  },
})
const { createMobileApprovals, approvalReason, approvalSession, liveApprovalCommand, MobileApprovalDock, MobileApprovalNotice } = module.exports
const request = { id: 'pending-1', conversationId: 'writer', sessionId: 'part-2', toolName: 'bash', callId: 'call-1', reason: 'Read the requested project folder.' }
const pending = () => Promise.withResolvers()
const nodes = (tree, match) => !tree || typeof tree !== 'object' ? []
  : [...(match(tree) ? [tree] : []), ...(tree.children ?? []).flatMap(child => nodes(child, match))]

test('one local answer owns the button lock and never permits persistent grants', async () => {
  const gate = pending()
  const sent = []
  let listed = [request]
  const state = createMobileApprovals(async (endpoint, payload) => {
    if (endpoint === 'approvals.list') return { requests: listed }
    sent.push(payload)
    await gate.promise
    listed = []
    return { accepted: true }
  })
  await state.refresh()
  await state.answer(request.id, 'always-allow')
  const first = state.answer(request.id, 'allowed-once')
  await state.answer(request.id, 'rejected')
  assert.equal(sent.length, 1)
  assert.equal(sent[0].id, request.id)
  assert.equal(sent[0].decision, 'allowed-once')
  assert.equal(state.getSnapshot().busy[0], request.id)
  gate.resolve()
  await first
  assert.equal(state.getSnapshot().requests.length, 0)
  state.dispose()
})

test('a lost race refreshes the live broker list instead of reopening or replaying an approval', async () => {
  let calls = 0
  const state = createMobileApprovals(async endpoint => {
    if (endpoint === 'approvals.list') return { requests: ++calls === 1 ? [request] : [] }
    throw Object.assign(new Error('Already answered on phone'), { code: 'APPROVAL_STALE' })
  })
  await state.refresh()
  await state.answer(request.id, 'rejected')
  assert.equal(state.getSnapshot().requests.length, 0)
  assert.equal(Object.keys(state.getSnapshot().errors).length, 0)
  state.dispose()
})

test('a late list cannot resurrect an approval after the answer succeeded', async () => {
  const oldList = pending()
  let calls = 0
  const state = createMobileApprovals(async endpoint => {
    if (endpoint !== 'approvals.list') return { accepted: true }
    calls++
    return calls === 2 ? oldList.promise : { requests: calls === 1 ? [request] : [] }
  })
  await state.refresh()
  const older = state.refresh()
  await state.answer(request.id, 'allowed-once')
  oldList.resolve({ requests: [request] })
  await older
  assert.equal(state.getSnapshot().requests.length, 0)
  state.dispose()
})

test('disconnection disables stale answers and a fresh cancellation removes the request', async () => {
  let offline = false
  let listed = [request]
  let answers = 0
  const state = createMobileApprovals(async endpoint => {
    if (offline) throw new Error('offline')
    if (endpoint !== 'approvals.list') { answers++; return { accepted: true } }
    return { requests: listed }
  })
  await state.refresh()
  offline = true
  await state.refresh()
  await state.answer(request.id, 'allowed-once')
  assert.equal(state.getSnapshot().connected, false)
  assert.equal(answers, 0)
  offline = false
  listed = []
  await state.refresh()
  assert.equal(state.getSnapshot().requests.length, 0)
  state.dispose()
})

test('disposing aborts transport and ignores a list arriving afterward', async () => {
  const gate = pending()
  let signal
  const state = createMobileApprovals(async (_endpoint, _payload, value) => { signal = value; return gate.promise })
  const load = state.refresh()
  state.dispose()
  assert.equal(signal.aborted, true)
  gate.resolve({ requests: [request] })
  await load
  assert.equal(state.getSnapshot().requests.length, 0)
})

test('request explanations retain their full text and locale fallback', () => {
  const detail = 'Requested operation '.repeat(1000)
  assert.equal(approvalReason({ ...request, reason: detail }), detail)
  assert.equal(approvalReason({ ...request, displayReason: { en: 'English scope', zh: '中文范围' } }, 'zh-CN'), '中文范围')
  assert.equal(approvalReason({ ...request, displayReason: { en: 'English scope' } }, 'fr'), 'English scope')
})

test('the dock renders only live requests for its session with one-shot decisions', () => {
  const state = { requests: [request], connected: true, busy: [], errors: {} }
  const props = { useMobileApprovals: select => select(state), useRoster: select => select({ byId: { writer: {} }, roomsById: {} }), actions: {} }
  assert.equal(MobileApprovalDock({ ...props, sessionId: 'unowned' }), null)
  const tree = MobileApprovalDock({ ...props, sessionId: request.sessionId })
  assert.deepEqual(nodes(tree, node => node.type === 'button').map(node => node.children[0]), ['Reject', 'Allow once'])
  assert.equal(nodes(tree, node => node.props.dangerouslySetInnerHTML !== undefined).length, 0)
  const notice = MobileApprovalNotice({ ...props, useRoster: select => select({ byId: { writer: { name: 'Writer' } }, roomsById: {} }), useSessions: select => select({ byId: { other: { id: 'other', retainedBy: { mainView: 1 } } } }) })
  assert.equal(nodes(notice, node => node.type === 'button').length, 1)
})

test('only the exact live tool call supplies command detail, never a completed or unrelated call', () => {
  const tool = (callId, phase, command) => ({ kind: 'tool-call', data: { root: { callId, phase, argsRaw: JSON.stringify({ command }) } } })
  const snapshot = { nodes: new Map([
    ['old', tool(request.callId, 'end', 'old-command')],
    ['other', tool('other-call', 'start', 'unrelated-command')],
    ['live', tool(request.callId, 'start', 'printf approval-fixture')],
  ]) }
  assert.equal(liveApprovalCommand(snapshot, request), 'printf approval-fixture')
  snapshot.nodes.delete('live')
  assert.equal(liveApprovalCommand(snapshot, request), undefined)
  assert.equal(liveApprovalCommand(snapshot, { ...request, callId: undefined }), undefined)
})

test('group member approvals open the public group and never expose an internal member Session', () => {
  const groupRequest = { ...request, conversationId: 'room', sessionId: 'hidden-member' }
  const roster = { byId: {}, roomsById: { room: { id: 'room', name: 'Project' } } }
  const state = { requests: [groupRequest], connected: true, busy: [], errors: {} }
  const opened = []
  const props = { useMobileApprovals: select => select(state), useRoster: select => select(roster),
    useChat: () => { throw new Error('Internal member tool detail must not be read') }, actions: { openMobileApproval: id => opened.push(id) } }
  assert.equal(approvalSession(groupRequest, roster), 'room')
  assert.equal(approvalSession(groupRequest, { byId: {}, roomsById: {} }), null)
  assert.equal(MobileApprovalDock({ ...props, sessionId: 'hidden-member' }), null)
  assert.ok(MobileApprovalDock({ ...props, sessionId: 'room' }))
  const notice = MobileApprovalNotice({ ...props, useSessions: select => select({ byId: {} }) })
  nodes(notice, node => node.type === 'button')[0].props.onClick()
  assert.deepEqual(opened, ['room'])
})
