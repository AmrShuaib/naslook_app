// Numbered, forward-only schema migrations: server/db/NNNN_name.sql, applied once each inside a transaction
// and recorded in schema_migrations. The app refuses to start when a migration fails, so a half-applied
// schema can never serve traffic. Rolling back = restore the nightly backup (see ops/backup.sh); nothing here
// ever drops or rewrites existing data.
import fs from "node:fs"; import path from "node:path"; import { fileURLToPath } from "node:url";

const DB_DIR = path.join(path.dirname(fileURLToPath(import.meta.url)), "..", "db");

export function listMigrations(dir = DB_DIR) {
  return fs.readdirSync(dir).filter(f => /^\d{4}_[\w-]+\.sql$/.test(f)).sort()
    .map(f => ({ version: Number(f.slice(0, 4)), name: f, sql: fs.readFileSync(path.join(dir, f), "utf8") }));
}

export async function runMigrations(pool, { dir = DB_DIR, log = console } = {}) {
  await pool.query(`CREATE TABLE IF NOT EXISTS schema_migrations(
    version int PRIMARY KEY, name text NOT NULL, applied_at timestamptz NOT NULL DEFAULT now())`);
  const applied = new Set((await pool.query("SELECT version FROM schema_migrations")).rows.map(r => r.version));
  // A database that predates this runner already has the baseline schema: record 0001 instead of re-creating it.
  if (!applied.size) {
    const hasUsers = (await pool.query("SELECT to_regclass('public.users') AS t")).rows[0].t;
    if (hasUsers) { await pool.query("INSERT INTO schema_migrations(version,name) VALUES(1,'0001_baseline.sql (pre-existing)')"); applied.add(1); }
  }
  const pending = listMigrations(dir).filter(m => !applied.has(m.version));
  for (const m of pending) {
    const client = await pool.connect();
    try {
      await client.query("BEGIN");
      // pg_dump output carries psql meta-commands and a search_path reset; neither belongs in a migration
      await client.query(m.sql.split("\n").filter(l => !l.startsWith("\\") && !/^SELECT pg_catalog\.set_config\('search_path'/.test(l)).join("\n"));
      await client.query("SET search_path TO public");
      await client.query("INSERT INTO schema_migrations(version,name) VALUES($1,$2)", [m.version, m.name]);
      await client.query("COMMIT");
      log.info?.(`migration applied: ${m.name}`);
    } catch (e) {
      await client.query("ROLLBACK").catch(() => {});
      throw new Error(`migration ${m.name} failed: ${e.message}`);
    } finally { client.release(); }
  }
  return pending.map(m => m.name);
}

/** Run fn(client) inside BEGIN/COMMIT; any throw rolls everything back. */
export async function withTx(pool, fn) {
  const client = await pool.connect();
  try { await client.query("BEGIN"); const out = await fn(client); await client.query("COMMIT"); return out; }
  catch (e) { await client.query("ROLLBACK").catch(() => {}); throw e; }
  finally { client.release(); }
}
