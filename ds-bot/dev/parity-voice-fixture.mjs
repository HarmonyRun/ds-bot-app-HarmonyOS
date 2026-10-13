// Controlled UI lifecycle test only. This does not perform speech recognition.
// Explicitly loaded in an isolated mock bench; excluded from the plugin archive.
import { basename } from 'node:path'
import { Service } from '@deepseek-ai/cordis'

export default class VoiceFixture extends Service {
  constructor(ctx, config) {
    if (!/^[a-z0-9-]+$/.test(config.bench ?? '') || basename(process.env.DSH_HOME ?? '') !== `.dsh-test-${config.bench}`) {
      throw new Error('The voice fixture requires an explicitly named isolated mock bench')
    }
    super(ctx, 'speechToText')
  }
  snapshot() { return { providers: [{ id: 'mock-ui', name: 'Mock UI lifecycle fixture', preparation: { phase: 'ready' } }] } }
  resolve({ audio }) { return { audio } }
  async transcribe({ audio }, signal) {
    signal.throwIfAborted()
    if (audio.length < 44 || Buffer.from(audio.subarray(0, 4)).toString() !== 'RIFF') throw new Error('The fixture requires normalized WAV input')
    await new Promise((resolve, reject) => {
      const finish = () => { signal.removeEventListener('abort', abort); resolve() }
      const timer = setTimeout(finish, 200)
      const abort = () => { clearTimeout(timer); reject(signal.reason) }
      signal.addEventListener('abort', abort, { once: true })
    })
    signal.throwIfAborted()
    return { text: 'Voice lifecycle fixture.', audioSeconds: 3, inferenceSeconds: 0.2 }
  }
}
