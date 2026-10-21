// «النسخ الاحتياطي» (server/backups.js): نافذة لوحة الإدارة على النسخ الاحتياطي الليلي الذي يكتبه server/backup.sh (مؤقّت systemd
// على الخادم يثبّته server/install-backup.sh). الإضافة لا تنسخ شيئاً بنفسها: تقرأ ملف الحالة last.json ومجلد النسخ وتحسب ما يهم
// المدير (هل ثُبّت؟ هل آخر نسخة حديثة وناجحة؟ هل توجد نسخة خارج الخادم؟ متى آخر تمرين استعادة؟) ولا ترمي خطأً أبداً عند غياب
// الملف أو تلفه. المساران من NASLIFE_BACKUP_STATUS وNASLIFE_BACKUP_DIR (الافتراضيان كما في السكربت) ويُقرآن عند كل طلب.
// التسجيل في register.txt:
//   await app.register((await import("./backups.js")).default, { pool, auth });
import fs from "node:fs/promises";
import path from "node:path";

export const STALE_HOURS = 30, DRILL_STALE_DAYS = 10, MAX_DUMPS = 20;
export const DEFAULT_STATUS = "/opt/naslife/ops/backup/last.json", DEFAULT_DIR = "/opt/naslife/backups";

const hoursSince = (iso, now) => { const t = Date.parse(String(iso ?? "")); return Number.isFinite(t) ? Math.max(0, Math.round(((now - t) / 3600000) * 10) / 10) : null; };
const obj = (v) => (v && typeof v === "object" && !Array.isArray(v) ? v : null);

/// الحالة المحسوبة من ملف last.json ومجلد النسخ؛ تُستدعى من المسار ومن globalThis.naslifeBackupsInfo.
export async function backupsInfo({ statusPath = process.env.NASLIFE_BACKUP_STATUS || DEFAULT_STATUS, dir = process.env.NASLIFE_BACKUP_DIR || DEFAULT_DIR, now = Date.now() } = {}) {
  let installed = false, status = null, error = null;
  try {
    const raw = await fs.readFile(statusPath, "utf8"); installed = true;
    status = obj(JSON.parse(raw));
    if (!status) throw new Error("status is not an object");
  } catch (e) {
    if (e?.code !== "ENOENT") error = `status-unreadable: ${String(e?.message ?? e).slice(0, 200)}`;
  }
  const ageHours = status ? hoursSince(status.finishedAt, now) : null;
  const stale = !status || status.ok !== true || ageHours == null || ageHours > STALE_HOURS;
  const off = obj(status?.offsite);
  const offsite = !!off && off.kind != null && off.kind !== "none" && off.ok === true;
  const d = obj(status?.drill); const drillAge = d?.at ? hoursSince(d.at, now) : null;
  const drill = d?.at ? { at: d.at, ok: d.ok === true, ageDays: drillAge == null ? null : Math.round((drillAge / 24) * 10) / 10, error: d.error ?? null, tables: d.tables ?? null, rows: obj(d.rows) ?? {} } : null;
  const drillStale = !drill || drill.ageDays == null || drill.ageDays > DRILL_STALE_DAYS;
  let dumps = [];
  try {
    const dbDir = path.join(dir, "db");
    const names = (await fs.readdir(dbDir)).filter((n) => n.endsWith(".dump"));
    const list = await Promise.all(names.map(async (n) => { try { const st = await fs.stat(path.join(dbDir, n)); return { file: n, bytes: st.size, at: st.mtime.toISOString() }; } catch { return null; } }));
    dumps = list.filter(Boolean).sort((a, b) => (a.at < b.at ? 1 : a.at > b.at ? -1 : 0)).slice(0, MAX_DUMPS);
  } catch { /* المجلد غير موجود أو غير مقروء: قائمة فارغة */ }
  return { installed, status, ageHours, stale, offsite, offsiteError: off?.error ?? null, drill, drillStale, dumps, dir, statusPath, error };
}

export default async function backups(app, opts = {}) {
  const auth = typeof opts.auth === "function" ? opts.auth : async () => null;
  const isAdmin = async (uid) => { try { return !!(await globalThis.naslifeIsAdmin?.(uid)); } catch { return false; } };
  const adminOnly = async (req, reply) => { const uid = await auth(req); if (!uid) { reply.code(401).send({ error: "auth" }); return null; } if (!(await isAdmin(uid))) { reply.code(403).send({ error: "admin-only" }); return null; } return uid; };
  globalThis.naslifeBackupsInfo = () => backupsInfo();

  app.get("/adminapi/backups", async (req, reply) => {
    const uid = await adminOnly(req, reply); if (!uid) return;
    reply.header("cache-control", "no-store");
    return backupsInfo();
  });
}
