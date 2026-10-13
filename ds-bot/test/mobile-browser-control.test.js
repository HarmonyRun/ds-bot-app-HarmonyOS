import test from 'node:test'
import assert from 'node:assert/strict'
import { createRequire } from 'node:module'
import { resolve } from 'node:path'
import { createBrowserChannel } from '../src/host/browser.js'
import { mobilePageScript } from '../src/client/mobile-browser-page.js'
const {JSDOM}=createRequire(resolve(process.env.DSH_HARNESS || '../deepseek-harness','package.json'))('jsdom')
test('desktop results must belong to the commanded window, and cancellation removes queued mutations',async()=>{
  const channel=createBrowserChannel({waitMs:1,readTimeoutMs:1000})
  await channel.wait('owner',{bot:{mobileControl:true}})
  const controller=new AbortController()
  const result=channel.read('bot',{signal:controller.signal,mobileCommand:{command:'click',item:0}})
  const [request]=await channel.wait('owner',{bot:{mobileControl:true}})
  assert.equal(channel.result({id:request.id,clientId:'other',ok:true,page:{changed:true}}),false)
  controller.abort();assert.match((await result).error,/cancelled/)
  assert.deepEqual(await channel.wait('owner',{bot:{mobileControl:true}}),[])
  assert.equal(channel.result({id:request.id,clientId:'owner',ok:true,page:{changed:true}}),false)
  channel.dispose()
})
test('page snapshots exclude sensitive fields and stale references cannot click or fill',()=>{
  const dom=new JSDOM('<button id="run">Run</button><input id="note"><input type="password" id="secret"><input autocomplete="cc-number"><input autocomplete="one-time-code">',{url:'https://example.test/',runScripts:'outside-only'})
  const {window}=dom
  window.HTMLElement.prototype.getClientRects=function(){return [{width:100,height:20}]}
  let clicks=0;window.document.getElementById('run').addEventListener('click',()=>clicks++)
  const first=window.eval(mobilePageScript({command:'snapshot',snapshotId:'one'}))
  assert.equal(first.controls.length,2)
  window.eval(mobilePageScript({command:'fill',snapshotId:'one',item:1,text:'literal <script>example</script>'}))
  assert.equal(window.document.getElementById('note').value,'literal <script>example</script>')
  assert.throws(()=>window.eval(mobilePageScript({command:'click',snapshotId:'one',item:0})),/Page changed/)
  window.eval(mobilePageScript({command:'snapshot',snapshotId:'two'}))
  window.eval(mobilePageScript({command:'click',snapshotId:'two',item:0}));assert.equal(clicks,1)
  assert.throws(()=>window.eval(mobilePageScript({command:'click',snapshotId:'two',item:0})),/Page changed/)
  window.eval(mobilePageScript({command:'snapshot',snapshotId:'three'}));window.document.getElementById('run').remove()
  assert.throws(()=>window.eval(mobilePageScript({command:'click',snapshotId:'three',item:0})),/no longer available/)
  dom.window.close()
})
