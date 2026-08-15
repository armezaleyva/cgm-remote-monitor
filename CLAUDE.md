# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this is

Nightscout (`cgm-remote-monitor`) — a real-time CGM (continuous glucose monitor) dashboard. Node.js + Express 4 + MongoDB + Socket.IO, with a Webpack-bundled D3/jQuery frontend.

This is health-critical software: people use it to make insulin decisions, and a large ecosystem of uploaders (AAPS, Loop, xDrip, bridges) and viewers depends on its API shapes. Prefer small, backward-compatible changes over rewrites. Do not change API v1/v2/v3 request or response shapes without an explicit decision to do so.

## Setup and commands

Requires Node >= 20 and npm >= 10 per `package.json` `engines`, plus a reachable MongoDB. Note that `.nvmrc` is stale — it pins 16.16.0, which the engines field rejects. Node 22 matches both the `Dockerfile` base image and the CI matrix.

`bin/setup-dev.sh` does the whole local setup in one step — checks the toolchain against `engines`, runs `npm ci`, writes `my.test.env` and `my.env`, and probes for MongoDB. It is POSIX sh, works in Git Bash on Windows, and never overwrites existing env files.

```bash
bin/setup-dev.sh                  # full setup, including the webpack bundle
bin/setup-dev.sh --fast           # skip the bundle — enough for lint + unit tests
bin/setup-dev.sh --verify         # run lint and the unit suite when finished
```

**Do not use `bin/setup.sh`** — that is upstream's Vagrant/Ubuntu provisioner and it installs Node 8, which `engines` rejects.

The equivalent steps by hand:

```bash
npm install                       # also runs the webpack production build via postinstall
cp docs/example-template.env my.env   # then edit MONGO_CONNECTION, API_SECRET; keep NODE_ENV=development
npm run dev                       # nodemon + webpack dev middleware + HMR on PORT (default 1337)
npm run lint                      # eslint, lib/ only — does not cover tests/, bundle/, webpack/
npm run bundle                    # production bundle;  npm run bundle-dev  for the dev build
```

Tests need `my.test.env`, which is gitignored. **`make my.test.env` produces a file that cannot run the suite**, in two separate ways. The target omits `NODE_ENV=test`, which `tests/lib/production-safety.js` hard-fails without; and its database name `test_db` fails `tests/mongo-storage.test.js`, which hardcodes `testdb`. CI never hit either, because it uses `tests/ci.test.env` throughout. `bin/setup-dev.sh` writes a file that fixes both — prefer it over the Makefile target.

```bash
npm test                          # everything
npm run test:unit                 # fast suite, runs parallel with 2 jobs
npm run test:integration          # api/api3/websocket/storage/reports suites
npm run test:flaky                # repeat-runs suites to surface flakiness (scripts/flaky-test-runner.js)
```

**`test:unit` is not self-contained**, despite the name. It needs two things beyond `npm ci`: the webpack bundle, because 5 suites (`admintools`, `careportal`, `hashauth`, `pluginbase`, `profileeditor`) load it through `tests/fixtures/headless.js`; and a running MongoDB, because 6 tests in `security` and `verifyauth` call `bootevent().boot()` and otherwise sit there until they time out. Lint and the pure-logic plugin suites need neither.

Full local baseline, verified on Windows / Node 22.23.2 / MongoDB 4.4 in Docker: **`test:unit` 253 passing, `test:integration` 501 passing + 1 pending, both clean.** `npm run lint` reports 48 pre-existing problems (34 errors, 14 warnings) across `lib/server/`, `lib/storage/` and others — that is the baseline, not a regression. A local Mongo for tests is one command: `docker run -d --name ns-test-mongo -p 27017:27017 mongo:4.4`.

**A new test file does not run automatically.** `test:unit` and `test:integration` (and their `:ci` twins) use an explicit brace-list of suite names in `package.json`, not a wildcard. `deploy.sh` gates on `npm run test:unit:ci`, so a test omitted from that list is silently skipped by the only verification step this fork has. Add the suite name to both the plain and `:ci` variant when adding a test. Only `npm test` and `test:parallel` glob all of `tests/*.test.js`.

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

`docs/meta/ROADMAP.md` is **this fork's** roadmap — what we are working on, in order, plus a *Decided* section recording closed questions. Check it before proposing work, and do not re-open something it has already settled.

**Log work there as part of doing it, not as an afterthought.** Starting something substantial → add it under *Now* (two or three items maximum). **That is where detail belongs** — what is being attempted, what is still unresolved, what to watch — because that is what the next session picking it up actually needs. Finishing it → **compress it to a single line** under *Done* with the completion date and a link; a finished item is a pointer to where the detail now lives, not a retrospective. Settling a question → *Decided*, together with the consequence that follows from it. Deferring something you discovered but are deliberately not doing → *Next* or *Later*, so the next session doesn't rediscover it from scratch. Changing how far this fork diverges from upstream → update the *Where the fork stands* table. Follow that file's own rules: one line per item plus a link, no effort estimates and no code samples — detail belongs in `docs/requirements/` or `docs/proposals/`.

Everything else under `docs/` — the seven `audits/`, `architecture-overview.md`, and `modernization-roadmap.md` — describes **upstream**, not this fork's plans. Despite its name, `modernization-roadmap.md` is not our roadmap; it is upstream's technical-debt catalogue. It was generated in a single AI pass in commit `2f79b3fa` (2026-01-13) and never substantively revised; spot-checks found claims that were inaccurate when written, not merely stale. Treat it as leads to verify against the code, never as findings, and never as work this fork has committed to.

## Deployment shape

This fork is deployed, not just developed. Operator-specific details (host, domain, credentials) are deliberately kept out of this repo — ask rather than guess. What matters for writing code here:

- Production runs the app as a **Docker image built from this repo's own `Dockerfile`**, tagged with the short commit SHA, from a git checkout of the fork. There is no CI pipeline and no image registry. Deploys and rollbacks go through the scripts in `deploy/` — see *Feature development protocol* below. Rollback is re-pointing the image tag at a previous SHA, so keeping builds tagged per-commit matters.
- The target host is **`aarch64`/ARM64**. Anything added to the build must compile natively on ARM — native npm modules with x86-only prebuilds will break the image build, not just runtime.
- Production pins **MongoDB 4.4**, the floor of the CI matrix. Don't use query or driver features newer than that, even though CI also passes on 5.0/6.0.
- TLS is terminated by a reverse proxy in front of the app, which runs with `INSECURE_USE_HTTP=true` and listens on 1337 internally. Code must not assume it sees HTTPS directly; respect the forwarded headers rather than reading the scheme off the socket.
- Secrets (`API_SECRET`, bridge credentials) come from an `.env` file next to the compose file and are referenced as `${VAR}`. Never inline a secret value into compose, code, or docs.
- `AUTH_DEFAULT_ROLES=denied` in production, so unauthenticated API reads return 401. A 401 from a deployed instance is usually correct behavior, not a regression.
- Mongo is backed up nightly by a host cron script. Any change touching schema or migrations should be considered against a restore path.

## Feature development protocol

This fork ships to a live instance carrying one person's real CGM data, with no CI and no staging environment. The loop below is the entire safety net — follow it rather than improvising a shorter path.

1. **Branch.** `git checkout -b wip/<short-name>` off `master`. `master` means "known good in production"; don't develop on it directly.
2. **Change and commit.** Keep changes small and backward-compatible — see the API-stability note at the top of this file.
3. **Push.** `deploy.sh` deploys a *pushed* git ref, so unpushed work cannot be deployed.
4. **Deploy the branch:** `./deploy.sh wip/<short-name>` on the host (see `deploy/README.md`). It builds an image tagged with the short SHA, runs the unit suite *inside that image* against a throwaway MongoDB, takes a pre-deploy `mongodump`, swaps the container, health-checks it, and rolls back automatically if the app doesn't come back.
5. **Verify against the running instance.**
6. **Merge to `master`** once it is proven in production, and push.

**Never hand-build the image or hand-edit the compose image tag.** That bypasses the test gate and the pre-deploy backup and leaves the recorded rollback target wrong. `deploy/deploy.sh` refuses to run from inside the build checkout for the same reason — always run the installed copy.

**Rollback** is `./rollback.sh` on the host, which reverts to the tag the last deploy replaced. The most recent image tags are retained as rollback targets.

Realities that shape verification:

- There is often **no local Node toolchain and no local MongoDB**, so `npm test` may not be runnable on the dev machine. The test gate inside the built image is then the only real verification path. It works because the `Dockerfile` runs `npm ci --omit=optional` — omitting *optional*, not *dev* — so mocha and `tests/` ship inside the image, and `tests/ci.test.env` is committed.
- A deploy **recreates the container**, so expect a brief outage (~15s) while it restarts. Avoid deploying while someone is actively watching CGM data.
- A deployed instance answers **401** on API reads because `AUTH_DEFAULT_ROLES=denied`. 401 means healthy; the health check accepts 401 and 200 as success. Don't "fix" a working instance over it.
- Host-specific values (hostname, paths) live in a `deploy.conf` on the server that is deliberately not in this repo. Ask rather than guess.

## Contributing conventions

Upstream (`nightscout/cgm-remote-monitor`) develops on `dev`; `master` is the stable distribution branch and pull requests target `dev`. Feature branches use a `wip/` prefix. New npm dependencies need justification — the project prefers reducing them.
