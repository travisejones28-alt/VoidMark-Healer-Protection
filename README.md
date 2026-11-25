# VoidMark Healer

Healer protection and group communication for **WoW Forever** (Interface 16001), part of the VoidMark suite.
Tells your group when the healer is crowd-controlled, interrupted, out of mana, in danger or dead, and
counts down to when healing comes back. Works in dungeons, raids, battlegrounds and world PvP, alongside VuhDo or any other healing addon.

No external libraries. Original code: the feature list was inspired by HealerProtection, but no code, assets
or libraries from it are used.

## Install

1. Clone this repo (e.g. `C:\WoW Forever Addons\VoidMark-Healer`).
2. Double-click **INSTALL.bat**. It links the folder into
   `C:\Program Files (x86)\World of Warcraft\_forever_\Interface\AddOns\VoidMarkHealer`.
   (No PowerShell? Copy `dist\VoidMarkHealer.zip`'s `VoidMarkHealer` folder into AddOns instead.)
3. In game: `/reload`, then `/vmh`.

Updates: pull in GitHub Desktop, then `/reload`.

## What it announces

| Group | Alerts |
|---|---|
| Crowd control | Silence, interrupt + school lockout, stun, fear, horror, polymorph, sap, blind, disorient, sleep, mind control, incapacitate, cyclone, other healing-blocking effects, roots (movement only) |
| Countdown | "Healing resumes in 5s / 3s", then "Healer free - healing resumed!" |
| Mana & health | Low mana, out of mana, mana recovered, low health, critical health, drinking, finished drinking |
| Death | Healer died, self-resurrect available (Soulstone/Reincarnation), healer back up |
| Aggro & threat | Aggro, excessive threat, several enemies on the healer, line-of-sight and range failures |

Example: `Healer silenced! (8s)` - `Healing resumes in 3s!` - `Healer free - healing resumed!`

Every alert has: on/off, custom text, channels, repeat cooldown, sound, on-screen warning, PvE/PvP restriction,
threshold (where it applies) and a Test button.

### Countdown rules (default "smart" plan)

| Healing blocked for | Messages |
|---|---|
| under 5s | first alert (recovery optional) |
| 5-9s | first alert, 3s warning, recovery |
| 10s+ | first alert, 5s warning, 3s warning, recovery |

Overlapping effects are one "healing blocked" window that ends with the **last** effect. Recovery is never
announced while something else still stops healing. Early dispels, trinkets and diminishing returns are
handled because the times come from the game itself. Roots never block healing ("healing resumed (still rooted)").

### Channels

Auto, Party, Raid, Instance, Battleground, Say, Yell, Self only - per alert. Never General, Trade or guild.
Raid + Party or Instance + Party only sends once. Crowd control jumps the queue ahead of routine messages;
a global throttle and duplicate filter keep chat clean.

### Profiles

Dungeon, Raid, PvP, Solo (local only), Custom, plus your own. Profiles are account-wide; each character picks one,
or makes a character-only copy. Auto-switch by location (dungeon, raid, battleground, arena, world solo/grouped)
only changes the profile when you move to a different kind of content.

### Display

Movable bars with icon, type, spell, school, caster (when known), remaining time and a
`HEALING BLOCKED 4.2s` header. Scale, opacity, fonts, icon/bar size, colors, rows, lock, out-of-combat visibility,
preview mode.

## Commands

| | |
|---|---|
| `/vmh` | Settings |
| `/vmh test silence\|stun\|interrupt\|countdown\|overlap\|early\|unknown\|mana\|all` | Simulations (local only) |
| `/vmh stop` | End simulations |
| `/vmh preview` | Display preview |
| `/vmh status` | What the game is letting the addon read right now |
| `/vmh debug` / `/vmh debug log` | Local debug messages |
| `/vmh reset confirm` | Reset all settings (statistics kept) |

Simulations run through the real detection, countdown and display, print with a `[SIM]` tag, and never post to a group.

## WoW Forever limits and fallbacks

Forever has no combat log, and can hide values from addons in combat. VoidMark Healer never guesses:

- **Crowd control** comes from Loss of Control data, then your debuffs. If the game hides the duration,
  the alert has no number and the countdown simply waits for the effect to end.
- **Interrupts**: from Loss of Control lockout data. If that is hidden, a lockout is still proven by checking
  whether the interrupted spell is on a cooldown longer than its own; otherwise nothing is announced.
- **Who interrupted / crowd-controlled you**: only when visible (aura caster, or a target/focus/nameplate enemy
  casting an interrupt at you). Turn on enemy nameplates.
- **Mana**: real percentage when readable. When hidden, alerts use whether your own spells are castable
  (costs learned out of combat) and the message leaves the percentage out.
- **Health alerts** pause while health is hidden. Death and resurrection alerts always work.
- **Say / Yell** only work inside instances (game rule). **Group chat lockdown**: messages show locally instead.
- **Line of sight / range** only count failed *helpful* spells (a Mind Blast out of sight is ignored). The name is your
  mouseover or friendly target, so with click-casting it's the frame you clicked.
- **Low/critical health** alerts only fire in combat.
- **Statistics** only count while you're healing.
- **Shadow Priests**: Shadowform counts as "not healing" (set "Announce when: Always" to override).

## Development

```
pip install lupa==2.8
python -X utf8 tests/validate.py      # syntax, TOC, mocked-client regressions
python tools/package.py               # build + verify dist/VoidMarkHealer.zip
```

Tests run against a mocked client (including secret values). They do not replace an in-game check.

## Changes

**1.0.1** - Countdown has its own tab; visible scroll bar on long pages; shorter alert names; plain one-line status on
General (full status via button or `/vmh status`); "Where" renamed "Use in"; Reset lifetime confirm times out; sliders
ignore the mouse wheel so scrolling can't change settings. Fixes: line-of-sight/range no longer fire for damage spells;
one effect is never announced twice when the game hides/unhides values; 10s effects always get the 5s warning;
queued messages are dropped if you leave the group; health alerts only in combat; no aggro alerts while dead;
hidden-mana recovery no longer bounces; every timer and the update loop are error-protected.
