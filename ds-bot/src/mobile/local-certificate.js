import { createHash, createPrivateKey, createPublicKey, generateKeyPairSync, randomBytes, sign, X509Certificate } from 'node:crypto'
import { chmod, mkdir, readFile, rename, writeFile } from 'node:fs/promises'
import { join } from 'node:path'
import { ipBytes } from './ip-address.js'

const der = (tag, bytes) => {
  const value = Buffer.from(bytes)
  let length = value.length
  const encoded = []
  do { encoded.unshift(length & 255); length >>>= 8 } while (length)
  return Buffer.concat([Buffer.from([tag, ...(value.length < 128 ? [value.length] : [128 | encoded.length, ...encoded])]), value])
}
const seq = (...values) => der(0x30, Buffer.concat(values))
const hex = value => Buffer.from(value, 'hex')
const algorithm = seq(hex('06082a8648ce3d040302'))
const name = seq(der(0x31, seq(hex('0603550403'), der(0x0c, Buffer.from('DS Bot local computer')))))
const extension = (oid, value, critical = false) => seq(hex(oid), ...(critical ? [hex('0101ff')] : []), der(4, value))
const time = value => {
  const digits = value.toISOString().replace(/[-:T]/g, '').slice(0, 14)
  return der(value.getUTCFullYear() < 2050 ? 0x17 : 0x18, Buffer.from((value.getUTCFullYear() < 2050 ? digits.slice(2) : digits) + 'Z'))
}
const pem = bytes => '-----BEGIN CERTIFICATE-----\n' + bytes.toString('base64').match(/.{1,64}/g).join('\n') + '\n-----END CERTIFICATE-----\n'
const fingerprint = key => 'sha256:' + createHash('sha256').update(createPublicKey(key).export({ format: 'der', type: 'spki' })).digest('hex')

export function generateLocalCertificate(privateKey, addresses, now = Date.now()) {
  if (!Array.isArray(addresses) || !addresses.length) throw new Error('Choose an IPv4 or IPv6 address for mobile access.')
  const names = [...new Set(addresses)].map(ipBytes)
  const publicKey = createPublicKey(privateKey).export({ format: 'der', type: 'spki' })
  const serialBytes = randomBytes(16)
  serialBytes[0] |= 0x80
  const serial = der(2, Buffer.concat([Buffer.from([0]), serialBytes]))
  const extensions = der(0xa3, seq(
    extension('0603551d13', seq(), true),
    extension('0603551d0f', hex('03020780'), true),
    extension('0603551d25', seq(hex('06082b06010505070301'))),
    extension('0603551d11', seq(...names.map(bytes => der(0x87, bytes)))),
  ))
  const tbs = seq(der(0xa0, hex('020102')), serial, algorithm, name,
    seq(time(new Date(now - 300000)), time(new Date(now + 365 * 86400000))), name, publicKey, extensions)
  return pem(seq(tbs, algorithm, der(3, Buffer.concat([Buffer.from([0]), sign('sha256', tbs, privateKey)]))))
}

export async function ensureLocalCertificate(home, addresses, { now = Date.now(), assertOwner = () => {} } = {}) {
  assertOwner()
  await mkdir(home, { recursive: true, mode: 0o700 })
  await chmod(home, 0o700)
  const keyPath = join(home, 'computer.key')
  const certPath = join(home, 'computer.crt')
  let key
  try {
    key = createPrivateKey(await readFile(keyPath))
    if (key.asymmetricKeyType !== 'ec' || key.asymmetricKeyDetails?.namedCurve !== 'prime256v1') throw new Error('Unsupported local identity key')
  }
  catch (error) {
    if (error.code !== 'ENOENT') throw new Error('The local computer identity cannot be read. Restore its private key before reconnecting phones.')
    key = generateKeyPairSync('ec', { namedCurve: 'prime256v1' }).privateKey
    assertOwner()
    const pending = keyPath + '.tmp'
    await writeFile(pending, key.export({ format: 'pem', type: 'pkcs8' }), { mode: 0o600 })
    assertOwner(); await rename(pending, keyPath)
  }
  let cert
  try { cert = new X509Certificate(await readFile(certPath)) } catch {}
  if (!cert || !cert.checkPrivateKey(key) || !cert.verify(cert.publicKey) || Date.parse(cert.validTo) <= now + 7 * 86400000 || Date.parse(cert.validFrom) > now || addresses.some(ip => !cert.checkIP(ip))) {
    const body = generateLocalCertificate(key, addresses, now)
    const pending = certPath + '.tmp'
    assertOwner(); await writeFile(pending, body, { mode: 0o600 })
    assertOwner(); await rename(pending, certPath)
    cert = new X509Certificate(body)
  }
  await chmod(keyPath, 0o600); await chmod(certPath, 0o600)
  return { certPath, keyPath, tlsPin: fingerprint(key), expiresAt: cert.validTo }
}
