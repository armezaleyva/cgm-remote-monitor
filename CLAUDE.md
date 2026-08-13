# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this is

Nightscout (`cgm-remote-monitor`) — a real-time CGM (continuous glucose monitor) dashboard. Node.js + Express 4 + MongoDB + Socket.IO, with a Webpack-bundled D3/jQuery frontend.

This is health-critical software: people use it to make insulin decisions, and a large ecosystem of uploaders (AAPS, Loop, xDrip, bridges) and viewers depends on its API shapes. Prefer small, backward-compatible changes over rewrites. Do not change API v1/v2/v3 request or response shapes without an explicit decision to do so.

## Setup and commands

Requires Node >= 20 and npm >= 10 per `package.json` `engines`, plus a reachable MongoDB. Note that `.nvmrc` is stale — it pins 16.16.0, which the engines field rejects. Node 22 matches both the `Dockerfile` base image and the CI matrix.

```bash
npm install                       # also runs the webpack production build via postinstall
cp docs/example-template.env my.env   # then edit MONGO_CONNECTION, API_SECRET; keep NODE_ENV=development
npm run dev                       # nodemon + webpack dev middleware + HMR on PORT (default 1337)
npm run lint                      # eslint, lib/ only — does not cover tests/, bundle/, webpack/
npm run bundle                    # production bundle;  npm run bundle-dev  for the dev build
```

Tests need `my.test.env`, which is gitignored. Generate it with `make my.test.env` (writes Makefile defaults: local mongo `test_db`, `API_SECRET=test-secret-key`).

```bash
npm test                          # everything
npm run test:unit                 # fast, no DB-heavy suites, runs parallel with 2 jobs
npm run test:integration          # api/api3/websocket/storage/reports suites
npm run test:flaky                # repeat-runs suites to surface flakiness (scripts/flaky-test-runner.js)
```

Single suite — the script reads a `TEST` env var naming a file in `tests/` without the `.test.js` suffix:

```powershell
$env:TEST='iob'; npm run test-single      # PowerShell
```
```bash
TEST=iob npm run test-single              # bash
```

**Test safety preflight.** `tests/hooks.js` runs `tests/lib/production-safety.js` before any suite. It refuses to run if the database name lacks `test` or if the entries collection exceeds ~100 documents, so tests cannot be pointed at a live instance. Override knobs (`TEST_SAFETY_*`) exist but exist for emergencies — if the preflight trips, fix the connection string rather than bypassing it.

CI (`.github/workflows/main.yml`) runs the matrix Node 20/22/24 × MongoDB 4.4/5.0/6.0, so avoid syntax and driver features outside that range.

## Architecture

### Boot: `ctx` is assembled once, then passed everywhere

`lib/server/server.js` → `lib/server/bootevent.js` → `lib/server/app.js`.

`bootevent.js` is the single most useful file for orienting yourself. It runs an ordered `bootevent` chain — `startBoot`, `checkNodeVersion`, `checkEnv`, `augmentSettings`, `checkSettings`, `setupStorage`, `setupAuthorization`, `setupInternals`, `ensureIndexes`, `setupListeners`, `setupConnect`, `setupBridge`, `setupMMConnect`, `finishBoot` — each step hanging another subsystem off a shared `ctx` object (`ctx.store`, `ctx.plugins`, `ctx.entries`, `ctx.treatments`, `ctx.ddata`, `ctx.notifications`, …).

Two consequences worth knowing:

- `ctx` is effectively a global service locator. Nearly every server module is a factory taking `(env, ctx)`. New server subsystems get wired in `setupInternals`.
- Failures accumulate in `ctx.bootErrors` instead of throwing. Most steps early-return when `hasBootErrors(ctx)` is true, and the server boots into an error page rather than crashing. A subsystem that silently never initializes is usually an earlier boot error, not a bug in that subsystem.

### The data cycle

`lib/bus.js` is a plain Node `Stream` used as a pub/sub bus, emitting `tick` on a heartbeat interval. `setupListeners` in `bootevent.js` wires the cycle:

```
tick / data-received  →  (debounced) dataloader.update(ctx.ddata)  →  data-loaded
data-loaded  →  build a fresh sandbox  →  plugins.setProperties(sbx)
             →  notifications.initRequests / plugins.checkNotifications / notifications.process
             →  data-processed  (ctx.runtimeState = 'loaded')
```

The dataloader call is debounced leading-edge (1s, `maxWait` 5s) with a concurrency guard, so a burst of uploads from one client coalesces into one reload instead of stacking overlapping runs over shared `ddata`. Anything that reacts to new data should hang off these bus events rather than polling.

### Plugins and the sandbox

`lib/plugins/index.js` holds two explicit registration lists: `clientDefaultPlugins` and `serverDefaultPlugins`. A new plugin file in `lib/plugins/` does nothing until it is added to the right list — server-side for anything producing alarms or notifications, client-side for anything rendering a pill.

Plugins never receive `ctx`. They receive a **sandbox** (`sbx`) built by `lib/sandbox.js`, which has `serverInit(env, ctx)` and `clientInit(...)` variants so the same plugin code runs in both places. The sandbox exposes only a narrowed surface — data, settings, `sbx.properties`, and `_.pick`ed notification methods. Per-plugin config arrives via `withExtendedSettings`, which slices `extendedSettings` by plugin name (the `EXTENDED_SETTINGS` env convention). Plugins publish results by setting `sbx.properties`, which is how they pass values to each other and to the renderer.

### API layers

- `lib/api/` — v1. `API_SECRET` (SHA1) auth. The compatibility surface every uploader depends on.
- `lib/api2/` — v2. Adds JWT, roles, and `properties`.
- `lib/api3/` — v3. OpenAPI 3.0, Swagger UI at `/api3-docs`.

API v3 is structured differently from v1/v2 and is where new endpoint work generally belongs. `lib/api3/generic/` is a **collection-agnostic** CRUD engine (`create/`, `read/`, `update/`, `patch/`, `delete/`, `search/`, `history/`) driven by the `enabledCollections` list set in `lib/api3/index.js`; `lib/api3/specific/` holds the few non-CRUD endpoints (`status`, `version`, `lastModified`). Changing generic CRUD behavior affects every collection at once.

Authorization lives in `lib/authorization/` and uses `shiro-trie` for hierarchical permission strings.

### Client

Webpack builds two entries, `app` and `clock`, from `bundle/bundle.source.js` and `bundle/bundle.clocks.source.js`. **Output goes to `node_modules/.cache/_ns_cache/public`, not into the repo** — the bundle is a build artifact, so there is nothing to commit and a stale bundle is fixed by re-running `npm run bundle`.

The bundle assigns the `window.Nightscout` namespace (`client`, `units`, `admin_plugins`, report/profile/food clients). Client modules in `lib/client/` are plain CommonJS factories: `index.js` is the dashboard controller, `chart.js` and `renderer.js` draw the D3 chart, `browser-settings.js` handles per-viewer settings.

### Settings have three layers

Adding a user-facing setting usually means touching all three:

1. `lib/settings.js` — the default value and its type coercion.
2. `lib/client/browser-settings.js` — reading the DOM control into the setting, and writing the stored value back into the control. Browser settings persist per-browser in localStorage and override server defaults for that viewer only.
3. `views/index.html` — the actual control in the settings drawer.

Server-side settings come from env vars via `lib/server/env.js`; `IMPORT_CONFIG` can additionally merge a remote settings JSON at boot (`augmentSettings`).

## Documentation

`docs/` is deliberately written as an agent-readable knowledge base, and `docs/INDEX.md` is its entrypoint. Before non-trivial work in an area, check `docs/audits/` for how it currently works, `docs/requirements/` for correctness criteria, and `docs/test-specs/` for known coverage gaps. `docs/proposals/` holds RFC-style designs that are proposed but not implemented — do not treat them as describing current behavior.

`docs/meta/ROADMAP.md` is the short list of what is actually being worked on, in order, including a *Decided against* section — check it before proposing work, and read it before suggesting something that section already rules out. `docs/meta/tech-debt-inventory.md` is the full catalogue of known debt behind it: a reference, not a plan, and parts of it have been overtaken by events, so verify against the code before acting on an entry.

## Deployment shape

This fork is deployed, not just developed. Operator-specific details (host, domain, credentials) are deliberately kept out of this repo — ask rather than guess. What matters for writing code here:

- Production runs the app as a **Docker image built from this repo's own `Dockerfile`**, tagged with the short commit SHA, from a git checkout of the fork. There is no CI pipeline and no image registry; a deploy is a build on the host followed by `docker compose up -d`. Rollback is re-pointing the image tag at a previous SHA, so keeping builds tagged per-commit matters.
- The target host is **`aarch64`/ARM64**. Anything added to the build must compile natively on ARM — native npm modules with x86-only prebuilds will break the image build, not just runtime.
- Production pins **MongoDB 4.4**, the floor of the CI matrix. Don't use query or driver features newer than that, even though CI also passes on 5.0/6.0.
- TLS is terminated by a reverse proxy in front of the app, which runs with `INSECURE_USE_HTTP=true` and listens on 1337 internally. Code must not assume it sees HTTPS directly; respect the forwarded headers rather than reading the scheme off the socket.
- Secrets (`API_SECRET`, bridge credentials) come from an `.env` file next to the compose file and are referenced as `${VAR}`. Never inline a secret value into compose, code, or docs.
- `AUTH_DEFAULT_ROLES=denied` in production, so unauthenticated API reads return 401. A 401 from a deployed instance is usually correct behavior, not a regression.
- Mongo is backed up nightly by a host cron script. Any change touching schema or migrations should be considered against a restore path.

## Contributing conventions

Upstream (`nightscout/cgm-remote-monitor`) develops on `dev`; `master` is the stable distribution branch and pull requests target `dev`. Feature branches use a `wip/` prefix. New npm dependencies need justification — the project prefers reducing them.
