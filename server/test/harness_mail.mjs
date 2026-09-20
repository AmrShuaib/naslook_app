// خدمة البريد (server/mail.js): الإعدادات من لوحة الإدارة، إرسال SMTP إلى خادم وهمي محلي (AUTH PLAIN/LOGIN، dot-stuffing،
// ترويسات عربية مرمّزة)، مزوّدو HTTP عبر fetch وهمي، السجل، الحراسة، وحالة التفعيل العامة.
import Fastify from 'fastify';
import pg from 'pg';
import { startFakeSmtp, plainTextOf } from './fake_smtp.mjs';
process.env.NASLIFE_HEALTH_BRIDGE = '0';
const MASK = '••••••••';
const pool = new pg.Pool({ host: '127.0.0.1', user: 'postgres', password: 'pg', database: 'naslife_test' });
await pool.query("CREATE TABLE IF NOT EXISTS admin_audit (id UUID PRIMARY KEY, admin_id TEXT NOT NULL, action TEXT NOT NULL, target TEXT, details JSONB NOT NULL DEFAULT '{}', created_at TIMESTAMPTZ NOT NULL DEFAULT now())");
await pool.query('DROP TABLE IF EXISTS mail_settings; DROP TABLE IF EXISTS mail_log');
globalThis.naslifeIsAdmin = async (uid) => uid === 'SA0000001';
const auth = async (req) => req.headers['x-user'] || null;
const smtp = await startFakeSmtp({ user: 'mailer', pass: 'secret', rejectRcpt: 'nobody@bounce.test' });
const app = Fastify();
const mailMod = await import('../mail.js');
app.register(mailMod.default, { pool, auth });
await app.ready();
let fails = 0;
const check = (c, l, extra = '') => { if (!c) fails++; console.log((c ? 'OK  ' : 'FAIL') + ' ' + l + (extra ? ' ' + extra : '')); };
const call = async (method, url, { body, user } = {}) => { const r = await app.inject({ method, url, headers: { 'content-type': 'application/json', ...(user ? { 'x-user': user } : {}) }, payload: body ? JSON.stringify(body) : undefined }); let j; try { j = r.json(); } catch { j = r.body; } return { code: r.statusCode, json: j }; };
const A = { user: 'SA0000001' };

let r = await call('GET', '/mail/status');
check(r.code === 200 && r.json.configured === false && r.json.provider === 'off', 'status: off by default', JSON.stringify(r.json));
check(globalThis.naslifeMail && globalThis.naslifeMail.configured() === false, 'global naslifeMail exposed, not configured');
r = await call('GET', '/adminapi/mail');
check(r.code === 401, 'settings need auth');
r = await call('GET', '/adminapi/mail', { user: 'SA0000002' });
check(r.code === 403 && r.json.error === 'admin-only', 'settings are admin-only');
r = await call('GET', '/adminapi/mail', A);
check(r.code === 200 && r.json.provider === 'off' && r.json.hasPass === false && r.json.fromName === 'ناس لايف', 'defaults', JSON.stringify(r.json));
r = await call('PUT', '/adminapi/mail', { ...A, body: { provider: 'gmail' } });
check(r.code === 400 && r.json.error === 'bad-provider', 'bad provider rejected');
r = await call('PUT', '/adminapi/mail', { ...A, body: { port: 99999 } });
check(r.code === 400 && r.json.error === 'bad-port', 'bad port rejected');
r = await call('PUT', '/adminapi/mail', { ...A, body: { from: 'not-an-email' } });
check(r.code === 400 && r.json.error === 'bad-from', 'bad from rejected');
r = await call('POST', '/adminapi/mail/test', { ...A, body: { to: 'a@b.co' } });
check(r.code === 400 && r.json.error === 'not-configured', 'test send refused while off');
r = await call('PUT', '/adminapi/mail', { ...A, body: { provider: 'smtp', host: '127.0.0.1', port: smtp.port, secure: false, user: 'mailer', pass: 'secret', from: 'no-reply@naslife.app', fromName: 'ناس لايف', replyTo: 'support@naslife.app' } });
check(r.code === 200 && r.json.configured === true && r.json.pass === MASK && r.json.hasPass === true && r.json.port === smtp.port, 'smtp settings saved, password masked', JSON.stringify(r.json));
r = await call('GET', '/mail/status');
check(r.json.configured === true && r.json.provider === 'smtp', 'public status reflects configuration');
r = await call('PUT', '/adminapi/mail', { ...A, body: { pass: MASK, fromName: 'Naslife' } });
check(r.code === 200 && r.json.hasPass === true && r.json.fromName === 'Naslife', 'masked password keeps the stored secret');
const row = (await pool.query('SELECT data FROM mail_settings WHERE id=1')).rows[0].data;
check(row.pass === 'secret' && row.fromName === 'Naslife', 'stored secret intact in DB');
r = await call('POST', '/adminapi/mail/test', { ...A, body: { to: 'Founder@Example.com' } });
check(r.code === 200 && r.json.ok === true, 'test send over SMTP (AUTH PLAIN)', JSON.stringify(r.json));
check(smtp.messages.length === 1 && smtp.messages[0].authed && smtp.messages[0].from === 'no-reply@naslife.app' && smtp.messages[0].to[0] === 'founder@example.com', 'fake SMTP received the authenticated message', JSON.stringify(smtp.messages[0]?.to));
const raw = smtp.messages[0]?.raw ?? '';
check(/^Subject: =\?UTF-8\?B\?/m.test(raw) && /^From: [^\n]*<no-reply@naslife\.app>/m.test(raw) && /^Reply-To: support@naslife\.app/m.test(raw) && /^Message-ID: <[0-9a-f-]+@naslife\.app>/m.test(raw), 'headers: encoded subject, from, reply-to, message-id');
check(plainTextOf(raw).includes('رسالة تجريبية من ناس لايف'), 'body text decoded', plainTextOf(raw).slice(0, 40));
const text = mailMod.template({ title: 'نقطة', lines: ['.سطر يبدأ بنقطة', 'بعده سطر'] });
r = await (async () => { try { return { ok: true, res: await globalThis.naslifeMail.send({ to: 'dot@example.com', subject: 'dots', ...text, tag: 'dots' }) }; } catch (e) { return { ok: false, err: e.message }; } })();
check(r.ok && smtp.messages.length === 2, 'message with dot-leading line delivered intact', JSON.stringify(r));
check(plainTextOf(smtp.messages[1]?.raw ?? '').includes('.سطر يبدأ بنقطة'), 'leading dot preserved after unstuffing');
r = await call('POST', '/adminapi/mail/test', { ...A, body: { to: 'nobody@bounce.test' } });
check(r.code === 502 && r.json.error === 'send-failed' && /RCPT/.test(r.json.detail), 'rejected recipient surfaces the SMTP error', JSON.stringify(r.json));
r = await call('POST', '/adminapi/mail/test', { ...A, body: { to: 'bad' } });
check(r.code === 400 && r.json.error === 'bad-recipient', 'bad recipient rejected');
await call('PUT', '/adminapi/mail', { ...A, body: { pass: 'wrong' } });
r = await call('POST', '/adminapi/mail/test', { ...A, body: { to: 'x@example.com' } });
check(r.code === 502 && /535|credentials/i.test(r.json.detail), 'wrong password: auth error reported', JSON.stringify(r.json));
await call('PUT', '/adminapi/mail', { ...A, body: { pass: 'secret' } });
r = await call('GET', '/adminapi/mail/log', A);
check(r.code === 200 && r.json.log.length === 4 && r.json.sent30d === 2 && r.json.failed30d === 2 && r.json.log[0].status === 'failed' && r.json.log.some((l) => l.tag === 'dots'), 'log lists sent and failed attempts', JSON.stringify({ n: r.json.log.length, s: r.json.sent30d, f: r.json.failed30d }));
const calls = [];
globalThis.fetch = async (url, init) => { calls.push({ url, headers: init.headers, body: JSON.parse(init.body) }); return { ok: true, status: 200, text: async () => JSON.stringify({ id: 'msg-http-1' }), headers: { get: () => null } }; };
r = await call('PUT', '/adminapi/mail', { ...A, body: { provider: 'resend', apiKey: 're_123', from: 'hello@naslife.app', fromName: 'ناس لايف' } });
check(r.code === 200 && r.json.configured === true && r.json.apiKey === MASK && r.json.hasApiKey === true, 'resend settings saved, key masked');
r = await call('POST', '/adminapi/mail/test', { ...A, body: { to: 'r@example.com' } });
check(r.code === 200 && r.json.id === 'msg-http-1' && calls[0].url === 'https://api.resend.com/emails' && calls[0].headers.authorization === 'Bearer re_123' && calls[0].body.to[0] === 'r@example.com' && calls[0].body.from.includes('hello@naslife.app'), 'resend request shape', JSON.stringify(calls[0]?.body?.from));
await call('PUT', '/adminapi/mail', { ...A, body: { provider: 'brevo', apiKey: 'xkeysib-1' } });
r = await call('POST', '/adminapi/mail/test', { ...A, body: { to: 'b@example.com' } });
check(r.code === 200 && calls[1].url === 'https://api.brevo.com/v3/smtp/email' && calls[1].headers['api-key'] === 'xkeysib-1' && calls[1].body.to[0].email === 'b@example.com' && calls[1].body.sender.email === 'hello@naslife.app', 'brevo request shape');
await call('PUT', '/adminapi/mail', { ...A, body: { provider: 'sendgrid', apiKey: 'SG.1' } });
r = await call('POST', '/adminapi/mail/test', { ...A, body: { to: 's@example.com' } });
check(r.code === 200 && calls[2].url === 'https://api.sendgrid.com/v3/mail/send' && calls[2].headers.authorization === 'Bearer SG.1' && calls[2].body.personalizations[0].to[0].email === 's@example.com' && calls[2].body.content.length === 2, 'sendgrid request shape');
globalThis.fetch = async () => ({ ok: false, status: 401, text: async () => '{"errors":[{"message":"bad key"}]}', headers: { get: () => null } });
r = await call('POST', '/adminapi/mail/test', { ...A, body: { to: 's@example.com' } });
check(r.code === 502 && /401/.test(r.json.detail) && /bad key/.test(r.json.detail), 'http provider error surfaced', JSON.stringify(r.json));
r = await call('PUT', '/adminapi/mail', { ...A, body: { provider: 'off' } });
check(r.code === 200 && r.json.configured === false && (await call('GET', '/mail/status')).json.configured === false, 'switching off');
const audit = (await pool.query("SELECT action, details FROM admin_audit WHERE target='mail' ORDER BY created_at DESC")).rows;
check(audit.some((a) => a.action === 'mail.settings') && audit.some((a) => a.action === 'mail.test' && a.details.ok === true) && !JSON.stringify(audit).includes('secret'), 'audit records settings and tests without secrets');
// ---- بريد النطاق الرسمي (admin@naslife.app): مزوّد وهمي Resend/Brevo + DNS وهمي عبر DoH
const dns = {}; const dom = { resend: null, brevo: null }; let verifyCalls = 0;
globalThis.fetch = async (url, init = {}) => {
  const u = String(url); const m = init.method ?? 'GET';
  const res = (code, body) => ({ ok: code < 300, status: code, text: async () => JSON.stringify(body), headers: { get: () => null } });
  if (u.startsWith('https://cloudflare-dns.com/')) { const q = new URL(u); return res(200, { Answer: (dns[q.searchParams.get('name') + ':' + q.searchParams.get('type')] ?? []).map((d) => ({ data: d })) }); }
  if (u === 'https://api.resend.com/domains' && m === 'POST') {
    if (init.headers.authorization !== 'Bearer re_key') return res(401, { message: 'invalid key' });
    if (dom.resend) return res(403, { message: 'already exists' });
    dom.resend = { id: 'dom_1', name: JSON.parse(init.body).name, status: 'not_started', records: [
      { record: 'SPF', name: 'send', type: 'MX', ttl: 'Auto', status: 'not_started', value: 'feedback-smtp.eu-west-1.amazonses.com', priority: 10 },
      { record: 'SPF', name: 'send', type: 'TXT', ttl: 'Auto', status: 'not_started', value: 'v=spf1 include:amazonses.com ~all' },
      { record: 'DKIM', name: 'resend._domainkey', type: 'TXT', ttl: 'Auto', status: 'not_started', value: 'p=MIGfMA0' }] };
    return res(201, dom.resend);
  }
  if (u === 'https://api.resend.com/domains' && m === 'GET') return res(200, { data: dom.resend ? [{ id: dom.resend.id, name: dom.resend.name }] : [] });
  if (u === 'https://api.resend.com/domains/dom_1/verify') { verifyCalls++; const ok = !!dns['resend._domainkey.naslife.app:TXT']; dom.resend.status = ok ? 'verified' : 'pending'; for (const r of dom.resend.records) r.status = ok ? 'verified' : 'pending'; return res(200, { object: 'domain', id: 'dom_1' }); }
  if (u === 'https://api.resend.com/domains/dom_1') return res(200, dom.resend);
  if (u === 'https://api.brevo.com/v3/senders/domains' && m === 'POST') {
    if (init.headers['api-key'] !== 'xkeysib-1') return res(401, { message: 'Key not found' });
    dom.brevo = { id: 77, domain_name: JSON.parse(init.body).name, authenticated: false, verified: false, dns_records: {
      dkim_record: { type: 'TXT', value: 'k=rsa;p=MIGf', host_name: 'mail._domainkey.naslife.app', status: false },
      brevo_code: { type: 'TXT', value: 'brevo-code:abc123', host_name: 'naslife.app', status: false },
      dmarc_record: { type: 'TXT', value: 'v=DMARC1; p=none; rua=mailto:rua@dmarc.brevo.com', host_name: '_dmarc.naslife.app', status: false } } };
    return res(201, { id: 77, domain_name: dom.brevo.domain_name, message: 'Domain added', dns_records: dom.brevo.dns_records });
  }
  if (u === 'https://api.brevo.com/v3/senders/domains/naslife.app/authenticate') { const ok = !!dns['mail._domainkey.naslife.app:TXT']; dom.brevo.authenticated = ok; dom.brevo.verified = ok; for (const r of Object.values(dom.brevo.dns_records)) r.status = ok; return ok ? res(200, { domain_name: 'naslife.app', message: 'authenticated' }) : res(400, { message: 'not yet' }); }
  if (u === 'https://api.brevo.com/v3/senders/domains/naslife.app') return res(200, { domain_name: 'naslife.app', id: 77, authenticated: dom.brevo.authenticated, verified: dom.brevo.verified, dns_records: dom.brevo.dns_records });
  return res(404, { message: 'no route ' + m + ' ' + u });
};
r = await call('GET', '/adminapi/mail/domain');
check(r.code === 401, 'domain needs auth');
r = await call('GET', '/adminapi/mail/domain', A);
check(r.code === 200 && r.json.domain === null && r.json.suggested.name === 'naslife.app' && r.json.suggested.local === 'admin' && r.json.providerReady === false, 'no domain yet, suggestion + provider not ready', JSON.stringify(r.json));
r = await call('POST', '/adminapi/mail/domain', { ...A, body: { domain: 'naslife.app' } });
check(r.code === 400 && r.json.error === 'provider-required', 'needs Resend/Brevo key first');
await call('PUT', '/adminapi/mail', { ...A, body: { provider: 'resend', apiKey: 'wrong', from: 'jeddahh@gmail.com' } });
r = await call('POST', '/adminapi/mail/domain', { ...A, body: { domain: 'naslife.app' } });
check(r.code === 403 && r.json.error === 'key-invalid' && /401/.test(r.json.detail), 'bad key → key-invalid', JSON.stringify(r.json));
globalThis.fetch = (function (orig) { return async (url, init = {}) => (String(url) === 'https://api.resend.com/domains' && (init.method ?? 'GET') === 'POST' && init.headers.authorization === 'Bearer re_sendonly') ? { ok: false, status: 401, text: async () => JSON.stringify({ statusCode: 401, message: 'This API key is restricted to only send emails', name: 'restricted_api_key' }), headers: { get: () => null } } : orig(url, init); })(globalThis.fetch);
await call('PUT', '/adminapi/mail', { ...A, body: { apiKey: 're_sendonly' } });
r = await call('POST', '/adminapi/mail/domain', { ...A, body: { domain: 'naslife.app' } });
check(r.code === 403 && r.json.error === 'key-restricted', 'send-only Resend key → key-restricted', JSON.stringify(r.json));
await call('PUT', '/adminapi/mail', { ...A, body: { apiKey: 're_key' } });
r = await call('POST', '/adminapi/mail/domain', { ...A, body: { domain: 'not a domain' } });
check(r.code === 400 && r.json.error === 'bad-domain', 'bad domain rejected');
r = await call('POST', '/adminapi/mail/domain', { ...A, body: { domain: 'www.NasLife.app', local: 'bad local!' } });
check(r.code === 400 && r.json.error === 'bad-local', 'bad local part rejected');
r = await call('POST', '/adminapi/mail/domain', { ...A, body: { domain: 'www.NasLife.app', local: 'admin' } });
let d = r.json.domain;
check(r.code === 200 && d.name === 'naslife.app' && d.sender === 'admin@naslife.app' && d.id === 'dom_1' && d.status === 'pending' && d.verified === false, 'resend domain created', JSON.stringify(r.json).slice(0, 200));
check(d.records.length === 4 && d.records.map((x) => x.host).join(',') === 'send,send,resend._domainkey,_dmarc' && d.records[0].type === 'MX' && d.records[0].priority === 10 && d.records[0].fqdn === 'send.naslife.app', 'records normalized + DMARC suggested', JSON.stringify(d.records.map((x) => [x.type, x.host, x.priority])));
check(d.records.every((x) => x.dnsOk === false) && d.records[3].optional === true && /rua=mailto:admin@naslife.app/.test(d.records[3].value), 'DNS not present yet; DMARC points to admin@', JSON.stringify(d.records[3]));
r = await call('GET', '/adminapi/mail', A);
check(r.json.from === 'jeddahh@gmail.com' && r.json.domain.name === 'naslife.app', 'from untouched while pending; domain persisted in settings');
// السجلات تُنشر تدريجياً
dns['send.naslife.app:MX'] = ['10 feedback-smtp.eu-west-1.amazonses.com.'];
dns['send.naslife.app:TXT'] = ['"v=spf1 include:amazonses.com ~all"'];
r = await call('POST', '/adminapi/mail/domain/verify', { ...A, body: {} });
d = r.json.domain;
check(r.code === 200 && d.status === 'pending' && d.records[0].dnsOk === true && d.records[1].dnsOk === true && d.records[2].dnsOk === false && verifyCalls === 1, 'partial DNS: still pending, per-record DNS state', JSON.stringify(d.records.map((x) => x.dnsOk)));
dns['resend._domainkey.naslife.app:TXT'] = ['"p=MIGf" "MA0"'];
dns['_dmarc.naslife.app:TXT'] = ['"v=DMARC1; p=quarantine; rua=mailto:admin@naslife.app"'];
r = await call('POST', '/adminapi/mail/domain/verify', { ...A, body: {} });
d = r.json.domain;
check(r.code === 200 && d.status === 'verified' && d.verified === true && d.verifiedAt && d.fromApplied === true && r.json.from === 'admin@naslife.app', 'verified → sender switched to admin@naslife.app', JSON.stringify({ s: d.status, from: r.json.from }));
check((await call('GET', '/adminapi/mail', A)).json.from === 'admin@naslife.app' && (await call('GET', '/mail/status')).json.configured === true, 'settings saved with new from; mail configured');
r = await call('GET', '/adminapi/mail/domain', A);
check(r.json.domain.status === 'verified' && r.json.domain.records[2].dnsOk === true && r.json.domain.checkedAt, 'GET refreshes from provider + DNS');
// بعد التوثيق: «تحقق الآن» لا يستدعي verify عند المزوّد، والحالة تبقى موثّقة حتى لو أعاد المزوّد «قيد الفحص» مؤقتاً
const vc = verifyCalls; dom.resend.status = 'pending';
r = await call('POST', '/adminapi/mail/domain/verify', { ...A, body: {} });
check(r.code === 200 && verifyCalls === vc && r.json.domain.status === 'verified', 'verified domain: recheck is read-only and sticky', JSON.stringify({ calls: verifyCalls - vc, s: r.json.domain.status }));
dom.resend.status = 'failed';
r = await call('POST', '/adminapi/mail/domain/verify', { ...A, body: {} });
check(r.json.domain.status === 'failed', 'provider failure still surfaces');
dom.resend.status = 'verified';
// سجل جديد معلّق (MX الاستقبال) بعد التوثيق: إعادة الفحص تطلب verify من المزوّد وتبقى الحالة موثّقة
dom.resend.records.push({ record: 'MX', name: '@', type: 'MX', ttl: 'Auto', status: 'pending', value: 'inbound-smtp.eu-west-1.amazonses.com', priority: 10 });
r = await call('GET', '/adminapi/mail/domain', A);
check(r.json.domain.records.some((x) => x.host === '@' && x.status === 'pending') && r.json.domain.status === 'verified', 'pending receiving record listed, domain stays verified');
const vc2 = verifyCalls; dns['naslife.app:MX'] = ['10 inbound-smtp.eu-west-1.amazonses.com.'];
r = await call('POST', '/adminapi/mail/domain/verify', { ...A, body: {} });
check(verifyCalls === vc2 + 1 && r.json.domain.status === 'verified' && r.json.domain.records.find((x) => x.host === '@').status === 'verified', 'recheck re-verifies at the provider when a record is pending', JSON.stringify(r.json.domain.records.map((x) => [x.host, x.status])));
dom.resend.records.pop();
// إعادة الربط بعد الحذف: النطاق موجود مسبقاً عند المزوّد → يُلتقط من القائمة
r = await call('DELETE', '/adminapi/mail/domain', A);
check(r.code === 200 && (await call('GET', '/adminapi/mail/domain', A)).json.domain === null, 'domain removed locally');
r = await call('POST', '/adminapi/mail/domain', { ...A, body: { domain: 'naslife.app', local: 'no-reply' } });
check(r.code === 200 && r.json.domain.id === 'dom_1' && r.json.domain.status === 'verified' && r.json.domain.sender === 'no-reply@naslife.app', 'existing provider domain reattached', JSON.stringify(r.json.domain).slice(0, 160));
check((await call('GET', '/adminapi/mail', A)).json.from === 'admin@naslife.app', 'from already on the domain is kept');
// Brevo
await call('DELETE', '/adminapi/mail/domain', A);
await call('PUT', '/adminapi/mail', { ...A, body: { provider: 'brevo', apiKey: 'xkeysib-1', from: 'jeddahh@gmail.com' } });
r = await call('POST', '/adminapi/mail/domain', { ...A, body: { domain: 'naslife.app', local: 'admin' } });
d = r.json.domain;
check(r.code === 200 && d.provider === 'brevo' && d.id === 77 && d.status === 'pending' && d.records.length === 3 && d.records.map((x) => x.host).join(',') === 'mail._domainkey,@,_dmarc' && d.records[1].fqdn === 'naslife.app', 'brevo records normalized (relative hosts, no duplicate DMARC)', JSON.stringify(d.records.map((x) => [x.type, x.host, x.source])));
r = await call('POST', '/adminapi/mail/domain/verify', { ...A, body: {} });
check(r.code === 200 && r.json.domain.status === 'pending' && r.json.domain.error == null, 'brevo not authenticated yet is not an error');
dns['mail._domainkey.naslife.app:TXT'] = ['"k=rsa;p=MIGf"']; dns['naslife.app:TXT'] = ['"brevo-code:abc123"']; dns['_dmarc.naslife.app:TXT'] = ['"v=DMARC1; p=none; rua=mailto:rua@dmarc.brevo.com"'];
r = await call('POST', '/adminapi/mail/domain/verify', { ...A, body: {} });
check(r.code === 200 && r.json.domain.status === 'verified' && r.json.from === 'admin@naslife.app', 'brevo authenticated → sender switched', JSON.stringify({ s: r.json.domain.status, from: r.json.from }));
const dAudit = (await pool.query("SELECT action, details FROM admin_audit WHERE target='mail' AND action LIKE 'mail.domain%' ORDER BY created_at")).rows;
check(dAudit.some((a) => a.action === 'mail.domain' && a.details.ok === true) && dAudit.some((a) => a.action === 'mail.domain.verify') && dAudit.some((a) => a.action === 'mail.domain.remove') && !JSON.stringify(dAudit).includes('re_key'), 'domain actions audited without secrets');
console.log(fails ? `\n${fails} FAILED` : '\nALL MAIL TESTS PASSED');
await app.close(); await smtp.close(); await pool.end(); process.exit(fails ? 1 : 0);
