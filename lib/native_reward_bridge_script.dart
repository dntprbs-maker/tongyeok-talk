import 'dart:convert';

String nativeRewardBridgeScript(String nonce, {required bool testMode}) =>
    _script
        .replaceAll('__NONCE_JSON__', jsonEncode(nonce))
        .replaceAll('__TEST_MODE__', jsonEncode(testMode));

const _script = r'''
(() => {
  if (window !== window.top || window.tongyeokNativeRewardProtocolVersion !== 1 ||
      !window.TongyeokNativeReward || window.__tongyeokNativeRewardComplete) return;
  const nonce = __NONCE_JSON__;
  let sequence = 0;
  const pending = new Map();
  const request = (action, uid, fields = {}) => new Promise((resolve, reject) => {
    if (!/^[A-Za-z0-9_-]{20,128}$/.test(uid) || pending.size) return reject(new Error('adUnavailable'));
    const id = 'r' + (++sequence);
    const timer = setTimeout(() => { pending.delete(id); reject(new Error('adLoadFailed')); }, 180000);
    pending.set(id, {resolve, reject, timer});
    try { window.TongyeokNativeReward.postMessage(JSON.stringify({id, action, uid, nonce, ...fields})); }
    catch (_) { clearTimeout(timer); pending.delete(id); reject(new Error('adLoadFailed')); }
  });
  window.__tongyeokNativeRewardComplete = (key, id, value, error) => {
    if (key !== nonce) return;
    const item = pending.get(id);
    if (!item) return;
    clearTimeout(item.timer); pending.delete(id);
    if (error) item.reject(new Error('adLoadFailed')); else item.resolve(value);
  };
  window.tongyeokRewardPrepare = uid => request('prepare', uid);
  window.tongyeokRewardShow = (uid, sessionId, adUnitId, testAds) =>
    request('show', uid, {sessionId, adUnitId, testAds});
  window.tongyeokRewardPrivacy = uid => request('privacy', uid);
  window.tongyeokNativeRewardTestMode = __TEST_MODE__;
  window.tongyeokNativeRewardSupported = true;
  if (typeof Event === 'function' && typeof window.dispatchEvent === 'function')
    window.dispatchEvent(new Event('tongyeok-native-reward-ready'));
})();
''';
