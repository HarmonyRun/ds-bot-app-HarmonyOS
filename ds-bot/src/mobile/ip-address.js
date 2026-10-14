import { isIP } from 'node:net'

export function ipBytes(address) {
  const family = isIP(address)
  if (!family || address.includes('%')) throw new Error('Use an IPv4 or IPv6 address without an interface scope.')
  if (family === 4) return Buffer.from(address.split('.').map(Number))
  // URL normalizes embedded IPv4 and compressed IPv6 before DER encoding.
  const canonical = new URL(`https://[${address}]`).hostname.slice(1, -1)
  const [left, right] = canonical.split('::').map(part => part ? part.split(':') : [])
  const words = right === undefined ? left : [...left, ...Array(8 - left.length - right.length).fill('0'), ...right]
  const bytes = Buffer.alloc(16)
  words.forEach((word, index) => bytes.writeUInt16BE(parseInt(word, 16), index * 2))
  return bytes
}

export function ipv6Scope(address) {
  if (isIP(address) !== 6 || address.includes('%')) return undefined
  const bytes = ipBytes(address)
  if ((bytes[0] & 0xfe) === 0xfc) return 'private'
  if ((bytes[0] & 0xe0) === 0x20) return 'global'
  // Link-local addresses require interface scopes that differ on each device.
  return undefined
}
