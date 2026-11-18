import 'dart:convert';

String nativePushBridgeScript(String nonce) =>
    _nativePushScript.replaceAll('__NONCE_JSON__', jsonEncode(nonce));

const _nativePushScript = r'''
(() => {
  if (window !== window.top || window.tongyeokNativePushProtocolVersion !== 1 ||
      !window.TongyeokNativePush || window.__tongyeokNativePushComplete) return;
  const nonce = __NONCE_JSON__;
  let sequence = 0;
  const pending = new Map();
  const request = (action, uid) => new Promise((resolve, reject) => {
    if (!/^[A-Za-z0-9_-]{20,128}$/.test(uid)) return reject(new Error('push_failed'));
    const id = 'p' + (++sequence);
    const timer = setTimeout(() => { pending.delete(id); reject(new Error('push_timeout')); }, 20000);
    pending.set(id, {resolve, reject, timer});
    try { window.TongyeokNativePush.postMessage(JSON.stringify({id, action, uid, nonce})); }
    catch (_) { clearTimeout(timer); pending.delete(id); reject(new Error('push_failed')); }
  });
  window.__tongyeokNativePushComplete = (key, id, value, error) => {
    if (key !== nonce) return;
    const item = pending.get(id);
    if (!item) return;
    clearTimeout(item.timer); pending.delete(id);
    if (error) item.reject(new Error('push_failed')); else item.resolve(value);
  };
  window.tongyeokPushState = uid => request('state', uid);
  window.tongyeokPushEnable = uid => request('enable', uid);
  window.tongyeokPushDisable = uid => request('disable', uid);
  window.tongyeokPushConfirm = uid => request('confirm', uid);
  // A native app uses its own notification permission, not Safari's PWA flow.
  window.tongyeokAppleMobile = false;
})();
''';
