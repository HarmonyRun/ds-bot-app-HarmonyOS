import { detail } from './projection.js'
const failure = (status, code, message) => Object.assign(new Error(message), { status, code })
export const MANAGEMENT_ACTIONS = {
  'plugins-list': [], 'plugins-set-enabled': ['id', 'enabled'], 'bundle-set-enabled': ['id', 'enabled'],
  'skills-list': ['conversationId'],
  'skills-get': ['conversationId', 'name'],
  'skills-library': [], 'skills-save': ['name', 'description', 'content', 'modelInvocable', 'userInvocable', 'expectedRevision'], 'skills-delete': ['name', 'expectedRevision'],
  'plugins-inspect': ['spec'], 'plugins-install': ['spec', 'requestId', 'approvedBuilds'],
  'plugins-remove': ['id', 'requestId'], 'plugins-operation': ['requestId'], 'plugins-cancel': ['requestId'],
}

export function createManagement(rt, { optional, conversation, redact }) {
  const operations = new Map()
  rt.ctx.on?.('plugin-manager/install-state', progress => {
    const operation = [...operations.values()].find(item => item.hostId === progress.requestId)
    if (operation) operation.progress = { phase: progress.phase, ...(progress.attempt ? { attempt: { index: progress.attempt.index, total: progress.attempt.total } } : {}) }
  })
  const requestKey = (body, caller) => {
    if (typeof body.requestId !== 'string' || !/^[A-Za-z0-9_-]{1,100}$/.test(body.requestId)) throw failure(400, 'mobile/invalid', 'A stable operation request ID is required')
    return `${caller.deviceId ?? 'operator'}_${body.requestId}`
  }
  const specOf = value => {
    if (typeof value !== 'string' || value.length > 1024 || /[\s\x00-\x1f]/.test(value) || !value) throw failure(400, 'mobile/invalid', 'Enter a package name, Git repository or HTTPS archive')
    if (/^(file:|link:|\/|\.|~|[a-z]:)/i.test(value) && !/^https:/i.test(value)) throw failure(400, 'mobile/invalid', 'Install local paths from the host; mobile accepts registry packages, Git repositories and HTTPS archives')
    if (value.includes('://')) {
      let url
      try { url = new URL(value.replace(/^git\+/, '')) } catch { throw failure(400, 'mobile/invalid', 'Invalid package address') }
      if (url.protocol !== 'https:' || url.username || url.password || url.search || url.hash) throw failure(400, 'mobile/invalid', 'Use an HTTPS package address without credentials or query parameters')
    }
    return value
  }
  const text = value => typeof value === 'string' ? detail(value, 8000, redact).text : undefined
  const localized = value => typeof value === 'string' ? text(value) : value && typeof value === 'object'
    ? Object.fromEntries(Object.entries(value).filter(([locale, entry]) => /^[a-z][\w-]{0,31}$/i.test(locale) && typeof entry === 'string').map(([locale, entry]) => [locale, text(entry)])) : undefined
  const meta = value => value ? { title: localized(value.title), description: localized(value.description), error: text(value.error) } : undefined
  const diagnostic = value => value ? { code: text(value.code), diagnostic: text(value.diagnostic) } : undefined
  const selfModule = name => name === 'ds-bot' || /(?:^|[/\\])ds-bot(?:[/\\](?:index\.js)?)?$/.test(name)
  const ownEntry = id => typeof id === 'string' && id === rt.ctx.fiber?.entry?.id
  const selfEntry = item => ownEntry(item.entryId) || selfModule(item.moduleName)
  const selfBundle = item => item.name === 'ds-bot' || item.rows?.some(row => selfModule(row.moduleName) || ownEntry(row.entryId))
  const plugin = item => ({ entryId: item.entryId, moduleName: text(item.moduleName), enabled: item.enabled === true,
    fiberPhase: item.fiberPhase ?? null, meta: meta(item.meta),
    ...(selfEntry(item) ? { readOnlyReason: 'mobile-required' } : item.readOnlyReason ? { readOnlyReason: item.readOnlyReason } : {}) })
  const bundle = item => ({ name: item.name, version: text(item.version), description: text(item.description), meta: meta(item.meta),
    enabled: item.enabled === true, installed: item.installed === true, optional: item.optional === true, removable: item.removable === true && !selfBundle(item),
    ...(selfBundle(item) ? { readOnlyReason: 'mobile-required' } : item.readOnlyReason ? { readOnlyReason: item.readOnlyReason } : {}),
    ...(item.error ? { error: diagnostic(item.error) } : {}) })
  async function skills(body, signal, load = false) {
    const service = optional('skills')
    if (!service?.list) return { available: false, skills: [] }
    let scope
    let cwd = optional('workspaceRegistry')?.get(rt.state?.workspaceId)?.path
    if (body.conversationId !== undefined) {
      const target = await conversation(body.conversationId)
      signal.throwIfAborted()
      if (typeof rt.resolveAgent !== 'function') throw failure(503, 'mobile/unavailable', 'Agent skill discovery is unavailable on this host')
      scope = await rt.resolveAgent(target.sessionId)
      cwd = scope.session.header.cwd
    }
    signal.throwIfAborted()
    if (load) {
      if (typeof body.name !== 'string' || !/^[a-z0-9]+(?:-[a-z0-9]+)*$/.test(body.name)) throw failure(400, 'mobile/invalid', 'Choose a listed skill name')
      const selected = (await service.list({ cwd, scope, signal })).find(item => item.name === body.name && item.invocation?.userInvocable)
      if (!selected || !service.get) throw failure(404, 'mobile/not-found', 'This skill is not available for user invocation')
      const skill = await service.get(body.name, { cwd, scope, signal })
      signal.throwIfAborted()
      if (!skill?.invocation?.userInvocable) throw failure(404, 'mobile/not-found', 'This skill is no longer available')
      const content = String(redact(skill.content ?? ''))
      return { name: skill.name, description: text(skill.description), content: content.slice(0, 128 * 1024), truncated: content.length > 128 * 1024,
        invocation: skill.invocation, source: text(skill.source), provider: text(skill.provider) }
    }
    const entries = await service.list({ cwd, scope, signal })
    signal.throwIfAborted()
    return { available: true, skills: entries.map(item => ({ name: item.name, description: text(item.description),
      whenToUse: text(item.whenToUse), source: text(item.source), provider: text(item.provider),
      invocation: { modelInvocable: item.invocation?.modelInvocable === true, userInvocable: item.invocation?.userInvocable === true } })) }
  }
  const changeView = result => ({ changed: result.changed === true, application: result.application, stage: result.stage, target: text(result.target),
    ...(typeof result.enabled === 'boolean' ? { enabled: result.enabled } : {}), ...(result.error ? { error: diagnostic(result.error) } : {}),
    ...(Array.isArray(result.warnings) ? { warnings: result.warnings.map(text) } : {}),
    ...(['install', 'remove'].includes(result.stage) && result.packageResult ? { packageResult: { kind: result.packageResult.kind, exitCode: result.packageResult.exitCode, truncated: result.packageResult.truncated, output: text(result.packageResult.output) } } : {}),
    ...(result.pendingBuilds ? { pendingBuilds: result.pendingBuilds.map(text) } : {}), ...(result.version ? { version: text(result.version) } : {}) })
  return async function management(endpoint, body, signal, caller = {}) {
    if (['skills-library', 'skills-save', 'skills-delete'].includes(endpoint)) {
      if (!rt.mobileSkills) throw failure(503, 'mobile/unavailable', 'The mobile skill library is unavailable on this host')
      return endpoint === 'skills-library' ? rt.mobileSkills.snapshot() : endpoint === 'skills-save' ? rt.mobileSkills.save(body, signal) : rt.mobileSkills.remove(body, signal)
    }
    if (endpoint === 'skills-list' || endpoint === 'skills-get') return skills(body, signal, endpoint === 'skills-get')
    const manager = optional('pluginManager')
    if (!manager?.listPlugins || !manager?.listBundles) throw failure(503, 'mobile/unavailable', 'Plugin management is unavailable on this host')
    if (endpoint === 'plugins-operation' || endpoint === 'plugins-cancel') {
      const operation = operations.get(requestKey(body, caller))
      if (!operation) throw failure(404, 'mobile/not-found', 'This operation is not tracked for this device. Check the host before retrying.')
      if (endpoint === 'plugins-cancel') {
        if (operation.kind !== 'install' || operation.status !== 'running') return { status: 'not-running' }
        const cancelled = await manager.cancelInstall(operation.hostId)
        signal.throwIfAborted()
        return cancelled
      }
      return { requestId: body.requestId, kind: operation.kind, status: operation.status, progress: operation.progress, result: operation.result, error: operation.error }
    }
    if (endpoint === 'plugins-inspect') {
      if (!manager.inspect) throw failure(503, 'mobile/unavailable', 'Package inspection is unavailable on this host')
      const result = await manager.inspect(specOf(body.spec), undefined, signal)
      signal.throwIfAborted()
      return { status: result.status, kind: result.kind, name: text(result.name), version: text(result.version), description: text(result.description), bundle: result.bundle, ...(result.kind === 'registry' && result.name && result.version ? { resolvedSpec: `${result.name}@${result.version}` } : {}),
        ...(result.problem ? { problem: result.problem, reason: text(result.reason) } : {}) }
    }
    const [plugins, bundles] = await Promise.all([manager.listPlugins(), manager.listBundles()])
    signal.throwIfAborted()
    if (endpoint === 'plugins-list') return { writable: rt.readOnly?.() === undefined, plugins: plugins.map(plugin), bundles: bundles.map(bundle),
      operations: [...operations.values()].filter(item => item.deviceId === caller.deviceId).map(item => ({ requestId: item.requestId, kind: item.kind, status: item.status, progress: item.progress, result: item.result, error: item.error })) }
    if (rt.readOnly?.() !== undefined) throw failure(409, 'mobile/read-only', 'This host is read-only')
    if (endpoint === 'plugins-install' || endpoint === 'plugins-remove') {
      const key = requestKey(body, caller)
      const identity = JSON.stringify({ endpoint, spec: body.spec, id: body.id, approvedBuilds: body.approvedBuilds ?? [] })
      const previous = operations.get(key)
      if (previous) {
        if (previous.identity !== identity) throw failure(409, 'mobile/request-conflict', 'This request ID belongs to a different package operation')
        return { requestId: body.requestId, kind: previous.kind, status: previous.status, progress: previous.progress, result: previous.result }
      }
      if ([...operations.values()].some(item => item.status === 'running')) throw failure(409, 'mobile/plugin-busy', 'Another package operation is still running. Wait for its result.')
      if (operations.size >= 200) {
        for (const [id, item] of operations) if (item.status !== 'running') { operations.delete(id); break }
      }
      let run
      if (endpoint === 'plugins-install') {
        if (!manager.installBundle || !manager.inspect) throw failure(503, 'mobile/unavailable', 'Package installation is unavailable on this host')
        const spec = specOf(body.spec)
        if (body.approvedBuilds !== undefined && (!Array.isArray(body.approvedBuilds) || body.approvedBuilds.length > 100 || body.approvedBuilds.some(name => typeof name !== 'string' || !/^(@[\w.-]+\/)?[\w.-]+$/.test(name)))) throw failure(400, 'mobile/invalid', 'Choose only the named packages awaiting build approval')
        const inspected = await manager.inspect(spec, undefined, signal)
        signal.throwIfAborted()
        if (inspected.status !== 'accepted') throw failure(400, 'mobile/package-refused', 'The host refused this package. Inspect it again before installing.')
        if (selfModule(inspected.name)) throw failure(409, 'mobile/required-plugin', 'Update DS Bot through its dedicated update flow on the host')
        if (inspected.kind === 'registry' && inspected.name && inspected.version && spec !== `${inspected.name}@${inspected.version}`) throw failure(409, 'mobile/package-changed', 'Inspect and confirm the exact registry package version before installing')
        run = () => manager.installBundle(spec, { requestId: key, ...(body.approvedBuilds ? { approvedBuilds: body.approvedBuilds } : {}) })
      } else {
        const item = bundles.find(item => item.name === body.id)
        if (!item) throw failure(404, 'mobile/not-found', 'This bundle is not installed')
        if (selfBundle(item) || item.readOnlyReason || !item.removable) throw failure(409, 'mobile/protected-plugin', 'The host protects this bundle from removal')
        run = () => manager.removeBundle(body.id)
      }
      signal.throwIfAborted()
      if (rt.readOnly?.() !== undefined) throw failure(409, 'mobile/read-only', 'This host is read-only')
      const concurrent = operations.get(key)
      if (concurrent) {
        if (concurrent.identity !== identity) throw failure(409, 'mobile/request-conflict', 'This request ID belongs to a different package operation')
        return { requestId: body.requestId, kind: concurrent.kind, status: concurrent.status, progress: concurrent.progress, result: concurrent.result }
      }
      if ([...operations.values()].some(item => item.status === 'running')) throw failure(409, 'mobile/plugin-busy', 'Another package operation is still running. Wait for its result.')
      const operation = { identity, hostId: key, deviceId: caller.deviceId, requestId: body.requestId, kind: endpoint === 'plugins-install' ? 'install' : 'remove', status: 'running' }
      operations.set(key, operation)
      // Accepted package work outlives an HTTP response; never replay on a lost reply.
      void Promise.resolve().then(run).then(result => { operation.result = changeView(result); operation.status = 'finished' }, () => {
        operation.error = 'The package operation failed. Check the host diagnostics before retrying.'; operation.status = 'failed'
      })
      return { requestId: body.requestId, kind: operation.kind, status: operation.status }
    }
    if (typeof body.id !== 'string' || body.id.length > 512 || typeof body.enabled !== 'boolean') throw failure(400, 'mobile/invalid', 'Choose an installed plugin and its enabled state')
    const isBundle = endpoint === 'bundle-set-enabled'
    const item = (isBundle ? bundles : plugins).find(entry => (isBundle ? entry.name : entry.entryId) === body.id)
    if (!item) throw failure(404, 'mobile/not-found', 'This plugin or bundle is not installed on the host')
    if ((isBundle ? selfBundle(item) : selfEntry(item))) throw failure(409, 'mobile/required-plugin', 'Manage DS Bot from the host to keep this mobile connection available')
    if (item.readOnlyReason) throw failure(409, 'mobile/protected-plugin', 'The host protects this plugin from direct changes')
    signal.throwIfAborted()
    let result
    try { result = await (isBundle ? manager.setBundleEnabled(body.id, body.enabled) : manager.setPluginEnabled(body.id, body.enabled)) }
    catch { throw failure(400, 'mobile/plugin-change-failed', 'The host refused this plugin change. Refresh its state and check the host diagnostics.') }
    return changeView(result)
  }
}
