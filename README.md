# Forever Fishing Utilities

A small fishing companion for **World of Warcraft: Forever**. It shows the Fishing skill your current zone needs and makes fishing a one-key job.

## Features

- **Zone skill window.** Shows your zone and subzone, the skill needed to cast there (**Minimum**), the skill where no fish get away (**Recommended**), and **Your Skill**, including pole and lure bonuses. Subzones with their own requirements are handled too, such as Jademir Lake and Bay of Storms.
- **World map info.** Hover any zone on the world map to see its fishing numbers, including special bodies of water like Jademir Lake.
- **One-key fishing.** With a fishing pole equipped, Space casts, then clicks the bobber. Without a pole, or in combat, Space jumps as normal. This can be toggled, and a dedicated keybind is also available.
- **Double right-click to cast** (optional, off by default).
- **Fishing sound mode** (optional, off by default). While fishing, music, ambience, dialog and pet sounds are muted and effects turned up so the splash stands out. Your settings come back afterwards.
- **Best-lure button.** Applies the strongest lure in your bags that your skill can use.
- **Fishing food button.** Eats the best food in your bags that gives Fishing skill.
- **Pole / weapon swap.** One click or key swaps between your fishing pole and the weapons you had on, and it works in combat. Pulled into a fight with the pole out? Your weapons go on automatically, and the pole comes back afterwards.
- **Training help.** A book next to Your Skill shows how to learn the next Fishing rank: the closest trainer and the cost, the Expert book, or the Artisan quest. Ctrl-click it for a map pin.

## Install

1. Download the latest release.
2. Unzip it into `World of Warcraft\_forever_\Interface\AddOns\`. You should end up with `AddOns\ForeverFishingUtilities\ForeverFishingUtilities.toc`.
3. Restart the game fully, so the keybinds appear.
4. If you use **Better Fishing**, disable it. Both addons manage the same keys.

## Usage

| Command | What it does |
|---|---|
| `/ffu` | Show or hide the window |
| `/ffu pole` | Switch between showing the window only with a fishing pole equipped (default) and always showing it |
| `/ffu lock` | Lock the window in place |
| `/ffu reset` | Move the window back to its default spot, centred near the top of the screen |
| `/ffu space` | Turn Space fishing on or off (same as the fishing icon) |
| `/ffu dblclick` | Turn double right-click casting on or off |
| `/ffu combatswap` | Swap to your weapons when combat starts, and back to the pole when it ends (on by default) |
| `/ffu learn [reset]` | Correct Minimum/Recommended from your own casts and getaways (on by default); `reset` clears the corrections |
| `/ffu moving [swap\|jump]` | What jumping while moving with the pole out does: swap to your weapons (default) or just jump |
| `/ffu map` | Turn the world map fishing info on or off (on by default) |
| `/ffu sound [0-100]` | Turn fishing sound mode on or off, or set its volume |
| `/ffu catches [smart\|up\|down]` | Turn the catches list (hover the zone name) on or off, or choose where it opens |
| `/ffu options` | Open the options panel (also under Options > AddOns) |

Type `/ffu help` to see the commands and whether each option is on.

Keybinds: **Options → Keybindings → AddOns → Forever Fishing Utilities** ("Cast and Interact" and "Swap Fishing Pole / Weapons").

## How it works

Some technical details, for the curious:

- **One-key fishing.** The fishing keys are pointed, using override bindings, at a secure action button that casts Fishing. While the cast is up they're re-pointed at the game's *Interact with Target* command, with soft-target interact turned on so the bobber is the target. Override bindings are never saved, are cleared as combat starts, and are restored afterwards.
- **Swap in combat.** Equipment changes from addon code are blocked in combat. The swap button is a secure button: a secure snippet checks `[equipped:Fishing Poles]` at click time and picks the matching `/equipslot` macro, so it swaps the right way even mid-fight.
- **World map.** While the map is open, the addon works out which zone is under the cursor with `C_Map.GetMapInfoAtPosition` and shows that zone's numbers in a small tooltip.
- **Settings safety.** Sound and soft-target settings changed while fishing are cached and restored afterwards, at logout, or at the next login after a crash.

## Data and limitations

- Skill values are bundled in `Data.lua`, taken from the Classic-era zone tables, which WoW Forever guides match so far. Zones new to Forever have no published values yet. (Addons can't access the internet, so the data has to ship with the addon.)
- Zone lookups use English zone names, so the addon currently works on **English (enUS) clients** only.
- Catch lists and rates are bundled in `Drops.lua`, generated from the open-source cMaNGOS Classic database (github.com/cmangos/classic-db) by `tools/update_drops.py`, which also checks that source for changes. They cover open water only, not fishing pools, and they're Classic-era values that may differ on Forever.
- Minimum and Recommended correct themselves from your own fishing: a successful cast below the Minimum lowers it, and a getaway at or above Recommended raises that (marked with a grey *).
- Trainer locations, costs and requirements are in `Training.lua`, from WoW Forever trainer guides. The 10% discount at Honored follows the Classic rule.
- The lure list uses the Classic lures. Lures added in Forever aren't included yet.

## Credits

Made by Erick Ihrig. Built with AI assistance (Claude, by Anthropic).

## License

[MIT](LICENSE)
