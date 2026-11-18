# Changelog

## Unreleased
- New: auto lure. When your pole has no lure, the cast key puts the best lure from your bags on first; press again to fish. Right-click the lure button (or `/ffu autolure`) to turn it on or off; the button shows the autocast corners while it's on. By default it skips the lure when your skill already reaches the water's Recommended, unless you have the Luremaster Legacy perk (`/ffu autolure smart` or the options to change that). Off by default.
- The sound settings moved to the right-hand column of the options panel.

## 1.2.1
- Fixed: Lua errors ("Auras cannot be accessed when secret") in combat. WoW: Forever hides buffs from addons during a fight, so the food button's glow now keeps its last state until the fight ends.

## 1.2.0
- New: pulled into a fight with your fishing pole out, your weapons go on as combat starts, and the pole comes back when it ends (only if the pole was on when the fight began, and you didn't change weapons yourself). On by default; `/ffu combatswap`.
- New: Minimum and Recommended correct themselves from your own fishing. Cast successfully below a zone's Minimum and it drops to your skill, rounded down to a 5; have a fish get away at or above Recommended and that goes up. The other number keeps its usual gap. Corrected numbers show a grey *. On by default; `/ffu learn`, and `/ffu learn reset` to go back to the listed values.
- New: a training book next to Your Skill. Hover it to see how to learn the next Fishing rank: the closest trainer and the cost (with your reputation discount), the Expert book in Booty Bay, or Nat Pagle's quest for Artisan. It's greyed out until you meet the level and skill needed. Ctrl-click it to put a map pin there.
- New: a food button next to the lure button. It eats the best food in your bags that gives Fishing skill (WoW: Forever added a Fishing bonus to six fish dishes).
- New: every button can be hidden in the options (Space toggle, sound toggle, swap, lure, food, training book). The rest close up.
- Changed: with the pole out, Space now just jumps while you're moving, and casts when you're standing still. The old behaviour (jumping on the move swaps to your weapons) is still an option: `/ffu moving swap`, or in the options. `/ffu moving swap|jump` replaces `/ffu jumpswap`.
- The window's button tooltips now open against the window, on the same side as the catches list.
- The lure and food buttons glow while their buff is up (a lure on your pole, or Well Fed with a Fishing bonus).
- The lure and food buttons sit a little higher, clear of the window's border.
- The pole/weapon swap button moved to the top-right corner, at the far right of the two toggles.
- Your Skill only turns red when you're capped and can learn the next rank now; capped but not high enough level stays white.
- In water with no listed numbers (like Forever's new zones), your casts and getaways now give a rough Minimum ("90 or less") and Recommended ("125+").
- The off-hand of two identical weapons is now filled straight away, even in combat, instead of waiting for combat to end.

## 1.1.0
- New: hover the zone name to see what you can catch there, with icons, names and catch rates. The list is as wide as the window and opens above or below it (`/ffu catches smart|up|down`; smart opens away from the nearer screen edge). Classic items that WoW Forever doesn't have are left out.
- New: on the world map, hold Shift while hovering a zone to add its catches to the fishing tooltip.
- New: with your pole out, jumping while moving swaps back to your weapons (out of combat; `/ffu jumpswap`, on by default).
- The world map fishing tooltip now sits in the map's bottom-left corner instead of following the cursor, out of the way of other addons' tooltips.
- New: an options panel under Options > AddOns > Forever Fishing Utilities (`/ffu options`).
- The three lines in the window are now evenly spaced.
- Your Skill now shows your cap, like 140/225, and turns red when you're capped and can learn the next rank (not at 300, and not before you're high enough level).

## 1.0.1
- Fixed: swapping back to two identical weapons (e.g. two Copper Daggers) now fills the off-hand too. If you swap mid-fight, the off-hand follows as soon as combat ends.

## 1.0.0
First public release.
- Zone skill window: Minimum and Recommended Fishing skill for your zone or subzone, plus your own skill, including pole and lure bonuses.
- World map info: hover any zone to see its fishing numbers (`/ffu map`).
- One-key fishing: Space (or a keybind) casts, then clicks the bobber, while a fishing pole is equipped.
- Optional double right-click casting (`/ffu dblclick`) and fishing sound mode (`/ffu sound`).
- Best-lure button and a pole/weapon swap button (with keybind) that works in combat.

Development history before 1.0.0 is in the Git log.
