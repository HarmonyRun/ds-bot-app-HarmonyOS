import test from 'node:test'
import assert from 'node:assert/strict'
import { mkdtemp, rm, readFile } from 'node:fs/promises'
import { tmpdir } from 'node:os'
import { join } from 'node:path'
import { createNotificationHub } from '../src/mobile/notifications.js'
async function eventually(predicate) { for (let i=0;i<200;i++) { if(await predicate())return; await new Promise(resolve=>setTimeout(resolve,5)) } throw new Error('Notification did not settle') }
const tick=()=>new Promise(resolve=>setImmediate(resolve))
function fixture(){
  let wake, active=true
  const frames=[]
  const valid=new Set(['one','two']), pushes=[]
  const adapter={conversations:async()=>({conversations:[{id:'owned'}]}),state:async()=>({questions:{}}),action:async()=>({requests:[]}),async *follow(_id,_options,signal){
    yield {type:'reset',messages:[]}
    while(!signal.aborted){
      if(!frames.length){
        let release
        await new Promise(resolve=>{release=resolve;wake=resolve;signal.addEventListener('abort',resolve,{once:true});if(signal.aborted)resolve()})
        signal.removeEventListener('abort',release)
        if(wake===release)wake=undefined
      }
      if(signal.aborted)break
      if(frames.length)yield frames.shift()
    }
  }}
  return {adapter,valid,pushes,authorized:id=>valid.has(id),active:()=>active,sendPush:async(tokens,item)=>pushes.push({tokens,item}),emit(value){frames.push(value);wake?.()},disable(){active=false}}
}
test('notification events persist without transcripts, device reads are isolated and revoked devices cannot register',async t=>{
  const home=await mkdtemp(join(tmpdir(),'ds-bot-notifications-'));t.after(()=>rm(home,{recursive:true,force:true}))
  const f=fixture();let hub=await createNotificationHub({home,...f,pollMs:60000});t.after(()=>hub.close())
  await hub.poll();await tick()
  f.emit({type:'message',message:{id:'session:1',role:'assistant',text:'Private transcript must never be stored'}});await tick();await tick()
  let inbox=await hub.action('notifications-list',{},'one');assert.equal(inbox.items.length,1);assert.equal(inbox.items[0].read,false)
  await hub.action('notifications-read',{ids:[inbox.items[0].id]},'one');assert.equal((await hub.action('notifications-list',{},'one')).items[0].read,true);assert.equal((await hub.action('notifications-list',{},'two')).items[0].read,false)
  assert.equal((await readFile(join(home,'notifications.json'),'utf8')).includes('Private transcript'),false)
  f.valid.delete('two');await assert.rejects(hub.action('notifications-register',{token:'ExpoPushToken[fixture-only]'},'two'),{status:401})
  await hub.close();hub=await createNotificationHub({home,...f,pollMs:60000});inbox=await hub.action('notifications-list',{},'one');assert.equal(inbox.items.length,1);assert.equal(inbox.items[0].read,true);assert.equal(inbox.pushRegistered,false)
})
test('push delivery requires explicit registration and category preference, and duplicate public frames coalesce',async t=>{
  const home=await mkdtemp(join(tmpdir(),'ds-bot-notifications-'));t.after(()=>rm(home,{recursive:true,force:true}))
  const f=fixture(),hub=await createNotificationHub({home,...f,pollMs:60000});t.after(()=>hub.close());await hub.poll();await tick()
  await hub.action('notifications-register',{token:'ExpoPushToken[synthetic-routing]'},'one')
  await hub.action('notifications-preferences',{enabled:true,categories:['reply']},'one')
  const frame={type:'message',message:{id:'session:2',role:'assistant',text:'Sensitive conversation content'}}
  f.emit(frame);await tick();await tick();await tick();f.emit(frame);await tick();await tick()
  await eventually(()=>f.pushes.length===1);assert.equal(f.pushes.length,1);assert.equal(JSON.stringify(f.pushes).includes('Sensitive conversation'),false)
  await hub.action('notifications-preferences',{enabled:false,categories:['reply']},'one');assert.equal((await hub.action('notifications-list',{},'one')).pushRegistered,false)
})
test('notification questions and approvals use the public owned conversation mapping',async t=>{
  const home=await mkdtemp(join(tmpdir(),'ds-bot-notifications-'));t.after(()=>rm(home,{recursive:true,force:true}))
  const f=fixture();f.adapter.state=async()=>({questions:{session:{id:'q1',conversationId:'owned'},other:{id:'q2',conversationId:'external'}}});f.adapter.action=async()=>({requests:[{id:'approval1',conversationId:'owned'}]})
  const hub=await createNotificationHub({home,...f,pollMs:60000});t.after(()=>hub.close());await hub.poll();await hub.poll()
  assert.deepEqual((await hub.action('notifications-list',{},'one')).items.map(item=>item.kind),['approval','question'])
})
test('background receiver gets only enabled, unread metadata and registration does not persist credentials',async t=>{
  const home=await mkdtemp(join(tmpdir(),'ds-bot-notifications-'));t.after(()=>rm(home,{recursive:true,force:true}))
  const f=fixture(),hub=await createNotificationHub({home,...f,pollMs:60000});t.after(()=>hub.close());await hub.poll();await tick()
  const lease=await hub.action('notifications-background-register',{},'one')
  await hub.action('notifications-preferences',{enabled:true,categories:['reply']},'one')
  f.adapter.state=async()=>({questions:{owned:{id:'question-bg',conversationId:'owned'}}})
  f.emit({type:'message',message:{id:'session:bg',role:'assistant',text:'Private background transcript'}})
  await eventually(async()=>(await hub.action('notifications-list',{},'one')).items.some(item=>item.kind==='reply'))
  f.emit({type:'message',message:{id:'session:bg-next',role:'assistant',text:'Another private background transcript'}})
  await eventually(async()=>(await hub.action('notifications-list',{},'one')).items.filter(item=>item.kind==='reply').length===2)
  const result=await hub.backgroundPoll(lease.token,lease.cursor)
  assert.deepEqual(result.items.map(item=>item.kind),['reply','reply'])
  assert.ok(result.items[1].id > result.items[0].id)
  assert.equal(result.deliveryEnabled,true)
  assert.equal(JSON.stringify(result).includes('Private background'),false)
  const disk=await readFile(join(home,'notifications.json'),'utf8')
  assert.equal(disk.includes(lease.token),false)
  await hub.action('notifications-read',{ids:result.items.map(item=>item.id)},'one')
  assert.deepEqual((await hub.backgroundPoll(lease.token,lease.cursor)).items,[])
  await hub.action('notifications-register',{token:'ExpoPushToken[synthetic-routing]'},'one')
  assert.equal((await hub.backgroundPoll(lease.token,lease.cursor)).deliveryEnabled,false)
})
test('background leases rotate independently from app sessions and stop after disable, revoke or host restart',async t=>{
  const home=await mkdtemp(join(tmpdir(),'ds-bot-notifications-'));t.after(()=>rm(home,{recursive:true,force:true}))
  const f=fixture();let hub=await createNotificationHub({home,...f,pollMs:60000});t.after(()=>hub.close())
  const first=await hub.action('notifications-background-register',{},'one')
  const next=await hub.action('notifications-background-register',{},'one')
  assert.throws(()=>hub.backgroundDevice(first.token),{status:401})
  assert.equal(hub.backgroundDevice(next.token),'one')
  await assert.rejects(hub.backgroundPoll(next.token,-1),{status:400})
  await hub.action('notifications-preferences',{enabled:false,categories:[]},'one')
  assert.throws(()=>hub.backgroundDevice(next.token),{status:401})
  await assert.rejects(hub.action('notifications-background-register',{},'one'),{status:409})
  const other=await hub.action('notifications-background-register',{},'two')
  hub.revoke('two');assert.throws(()=>hub.backgroundDevice(other.token),{status:401})
  await hub.action('notifications-preferences',{enabled:true,categories:['reply']},'one')
  const restart=await hub.action('notifications-background-register',{},'one')
  await hub.close();hub=await createNotificationHub({home,...f,pollMs:60000})
  assert.throws(()=>hub.backgroundDevice(restart.token),{status:401})
})
test('revocation or lease rotation during a background read cannot release late metadata',async t=>{
  const home=await mkdtemp(join(tmpdir(),'ds-bot-notifications-'));t.after(()=>rm(home,{recursive:true,force:true}))
  const f=fixture(),hub=await createNotificationHub({home,...f,pollMs:60000});t.after(()=>hub.close())
  const lease=await hub.action('notifications-background-register',{},'one')
  f.adapter.conversations=async()=>{f.valid.delete('one');return {conversations:[{id:'owned'}]}}
  await assert.rejects(hub.backgroundPoll(lease.token,0),{status:401})
})
