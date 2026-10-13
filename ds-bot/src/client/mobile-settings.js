import { createElement as h, useEffect, useRef, useState } from 'react'
import { call } from './api.js'
import { t } from './i18n.js'

const mobile = (endpoint, payload) => call('mobile', { endpoint, payload })

export function MobileDevicesPage() {
  const [state, setState] = useState(null)
  const [pairing, setPairing] = useState(null)
  const [error, setError] = useState('')
  const [busy, setBusy] = useState(false)
  const alive = useRef(true)
  const [address, setAddress] = useState('')
  useEffect(() => {
    let disposed = false
    alive.current = true
    const refresh = () => mobile('status').then(value => {
      if (!disposed) { setState(value); setError(value.error ?? value.https?.error ?? ''); setPairing(previous => previous && (previous.url !== value.url || Date.now() >= new Date(previous.expiresAt).getTime()) ? null : previous) }
    }, () => { if (!disposed) setError('Could not refresh mobile devices.') })
    void refresh()
    const timer = setInterval(refresh, 3000)
    return () => { disposed = true; alive.current = false; clearInterval(timer) }
  }, [])
  const run = async (endpoint, payload) => {
    if (busy) return
    setBusy(true)
    setError('')
    try {
      const result = await mobile(endpoint, payload)
      if (endpoint === 'https.enable') {
        const code = await mobile('pairing.create')
        if (alive.current) setPairing(code)
      }
      if (endpoint === 'pairing.create' && alive.current) setPairing(result)
      if (endpoint === 'https.disable' && alive.current) setPairing(null)
      const current = await mobile('status')
      if (alive.current) setState(current)
    } catch (cause) { if (alive.current) setError(cause.message ?? 'Request failed.') }
    finally { if (alive.current) setBusy(false) }
  }
  const row = (key, label, hint, children) => h('div', { key, className: 'bt-set-row' },
    h('div', { className: 'bt-set-copy' }, h('span', null, t(label)), hint ? h('span', { className: 'bt-set-hint' }, t(hint)) : null), children)
  const button = (label, action) => h('button', { type: 'button', className: 'bt-soft bt-soft-sm', disabled: busy, onClick: action }, t(label))
  const activePairing = pairing && Date.now() < new Date(pairing.expiresAt).getTime()
  return h('section', { className: 'bt-set-section' },
    error ? h('div', { className: 'bt-error', role: 'alert' }, t(error)) : null,
    !state ? h('p', null, t('Loading devices…')) : !state.enabled
      ? h('div', { className: 'bt-set-card' }, row('off', 'Connect your phone', state.locked ? 'Mobile access is disabled by this host configuration.' : 'One click starts local HTTPS. Then scan the QR code in DS Bot Mobile on the same Wi-Fi. No domain or extra app is needed.',
            !state.locked && state.https?.provider === 'local' ? h('div', { className: 'bt-actions' },
              (state.https.addresses?.length ?? 0) > 1 ? h('select', { 'aria-label': t('Computer network address'), value: address, onChange: event => setAddress(event.target.value), disabled: busy },
                h('option', { value: '' }, t('Automatic network address')), ...state.https.addresses.map(item => h('option', { key: item.address, value: item.address }, item.name + ' · ' + item.address))) : null,
              button('Enable phone connection', () => void run('https.enable', address ? { address } : {}))) : null))
      : h('div', { className: 'bt-set-card' },
          row('host', 'Connect your phone', state.url ?? 'Mobile bridge', button('Create pairing code', () => void run('pairing.create'))),
          state.https?.provider === 'local' ? row('https', 'Local HTTPS is running', 'Keep both devices on the same Wi-Fi. If the firewall asks, allow access on your private network.', button('Turn off phone connection', () => { if (window.confirm(t('Disconnect all phones from this host?'))) void run('https.disable') })) : null,
          activePairing ? h('div', { className: 'bt-set-row', style: { flexDirection: 'column', alignItems: 'flex-start', gap: 12 } },
            h('img', { src: pairing.qrDataUrl, width: 220, height: 220, alt: t('Scan this code in DS Bot Mobile to request access.') }),
            button('Hide pairing code', () => setPairing(null)),
            h('p', { className: 'bt-set-hint' }, t('Scan in the mobile app, then approve the device below. This code expires in two minutes.')),
            h('label', { style: { width: '100%' } }, t('Manual pairing data'), h('textarea', {
              readOnly: true, rows: 3, style: { width: '100%', wordBreak: 'break-all' },
              'aria-label': t('Manual pairing data'), value: JSON.stringify({ url: pairing.url, code: pairing.code, serverId: pairing.serverId, ...(pairing.tlsPin ? { tlsPin: pairing.tlsPin } : {}) }),
            }))) : null,
          ...(state.pending ?? []).map(request => row(request.requestId, request.deviceName ?? 'Phone', 'Requests access to your Bot team. Approve only a device you recognize.',
            h('div', { className: 'bt-actions' },
              button('Approve', () => void run('pairing.approve', { requestId: request.requestId })),
              button('Deny', () => void run('pairing.deny', { requestId: request.requestId }))))),
          ...(state.devices ?? []).filter(device => !device.revokedAt).map(device => row(device.id, device.name ?? device.deviceName ?? 'Phone', 'Paired device',
            button('Revoke access', () => {
              if (window.confirm(t('Revoke this device? It must pair again to reconnect.'))) void run('device.revoke', { id: device.id })
            }))),
          row('scope', 'Your phone uses this DSH host', 'Keep this computer or server running. Tool approvals remain in DSH. Revoking a device stops new access; it does not erase its local cache.')))
}
