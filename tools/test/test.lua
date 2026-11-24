-- Offline checks for the lure pick and the skill bonus. Run with tools/test/run.py.
local fails = 0
local function check(name, got, want)
  if got == want then log("ok  ", name) else fails = fails + 1; log("FAIL", name, "got", tostring(got), "want", tostring(want)) end
end

fire("ADDON_LOADED", "ForeverFishingUtilities")
fire("PLAYER_ENTERING_WORLD")
flushTimers()

local lure = ForeverFishingUtilitiesLureButton
local function picked()
  fire("BAG_UPDATE_DELAYED")
  local m = lure:GetAttribute("macrotext")
  return m and tonumber(m:match("item:(%d+)"))
end
local function skillText()
  tick()
  for _, f in ipairs(frames) do
    if f.kind == "FontString" and type(f.text) == "string" and f.text:find("Your Skill") then return f.text end
  end
end

-- The example: Recommended 225 (Stranglethorn), skill 200, Bright Baubles + Nightcrawlers.
STATE.bags = { [6532] = 5, [6530] = 5 }
check("200 vs 225: Nightcrawlers (+50) is enough", picked(), 6530)
-- None is enough: the strongest.
STATE.rank = 140
check("140 vs 225: nothing reaches, Bright Baubles", picked(), 6532)
-- A small gap takes the smallest lure.
STATE.zone, STATE.rank = "Hillsbrad Foothills", 140
STATE.bags[6529] = 3
check("140 vs 150: Shiny Bauble", picked(), 6529)
-- Already at Recommended: still the weakest (for smart off or Luremaster).
STATE.rank = 160
check("160 vs 150: Shiny Bauble", picked(), 6529)
-- Equal bonuses: Nightcrawlers before the Fish Lens.
STATE.zone, STATE.rank, STATE.bags = "Stranglethorn Vale", 200, { [6811] = 1, [6530] = 1, [6532] = 1 }
check("tie: Nightcrawlers over Aquadynamic Fish Lens", picked(), 6530)
-- Lures your base skill can't use are skipped (Bright Baubles needs 100).
STATE.rank, STATE.bags = 90, { [6532] = 1, [6529] = 1 }
check("skill 90: Bright Baubles not usable, Shiny Bauble", picked(), 6529)
-- Water with no numbers: the strongest.
STATE.zone, STATE.rank, STATE.bags = "Nowhere Land", 200, { [6532] = 1, [6530] = 1 }
check("unknown water: Bright Baubles", picked(), 6532)
-- The pole's bonus counts toward the need: 200 + 3 pole vs 225 -> Nightcrawlers still,
-- but at 172 + 3 = 175, Nightcrawlers (+50) just reaches 225.
STATE.zone, STATE.rank = "Stranglethorn Vale", 172
TIPS.inv[16] = { "Blump Family Fishing Pole", "Main Hand", "Equip: Increased Fishing +3." }
NOW = NOW + 2 -- the tooltip bonus is re-read at most once a second
check("172 + 3 pole vs 225: Nightcrawlers reaches", picked(), 6530)
TIPS.inv[16] = nil
NOW = NOW + 2
check("172 without the pole bonus: Bright Baubles", picked(), 6532)

-- Your Skill line includes the pole when the API leaves it out.
STATE.rank, STATE.modifier, STATE.bags = 200, 0, {}
TIPS.inv[16] = { "Blump Family Fishing Pole", "Main Hand", "Equip: Increased Fishing +3." }
check("skill line with pole", skillText():match("%(%+%d+ = %d+%)"), "(+3 = 203)")
-- A lure on the pole and a fishing hat add up.
TIPS.inv[16] = { "Blump Family Fishing Pole", "Main Hand", "Fishing Lure (+50 Fishing Skill) (10 min)", "Equip: Increased Fishing +3." }
STATE.inv[1] = 19972
TIPS.inv[1] = { "Lucky Fishing Hat", "Head", "Equip: Increased Fishing +5." }
check("pole + lure + hat", skillText():match("%(%+%d+ = %d+%)"), "(+58 = 258)")
-- Food buff counts too.
TIPS.buff[1] = { "Well Fed", "Fishing skill increased by 10." }
check("plus food", skillText():match("%(%+%d+ = %d+%)"), "(+68 = 268)")
-- When the API already has everything, it isn't counted twice.
STATE.modifier = 68
check("API already has it", skillText():match("%(%+%d+ = %d+%)"), "(+68 = 268)")
-- "Requires Fishing (100)" lines are not a bonus.
STATE.inv[1], TIPS.inv[1], TIPS.buff[1], STATE.modifier = nil, nil, nil, 0
TIPS.inv[16] = { "Big Iron Fishing Pole", "Requires Fishing (100)", "Equip: Increased Fishing +20." }
check("Requires line ignored", skillText():match("%(%+%d+ = %d+%)"), "(+20 = 220)")

-- Learning: Minimum and Recommended stay 95 apart on listed water.
TIPS.inv[16], STATE.modifier, STATE.inv[1] = nil, 0, nil
NOW = NOW + 2
local function thresholds()
  tick()
  for _, f in ipairs(frames) do
    if f.kind == "FontString" and type(f.text) == "string" and f.text:find("Minimum") then
      local plain = f.text:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "")
      return plain:match("Minimum: (%d+)%*?%s+Recommended: (%d+)")
    end
  end
end
local function cast() fire("UNIT_SPELLCAST_CHANNEL_START", "player", "x", 7620); fire("UNIT_SPELLCAST_CHANNEL_STOP", "player", "x", 7620) end
local function getaway() fire("UI_ERROR_MESSAGE", 0, "Your fish got away!") end
STATE.zone, STATE.rank = "Stranglethorn Vale", 112 -- listed 130 / 225
cast()
local mn, fl = thresholds()
check("cast at 112 lowers Minimum to 110", mn, "110")
check("... and Recommended follows to 205", fl, "205")
STATE.rank = 210
cast(); getaway()
mn, fl = thresholds()
check("getaway at 210 raises Recommended to 215", fl, "215")
check("... and Minimum follows to 120", mn, "120")
-- A save from before: only a learned min.
ForeverFishingUtilitiesDB.learned["Stranglethorn Vale"] = { min = 100 }
mn, fl = thresholds()
check("old save min 100 -> Recommended 195", fl, "195")
check("old save min 100 -> Minimum 100", mn, "100")
-- Starter water: Minimum stays at 1 while Recommended rises.
STATE.zone, STATE.rank = "Durotar", 40 -- listed 1 / 25
cast(); getaway()
mn, fl = thresholds()
check("starter getaway at 40 -> Recommended 45", fl, "45")
check("starter Minimum stays 1", mn, "1")
-- Unlisted water keeps its two separate bounds.
STATE.zone, STATE.rank = "Nowhere Land", 90
cast()
STATE.rank = 120
cast(); getaway()
check("unlisted: cast bound kept", ForeverFishingUtilitiesDB.learned["Nowhere Land"].min, 90)
check("unlisted: getaway bound kept", ForeverFishingUtilitiesDB.learned["Nowhere Land"].full, 125)

log(fails == 0 and "ALL PASSED" or (fails .. " FAILED"))
