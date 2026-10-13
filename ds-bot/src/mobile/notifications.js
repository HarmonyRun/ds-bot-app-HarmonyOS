import { mkdir, readFile, rename, writeFile } from 'node:fs/promises'
import { join } from 'node:path'
import { randomBytes } from 'node:crypto'
import { BridgeError, digest } from './auth.js'
const kinds = { reply: 'Bot 有新回复', question: 'Bot 等待你的回答', approval: '工具需要你的确认' }
export async function createNotificationHub({ home, adapter, authorized, active, sendPush, pollMs = 8000 }) {
  const path = join(home, 'notifications.json')
  let state = { cursor: 0, items: [], seen: [], devices: {} }
  try { state = JSON.parse(await readFile(path, 'utf8')) } catch (error) { if (error.code !== 'ENOENT') throw new Error('The notification inbox could not be loaded') }
  if (!Number.isSafeInteger(state.cursor) || !Array.isArray(state.items) || !Array.isArray(state.seen) || !state.devices || typeof state.devices !== 'object') throw new Error('Invalid notification inbox')
  state.lastReply ||= {}
  state.startedAt ||= Date.now()
  const watchers = new Map(), tokens = new Map(), background = new Map()
  const dropBackground = id => { for (const [hash, lease] of background) if (lease.deviceId === id) background.delete(hash) }
  function backgroundLease(token) {
    const lease = typeof token === 'string' && /^[A-Za-z0-9_-]{43}$/.test(token) ? background.get(digest(token)) : undefined
    if (!lease || lease.expiresAt <= Date.now() || !authorized(lease.deviceId)) throw new BridgeError(401, 'BACKGROUND_UNAUTHORIZED', 'Open the App to reconnect background notifications')
    return lease
  }
  let writes = Promise.resolve(), stopped = false, polling = false
  const persist = () => { const serialized = JSON.stringify(state); const work = writes.then(async () => { await mkdir(home, { recursive: true }); await writeFile(path + '.tmp', serialized, {mode:0o600}); await rename(path + '.tmp', path) }); writes = work.catch(() => {}); return work }
  async function notify(key, conversationId, kind) {
    if (stopped || state.seen.includes(key)) return
    const item = { id: ++state.cursor, conversationId, kind, title: kinds[kind], createdAt: Date.now() }
    state.items.push(item); state.items = state.items.slice(-500)
    state.seen.push(key); state.seen = state.seen.slice(-2000)
    await persist()
    const destinations = [...tokens].filter(([id]) => authorized(id) && state.devices[id]?.enabled !== false && state.devices[id]?.categories?.includes(kind)).map(([, value]) => value)
    if (destinations.length && sendPush) await sendPush(destinations, item).catch(() => {})
  }
  async function follow(item, controller) {
    try {
      for await (const frame of adapter.follow(item.id, {}, controller.signal)) {
        if (controller.signal.aborted || stopped) break
        if (frame.type === 'reset') {
          const message = frame.messages?.findLast(message => message.role === 'assistant' && !message.pending && (message.text || message.attachments?.length))
          if (message && state.lastReply[item.id] !== message.id) {
            const previous = state.lastReply[item.id]; state.lastReply[item.id] = message.id
            if (previous || new Date(message.createdAt).getTime() >= state.startedAt) await notify('reply:' + message.id, item.id, 'reply')
            else await persist()
          }
        }
        if (frame.type === 'message' && frame.message?.role === 'assistant' && !frame.message.pending && (frame.message.text || frame.message.attachments?.length)) { state.lastReply[item.id] = frame.message.id; await notify('reply:' + frame.message.id, item.id, 'reply') }
      }
    } catch { /* Public streams can disappear when a session is archived. Rediscover it. */ }
    finally { if (watchers.get(item.id)?.controller === controller) watchers.delete(item.id) }
  }
  async function poll() {
    if (stopped || polling) return
    polling = true
    try {
      for (const id of tokens.keys()) if (!authorized(id)) tokens.delete(id)
      if (!active()) { for (const entry of watchers.values()) entry.controller.abort(); watchers.clear(); return }
      const result = await adapter.conversations()
      if (stopped) return
      const items = result.conversations.slice(0, 200)
      const ids = new Set(items.map(item => item.id))
      for (const [id, entry] of watchers) if (!ids.has(id)) { entry.controller.abort(); watchers.delete(id) }
      for (const item of items) {
        if (!watchers.has(item.id)) { const controller = new AbortController(); const entry = {controller}; watchers.set(item.id, entry); entry.job = follow(item, controller) }
      }
      if (adapter.state) {
        const view = await adapter.state()
        for (const question of Object.values(view.questions || {})) if (question.id && ids.has(question.conversationId)) await notify('question:' + question.id, question.conversationId, 'question')
      }
      if (adapter.action) {
        const approvals = await adapter.action('approvals', {})
        for (const request of approvals.requests || []) if (request.conversationId) await notify('approval:' + request.id, request.conversationId, 'approval')
      }
    } catch { /* Keep the durable inbox available while the host reconnects. */ }
    finally { polling = false }
  }
  let pollJob
  const refresh = () => { if (!pollJob) pollJob = poll().finally(() => { pollJob = undefined }); return pollJob }
  const timer = setInterval(() => void refresh(), pollMs); timer.unref?.()
  return {
    poll: refresh,
    backgroundDevice(token) { return backgroundLease(token).deviceId },
    async backgroundPoll(token, cursor, signal) {
      const lease = backgroundLease(token)
      if (!Number.isSafeInteger(cursor) || cursor < 0 || cursor > state.cursor) throw new BridgeError(400, 'INVALID_CURSOR', 'Invalid notification cursor')
      await refresh()
      const inbox = await this.action('notifications-list', {}, lease.deviceId, signal)
      if (backgroundLease(token) !== lease) throw new BridgeError(401, 'BACKGROUND_UNAUTHORIZED', 'Background registration changed')
      return { cursor: inbox.cursor, expiresAt: lease.expiresAt, deliveryEnabled: inbox.preferences.enabled && !inbox.pushRegistered, items: inbox.items.filter(item => item.id > cursor && !item.read && inbox.preferences.categories.includes(item.kind)).reverse().map(({read, ...item}) => item) }
    },
    async action(endpoint, body, deviceId, signal) {
      signal?.throwIfAborted()
      if (!authorized(deviceId)) throw new BridgeError(401, 'UNAUTHORIZED', 'This device is no longer authorized')
      const prefs = state.devices[deviceId] || { enabled: true, categories: ['reply','question','approval'], readThrough: 0 }
      const visible = new Set((await adapter.conversations()).conversations.map(item => item.id))
      signal?.throwIfAborted()
      if (!authorized(deviceId)) throw new BridgeError(401, 'UNAUTHORIZED', 'This device is no longer authorized')
      if (endpoint === 'notifications-list') return { items: state.items.filter(item => visible.has(item.conversationId)).slice(-100).reverse().map(item => ({ ...item, read: item.id <= prefs.readThrough || prefs.readIds?.includes(item.id) === true })), preferences: prefs, cursor:state.cursor, pushRegistered: tokens.has(deviceId), pushAvailable:!!sendPush }
      if (endpoint === 'notifications-read') {
        if (Array.isArray(body.ids)) {
          if (body.ids.length > 100 || body.ids.some(id => !Number.isSafeInteger(id) || !state.items.some(item => item.id === id && visible.has(item.conversationId)))) throw new BridgeError(400,'INVALID_REQUEST','Choose visible notifications')
          state.devices[deviceId] = { ...prefs, readIds: [...new Set([...(prefs.readIds || []), ...body.ids])].slice(-500) }; await persist(); return {ok:true}
        }
        if (!Number.isSafeInteger(body.through) || body.through < 0 || body.through > state.cursor) throw new BridgeError(400, 'INVALID_REQUEST', 'Invalid notification cursor')
        state.devices[deviceId] = { ...prefs, readThrough: Math.max(prefs.readThrough, body.through) }; await persist(); return {ok:true}
      }
      if (endpoint === 'notifications-preferences') {
        if (typeof body.enabled !== 'boolean' || !Array.isArray(body.categories) || body.categories.some(kind => !Object.hasOwn(kinds,kind))) throw new BridgeError(400, 'INVALID_REQUEST', 'Choose the notification categories')
        state.devices[deviceId] = { ...prefs, enabled:body.enabled, categories:[...new Set(body.categories)] }; if (!body.enabled) { tokens.delete(deviceId); dropBackground(deviceId) }; await persist(); return {ok:true}
      }
      if (endpoint === 'notifications-background-register') {
        if (!prefs.enabled) throw new BridgeError(409, 'NOTIFICATIONS_DISABLED', 'Enable notifications for this device first')
        dropBackground(deviceId)
        const token = randomBytes(32).toString('base64url'), expiresAt = Date.now() + 24 * 60 * 60_000
        background.set(digest(token), { deviceId, expiresAt })
        return { token, expiresAt, cursor: state.cursor }
      }
      if (endpoint === 'notifications-background-unregister') { dropBackground(deviceId); return {ok:true} }
      if (endpoint === 'notifications-register') {
        if (!sendPush) throw new BridgeError(503,'PUSH_UNAVAILABLE','Push delivery is unavailable')
        if (typeof body.token !== 'string' || !/^(Expo|Exponent)PushToken\[[a-zA-Z0-9_-]{8,200}\]$/.test(body.token)) throw new BridgeError(400,'INVALID_REQUEST','Invalid Expo push registration')
        tokens.set(deviceId,body.token); return {ok:true}
      }
      if (endpoint === 'notifications-unregister') { tokens.delete(deviceId); return {ok:true} }
      if (endpoint === 'notifications-test') { if (!tokens.has(deviceId)) throw new BridgeError(409,'PUSH_NOT_REGISTERED','Enable system notifications first'); await sendPush([tokens.get(deviceId)],{id:0,kind:'test',title:'DS Bot 通知测试',createdAt:Date.now()}); return {ok:true} }
      throw new BridgeError(404,'NOT_FOUND','Unknown notification action')
    },
    revoke(id) { tokens.delete(id); dropBackground(id); delete state.devices[id]; void persist().catch(() => {}) },
    async close() { stopped=true; clearInterval(timer); const jobs = [...watchers.values()]; for(const entry of jobs)entry.controller.abort(); tokens.clear(); background.clear(); await Promise.allSettled(jobs.map(entry=>entry.job)); await pollJob?.catch(() => {}); await writes }
  }
}
export async function expoPush(tokens, item, serverId) {
  for (let start=0; start<tokens.length; start+=100) {
    const result=await fetch('https://exp.host/--/api/v2/push/send', {method:'POST',headers:{'content-type':'application/json'},signal:AbortSignal.timeout(7000),body:JSON.stringify(tokens.slice(start,start+100).map(to=>({to,title:item.title,body:'打开 DS Bot 查看详情',sound:'default',channelId:'ds-bot',data:{serverId,conversationId:item.conversationId,notificationId:item.id},priority:'high',ttl:3600})))})
    if(!result.ok)throw new Error('Push relay did not accept this notification')
    const response=await result.json()
    if(response.errors?.length || response.data?.some(item=>item.status==='error'))throw new Error('Push registration needs attention')
  }
}
