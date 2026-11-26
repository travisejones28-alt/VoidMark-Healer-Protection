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
| Aggro & threat | Aggro, excessive threat, several enemies on the healer, line-of-sight failures |

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
| `/vmh world` | Turn open-world use on/off (default: dungeons and raids only) |
| `/vmh debug` / `/vmh debug log` / `/vmh debug clear` | Live debug messages / last 25 saved lines / clear |
| `/vmh reset confirm` | Reset all settings (statistics kept) |

Simulations run through the real detection, countdown and display, print with a `[SIM]` tag, and never post to a group.

## WoW Forever limits and fallbacks

Forever has no combat log, and can hide values from addons in combat. VoidMark Healer never guesses:

- **Crowd control** comes from Loss of Control data, then your debuffs (by spell ID, or by the debuff's tooltip text
  for mob spells). If the game hides the duration,
  the alert has no number and the countdown simply waits for the effect to end.
- **Interrupts**: from Loss of Control lockout data. If that is hidden, a lockout is still proven by checking
  whether the interrupted spell is on a cooldown longer than its own; otherwise nothing is announced.
- **Who interrupted / crowd-controlled you**: only when visible (aura caster, or a target/focus/nameplate enemy
  casting an interrupt at you). Turn on enemy nameplates.
- **Mana**: real percentage when readable. When hidden, alerts use whether your own spells are castable
  (costs learned out of combat) and the message leaves the percentage out.
- **Health alerts** pause while health is hidden. Death and resurrection alerts always work.
- **Say / Yell** only work inside instances (game rule). **Group chat lockdown** (the game blocks addon group chat, e.g. during boss fights): alerts show for you;
  mana/death alerts post once chat unlocks if still true. No addon can bypass this.
- **Line of sight** only counts failed *helpful* spells, in combat, on someone under 50% health (a Mind Blast out of sight is ignored). The name is your
  mouseover or friendly target, so with click-casting it's the frame you clicked.
- **Low/critical health** alerts only fire in combat.
- **Statistics** only count while you're healing.
- **Shadow Priests**: a Shadow talent spec or Shadowform counts as "not healing" (set "Announce when: Always" to override).

## Development

```
pip install lupa==2.8
python -X utf8 tests/validate.py      # syntax, TOC, mocked-client regressions
python tools/package.py               # build + verify dist/VoidMarkHealer.zip
```

Tests run against a mocked client (including secret values). They do not replace an in-game check.

## Changes

**1.1.6** - Two icons on each side of group messages ({star}{star} Low mana {star}{star}). Announcements > Icon style
switches back to one icon before the text.

**1.1.5** - Each kind of alert gets its own raid icon in group chat: skull = aggro / enemies / line of sight,
star = mana and drinking, cross = health and death, diamond = crowd control and countdown, triangle = healing resumed.
Change any alert's icon with the Icon dropdown on its settings (> on its tab). The old all-skull prefix is removed once.

**1.1.4** - No more "VoidMarkHealer has been blocked from an action only available to the Blizzard UI"
after typing a slash command such as `/ginvite`. The addon re-assigned the game's slash-command list
when it loaded, which made every slash command typed afterwards count as the addon's.

**1.1.3** - Quieter and smarter:
- Knows your active talent spec: mostly Shadow points = not healing, so no alerts as Shadow even out of Shadowform
  (Disc/Holy specs alert as before; if talents can't be read, nothing is blocked).
- Dungeon profile: "enemies on you" from 3 (2 is a normal pull); countdown messages only for effects of 8s or more.
  Your existing Dungeon profile is updated once if it was still on the old defaults.
- Aggro must last 2 seconds before it is announced.
- Less background work outside dungeons/raids and during combat mana ticks.

**1.1.2** - Line of sight only alerts in combat, and only when the player you were healing is under 50% health
(adjustable on the alert's settings). If the game hides their health, nothing is announced (reason in the debug log).

**1.1.1** - Sounds off by default (alert sounds and countdown ticks), including existing profiles once. Turn back on
under Visuals & Sounds > Sounds.

**1.1.0** - Taint fix ("VoidMarkHealer has been blocked from an action only available to the Blizzard UI" when using
Guild > Group Invite). The addon no longer touches any Blizzard UI object: own on-screen warning instead of the raid
warning frame, own tooltip instead of GameTooltip, preset color swatches instead of the color picker, and its windows
are no longer added to the Escape list (close with X or /vmh). Tests now fail if any of those objects is touched.

**1.0.9** - Last-resort detection when Forever hides all crowd-control data in combat: if your cheapest heal is greyed
out (not for mana, not dead/mounted/in a form/Shadowform), "Healer can't cast heals!" is announced, with recovery when
it's castable again. Never double-alerts when the real effect is readable. Every Loss of Control event now writes a
snapshot of what the game let the addon read to `/vmh debug log`.

**1.0.8** - Mob crowd control (e.g. Shrieking Banshee's silence) is now caught even when the game hides Loss of
Control data: debuffs not in the spell list are read from their tooltip ("Silenced.", "Stunned.", "Feared."...).
Once per debuff, cached.

**1.0.7** - Out-of-range alert removed entirely (too spammy). Its saved settings are cleaned up.

**1.0.6** - Out of range now whispers the player you were trying to heal ("You're out of my healing range - move
closer!"), 10s cooldown per player, never posted to the group; NPCs and yourself are never whispered. Line of sight
has the same whisper option (off by default). Both whisper texts are editable on the Aggro & Threat tab.

**1.0.5** - Chat lockdown: when the game blocks addon group chat (e.g. boss fights), alerts still show for you;
out of mana, low mana, death and self-res are posted when chat unlocks - only if still true. Crowd control and aggro
are not posted late (they'd be wrong by then).

**1.0.4** - Saved debug trail: every crowd-control sighting (with spell ID and source), every alert and why it was
sent or held back, and any Loss of Control entry the addon ignored. Survives /reload. `/vmh debug log` shows the
last 25 lines, `/vmh debug clear` empties it.

**1.0.3** - Group messages start with the {skull} raid icon by default (Announcements > Message prefix; clear it for none).
Raid-icon codes ({skull}, {cross}, {rt1}-{rt8}...) also work inside any alert text.

**1.0.2** - New "Run in" setting (General tab, account-wide): Dungeons and raids only (default), add battlegrounds/arenas,
or everywhere. Outside those places nothing is detected, shown, announced or counted. `/vmh world` toggles open world on/off.
Simulations and Test buttons still work anywhere.

**1.0.1** - Countdown has its own tab; visible scroll bar on long pages; shorter alert names; plain one-line status on
General (full status via button or `/vmh status`); "Where" renamed "Use in"; Reset lifetime confirm times out; sliders
ignore the mouse wheel so scrolling can't change settings. Fixes: line-of-sight/range no longer fire for damage spells;
one effect is never announced twice when the game hides/unhides values; 10s effects always get the 5s warning;
queued messages are dropped if you leave the group; health alerts only in combat; no aggro alerts while dead;
hidden-mana recovery no longer bounces; every timer and the update loop are error-protected.
