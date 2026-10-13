import { randomUUID } from 'node:crypto'
import { BridgeError } from './auth.js'

const refused = (status, code, message) => new BridgeError(status, code, message)

// One owner for the borrowed public approval/request promise. Desktop and
// mobile answer the same record; no competing call to the downstream waterfall
// is left waiting after another device has answered.
export function createApprovalBroker({ resolveConversation, enabled, authorizeDevice, redact = text => text, now = Date.now, id = randomUUID }) {
  const pending = new Map()
  const listeners = new Set()
  let disposed = false
  const notify = () => { for (const listener of listeners) { try { listener() } catch {} } }
  function settle(entry, outcome) {
    if (pending.get(entry.view.id) !== entry) return false
    pending.delete(entry.view.id)
    entry.signal?.removeEventListener('abort', entry.cancel)
    entry.resolve(outcome)
    notify()
    return true
  }
  const publicView = entry => ({ ...entry.view, ...(entry.view.displayReason ? { displayReason: { ...entry.view.displayReason } } : {}) })
  async function handle(request, next) {
    if (disposed || !enabled() || pending.size >= 100) return next()
    const sessionId = request.agent?.session?.id
    if (typeof sessionId !== 'string') return next()
    const conversationId = await resolveConversation(sessionId)
    if (disposed) return 'unavailable'
    if (typeof conversationId !== 'string' || !conversationId || !enabled() || pending.size >= 100) return next()
    if (request.signal?.aborted) return 'cancelled'
    const view = { id: id(), conversationId, sessionId, toolName: String(request.toolName), createdAt: now() }
    if (typeof request.callId === 'string') view.callId = request.callId
    if (typeof request.reason === 'string') view.reason = String(redact(request.reason))
    if (request.displayReason && typeof request.displayReason === 'object') {
      view.displayReason = Object.fromEntries(Object.entries(request.displayReason).filter(([, value]) => typeof value === 'string')
        .map(([locale, value]) => [locale, String(redact(value))]))
    }
    return new Promise(resolve => {
      const entry = { view, signal: request.signal, resolve }
      entry.cancel = () => settle(entry, 'cancelled')
      pending.set(view.id, entry)
      request.signal?.addEventListener('abort', entry.cancel, { once: true })
      if (request.signal?.aborted) entry.cancel()
      else notify()
    })
  }
  async function decide(payload, deviceId) {
    if (disposed) throw refused(503, 'APPROVAL_UNAVAILABLE', 'Approval access has stopped.')
    if (deviceId !== undefined && (!deviceId || !await authorizeDevice(deviceId))) throw refused(401, 'UNAUTHORIZED', 'This device is no longer authorized.')
    if (!payload || typeof payload.id !== 'string' || !['allowed-once', 'rejected'].includes(payload.decision)) {
      throw refused(400, 'INVALID_APPROVAL', 'Choose Allow once or Reject for this request.')
    }
    const entry = pending.get(payload.id)
    if (!entry) throw refused(409, 'APPROVAL_SETTLED', 'This request is no longer pending. Refresh the request list.')
    const conversationId = await resolveConversation(entry.view.sessionId)
    if (conversationId !== entry.view.conversationId) {
      settle(entry, 'cancelled')
      throw refused(409, 'APPROVAL_SCOPE_CHANGED', 'This request no longer belongs to the same conversation.')
    }
    // A device can be revoked while ownership validation is awaiting the host.
    if (deviceId !== undefined && !await authorizeDevice(deviceId)) throw refused(401, 'UNAUTHORIZED', 'This device is no longer authorized.')
    if (entry.signal?.aborted) settle(entry, 'cancelled')
    if (!settle(entry, payload.decision)) throw refused(409, 'APPROVAL_SETTLED', 'This request is no longer pending. Refresh the request list.')
    return { accepted: true }
  }
  return {
    handle,
    list: () => ({ requests: [...pending.values()].map(publicView) }),
    async resolveForDevice(deviceId, payload) {
      if (typeof deviceId !== 'string' || !deviceId) throw refused(401, 'UNAUTHORIZED', 'This device is no longer authorized.')
      return decide(payload, deviceId)
    },
    resolveForDesktop: payload => decide(payload),
    subscribe(listener) { listeners.add(listener); return () => listeners.delete(listener) },
    dispose() {
      disposed = true
      for (const entry of pending.values()) settle(entry, 'unavailable')
      listeners.clear()
    },
  }
}
