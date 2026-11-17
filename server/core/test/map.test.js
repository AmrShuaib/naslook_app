import { test, before } from "node:test"; import assert from "node:assert/strict";
import { getApp, register, as } from "./helpers.js";

let app, pool, alice, bob, carol;
const get = (u, url) => app.inject({ method: "GET", url, headers: as(u.token) });
const send = (u, method, url, payload) => app.inject({ method, url, headers: as(u.token), payload });
const JEDDAH = "39.0,21.3,39.4,21.8"; // west,south,east,north
const RIYADH = "46.5,24.5,46.9,24.9";

before(async () => {
  ({ app, pool } = await getApp());
  [alice, bob, carol] = await Promise.all([register(app), register(app), register(app)]);
});

test("stories are only returned inside the requested map view", async () => {
  const posted = await send(alice, "POST", "/stories", { type: "text", content: "مرحبا جدة", lat: 21.543219, lng: 39.198765 });
  assert.equal(posted.statusCode, 200, posted.body);
  assert.equal((await get(bob, "/stories")).statusCode, 400, "no bbox, no list");
  assert.equal((await get(bob, `/stories?bbox=${RIYADH}`)).json().length, 0, "other city sees nothing");
  const inView = (await get(bob, `/stories?bbox=${JEDDAH}`)).json();
  assert.equal(inView.length, 1);
  assert.equal(inView[0].lat, 21.543, "others get ~100 m precision"); assert.equal(inView[0].lng, 39.199);
  const mine = (await get(alice, `/stories?bbox=${JEDDAH}`)).json();
  assert.equal(mine[0].lat, 21.543219, "the author sees the exact spot");
});

test("stories never cross a block in either direction", async () => {
  assert.equal((await send(carol, "POST", "/blocks", { userId: alice.id })).statusCode, 200);
  assert.equal((await get(carol, `/stories?bbox=${JEDDAH}`)).json().length, 0, "blocker does not see the blocked user's story");
  const posted = await send(carol, "POST", "/stories", { type: "text", content: "x", lat: 21.5, lng: 39.2 });
  assert.equal(posted.statusCode, 200);
  assert.ok(!(await get(alice, `/stories?bbox=${JEDDAH}`)).json().some(s => s.userId === carol.id), "blocked user does not see the blocker's story");
});

test("announced pin: optional auto-hide, expiry honoured, bad values rejected", async () => {
  assert.equal((await send(alice, "PUT", "/me/map-presence", { lat: 21.5, lng: 39.2, visible: true, hideAfterHours: 5 })).statusCode, 400);
  const on = await send(alice, "PUT", "/me/map-presence", { lat: 21.5, lng: 39.2, visible: true, hideAfterHours: 1 });
  assert.equal(on.statusCode, 200, on.body);
  assert.equal(on.json().visible, true); assert.equal(on.json().hideAfterHours, 1); assert.ok(on.json().expiresAt);
  assert.ok((await get(bob, `/map/presence?bbox=${JEDDAH}`)).json().some(p => p.id === alice.id), "listed while valid");
  await pool.query("UPDATE map_presence SET expires_at = now() - interval '1 minute' WHERE user_id=$1", [alice.id]);
  assert.ok(!(await get(bob, `/map/presence?bbox=${JEDDAH}`)).json().some(p => p.id === alice.id), "hidden once expired");
  assert.equal((await get(alice, "/me/map-presence")).json().visible, false, "owner sees it as off");
  const forever = await send(alice, "PUT", "/me/map-presence", { visible: true, hideAfterHours: 0 });
  assert.equal(forever.json().visible, true); assert.equal(forever.json().expiresAt, null, "0/null keeps the pin until switched off");
});

test("logging out hides the announced pin immediately", async () => {
  await send(bob, "PUT", "/me/map-presence", { lat: 21.6, lng: 39.1, visible: true });
  assert.ok((await get(alice, `/map/presence?bbox=${JEDDAH}`)).json().some(p => p.id === bob.id));
  assert.equal((await send(bob, "POST", "/logout")).statusCode, 200);
  assert.ok(!(await get(alice, `/map/presence?bbox=${JEDDAH}`)).json().some(p => p.id === bob.id), "gone after logout");
  const again = await app.inject({ method: "POST", url: "/login", payload: { handle: bob.nickname, password: bob.password } });
  assert.equal(again.statusCode, 200, again.body);
  assert.equal((await get({ token: again.json().token }, "/me/map-presence")).json().visible, false, "stays off after signing back in");
});
