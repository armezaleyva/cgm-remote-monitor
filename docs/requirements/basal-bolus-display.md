# Basal & Bolus Display

> **Fork-local document.** Written for `armezaleyva/cgm-remote-monitor`, not upstream. Status:
> requirements stage — open questions below are unanswered. Linked from
> [ROADMAP.md](../meta/ROADMAP.md).

## Goal

Basal and bolus information should be visible on our instance, to all our viewers.

## What upstream already implements

**Nothing appears to be missing from the code.** Verified against this checkout:

### Basal

| Capability | Where |
|---|---|
| `basal` plugin — "Basal Profile" pill showing current rate | `lib/plugins/basalprofile.js` |
| Temp-basal / combo-bolus markers (`T:` / `C:` prefix on the pill) | `basalprofile.js:22-25` |
| Dedicated chart layer, ¼ of focus-chart height | `lib/client/chart.js:233,332` |
| Three render modes: **None / Default / Icicle** | `views/index.html:222-226` |
| Per-viewer persistence of the chosen mode | `browser-settings.js:198,253,316` |

### Bolus

| Capability | Where |
|---|---|
| Treatment marks on the chart, radius scaled by insulin/carbs | `lib/client/renderer.js:509-530` |
| Tooltips showing Insulin, Carbs, and bolus-calculator breakdown | `renderer.js:611-654` |
| `renderFormat`, `renderOver`, `notifyOver` extended settings | `lib/plugins/bolus.js` |
| "Bolus Display Threshold" control — compact format below threshold | `views/index.html:231-234`, `renderer.js:570` |
| Bolus wizard preview, bolus calculator | `boluswizardpreview.js`, `boluscalc.js` |

Both `basal` and `bolus` are in `DEFAULT_FEATURES` (`lib/settings.js:184`) and in the `ENABLE`
line of `docs/example-template.env`.

## Why it is not showing — ANSWERED

Diagnosed against production on 2026-08-13 (read-only queries). **The instance has no insulin
data at all**, so there is nothing for the display layer to draw.

```
entries:       8949   all device=share2, flowing normally (newest ~1 min before the query)
treatments:       0
devicestatus:     0
activity:         0
food:             0
profile:          1   stock defaults, never configured
```

Ingestion is the **Dexcom Share bridge** (`BRIDGE_USER_NAME` / `BRIDGE_PASSWORD` set, all
entries `device=share2`). Share is a CGM-sharing service — it carries glucose readings and has
no access to insulin data. No pump uploader is connected.

`ENABLE`, `SHOW_PLUGINS`, and `BASAL_RENDER` are all unset, so the app runs on `DEFAULT_FEATURES`
— which already includes `basal`, `bolus`, `careportal`, and `profile`. Those defaults are not
the blocker; the absence of data is. `BASAL_RENDER` will still need setting once data exists,
but it is a second-order issue.

**Consequence: this is not a display problem and not a configuration problem. It is a missing
data source.** No change to this codebase can fix it.

### The profile is unconfigured

The single profile document is Nightscout's out-of-box default (`startDate` 1970-01-01, created
2026-07-14):

```
basal 0.9 U/hr flat · carbratio 8 · sens 100 · dia 3
```

These are placeholders. The IOB, COB, and bolus-wizard plugins compute from them, so if insulin
data begins arriving while the profile still holds defaults, the site will render plausible but
meaningless numbers. In a health-critical app that is worse than displaying nothing. Configuring
the profile is a prerequisite for this item, not a follow-up.

## The multi-viewer problem

`basalrender` is a **browser setting**, persisted per-viewer in localStorage. Our instance serves
several people across several devices. Even once basal display works, each viewer must enable it
on each device unless a server-side default is set.

This is the same shape as the problem the display timezone picker solved, and it suggests the
durable fork-local requirement may be *"server-set display defaults that apply to every viewer"*
rather than anything basal-specific. Worth deciding before building anything.

## The setup

Established 2026-08-13:

- **Pump:** Tandem t:slim X2, running **Control-IQ** (Tandem's own closed loop)
- **App:** t:connect mobile on iOS. No Loop/Trio — they cannot drive a t:slim; Tandem exposes no
  open control interface
- **CGM:** Dexcom, reaching Nightscout via the Share bridge, independent of the pump path
- **Nothing has ever attempted to upload** — no POST to treatments/devicestatus/profile in the
  logs, and the sole auth subject (`share`, roles `["readable"]`) is read-only

## Route: tconnectsync

[jwoglom/tconnectsync](https://github.com/jwoglom/tconnectsync) polls Tandem's cloud and posts
treatments to the Nightscout API. It is the only route for a Tandem pump.

**Tandem Source, not t:connect.** Tandem retired the t:connect *portal* in favour of Tandem
Source (US, from 2024-09-30). **tconnectsync 2.0+ is required**; earlier versions target APIs
that no longer exist. The phone app is still branded t:connect — the change is server-side.

### Configuration

| Variable | Value |
|---|---|
| `TCONNECT_EMAIL` / `TCONNECT_PASSWORD` | Tandem Source credentials → `.env`, referenced as `${VAR}` |
| `NS_URL` | `http://nightscout:1337` — **internal compose address** |
| `NS_SECRET` | `API_SECRET`. The existing `share` token is read-only and cannot upload |
| `TIMEZONE_NAME` | The pump's timezone, TZ-database format |
| `TCONNECT_REGION` | `US` or `EU` (defaults to `US`) |
| `PUMP_SERIAL_NUMBER` | Optional |

Use the **internal** `NS_URL`: the API secret then never traverses the public path, traefik and
TLS are bypassed, and the uploader is unaffected by certificate or DNS problems. This mirrors
how `deploy.sh` health-checks against 127.0.0.1.

**Leave the CGM feature off** (it is opt-in). Upstream's own warning: it delivers CGM with
*">30 MINUTE lag and SHOULD NOT BE USED AS A REPLACEMENT FOR DEXCOM SHARE"*. Enabling it would
also write a second source into `entries` alongside `share2`, producing duplicates. Default
features — basals, boluses, pump events, insulin profiles — are exactly what we want.

### The arm64 problem

The published image is **amd64 only**, confirmed against the host:

```
ghcr.io/.../tconnectsync:latest   platform: {architecture: amd64, os: linux}
host                             aarch64 / arm64
```

Not a manifest list — a single-architecture manifest. It will not run natively.

**Build it on the host instead.** The Dockerfile is `python:3.11-slim` (multi-arch, arm64
included) and installs `gcc`, so native dependencies without arm64 wheels compile from source.
This is the same build-on-host pattern `deploy/deploy.sh` already uses for Nightscout, so it
fits the existing operational model rather than adding a new one.

## Expected latency

Pump → phone → Tandem Source → 5-minute poll. Insulin data will run **tens of minutes behind**
real time. This is inherent to the route, not tunable. It is suitable for reviewing the day, not
for in-the-moment decisions. Real-time insulin data would require a different pump and a looping
app — a hardware decision, not a software one.

## Prerequisites before data is useful

1. **Configure the profile.** Still Nightscout's factory default. tconnectsync syncs insulin
   profiles, which may populate it — verify rather than assume, because IOB/COB/BWP compute from
   whatever is there.
2. **Set `BASAL_RENDER`.** Currently unset, so `basalrender` falls back to `'none'` and no
   viewer sees the basal layer regardless of data.
3. **Decide the auth story.** `NS_SECRET` is the full-privilege API secret. Acceptable for a
   trusted container in our own stack; worth revisiting if Nightscout gains a scoped upload token
   that tconnectsync supports.

## Deployed 2026-08-13

tconnectsync v3.0.1 runs as a compose service on the host, polling every 300s.

- **Image built locally for arm64** — [deploy/tconnectsync/Dockerfile](../../deploy/tconnectsync/Dockerfile).
- **Service definition** — [compose-service.yml.example](../../deploy/tconnectsync/compose-service.yml.example).
- **Profile corrected.** `defaultProfile` moved off the Nightscout factory `Default` and onto the
  pump's active profile, with the pump's own basal schedule, ISF, carb ratio and DIA. The old
  `Default` store is preserved — the profile collection is append-only. Subsequent runs report
  *"Pump and Nightscout profiles up to date"*, so the sync is idempotent. (Therapy values are
  deliberately not recorded here; read them from the pump or the profile editor.)
- **Backfilled a multi-week window of treatments**, all stamped
  `enteredBy: "Pump (tconnectsync)"` — so a rollback is a single `deleteMany` on that field.
  The overwhelming majority are Temp Basal records: Control-IQ adjusts basal every few minutes,
  so expect roughly thirty times as many basal rows as boluses. Also present: Sleep, Basal
  Suspension/Resume, Site Change, Sensor Start/Stop. A handful of duplicate Site Change events
  were deduplicated by Nightscout on insert, so the stored count runs slightly below the number
  tconnectsync reports as processed — that gap is expected, not data loss.
- **`devicestatus` stayed 0.** `DEVICE_STATUS` yields nothing for historical data; it would only
  populate from live events. The `pump` plugin is also absent from `ENABLE`, so the pump pill
  would need that added before it could render anything.

### Gotcha: cache volume ownership

The credential-cache bind mount must be owned by **uid 1000** (the container's `appuser`), not
the host user — ours is 1001. Getting this wrong crash-loops the container on
`PermissionError: .../.creds_cache`. Recorded in the compose example.

## The remaining blocker is not ours

**Tandem Source has no pump events after 2026-07-15T08:28:35.** Verified by dry-running a recent
window (0 events) against a July window (2,662 events) — the pipeline is provably correct and the
source is empty. All four pumps on the account are quiet; this is not a pump switch.

The break is somewhere in pump → phone → Tandem cloud, and none of it is fixable from this repo.
Debug order: pull a report from source.tandemdiabetes.com (authoritative — empty there means the
data never reached Tandem); check t:connect's last-sync time on the phone; confirm the pump in
daily use is the one pinned in `PUMP_SERIAL_NUMBER`; check iOS Background App Refresh, Bluetooth
and Cellular for t:connect.

The uploader will pick up new data automatically within 5 minutes of it appearing.

### `BASAL_RENDER` — done 2026-08-13

Set to `default` on the nightscout service. Verified in the running container and as served:
`extendedSettings.basal: {"render": "default"}`.

**But it only reaches viewers with no stored preference.**
[browser-settings.js:316-317](../../lib/client/browser-settings.js#L316-L317) lets a localStorage
`basalrender` value override the server default. Any viewer who has previously saved settings in
the drawer keeps their stored `'none'` and still sees no basal layer until they pick "Default"
themselves. This is the deferred per-viewer problem surfacing in practice.

## Still open

- **Per-viewer vs. server-set display defaults.** No longer hypothetical — see above. A viewer
  who once opened the settings drawer is now pinned to their old value, and nothing we set
  server-side reaches them.
- **Live data.** Tandem Source still holds nothing after 2026-07-15. Working hypothesis (the
  operator's, and it fits the evidence): the t:connect app was not installed, and 2026-07-11 was
  the last manual upload. The pinned pump reported a `lastUploadDate` of 2026-08-13 during
  diagnosis and its last-seen event advanced from 07-11 to 07-15 mid-session, both consistent
  with a freshly installed app working through a backlog. Unresolved: whether the pump has been
  in use since 07-15, which decides between "more backlog is coming" and "nothing to upload".

**Note for auto-update:** `autoupdate.py` only ever processes a 24-hour window
(`time_start = time_end - timedelta(days=1)`). It notices when `maxDateOfEvents` advances and
then imports just the previous day, so any backlog older than 24h is silently skipped. Closing a
gap requires an explicit run with `--start-date` / `--end-date`.
