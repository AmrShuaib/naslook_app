// عامل خدمة الإشعارات (web/push_sw.js) في بيئة وهمية بلا متصفح: النقر على إشعار والتطبيق مفتوح يُقدّم التبويب ويرسل إليه
// الرابط برسالة (ولا يكتفي بتغيير الجزء # الذي لا يقرؤه التطبيق إلا عند الإقلاع)؛ تبويب قديم لا يؤكد خلال المهلة يُعاد تحميله
// على الرابط؛ صفحة أخرى من الموقع تُنقل إلى الوجهة؛ وبلا تبويبات تُفتح نافذة. وحدث الدفع يعرض الإشعار برابطه.
import fs from 'node:fs';
import vm from 'node:vm';

let fails = 0;
const check = (c, l, extra = '') => { if (!c) fails++; console.log((c ? 'OK  ' : 'FAIL') + ' ' + l + (extra ? ' ' + extra : '')); };
const src = fs.readFileSync(new URL('../../web/push_sw.js', import.meta.url), 'utf8');
const ID = '0d6f3c1e-1111-4222-8333-444455556666';

function makeSw(clients) {
  const handlers = {};
  const log = { opened: [], shown: [] };
  class FakeChannel { constructor() { this.port1 = { onmessage: null }; this.port2 = { postMessage: (d) => setTimeout(() => this.port1.onmessage?.({ data: d }), 5) }; } }
  const self = {
    addEventListener: (t, fn) => { handlers[t] = fn; },
    skipWaiting: () => {},
    location: { origin: 'https://naslife.app' },
    registration: { showNotification: async (title, opts) => { log.shown.push({ title, opts }); } },
    clients: { claim: async () => {}, matchAll: async () => clients, openWindow: async (u) => { log.opened.push(u); } },
  };
  vm.runInNewContext(src, { self, URL, setTimeout, clearTimeout, MessageChannel: FakeChannel, String, Date, Promise });
  const click = async (url) => {
    let p; let closed = false;
    handlers.notificationclick({ notification: { close: () => { closed = true; }, data: { url } }, waitUntil: (x) => { p = x; } });
    await p;
    return closed;
  };
  return { handlers, log, click };
}
/// تبويب وهمي: ack = التطبيق يستمع ويؤكد (النسخة الجديدة)
function tab(url, { ack = true, focused = false, visible = 'visible' } = {}) {
  const t = { url, focused, visibilityState: visible, posted: [], navigated: [], focusedCalls: 0 };
  t.postMessage = (msg, ports) => { t.posted.push(msg); if (ack && msg.type === 'naslife:open' && /#\/n\//.test(msg.url)) ports[0].postMessage('ok'); };
  t.focus = async () => { t.focusedCalls++; return t; };
  t.navigate = async (u) => { t.navigated.push(u); return t; };
  return t;
}

// 1) تبويب التطبيق مفتوح بنسخة تستمع: رسالة + تقديم، بلا تنقل ولا نافذة جديدة
{
  const a = tab('https://naslife.app/#/');
  const sw = makeSw([a]);
  const closed = await sw.click(`/#/n/${ID}`);
  check(closed && a.focusedCalls === 1 && a.posted.length === 1 && a.posted[0].type === 'naslife:open' && a.posted[0].url === `https://naslife.app/#/n/${ID}`, 'open app tab: focused and told to open the notification by message', JSON.stringify(a.posted));
  check(a.navigated.length === 0 && sw.log.opened.length === 0, 'open app tab: no navigation (a hash-only change opens nothing) and no new window');
}
// 2) تبويب بنسخة قديمة لا تؤكد: بعد المهلة يُعاد تحميله على الرابط بمعامل يجبر التحميل
{
  const a = tab('https://naslife.app/#/', { ack: false });
  const sw = makeSw([a]);
  const t0 = Date.now();
  await sw.click(`/#/n/${ID}`);
  const nav = a.navigated[0] ?? '';
  check(a.focusedCalls === 1 && a.navigated.length === 1 && /\?open=\d+#\/n\//.test(nav) && nav.endsWith(`#/n/${ID}`) && Date.now() - t0 >= 1400, 'old app tab without ack: reloaded on the link after the ack timeout', nav);
}
// 3) تبويبان: المُركَّز عليه يُختار
{
  const a = tab('https://naslife.app/#/'), b = tab('https://naslife.app/', { focused: true });
  const sw = makeSw([a, b]);
  await sw.click(`/#/n/${ID}`);
  check(b.posted.length === 1 && a.posted.length === 0 && b.focusedCalls === 1, 'two app tabs: the focused one gets the message');
}
// 4) صفحة أخرى من الموقع فقط (سياسة الخصوصية): تُنقل إلى الوجهة وتُقدَّم
{
  const p = tab('https://naslife.app/privacy');
  const sw = makeSw([p]);
  await sw.click(`/#/n/${ID}`);
  check(p.posted.length === 0 && p.navigated[0] === `https://naslife.app/#/n/${ID}` && p.focusedCalls === 1 && sw.log.opened.length === 0, 'only a legal page open: navigated to the link (the app boots on it)');
}
// 4ب) لوحة الإدارة وحدها لا تُنقل (عمل جارٍ فيها): نافذة جديدة
{
  const adm = tab('https://naslife.app/admin');
  const sw = makeSw([adm]);
  await sw.click(`/#/n/${ID}`);
  check(adm.navigated.length === 0 && adm.posted.length === 0 && sw.log.opened[0] === `https://naslife.app/#/n/${ID}`, 'only the admin console open: left alone, a new window opens the link');
}
// 5) لا تبويبات (أو من موقع آخر): نافذة جديدة
{
  const x = tab('https://example.com/');
  const sw = makeSw([x]);
  await sw.click(`/#/n/${ID}`);
  check(sw.log.opened[0] === `https://naslife.app/#/n/${ID}` && x.posted.length === 0 && x.navigated.length === 0, 'no naslife tab: a new window on the link; other sites are never touched');
}
// 6) الدفع: يعرض الإشعار برابطه
{
  const sw = makeSw([]);
  let p;
  sw.handlers.push({ data: { json: () => ({ title: 'وافق على الموعد', body: 'sara وافقت', url: `/#/n/${ID}`, tag: 'meet' }) }, waitUntil: (x) => { p = x; } });
  await p;
  check(sw.log.shown.length === 1 && sw.log.shown[0].title === 'وافق على الموعد' && sw.log.shown[0].opts.data.url === `/#/n/${ID}` && sw.log.shown[0].opts.dir === 'rtl', 'push: notification shown with its link');
}
console.log(fails ? `\n${fails} FAILED` : '\nALL PUSH SW TESTS PASSED');
process.exit(fails ? 1 : 0);
