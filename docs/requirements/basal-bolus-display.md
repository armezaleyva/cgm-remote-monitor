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

## Routes to insulin data

Only three exist, and the choice is a setup decision, not a software one.

1. **Care Portal manual entry.** Nightscout's built-in `careportal` plugin records boluses,
   carbs, and temp basals by hand. Requires no pump and no uploader — it is the route for anyone
   on injections rather than a pump. Already enabled by default.
2. **A looping app uploader** — AAPS (Android), Loop or Trio (iOS). Uploads boluses, temp basals,
   and a profile store automatically. Requires a compatible pump and a phone running it.
3. **A pump-specific uploader**, where one exists for the pump in question.

Route 1 works today with zero changes. Routes 2 and 3 depend on hardware we have not established
exists.

## Open questions

1. **Is there an insulin pump in the picture, or are we on injections?** This decides between
   route 1 and routes 2/3, and nothing can proceed before it is answered.
2. **Who would enter or upload the data?** Manual entry is a per-dose habit for someone; an
   uploader is a one-time setup.
3. **What should viewers see?** Settled: current-rate pill, basal chart layer, and bolus marks
   on the chart.
4. **Per-viewer vs. server-set defaults.** Deferred — not selected as a requirement, but it will
   resurface, because `basalrender` is per-browser localStorage and we have several viewers.

## Next step

Answer question 1. Until then this item cannot move, and no code in this repo is involved.
