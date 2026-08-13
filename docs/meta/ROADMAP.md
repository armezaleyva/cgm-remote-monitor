# Roadmap

What **this fork** is doing, in order. Not upstream's agenda.

Our instance serves several viewers — the operator plus family and caregivers — across more than
one timezone. Two themes follow from that:

- **Instance features** — what we want our Nightscout to do, whether or not upstream wants it.
- **Deployment & ops** — keeping the live instance healthy, current, and recoverable.

## How to use this file

- **One line per item**, plus a link to detail if detail exists.
- **No dates, no effort estimates, no code samples.** Those are what rotted the document this
  one replaced.
- **Now** is what is actively being worked. Two or three items, maximum.
- *Decided* is load-bearing. It stops closed questions from being reopened.
- An item belongs here only if it serves **our instance**. Upstream's priorities are upstream's
  until we deliberately adopt one.

---

## Where the fork stands

Divergence from upstream is one code change plus fork-local documentation:

| What | Where |
|---|---|
| Per-viewer display timezone picker (`341040a7`) | 41 lines across 5 client files |
| Fork-local docs | `CLAUDE.md`, `docs/meta/ROADMAP.md` |

Everything else is upstream `nightscout/cgm-remote-monitor`. Last upstream merge: `7e0e77f8`,
2026-04-29.

Note the name collision: upstream's `docs/meta/modernization-roadmap.md` is **not** a roadmap
for this fork — it is upstream's technical-debt catalogue, and we have not adopted it.

## Now

- **Add an `upstream` remote and write down the sync procedure.** *(ops)* `git remote -v` lists
  only `origin` (the fork), so there is no configured path to pull `nightscout/dev`. We are ~3½
  months behind. Upstream ships correctness fixes to a health-critical app — the Mongo driver
  hardening and profile-dedup fixes in this very log — and right now taking one is an ad-hoc
  scramble. This is plumbing, not a programme; it's here because we've committed to carrying a
  local patch indefinitely, which makes merging a permanent part of running the instance.

## Next

- **Move production off MongoDB 4.4.** *(ops)* 4.4 has been end-of-life since early 2024, so it
  receives no security patches, and it holds personal health data for several people. Upstream's
  CI already covers 5.0 and 6.0, so the compatibility risk is low and mostly ours to schedule.
  Consider this against the restore path before starting.

## Later

_Feature items to be filled in._ Empty because our wants haven't been written down yet, not
because there's nothing to build.

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
