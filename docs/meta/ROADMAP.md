# Roadmap

What **this fork** is doing, in order. Not upstream's agenda.

Our instance serves several viewers — the operator plus family and caregivers — across more than
one timezone. Two themes follow from that:

- **Instance features** — what we want our Nightscout to do, whether or not upstream wants it.
- **Deployment & ops** — keeping the live instance healthy, current, and recoverable.

## How to use this file

- **Log work here as part of doing it.** Starting something → *Now*. Finishing it → *Done*.
  Settling a question → *Decided*, with the consequence. Deferring something → *Next* or *Later*.
  A session that changes this fork should leave this file true.
- **Detail belongs in *Now*, not *Done*.** While work is live, say what is being attempted, what
  is still unresolved, and what to watch — that is what the next session needs. On completion,
  compress it to a single line: it happened, when, and where to read more. A finished item is a
  pointer, not a retrospective.
- **One line per item**, plus a link to detail if detail exists.
- **No dates, no effort estimates, no code samples.** Those are what rotted the document this
  one replaced.
- **Now** is what is actively being worked. Two or three items, maximum.
- *Decided* is load-bearing. It stops closed questions from being reopened.
- An item belongs here only if it serves **our instance**. Upstream's priorities are upstream's
  until we deliberately adopt one.

---

## Where the fork stands

Divergence from upstream is one app change plus fork-local tooling and docs:

| What | Where |
|---|---|
| Per-viewer display timezone picker (`341040a7`) | 41 lines across 5 client files |
| Deploy tooling (`74cbe3ea`) | `deploy/` — build, in-image test gate, DB backup, container swap, health check, auto-rollback |
| Fork-local docs | `CLAUDE.md`, `docs/meta/ROADMAP.md` |

Only the timezone picker touches upstream-owned application files; the rest lives at paths
upstream does not use, so it costs nothing at merge time. That is the pattern to keep.

Everything else is upstream `nightscout/cgm-remote-monitor`. Last upstream merge: `7e0e77f8`,
2026-04-29.

Note the name collision: upstream's `docs/meta/modernization-roadmap.md` is **not** a roadmap
for this fork — it is upstream's technical-debt catalogue, and we have not adopted it.

## Now

- **Make sure every viewer actually sees the basal layer.** *(feature — last mile)* The server
  default is set, but `browser-settings.js` lets a stored `basalrender` value in localStorage
  override it, so anyone who has previously saved settings in the drawer still sees nothing.
  Each such viewer must pick "Default" once. Decide whether that is acceptable or whether we
  want server-set defaults that genuinely reach everyone — the deferred question, now concrete.
  → [basal-bolus-display.md](../requirements/basal-bolus-display.md)

- **A "mood of the day" pill.** *(feature — shipping off by default first)* A decorative status
  pill showing one absurd emoji per day, chosen by hashing the local calendar date so it holds
  steady all day and every viewer sees the same one. Phase 1 ships it registered but hidden, so
  it has to be ticked on per browser while it is being verified; phase 2 flips it on for
  everyone. Phase 2 is the part to think about — a stored `showPlugins` in localStorage beats
  the server default, so reaching existing viewers needs a storage-version bump and a migration,
  which is **the same trap as the basal item above** on a payload where being wrong is harmless.
  Treat it as the rehearsal for that decision.
  → [mood-of-the-day.md](../requirements/mood-of-the-day.md)

## Done

- **A repeatable, verified deploy loop.** *(2026-08-14)* Build, in-image test gate, pre-deploy
  backup, swap, health check, auto-rollback. → [deploy/README.md](../../deploy/README.md)

- **Display basal and bolus information on the site.** *(2026-08-13)* No application code changed;
  the gap was a missing pump data source, now filled by tconnectsync.
  → [basal-bolus-display.md](../requirements/basal-bolus-display.md)

## Next

- **Move production off MongoDB 4.4.** *(ops)* 4.4 has been end-of-life since early 2024, so it
  receives no security patches, and it holds personal health data for several people. Upstream's
  CI already covers 5.0 and 6.0, so the compatibility risk is low and mostly ours to schedule.
  Consider this against the restore path before starting.

## Later

- **Fix `TZ: America/Phoenix` in the compose stack.** *(ops — latent bug)* The container runs on
  Arizona time while the household and pump are in Denver. The value came from the Nightscout
  docker template (the comment "Change if you are not in Arizona time" is still beside it) and
  was never changed. Phoenix does not observe DST and Denver does, so the container clock is an
  hour off through the summer and correct through the winter. Confirmed *not* the reason the
  display timezone picker was built, so the two are independent. Not urgent — Nightscout stores
  UTC and the chart renders in each browser's local time — but it will keep causing
  hard-to-reproduce, seasonal confusion until fixed.

- **Add an `upstream` remote and write down the sync procedure.** *(ops)* `git remote -v` lists
  only `origin` (the fork), so there is no configured path to pull `nightscout/dev`. We are ~3½
  months behind. Upstream ships correctness fixes to a health-critical app, and right now taking
  one is an ad-hoc scramble. Plumbing, not a programme — but it compounds while it waits.

## Decided

- **The display timezone picker stays local, permanently.** Not going upstream. We accept a
  small recurring merge cost on `lib/client/index.js`, `chart.js`, `browser-settings.js`,
  `lib/settings.js`, and `views/index.html` in exchange for skipping an upstream review cycle
  on a feature shaped around our own multi-timezone viewers. **Consequence worth honouring:**
  keep local patches small and isolated, because every one of them is now a permanent tax on
  every future sync.
- **We are not adopting upstream's modernization agenda.**
  [modernization-roadmap.md](./modernization-roadmap.md) stays as a reference to borrow from, never
  as a plan we inherit. It was generated in a single AI pass in `2f79b3fa` and contains claims
  that were untrue when written — verify anything before acting on it.

---

**See also:** [INDEX.md](../INDEX.md) for all docs.
