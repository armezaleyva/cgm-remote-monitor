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

## Why it might not be showing

Four gates, most likely first. These are hypotheses — none is yet confirmed against our instance.

1. **Basal rendering defaults to `none`.** `browser-settings.js:103` reads
   `settings.extendedSettings.basal ? settings.extendedSettings.basal.render : 'none'`. Unless
   the server sets `BASAL_RENDER`, every viewer sees no basal layer until they open the settings
   drawer and change it themselves.
2. **`ENABLE` on our instance may not list the relevant plugins.** Production's env is not in
   this repo, so this needs checking on the host.
3. **No treatment profile with basal rates.** `basalprofile.js:hasRequiredInfo()` bails and logs
   *"For the Basal plugin to function you need a treatment profile"* — silently, from the
   viewer's perspective.
4. **Treatments carrying `insulin`/`carbs` may not be reaching the database.** Depends entirely
   on which uploader feeds the instance.

## The multi-viewer problem

`basalrender` is a **browser setting**, persisted per-viewer in localStorage. Our instance serves
several people across several devices. Even once basal display works, each viewer must enable it
on each device unless a server-side default is set.

This is the same shape as the problem the display timezone picker solved, and it suggests the
durable fork-local requirement may be *"server-set display defaults that apply to every viewer"*
rather than anything basal-specific. Worth deciding before building anything.

## Open questions

1. **What is actually happening today?** Nothing rendering at all, or partially — e.g. boluses
   visible but no basal layer? This splits the diagnosis immediately.
2. **Which uploader and pump feed the instance?** AAPS, Loop, Trio, xDrip? This determines
   whether basal and treatment data exist at all, and in what shape.
3. **What should viewers see?** The current-rate pill, the basal chart layer, bolus marks, a
   report — or all of it? "Display basal/bolus information" is currently broad enough to mean
   several different pieces of work.
4. **Is per-viewer configuration acceptable,** or should defaults be set once for everyone?

## Next step

Answer 1 and 2 — they are cheap to check and they determine whether this is a configuration
task, a data-flow task, or (unlikely, on current evidence) a development task.
