import { test, before, after } from "node:test"; import assert from "node:assert/strict";
import crypto from "node:crypto"; import WebSocket from "ws";
process.env.WS_AUTH_TIMEOUT_MS = "400";
import { getApp, register, as } from "./helpers.js";

let app, pool, mod, alice, bob;
const inject = (method, url, opts = {}) => app.inject({ method, url, ...opts });
const login = (handle, password) => inject("POST", "/login", { payload: { handle, password }, remoteAddress: "127.0.0.1", headers: { "x-forwarded-for": "10.7." + crypto.randomInt(255) + "." + crypto.randomInt(255) } });
const sha = t => crypto.createHash("sha256").update(t).digest("hex");
const legacyHash = p => { const salt = crypto.randomBytes(16).toString("hex"); return salt + ":" + crypto.scryptSync(p, salt, 32).toString("hex"); };

before(async () => { mod = await getApp(); ({ app, pool } = mod); [alice, bob] = await Promise.all([register(app), register(app)]); });

test("new passwords need 8+ characters; register/reset/change agree", async () => {
  const short = await inject("POST", "/register", { payload: { nickname: "shorty_" + Date.now().toString(36), password: "abc1234" }, remoteAddress: "127.0.0.1", headers: { "x-forwarded-for": "10.8.0.1" } });
  assert.equal(short.statusCode, 400); assert.equal(short.json().error, "weak-password");
  const change = await inject("PATCH", "/me", { headers: as(alice.token), payload: { currentPassword: alice.password, password: "1234567" } });
  assert.equal(change.statusCode, 400); assert.equal(change.json().error, "weak-password");
});

test("login answers the same way for an unknown handle and a wrong password", async () => {
  const unknown = await login("no_such_user_" + Date.now().toString(36), "whatever-123");
  const wrong = await login(alice.nickname, "wrong-password-1");
  assert.equal(unknown.statusCode, 401); assert.equal(wrong.statusCode, 401);
  assert.deepEqual(unknown.json(), wrong.json());
  assert.equal(unknown.json().error, "bad-credentials");
});

test("an old account with a short password still signs in and is flagged", async () => {
  const id = "SA9" + String(crypto.randomInt(100000, 999999)), nick = "legacy_" + Date.now().toString(36);
  await pool.query("INSERT INTO users(id,nickname,identity_pubkey,recovery_hash,pass_hash) VALUES($1,$2,'',$3,$4)", [id, nick, legacyHash("phrase"), legacyHash("abcd")]);
  const r = await login(nick, "abcd");
  assert.equal(r.statusCode, 200, r.body); assert.equal(r.json().weakPassword, true);
  const fresh = await login(alice.nickname, alice.password);
  assert.equal(fresh.json().weakPassword, false);
});

test("session tokens are stored hashed; legacy raw tokens are migrated in place", async () => {
  const r = await login(alice.nickname, alice.password); const token = r.json().token;
  const rows = (await pool.query("SELECT token FROM sessions WHERE user_id=$1", [alice.id])).rows.map(x => x.token);
  assert.ok(!rows.includes(token), "raw token is not in the database");
  assert.ok(rows.includes(sha(token)), "its SHA-256 is");
  // a pre-upgrade row (raw 43-char token) keeps working after the migration runs
  const raw = crypto.randomBytes(32).toString("base64url");
  await pool.query("INSERT INTO sessions(token,user_id,expires_at) VALUES($1,$2,now()+interval '1 day')", [raw, bob.id]);
  assert.equal((await inject("GET", "/me", { headers: as(raw) })).statusCode, 401, "not usable before migration");
  await mod.migrateLegacySessions();
  assert.equal((await inject("GET", "/me", { headers: as(raw) })).statusCode, 200, "usable after migration");
});

test("tokens are not accepted from the query string on HTTP routes", async () => {
  assert.equal((await inject("GET", `/me?token=${alice.token}`)).statusCode, 401);
});

test("devices: list, sign one out, sign the rest out; a password change signs other devices out", async () => {
  const loginAs = ua => inject("POST", "/login", { payload: { handle: bob.nickname, password: bob.password }, remoteAddress: "127.0.0.1", headers: { "x-forwarded-for": "10.7.9." + crypto.randomInt(255), "user-agent": ua } });
  const phone = (await loginAs("Mozilla/5.0 (Android) TestPhone")).json().token;
  const laptop = (await loginAs("Mozilla/5.0 (X11; Linux) TestLaptop")).json().token;
  const list = (await inject("GET", "/me/sessions", { headers: as(laptop) })).json();
  assert.ok(list.length >= 3, "register + phone + laptop");
  const me = list.find(x => x.current); assert.ok(me); assert.match(me.userAgent, /TestLaptop/);
  const phoneRow = list.find(x => /TestPhone/.test(x.userAgent)); assert.ok(phoneRow);
  assert.equal((await inject("DELETE", `/me/sessions/${phoneRow.id}`, { headers: as(laptop) })).statusCode, 200);
  assert.equal((await inject("GET", "/me", { headers: as(phone) })).statusCode, 401, "phone signed out");
  assert.equal((await inject("GET", "/me", { headers: as(laptop) })).statusCode, 200, "laptop still in");
  const others = await inject("DELETE", "/me/sessions", { headers: as(laptop) });
  assert.equal(others.statusCode, 200); assert.ok(others.json().revoked >= 1);
  assert.equal((await inject("GET", "/me", { headers: as(bob.token) })).statusCode, 401, "original session revoked");
  assert.equal((await inject("GET", "/me/sessions", { headers: as(laptop) })).json().length, 1);
  // password change from the laptop keeps the laptop, drops everything else
  const tablet = (await login(bob.nickname, bob.password)).json().token;
  const ch = await inject("PATCH", "/me", { headers: as(laptop), payload: { currentPassword: bob.password, password: "Brand-new-pass-9" } });
  assert.equal(ch.statusCode, 200, ch.body);
  assert.equal((await inject("GET", "/me", { headers: as(tablet) })).statusCode, 401);
  assert.equal((await inject("GET", "/me", { headers: as(laptop) })).statusCode, 200);
  bob.password = "Brand-new-pass-9";
});

test("directory lookup needs a session, hides presence, and honours blocks", async () => {
  assert.equal((await inject("GET", `/users/${alice.nickname}`)).statusCode, 401);
  const r = await inject("GET", `/users/${alice.nickname}`, { headers: as(bob.token === undefined ? alice.token : (await login(bob.nickname, bob.password)).json().token) });
  assert.equal(r.statusCode, 200, r.body);
  assert.equal(r.json().id, alice.id); assert.equal(r.json().lastSeen, undefined); assert.equal(r.json().online, undefined);
  const carol = await register(app);
  assert.equal((await inject("POST", "/blocks", { headers: as(alice.token), payload: { userId: carol.id } })).statusCode, 200);
  assert.equal((await inject("GET", `/users/${alice.nickname}`, { headers: as(carol.token) })).statusCode, 404, "blocked user cannot find the blocker");
  assert.equal((await inject("GET", `/users/${carol.nickname}`, { headers: as(alice.token) })).statusCode, 404, "and vice versa");
});

test("websocket: first-message auth works, silence is dropped, wrong token is rejected", async () => {
  await app.listen({ port: 0, host: "127.0.0.1" });
  const port = app.server.address().port, url = `ws://127.0.0.1:${port}/ws`;
  const openAndAuth = (token) => new Promise((resolve) => {
    const ws = new WebSocket(url); const events = [];
    ws.on("open", () => { if (token !== undefined) ws.send(JSON.stringify({ type: "auth", token })); });
    ws.on("message", m => events.push(JSON.parse(String(m))));
    ws.on("close", code => resolve({ code, events }));
    ws.on("error", () => {});
    setTimeout(() => { if (ws.readyState === WebSocket.OPEN) { ws.close(1000); } }, 800);
  });
  const good = await openAndAuth(alice.token);
  assert.equal(good.code, 1000); assert.deepEqual(good.events[0], { event: "ready" });
  const silent = await openAndAuth(undefined);
  assert.equal(silent.code, 4001, "no auth frame within the timeout");
  const bad = await openAndAuth("not-a-real-token");
  assert.equal(bad.code, 4001);
});

after(async () => { try { await app.close(); } catch {} });
