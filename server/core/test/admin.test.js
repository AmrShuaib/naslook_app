import { test, before } from "node:test"; import assert from "node:assert/strict";
import { getApp, register, as } from "./helpers.js";

let app, pool, admin, user, target;
const inject = (method, url, opts = {}) => app.inject({ method, url, ...opts });

before(async () => {
  ({ app, pool } = await getApp());
  [admin, user, target] = await Promise.all([register(app), register(app), register(app)]);
  await pool.query("UPDATE users SET is_admin=true WHERE id=$1", [admin.id]);
});

test("admin routes need an admin account (or, for now, the static key)", async () => {
  assert.equal((await inject("GET", "/admin/reports")).statusCode, 401, "anonymous");
  assert.equal((await inject("GET", "/admin/reports", { headers: as(user.token) })).statusCode, 401, "ordinary user");
  assert.equal((await inject("GET", "/admin/reports", { headers: { "x-admin-key": "wrong" } })).statusCode, 401, "wrong key");
  assert.equal((await inject("GET", "/admin/reports", { headers: as(admin.token) })).statusCode, 200, "admin user");
  assert.equal((await inject("GET", "/admin/reports", { headers: { "x-admin-key": process.env.ADMIN_KEY } })).statusCode, 200, "static key still honoured");
});

test("every admin action lands in the audit log with actor, target, before/after", async () => {
  const rep = await inject("POST", "/reports", { headers: as(user.token), payload: { userId: target.id, reason: "abuse", details: "spam" } });
  assert.equal(rep.statusCode, 200, rep.body);
  const id = (await pool.query("SELECT id FROM reports WHERE reporter_id=$1", [user.id])).rows[0].id;
  const ch = await inject("PATCH", `/admin/reports/${id}`, { headers: as(admin.token), payload: { status: "actioned", reason: "confirmed spam" } });
  assert.equal(ch.statusCode, 200, ch.body);
  const rows = (await inject("GET", "/admin/audit", { headers: as(admin.token) })).json();
  const row = rows.find(r => r.target_id === id);
  assert.ok(row, "audit row exists");
  assert.equal(row.actor, "user:" + admin.id); assert.equal(row.admin_id, admin.id);
  assert.equal(row.action, "report.status"); assert.equal(row.reason, "confirmed spam");
  assert.deepEqual(row.before, { status: "new" }); assert.deepEqual(row.after, { status: "actioned" });
  assert.equal((await inject("GET", "/admin/audit", { headers: as(user.token) })).statusCode, 401);
});

test("the audit log cannot be edited or trimmed through the application role", async () => {
  await assert.rejects(pool.query("UPDATE audit_log SET reason='changed'"), /append-only/);
  await assert.rejects(pool.query("DELETE FROM audit_log"), /append-only/);
});

test("business verification is audited too", async () => {
  const b = (await inject("POST", "/businesses", { headers: as(user.token), payload: { name: "متجر", category: "shop", lat: 21.5, lng: 39.2 } })).json();
  const ok = await inject("PATCH", `/admin/businesses/${b.id}`, { headers: { "x-admin-key": process.env.ADMIN_KEY }, payload: { status: "approved" } });
  assert.equal(ok.statusCode, 200, ok.body);
  const row = (await pool.query("SELECT * FROM audit_log WHERE target_id=$1", [b.id])).rows[0];
  assert.equal(row.actor, "admin-key"); assert.equal(row.admin_id, null);
  assert.deepEqual(row.after, { status: "approved", verified: true });
});

test("health reports database readiness and every response carries a request id", async () => {
  const h = await inject("GET", "/health");
  assert.equal(h.json().db, true); assert.ok(h.headers["x-request-id"]);
});
