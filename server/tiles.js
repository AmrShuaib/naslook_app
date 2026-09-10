// تمرير بلاطات الخريطة عبر خادم Naslife بدل فتح tile.openstreetmap.org في سياسة الأمان.
// التسجيل في src/index.js قبل app.listen:
//   await app.register((await import("./tiles.js")).default);
// يخزّن البلاطات على القرص (TILE_CACHE_DIR، الافتراضي /opt/naslife/tilecache) لمدة 7 أيام،
// ويلتزم بسياسة استخدام OSM: هوية واضحة، خوادم فرعية متعددة، وتخزين مؤقت.
import fs from "node:fs/promises";
import path from "node:path";

const CACHE_DIR = process.env.TILE_CACHE_DIR || "/opt/naslife/tilecache";
const USER_AGENT = process.env.TILE_USER_AGENT || "Naslife/1.0 (+https://naslife.app)";
const TTL_MS = 7 * 24 * 3600 * 1000;
const MAX_ZOOM = 19;

export default async function tiles(app) {
  app.get("/tiles/:z/:x/:y", { config: { rateLimit: false } }, async (req, reply) => {
    const z = Number(req.params.z), x = Number(req.params.x);
    const y = Number(String(req.params.y).replace(/\.png$/i, ""));
    const n = 2 ** z;
    if (![z, x, y].every(Number.isInteger) || z < 0 || z > MAX_ZOOM || x < 0 || y < 0 || x >= n || y >= n) {
      return reply.code(400).send({ error: "bad-tile" });
    }
    const file = path.join(CACHE_DIR, String(z), String(x), `${y}.png`);
    reply.header("content-type", "image/png").header("cache-control", "public, max-age=86400");
    try {
      const st = await fs.stat(file);
      if (Date.now() - st.mtimeMs < TTL_MS) return fs.readFile(file);
    } catch {}
    const sub = "abc"[(x + y) % 3];
    let res;
    try {
      res = await fetch(`https://${sub}.tile.openstreetmap.org/${z}/${x}/${y}.png`, {
        headers: { "user-agent": USER_AGENT, "referer": "https://naslife.app/" },
        signal: AbortSignal.timeout(8000),
      });
    } catch {
      return reply.code(502).send({ error: "tile-upstream" });
    }
    if (!res.ok) return reply.code(502).send({ error: "tile-upstream" });
    const buf = Buffer.from(await res.arrayBuffer());
    fs.mkdir(path.dirname(file), { recursive: true }).then(() => fs.writeFile(file, buf)).catch(() => {});
    return buf;
  });
}
