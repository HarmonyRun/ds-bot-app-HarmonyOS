import assert from 'node:assert/strict'
import test from 'node:test'
import { createManagement } from '../src/mobile/management.js'

function fixture() {
  const calls = []
  const pluginManager = {
    listPlugins: async () => [
      { entryId: 'mobile', moduleName: 'ds-bot', enabled: true, fiberPhase: 'active', config: { secret: 'fixture-secret' } },
      { entryId: 'mcp', moduleName: '@deepseek-ai/dsh-mcp', enabled: false, fiberPhase: null, meta: { title: { en: 'MCP', zh: 'MCP' }, description: 'Tools', icon: 'secret-icon' } },
      { entryId: 'protected', moduleName: 'management', enabled: true, readOnlyReason: 'management-required' },
    ],
    listBundles: async () => [
      { name: 'ds-bot', enabled: true, installed: true, rows: [{ moduleName: 'ds-bot', entryId: 'mobile' }] },
      { name: 'tools', enabled: true, installed: true, source: 'private-source', rows: [{ moduleName: 'tools' }], error: { code: 'operation-error', diagnostic: 'fixture-secret' } },
    ],
    setPluginEnabled: async (id, enabled) => { calls.push({ id, enabled }); return { changed: true, target: id, enabled, stage: 'enable', application: 'restart-required', packageResult: { output: 'fixture-secret' } } },
    setBundleEnabled: async (id, enabled) => { calls.push({ id, enabled }); return { changed: true, target: id, enabled, stage: 'enable', application: 'applied' } },
  }
  const scope = { session: { header: { cwd: '/owned/workspace' } } }
  const services = { pluginManager, workspaceRegistry: { get: id => id === 'workspace' ? { path: '/owned/workspace' } : undefined },
    skills: { list: async request => {
      calls.push(request)
      return [{ name: 'review', description: 'Review fixture-secret', provider: 'filesystem', source: 'project-dsh', path: '/private/SKILL.md', content: 'never return', resourceBase: { path: '/private' },
        invocation: { modelInvocable: true, userInvocable: false }, locator: 'private' }]
    } } }
  const rt = { ctx: {}, state: { workspaceId: 'workspace' }, readOnly: () => undefined, resolveAgent: async id => {
    assert.equal(id, 'owned-session'); return scope
  } }
  const action = createManagement(rt, { optional: name => services[name], redact: value => value.replaceAll('fixture-secret', '[redacted]'),
    conversation: async id => {
      if (id !== 'owned') throw Object.assign(new Error('Not found'), { status: 404 })
      return { sessionId: 'owned-session' }
    } })
  return { action: (endpoint, body = {}, signal = new AbortController().signal) => action(endpoint, body, signal), calls, rt, services, scope }
}

test('plugin inventory returns metadata and disables controls for the mobile bridge itself', async () => {
  const f = fixture()
  const result = await f.action('plugins-list')
  assert.equal(result.writable, true)
  assert.equal(result.plugins[0].readOnlyReason, 'mobile-required')
  assert.equal(result.bundles[0].readOnlyReason, 'mobile-required')
  assert.equal(result.bundles[1].readOnlyReason, undefined)
  const serialized = JSON.stringify(result)
  for (const hidden of ['fixture-secret', 'private-source', 'secret-icon', 'config']) assert.equal(serialized.includes(hidden), false)
  assert.equal(result.bundles[1].error.diagnostic, '[redacted]')
})

test('only installed mutable plugins can change and the original application outcome survives', async () => {
  const f = fixture()
  await assert.rejects(f.action('plugins-set-enabled', { id: 'mobile', enabled: false }), { status: 409 })
  await assert.rejects(f.action('plugins-set-enabled', { id: 'protected', enabled: false }), { status: 409 })
  await assert.rejects(f.action('plugins-set-enabled', { id: 'foreign', enabled: true }), { status: 404 })
  await assert.rejects(f.action('plugins-set-enabled', { id: 'mcp', enabled: 'true' }), { status: 400 })
  const result = await f.action('plugins-set-enabled', { id: 'mcp', enabled: true })
  assert.deepEqual(result, { changed: true, target: 'mcp', enabled: true, stage: 'enable', application: 'restart-required' })
  assert.equal((await f.action('bundle-set-enabled', { id: 'tools', enabled: false })).application, 'applied')
  assert.deepEqual(f.calls, [{ id: 'mcp', enabled: true }, { id: 'tools', enabled: false }])
  f.rt.readOnly = () => 'Locked'
  await assert.rejects(f.action('bundle-set-enabled', { id: 'tools', enabled: true }), { status: 409 })
})

test('revocation during plugin discovery prevents its deferred mutation', async () => {
  const f = fixture()
  const controller = new AbortController()
  const list = f.services.pluginManager.listPlugins
  f.services.pluginManager.listPlugins = async () => { controller.abort(); return list() }
  await assert.rejects(f.action('plugins-set-enabled', { id: 'mcp', enabled: true }, controller.signal), { name: 'AbortError' })
  assert.equal(f.calls.length, 0)
})

test('Skill discovery selects only the team workspace or an owned conversation and omits host paths and bodies', async () => {
  const f = fixture()
  const result = await f.action('skills-list')
  assert.equal(f.calls[0].cwd, '/owned/workspace')
  assert.equal(f.calls[0].scope, undefined)
  assert.equal(result.skills[0].description, 'Review [redacted]')
  for (const hidden of ['path', 'resourceBase', 'content', 'locator']) assert.equal(hidden in result.skills[0], false)
  await f.action('skills-list', { conversationId: 'owned' })
  assert.equal(f.calls[1].scope, f.scope)
  await assert.rejects(f.action('skills-list', { conversationId: 'foreign' }), { status: 404 })
  assert.equal(f.calls.length, 2)
})

test('package installs are pinned, scoped to their device and never repeated after a lost response', async () => {
  const f=fixture();let installed=0, finish
  f.services.pluginManager.inspect=async()=>({status:'accepted',kind:'registry',name:'fixture-bundle',version:'1.2.3',bundle:true})
  f.services.pluginManager.installBundle=async()=>{installed++;return new Promise(resolve=>finish=resolve)}
  const run=createManagement(f.rt,{optional:name=>f.services[name],conversation:async()=>({sessionId:'owned-session'}),redact:value=>value.replaceAll('fixture-secret','[redacted]')})
  const signal=new AbortController().signal,caller={deviceId:'device-one'}
  const inspected=await run('plugins-inspect',{spec:'fixture-bundle'},signal,caller);assert.equal(inspected.resolvedSpec,'fixture-bundle@1.2.3')
  await assert.rejects(run('plugins-install',{spec:'fixture-bundle',requestId:'unpinned'},signal,caller),{status:409})
  const body={spec:'fixture-bundle@1.2.3',requestId:'install-once'}
  const result=await run('plugins-install',body,signal,caller);assert.equal(result.status,'running')
  await run('plugins-install',body,signal,caller);assert.equal(installed,1)
  await assert.rejects(run('plugins-operation',{requestId:body.requestId},signal,{deviceId:'other'}),{status:404})
  await assert.rejects(run('plugins-install',{...body,spec:'other@1.2.3'},signal,caller),{status:409})
  finish({changed:true,application:'applied',stage:'install',packageResult:{output:'Bearer syntheticfixture cookie=fixture-secret',logPath:'/private/log'},version:'1.2.3'})
  await new Promise(resolve=>setImmediate(resolve))
  const done=await run('plugins-operation',{requestId:body.requestId},signal,caller);assert.equal(done.status,'finished');assert.equal(JSON.stringify(done).includes('syntheticfixture'),false);assert.equal(done.result.packageResult.logPath,undefined)
  for(const spec of ['file:/private','/private/package','https://name:credential@example.test/archive.tgz'])await assert.rejects(run('plugins-inspect',{spec},signal,caller),{status:400})
})
