// Shared test harness: fresh schema in the test database, app imported without listening, and small API helpers.
import fs from "node:fs"; import path from "node:path"; import pg from "pg";
import { fileURLToPath } from "node:url";

if (!process.env.DATABASE_URL || !/_test\b/.test(process.env.DATABASE_URL))
  throw new Error("DATABASE_URL must point at a database whose name ends with _test");
process.env.NASLIFE_NO_LISTEN = "1";
process.env.UPLOAD_DIR ??= path.join(process.cwd(), "test-uploads");
process.env.ADMIN_KEY ??= "test-admin-key";

const here = path.dirname(fileURLToPath(import.meta.url));

/** Drop everything; the app rebuilds the schema through its migrations on import. */
export async function resetDatabase() {
  const admin = new pg.Pool({ connectionString: process.env.DATABASE_URL, max: 1 });
  await admin.query("DROP SCHEMA public CASCADE; CREATE SCHEMA public;"); // importing the app applies server/db/*.sql
  await admin.end();
}

let cached;
/** Import the server once (its startup migrations run against the fresh schema). */
export async function getApp() {
  if (!cached) { await resetDatabase(); cached = await import("../src/index.js"); await cached.app.ready(); }
  return cached;
}

export const json = res => { try { return res.json(); } catch { return null; } };

let seq = 0;
/** Register a throw-away user; returns { id, nickname, token }. */
export async function register(app, nickname = `t_${Date.now().toString(36)}_${seq++}`, password = "Testpass-12345") {
  const res = await app.inject({ method: "POST", url: "/register", payload: { nickname, password, country: "SA" }, remoteAddress: "127.0.0.1",
    headers: { "x-forwarded-for": `10.9.${(seq >> 8) & 255}.${seq & 255}` } });
  if (res.statusCode !== 200) throw new Error(`register failed: ${res.statusCode} ${res.body}`);
  return { ...res.json(), password };
}

export const as = token => ({ "x-token": token });
