import { test, before } from "node:test"; import assert from "node:assert/strict";
import { getApp, register, as } from "./helpers.js";
import { runMigrations, listMigrations, withTx } from "../src/migrate.js";

let app, pool, owner;
before(async () => { ({ app, pool } = await getApp()); owner = await register(app); });

test("every migration file is recorded once and re-running is a no-op", async () => {
  const files = listMigrations();
  const rows = (await pool.query("SELECT version, name FROM schema_migrations ORDER BY version")).rows;
  assert.deepEqual(rows.map(r => r.version), files.map(f => f.version));
  assert.deepEqual(await runMigrations(pool, { log: { info() {} } }), [], "nothing pending");
  assert.equal((await pool.query("SELECT count(*)::int AS n FROM schema_migrations")).rows[0].n, files.length);
});

test("a database that predates the runner is marked at the baseline instead of being rebuilt", async () => {
  await pool.query("DROP TABLE schema_migrations");
  const applied = await runMigrations(pool, { log: { info() {} } });
  assert.ok(!applied.some(n => n.startsWith("0001")), "0001 not re-applied on an existing schema");
  assert.equal((await pool.query("SELECT name FROM schema_migrations WHERE version=1")).rows[0].name, "0001_baseline.sql (pre-existing)");
});

test("withTx rolls everything back when a step throws", async () => {
  const nick = "tx_" + Date.now().toString(36);
  await assert.rejects(withTx(pool, async c => {
    await c.query("INSERT INTO users(id,nickname,identity_pubkey,recovery_hash) VALUES('SA1000001',$1,'','x')", [nick]);
    throw new Error("second step failed");
  }));
  assert.equal((await pool.query("SELECT 1 FROM users WHERE nickname=$1", [nick])).rowCount, 0);
});

test("creating a business writes the circle, the owner membership and the business together", async () => {
  const r = await app.inject({ method: "POST", url: "/businesses", headers: as(owner.token),
    payload: { name: "مقهى الاختبار", category: "cafe", lat: 21.5, lng: 39.2 } });
  assert.equal(r.statusCode, 200, r.body);
  const b = r.json();
  const v = await pool.query("SELECT kind, business_id FROM vessels WHERE id=$1", [b.vesselId]);
  assert.equal(v.rows[0].kind, "business"); assert.equal(v.rows[0].business_id, b.id);
  assert.equal((await pool.query("SELECT role FROM vessel_members WHERE vessel_id=$1 AND user_id=$2", [b.vesselId, owner.id])).rows[0].role, "owner");
});

test("changing district leaves the old circle and joins the new one atomically", async () => {
  await pool.query("INSERT INTO districts(id,name_ar,name_en,lat,lng) VALUES(9001,'حي أ','A',21.5,39.2),(9002,'حي ب','B',21.6,39.3) ON CONFLICT DO NOTHING");
  const a = await app.inject({ method: "PUT", url: "/me/district", headers: as(owner.token), payload: { districtId: 9001 } });
  assert.equal(a.statusCode, 200, a.body);
  const va = (await pool.query("SELECT vessel_id FROM districts WHERE id=9001")).rows[0].vessel_id;
  assert.equal((await pool.query("SELECT 1 FROM vessel_members WHERE vessel_id=$1 AND user_id=$2", [va, owner.id])).rowCount, 1);
  const b = await app.inject({ method: "PUT", url: "/me/district", headers: as(owner.token), payload: { districtId: 9002 } });
  assert.equal(b.statusCode, 200, b.body);
  const vb = (await pool.query("SELECT vessel_id FROM districts WHERE id=9002")).rows[0].vessel_id;
  assert.equal((await pool.query("SELECT 1 FROM vessel_members WHERE vessel_id=$1 AND user_id=$2", [va, owner.id])).rowCount, 0, "left the old circle");
  assert.equal((await pool.query("SELECT 1 FROM vessel_members WHERE vessel_id=$1 AND user_id=$2", [vb, owner.id])).rowCount, 1, "joined the new one");
  assert.equal((await pool.query("SELECT district_id FROM users WHERE id=$1", [owner.id])).rows[0].district_id, 9002);
});
