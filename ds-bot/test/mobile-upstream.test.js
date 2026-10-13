import assert from 'node:assert/strict'
import { test } from 'node:test'
import { formatSessionReferenceMention, parseSessionReferenceText } from '@deepseek-ai/dsh-session-reference'
import { createAdapter } from '../src/mobile/adapter.js'
import { sessionMention } from '../../apps/mobile/src/logic/composer.ts'

function fixture() {
  const calls=[]
  const view={revision:1,bots:[{id:'a',name:'Alpha',sessionId:'a-chat',parts:[]},{id:'b',name:'Beta',sessionId:'b-chat',parts:[]}],rooms:[{id:'room',name:'Group',members:['a','b']}],models:[{ref:'p/m',name:'Model'}],permissions:{options:[{value:'workspace-write',name:'Workspace'}]},work:{bots:{a:{tool:'read_file',since:100},foreign:{tool:'private'}},approvals:[{id:'approval-1',botId:'a',roomId:'room',sessionId:'hidden-member',tool:'shell',reason:'ds-bot-test-key',detail:{code:'echo ds-bot-test-key'},at:200,answerable:true}]}}
  const items=[{sessionId:'a-chat',blank:false,updatedAt:20},{sessionId:'b-chat',blank:false,updatedAt:30},{sessionId:'outside',blank:false,updatedAt:40},{sessionId:'child',origin:'subagent',blank:false,updatedAt:50},{sessionId:'blank',blank:true,updatedAt:60},{sessionId:'hidden-member',blank:false,updatedAt:70}]
  const rt={state:{rooms:{room:{members:['a','b'],sessions:{a:'hidden-member'}}}},groupOwners:new Map([['hidden-member',{roomId:'room',botId:'a'}]]),readOnly:()=>undefined,redactSecrets:value=>String(value).replaceAll('ds-bot-test-key','[redacted]'),resolveAgent:async id=>({session:{id}}),answerApproval:(id,choice)=>{calls.push(['approval',id,choice]);view.work.approvals=[]},teamCall:async(endpoint,payload)=>{calls.push(['team',endpoint,payload]);if(endpoint==='state')return{ok:true,value:view};if(endpoint==='efforts')return{ok:true,value:{efforts:[{id:'low',name:'Low'}]}};return{ok:true,value:{id:payload?.id}}},ctx:{sessionReferenceResolver:{listCandidates:async()=>items.map(item=>({...item,label:item.sessionId,createdAt:10}))},sessionController:{list:async()=>({items}),prompt:async payload=>{calls.push(['prompt',payload]);return{accepted:true}}}}}
  const adapter=createAdapter(rt);adapter.setApprovalBroker({list:()=>({requests:[]}),dispose(){}},{authorizeDevice:()=>true});return{rt,adapter,view,calls,items}
}

test('mobile reference codec agrees with the public Harness codec for Unicode and escaped labels',()=>{
  for(const [sessionId,label] of [['plain','Chat with Beta'],['会话/🪄','Label ] \\ notes']]){
    const text=sessionMention(sessionId,label)
    assert.equal(text,formatSessionReferenceMention({sessionId,label}))
    assert.deepEqual(parseSessionReferenceText(text).references,[{sessionId,label}])
  }
})
test('reference discovery includes other Bots and recent ordinary chats, never hidden members, subagents or blank sessions',async()=>{
  const {adapter}=fixture();const result=await adapter.action('reference-chats',{conversationId:'a'})
  assert.equal(result.available,true);assert.deepEqual(result.chats.map(row=>row.sessionId),['b-chat','outside'])
})
test('references reach the public prompt unchanged, while forged or hidden references never submit',async()=>{
  const {adapter,calls}=fixture();const text=sessionMention('b-chat','Chat with Beta')+'\n\nRead this'
  await adapter.submit({conversationId:'a',sessionId:'a-chat',requestId:'valid',text})
  assert.equal(calls.find(([kind])=>kind==='prompt')[1].content[0].text,text)
  for(const id of ['hidden-member','child','foreign','a-chat']){
    await assert.rejects(adapter.submit({conversationId:'a',sessionId:'a-chat',requestId:'bad-'+id,text:sessionMention(id,id)}),error=>error.status===403)
  }
  assert.equal(calls.filter(([kind])=>kind==='prompt').length,1)
})
test('reference ownership is checked again after attachment admission yields',async()=>{
  const {adapter,rt,calls}=fixture();rt.ctx.fileUploads={uploadStream:async()=>{rt.groupOwners.set('outside',{roomId:'room',botId:'b'});return{receiptId:'file'}}}
  const file=await adapter.upload('a','a-chat',{name:'note.txt',mediaType:'text/plain'},Buffer.from('test'))
  await assert.rejects(adapter.submit({conversationId:'a',sessionId:'a-chat',requestId:'race',text:sessionMention('outside','Recent'),attachments:[file.receiptId]}),error=>error.status===403)
  assert.equal(calls.filter(([kind])=>kind==='prompt').length,0)
})
test('mobile exposes thinking levels and permission presets and forwards only supported update fields',async()=>{
  const {adapter,calls}=fixture();assert.equal((await adapter.state()).permissions.options[0].value,'workspace-write')
  assert.deepEqual(await adapter.action('efforts',{ref:'p/m'}),{efforts:[{id:'low',name:'Low'}]})
  await assert.rejects(adapter.action('efforts',{ref:'private/model'}),error=>error.status===400)
  await adapter.action('update-bot',{id:'a',effort:'low',permission:'workspace-write',untrusted:'drop'})
  assert.deepEqual(calls.find(([kind,endpoint])=>kind==='team'&&endpoint==='update-bot')[2],{id:'a',effort:'low',permission:'workspace-write'})
})
test('group approvals share the host promise, redact details and settle once without opening hidden history',async()=>{
  const {adapter,calls}=fixture();const requests=(await adapter.action('approvals')).requests;assert.equal(requests[0].conversationId,'room');assert.equal(requests[0].reason,'[redacted]\n\necho [redacted]')
  assert.deepEqual(await adapter.action('approval-resolve',{id:'group:approval-1',decision:'allowed-once'},undefined,{deviceId:'device'}),{accepted:true})
  await assert.rejects(adapter.action('approval-resolve',{id:'group:approval-1',decision:'rejected'},undefined,{deviceId:'device'}),error=>error.status===409)
  assert.deepEqual(calls.filter(([kind])=>kind==='approval'),[['approval','approval-1','allow']])
})
test('group approval cannot be answered by a revoked device or after its member leaves',async()=>{
  const first=fixture();let checks=0;first.adapter.setApprovalBroker({list:()=>({requests:[]})},{authorizeDevice:()=>++checks===1})
  await assert.rejects(first.adapter.action('approval-resolve',{id:'group:approval-1',decision:'allowed-once'},undefined,{deviceId:'device'}),error=>error.status===401)
  assert.equal(first.calls.filter(([kind])=>kind==='approval').length,0)
  const second=fixture();second.rt.state.rooms.room.members=['b']
  await assert.rejects(second.adapter.action('approval-resolve',{id:'group:approval-1',decision:'allowed-once'},undefined,{deviceId:'device'}),error=>error.status===409)
  assert.equal(second.calls.filter(([kind])=>kind==='approval').length,0)
})
