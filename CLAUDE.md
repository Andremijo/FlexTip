# FlexTip: notes for Claude

FlexTip is a World of Warcraft addon for **WoW Forever**. It changes the game tooltip (`GameTooltip`):
- moves it to a draggable anchor, the cursor, or Blizzard's default spot
- scales it
- collapses unit tooltips to their first rows
- hides chosen rows: guild, level, class, faction, and so on
- works alongside Questie

The current version is in `FlexTip.toc` (`## Version`). The user-facing docs are in `README.md`.

## Status

- All code has been checked only against the mock in `tests/`. Nobody can run the game here.
- The owner tested 1.1.0 in game and said it "works, with some minor bugs" but never described them. Ask about them.
- Not verified in game yet:
  - Hidden rows might flash for one frame when a tooltip first appears. Row packing runs in OnUpdate.
  - `FitToRows` trims the height after rows are blanked.
  - Questie's lines are spotted from the caller path in `debugstack`. That path format is unconfirmed.
- License: MIT (`LICENSE`, copyright "Andremijo"). `LICENSE` ships in the install zip, as MIT requires; don't mark it export-ignore.

## Target client

- **Forever uses the Mainline (Midnight, 12.x) UI and API**, not the Classic API. Retail addon code applies.
- **Interface number: 16001.** Confirmed from Questie's `Questie_Forever.toc`. The TOC also lists the retail number (`## Interface: 16001, 120105`). In game, check with `/dump select(4, GetBuildInfo())`.
- Forever also loads flavor TOCs named `_Forever.toc` and `_Camelot.toc`. Camelot is Forever's internal name, according to Questie. FlexTip uses a single TOC with a comma-separated Interface line.
- AddOns folder: `World of Warcraft\_forever_\Interface\AddOns\FlexTip`. The folder must be named `FlexTip`.

### Rules the code follows (Midnight restrictions)

- **Secret values.** Some values are "secret" for addons, especially in instances and restricted combat. That includes unit tokens, names, line text, string widths and tooltip data tables.
  - Never test, compare, concatenate or do math on a possibly secret value. Call `issecretvalue(v)` first. Even `a or b` and `if a then` count as tests.
  - Display is fine: `FontString:SetText(secret)` and `AddLine(secret)` work.
  - Unit lookups (`UnitIsPlayer`, `GetGuildInfo`, ...) run inside `pcall`.
- **Taint.**
  - Never write fields onto `GameTooltip` or other Blizzard frames. Per-tooltip state lives in the local `state` table in `Tooltip.lua`.
  - Use `hooksecurefunc` and `HookScript`, never replace Blizzard functions.
  - Calling `Show()` on an already shown tooltip only re-measures it and runs no Lua, so it's the one call we make into the tooltip from hooks.
- Errors in optional features are swallowed by `SafeCall` (pcall). `/ftip debug` prints them.

## Files

| File | Contents |
|---|---|
| `FlexTip.toc` | Interface, version, SavedVariables (`FlexTipDB`), load order, `AddonCompartmentFunc` |
| `Core.lua` | Defaults, choices, ranges, `InitDB` (merges and sanitizes saved data), `FT:Set`, `FT:SetRow`, `ApplyAll`, slash commands, key binding globals, events |
| `Tooltip.lua` | Everything that touches `GameTooltip`: anchoring, scale, appearance, health bar, unit decorations, rows, collapse, quest rows, Questie detection, hooks, preview |
| `Mover.lua` | The draggable anchor box and its scale grip |
| `Options.lua` | The options window (`/ftip`), 3 columns (the third is "What tooltips show"), and a small entry under Options > AddOns |
| `Bindings.xml` | Key bindings: toggle collapse, lock or unlock, open options |
| `tests/` | WoW API mock, Questie mock, tests, `run.sh` |
| `.github/workflows/release-zip.yml` | Builds `FlexTip-Forever.zip` and attaches it to each published release (see Releasing) |
| `docs/` | `rows.png`, the README illustration, plus its source `illustration.html` and `render.js`. Regenerate with `node docs/render.js` (needs Playwright). It's labeled as an illustration because nobody could take in-game screenshots here. Swap in real screenshots if the owner provides some, using made-up or the owner's own character names only. |

## How it works

### Anchoring
- FlexTip post-hooks `GameTooltip_SetDefaultAnchor(tooltip, parent)`.
  - A parent of `UIParent`, `WorldFrame` or nil means a world tooltip (units and objects).
  - Anything else means a UI tooltip (unit frames, action bars).
- Each kind has a mode setting (`worldAnchor`, `frameAnchor`):
  - `MOVER` pins the tooltip's `anchorPoint` corner to the same corner of the anchor box.
  - `CURSOR` follows the cursor in OnUpdate, using `cursorPoint`, `cursorX` and `cursorY`.
  - `DEFAULT` leaves the tooltip alone (Edit Mode position).
- A hook on `GameTooltip:SetOwner` resets the per-show state, so tooltips anchored any other way are never moved.

### Anchor box (Mover.lua)
- An unnamed frame, so the game's layout cache doesn't save its position.
- The position is saved relative to the screen corner that matches `anchorPoint`. Changing `anchorPoint` re-saves it, so the box stays put.
- The scale grip sits in the corner opposite the pinned corner. The mouse wheel also scales.
- Right-click locks. A click without dragging shows a preview (`SetUnit("player")`).

### Scale
Applies to `GameTooltip`, `ShoppingTooltip1` and `ShoppingTooltip2`.

### Rows and collapse (the core of Tooltip.lua)
1. The Unit post-call (`TooltipDataProcessor.AddTooltipPostCall`) decorates the tooltip and sets `state.pending`. Decorating means class colors and the optional "Target:" row.
2. On the next OnUpdate, after every addon's post-call has run, `FT:UpdateRows` snapshots each line: left and right text, colors, word wrap, and row **kind**.
3. `Render` decides per entry: hidden, its own text, or a **shortened text** (see "Parts of rows"). It re-runs when `FT.settingsVersion` changes (bumped by `ApplyAll`) or the full-tooltip key goes up or down.
4. It writes back only the rows that should show, **packed to the top**, and blanks the rest. `written[j]` records which snapshot entry line `j` shows (0 means blank) and `writtenStamp[j]` which rendering of it, so lines are only rewritten when something changes.
5. `FitToRows` trims the height in case the game reserves space for blank lines.
6. Lines added later, for example by inspect-based addons, are noticed when `NumLines()` grows and are captured on the next frame.

The row kinds come from `Classify`:
- `name` is always line 1 and always shown.
- `target` is FlexTip's own row.
- `questgiver` is a Questie row with one of Questie's quest icons (`Questie\Icons\` in the text): a quest this NPC starts or ends.
- `quest` is any other Questie row (objective titles and progress), or one of the game's quest rows.
- `guild` is matched with `GetGuildInfo`.
- `level` is matched with the prefix from `TOOLTIP_UNIT_LEVEL`.
- `class` is the localized class name on its own row.
- `faction` is matched with `UnitFactionGroup` and `FACTION_*`.
- `pvp` is matched with `PVP`.
- `title` is line 2 on an NPC tooltip.
- `other` is anything else.
- `unknown` covers secret text, or no unit to compare with. These rows always show.

### Parts of rows
`db.rows` has one switch per part. Some rows are shortened instead of hidden:
- **Name** (`realm`, `playerTitle`): `RenderName` replaces `UnitPVPName` with the plain name, and drops `-Realm` and `FOREIGN_SERVER_LABEL`.
- **Guild** (`guild` hides the row, `guildRank`): `RenderGuild` shows just the guild name when the rank is in the row.
- **Level row** (`level`, `race`, plus `class` when the class is on this row): `RenderLevel` rebuilds the row from the parts that stay. The level comes from the number in the row, formatted with `TOOLTIP_UNIT_LEVEL`. The race is `UnitRace` for players and `UnitCreatureType` for NPCs. With every part off, the row is hidden.
- Secret rows are never shortened; they show in full if their row is on.
- `InitDB` migrates 1.2.0 settings: old `level = false` sets `race = false`, and old `quest = false` sets `questGivers = false`.

Collapse keeps the first `collapseLines` rows that pass the row filter. Quest rows (both kinds) don't count toward that limit while `collapseKeepsQuests` is on. Holding `expandModifier` (Shift by default) shows every row as the game wrote it, hidden and shortened ones included.

### Questie support (findings from Questie's source, Nov 2026)
- On Forever, Questie works like this:
  - It adds NPC quest rows in its own Unit post-call.
  - It hides the game's readable quest rows with `TooltipDataProcessor.AddLinePreCall`, which returns true.
  - Inside instances it re-adds the game's rows with possibly secret text, and objective rows wrap.
  - It only re-adds its lines when the game rebuilds the tooltip (its `CountTooltip` check). There's no OnUpdate re-adding on Forever, so FlexTip's blanking can't make it duplicate lines.
  - Its map-icon tooltips use `ANCHOR_CURSOR`, so FlexTip doesn't move them.
- When Questie is loaded, FlexTip post-hooks `GameTooltip:AddLine` and `AddDoubleLine`.
  - The first stack frame from `debugstack` that isn't `[C]` and isn't FlexTip's own code is checked for a `/Questie/` path. If it matches, `questieLines[index]` is set. This works for secret text.
  - `questieLines` is reset on OnTooltipCleared, SetOwner and OnHide, not in `EndUnit`, because Questie's post-call can run before FlexTip's.
- Without Questie, the game's own quest rows are recognized from the post-call `data.lines`: entries of type QuestTitle, QuestObjective and QuestPlayer.
- A row's word wrap is copied along when it moves (`CanWordWrap`/`SetWordWrap`).

### Other features
- **Appearance:** the class-colored border and the background opacity use `GameTooltip.NineSlice`. The original colors are saved and restored on hide. `bgAlpha` of 1 means "leave Blizzard's background alone".
- **Hide in combat:** done in the OnShow hook and on `PLAYER_REGEN_DISABLED`. The modes are NEVER, WORLD and ALL.

## Settings

- `FT.defaults` in `Core.lua` is the source of truth.
- Always change settings through `FT:Set(key, value)` or `FT:SetRow(row, shown)`. Both validate the value and call `ApplyAll`.
- `InitDB` fills in new keys, including new keys inside nested tables such as `rows`, so old saved settings keep working.
- To add a setting:
  1. Add it to `defaults`.
  2. Add a range to `RANGES` or a choice list to `CHOICES` if it needs one.
  3. Add a widget in `Options.lua`.
  4. Add tests.

## Development

```bash
apt-get install -y lua5.1 lua-check   # once per environment
tests/run.sh                          # luacheck + every tests/test_*.lua
```

- `tests/mock.lua` is a small WoW API mock, not a faithful client.
  - It marks values secret by value (`M.secret[text] = true`), so every equal string becomes secret for the rest of a test run.
  - Its tooltip layout leaves 2px for each blank line, the worst case.
  - Unit tooltips are built from `M.units` through tooltip data, line pre-calls and post-calls, like the game does.
- `tests/questie_mock.lua` copies Questie's Forever tooltip behavior listed above.
- When fixing or adding behavior, add a test. Then break the code on purpose to check that the test catches it.
- Install zip: always named **`FlexTip-Forever.zip`** (the owner's choice), with a `FlexTip/` folder inside, because WoW needs that folder name. Build it from the release commit, outside the repo folder so it never gets committed:
  ```bash
  git archive --format=zip --prefix=FlexTip/ -o /path/outside/repo/FlexTip-Forever.zip HEAD
  ```
  `.gitattributes` marks the dev files `export-ignore`, so the zip holds only the addon, README and LICENSE.
- Releasing a new version:
  1. Bump `## Version` in `FlexTip.toc` and the fallback version string in `Core.lua`.
  2. Push, and write release notes for the owner.
  3. The owner publishes the release in GitHub's web UI, with a new tag `vX.Y.Z` on `main` and the notes. A Claude session can't push tags or create releases (GitHub refuses both for this session type).
  4. The `Release zip` workflow then runs on its own:
     - It checks that `FlexTip.toc` has the tag's version, and fails if not.
     - It runs `tests/run.sh`.
     - It builds `FlexTip-Forever.zip` and attaches it to the release, replacing an older copy.
  5. For a release that already exists, the owner can start the workflow from Actions > Release zip > Run workflow, with the tag.
  - The README's install steps link to the latest release.
- `docs/rows.png` must match real behavior: `tests/test_parts.lua` checks the exact tooltips it shows. Change both together.
- The session's GitHub access can push branches only. Repository settings (description, topics), tags and releases are refused; the owner does those on GitHub.
- This is a public repo:
  - Commit with the account's GitHub noreply address, never a personal email.
  - Never commit tokens, personal data or session links in files.

## Ideas not done yet

- A font size option.
- Scaling `ItemRefTooltip` (clicked chat links).
- A CI workflow that runs `tests/run.sh`.
