// فحص سريع لمسار /l/:id بعد إصلاح دالة العرض
import Fastify from "fastify"; import pg from "pg"; import { randomUUID } from "node:crypto";
process.env.NASLIFE_WEBAPP_DIR = process.env.WEBAPP_DIR = new URL('../../build/web', import.meta.url).pathname;
const pool = new pg.Pool({ connectionString: "postgres://postgres:pg@localhost:5432/naslife_test" });
const app = Fastify(); const auth = async () => null;
await app.register((await import("../commerce.js")).default, { pool, auth });
await app.register((await import("../share.js")).default, { pool, auth });
await app.ready();
const id = randomUUID();
await pool.query("INSERT INTO market_listings(id, seller_id, kind, category, title, description, price, image_url, status) VALUES($1,'SA0000002','product','food','كيك <اختبار>','وصف',2500,'/seed/market/x.jpg','active')", [id]);
const r = await app.inject({ method: "GET", url: `/l/${id}` });
const ok = r.statusCode === 200 && r.body.includes("كيك &lt;اختبار&gt; · ") && r.body.includes('og:type" content="product"') && r.body.includes("/seed/market/x.jpg");
console.log(r.statusCode, ok ? "OK listing share page renders title, price, image" : "FAIL " + r.body.slice(0, 300));
const r2 = await app.inject({ method: "GET", url: `/l/not-a-uuid` }); console.log(r2.statusCode, r2.body.includes("عرض في سوق") ? "OK fallback page" : "FAIL " + r2.body.slice(0, 200));
await pool.query("DELETE FROM market_listings WHERE id=$1", [id]); await app.close(); await pool.end();
