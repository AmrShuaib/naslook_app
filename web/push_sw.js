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

// مهلة تأكيد التبويب أنه فتح الوجهة؛ بعدها يُعاد تحميله على الرابط (نسخة قديمة من التطبيق لا تستمع للرسائل)
const OPEN_ACK_MS = 1500;
const isAppPage = (u) => u.pathname === '/' || u.pathname === '/index.html';

/// يرسل الرابط إلى تبويب التطبيق وينتظر «ok» عبر منفذ الرسالة. true = التطبيق فتح الوجهة بنفسه.
function askTab(client, url) {
  return new Promise((resolve) => {
    let done = false;
    const finish = (v) => { if (!done) { done = true; resolve(v); } };
    const timer = setTimeout(() => finish(false), OPEN_ACK_MS);
    try {
      const ch = new MessageChannel();
      ch.port1.onmessage = (m) => { clearTimeout(timer); finish(m && m.data === 'ok'); };
      client.postMessage({ type: 'naslife:open', url }, [ch.port2]);
    } catch (_) { clearTimeout(timer); finish(false); }
  });
}

/// رابط بمعامل يجبر تحميلاً كاملاً: تغيير الجزء (#) وحده لا يعيد تحميل الصفحة، والتطبيق يقرأ #/n/<id> عند الإقلاع فقط.
function reloadUrl(target) {
  const u = new URL(target.href);
  u.searchParams.set('open', String(Date.now()));
  return u.href;
}

self.addEventListener('notificationclick', (e) => {
  e.notification.close();
  const raw = (e.notification.data && e.notification.data.url) || '/';
  e.waitUntil((async () => {
    const target = new URL(raw, self.location.origin);
    const list = await self.clients.matchAll({ type: 'window', includeUncontrolled: true });
    const sameOrigin = list.filter((c) => { try { return new URL(c.url).origin === target.origin; } catch (_) { return false; } });
    // تبويب التطبيق مفتوح: يُقدَّم ثم يُطلب منه فتح الوجهة برسالة (كان يغيّر الجزء فقط فلا يحدث شيء)
    const tabs = sameOrigin.filter((c) => { try { return isAppPage(new URL(c.url)); } catch (_) { return false; } });
    const tab = tabs.find((c) => c.focused) || tabs.find((c) => c.visibilityState === 'visible') || tabs[0];
    if (tab) {
      // التقديم أولاً: يُسمح به فقط قرب النقرة، قبل انتظار التأكيد
      try { if ('focus' in tab) await tab.focus(); } catch (_) {}
      if (await askTab(tab, target.href)) return;
      try { if ('navigate' in tab) { await tab.navigate(reloadUrl(target)); return; } } catch (_) {}
      return;
    }
    // صفحة أخرى من الموقع (الخصوصية مثلاً): تُنقل إلى الوجهة فيُقلع التطبيق بالرابط؛ لوحة الإدارة لا تُنقل (عمل جارٍ فيها)
    const other = sameOrigin.find((c) => { try { return 'navigate' in c && !new URL(c.url).pathname.startsWith('/admin'); } catch (_) { return false; } });
    if (other) {
      try { await other.navigate(target.href); if ('focus' in other) await other.focus(); return; } catch (_) {}
    }
    return self.clients.openWindow(target.href);
  })());
});
