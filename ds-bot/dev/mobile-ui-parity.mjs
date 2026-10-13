// Real browser checks against an isolated DSH mock-model bench and Expo web preview.
// Usage: node dev/mobile-ui-parity.mjs <bench-name> <dsh-web-port> <app-url> <screenshot-dir>
// Start the bench with MOBILE_PORT=8789 and MOBILE_WEB_ORIGIN matching <app-url>.
import assert from 'node:assert/strict'
import { execFileSync } from 'node:child_process'
import { mkdirSync, readFileSync } from 'node:fs'
import { dirname, join, resolve } from 'node:path'
import { fileURLToPath } from 'node:url'
import { playwright } from './desktop-linux/lib.mjs'

const [bench, port, appUrl, output = '/tmp/ds-bot-mobile-parity'] = process.argv.slice(2)
if (!bench || !/^\d+$/.test(port ?? '') || !appUrl) throw new Error('Usage: node dev/mobile-ui.mjs <bench-name> <dsh-web-port> <app-url> <screenshot-dir>')
if (!/^[a-z0-9-]+$/.test(bench)) throw new Error('Use an isolated test-bench name.')
const root = dirname(dirname(dirname(fileURLToPath(import.meta.url))))
const log = readFileSync(join(root, `.dsh-test-${bench}`, 'web.log'), 'utf8')
const login = log.match(new RegExp(`http://127\\.0\\.0\\.1:${port}/\\?token=[^\\s]+`))?.[0]
if (!login) throw new Error('The isolated bench has no login URL.')
const { chromium } = playwright(process.env.DSH_HARNESS || join(root, 'deepseek-harness'))
const executablePath = process.env.CHROME_BIN || execFileSync('sh', ['-c', 'command -v chromium || command -v google-chrome'], { encoding: 'utf8' }).trim()
const browser = await chromium.launch({ executablePath, headless: true })
const desktopContext = await browser.newContext()
const context = await browser.newContext({ viewport: { width: 390, height: 844 }, isMobile: true, deviceScaleFactor: 1, locale: 'en-US' })
const desktop = await desktopContext.newPage()
const page = await context.newPage()
page.setDefaultTimeout(30000)
const failures = []
const sensitive = []
const scrub = value => sensitive.reduce((text, secret) => text.replaceAll(secret, '[redacted]'), String(value))
page.on('pageerror', error => failures.push(error.message))
mkdirSync(output, { recursive: true })
let checks = 0
const check = (condition, name) => { assert.ok(condition, name); checks++; console.log(`ok ${checks} ${name}`) }
const api = async (endpoint, payload = {}) => {
  const result = await desktop.evaluate(async ([endpoint, payload]) => {
    const response = await fetch('/api/bot', { method: 'POST', headers: { 'Content-Type': 'application/json' }, body: JSON.stringify({ endpoint, payload }) })
    return response.json()
  }, [endpoint, payload])
  if (!result.ok) throw new Error(`The desktop test operation ${endpoint} failed.`)
  return result.value
}
const operator = (endpoint, payload) => api('mobile', { endpoint, payload })
const until = async (predicate, timeout = 30000) => {
  const end = Date.now() + timeout
  while (Date.now() < end) { const value = await predicate(); if (value) return value; await new Promise(resolve => setTimeout(resolve, 250)) }
  throw new Error('A test condition timed out.')
}
const label = text => page.getByRole('textbox', { name: text, exact: true })
const button = text => page.getByRole('button', { name: text, exact: true })
const drawer = async () => {
  for (let depth = 0; depth < 6 && !await button('Open navigation').count(); depth++) await button('Back').click()
  await button('Open navigation').click()
}
const settingsPage = async name => {
  await drawer()
  await button('Settings').click()
  await button('Close navigation').first().waitFor({ state: 'hidden' })
  if (name) await button(name).click()
}
const openChat = async name => {
  await drawer()
  await button(`Open ${name}`).click()
  await button('Close navigation').first().waitFor({ state: 'hidden' })
  await label('Message').waitFor()
}
const english = async () => {
  await page.getByRole('button', { name: /^(Open navigation|打开导航)$/ }).click()
  await page.getByRole('button', { name: /^(Settings|设置)$/ }).click()
  await page.getByRole('button', { name: /^(General|通用)$/ }).click()
  await button('English').click()
}
const cachedUserCount = text => page.evaluate(text => Object.keys(localStorage)
  .filter(key => key.startsWith('ds-bot:cache:') && key.includes('messages:'))
  .flatMap(key => { try { const value = JSON.parse(localStorage.getItem(key)); return Array.isArray(value) ? value : [] } catch { return [] } })
  .filter(message => message.role === 'user' && message.text === text).length, text)
let createdBot
let createdRoom
let createdTask
let pairedDevice
let originalPrefs
try {
  await desktop.goto(login).catch(() => { throw new Error('Could not open the isolated desktop test session.') })
  const notice = desktop.getByRole('dialog').getByRole('button', { name: 'Continue', exact: true })
  await desktop.addLocatorHandler(notice, () => notice.click())
  await desktop.locator('.bt-tile, .bt-row').first().waitFor({ timeout: 60000 })
  const run = Date.now().toString(36)
  const deviceName = `UI check ${run}`
  await desktop.locator('.bt-account').click()
  await desktop.getByRole('menuitem', { name: /Bot settings|Bot 设置|机器人设置/ }).click()
  const settings = desktop.locator('.bt-settings')
  await settings.getByRole('button', { name: 'Mobile devices', exact: true }).click()
  await settings.getByRole('button', { name: 'Create pairing code', exact: true }).click()
  const manualPairing = settings.getByRole('textbox', { name: 'Manual pairing data' })
  await manualPairing.waitFor()
  const pairing = JSON.parse(await manualPairing.inputValue())
  sensitive.push(pairing.code)
  const image = settings.getByRole('img', { name: 'Scan this code in DS Bot Mobile to request access.' })
  check((await image.getAttribute('src'))?.startsWith('data:image/png;base64,'), 'desktop Mobile devices settings generates an actual pairing QR image')
  let streamDeltas = 0
  page.on('websocket', socket => socket.on('framereceived', ({ payload }) => {
    try { if (JSON.parse(String(payload)).type === 'delta') streamDeltas++ } catch {}
  }))
  await page.goto(appUrl)
  await label('Pairing JSON').fill(JSON.stringify({ url: pairing.url, code: pairing.code, serverId: pairing.serverId }))
  await label('Device name').fill(deviceName)
  if (pairing.url.startsWith('http:')) await page.getByRole('switch', { name: 'Allow development loopback HTTP' }).check()
  await button('Connect to my host').click()
  await page.getByText('Waiting for approval on your computer…', { exact: true }).waitFor()
  check(await button('Open navigation').count() === 0, 'pairing stays locked until the desktop owner approves')
  const pendingRow = settings.locator('.bt-set-row').filter({ hasText: deviceName })
  await pendingRow.getByRole('button', { name: 'Approve', exact: true }).click()
  await page.getByRole('button', { name: /^(Open navigation|打开导航)$/ }).waitFor()
  await english()
  pairedDevice = (await operator('status', {})).devices.find(item => item.name === deviceName || item.deviceName === deviceName)?.id
  check(Boolean(pairedDevice), 'approved browser device appears in the real host device list')

  const state = await api('state')
  const chief = state.bots.find(bot => bot.id === state.mainBotId)
  originalPrefs = state.prefs || {}
  await openChat(chief.name)
  if (!chief?.model) {
    if (await page.getByRole('button', { name: /Choose a model to begin/ }).count()) await page.getByRole('button', { name: /Choose a model to begin/ }).click()
    await page.getByRole('button', { name: state.models[0].name, exact: true }).first().click()
  }
  // A reused mock bench may retain an unanswered question from a previous run.
  // Finish it through the public UI action before checking a new reply.
  for (let attempt = 0; attempt < 8; attempt++) {
    const current = await api('state')
    for (const [sessionId] of Object.entries(current.questions || {})) await api('dismiss-question', { sessionId })
    if (!current.bots.find(bot => bot.id === chief.id)?.waiting && attempt > 1) break
    await page.waitForTimeout(500)
  }
  const greeting = `mobile ui greeting ${run}`
  await label('Message').fill(greeting)
  await button('Send').click()
  await page.getByText(`收到：${greeting}`, { exact: false }).first().waitFor({ timeout: 45000 })
  check(await page.getByText(greeting, { exact: true }).count() === 1, 'chat submits a real message and renders one user bubble')
  check(streamDeltas > 0, 'the real DSH reply arrives through streaming websocket deltas')
  await page.screenshot({ path: join(output, '01-chat.png') })

  await context.setOffline(true)
  await page.getByText(/Host offline\. Cached messages/).waitFor({ timeout: 20000 })
  await label('Message').fill(`offline draft ${run}`)
  await settingsPage()
  await openChat(chief.name)
  await label('Message').waitFor()
  await until(async () => await label('Message').inputValue() === `offline draft ${run}`)
  await until(async () => await cachedUserCount(greeting) === 1)
  check(true, 'cached history and draft survive changing screens while offline')
  check(await button('Send').isDisabled(), 'offline mode prevents new sends')
  await context.setOffline(false)
  await until(async () => !await button('Send').isDisabled(), 25000)

  const uncertain = `mobile ui receipt ${run}`
  let postCount = 0
  let loseReceipt = true
  await page.route('**/mobile/v1/submissions', async route => {
    if (route.request().method() !== 'POST') return route.continue()
    postCount++
    if (!loseReceipt) return route.continue()
    loseReceipt = false
    await route.fetch()
    await route.abort('connectionfailed')
  })
  await label('Message').fill(uncertain)
  await button('Send').click()
  await button('Retry').waitFor()
  await until(async () => !await button('Retry').isDisabled())
  await button('Retry').click()
  await button('Send').waitFor()
  await page.getByText(`收到：${uncertain}`, { exact: false }).first().waitFor({ timeout: 45000 })
  await until(async () => await cachedUserCount(uncertain) === 1)
  check(postCount === 1, 'a lost submission response is recovered by its receipt without duplicate sending')
  await page.unroute('**/mobile/v1/submissions')

  await drawer()
  await button('New chat').click()
  await button('New Bot').click()
  const botName = `Mobile reviewer ${run}`
  await label('Name').fill(botName)
  await label('Label').fill('Mobile test reviewer')
  await label('Instructions').fill('Review the current task briefly.')
  await button('Create').click()
  await button('Open chat').waitFor()
  createdBot = (await api('state')).bots.find(bot => bot.name === botName)
  check(Boolean(createdBot), 'the mobile team form creates a Bot on the real host')
  await label('Label').fill('Reviewed from mobile')
  await label('Label').blur()
  await until(async () => (await api('state')).bots.find(bot => bot.id === createdBot.id)?.role === 'Reviewed from mobile')
  check((await api('state')).bots.find(bot => bot.id === createdBot.id)?.role === 'Reviewed from mobile', 'editing a Bot updates host team state')
  await page.screenshot({ path: join(output, '02-team.png') })

  await button('Memory').click()
  const memoryText = `Remember this parity fixture ${run}`
  await label('Ask or update').fill(`remember ${memoryText}`)
  await button('Send').click()
  await until(async () => (await api('memory-view', { botId: createdBot.id })).entries.some(entry => entry.text === memoryText))
  await page.getByRole('button', { name: /^Memory view: All entries/ }).click()
  await page.getByText(memoryText, { exact: true }).last().waitFor()
  check(true, 'the mobile memory conversation writes and lists a real saved entry')
  await page.screenshot({ path: join(output, '09-memory.png') })
  await button('Remove').last().click()
  await button('Confirm removal').click()
  await until(async () => !(await api('memory-view', { botId: createdBot.id })).entries.some(entry => entry.text === memoryText))
  check(true, 'memory removal requires confirmation and removes the real host entry')

  await settingsPage('General')
  await button('Paper').click()
  await until(async () => (await api('state')).prefs.theme === 'paper')
  await until(async () => await desktop.evaluate(() => getComputedStyle(document.body).getPropertyValue('--bt-main').trim()) === '#faf9f5')
  await page.screenshot({ path: join(output, '04-theme-paper.png') })
  check(true, 'changing the mobile theme updates the shared host preference and desktop theme tokens')
  await button('简体中文').click()
  await button('跟随主机').waitFor()
  check(true, 'the mobile language setting switches settings controls to Chinese')
  await button('English').click()

  await drawer()
  await button('New chat').click()
  await button('New group chat').click()
  const roomName = `Parity group ${run}`
  await label('Name').fill(roomName)
  const rowWith = (name, action) => page.locator('div').filter({ has: page.getByText(name, { exact: true }) }).filter({ has: button(action) }).last()
  await rowWith(chief.name, 'Make admin').getByRole('button', { name: 'Make admin', exact: true }).click()
  check(await button('Create group').isDisabled(), 'group creation requires an admin and at least two Bots')
  await rowWith(botName, 'Add').getByRole('button', { name: 'Add', exact: true }).click()
  await button('Create group').click()
  await until(async () => { createdRoom = (await api('state')).rooms.find(room => room.name === roomName); return createdRoom })
  check(createdRoom.members.length === 2 && createdRoom.admin === chief.id, 'mobile group creation preserves the selected admin and two-member rule')
  await page.screenshot({ path: join(output, '05-group.png') })

  await settingsPage('Scheduled tasks')
  await button('＋ New task').click()
  const taskName = `Parity task ${run}`
  await label('Name').fill(taskName)
  await label('What to do').fill('Report the scheduled test result.')
  await button('When: Every day').click()
  await label('Time (HH:MM)').fill('23:59')
  await button('Create task').click()
  await until(async () => { createdTask = (await api('schedules')).tasks.find(task => task.title === taskName); return createdTask })
  check(Boolean(createdTask), 'the mobile schedule form creates a real host task')
  await page.screenshot({ path: join(output, '06-schedules.png') })
  await rowWith(taskName, 'Delete').getByRole('button', { name: 'Delete', exact: true }).click()
  check((await api('schedules')).tasks.some(task => task.id === createdTask.id), 'the first delete tap requests confirmation without deleting a schedule')
  await button('Delete task').click()
  await until(async () => !(await api('schedules')).tasks.some(task => task.id === createdTask.id))
  createdTask = undefined

  await settingsPage('Usage')
  await page.getByText('Time range', { exact: true }).waitFor()
  await page.screenshot({ path: join(output, '07-usage.png') })
  check(await page.getByText('No usage yet.', { exact: true }).count() === 0, 'mobile usage renders real mock-model usage after the conversation')

  await openChat(chief.name)
  await label('Message').fill('多选')
  await button('Send').click()
  await page.getByRole('checkbox', { name: '收集资料', exact: true }).waitFor()
  await page.getByRole('checkbox', { name: '收集资料', exact: true }).click()
  await page.getByRole('checkbox', { name: '每周复盘', exact: true }).click()
  await button('Submit').click()
  await until(async () => !(await api('state')).questions?.[chief.id])
  check(true, 'a real model question preserves descriptions and submits multiple selected answers')
  await label('Message').fill('team')
  await button('Send').click()
  await button('list_bots details').last().waitFor()
  await button('list_bots details').last().click()
  await page.getByText('已完成', { exact: true }).last().waitFor()
  await button('原始详情').last().waitFor()
  check(true, 'real tool calls show a completed expandable card with their result')
  await page.screenshot({ path: join(output, '08-tool.png') })
  await button('Close').last().click()

  if (await desktop.locator('.bt-settings-close').count()) await desktop.locator('.bt-settings-close').click()
  await desktop.locator('.bt-tile, .bt-row').filter({ hasText: chief.name }).first().click()
  await label('Message').fill('ds-bot-test-approval')
  await button('Send').click()
  await button('Allow once').waitFor()
  const desktopApproval = desktop.getByRole('region', { name: 'ds_bot_test_approval approval', exact: true })
  await desktopApproval.waitFor()
  const pendingApproval = (await operator('approvals.list')).requests.find(request => request.conversationId === chief.id)
  check(Boolean(pendingApproval), 'the same real tool approval appears on desktop and mobile')
  await button('Allow once').scrollIntoViewIfNeeded()
  await page.screenshot({ path: join(output, '12-approval.png') })
  await button('Allow once').click()
  await page.getByText('Mock approval outcome: allowed-once', { exact: true }).last().waitFor()
  await desktopApproval.waitFor({ state: 'hidden' })
  check((await operator('approvals.list')).requests.length === 0, 'a phone approval settles the host tool once and removes the desktop prompt')
  await label('Message').fill('ds-bot-test-approval')
  await button('Send').click()
  await button('Reject').waitFor()
  await desktopApproval.getByRole('button', { name: 'Reject', exact: true }).click()
  await button('Reject').waitFor({ state: 'hidden' })
  await page.getByText('Mock approval outcome: rejected', { exact: true }).last().waitFor()
  check(true, 'a desktop rejection settles the same request and removes the phone prompt')

  await label('Message').fill('A **parity bold** fragment.\n\n```js\nconst checked = true;\n```')
  await button('Send').click()
  await button('Copy code').last().waitFor()
  check(await page.getByText('parity bold', { exact: true }).count() > 0, 'assistant Markdown renders emphasis and a selectable code block')
  await page.screenshot({ path: join(output, '10-markdown.png') })

  await button('Attach').click()
  const choosingFile = page.waitForEvent('filechooser')
  await button('Choose a file').click()
  await (await choosingFile).setFiles({ name: '手机附件.txt', mimeType: 'text/plain', buffer: Buffer.from('Exact UTF-8 file bytes.\n手机文件预览。\n') })
  await until(async () => !await button('Send').isDisabled())
  await label('Message').fill(`download fixture ${run}`)
  await button('Send').click()
  await button('Open file 手机附件.txt').last().waitFor()
  await button('Open file 手机附件.txt').last().click()
  await button('Preview text').click()
  await page.getByText('Exact UTF-8 file bytes.\n手机文件预览。', { exact: false }).waitFor()
  check(true, 'a file uploaded from the phone previews exact UTF-8 text through the authenticated host API')
  const fileDownloadEvent = page.waitForEvent('download')
  await button('Download file').click()
  const fileDownload = await fileDownloadEvent
  check(readFileSync(await fileDownload.path(), 'utf8') === 'Exact UTF-8 file bytes.\n手机文件预览。\n', 'file download preserves the original bytes')
  check(fileDownload.suggestedFilename() === '手机附件.txt', 'the phone download keeps the original Unicode filename')
  await button('Close').last().click()

  await button('Search conversation').click()
  await label('Search messages').fill(greeting)
  await button('Search').click()
  await page.getByText(/matching messages?/).waitFor()
  const hit = page.getByRole('button', { name: /^Open user message/ }).first()
  await hit.click()
  await page.getByText('Conversation part', { exact: true }).waitFor()
  check(await page.getByText(greeting, { exact: true }).last().isVisible(), 'host history search opens the actual Session context for the selected message')
  await button('Close').last().click()

  await button('Conversation history').click()
  await button('Export conversation').click()
  const exportEvent = page.waitForEvent('download')
  await button('Download JSON').click()
  const exported = JSON.parse(readFileSync(await (await exportEvent).path(), 'utf8'))
  check(exported.messages.some(item => item.text.includes(greeting)) && exported.messages.some(item => item.attachments?.some(file => file.name === '手机附件.txt')), 'JSON export includes canonical conversation history and file metadata')
  check(exported.version === 1 && !exported.messages.some(item => item.requestId || item.pending), 'conversation export excludes receipt metadata and uncommitted stream fragments')
  await button('Close').last().click()

  await button('Skills').click()
  await button('新建技能').click()
  const skillName = `mobile-proof-ui-${run}`
  await label('名称（kebab-case）').fill(skillName)
  await label('用途说明').fill('Check evidence')
  await label('Markdown 指令').fill('# Evidence\nUse only confirmed facts.')
  await button('Save').last().click()
  await page.getByText(skillName, { exact: true }).first().waitFor()
  check(true, 'the phone creates a managed skill through the real public provider')
  const skillRow = page.locator('div').filter({ has: page.getByText(skillName, {exact:true}) }).filter({has:button('查看技能指令')}).last()
  await skillRow.getByRole('button',{name:'查看技能指令',exact:true}).click()
  await page.getByText('Use only confirmed facts.', {exact:true}).waitFor()
  await button('Close').last().click()
  await button(`使用 /${skillName}`).click()
  check(await label('Message').inputValue() === `/${skillName} `, 'choosing a skill prepares a draft for explicit user confirmation')
  await button('Send').click()
  await page.getByText('Mock received mobile skill instructions.',{exact:true}).last().waitFor()
  check(true, 'the confirmed skill draft injects its instructions in a real Harness request')
  await button('Skills').click()
  const managedRow = page.locator('div').filter({has:page.getByText(skillName,{exact:true})}).filter({has:button('Delete')}).last()
  await managedRow.getByRole('button',{name:'Delete',exact:true}).click()
  await button('确认删除').click()
  await until(async () => await page.getByText(skillName,{exact:true}).count() === 0)
  await button('Close').last().click()
  check(true, 'managed skill deletion requires confirmation and removes its live provider entry')
  await settingsPage('通知中心')
  await button('刷新通知').click()
  await button('全部标为已读').click()
  check(await button('开启系统推送').isVisible(), 'the notification center separates its inbox from optional platform push registration')
  check(await button('开启后台运行提醒').isVisible() && await button('开启后台运行提醒').isDisabled() && await button('开启系统推送').isDisabled(), 'web preview explains the credential-free native receiver and keeps unconfigured cloud push optional')
  await page.screenshot({path:join(output,'13-notifications.png')})
  await settingsPage('Harness settings')
  await label('Search settings').waitFor()
  check(await button('Refresh host settings').isVisible(), 'the Harness settings page loads real redacted namespace descriptors')
  await page.screenshot({ path: join(output, '11-host-settings.png') })
  await button('Manage plugins').click()
  await label('Package specification').waitFor()
  check(await button('Inspect package').isDisabled(), 'package management requires a concrete package before inspection')
  await page.screenshot({path:join(output,'14-plugins.png')})

  await settingsPage('Mobile devices')
  await page.getByText(deviceName, { exact: true }).waitFor()
  await page.getByText('This device', { exact: true }).waitFor()
  await page.screenshot({ path: join(output, '03-settings.png') })

  await openChat(chief.name)
  const oldPairingText = `mobile ui prior pairing ${run}`
  let oldPairingPosts = 0
  await page.route('**/mobile/v1/submissions', async route => {
    if (route.request().method() !== 'POST') return route.continue()
    oldPairingPosts++
    await route.fetch()
    await route.abort('connectionfailed')
  })
  await label('Message').fill(oldPairingText)
  await button('Send').click()
  await button('Retry').waitFor()
  await until(async () => !await button('Retry').isDisabled())
  await operator('device.revoke', { id: pairedDevice })
  await page.getByText(/Access revoked|Pair again|Pair this device|session has expired or was revoked/i).first().waitFor({ timeout: 25000 })
  await until(async () => await button('Retry').isDisabled())
  check(true, 'revoked authentication disables retry without replaying a send')
  await settingsPage('Mobile devices')
  await button('Disconnect this device').click()
  await button('Confirm').click()
  await button('Connect to my host').waitFor()
  check(true, 'a revoked device can leave the disconnected workspace and return to pairing')

  await desktop.locator('.bt-account').click()
  await desktop.getByRole('menuitem', { name: /Bot settings|Bot 设置|机器人设置/ }).click()
  await settings.getByRole('button', { name: 'Mobile devices', exact: true }).click()
  const usedPairing = await manualPairing.count() ? await manualPairing.inputValue() : ''
  await settings.getByRole('button', { name: 'Create pairing code', exact: true }).click()
  await until(async () => await manualPairing.inputValue() !== usedPairing)
  const replacementPairing = JSON.parse(await manualPairing.inputValue())
  sensitive.push(replacementPairing.code)
  const replacementName = `${deviceName} re-paired`
  await label('Pairing JSON').fill(JSON.stringify(replacementPairing))
  await label('Device name').fill(replacementName)
  if (replacementPairing.url.startsWith('http:')) await page.getByRole('switch', { name: 'Allow development loopback HTTP' }).check()
  await button('Connect to my host').click()
  await page.getByText('Waiting for approval on your computer…', { exact: true }).waitFor()
  await settings.locator('.bt-set-row').filter({ hasText: replacementName }).getByRole('button', { name: 'Approve', exact: true }).click()
  await button('Open navigation').waitFor()
  await page.getByText('This unconfirmed send belongs to a previous pairing and cannot be retried. Review it on your host before starting a new message.', { exact: true }).waitFor()
  pairedDevice = (await operator('status', {})).devices.find(item => item.name === replacementName || item.deviceName === replacementName)?.id
  check(await button('Retry').isDisabled() && oldPairingPosts === 1, 're-pairing under a new device identity cannot replay an old unconfirmed send')
  await button('Review previous pairing sends').click()
  await page.getByText(oldPairingText, { exact: true }).last().waitFor()
  await button('Archive and start an empty draft').click()
  await button('Send').waitFor()
  check(await label('Message').inputValue() === '' && oldPairingPosts === 1, 'archiving an old pairing receipt keeps its reference without copying or resending the message')
  await page.unroute('**/mobile/v1/submissions')
  check(failures.length === 0, 'the mobile web flow produces no uncaught browser exceptions')
  console.log(`Passed ${checks} mobile UI checks. Screenshots: ${resolve(output)}`)
} catch (error) {
  console.error('Visible app errors:', scrub(JSON.stringify(await page.getByRole('alert').allTextContents().catch(() => []))))
  console.error('Uncaught browser errors:', scrub(JSON.stringify(failures)))
  await page.screenshot({ path: join(output, 'failure.png'), mask: [page.getByRole('textbox')] }).catch(() => {})
  throw new Error(scrub(error.message))
} finally {
  await context.setOffline(false).catch(() => {})
  if (pairedDevice) await operator('device.revoke', { id: pairedDevice }).catch(() => {})
  if (createdRoom) await api('delete-room', { id: createdRoom.id }).catch(() => {})
  if (createdTask) await api('schedule-delete', { sessionId: createdTask.sessionId, id: createdTask.id }).catch(() => {})
  if (createdBot) await api('delete-bot', { id: createdBot.id }).catch(() => {})
  if (originalPrefs) await api('set-prefs', { theme: originalPrefs.theme || 'deepseek', accent: originalPrefs.accent ?? null, motion: originalPrefs.motion ?? false }).catch(() => {})
  await browser.close()
}
