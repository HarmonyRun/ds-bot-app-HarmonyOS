import assert from 'node:assert/strict'
import { test } from 'node:test'
import { groupsFor, readMode, surfaceGroups, writeMode } from '../src/client/surface.js'
import { STORAGE } from '../src/client/storage.js'

test('Bot mode mounts both groups; Agent mode mounts neither', () => {
  assert.deepEqual(groupsFor({ mode: 'bot' }), { shell: true, conversation: true })
  assert.deepEqual(groupsFor({ mode: 'bot', plain: false }), { shell: true, conversation: true })
  assert.deepEqual(groupsFor({ mode: 'agent' }), { shell: false, conversation: false })
  assert.deepEqual(groupsFor({ mode: 'agent', plain: true }), { shell: false, conversation: false })
})

test('a plain Bot-mode view keeps the shell but drops the conversation', () => {
  assert.deepEqual(groupsFor({ mode: 'bot', plain: true }), { shell: true, conversation: false })
})

test('the saved surface mode survives reloads and defaults to bot', () => {
  const store = new Map()
  const storage = {
    getItem: key => (store.has(key) ? store.get(key) : null),
    setItem: (key, value) => store.set(key, value),
    removeItem: key => store.delete(key),
  }
  assert.equal(readMode(storage), 'bot')
  writeMode('agent', storage)
  assert.equal(readMode(storage), 'agent')
  writeMode('bot', storage)
  assert.equal(readMode(storage), 'bot')
  store.set(STORAGE.surface, 'nonsense')
  assert.equal(readMode(storage), 'bot')
})

const recordingGroups = (log, { failing = null } = {}) => {
  const entry = (name) => () => {
    log.push(name)
    if (name === failing) throw new Error(`could not release ${name}`)
  }
  return surfaceGroups({
    shell: () => { log.push('install shell'); return [entry('shell styles'), entry('shell theme')] },
    conversation: () => { log.push('install conversation'); return [entry('conversation styles'), entry('conversation tokens'), entry('conversation cells')] },
  })
}

test('switching to Agent mode withdraws the conversation before the shell, last entry first', (t) => {
  t.mock.method(console, 'warn', () => {})
  const log = []
  const groups = recordingGroups(log)
  groups.reconcile(groupsFor({ mode: 'bot' }))
  assert.deepEqual(log, ['install shell', 'install conversation'])
  log.length = 0
  groups.reconcile(groupsFor({ mode: 'agent' }))
  assert.deepEqual(log, ['conversation cells', 'conversation tokens', 'conversation styles', 'shell theme', 'shell styles'])
})

test('a throwing disposer does not stop the rest, and the group can be installed again', (t) => {
  const warn = t.mock.method(console, 'warn', () => {})
  const log = []
  const groups = recordingGroups(log, { failing: 'conversation tokens' })
  groups.reconcile(groupsFor({ mode: 'bot' }))
  log.length = 0
  assert.doesNotThrow(() => groups.reconcile(groupsFor({ mode: 'agent' })))
  assert.deepEqual(log, ['conversation cells', 'conversation tokens', 'conversation styles', 'shell theme', 'shell styles'])
  assert.equal(warn.mock.callCount(), 1)
  log.length = 0
  groups.reconcile(groupsFor({ mode: 'bot' }))
  assert.deepEqual(log, ['install shell', 'install conversation'])
})

test('unloading the plugin disposes every group even when a disposer throws', (t) => {
  t.mock.method(console, 'warn', () => {})
  const log = []
  const groups = recordingGroups(log, { failing: 'conversation cells' })
  groups.reconcile(groupsFor({ mode: 'bot' }))
  log.length = 0
  assert.doesNotThrow(() => groups.dispose())
  assert.deepEqual(log, ['conversation cells', 'conversation tokens', 'conversation styles', 'shell theme', 'shell styles'])
  log.length = 0
  groups.dispose()
  assert.deepEqual(log, [])
})

test('a group whose install throws stays unmounted and is tried again', (t) => {
  t.mock.method(console, 'warn', () => {})
  let attempts = 0
  const groups = surfaceGroups({
    shell: () => [() => {}],
    conversation: () => { attempts += 1; if (attempts === 1) throw new Error('slot refused'); return [() => {}] },
  })
  assert.doesNotThrow(() => groups.reconcile(groupsFor({ mode: 'bot' })))
  groups.reconcile(groupsFor({ mode: 'bot', plain: true }))
  groups.reconcile(groupsFor({ mode: 'bot' }))
  assert.equal(attempts, 2)
})

test('readMode falls back to bot when storage throws', () => {
  assert.equal(readMode({ getItem: () => { throw new Error('denied') } }), 'bot')
})
