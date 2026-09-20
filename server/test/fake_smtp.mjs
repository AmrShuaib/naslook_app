// خادم SMTP وهمي للاختبار: EHLO، AUTH PLAIN/LOGIN، MAIL/RCPT/DATA/QUIT؛ يسجّل الرسائل الواردة.
import net from 'node:net';
const NUL = String.fromCharCode(0);
export function startFakeSmtp({ user = 'mailer', pass = 'secret', rejectRcpt = null } = {}) {
  const messages = [];
  const server = net.createServer((sock) => {
    let state = { authStep: 0, from: null, to: [], data: null, authed: false };
    const w = (s) => sock.write(s + '\r\n');
    w('220 fake.smtp ESMTP ready');
    let buf = '';
    sock.on('data', (c) => {
      buf += c.toString('utf8');
      for (;;) {
        const i = buf.indexOf('\n'); if (i < 0) break;
        const line = buf.slice(0, i).replace(/\r$/, ''); buf = buf.slice(i + 1);
        if (state.data !== null) {
          if (line === '.') { messages.push({ from: state.from, to: state.to, raw: state.data.join('\n'), authed: state.authed }); state.data = null; w('250 2.0.0 OK id=msg' + messages.length); }
          else state.data.push(line.startsWith('..') ? line.slice(1) : line);
          continue;
        }
        if (state.authStep === 1) { state.authUser = Buffer.from(line, 'base64').toString(); state.authStep = 2; w('334 UGFzc3dvcmQ6'); continue; }
        if (state.authStep === 2) { state.authStep = 0; const p = Buffer.from(line, 'base64').toString(); if (state.authUser === user && p === pass) { state.authed = true; w('235 2.7.0 ok'); } else w('535 5.7.8 bad credentials'); continue; }
        const [cmd, ...rest] = line.split(' '); const arg = rest.join(' ');
        switch (cmd.toUpperCase()) {
          case 'EHLO': w('250-fake.smtp greets you'); w('250-SIZE 10485760'); w('250-8BITMIME'); w('250 AUTH PLAIN LOGIN'); break;
          case 'AUTH': {
            if (/^PLAIN/i.test(arg)) { const parts = Buffer.from(arg.split(' ')[1] ?? '', 'base64').toString().split(NUL); if (parts[1] === user && parts[2] === pass) { state.authed = true; w('235 2.7.0 ok'); } else w('535 5.7.8 bad credentials'); }
            else if (/^LOGIN/i.test(arg)) { state.authStep = 1; w('334 VXNlcm5hbWU6'); }
            else w('504 unknown auth'); break;
          }
          case 'MAIL': state.from = (arg.match(/<([^>]*)>/) || [])[1] ?? arg; w('250 2.1.0 ok'); break;
          case 'RCPT': { const r = (arg.match(/<([^>]*)>/) || [])[1] ?? arg; if (rejectRcpt && r === rejectRcpt) w('550 5.1.1 no such user'); else { state.to.push(r); w('250 2.1.5 ok'); } break; }
          case 'DATA': state.data = []; w('354 end with .'); break;
          case 'QUIT': w('221 bye'); sock.end(); break;
          case 'NOOP': w('250 ok'); break;
          default: w('500 unknown command');
        }
      }
    });
    sock.on('error', () => {});
  });
  return new Promise((resolve) => server.listen(0, '127.0.0.1', () => resolve({ port: server.address().port, messages, close: () => new Promise((r) => server.close(r)) })));
}
/// يفك نص الرسالة (الجزء text/plain المرمّز base64) من الرسالة الخام.
export function plainTextOf(raw) {
  const m = raw.match(/Content-Type: text\/plain[\s\S]*?\r?\n\r?\n([\s\S]*?)\r?\n--/);
  if (!m) return '';
  return Buffer.from(m[1].replace(/\s+/g, ''), 'base64').toString('utf8');
}
