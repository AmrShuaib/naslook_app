import { test, before } from "node:test"; import assert from "node:assert/strict";
import fs from "node:fs"; import path from "node:path"; import sharp from "sharp";
process.env.MAX_IMAGE_PIXELS = "1000000"; // 1 MP for the test process, so the pixel guard is cheap to exercise
import { getApp, register, as } from "./helpers.js";

let app, alice, bob;
const UPLOAD_DIR = process.env.UPLOAD_DIR;
const listFiles = () => fs.readdirSync(UPLOAD_DIR).filter(f => !f.startsWith("."));
const incoming = () => fs.readdirSync(path.join(UPLOAD_DIR, ".incoming"));

/** Build a multipart/form-data body by hand for app.inject. */
function multipart(filename, bytes, mime = "application/octet-stream") {
  const boundary = "----naslife" + Date.now();
  const head = Buffer.from(`--${boundary}\r\nContent-Disposition: form-data; name="file"; filename="${filename}"\r\nContent-Type: ${mime}\r\n\r\n`);
  const tail = Buffer.from(`\r\n--${boundary}--\r\n`);
  return { payload: Buffer.concat([head, bytes, tail]), headers: { "content-type": `multipart/form-data; boundary=${boundary}` } };
}
const upload = (user, filename, bytes, mime, url = "/upload") => {
  const m = multipart(filename, bytes, mime);
  return app.inject({ method: "POST", url, headers: { ...as(user.token), ...m.headers }, payload: m.payload });
};
/** 0.5 s of silence as a 16-bit mono WAV. */
function wav() {
  const rate = 8000, n = rate / 2, data = Buffer.alloc(n * 2), h = Buffer.alloc(44);
  h.write("RIFF", 0); h.writeUInt32LE(36 + data.length, 4); h.write("WAVE", 8); h.write("fmt ", 12); h.writeUInt32LE(16, 16);
  h.writeUInt16LE(1, 20); h.writeUInt16LE(1, 22); h.writeUInt32LE(rate, 24); h.writeUInt32LE(rate * 2, 28); h.writeUInt16LE(2, 32);
  h.writeUInt16LE(16, 34); h.write("data", 36); h.writeUInt32LE(data.length, 40);
  return Buffer.concat([h, data]);
}
const png = (w, h) => sharp({ create: { width: w, height: h, channels: 3, background: "#1f55f0" } }).png().toBuffer();

before(async () => { ({ app } = await getApp()); [alice, bob] = await Promise.all([register(app), register(app)]); });

test("a real image is re-encoded to jpg and served", async () => {
  const r = await upload(alice, "photo.png", await png(300, 200), "image/png");
  assert.equal(r.statusCode, 200, r.body);
  const { url, kind } = r.json(); assert.equal(kind, "image"); assert.match(url, /^\/files\/[0-9a-f-]{36}\.jpg$/);
  const served = await app.inject({ method: "GET", url });
  assert.equal(served.statusCode, 200); assert.equal(served.rawPayload[0], 0xFF, "served bytes are a JPEG, not the original PNG");
  assert.equal(incoming().length, 0, "no temp files left behind");
});

test("the filename and declared type are ignored: bytes decide", async () => {
  const before = listFiles().length;
  const html = Buffer.from("<html><script>alert(1)</script></html>");
  const r = await upload(alice, "innocent.jpg", html, "image/jpeg");
  assert.equal(r.statusCode, 415); assert.equal(r.json().error, "unsupported-media");
  assert.equal(listFiles().length, before, "nothing was published");
  assert.equal(incoming().length, 0);
  // a PNG header followed by garbage is not published either
  const fake = Buffer.concat([Buffer.from("89504e470d0a1a0a", "hex"), Buffer.alloc(500, 7)]);
  assert.equal((await upload(alice, "x.png", fake, "image/png")).statusCode, 415);
  assert.equal(listFiles().length, before);
});

test("oversized images are rejected before decoding", async () => {
  const before = listFiles().length;
  const r = await upload(alice, "huge.png", await png(1500, 1500), "image/png"); // 2.25 MP > 1 MP test limit
  assert.equal(r.statusCode, 413); assert.equal(r.json().error, "too-large");
  assert.equal(listFiles().length, before);
});

test("animated GIF is re-encoded rather than passed through", async () => {
  const frames = await Promise.all([0, 1, 2].map(i => sharp({ create: { width: 40, height: 40, channels: 3, background: i ? "#00a870" : "#e5484d" } }).raw().toBuffer()));
  const gif = await sharp(Buffer.concat(frames), { raw: { width: 40, height: 120, channels: 3 } }).gif({ effort: 1 }).toBuffer();
  // sharp writes a single-page gif from raw pixels; append a comment extension block to make sure bytes are not copied verbatim
  const r = await upload(alice, "anim.gif", gif, "image/gif");
  assert.equal(r.statusCode, 200, r.body);
  assert.match(r.json().url, /\.(gif|jpg)$/);
  const served = await app.inject({ method: "GET", url: r.json().url });
  assert.equal(served.statusCode, 200);
  assert.notDeepEqual(served.rawPayload, gif, "output is a fresh encode");
});

test("audio is transcoded to m4a; the scan hook can veto a file", async () => {
  const ok = await upload(alice, "note.wav", wav(), "audio/wav");
  assert.equal(ok.statusCode, 200, ok.body); assert.equal(ok.json().kind, "audio"); assert.match(ok.json().url, /\.m4a$/);
  process.env.SCAN_COMMAND = "/bin/false";
  try {
    const vetoed = await upload(alice, "note.wav", wav(), "audio/wav");
    assert.equal(vetoed.statusCode, 415); assert.equal(vetoed.json().error, "rejected-by-scan");
  } finally { delete process.env.SCAN_COMMAND; }
  assert.equal(incoming().length, 0);
});

test("avatar accepts images only and drops the previous picture", async () => {
  assert.equal((await upload(alice, "v.wav", wav(), "audio/wav", "/me/avatar")).statusCode, 400);
  const first = (await upload(alice, "a.png", await png(64, 64), "image/png", "/me/avatar")).json().avatarUrl;
  const second = (await upload(alice, "b.png", await png(64, 64), "image/png", "/me/avatar")).json().avatarUrl;
  await new Promise(r => setTimeout(r, 200));
  assert.ok(!fs.existsSync(path.join(UPLOAD_DIR, path.basename(first))), "old avatar file removed");
  assert.ok(fs.existsSync(path.join(UPLOAD_DIR, path.basename(second))));
});

test("deleting a message removes its file unless something else still uses it", async () => {
  const url = (await upload(alice, "p.png", await png(80, 80), "image/png")).json().url;
  const send = () => app.inject({ method: "POST", url: "/messages", headers: as(alice.token), payload: { to: bob.id, type: "image", content: url } });
  const m1 = await send(); assert.equal(m1.statusCode, 200, m1.body);
  const m2 = await send(); assert.equal(m2.statusCode, 200, m2.body);
  const file = path.join(UPLOAD_DIR, path.basename(url));
  assert.equal((await app.inject({ method: "DELETE", url: `/messages/${m1.json().id}`, headers: as(alice.token) })).statusCode, 200);
  await new Promise(r => setTimeout(r, 200));
  assert.ok(fs.existsSync(file), "still referenced by the second message");
  assert.equal((await app.inject({ method: "DELETE", url: `/messages/${m2.json().id}`, headers: as(alice.token) })).statusCode, 200);
  await new Promise(r => setTimeout(r, 200));
  assert.ok(!fs.existsSync(file), "gone once the last reference is deleted");
});
