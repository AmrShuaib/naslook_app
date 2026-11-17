# Naslife

تطبيق اجتماعي سعودي بلا رقم جوال: محادثات فردية، دوائر محتوى («الأوعية»)، دوائر الأحياء والأعمال التجارية، وخريطة بتواجد اختياري.
واجهة Flutter Web (عربية، RTL) وخادم Node/Fastify واحد مع PostgreSQL. الإنتاج: <https://naslife.app>.

## البنية

```
lib/                      Flutter client
  main.dart               auth, chats, thread, "أنا", sessions/privacy screens
  screens/                map, vessels (circles), profile, business
  api/client.dart         REST + WebSocket client (X-Token header; ws auth by first frame)
  state/app_state.dart    Provider state, socket, unread counters
  theme/app_colors.dart   Naslife DS 1.0 (light default + dark)
  platform/               web-only helpers (native <audio>, downloads)
web/flutter_bootstrap.js  loads CanvasKit from /canvaskit/ (no CDN, CSP-friendly)
server/
  src/index.js            the whole API (routes, WebSocket, media pipeline, push)
  src/migrate.js          numbered migrations runner + withTx()
  db/NNNN_*.sql           schema: 0001 baseline, 0002 startup additions, 0003 admin/audit, 0004 privacy
  test/*.test.js          node:test suite (app.inject against a *_test database)
  ops/                    systemd unit, installer, deploy, backup, health-check, cron files, restore notes
tools/                    workstation scripts: deploy-web.sh, deploy-server.sh, test-remote.sh
```

Runtime layout on the VPS: `/opt/naslife/{src,db,node_modules,webapp,uploads,backups,ops,.env}`. Caddy terminates TLS on 443 and
proxies to Node on `127.0.0.1:4000`; the service runs as the unprivileged `naslife` user (`ops/naslife.service`).

## المتطلبات

- Node 22 (CI) / 20+ (VPS), PostgreSQL 14+, `ffmpeg` + `ffprobe`, `gpg` (backups)
- Flutter 3.35 (Dart 3.9) for the client
- The server only listens on loopback; put a TLS reverse proxy in front (Caddy config: `reverse_proxy 127.0.0.1:4000`)

## متغيرات البيئة (`/opt/naslife/.env`)

| Variable | Required | Meaning |
|---|---|---|
| `DATABASE_URL` | yes | `postgres://naslife:<password>@localhost/naslife` |
| `PORT`, `HOST` | no | default `4000`, `127.0.0.1` (set `HOST=0.0.0.0` only behind your own firewall) |
| `TRUSTED_PROXIES` | no | comma list of proxy IPs allowed to set `X-Forwarded-For` (default loopback) |
| `VAPID_PUBLIC`, `VAPID_PRIVATE`, `VAPID_SUBJECT` | for push | generated once by `ops/deploy-server.sh` |
| `ADMIN_KEY` | transitional | static admin header; remove it once an account has `is_admin` (`ops/grant-admin.sh`) |
| `UPLOAD_DIR`, `WEBAPP_DIR` | no | default `/opt/naslife/uploads`, `/opt/naslife/webapp` |
| `MAX_IMAGE_PIXELS`, `MAX_MEDIA_SECONDS` | no | media guards (40 MP, 600 s) |
| `SCAN_COMMAND` | no | e.g. `clamdscan --no-summary` — non-zero exit rejects an upload |
| `WS_LEGACY_QUERY_TOKEN` | no | `0` to refuse `?token=` on `/ws` (the current client uses first-frame auth) |
| `LOG_LEVEL` | no | pino level, default `info` |

Never commit `.env`; it is gitignored and backed up only inside the encrypted `secrets-*.tar.gz.gpg`.

## التطوير المحلي

```bash
cd server && npm ci
DATABASE_URL=postgres://naslife:naslife@localhost/naslife_dev NASLIFE_NO_LISTEN=0 node src/index.js   # migrations run on start
flutter pub get && flutter run -d chrome --dart-define=BUILD_ID=dev
```

`lib/api/client.dart` reads the API base URL (`apiUrl`); point it at `http://localhost:4000` for local work.

## قاعدة البيانات والترحيلات

`server/src/migrate.js` applies `server/db/NNNN_name.sql` once each, inside a transaction, recording them in `schema_migrations`.
The server exits if a migration fails. A database that predates the runner is marked at `0001` instead of being rebuilt.
Add a change: create `server/db/0005_short_name.sql` (idempotent SQL, no destructive statements), deploy. Rollback = restore a backup.
Multi-step writes use `withTx(pool, async c => …)`.

## الاختبارات

```bash
cd server && DATABASE_URL=postgres://…/naslife_test npm test        # needs a database whose name ends with _test
tools/test-remote.sh naslife                                       # same suite on the VPS (no local Postgres here)
flutter analyze && flutter test
```

The suite covers security headers and proxy trust, vessel access rules and bans, map privacy, upload hardening, auth/sessions/WebSocket,
migrations/transactions, admin/audit and account deletion. `.github/workflows/ci.yml` runs it on every push and PR with a Postgres service,
plus `npm audit`, `flutter analyze/test` and a gitleaks secret scan.

## النشر

```bash
# server (guarded): tarball -> staging -> node --check -> npm ci if lockfile changed -> atomic swap -> restart -> health gate -> rollback on failure
tools/deploy-server.sh naslife
# web: flutter build web --release --pwa-strategy=none --dart-define=BUILD_ID=$(date +%Y%m%d-%H%M); write build/web/build.json; then
tools/deploy-web.sh naslife        # md5-diffed, chunked, checksum-verified upload (plain scp drops from some networks)
```

Clients poll `build.json` and reload on a new id; there is no service worker (`--pwa-strategy=none`). `/health` returns `db:true|false`.

## النسخ الاحتياطي والاستعادة

`ops/backup.sh` (cron 03:00 UTC) writes AES-256 encrypted dumps of the database, uploads, source and secrets to `/opt/naslife/backups`
(14-day retention, sha256 checksums). Passphrase: `/root/.naslife-backup-pass` — copy it off the server. `backup.sh --verify` (cron Sundays)
restores the newest dump into a scratch database and checks row counts. `ops/pull-backups.ps1` pulls everything to a workstation as the
off-site copy. Restore steps: `server/ops/restore.md`.

## الوسائط

Uploads stream to `uploads/.incoming`, are identified by magic bytes (never by filename), then re-encoded: images → JPEG ≤1600 px
(animated GIF → GIF ≤800 px), audio → AAC m4a, video → H.264 mp4 ≤90 s + thumbnail. Anything that fails is rejected (415) and deleted;
the raw upload is never published. `releaseMedia()` deletes a file once no row references it.

## الإدارة

Grant admin: `bash /opt/naslife/ops/grant-admin.sh SA1234567`. Admin routes (`/admin/reports`, `/admin/businesses`, `/admin/audit`,
`/admin/districts/import`) accept an admin session (`X-Token`) or, temporarily, `X-Admin-Key`. Every action is written to the append-only
`audit_log` (trigger blocks UPDATE/DELETE).

## إضافة مسار أو ميزة

1. Route in `server/src/index.js`: `auth(req)` first; for circle content use `requireVessel`/`requirePost`; validate every field; body-less
   POST/DELETE must not send `Content-Type: application/json` from the client (`_t(token)` header map).
2. Schema change → new `server/db/NNNN_*.sql`. Multi-step write → `withTx`.
3. Test in `server/test/<area>.test.js` using `getApp()`, `register()`, `app.inject`.
4. Client: `lib/api/client.dart` function + screen; colours only through `AppColors.of(context)`.
5. `tools/test-remote.sh`, `tools/deploy-server.sh`, build + `tools/deploy-web.sh`, one commit per change.

## الاستجابة للحوادث

- Service down: `journalctl -u naslife -n 100`; `ops/healthcheck.sh` restarts it every 5 min if `/health` fails (`/var/log/naslife-health.log`).
- Bad deploy: `ops/deploy-server.sh` rolls back automatically; manual: copy `/opt/naslife/releases/prev-*/src` back and restart.
- Compromised token/session: user → «الأجهزة والجلسات»; admin: `DELETE FROM sessions WHERE user_id=…` (tokens are stored hashed).
- Leaked `.env`: rotate `DATABASE_URL` password, regenerate VAPID keys (`deploy-server.sh` does it when absent), remove `ADMIN_KEY`.
- Data restore: `server/ops/restore.md`; verify with `backup.sh --verify` first.
- Abuse: `/admin/reports`, `/admin/audit`; ban from a circle via `DELETE /vessels/:id/members/:userId?ban=1`.
