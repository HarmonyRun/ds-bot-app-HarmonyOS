import test from 'node:test'
import assert from 'node:assert/strict'
import { mkdtemp, rm } from 'node:fs/promises'
import { tmpdir } from 'node:os'
import { join } from 'node:path'
import { createSkillLibrary } from '../src/mobile/skills.js'
test('the mobile library survives restart, scopes its own edits and detects concurrent saves', async t => {
  const home = await mkdtemp(join(tmpdir(),'ds-bot-skills-')); t.after(()=>rm(home,{recursive:true,force:true}))
  let provider, invalidated=0, removed=0
  const service={registerProvider(factory){provider=factory({invalidate(){invalidated++}});return()=>removed++}}
  let library=await createSkillLibrary({home,service});t.after(()=>library.dispose())
  const signal=new AbortController().signal
  const body={name:'mobile-review',description:'Review work',content:'# Review\nCheck evidence.',modelInvocable:false,userInvocable:true,expectedRevision:0}
  const results=await Promise.allSettled([library.save(body,signal),library.save({...body,content:'Other instructions'},signal)])
  assert.equal(results.filter(item=>item.status==='fulfilled').length,1)
  assert.equal(results.find(item=>item.status==='rejected').reason.status,409)
  assert.equal(invalidated,1)
  const candidates=await provider.list({signal});assert.equal(candidates[0].rank,700);assert.equal(candidates[0].content,undefined)
  assert.equal((await provider.get(candidates[0],{signal})).content,body.content)
  await assert.rejects(library.remove({name:'built-in',expectedRevision:1},signal),{status:404})
  await library.dispose();assert.equal(removed,1)
  library=await createSkillLibrary({home,service});assert.equal(library.snapshot().revision,1)
  await library.remove({name:body.name,expectedRevision:1},signal);assert.deepEqual(library.snapshot(),{revision:2,skills:[]})
})
test('read-only and cancelled skill writes do not create a provider definition', async t=>{
  const home=await mkdtemp(join(tmpdir(),'ds-bot-skills-'));t.after(()=>rm(home,{recursive:true,force:true}))
  let locked=true
  const library=await createSkillLibrary({home,service:{registerProvider(factory){factory({invalidate(){}});return()=>{}}},readOnly:()=>locked?'locked':undefined});t.after(()=>library.dispose())
  const body={name:'valid',description:'Read',content:'Instructions',modelInvocable:false,userInvocable:true,expectedRevision:0}
  await assert.rejects(library.save(body,new AbortController().signal),{status:409});locked=false
  const controller=new AbortController();controller.abort();await assert.rejects(library.save(body,controller.signal),{name:'AbortError'})
  assert.equal(library.snapshot().skills.length,0)
})
