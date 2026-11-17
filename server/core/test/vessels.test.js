import { test, before } from "node:test"; import assert from "node:assert/strict";
import { getApp, register, as } from "./helpers.js";

let app, pool, owner, member, stranger, banned, pub, priv, privPost, pubPost;

const create = async (user, isPublic) => {
  const r = await app.inject({ method: "POST", url: "/vessels", headers: as(user.token),
    payload: { name: isPublic ? "وعاء عام" : "وعاء خاص", topic: "اختبار", description: "", isPublic } });
  assert.equal(r.statusCode, 200, r.body);
  return r.json();
};
const post = async (user, vid) => {
  const r = await app.inject({ method: "POST", url: `/vessels/${vid}/posts`, headers: as(user.token), payload: { type: "text", content: "مرحبا" } });
  assert.equal(r.statusCode, 200, r.body);
  return r.json();
};
const get = (user, url) => app.inject({ method: "GET", url, headers: as(user.token) });
const send = (user, method, url, payload) => app.inject({ method, url, headers: as(user.token), payload });

before(async () => {
  ({ app, pool } = await getApp());
  [owner, member, stranger, banned] = await Promise.all([register(app), register(app), register(app), register(app)]);
  pub = await create(owner, true);
  priv = await create(owner, false);
  // there is no invite flow yet: seed the private membership directly
  await pool.query("INSERT INTO vessel_members(vessel_id,user_id) VALUES($1,$2),($1,$3)", [priv.id, member.id, banned.id]);
  privPost = await post(owner, priv.id);
  pubPost = await post(owner, pub.id);
});

test("public vessel: anyone signed in can read, only members can write", async () => {
  for (const url of [`/vessels/${pub.id}`, `/vessels/${pub.id}/posts`, `/vessels/${pub.id}/members`, `/posts/${pubPost.id}`, `/posts/${pubPost.id}/comments`])
    assert.equal((await get(stranger, url)).statusCode, 200, url);
  assert.equal((await send(stranger, "POST", `/posts/${pubPost.id}/comments`, { text: "x" })).statusCode, 403);
  assert.equal((await send(stranger, "POST", `/posts/${pubPost.id}/support`)).statusCode, 403);
  assert.equal((await send(stranger, "POST", `/vessels/${pub.id}/join`)).statusCode, 200);
  assert.equal((await send(stranger, "POST", `/posts/${pubPost.id}/comments`, { text: "x" })).statusCode, 200);
});

test("private vessel: owner and member can read and write", async () => {
  for (const u of [owner, member]) {
    for (const url of [`/vessels/${priv.id}`, `/vessels/${priv.id}/posts`, `/vessels/${priv.id}/members`, `/posts/${privPost.id}`, `/posts/${privPost.id}/comments`])
      assert.equal((await get(u, url)).statusCode, 200, `${u.nickname} ${url}`);
    assert.equal((await send(u, "POST", `/posts/${privPost.id}/comments`, { text: "تعليق" })).statusCode, 200);
    assert.equal((await send(u, "POST", `/posts/${privPost.id}/support`)).statusCode, 200);
  }
});

test("private vessel: a non-member gets 403 everywhere, even with the UUIDs", async () => {
  for (const url of [`/vessels/${priv.id}`, `/vessels/${priv.id}/posts`, `/vessels/${priv.id}/members`, `/posts/${privPost.id}`, `/posts/${privPost.id}/comments`]) {
    const r = await get(stranger, url);
    assert.equal(r.statusCode, 403, url); assert.equal(r.json().error, "private");
  }
  assert.equal((await send(stranger, "POST", `/posts/${privPost.id}/comments`, { text: "x" })).statusCode, 403);
  assert.equal((await send(stranger, "POST", `/posts/${privPost.id}/support`)).statusCode, 403);
  assert.equal((await send(stranger, "POST", `/vessels/${priv.id}/posts`, { type: "text", content: "x" })).statusCode, 403);
  assert.equal((await send(stranger, "POST", `/vessels/${priv.id}/join`)).statusCode, 403);
  // private posts never leak through the member-only feed either
  const feed = await get(stranger, "/vessels/feed");
  assert.ok(!feed.json().some(p => p.vesselId === priv.id));
});

test("owner can remove and ban a member; a banned user loses access and cannot rejoin", async () => {
  assert.equal((await send(member, "DELETE", `/vessels/${priv.id}/members/${banned.id}`)).statusCode, 403, "only owner/moderator");
  assert.equal((await send(owner, "DELETE", `/vessels/${priv.id}/members/${owner.id}`)).statusCode, 400, "owner stays");
  assert.equal((await send(owner, "DELETE", `/vessels/${priv.id}/members/${banned.id}?ban=1`)).statusCode, 200);
  for (const url of [`/vessels/${priv.id}`, `/vessels/${priv.id}/posts`, `/posts/${privPost.id}`, `/posts/${privPost.id}/comments`]) {
    const r = await get(banned, url); assert.equal(r.statusCode, 403, url); assert.equal(r.json().error, "banned");
  }
  assert.equal((await send(banned, "POST", `/vessels/${priv.id}/join`)).statusCode, 403);
  // a ban on a public circle also blocks reading and rejoining
  await send(banned, "POST", `/vessels/${pub.id}/join`);
  assert.equal((await send(owner, "DELETE", `/vessels/${pub.id}/members/${banned.id}?ban=1`)).statusCode, 200);
  assert.equal((await get(banned, `/vessels/${pub.id}/posts`)).json().error, "banned");
  assert.equal((await send(banned, "POST", `/vessels/${pub.id}/join`)).json().error, "banned");
  // the public circle keeps working for everyone else
  assert.equal((await get(stranger, `/vessels/${pub.id}/posts`)).statusCode, 200);
});

test("unknown or malformed ids", async () => {
  assert.equal((await get(owner, "/vessels/00000000-0000-4000-8000-000000000000")).statusCode, 404);
  assert.equal((await get(owner, "/posts/00000000-0000-4000-8000-000000000000")).statusCode, 404);
  assert.equal((await get(owner, "/vessels/not-a-uuid/members")).statusCode, 400);
});
