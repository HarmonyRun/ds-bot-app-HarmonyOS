// Own mock bench only. This exercises the real host and a controlled browser window;
// it does not claim a native Electron, APNs or FCM delivery test.
import assert from 'node:assert/strict'
import { randomUUID } from 'node:crypto'
import { readFile } from 'node:fs/promises'
import { createServer } from 'node:http'
import { dirname, join } from 'node:path'
import { fileURLToPath } from 'node:url'
import { execFileSync } from 'node:child_process'
import { MobileClient, MemoryTokenStore } from '../../packages/mobile-sdk/index.js'
import { playwright } from './desktop-linux/lib.mjs'
import { mobilePage } from '../src/client/mobile-browser-page.js'
const [name, webPort, mobilePort] = process.argv.slice(2)
if (!/^[a-z0-9-]+$/.test(name || '') || [webPort,mobilePort].some(value=>!/^\d+$/.test(value || '') || Number(value)<1024 || Number(value)===3080))throw new Error('Use an isolated named mock bench and test ports')
const root=dirname(dirname(dirname(fileURLToPath(import.meta.url))))
const log=await readFile(join(root,`.dsh-test-${name}`,'web.log'),'utf8')
const login=log.match(new RegExp(`http://127\\.0\\.0\\.1:${webPort}/\\?token=[^\\s]+`))?.[0]
if(!login)throw new Error('The isolated bench has no login URL')
const response=await fetch(login,{redirect:'manual'}),cookie=response.headers.getSetCookie().map(value=>value.split(';')[0]).join('; ')
const abort=new AbortController()
async function desktop(endpoint,payload={},signal){const result=await(await fetch(`http://127.0.0.1:${webPort}/api/bot`,{method:'POST',headers:{cookie,'content-type':'application/json'},body:JSON.stringify({endpoint,payload}),signal})).json();if(!result.ok)throw new Error(`Host refused ${endpoint}`);return result.value}
const operator=(endpoint,payload)=>desktop('mobile',{endpoint,payload})
const store=new MemoryTokenStore(),mobile=new MobileClient({baseUrl:`http://127.0.0.1:${mobilePort}`,tokenStore:store,allowInsecure:true})
const {chromium}=playwright(join(root,'deepseek-harness'))
const browser=await chromium.launch({executablePath:execFileSync('sh',['-c','command -v chromium || command -v google-chrome'],{encoding:'utf8'}).trim(),headless:true})
const page=await browser.newPage()
const fixture=createServer((request,response)=>{response.setHeader('content-type','text/html');response.end('<title>Controlled fixture</title><h1>Mobile browser fixture</h1><input placeholder="Note"><button onclick="window.clicks=(window.clicks||0)+1;document.querySelector(\'h1\').textContent=\'Clicked once\'">Run</button>')})
await new Promise(resolve=>fixture.listen(0,'127.0.0.1',resolve))
const fixtureUrl=`http://127.0.0.1:${fixture.address().port}/`
let bot,deviceId,skillName,checks=0,control=false,loop
const check=(condition,message)=>{assert.ok(condition,message);console.log(`ok ${++checks} ${message}`)}
async function until(fn){for(let i=0;i<300;i++){const value=await fn();if(value)return value;await new Promise(resolve=>setTimeout(resolve,100))}throw new Error('A feature did not settle')}
try{
 const pairing=await operator('pairing.create'),claim=await mobile.pair(pairing.code,'Feature validation')
 await operator('pairing.approve',{requestId:claim.requestId});await mobile.completePairing(claim.claimToken);deviceId=(await store.get()).deviceId
 const state=await mobile.state(),model=state.models[0]
 bot=await mobile.action('create-bot',{name:'Feature validation Bot',model:model.ref})
 const botId=bot.id || bot.botId || bot.bot?.id;assert.ok(botId);bot={id:botId}
 await until(async()=>{const state=await mobile.state();const question=Object.values(state.questions || {}).find(item=>item.conversationId===botId);if(question)await mobile.action('dismiss-question',{sessionId:question.sessionId});return !state.bots.find(item=>item.id===botId)?.waiting})
 skillName='mobile-proof-'+Date.now().toString(36)
 let library=await mobile.action('skills-library',{})
 library=await mobile.action('skills-save',{name:skillName,description:'Check evidence',content:'# Evidence\nUse only confirmed facts.',modelInvocable:false,userInvocable:true,expectedRevision:library.revision})
 const directory=await mobile.action('skills-list',{conversationId:botId});check(directory.skills.some(item=>item.name===skillName && item.invocation.userInvocable),'a mobile-managed skill appears in the real Bot scope')
 const skill=await mobile.action('skills-get',{conversationId:botId,name:skillName});check(skill.content.includes('Use only confirmed facts.'),'the public skill registry loads the managed instructions')
 await mobile.submit({...await mobile.target(botId),requestId:randomUUID(),text:`/${skillName} Review this fixture.`})
 await until(async()=>(await mobile.messages(botId)).messages.some(message=>message.text==='Mock received mobile skill instructions.'))
 check(true,'a genuine slash invocation injects instructions into the real Harness model request')
 const clientId=randomUUID(),answered=new Map()
 loop=(async()=>{while(!abort.signal.aborted){try{const open={ [botId]:{url:page.url(),title:'Controlled fixture',mobileControl:control,active:'fixture-tab',tabs:[{id:'fixture-tab',url:page.url(),title:'Controlled fixture'}]} };const requests=await desktop('browser-wait',{clientId,open},abort.signal)
 for(const request of requests){let job=answered.get(request.id);if(!job){job=(async()=>{try{if(!control)throw new Error('Mobile control disabled');const command=request.mobileCommand;if(command.command==='navigate'){await page.goto(command.url);return {changed:true,tabId:'fixture-tab'}}const value=await page.evaluate(mobilePage,command);return {...value,tabId:'fixture-tab'}}catch{return {error:'Fixture refused this command'}}})();answered.set(request.id,job)}const result=await job;await desktop('browser-result',{id:request.id,clientId,ok:!result.error,...(result.error?{error:result.error}:{page:result})},abort.signal)}
 }catch{if(!abort.signal.aborted)await new Promise(resolve=>setTimeout(resolve,100))}}})()
 await page.goto(fixtureUrl);control=true
 await until(async()=>(await mobile.action('browser-pages',{})).pages.some(item=>item.botId===botId && item.mobileControl))
 const snapshot=await mobile.action('browser-control',{botId,command:'snapshot',requestId:randomUUID()});check(snapshot.page.controls.some(item=>item.name==='Run'),'the host routes a mobile page snapshot to the connected window')
 const field=snapshot.page.controls.find(item=>item.editable)
 await mobile.action('browser-control',{botId,command:'fill',tabId:snapshot.page.tabId,snapshotId:snapshot.page.snapshotId,item:field.item,text:'Phone text',requestId:randomUUID()});check(await page.locator('input').inputValue()==='Phone text','fixed text input changes the actual controlled page')
 const fresh=await mobile.action('browser-control',{botId,command:'snapshot',requestId:randomUUID()});const button=fresh.page.controls.find(item=>item.name==='Run')
 const click={botId,command:'click',tabId:fresh.page.tabId,snapshotId:fresh.page.snapshotId,item:button.item,requestId:randomUUID()}
 await Promise.all([mobile.action('browser-control',click),mobile.action('browser-control',click)]);check(await page.evaluate(()=>window.clicks)===1,'duplicate mobile clicks share one original browser receipt')
 const phoneContext=await browser.newContext({viewport:{width:390,height:844},isMobile:true})
 const phone=await phoneContext.newPage(),code=await operator('pairing.create')
 await phone.goto('http://127.0.0.1:8082')
 await phone.getByRole('textbox',{name:/^(Pairing JSON|配对数据 JSON)$/}).fill(JSON.stringify({url:code.url,code:code.code,serverId:code.serverId}))
 const deviceName='Browser feature UI '+Date.now()
 await phone.getByRole('textbox',{name:/^(Device name|设备名称)$/}).fill(deviceName)
 await phone.getByRole('switch').check()
 await phone.getByRole('button',{name:/^(Connect to my host|连接我的主机)$/}).click()
 const pending=await until(async()=>(await operator('status')).pending.find(item=>item.deviceName===deviceName || item.name===deviceName))
 await operator('pairing.approve',{requestId:pending.requestId})
 await phone.getByRole('button',{name:/^(Open navigation|打开导航)$/}).click()
 await phone.getByRole('button',{name:/^(Open Feature validation Bot|打开 Feature validation Bot)$/}).click()
 await phone.getByRole('button',{name:'桌面浏览器',exact:true}).click()
 await phone.getByRole('button',{name:'读取当前页面',exact:true}).click()
 await phone.getByText('Controlled fixture',{exact:true}).last().waitFor()
 check(true,'the actual mobile browser panel reads its controlled Desktop page')
 await phone.getByRole('button',{name:'输入文字',exact:true}).click()
 await phone.getByRole('textbox',{name:'文字',exact:true}).fill('Mobile UI text')
 await phone.getByRole('button',{name:'填入电脑页面',exact:true}).click()
 await until(async()=>await page.locator('input').inputValue()==='Mobile UI text')
 check(true,'the mobile text entry sheet updates the controlled page through the real host')
 await phone.getByRole('button',{name:'读取当前页面',exact:true}).click()
 await phone.getByRole('button',{name:'点击',exact:true}).click()
 await phone.getByRole('button',{name:'确认点击',exact:true}).click()
 await until(async()=>await page.evaluate(()=>window.clicks)===2)
 check(true,'the mobile click sheet confirms one explicit action')
 await phone.getByRole('button',{name:'读取当前页面',exact:true}).click()
 await phone.screenshot({path:'/workspace/scratch/mobile-next/six-ui/15-desktop-browser.png'})
 const phoneDevice=(await operator('status')).devices.find(item=>item.name===deviceName || item.deviceName===deviceName)
 if(phoneDevice)await operator('device.revoke',{id:phoneDevice.id})
 await phoneContext.close()
 control=false
 // The long poll reports the desktop switch on its next heartbeat.
 await until(async()=>(await mobile.action('browser-pages',{})).pages.some(item=>item.botId===botId && !item.mobileControl))
 await assert.rejects(mobile.action('browser-control',{botId,command:'snapshot',requestId:randomUUID()}),error=>error.status===409);check(true,'Desktop revocation refuses further mobile commands')
 const inbox=await until(async()=>{const value=await mobile.action('notifications-list',{});return value.items.some(item=>item.conversationId===botId)?value:null});check(inbox.items.every(item=>!Object.hasOwn(item,'text')),'real host events reach the durable inbox without conversation bodies')
 await mobile.action('notifications-read',{through:inbox.cursor});check((await mobile.action('notifications-list',{})).items.every(item=>item.read),'notification reads are stored for the paired device')
 check((await mobile.action('plugins-list',{})).bundles.every(item=>item.name!=='ds-bot' || !item.removable),'the bridge protects its own package in the real plugin inventory')
 console.log(`mobile features: all ${checks} checks passed`)
}finally{
 abort.abort();await loop?.catch(()=>{});await browser.close();await new Promise(resolve=>fixture.close(resolve))
 if(skillName){try{const library=await mobile.action('skills-library',{});await mobile.action('skills-delete',{name:skillName,expectedRevision:library.revision})}catch{}}
 if(bot?.id)await mobile.action('delete-bot',{id:bot.id}).catch(()=>{})
 if(deviceId)await operator('device.revoke',{id:deviceId}).catch(()=>{})
}
