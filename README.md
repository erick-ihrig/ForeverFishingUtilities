# Zone Fishing Skill

A small fishing companion for **World of Warcraft: Forever**. It shows the Fishing skill your current zone needs and makes fishing a one-key job.

## Features

- **Zone skill window.** Shows your zone and subzone, the skill needed to cast there (**Minimum**), the skill where no fish get away (**Recommended**), and **Your Skill**, including pole and lure bonuses. Subzones with their own requirements are handled too, such as Jademir Lake and Bay of Storms.
- **World map info.** Hover a zone on the world map to see its fishing numbers under the zone name.
- **One-key fishing.** With a fishing pole equipped, Space casts, then clicks the bobber. Without a pole, or in combat, Space jumps as normal. This can be toggled, and a dedicated keybind is also available.
- **Double right-click to cast.**
- **Fishing sound mode.** While fishing, music, ambience, dialog and pet sounds are muted and effects turned up so the splash stands out. Your settings come back afterwards.
- **Best-lure button.** Applies the strongest lure in your bags that your skill can use.
- **Pole / weapon swap.** One click or key swaps between your fishing pole and the weapons you had on, and it works in combat.

## Install

1. Download the latest release.
2. Unzip it into `World of Warcraft\_forever_\Interface\AddOns\`. You should end up with `AddOns\ZoneFishingSkill\ZoneFishingSkill.toc`.
3. Restart the game fully, so the keybinds appear.
4. If you use **Better Fishing**, disable it. Both addons manage the same keys.

## Usage

| Command | What it does |
|---|---|
| `/zfs` | Show or hide the window |
| `/zfs pole` | Only show the window while a fishing pole is equipped |
| `/zfs lock` / `/zfs reset` | Lock the window, or move it back to the top of the screen |
| `/zfs space` | Turn Space fishing on or off (same as the fishing icon) |
| `/zfs sound [0-100]` | Turn fishing sound mode on or off, or set its volume |
| `/zfs dblclick [seconds]` | Turn double right-click casting on or off, or set the click speed |
| `/zfs swapkey <KEY>` | Set the pole/weapon swap key, e.g. `/zfs swapkey CTRL-W` |
| `/zfs keys` | Show which keys are set |
| `/zfs map` | Turn the world map fishing info on or off |
| `/zfs set <min> [recommended]` | Enter your own values for the current subzone, e.g. for new Forever zones |

Keybinds: **Options → Keybindings → AddOns → Zone Fishing Skill** ("Cast and Interact" and "Swap Fishing Pole / Weapons").

## How it works

Some technical details, for the curious:

- **One-key fishing.** The fishing keys are pointed, using override bindings, at a secure action button that casts Fishing. While the cast is up they're re-pointed at the game's *Interact with Target* command, with soft-target interact turned on so the bobber is the target. Override bindings are never saved, are cleared as combat starts, and are restored afterwards.
- **Swap in combat.** Equipment changes from addon code are blocked in combat. The swap button is a secure button: a secure snippet checks `[equipped:Fishing Poles]` at click time and picks the matching `/equipslot` macro, so it swaps the right way even mid-fight.
- **World map.** The addon hooks the map's area-label provider and adds the fishing numbers to the hovered zone's description.
- **Settings safety.** Sound and soft-target settings changed while fishing are cached and restored afterwards, at logout, or at the next login after a crash.

## Data and limitations

- Skill values are the Classic-era zone tables, which WoW Forever guides match so far. Zones new to Forever have no published values yet; use `/zfs set` to add your own.
- Zone lookups use English zone names, so the addon currently works on **English (enUS) clients** only.
- The lure list uses the Classic lures. Lures added in Forever aren't included yet.

## Credits

Made by Erick Ihrig. Built with AI assistance (Claude, by Anthropic).

## License

[MIT](LICENSE)
