// Fixed, application-owned scripts. The mobile API never accepts JavaScript or selectors.
export function mobilePage(request) {
  const key = '__dsBotMobilePage';
  const visible = node => node.isConnected && node.getClientRects().length > 0 && getComputedStyle(node).visibility !== 'hidden';
  const secret = node => node.type === 'password' || /password|passwd|token|secret|api.?key|credit.?card|cvv|cc-|one-time-code|\botp\b|passcode/i.test(`${node.name || ''} ${node.id || ''} ${node.autocomplete || ''}`);
  if (request.command === 'snapshot') {
    const nodes = [];
    const scan = root => {
      for (const node of root.querySelectorAll('a[href],button,input:not([type=hidden]),textarea,select,[role=button],[contenteditable=true]')) {
        if (nodes.length >= 100) break;
        if (visible(node) && !secret(node)) nodes.push(node);
      }
      for (const node of root.querySelectorAll('*')) if (node.shadowRoot && nodes.length < 100) scan(node.shadowRoot);
    };
    scan(document);
    window[key] = { id: request.snapshotId, url: location.href, nodes };
    return { snapshotId: request.snapshotId, url: location.href, title: document.title, text: (document.body?.innerText || '').slice(0, 12000), controls: nodes.map((node, index) => ({ item: index, role: node.tagName.toLowerCase(), name: (node.getAttribute('aria-label') || node.innerText || node.placeholder || node.name || node.type || '').slice(0, 160), disabled: node.disabled === true, editable: (['INPUT', 'TEXTAREA'].includes(node.tagName) && !['submit', 'button', 'checkbox', 'radio', 'file'].includes(node.type)) || node.isContentEditable })) };
  }
  if (request.command === 'scroll') { window.scrollBy({ top: request.direction === 'up' ? -600 : 600, behavior: 'instant' }); return { changed: true }; }
  const state = window[key];
  if (!state || state.id !== request.snapshotId || state.url !== location.href) throw new Error('Page changed. Refresh before interacting.');
  const node = state.nodes[request.item];
  if (!node || !visible(node) || node.disabled || secret(node)) throw new Error('This control is no longer available.');
  if (request.command === 'click') { node.click(); window[key] = undefined; return { changed: true }; }
  if (request.command === 'fill') {
    if (!(['INPUT', 'TEXTAREA'].includes(node.tagName) || node.isContentEditable) || ['file', 'checkbox', 'radio', 'submit', 'button'].includes(node.type)) throw new Error('This is not a text field.');
    node.focus();
    if (node.isContentEditable) node.textContent = request.text;
    else {
      const prototype = node.tagName === 'TEXTAREA' ? HTMLTextAreaElement.prototype : HTMLInputElement.prototype;
      Object.getOwnPropertyDescriptor(prototype, 'value').set.call(node, request.text);
    }
    node.dispatchEvent(new Event('input', { bubbles: true })); node.dispatchEvent(new Event('change', { bubbles: true }));
    window[key] = undefined;
    return { changed: true };
  }
  throw new Error('Unsupported browser action.');
}
export const mobilePageScript = request => `(${mobilePage.toString()})(${JSON.stringify(request)})`;
