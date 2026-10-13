// Real browser checks against an isolated DSH mock-model bench and Expo web preview.
// Usage: node dev/mobile-ui.mjs <bench-name> <dsh-web-port> <app-url> <screenshot-dir>
// Start the bench with MOBILE_PORT=8789 and MOBILE_WEB_ORIGIN matching <app-url>.
import assert from 'node:assert/strict'
import { execFileSync } from 'node:child_process'
import { mkdirSync, readFileSync } from 'node:fs'
import { dirname, join, resolve } from 'node:path'
import { fileURLToPath } from 'node:url'
import { playwright } from './desktop-linux/lib.mjs'

const [bench, port, appUrl, output = '/tmp/ds-bot-mobile-ui'] = process.argv.slice(2)
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
const context = await browser.newContext({ viewport: { width: 390, height: 844 }, isMobile: true, deviceScaleFactor: 1 })
const desktop = await desktopContext.newPage()
const page = await context.newPage()
page.setDefaultTimeout(30000)
const failures = []
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
const tab = text => page.getByRole('tab', { name: text, exact: true })
const cachedUserCount = text => page.evaluate(text => Object.keys(localStorage)
  .filter(key => key.startsWith('ds-bot:cache:') && key.includes('messages:'))
  .flatMap(key => { try { const value = JSON.parse(localStorage.getItem(key)); return Array.isArray(value) ? value : [] } catch { return [] } })
  .filter(message => message.role === 'user' && message.text === text).length, text)
let createdBot
let pairedDevice
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
  check(await tab('Chat').count() === 0, 'pairing stays locked until the desktop owner approves')
  const pendingRow = settings.locator('.bt-set-row').filter({ hasText: deviceName })
  await pendingRow.getByRole('button', { name: 'Approve', exact: true }).click()
  await tab('Chat').waitFor()
  await label('Message').waitFor()
  pairedDevice = (await operator('status', {})).devices.find(item => item.name === deviceName || item.deviceName === deviceName)?.id
  check(Boolean(pairedDevice), 'approved browser device appears in the real host device list')

  const state = await api('state')
  const chief = state.bots.find(bot => bot.id === state.mainBotId)
  if (!chief?.model) {
    await page.getByRole('button', { name: /Choose a model to begin/ }).click()
    await page.getByRole('button', { name: /Mock/ }).first().click()
  }
  const greeting = `mobile ui greeting ${run}`
  await label('Message').fill(greeting)
  await button('Send ↑').click()
  await page.getByText(`收到：${greeting}`, { exact: false }).first().waitFor({ timeout: 45000 })
  check(await page.getByText(greeting, { exact: true }).count() === 1, 'chat submits a real message and renders one user bubble')
  check(streamDeltas > 0, 'the real DSH reply arrives through streaming websocket deltas')
  await page.screenshot({ path: join(output, '01-chat.png') })

  await context.setOffline(true)
  await page.getByText(/Host offline\. Cached messages/).waitFor({ timeout: 20000 })
  await label('Message').fill(`offline draft ${run}`)
  await tab('Team').click()
  await tab('Chat').click()
  await label('Message').waitFor()
  await until(async () => await label('Message').inputValue() === `offline draft ${run}`)
  await until(async () => await cachedUserCount(greeting) === 1)
  check(true, 'cached history and draft survive changing screens while offline')
  check(await button('Send ↑').isDisabled(), 'offline mode prevents new sends')
  await context.setOffline(false)
  await until(async () => !await button('Send ↑').isDisabled(), 25000)

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
  await button('Send ↑').click()
  await button('Retry').waitFor()
  await until(async () => !await button('Retry').isDisabled())
  await button('Retry').click()
  await button('Send ↑').waitFor()
  await page.getByText(`收到：${uncertain}`, { exact: false }).first().waitFor({ timeout: 45000 })
  await until(async () => await cachedUserCount(uncertain) === 1)
  check(postCount === 1, 'a lost submission response is recovered by its receipt without duplicate sending')
  await page.unroute('**/mobile/v1/submissions')

  await tab('Team').click()
  await button('＋ New Bot').click()
  const botName = `Mobile reviewer ${run}`
  await label('Name').fill(botName)
  await label('Role').fill('Mobile test reviewer')
  await label('Instructions').fill('Review the current task briefly.')
  await button('Save Bot').click()
  await label('Name').waitFor({ state: 'hidden' })
  createdBot = (await api('state')).bots.find(bot => bot.name === botName)
  check(Boolean(createdBot), 'the mobile team form creates a Bot on the real host')
  const card = page.getByText(botName, { exact: true }).locator('..').locator('..').locator('..').locator('..')
  await card.getByRole('button', { name: 'Edit', exact: true }).click()
  await label('Role').fill('Reviewed from mobile')
  await button('Save Bot').click()
  await label('Name').waitFor({ state: 'hidden' })
  check((await api('state')).bots.find(bot => bot.id === createdBot.id)?.role === 'Reviewed from mobile', 'editing a Bot updates host team state')
  await page.screenshot({ path: join(output, '02-team.png') })

  await tab('Settings').click()
  await page.getByText(`${deviceName} · this device`, { exact: true }).waitFor()
  await page.screenshot({ path: join(output, '03-settings.png') })

  await tab('Chat').click()
  const oldPairingText = `mobile ui prior pairing ${run}`
  let oldPairingPosts = 0
  await page.route('**/mobile/v1/submissions', async route => {
    if (route.request().method() !== 'POST') return route.continue()
    oldPairingPosts++
    await route.fetch()
    await route.abort('connectionfailed')
  })
  await label('Message').fill(oldPairingText)
  await button('Send ↑').click()
  await button('Retry').waitFor()
  await until(async () => !await button('Retry').isDisabled())
  await operator('device.revoke', { id: pairedDevice })
  await page.getByText(/Access revoked|Pair again|Pair this device|session has expired or was revoked/i).first().waitFor({ timeout: 25000 })
  check(await button('Retry').isDisabled(), 'host revocation immediately prevents more chat sends')
  await tab('Settings').click()
  await button('Disconnect this device').click()
  await button('Confirm').click()
  await button('Connect to my host').waitFor()
  check(true, 'a revoked device can leave the disconnected workspace and return to pairing')

  const usedPairing = await manualPairing.inputValue()
  await settings.getByRole('button', { name: 'Create pairing code', exact: true }).click()
  await until(async () => await manualPairing.inputValue() !== usedPairing)
  const replacementPairing = JSON.parse(await manualPairing.inputValue())
  const replacementName = `${deviceName} re-paired`
  await label('Pairing JSON').fill(JSON.stringify(replacementPairing))
  await label('Device name').fill(replacementName)
  if (replacementPairing.url.startsWith('http:')) await page.getByRole('switch', { name: 'Allow development loopback HTTP' }).check()
  await button('Connect to my host').click()
  await page.getByText('Waiting for approval on your computer…', { exact: true }).waitFor()
  await settings.locator('.bt-set-row').filter({ hasText: replacementName }).getByRole('button', { name: 'Approve', exact: true }).click()
  await tab('Chat').waitFor()
  await page.getByText('This unconfirmed send belongs to a previous pairing and cannot be retried. Review it on your host before starting a new message.', { exact: true }).waitFor()
  pairedDevice = (await operator('status', {})).devices.find(item => item.name === replacementName || item.deviceName === replacementName)?.id
  check(await button('Retry').isDisabled() && oldPairingPosts === 1, 're-pairing under a new device identity cannot replay an old unconfirmed send')
  await button('Review previous pairing sends').click()
  await page.getByText(oldPairingText, { exact: true }).last().waitFor()
  await button('Archive and start an empty draft').click()
  await button('Send ↑').waitFor()
  check(await label('Message').inputValue() === '' && oldPairingPosts === 1, 'archiving an old pairing receipt keeps its reference without copying or resending the message')
  await page.unroute('**/mobile/v1/submissions')
  check(failures.length === 0, 'the mobile web flow produces no uncaught browser exceptions')
  console.log(`Passed ${checks} mobile UI checks. Screenshots: ${resolve(output)}`)
} catch (error) {
  console.error('Visible app errors:', JSON.stringify(await page.getByRole('alert').allTextContents().catch(() => [])))
  console.error('Uncaught browser errors:', JSON.stringify(failures))
  await page.screenshot({ path: join(output, 'failure.png'), mask: [page.getByRole('textbox')] }).catch(() => {})
  throw error
} finally {
  await context.setOffline(false).catch(() => {})
  if (pairedDevice) await operator('device.revoke', { id: pairedDevice }).catch(() => {})
  if (createdBot) await api('delete-bot', { id: createdBot.id }).catch(() => {})
  await browser.close()
}
