// يجلب لكل عرض صورة مطابقة من Openverse (صور بترخيص مفتوح) ويحفظها 640×480 في web/seed/market/<slug>.jpg
// مع ملف credits.json يحمل نسب كل صورة. يحترم حدّ 20 طلباً بالدقيقة.
import { execFileSync } from "node:child_process";
import fs from "node:fs";
const { LISTINGS } = await import("/home/user/naslook_app/server/market_seed_data.js");
const OUT = "/home/user/naslook_app/web/seed/market";
const UA = "naslife-seed/1.0 (jeddahh@gmail.com)";
// وسائط: slug أو slug=استعلام مخصص (يعيد جلب هذا العرض بالاستعلام المعطى)
const overrides = new Map(process.argv.slice(2).filter((a) => a.includes("=")).map((a) => a.split(/=(.*)/s).slice(0, 2)));
const only = new Set(process.argv.slice(2).map((a) => a.split("=")[0]));
const creditsPath = OUT + "/credits.json";
const credits = fs.existsSync(creditsPath) ? JSON.parse(fs.readFileSync(creditsPath, "utf8")) : {};
const sleep = (ms) => new Promise((r) => setTimeout(r, ms));
const curl = (args, timeout = 60000) => execFileSync("curl", ["-sS", "-L", "-m", "50", "-H", "User-Agent: " + UA, ...args], { timeout, maxBuffer: 64 << 20 });
const usedIds = new Set(Object.values(credits).map((c) => c.id));
let ok = 0, fail = 0;
await sleep(5000);
for (const l of LISTINGS) {
  if (only.size && !only.has(l.slug)) continue;
  const dest = `${OUT}/${l.slug}.jpg`;
  if (!only.size && credits[l.slug] && fs.existsSync(dest)) { ok++; continue; }
  if (only.size) { const prev = credits[l.slug]?.id; if (prev) usedIds.delete(prev); }
  const q = overrides.get(l.slug) ?? l.photo.replace(/,/g, " ");
  let results = [];
  try {
    const j = JSON.parse(curl([`https://api.openverse.org/v1/images/?q=${encodeURIComponent(q)}&page_size=20&mature=false&license=cc0,pdm,by,by-sa`]).toString("utf8"));
    results = j.results ?? [];
  } catch (e) { console.log("API-FAIL", l.slug, String(e).slice(0, 80)); fail++; await sleep(3500); continue; }
  // الأفضلية: غير مستخدمة، عرض ≥ 600، أفقية، ثم الملك العام قبل غيره
  const score = (r) => (usedIds.has(r.id) ? -100 : 0) + ((r.width ?? 0) >= 600 ? 10 : 0) + ((r.width ?? 0) >= (r.height ?? 1) ? 5 : 0) + (/^(cc0|pdm)$/.test(r.license) ? 2 : 0) + (/flickr|wikimedia/.test(r.provider ?? "") ? 1 : 0);
  results.sort((a, b) => score(b) - score(a));
  let got = null;
  for (const r of results.slice(0, 6)) {
    for (const url of [r.url, r.thumbnail]) {
      if (!url) continue;
      try {
        curl(["-o", "/tmp/mkt/ov_raw", url]);
        const st = fs.statSync("/tmp/mkt/ov_raw"); if (st.size < 8000) continue;
        execFileSync("ffmpeg", ["-nostdin", "-loglevel", "error", "-y", "-i", "/tmp/mkt/ov_raw", "-vf", "scale=640:480:force_original_aspect_ratio=increase,crop=640:480", "-q:v", "5", dest], { timeout: 60000 });
        got = { id: r.id, title: r.title, creator: r.creator, license: r.license, licenseUrl: r.license_url, source: r.foreign_landing_url, provider: r.provider, url };
        break;
      } catch { /* جرّب الرابط التالي */ }
    }
    if (got) break;
  }
  if (got) { usedIds.add(got.id); credits[l.slug] = got; fs.writeFileSync(creditsPath, JSON.stringify(credits, null, 1)); ok++; console.log("OK", l.slug, "|", (got.title ?? "").slice(0, 50), "|", got.license, got.provider); }
  else { fail++; console.log("FAIL", l.slug, "(" + q + ")", "results", results.length); }
  await sleep(3300);
}
console.log(`DONE ok=${ok} fail=${fail}`);
