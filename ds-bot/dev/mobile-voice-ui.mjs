// Controlled voice lifecycle: fake microphone WAV, fixture ASR and silent TTS callbacks.
// Use PARITY_VOICE=1 in an isolated bench. Real recognition is verified separately.
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
if (!process.env.MOBILE_VOICE_WAV) throw new Error('Set MOBILE_VOICE_WAV to an isolated synthetic microphone WAV fixture.')
const browser = await chromium.launch({ executablePath, headless: true, args: ['--use-fake-ui-for-media-stream', '--use-fake-device-for-media-stream', `--use-file-for-fake-audio-capture=${resolve(process.env.MOBILE_VOICE_WAV)}`] })
const desktopContext = await browser.newContext()
const context = await browser.newContext({ viewport: { width: 390, height: 844 }, isMobile: true, deviceScaleFactor: 1, locale: 'en-US', permissions: ['microphone'] })
const desktop = await desktopContext.newPage()
const page = await context.newPage()
page.setDefaultTimeout(30000)
const failures = []
const sensitive = []
sensitive.push(login, new URL(login).searchParams.get('token') || login)
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
let pairedDevice
await page.addInitScript(() => {
  window.testTracks = []
  window.testSpeech = []
  const getMedia = navigator.mediaDevices.getUserMedia.bind(navigator.mediaDevices)
  navigator.mediaDevices.getUserMedia = async (...args) => { const stream = await getMedia(...args); window.testTracks.push(...stream.getTracks()); return stream }
  speechSynthesis.speak = utterance => { window.testSpeech.push(utterance.text); setTimeout(() => utterance.dispatchEvent(new Event('end')), 200) }
  speechSynthesis.cancel = () => {}
})
let posts = 0
page.on('request', request => { if (request.method() === 'POST' && new URL(request.url()).pathname === '/mobile/v1/submissions') posts++ })
try {
  await desktop.goto(login).catch(() => { throw new Error('Could not open the isolated desktop test session.') })
  await desktop.locator('.bt-tile, .bt-row').first().waitFor({timeout: 60000})
  const pairing = await operator('pairing.create', {})
  await page.goto(appUrl)
  await label('Pairing JSON').fill(JSON.stringify(pairing))
  await label('Device name').fill('Controlled voice UI fixture')
  await page.getByRole('switch', {name:'Allow development loopback HTTP'}).check()
  await button('Connect to my host').click()
  const pending = await until(async () => (await operator('status')).pending.find(item => item.deviceName === 'Controlled voice UI fixture'))
  await operator('pairing.approve', {requestId:pending.requestId})
  await page.getByRole('button', {name:/^(Open navigation|打开导航)$/}).waitFor()
  await english()
  pairedDevice = (await operator('status')).devices.find(item => item.name === 'Controlled voice UI fixture' || item.deviceName === 'Controlled voice UI fixture')?.id
  const team = await api('state')
  const chief = team.bots.find(item => item.id === team.mainBotId)
  await openChat(chief.name)
  await until(async () => !await button('Voice chat').isDisabled())
  await button('Voice chat').click()
  await page.getByText('Paused', {exact:true}).waitFor()
  check(await page.evaluate(() => window.testTracks.length === 0), 'opening voice mode does not activate the microphone')
  await button('Resume listening').click()
  await page.getByText('Listening…', {exact:true}).waitFor()
  await until(async () => posts > 0, 30000)
  check(posts === 1, 'speech followed by silence creates exactly one submission through the real mobile transport')
  await until(async () => await page.evaluate(() => window.testSpeech.length > 0), 45000)
  await page.getByText('Listening…', {exact:true}).waitFor()
  check(await page.evaluate(() => window.testSpeech[0].includes('Voice lifecycle fixture.')), 'the accepted mock reply is spoken and then listening resumes')
  await button('Pause').click()
  await page.getByText('Paused', {exact:true}).waitFor()
  await until(async () => await page.evaluate(() => window.testTracks.every(track => track.readyState === 'ended')))
  check(true, 'pause releases every microphone track')
  const acceptedPosts = posts
  await button('Resume listening').click()
  await page.getByText('Listening…', {exact:true}).waitFor()
  await context.setOffline(true)
  await page.getByText('Paused', {exact:true}).waitFor({timeout:25000})
  await until(async () => await page.evaluate(() => window.testTracks.every(track => track.readyState === 'ended')))
  check(posts === acceptedPosts, 'disconnect pauses recording without creating another submission')
  await context.setOffline(false)
  await until(async () => !await button('Resume listening').isDisabled())
  check(await page.getByText('Paused', {exact:true}).isVisible(), 'reconnection requires an explicit resume')
  let releaseTranscription
  const gate = new Promise(resolve => { releaseTranscription = resolve })
  await page.route('**/mobile/v1/transcriptions?*', async route => { await gate; await route.continue().catch(() => {}) })
  await button('Resume listening').click()
  await page.getByText('Listening…', {exact:true}).waitFor()
  await until(async () => !await button('Send voice turn').isDisabled())
  await button('Send voice turn').click()
  await page.getByText('Transcribing…', {exact:true}).waitFor()
  await button('Pause').click()
  releaseTranscription()
  await page.getByText('Paused', {exact:true}).waitFor()
  await button('End voice chat').click()
  await button('Voice chat').waitFor()
  await page.waitForTimeout(800)
  check(posts === acceptedPosts, 'cancelling transcription and closing cannot send late recognized text')
  await until(async () => await page.evaluate(() => window.testTracks.every(track => track.readyState === 'ended')))
  check(failures.length === 0, 'controlled voice lifecycle has no uncaught browser exceptions')
  console.log(`Passed ${checks} controlled voice UI checks. ASR and audible TTS are fixtures; real SenseVoice is verified separately.`)
} catch(error) {
  console.error('App alerts:', scrub(JSON.stringify(await page.getByRole('alert').allTextContents())))
  console.error('Page errors:', scrub(JSON.stringify(failures)))
  await page.screenshot({path:join(output,'voice-failure.png')})
  throw new Error(scrub(error.message))
} finally {
  await context.setOffline(false).catch(() => {})
  if(pairedDevice) await operator('device.revoke',{id:pairedDevice}).catch(() => {})
  await browser.close()
}
