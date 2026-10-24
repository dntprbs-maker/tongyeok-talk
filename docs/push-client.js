(() => {
  const base = new URL('./', document.baseURI);
  const supported = () => 'serviceWorker' in navigator && 'PushManager' in window && 'Notification' in window && !!window.TONGYEOK_PUSH_PUBLIC_KEY;
  const ownerKey = 'tongyeok.pushOwner', deviceKey = 'tongyeok.pushDevice';
  const registration = () => navigator.serviceWorker.register(new URL('tongyeok-push-sw.js', base).href, {scope: new URL('push/', base).href});
  window.tongyeokPushState = async uid => {
    if (!supported()) return 'unsupported';
    if (Notification.permission === 'denied') return 'denied';
    if (localStorage.getItem(ownerKey) !== uid) return 'off';
    const reg = await registration();
    return Notification.permission === 'granted' && await reg.pushManager.getSubscription() ? 'enabled' : 'off';
  };
  window.tongyeokPushEnable = async uid => {
    if (!supported()) return 'unsupported';
    if (await Notification.requestPermission() !== 'granted') return Notification.permission === 'denied' ? 'denied' : 'off';
    const reg = await registration();
    if (!reg.active) await new Promise(resolve => {
      const worker = reg.installing || reg.waiting;
      if (!worker) return resolve();
      worker.addEventListener('statechange', () => { if (worker.state === 'activated') resolve(); });
    });
    let sub = await reg.pushManager.getSubscription();
    if (sub && localStorage.getItem(ownerKey) !== uid) { await sub.unsubscribe(); sub = null; }
    sub ||= await reg.pushManager.subscribe({userVisibleOnly:true, applicationServerKey:window.TONGYEOK_PUSH_PUBLIC_KEY});
    let deviceId = localStorage.getItem(deviceKey);
    if (!deviceId) { deviceId = crypto.randomUUID(); localStorage.setItem(deviceKey, deviceId); }
    localStorage.setItem(ownerKey, uid);
    return JSON.stringify({deviceId, subscription:sub.toJSON()});
  };
  window.tongyeokPushDisable = async uid => {
    if (!supported() || localStorage.getItem(ownerKey) !== uid) return 'off';
    const reg = await registration(), sub = await reg.pushManager.getSubscription();
    if (sub && !(await sub.unsubscribe())) throw new Error('unsubscribe_failed');
    localStorage.removeItem(ownerKey);
    return JSON.stringify({deviceId:localStorage.getItem(deviceKey)});
  };
})();
