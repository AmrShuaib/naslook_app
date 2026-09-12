// عامل خدمة للإشعارات الفورية فقط: لا يخزّن أي ملفات ولا يعترض الطلبات، حتى تصل التحديثات فوراً.
self.addEventListener('install', () => self.skipWaiting());
self.addEventListener('activate', (e) => e.waitUntil(self.clients.claim()));

self.addEventListener('push', (e) => {
  let d = {};
  try { d = e.data ? e.data.json() : {}; } catch (_) { d = { body: e.data ? e.data.text() : '' }; }
  const title = d.title || d.nickname || 'Naslife';
  const body = d.body || d.message || d.content || '';
  const url = d.url || d.link || '/';
  e.waitUntil(self.registration.showNotification(title, {
    body, icon: '/icons/Icon-192.png', badge: '/icons/Icon-192.png', dir: 'rtl', lang: 'ar',
    tag: d.tag || d.peerId || 'naslife', renotify: true, data: { url },
  }));
});

self.addEventListener('notificationclick', (e) => {
  e.notification.close();
  const url = (e.notification.data && e.notification.data.url) || '/';
  e.waitUntil(self.clients.matchAll({ type: 'window', includeUncontrolled: true }).then((list) => {
    for (const c of list) { if ('focus' in c) { if (c.navigate) c.navigate(url); return c.focus(); } }
    return self.clients.openWindow(url);
  }));
});
