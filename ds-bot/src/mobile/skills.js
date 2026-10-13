import { mkdir, readFile, rename, writeFile } from 'node:fs/promises'
import { join } from 'node:path'

export async function createSkillLibrary({ home, service, readOnly = () => undefined, redact = value => value }) {
  const path = join(home, 'skills.json')
  let state = { revision: 0, skills: [] }
  try { state = JSON.parse(await readFile(path, 'utf8')) } catch (error) { if (error.code !== 'ENOENT') throw new Error('The mobile skill library could not be loaded') }
  if (!Number.isSafeInteger(state.revision) || state.revision < 0 || !Array.isArray(state.skills) || state.skills.length > 100 || state.skills.some(skill => !skill || typeof skill.name !== 'string' || !/^[a-z0-9]+(?:-[a-z0-9]+)*$/.test(skill.name) || skill.name.length > 100 || typeof skill.content !== 'string' || skill.content.length > 65536 || typeof skill.description !== 'string' || skill.description.length > 2000 || typeof skill.invocation?.modelInvocable !== 'boolean' || typeof skill.invocation?.userInvocable !== 'boolean') || new Set(state.skills.map(skill => skill.name)).size !== state.skills.length) throw new Error('Invalid mobile skill library')
  let control
  const provider = 'ds-bot-mobile-skills'
  const off = service.registerProvider(value => {
    control = value
    return { name: provider,
      list: async ({ signal }) => { signal?.throwIfAborted(); return state.skills.map(({ content: _, ...skill }) => ({ ...skill, rank: 700, locator: skill.name, source: provider, provider })) },
      get: async (candidate, { signal }) => { signal?.throwIfAborted(); const skill = state.skills.find(item => item.name === candidate.name); return skill ? { ...skill, source: provider, provider } : undefined },
    }
  })
  let writes = Promise.resolve()
  const snapshot = () => ({ revision: state.revision, skills: state.skills.map(skill => ({ ...skill, invocation: { ...skill.invocation }, content: String(redact(skill.content)), description: String(redact(skill.description)) })) })
  const fail = (status, message) => { throw Object.assign(new Error(message), { status, code: 'mobile/skill-library' }) }
  const mutate = (body, signal, remove) => {
    const run = writes.then(async () => {
      signal.throwIfAborted()
      if (readOnly() !== undefined) fail(409, 'This host is read-only')
      if (body.expectedRevision !== state.revision) fail(409, 'The skill library changed. Refresh before saving.')
      if (typeof body.name !== 'string' || !/^[a-z0-9]+(?:-[a-z0-9]+)*$/.test(body.name) || body.name.length > 100) fail(400, 'Use a kebab-case skill name')
      let skills = state.skills.filter(item => item.name !== body.name)
      if (remove && skills.length === state.skills.length) fail(404, 'This skill is not managed by the mobile library')
      if (!remove) {
        if (typeof body.description !== 'string' || !body.description.trim() || body.description.length > 2000 || typeof body.content !== 'string' || !body.content.trim() || body.content.length > 65536) fail(400, 'A description and instructions up to 64 KiB are required')
        if (typeof body.modelInvocable !== 'boolean' || typeof body.userInvocable !== 'boolean') fail(400, 'Choose the invocation permissions')
        if (skills.length >= 100) fail(413, 'The mobile skill library supports at most 100 skills')
        skills.push({ name: body.name, description: body.description.trim(), content: body.content, invocation: { modelInvocable: body.modelInvocable, userInvocable: body.userInvocable } })
      }
      const next = { revision: state.revision + 1, skills: skills.sort((a, b) => a.name.localeCompare(b.name)) }
      await mkdir(home, { recursive: true })
      await writeFile(path + '.tmp', JSON.stringify(next), { mode: 0o600 })
      signal.throwIfAborted()
      await rename(path + '.tmp', path)
      state = next
      control.invalidate()
      return snapshot()
    })
    writes = run.catch(() => {})
    return run
  }
  return { snapshot, save: (body, signal) => mutate(body, signal, false), remove: (body, signal) => mutate(body, signal, true), dispose: async () => { await writes; off() } }
}
