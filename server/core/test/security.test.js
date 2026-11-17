import { test } from "node:test"; import assert from "node:assert/strict";
import { getApp } from "./helpers.js";

test("every response carries the security headers", async () => {
  const { app } = await getApp();
  const res = await app.inject({ method: "GET", url: "/health" });
  assert.equal(res.statusCode, 200);
  const h = res.headers;
  assert.equal(h["x-content-type-options"], "nosniff");
  assert.equal(h["x-frame-options"], "DENY");
  assert.match(String(h["strict-transport-security"]), /max-age=\d+/);
  assert.match(String(h["content-security-policy"]), /default-src 'self'/);
  assert.match(String(h["content-security-policy"]), /frame-ancestors 'none'/);
  assert.match(String(h["permissions-policy"]), /geolocation=\(self\)/);
});

test("X-Forwarded-For is honoured only from the local proxy", async () => {
  const { app } = await getApp();
  const viaProxy = await app.inject({ method: "GET", url: "/__test/ip", remoteAddress: "127.0.0.1", headers: { "x-forwarded-for": "203.0.113.7" } });
  assert.equal(viaProxy.json().ip, "203.0.113.7");
  const direct = await app.inject({ method: "GET", url: "/__test/ip", remoteAddress: "198.51.100.9", headers: { "x-forwarded-for": "203.0.113.7" } });
  assert.equal(direct.json().ip, "198.51.100.9");
});

test("login attempts from one spoofed-header client are rate limited together", async () => {
  const { app } = await getApp();
  let last;
  for (let i = 0; i < 6; i++) {
    last = await app.inject({ method: "POST", url: "/login", remoteAddress: "198.51.100.77",
      headers: { "x-forwarded-for": `10.1.1.${i}` }, payload: { handle: `nobody_${i}_${Date.now()}`, password: "x" } });
  }
  assert.equal(last.statusCode, 429);
});
