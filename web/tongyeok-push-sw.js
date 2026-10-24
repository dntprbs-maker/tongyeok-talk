self.addEventListener('install', () => self.skipWaiting());
self.addEventListener('activate', event => event.waitUntil(self.clients.claim()));
self.addEventListener('push', event => {
  let data = {};
  try { data = event.data?.json() || {}; } catch (_) {}
  const mn = data.language === 'mn';
  const appUrl = new URL('../', self.registration.scope).href;
  event.waitUntil(self.registration.showNotification(mn ? 'Орчуулагч Ток' : '통역톡', {
    body: mn ? 'Шинэ зурвас ирлээ. Чатаа нээж шалгана уу.' : '새 메시지가 도착했어요. 대화 목록에서 확인해 주세요.',
    icon: new URL('icons/Icon-192.png', appUrl).href,
    badge: new URL('icons/Icon-192.png', appUrl).href,
    tag: `tongyeok-${data.conversationId || 'message'}`,
    data: {url: appUrl},
    renotify: true,
  }));
});
self.addEventListener('notificationclick', event => {
  event.notification.close();
  const appUrl = new URL('../', self.registration.scope).href;
  event.waitUntil(self.clients.matchAll({type:'window', includeUncontrolled:true}).then(async clients => {
    for (const client of clients) {
      if (client.url.startsWith(appUrl)) { await client.navigate(appUrl); return client.focus(); }
    }
    return self.clients.openWindow(appUrl);
  }));
});
