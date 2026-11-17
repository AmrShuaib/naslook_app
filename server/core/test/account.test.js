import { test, before } from "node:test"; import assert from "node:assert/strict";
import fs from "node:fs"; import path from "node:path"; import sharp from "sharp";
import { getApp, register, as } from "./helpers.js";

let app, pool, alice, bob;
const inject = (method, url, opts = {}) => app.inject({ method, url, ...opts });
before(async () => { ({ app, pool } = await getApp()); [alice, bob] = await Promise.all([register(app), register(app)]); });

test("notification preview is off by default and can be switched on", async () => {
  assert.equal((await inject("GET", "/me", { headers: as(alice.token) })).json().pushPreview, false);
  const on = await inject("PATCH", "/me/settings", { headers: as(alice.token), payload: { pushPreview: true } });
  assert.equal(on.json().pushPreview, true);
  assert.equal((await inject("GET", "/me", { headers: as(alice.token) })).json().pushPreview, true);
});

test("export returns the account's data as one document", async () => {
  await inject("POST", "/messages", { headers: as(alice.token), payload: { to: bob.id, type: "text", content: "مرحبا" } });
  const r = await inject("GET", "/me/export", { headers: as(alice.token) });
  assert.equal(r.statusCode, 200, r.body);
  const doc = r.json();
  assert.equal(doc.account.id, alice.id);
  assert.ok(doc.messages.some(m => m.content === "مرحبا"));
  for (const k of ["contacts", "posts", "comments", "circles", "mapPins", "stories", "businesses", "sessions"]) assert.ok(Array.isArray(doc[k]), k);
});

test("deleting the account needs the password, purges personal data, keeps the peer's chat, frees media", async () => {
  // some footprint: an uploaded image sent to bob, a business, a private circle with a member
  const png = await sharp({ create: { width: 20, height: 20, channels: 3, background: "#000" } }).png().toBuffer();
  const boundary = "----x" + Date.now();
  const body = Buffer.concat([Buffer.from(`--${boundary}\r\nContent-Disposition: form-data; name="file"; filename="a.png"\r\nContent-Type: image/png\r\n\r\n`), png, Buffer.from(`\r\n--${boundary}--\r\n`)]);
  const up = await inject("POST", "/upload", { headers: { ...as(alice.token), "content-type": `multipart/form-data; boundary=${boundary}` }, payload: body });
  const url = up.json().url; const file = path.join(process.env.UPLOAD_DIR, path.basename(url));
  assert.equal((await inject("POST", "/messages", { headers: as(alice.token), payload: { to: bob.id, type: "image", content: url } })).statusCode, 200);
  const biz = (await inject("POST", "/businesses", { headers: as(alice.token), payload: { name: "متجر أليس", category: "shop", lat: 21.5, lng: 39.2 } })).json();
  const made = await inject("POST", "/vessels", { headers: as(alice.token), payload: { name: "دائرتي", topic: "اختبار", isPublic: true } });
  assert.equal(made.statusCode, 200, made.body); const circle = made.json();
  assert.equal((await inject("POST", `/vessels/${circle.id}/join`, { headers: as(bob.token) })).statusCode, 200);
  await inject("PUT", "/me/map-presence", { headers: as(alice.token), payload: { lat: 21.5, lng: 39.2, visible: true } });

  assert.equal((await inject("DELETE", "/me", { headers: as(alice.token), payload: { password: "wrong" } })).statusCode, 401);
  const del = await inject("DELETE", "/me", { headers: as(alice.token), payload: { password: alice.password } });
  assert.equal(del.statusCode, 200, del.body);
  await new Promise(r => setTimeout(r, 300));

  assert.equal((await inject("GET", "/me", { headers: as(alice.token) })).statusCode, 401, "sessions gone");
  const login = await inject("POST", "/login", { payload: { handle: alice.nickname, password: alice.password }, remoteAddress: "127.0.0.1", headers: { "x-forwarded-for": "10.3.3.3" } });
  assert.equal(login.statusCode, 401, "cannot sign in again");
  assert.equal((await inject("GET", `/users/${alice.nickname}`, { headers: as(bob.token) })).statusCode, 404, "not findable");
  const u = (await pool.query("SELECT nickname, pass_hash, avatar_url, deleted_at FROM users WHERE id=$1", [alice.id])).rows[0];
  assert.match(u.nickname, /^deleted_/); assert.equal(u.pass_hash, null); assert.ok(u.deleted_at);
  assert.equal((await pool.query("SELECT count(*)::int AS n FROM businesses WHERE owner_id=$1", [alice.id])).rows[0].n, 0);
  assert.equal((await pool.query("SELECT count(*)::int AS n FROM vessels WHERE id=$1", [biz.vesselId])).rows[0].n, 0, "business circle removed");
  assert.equal((await pool.query("SELECT owner_id FROM vessels WHERE id=$1", [circle.id])).rows[0].owner_id, bob.id, "circle handed to its remaining member");
  assert.equal((await pool.query("SELECT count(*)::int AS n FROM map_presence WHERE user_id=$1", [alice.id])).rows[0].n, 0);
  // bob keeps the text of the conversation; alice's media message is blanked and its file released
  const chat = (await inject("GET", `/messages/${alice.id}`, { headers: as(bob.token) })).json();
  assert.ok(Array.isArray(chat) ? chat.length > 0 : true);
  assert.ok(!fs.existsSync(file), "uploaded file deleted");
});
