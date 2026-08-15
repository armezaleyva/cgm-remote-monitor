# Mood of the Day

> **Fork-local document.** Written for `armezaleyva/cgm-remote-monitor`, not upstream. Status:
> phase 1 code deployed but not yet switched on; phase 2 not started. Linked from
> [ROADMAP.md](../meta/ROADMAP.md).

## Goal

A decorative status pill showing one absurd emoji per day, with a deadpan caption in the tooltip.
Purely for fun. It is the first fork-local *feature* plugin, so it doubles as a low-stakes trial
of two things we will want again: adding a plugin at all, and making a plugin visible to viewers
who already have saved browser settings.

## Correctness criteria

| Requirement | Why |
|---|---|
| The emoji is stable for a whole calendar day | `updateVisualisation` runs on every `data-loaded` — roughly every five minutes. `Math.random()` there would reshuffle the pill under the viewer. |
| All viewers see the same emoji on the same day | It is a shared joke; per-viewer randomness makes it meaningless to talk about. |
| The chosen day is the *viewer's* local date | Matches how the rest of the client renders, and our viewers span timezones. Consequence: the pill flips at each viewer's own midnight, so two viewers briefly disagree. Accepted. |
| Never reads CGM data | It has nothing to say about glucose, and must not imply that it does. |
| Never raises a notification | A joke must not be able to reach the alarm path. Enforced by a test asserting `checkNotifications` does not exist. |
| Renders with no data present | It does not depend on the data cycle having produced anything. |

The mood is `MOODS[fnv1a(localDateAsYYYYMMDD) % MOODS.length]`. No storage, no server round-trip,
no per-viewer state — the date *is* the seed.

Deliberately **not** keyed off `sbx.time`: in the client sandbox that follows the chart brush, so
scrubbing through history would change the pill as you drag.

## Implementation

| Piece | Where |
|---|---|
| The whole feature | `lib/plugins/moodoftheday.js` |
| Registration — **client list only** | `lib/plugins/index.js` |
| Tests | `tests/moodoftheday.test.js` |

Not touched: `views/index.html` (the settings-drawer checkbox is generated from the plugin list at
`browser-settings.js:118-126`), `lib/settings.js` (no new setting), and anything server-side.

## Rollout

Visibility needs **two** independent things: the plugin must be enabled (`ENABLE`) *and* shown
(`SHOW_PLUGINS`). Enabling alone renders nothing — the auto-show fallback at `settings.js:326-342`
requires `showPlugins` to be both truthy and zero-length, which no string satisfies, so it never
fires.

### Phase 1 — off by default (code deployed; not yet switched on)

`ENABLE` gets `moodoftheday`; `SHOW_PLUGINS` does not. The plugin registers and its checkbox
appears in the settings drawer, but the pill stays hidden until a viewer ticks it. Nothing changes
for anyone who does not go looking.

Where to make that edit, confirmed on the host: **`ENABLE` is set directly in the stack's
`docker-compose.yml`, not in the `.env` beside it**, and there is no `SHOW_PLUGINS` key at all.
`deploy.sh` only rewrites `NS_IMAGE_TAG` inside `.env`, so editing the compose file does not
collide with it, and the next `docker compose up -d` picks both up together.

The absent `SHOW_PLUGINS` is convenient here: the server default for `showPlugins` is `dbsize`
plus what `adjustShownPlugins` appends, which does not include this plugin, so phase 1 is
hidden-by-default without any extra configuration.

Verify: the emoji renders (rather than a tofu box) on the devices our viewers actually use, the
caption appears on hover, and the emoji is unchanged after a page reload but different tomorrow.

### Phase 2 — on by default (not started)

Two populations, and the server default only reaches one of them:

| Viewer | `showPlugins` in localStorage? | Reached by `SHOW_PLUGINS`? |
|---|---|---|
| Never saved browser settings | No | Yes — server default applies |
| Ever clicked Save | Yes, frozen at that moment | **No** |

`browser-settings.js:293-297` prefers any stored value over the server default, and Save writes
the complete checked-plugin list (`browser-settings.js:205-211`). A plugin that did not exist then
cannot be in that string, so those viewers never see the pill.

The fix is upstream's own pattern: `handleStorageVersions()` at `browser-settings.js:274-288`
already does exactly this for `careportal`, mutating in-memory settings rather than writing to
localStorage, so it re-applies on every load until the viewer saves again. Phase 2 bumps
`STORAGE_VERSION` from 1 to 2 and adds a `previousVersion < 2` branch. The gating works out:
`parseInt(null)` is `NaN` and `NaN < 2` is false, so never-saved viewers skip the migration — which
is correct, since the server default already covers them.

Phase 2 touches `browser-settings.js`, an upstream-owned file, so it increases fork divergence.
Keep the migration mood-specific and shaped like the careportal precedent; generalise into a
"server can force-show a plugin" mechanism only once it has been proven twice.

## Open questions

- Does the migration actually behave on a real browser with saved settings? That is the whole
  point of running this before touching basal.
- Do any of our viewers' devices fail to render the emoji set? Unknown until phase 1 is observed.
