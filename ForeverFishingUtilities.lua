-- Forever Fishing Utilities
-- A small window for where you stand: the Fishing skill needed to cast here
-- (Minimum, orange), the skill where no fish get away (Recommended, yellow),
-- and your own skill. Buttons: Space fishing and sound mode (top right),
-- pole/weapon swap and best lure (bottom right).
-- Also: one-key fishing (Space or a keybind casts, then clicks the bobber),
-- optional double right-click casting, optional fishing sound mode, and
-- fishing numbers when hovering zones on the world map.

local ADDON, ns = ...

local FISHING_SKILLLINE = 356
local FISHING_SPELL = 7620

local COLOR = {
    red    = "|cffff2020",
    orange = "|cffff8040",
    yellow = "|cffffff00",
    green  = "|cff40c040",
    grey   = "|cff9d9d9d",
    white  = "|cffffffff",
}

local DEFAULTS = {
    shown = true,
    poleOnly = true,      -- only show the window with a fishing pole equipped
    locked = false,
    point = { "TOP", "UIParent", "TOP", 0, -120 },
    spaceOn = true,       -- Space casts and interacts while a pole is equipped (jumps otherwise)
    doubleClick = false,  -- double right-click casts (opt-in)
    sound = false,        -- quiet everything but effects while fishing (opt-in)
    mapTip = true,        -- fishing numbers when hovering zones on the world map
    volume = 1,           -- master volume while fishing
    dropTip = true,       -- list of catches when hovering the zone name
    flyout = "smart",     -- where that list opens: "smart", "up" or "down"
    moving = "jump",      -- jump while moving with the pole out: just "jump", or "swap" to weapons
    showSpace = true,     -- which buttons the window shows
    showSound = true,
    showSwap = true,
    showLure = true,
    showFood = true,
    showBook = true,
    autoLure = false,     -- the cast key puts a lure on first when the pole has none
    autoLureSmart = true, -- ...but not when you're already at Recommended (unless you have Luremaster)
    combatSwap = true,    -- entering combat with the pole out swaps to weapons, and back after
    learn = true,         -- adjust Minimum/Recommended from your own casts and getaways
}

local db
local RegisterOptions -- defined with the options panel, further down
local JumpSwap        -- defined with the swap button, further down

---------------------------------------------------------------------------
-- Lookups
---------------------------------------------------------------------------

local function FishingName()
    if C_Spell and C_Spell.GetSpellName then
        local n = C_Spell.GetSpellName(FISHING_SPELL)
        if n then return n end
    end
    if GetSpellInfo then
        local n = GetSpellInfo(FISHING_SPELL)
        if n then return n end
    end
    return "Fishing"
end

-- The Fishing bonus read from tooltips: equipped items (the pole, its lure,
-- hats, gloves and so on) and a Well Fed buff. On Forever the skill APIs
-- below leave at least the pole's bonus out (seen with the Blump Family
-- Fishing Pole), so GetFishingSkill takes whichever total is bigger.
local TooltipFishingBonus
do
    local tip, gear, food, scannedAt = nil, 0, 0, nil
    local function LineBonus(text, word)
        if type(text) ~= "string" or not text:find(word, 1, true) or text:find("^Requires") then return 0 end
        local n = text:match("%+(%d+)") or (text:find("^Equip:") and text:match("(%d+)"))
        return tonumber(n) or 0
    end
    local function ScanLines(word, first)
        local sum = 0
        for line = 2, tip:NumLines() or 0 do
            local fs = _G["ForeverFishingUtilitiesGearTipTextLeft" .. line]
            local n = LineBonus(fs and fs:GetText(), word)
            if n > 0 then
                if first then return n end
                sum = sum + n
            end
        end
        return sum
    end
    local function Scan()
        tip = tip or CreateFrame("GameTooltip", "ForeverFishingUtilitiesGearTip", nil, "GameTooltipTemplate")
        local word = FishingName()
        local total = 0
        for slot = 1, 19 do
            if GetInventoryItemID("player", slot) then
                tip:SetOwner(WorldFrame, "ANCHOR_NONE")
                tip:ClearLines()
                tip:SetInventoryItem("player", slot)
                total = total + ScanLines(word)
            end
        end
        gear = total
        -- Buffs are secret in combat on Forever; keep the last value then.
        local secret = InCombatLockdown() or (C_Secrets and C_Secrets.ShouldAurasBeSecret and C_Secrets.ShouldAurasBeSecret())
        if not secret then
            local buff = 0
            for i = 1, 40 do
                local name
                if C_UnitAuras and C_UnitAuras.GetBuffDataByIndex then
                    local aura = C_UnitAuras.GetBuffDataByIndex("player", i)
                    name = aura and aura.name
                elseif UnitBuff then
                    name = UnitBuff("player", i)
                end
                if not name then break end
                tip:SetOwner(WorldFrame, "ANCHOR_NONE")
                tip:ClearLines()
                tip:SetUnitBuff("player", i)
                for line = 2, tip:NumLines() or 0 do
                    local fs = _G["ForeverFishingUtilitiesGearTipTextLeft" .. line]
                    local text = fs and fs:GetText()
                    if type(text) == "string" and text:find(word, 1, true) then
                        buff = buff + (tonumber(text:match("(%d+)")) or 0)
                        break
                    end
                end
            end
            food = buff
        end
    end
    function TooltipFishingBonus()
        if not scannedAt or GetTime() - scannedAt >= 1 then
            scannedAt = GetTime()
            pcall(Scan)
        end
        return gear + food
    end
end

-- Returns base rank, bonus (pole, lure, gear, food) and current cap, or nil if Fishing isn't learned.
local function GetFishingSkill()
    local rank, bonus, maxRank
    if GetProfessions and GetProfessionInfo then
        local _, _, _, fishing = GetProfessions()
        if fishing then
            local _, _, r, m, _, _, skillLine, modifier = GetProfessionInfo(fishing)
            if r and (skillLine == nil or skillLine == FISHING_SKILLLINE) then
                rank, bonus, maxRank = r, modifier or 0, m
            end
        end
    end
    if not rank and GetNumSkillLines and GetSkillLineInfo then
        local name = FishingName()
        for i = 1, GetNumSkillLines() do
            local skillName, isHeader, _, r, temp, modifier, m = GetSkillLineInfo(i)
            if not isHeader and skillName == name then
                rank, bonus, maxRank = r, (modifier or 0) + (temp or 0), m
                break
            end
        end
    end
    if not rank then return nil end
    return rank, math.max(bonus, TooltipFishingBonus()), maxRank
end

local function HasPoleEquipped()
    local id = GetInventoryItemID("player", 16)
    if not id then return false end
    local info = (C_Item and C_Item.GetItemInfoInstant) or GetItemInfoInstant
    if not info then return false end
    local _, _, _, _, _, classID, subclassID = info(id)
    return classID == 2 and subclassID == 20
end

-- Finds the data for where you stand. Subzone first, then zone.
-- Returns the entry and the name it matched.
local function Lookup()
    local zone = GetRealZoneText() or ""
    local sub = GetSubZoneText() or ""
    if sub ~= "" and ns.SUBZONES[sub] then return ns.SUBZONES[sub], sub end
    return ns.ZONES[zone], zone
end

-- Minimum and Recommended corrected by your own fishing (db.learned[name]):
-- a cast that lands below the listed Minimum lowers it, and a fish getting away
-- at or above the listed Recommended raises that. A value that hasn't been
-- corrected keeps the original gap to the one that has.
local function Effective(entry, key)
    local learned = key and db and db.learn and db.learned and db.learned[key]
    if not learned then return entry end
    if not entry then
        -- No listed numbers here: show what your own fishing has shown.
        if not (learned.min or learned.full) then return nil end
        return { min = learned.min, full = learned.full, guessed = true,
            learnedMin = learned.min ~= nil, learnedFull = learned.full ~= nil }
    end
    local gap = entry.full - entry.min
    local min, full = entry.min, entry.full
    if learned.min and learned.full then
        min, full = learned.min, math.max(learned.full, learned.min)
    elseif learned.min then
        min, full = learned.min, learned.min + gap
    elseif learned.full then
        min, full = math.max(1, learned.full - gap), learned.full
    end
    return { min = min, full = full, learnedMin = learned.min ~= nil, learnedFull = learned.full ~= nil }
end

local fishingActive = false

local function IsFishingSpell(spellID)
    if not spellID then return false end
    local name
    if C_Spell and C_Spell.GetSpellName then
        name = C_Spell.GetSpellName(spellID)
    elseif GetSpellInfo then
        name = GetSpellInfo(spellID)
    end
    return name ~= nil and name == FishingName()
end

---------------------------------------------------------------------------
-- Window
---------------------------------------------------------------------------

local frame = CreateFrame("Frame", "ForeverFishingUtilitiesFrame", UIParent, "BackdropTemplate")
frame:SetSize(220, 40)
frame:SetFrameStrata("MEDIUM")
frame:SetClampedToScreen(true)
frame:SetMovable(true)
frame:EnableMouse(true)
frame:RegisterForDrag("LeftButton")
frame:SetBackdrop({
    bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
    edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
    tile = true, tileSize = 16, edgeSize = 12,
    insets = { left = 3, right = 3, top = 3, bottom = 3 },
})
frame:SetBackdropColor(0, 0, 0, 0.75)
frame:SetBackdropBorderColor(0.4, 0.4, 0.4, 1)
frame:Hide()

frame:SetScript("OnDragStart", function(self)
    if not db.locked and not InCombatLockdown() then self:StartMoving() end
end)
frame:SetScript("OnDragStop", function(self)
    self:StopMovingOrSizing()
    local p, _, rp, x, y = self:GetPoint()
    db.point = { p, "UIParent", rp, x, y }
end)

local line1 = frame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
line1:SetPoint("TOPLEFT", 8, -7)
line1:SetPoint("TOPRIGHT", -46, -7)
line1:SetJustifyH("LEFT")
line1:SetWordWrap(false)

local line2 = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
line2:SetPoint("TOPLEFT", line1, "BOTTOMLEFT", 0, -6)
line2:SetPoint("RIGHT", -8, 0)
line2:SetJustifyH("LEFT")

local lineSkill = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
lineSkill:SetPoint("TOPLEFT", line2, "BOTTOMLEFT", 0, -6) -- same gap as above line 2
lineSkill:SetJustifyH("LEFT")
lineSkill:SetWordWrap(false)

line2:SetWordWrap(false)

-- Which way lists and tooltips open from the window: db.flyout, where
-- "smart" opens away from whichever of the top and bottom screen edges is nearer.
local function FlyoutDirection()
    local dir = db and db.flyout
    if dir == "up" or dir == "down" then return dir end
    local _, y = frame:GetCenter()
    local scale = frame:GetEffectiveScale() / UIParent:GetEffectiveScale()
    return (y and y * scale > UIParent:GetHeight() / 2) and "down" or "up"
end

-- The window's button tooltips sit against the window, where the catches
-- list opens, and are at least as wide as it.
local function WindowTip()
    local tip = GameTooltip
    tip:SetOwner(frame, "ANCHOR_NONE")
    tip:ClearAllPoints()
    if FlyoutDirection() == "down" then
        tip:SetPoint("TOPLEFT", frame, "BOTTOMLEFT", 0, -2)
    else
        tip:SetPoint("BOTTOMLEFT", frame, "TOPLEFT", 0, 2)
    end
    if tip.SetMinimumWidth then tip:SetMinimumWidth(frame:GetWidth()) end
    return tip
end

local function HideWindowTip()
    GameTooltip:Hide()
    if GameTooltip.SetMinimumWidth then GameTooltip:SetMinimumWidth(0) end
end

-- Training book just right of "Your Skill": hover it for how to learn the
-- next Fishing rank. Greyed until you meet that rank's requirements.
local trainIcon = CreateFrame("Button", nil, frame)
trainIcon:SetSize(13, 13)
trainIcon:SetPoint("LEFT", lineSkill, "RIGHT", 4, 0)
local trainTex = trainIcon:CreateTexture(nil, "ARTWORK")
trainTex:SetAllPoints()
trainTex:SetTexture("Interface\\Icons\\INV_Misc_Book_09")
trainTex:SetTexCoord(0.08, 0.92, 0.08, 0.92)

-- How many buttons sit in the top-right and bottom-right corners, and
-- whether the training book shows (set by LayoutButtons).
local topCount, bottomCount, bookShown = 3, 2, true

-- Sizes the window to fit its lines.
local function Fit(lines)
    local w = 160
    local line1Room = 10 + 6 + 20 * topCount
    local skillRoom = 14 + 20 * bottomCount + (bookShown and 18 or 0)
    for _, fs in ipairs(lines) do
        w = math.max(w, fs:GetStringWidth() + ((fs == line1 and line1Room) or (fs == lineSkill and skillRoom) or 18))
    end
    frame:SetWidth(w)
    frame:SetHeight(20 + 14 * #lines) -- a little extra so the corner buttons clear line 2
end

-- True when skill is stuck at its cap AND the next rank can be learned now
-- (level and skill met). Capped but not able to train yet stays white.
local function NeedsNextRank(rank, maxRank)
    if not maxRank or maxRank <= 0 or rank < maxRank then return false end
    for _, r in ipairs(ns.RANKS) do
        if r.from == maxRank then
            return UnitLevel("player") >= r.level and rank >= r.skill
        end
    end
    return false -- top rank
end

-- "Your Skill: 140/225", red when capped and the next rank is learnable.
local function SkillText()
    local rank, bonus, maxRank = GetFishingSkill()
    if not rank then
        return "Your Skill: " .. COLOR.grey .. "not learned|r"
    end
    local color = NeedsNextRank(rank, maxRank) and COLOR.red or COLOR.white
    local text = "Your Skill: " .. color .. rank
    if maxRank and maxRank > 0 then text = text .. "/" .. maxRank end
    text = text .. "|r"
    if bonus and bonus ~= 0 then
        text = text .. COLOR.grey .. "  (" .. (bonus > 0 and "+" or "") .. bonus ..
            " = " .. (rank + bonus) .. ")|r"
    end
    return text
end

-- "Minimum: 55   Recommended: 150" in orange and yellow.
-- A grey * marks a number corrected by your own fishing.
local LEARNED_MARK = COLOR.grey .. "*|r"
-- In water with no listed numbers, your fishing only gives limits: a cast
-- that landed means the Minimum is at most that; a getaway means
-- Recommended is at least the next 5 up.
local function MinText(e)
    if not e.min then return "?" end
    return (e.guessed and (e.min .. " or less") or e.min) .. "|r" .. (e.learnedMin and LEARNED_MARK or "")
end
local function FullText(e)
    if not e.full then return "?" end
    return (e.guessed and (e.full .. "+") or e.full) .. "|r" .. (e.learnedFull and LEARNED_MARK or "")
end
local function Thresholds(entry)
    return COLOR.orange .. "Minimum: " .. MinText(entry) .. "   " ..
        COLOR.yellow .. "Recommended: " .. FullText(entry)
end

---------------------------------------------------------------------------
-- Training: the book next to Your Skill
---------------------------------------------------------------------------

local UpdateTrainIcon
do
-- The next rank to learn, or nil at the top rank.
local function NextRank()
    local rank, _, maxRank = GetFishingSkill()
    for _, r in ipairs(ns.RANKS) do
        if (not rank and r.from == nil) or (rank and r.from == maxRank) then return r, rank or 0 end
    end
end

local function RankReady(r, skill)
    return UnitLevel("player") >= r.level and skill >= r.skill
end

-- Honored or better with the faction: 10% off (the Classic rule).
local function Discounted(cost, repID)
    if not repID then return cost, nil end
    local standing, name
    if C_Reputation and C_Reputation.GetFactionDataByID then
        local data = C_Reputation.GetFactionDataByID(repID)
        if data then standing, name = data.reaction, data.name end
    end
    if not standing and GetFactionInfoByID then
        local n, _, s = GetFactionInfoByID(repID)
        name, standing = n, s
    end
    if standing and standing >= 6 then return math.floor(cost * 0.9), name end
    return cost, nil
end

-- Gold, silver and copper with the little coin icons.
local COIN = "|TInterface\\MoneyFrame\\UI-%sIcon:0:0:2:0|t"
local function Money(copper)
    local g, s, c = math.floor(copper / 10000), math.floor(copper / 100) % 100, copper % 100
    local parts = {}
    if g > 0 then parts[#parts + 1] = g .. COIN:format("Gold") end
    if s > 0 then parts[#parts + 1] = s .. COIN:format("Silver") end
    if c > 0 or #parts == 0 then parts[#parts + 1] = c .. COIN:format("Copper") end
    return table.concat(parts, " ")
end

local function MapName(mapID)
    local info = C_Map and C_Map.GetMapInfo and C_Map.GetMapInfo(mapID)
    return info and info.name
end

-- World position of a map point, for distances. Nil if the client can't say.
local function WorldPos(mapID, x, y)
    if not (C_Map and C_Map.GetWorldPosFromMapPos and CreateVector2D) then return nil end
    local ok, instance, pos = pcall(C_Map.GetWorldPosFromMapPos, mapID, CreateVector2D(x / 100, y / 100))
    if not ok or not pos then return nil end
    local a, b = pos:GetXY()
    return instance, a, b
end

-- The closest trainer you can use. Falls back to one in your zone, then the
-- first one listed for your side, when positions aren't available.
local function NearestTrainer()
    local side = UnitFactionGroup("player")
    side = (side == "Alliance" and "A") or (side == "Horde" and "H") or "N"
    local py, px, _, pInstance
    if UnitPosition then py, px, _, pInstance = UnitPosition("player") end
    local zone = GetRealZoneText() or ""
    local best, bestDist, inZone, first
    for _, t in ipairs(ns.TRAINERS) do
        if t.side == "N" or t.side == side then
            first = first or t
            if not inZone and t.place:find(zone, 1, true) and zone ~= "" then inZone = t end
            if py then
                local instance, a, b = WorldPos(t.map, t.x, t.y)
                if instance and instance == pInstance then
                    local d = (a - py) ^ 2 + (b - px) ^ 2
                    if not bestDist or d < bestDist then best, bestDist = t, d end
                end
            end
        end
    end
    return best or inZone or first, best ~= nil
end

local function Requirement(tip, label, have, need)
    local ok = have >= need
    tip:AddDoubleLine(label, need, 0.8, 0.8, 0.8, ok and 0.25 or 1, ok and 1 or 0.25, ok and 0.25 or 0.25)
end

local function AddCost(tip, cost, repID)
    tip:AddDoubleLine("Cost", Money((Discounted(cost, repID))), 0.8, 0.8, 0.8, 1, 1, 1)
end

local function Where(tip, place, mapID, x, y)
    tip:AddLine(place .. string.format(" (%.1f, %.1f)", x, y), 1, 1, 1, true)
end

trainIcon:SetScript("OnEnter", function(self)
    local tip = GameTooltip
    WindowTip()
    local r, skill = NextRank()
    if not r then
        tip:SetText("Fishing training")
        tip:AddLine("You have the highest Fishing rank.", 1, 1, 1, true)
        tip:Show()
        return
    end
    tip:SetText((r.from and "Next rank: " or "Learn Fishing: ") .. r.name .. " Fishing")
    tip:AddLine(r.from and ("Raises your skill cap to " .. r.cap .. ".") or "Lets you fish, up to skill 75.", 0.8, 0.8, 0.8, true)
    tip:AddLine(" ")
    if r.level > 1 then Requirement(tip, "Character level", UnitLevel("player"), r.level) end
    if r.skill > 0 then Requirement(tip, "Fishing skill", skill, r.skill) end
    if r.how == "trainer" then
        local t, nearest = NearestTrainer()
        if t then
            tip:AddLine(" ")
            tip:AddLine((nearest and "Closest trainer: " or "Trainer: ") .. t.name, 1, 0.82, 0)
            Where(tip, t.place, t.map, t.x, t.y)
            AddCost(tip, r.cost, t.rep)
            if not nearest then
                tip:AddLine("Any Fishing trainer teaches it.", 0.5, 0.5, 0.5, true)
            end
        end
    elseif r.how == "book" then
        local b = ns.EXPERT_BOOK
        tip:AddLine(" ")
        tip:AddLine("Buy and read the book " .. b.title .. ".", 1, 1, 1, true)
        tip:AddLine("Sold by " .. b.seller, 1, 0.82, 0)
        Where(tip, b.place, b.map, b.x, b.y)
        AddCost(tip, r.cost, b.rep)
    elseif r.how == "quest" then
        local q = ns.ARTISAN_QUEST
        tip:AddLine(" ")
        tip:AddLine("Complete the quest " .. q.title .. ".", 1, 1, 1, true)
        tip:AddLine("From " .. q.giver, 1, 0.82, 0)
        Where(tip, q.place, q.map, q.x, q.y)
    end
    tip:AddLine(" ")
    tip:AddLine("Ctrl-click to pin this place on your map.", 0.5, 0.5, 0.5, true)
    tip:Show()
end)
trainIcon:SetScript("OnLeave", HideWindowTip)

-- Where the next rank is learned: { name, map, x, y } or nil.
local function TrainingSpot()
    local r = NextRank()
    if not r then return nil end
    if r.how == "trainer" then
        local t = NearestTrainer()
        return t and { name = t.name, map = t.map, x = t.x, y = t.y }
    elseif r.how == "book" then
        local b = ns.EXPERT_BOOK
        return { name = b.seller, map = b.map, x = b.x, y = b.y }
    else
        local q = ns.ARTISAN_QUEST
        return { name = q.giver, map = q.map, x = q.x, y = q.y }
    end
end

-- The game's own map pin if this client has it, else TomTom, else /mappin.
local function SlashFor(command)
    for key in pairs(SlashCmdList) do
        for i = 1, 5 do
            local alias = _G["SLASH_" .. key .. i]
            if type(alias) ~= "string" then break end
            if alias:lower() == command then return SlashCmdList[key] end
        end
    end
end

local function PinSpot(spot)
    local where = string.format("%s (%.1f, %.1f)", MapName(spot.map) or "", spot.x, spot.y)
    if C_Map and C_Map.SetUserWaypoint and UiMapPoint and UiMapPoint.CreateFromCoordinates
        and (not C_Map.CanSetUserWaypointOnMap or C_Map.CanSetUserWaypointOnMap(spot.map)) then
        C_Map.SetUserWaypoint(UiMapPoint.CreateFromCoordinates(spot.map, spot.x / 100, spot.y / 100))
        if C_SuperTrack and C_SuperTrack.SetSuperTrackedUserWaypoint then
            C_SuperTrack.SetSuperTrackedUserWaypoint(true)
        end
    elseif TomTom and TomTom.AddWaypoint then
        TomTom:AddWaypoint(spot.map, spot.x / 100, spot.y / 100, { title = spot.name })
    else
        local mappin = SlashFor("/mappin")
        if not mappin then
            print("|cff40c0ffForever Fishing Utilities:|r " .. spot.name .. " is at " .. where .. ".")
            return
        end
        mappin(string.format("%d %.1f %.1f", spot.map, spot.x, spot.y))
    end
    print("|cff40c0ffForever Fishing Utilities:|r map pin set on " .. spot.name .. ", " .. where .. ".")
end

trainIcon:RegisterForClicks("LeftButtonUp")
trainIcon:SetScript("OnClick", function()
    if not IsControlKeyDown() then return end
    local spot = TrainingSpot()
    if spot then PinSpot(spot) end
end)

function UpdateTrainIcon()
    local r, skill = NextRank()
    local ready = r and RankReady(r, skill)
    trainTex:SetDesaturated(not ready)
    trainTex:SetAlpha(ready and 1 or 0.6)
end
end

local function Refresh()
    if not db then return end
    -- The lure button is a secure button, which makes this window protected in
    -- combat: text can still change, but showing, hiding and resizing must wait.
    local locked = InCombatLockdown()
    if not db.shown or (db.poleOnly and not HasPoleEquipped()) then
        if not locked then frame:Hide() end
        return
    end

    local zone = GetRealZoneText() or ""
    local sub = GetSubZoneText() or ""
    local entry, matched = Lookup()
    entry = Effective(entry, matched)

    local place = zone
    if sub ~= "" and sub ~= zone then place = zone .. " - " .. sub end
    line1:SetText(place)

    if entry then
        local note = (matched == sub and sub ~= "") and (COLOR.grey .. "  (subzone)|r") or ""
        if entry.guessed then note = COLOR.grey .. "  (from your fishing)|r" end
        line2:SetText(Thresholds(entry) .. note)
    else
        line2:SetText(COLOR.grey .. "No fishing data for this zone yet|r")
    end

    lineSkill:SetText(SkillText())
    UpdateTrainIcon()

    if not locked then
        Fit({ line1, line2, lineSkill })
        frame:Show()
    end
end

---------------------------------------------------------------------------
-- Catches flyout: what the water here can give, shown on hovering the zone name
---------------------------------------------------------------------------
-- A list anchored to the window and as wide as it, opening above or below.
-- "smart" opens away from the nearer screen edge (top or bottom).

local ROW_H = 16
local flyout = CreateFrame("Frame", "ForeverFishingUtilitiesCatches", frame, "BackdropTemplate")
flyout:SetFrameStrata("TOOLTIP")
flyout:SetBackdrop({
    bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
    edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
    tile = true, tileSize = 16, edgeSize = 12,
    insets = { left = 3, right = 3, top = 3, bottom = 3 },
})
flyout:SetBackdropColor(0, 0, 0, 0.9)
flyout:SetBackdropBorderColor(0.4, 0.4, 0.4, 1)
flyout:Hide()

local flyTitle = flyout:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
flyTitle:SetPoint("TOPLEFT", 8, -7)
flyTitle:SetPoint("TOPRIGHT", -8, -7)
flyTitle:SetJustifyH("LEFT")
flyTitle:SetWordWrap(false)

local flyNote = flyout:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
flyNote:SetPoint("BOTTOMLEFT", 8, 7)
flyNote:SetPoint("BOTTOMRIGHT", -8, 7)
flyNote:SetJustifyH("LEFT")
flyNote:SetWordWrap(false)

local flyRows = {}
local function FlyRow(i)
    local row = flyRows[i]
    if row then return row end
    row = CreateFrame("Frame", nil, flyout)
    row:SetHeight(ROW_H)
    row:SetPoint("TOPLEFT", 8, -7 - 14 - (i - 1) * ROW_H)
    row:SetPoint("RIGHT", -8, 0)
    row.icon = row:CreateTexture(nil, "ARTWORK")
    row.icon:SetSize(ROW_H - 2, ROW_H - 2)
    row.icon:SetPoint("LEFT")
    row.icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
    row.rate = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    row.rate:SetPoint("RIGHT")
    row.rate:SetJustifyH("RIGHT")
    row.name = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    row.name:SetPoint("LEFT", row.icon, "RIGHT", 4, 0)
    row.name:SetPoint("RIGHT", row.rate, "LEFT", -4, 0)
    row.name:SetJustifyH("LEFT")
    row.name:SetWordWrap(false)
    flyRows[i] = row
    return row
end

-- The catch table for where you stand, and the name it belongs to.
local function LookupDrops()
    local zone = GetRealZoneText() or ""
    local sub = GetSubZoneText() or ""
    local subs = ns.DROP_SUBZONES and ns.DROP_SUBZONES[zone]
    if sub ~= "" and subs and subs[sub] then
        return ns.DROP_TABLES[subs[sub]], sub
    end
    local id = ns.DROP_ZONES and ns.DROP_ZONES[zone]
    return id and ns.DROP_TABLES[id], zone
end

local function RateText(pct)
    if pct >= 10 then return string.format("%.0f%%", pct) end
    if pct >= 1 then return (string.format("%.1f", pct):gsub("%.0$", "")) .. "%" end
    return string.format("%g%%", pct)
end

local TAG_TEXT = { w = " (winter)", s = " (summer)", q = " (quest)" }

-- Item name (coloured by quality) and icon; the name is nil until the game has loaded the item.
local function DropInfo(itemID)
    local getInfo = (C_Item and C_Item.GetItemInfo) or GetItemInfo
    local name, _, quality = getInfo(itemID)
    local getIcon = (C_Item and C_Item.GetItemIconByID) or GetItemIcon
    local icon = getIcon and getIcon(itemID)
    if not name then
        if C_Item and C_Item.RequestLoadItemDataByID then C_Item.RequestLoadItemDataByID(itemID) end
        return nil, icon
    end
    local color = quality and ITEM_QUALITY_COLORS and ITEM_QUALITY_COLORS[quality]
    if color and color.hex then name = color.hex .. name .. "|r" end
    return name, icon
end

local flyWaiting = false -- some item names weren't loaded yet
local dropAsked = {}     -- itemID -> when its name was first asked for
local DROP_GIVE_UP = 3   -- seconds; an item the server never answers for isn't in this game

local function FillFlyout()
    local drops, where = LookupDrops()
    flyWaiting = false
    local n = 0
    if drops then
        flyTitle:SetText("Catches: " .. where)
        for _, drop in ipairs(drops) do
            local id = drop[1]
            local name, icon = DropInfo(id)
            local skip = false
            if name then
                dropAsked[id] = nil
            else
                dropAsked[id] = dropAsked[id] or GetTime()
                -- Leave out items the server doesn't know (Classic items that
                -- WoW Forever doesn't have). They come back if a name ever arrives.
                skip = GetTime() - dropAsked[id] > DROP_GIVE_UP
                if not skip then flyWaiting = true end
            end
            if not skip then
                n = n + 1
                local row = FlyRow(n)
                row.icon:SetTexture(icon or "Interface\\Icons\\INV_Misc_QuestionMark")
                row.rate:SetText(RateText(drop[2]))
                row.name:SetText((name or "Loading...") ..
                    (drop[3] and (COLOR.grey .. TAG_TEXT[drop[3]] .. "|r") or ""))
                row:Show()
            end
        end
        flyNote:SetText("Open water, per catch")
    else
        flyTitle:SetText("Catches")
        flyNote:SetText("No catch data for this area yet")
    end
    for i = n + 1, #flyRows do flyRows[i]:Hide() end
    flyout:SetHeight(7 + 14 + n * ROW_H + 4 + 12 + 7)
end

local function PlaceFlyout()
    local dir = FlyoutDirection()
    flyout:ClearAllPoints()
    if dir == "down" then
        flyout:SetPoint("TOPLEFT", frame, "BOTTOMLEFT", 0, -2)
        flyout:SetPoint("TOPRIGHT", frame, "BOTTOMRIGHT", 0, -2)
    else
        flyout:SetPoint("BOTTOMLEFT", frame, "TOPLEFT", 0, 2)
        flyout:SetPoint("BOTTOMRIGHT", frame, "TOPRIGHT", 0, 2)
    end
end

-- Watches the mouse instead of using a mouse-enabled frame over the zone name,
-- so dragging the window by its header still works.
local flyElapsed, flyKey = 0, nil
frame:SetScript("OnUpdate", function(_, elapsed)
    flyElapsed = flyElapsed + elapsed
    if flyElapsed < 0.1 then return end
    flyElapsed = 0
    if not (db and db.dropTip and line1:IsMouseOver()) then
        if flyout:IsShown() then flyout:Hide() end
        flyKey = nil
        return
    end
    local key = (GetRealZoneText() or "") .. "|" .. (GetSubZoneText() or "")
    if key ~= flyKey or flyWaiting or not flyout:IsShown() then
        flyKey = key
        FillFlyout()
    end
    PlaceFlyout()
    flyout:Show()
end)

---------------------------------------------------------------------------
-- World map: fishing numbers for the zone under the cursor
---------------------------------------------------------------------------
-- While the world map is open, a small tooltip follows the cursor and shows
-- the hovered zone's fishing numbers (on a continent map), or the shown zone's
-- numbers (on a zone map). It works out the zone itself from the cursor
-- position with C_Map.GetMapInfoAtPosition, so it doesn't depend on how the
-- map draws its own labels.

local mapTip = CreateFrame("GameTooltip", "ForeverFishingUtilitiesMapTip", UIParent, "GameTooltipTemplate")
mapTip:SetFrameStrata("TOOLTIP")

local function AddZoneLines(name)
    local entry = Effective(ns.ZONES[name], name)
    local added = false
    if entry then
        mapTip:AddLine(Thresholds(entry))
        added = true
    end
    -- Bodies of water in this zone that need a different skill.
    for subName, parent in pairs(ns.SUBZONE_PARENT) do
        local subEntry = Effective(ns.SUBZONES[subName], subName)
        if parent == name and subEntry then
            mapTip:AddLine(COLOR.grey .. subName .. ":|r " .. COLOR.orange .. MinText(subEntry) ..
                " / " .. COLOR.yellow .. FullText(subEntry))
            added = true
        end
    end
    return added
end

-- True when the game or another addon (Questie, map pins, etc.) is already
-- showing a tooltip. Unused since the map tooltip moved to the map's corner,
-- where it no longer overlaps them; kept in case it goes back to the cursor.
local OTHER_TIPS = { "GameTooltip", "WorldMapTooltip", "WorldMapCompareTooltip1" }
local function OtherTooltipShown()
    for _, tipName in ipairs(OTHER_TIPS) do
        local tip = _G[tipName]
        if tip and tip ~= mapTip and tip:IsShown() then return true end
    end
    return false
end

local lastMapZone
local mapWaiting = false -- item names in the map tooltip still loading
local function UpdateMapTip()
    local map = WorldMapFrame
    local scroll = map and map.ScrollContainer
    if not (db and db.mapTip and map and map:IsShown() and scroll and scroll:IsMouseOver()) then
        if mapTip:IsShown() then mapTip:Hide() end
        lastMapZone = nil
        return
    end
    local mapID = map:GetMapID()
    local x, y = scroll:GetNormalizedCursorPosition()
    local name
    if mapID and x and y and C_Map and C_Map.GetMapInfoAtPosition then
        local info = C_Map.GetMapInfoAtPosition(mapID, x, y)
        if info and info.mapID ~= mapID then name = info.name end
    end
    if not name and mapID and C_Map then
        -- Not over a child zone: use the zone the map is showing, if it is one.
        local info = C_Map.GetMapInfo(mapID)
        name = info and info.name
    end
    local ownNumbers = name and db.learn and db.learned and db.learned[name]
    if not name or not (ns.ZONES[name] or ns.SUBZONE_PARENT[name] or ownNumbers) then
        if mapTip:IsShown() then mapTip:Hide() end
        lastMapZone = nil
        return
    end
    -- Rebuild only when the zone or the Shift state changes (or item names are
    -- still arriving); a cursor-anchored tooltip follows the mouse by itself.
    local drops = ns.DROP_ZONES and ns.DROP_TABLES[ns.DROP_ZONES[name] or 0]
    local shift = drops and IsShiftKeyDown() or false
    local key = name .. (shift and "+" or "")
    if key ~= lastMapZone or mapWaiting or not mapTip:IsShown() then
        lastMapZone = key
        mapWaiting = false
        -- Sits in the map's bottom-left corner, out of the way of cursor tooltips.
        mapTip:SetOwner(scroll, "ANCHOR_NONE")
        mapTip:ClearAllPoints()
        mapTip:SetPoint("BOTTOMLEFT", scroll, "BOTTOMLEFT", 8, 8)
        mapTip:AddLine(name .. " fishing", 1, 0.82, 0)
        AddZoneLines(name)
        if shift then
            -- Shift held: the zone's open-water catches, as in the window's list.
            mapTip:AddLine(" ")
            for _, drop in ipairs(drops) do
                local id = drop[1]
                local itemName, icon = DropInfo(id)
                local skip = false
                if itemName then
                    dropAsked[id] = nil
                else
                    dropAsked[id] = dropAsked[id] or GetTime()
                    skip = GetTime() - dropAsked[id] > DROP_GIVE_UP
                    if not skip then mapWaiting = true end
                end
                if not skip then
                    mapTip:AddDoubleLine(
                        "|T" .. (icon or "Interface\\Icons\\INV_Misc_QuestionMark") .. ":14:14:0:0:64:64:5:59:5:59|t " ..
                            (itemName or "Loading...") ..
                            (drop[3] and (COLOR.grey .. TAG_TEXT[drop[3]] .. "|r") or ""),
                        RateText(drop[2]), 1, 1, 1, 1, 1, 1)
                end
            end
            if ns.DROP_SUBZONES[name] then
                mapTip:AddLine("Coasts and some subzones differ.", 0.5, 0.5, 0.5)
            end
        elseif drops then
            mapTip:AddLine("Hold Shift for catches", 0.5, 0.5, 0.5)
        end
        mapTip:Show()
    end
end

local mapTicker
local mapHooked = false
local function HookWorldMap()
    if mapHooked or not WorldMapFrame then return end
    mapHooked = true
    WorldMapFrame:HookScript("OnShow", function()
        if not mapTicker then mapTicker = C_Timer.NewTicker(0.05, UpdateMapTip) end
    end)
    WorldMapFrame:HookScript("OnHide", function()
        if mapTicker then mapTicker:Cancel(); mapTicker = nil end
        mapTip:Hide()
        lastMapZone = nil
    end)
    if WorldMapFrame:IsShown() and not mapTicker then
        mapTicker = C_Timer.NewTicker(0.05, UpdateMapTip)
    end
end

---------------------------------------------------------------------------
-- One-key fishing
---------------------------------------------------------------------------
-- How it works (same idea as Better Fishing):
--   * The fishing keys are pointed, with override bindings, at a secure button
--     that casts Fishing.
--   * While the cast is up, the same keys are pointed at the game's
--     "Interact with Target" command, and soft-target interact is turned on so
--     the bobber is the target.
--   * Override bindings are never saved, so nothing sticks after a reload.
--     They can't change in combat: they're cleared as combat starts and put
--     back when it ends.

local function Say(msg)
    print("|cff40c0ffForever Fishing Utilities:|r " .. msg)
end

BINDING_HEADER_FOREVERFISHINGUTILITIES = "Forever Fishing Utilities"
BINDING_NAME_FOREVERFISHINGUTILITIES_CAST = "Cast and Interact (pole equipped)"

local CAST_BUTTON_NAME = "ForeverFishingUtilitiesCastButton"
local castButton = CreateFrame("Button", CAST_BUTTON_NAME, UIParent, "SecureActionButtonTemplate")
castButton:RegisterForClicks("AnyDown", "AnyUp")
castButton:SetAttribute("type", "spell")
castButton:SetAttribute("spell", FishingName())

local keyOwner = CreateFrame("Frame")   -- owns the key overrides
local mouseOwner = CreateFrame("Frame") -- owns the right-click override
local keysPending = false               -- keys need updating once combat ends
local restoreTimer

castButton:SetScript("PostClick", function(_, mouseButton, down)
    -- Only for double right-click casts: hold mouselook through the click so
    -- the right-click doesn't turn the camera, then release it. Key presses
    -- skip this: their key-up goes to Interact once the cast starts, so a
    -- mouselook started on key-down would never be released.
    if mouseButton == "Jump" then
        -- The jump key, pointed here while the pole is out. Pressed on the
        -- move, it means "I'm done fishing": put the weapons back.
        if down then JumpSwap() end
        return
    end
    if mouseButton ~= "RightButton" then return end
    if down then
        MouselookStart()
        return
    end
    MouselookStop()
    if not InCombatLockdown() then ClearOverrideBindings(mouseOwner) end
end)

-- Keys that should cast/interact right now.
local function FishingKeys()
    local keys = {}
    if db.spaceOn then keys[#keys + 1] = "SPACE" end
    for _, key in ipairs({ GetBindingKey("FOREVERFISHINGUTILITIES_CAST") }) do
        if key ~= "SPACE" then keys[#keys + 1] = key end
    end
    return keys
end

local function UpdateKeys()
    if InCombatLockdown() then
        keysPending = true
        return
    end
    keysPending = false
    ClearOverrideBindings(keyOwner)
    if not HasPoleEquipped() then return end
    local jumpKeys = { SPACE = true }
    for _, key in ipairs({ GetBindingKey("JUMP") }) do jumpKeys[key] = true end
    -- "Just jump" while moving: leave jump keys alone until you stop.
    local moving = db.moving == "jump" and IsPlayerMoving and IsPlayerMoving()
    for _, key in ipairs(FishingKeys()) do
        if moving and jumpKeys[key] and not fishingActive then
            -- (no override: the key jumps as usual)
        elseif fishingActive then
            SetOverrideBinding(keyOwner, true, key, "INTERACTTARGET")
        else
            -- Jump keys click as "Jump" so the button can tell them apart.
            SetOverrideBindingClick(keyOwner, true, key, CAST_BUTTON_NAME, jumpKeys[key] and "Jump" or nil)
        end
    end
end

-- The binding itself only runs when the overrides aren't in place.
function ForeverFishingUtilities_CastKey()
    if not HasPoleEquipped() then
        Say("equip a fishing pole to use this key.")
    elseif InCombatLockdown() then
        Say("fishing keys are off in combat.")
    end
end

---------------------------------------------------------------------------
-- Settings changed only while fishing (sound and soft-target interact)
---------------------------------------------------------------------------

local FISHING_CVARS = {
    -- soft-target interact, so Interact with Target picks the bobber
    { "SoftTargetInteract", "3" },
    { "SoftTargetInteractArc", "2" },
    { "SoftTargetInteractRange", "60" },
}
local SOUND_CVARS = {
    { "Sound_EnableAllSound", "1" },
    { "Sound_EnableSFX", "1" },
    { "Sound_EnableSoundWhenGameIsInBG", "1" },
    { "Sound_SFXVolume", "1" },
    { "Sound_EnableMusic", "0" },
    { "Sound_EnableAmbience", "0" },
    { "Sound_EnableDialog", "0" },
    { "Sound_EnablePetSounds", "0" },
}

local function CVarExists(name)
    return GetCVar(name) ~= nil
end

-- Sound settings go into the same cache, so they can be switched on or off
-- in the middle of a fishing session.
local function ApplySound()
    local cache = db.cvarCache
    if not cache then return end
    local function set(name, value)
        if CVarExists(name) then
            if cache[name] == nil then cache[name] = GetCVar(name) end
            SetCVar(name, value)
        end
    end
    for _, cv in ipairs(SOUND_CVARS) do set(cv[1], cv[2]) end
    set("Sound_MasterVolume", tostring(db.volume))
end

local function RestoreSound()
    local cache = db.cvarCache
    if not cache then return end
    local names = { "Sound_MasterVolume" }
    for _, cv in ipairs(SOUND_CVARS) do names[#names + 1] = cv[1] end
    for _, name in ipairs(names) do
        if cache[name] ~= nil then
            SetCVar(name, cache[name])
            cache[name] = nil
        end
    end
end

local function ApplyFishingSettings()
    if restoreTimer then restoreTimer:Cancel(); restoreTimer = nil end
    if db.cvarCache then return end -- already applied this session
    local cache = {}
    local function set(name, value)
        if CVarExists(name) then
            cache[name] = GetCVar(name)
            SetCVar(name, value)
        end
    end
    for _, cv in ipairs(FISHING_CVARS) do set(cv[1], cv[2]) end
    db.cvarCache = cache
    if db.sound then ApplySound() end
end

local function RestoreSettings()
    if restoreTimer then restoreTimer:Cancel(); restoreTimer = nil end
    if not db.cvarCache then return end
    for name, value in pairs(db.cvarCache) do
        SetCVar(name, value)
    end
    db.cvarCache = nil
end

-- Wait a few seconds before restoring, so recasting doesn't flicker the music.
local function RestoreSoon()
    if restoreTimer then restoreTimer:Cancel() end
    restoreTimer = C_Timer.NewTimer(6, function()
        restoreTimer = nil
        if not fishingActive then RestoreSettings() end
    end)
end

---------------------------------------------------------------------------
-- Double right-click
---------------------------------------------------------------------------

-- Two right-clicks within this many seconds count as a double-click. Close
-- to the usual system setting, so it feels like any other double-click.
local DOUBLE_CLICK_TIME = 0.4
local lastRightClick = 0
local lastDoubleCast = 0

local function CanCast()
    return HasPoleEquipped()
        and not InCombatLockdown()
        and not IsPlayerMoving()
        and not IsMounted()
        and not IsFlying()
        and not IsFalling()
        and not IsSwimming()
        and not UnitOnTaxi("player")
        and not UnitIsDeadOrGhost("player")
        and GetNumLootItems() == 0
end

local function OnRightDown()
    if not db.doubleClick or InCombatLockdown() then return end
    if IsMouseButtonDown("LeftButton") then return end
    local now = GetTime()
    local gap = now - lastRightClick
    lastRightClick = now
    if gap < 0.04 or gap > DOUBLE_CLICK_TIME then return end
    if now - lastDoubleCast < 0.5 then return end
    lastRightClick = 0
    if fishingActive then
        SetOverrideBinding(mouseOwner, true, "BUTTON2", "INTERACTTARGET")
    elseif CanCast() then
        lastDoubleCast = now
        SetOverrideBindingClick(mouseOwner, true, "BUTTON2", CAST_BUTTON_NAME, "RightButton")
    end
end

local function OnRightUp()
    -- Leave the override in place for this click, then clear it.
    C_Timer.After(0.1, function()
        if not InCombatLockdown() then ClearOverrideBindings(mouseOwner) end
    end)
end

---------------------------------------------------------------------------
-- Space button
---------------------------------------------------------------------------

-- A small square toggle in the window's top-right corner.
local function MakeToggle(texture, xOffset, atlas)
    local button = CreateFrame("Button", nil, frame)
    button:SetSize(16, 16)
    button:SetPoint("TOPRIGHT", xOffset, -4)
    local icon = button:CreateTexture(nil, "ARTWORK")
    icon:SetAllPoints()
    if atlas and C_Texture and C_Texture.GetAtlasInfo and C_Texture.GetAtlasInfo(atlas) then
        icon:SetAtlas(atlas)
    else
        icon:SetTexture(texture)
        icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    end
    local glow = button:CreateTexture(nil, "OVERLAY")
    glow:SetPoint("TOPLEFT", -2, 2)
    glow:SetPoint("BOTTOMRIGHT", 2, -2)
    glow:SetTexture("Interface\\Buttons\\UI-ActionButton-Border")
    glow:SetBlendMode("ADD")
    glow:SetVertexColor(0.3, 1, 0.3)
    glow:SetTexCoord(0.2, 0.8, 0.2, 0.8)
    button:SetHighlightTexture("Interface\\Buttons\\ButtonHilight-Square", "ADD")
    button.SetOn = function(_, on)
        icon:SetDesaturated(not on)
        icon:SetAlpha(on and 1 or 0.6)
        glow:SetShown(on and true or false)
    end
    button:SetScript("OnLeave", HideWindowTip)
    return button
end

local spaceButton = MakeToggle("Interface\\Icons\\Trade_Fishing", -6)
-- The game's speaker icon if this client has it; otherwise the Silence spell icon.
local soundButton = MakeToggle("Interface\\Icons\\Spell_Shadow_ImpPhaseShift", -26, "voicechat-icon-speaker")

local function UpdateSpaceButton()
    spaceButton:SetOn(db and db.spaceOn)
    soundButton:SetOn(db and db.sound)
end

local function SetSound(on)
    db.sound = on and true or false
    if db.cvarCache then -- mid-session: switch right away
        if db.sound then ApplySound() else RestoreSound() end
    end
    UpdateSpaceButton()
end

soundButton:SetScript("OnClick", function()
    SetSound(not db.sound)
end)
soundButton:SetScript("OnEnter", function(self)
    WindowTip()
    if db.sound then
        GameTooltip:SetText("Fishing sound: on")
        GameTooltip:AddLine("While fishing, music, ambience, dialog and pet sounds are off and effects are loud (master " ..
            math.floor(db.volume * 100 + 0.5) .. "%). Click to leave your sound alone.", 1, 1, 1, true)
    else
        GameTooltip:SetText("Fishing sound: off")
        GameTooltip:AddLine("Your sound settings are left alone while fishing. Click to quiet everything but the splash.", 1, 1, 1, true)
    end
    GameTooltip:Show()
end)

local function SetSpace(on, quiet)
    db.spaceOn = on and true or false
    UpdateKeys()
    UpdateSpaceButton()
    if keysPending and not quiet then
        Say("keys can't change in combat; will switch when combat ends.")
    end
end

local function ToggleSpace()
    SetSpace(not db.spaceOn)
end

spaceButton:SetScript("OnClick", ToggleSpace)
spaceButton:SetScript("OnEnter", function(self)
    WindowTip()
    if db.spaceOn then
        GameTooltip:SetText("Space fishing: on")
        GameTooltip:AddLine("With a fishing pole equipped, Space casts and clicks the bobber. Without one, or in combat, Space jumps. Click to turn off.", 1, 1, 1, true)
    else
        GameTooltip:SetText("Space fishing: off")
        GameTooltip:AddLine("Space always jumps. Click to make it cast and click the bobber whenever your pole is equipped.", 1, 1, 1, true)
    end
    GameTooltip:Show()
end)

-- Undo the key swap left by version 1.3, which used saved bindings.
local function MigrateOldSwap()
    if not db.swap or InCombatLockdown() then return end
    SetBinding("SPACE", db.swap.space or "JUMP")
    for _, key in ipairs(db.swap.keys or {}) do
        if key ~= "SPACE" then SetBinding(key, "BETTERFISHINGKEY") end
    end
    db.swap = nil
end

---------------------------------------------------------------------------
-- Lure button
---------------------------------------------------------------------------
-- Picks the weakest lure in your bags (that your base skill can use) whose
-- bonus lifts your skill to the water's Recommended, so the strong lures are
-- saved for water that needs them. If none is enough, or the water's numbers
-- aren't known, it picks the strongest. Equal bonuses: the first in the list
-- (the cheaper vendor lure). Clicking runs "/use <lure>" then "/use 16" (main
-- hand), the same as doing it by hand. Its target can only change out of combat.

local LURES = { -- best first
    { id = 6533, bonus = 100, req = 100 }, -- Aquadynamic Fish Attractor (5 min)
    { id = 6532, bonus = 75,  req = 100 }, -- Bright Baubles
    { id = 7307, bonus = 75,  req = 100 }, -- Flesh Eating Worm
    { id = 6530, bonus = 50,  req = 50  }, -- Nightcrawlers
    { id = 6811, bonus = 50,  req = 50  }, -- Aquadynamic Fish Lens
    { id = 6529, bonus = 25,  req = 1   }, -- Shiny Bauble
}

local function ItemCount(id)
    if C_Item and C_Item.GetItemCount then return C_Item.GetItemCount(id) or 0 end
    return GetItemCount and GetItemCount(id) or 0
end

local function ItemIcon(id)
    if C_Item and C_Item.GetItemIconByID then return C_Item.GetItemIconByID(id) end
    return GetItemIcon and GetItemIcon(id)
end

local function ItemName(id)
    if C_Item and C_Item.GetItemNameByID then return C_Item.GetItemNameByID(id) end
    return GetItemInfo and (GetItemInfo(id))
end

-- prev: the lure picked last time. While a lure is on the pole the skill
-- bonus already includes it, so the pick stays as it was.
local function BestLure(prev)
    local rank, bonus = GetFishingSkill()
    if not rank then return nil end
    local strongest, pick
    local entry, key = Lookup()
    local shown = Effective(entry, key)
    local need = shown and shown.full and (shown.full - rank - (bonus or 0))
    local lureOn = HasPoleEquipped() and GetWeaponEnchantInfo()
    for _, lure in ipairs(LURES) do
        if rank >= lure.req and ItemCount(lure.id) > 0 then
            if lureOn and prev and lure.id == prev.id then return prev end
            strongest = strongest or lure
            if need and lure.bonus >= need and (not pick or lure.bonus < pick.bonus) then pick = lure end
        end
    end
    return pick or strongest
end

local lureButton = CreateFrame("Button", "ForeverFishingUtilitiesLureButton", frame, "SecureActionButtonTemplate")
lureButton:SetSize(16, 16)
lureButton:SetPoint("BOTTOMRIGHT", -6, 4)
lureButton:RegisterForClicks("AnyUp", "AnyDown")
local lureIcon = lureButton:CreateTexture(nil, "ARTWORK")
lureIcon:SetAllPoints()
lureIcon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
local lureCount = lureButton:CreateFontString(nil, "OVERLAY", "NumberFontNormalSmall")
lureCount:SetPoint("BOTTOMRIGHT", 3, -2)
lureButton:SetHighlightTexture("Interface\\Buttons\\ButtonHilight-Square", "ADD")

local currentLure
local lurePending = false

local function UpdateLure()
    if not db then return end
    local lure = BestLure(currentLure)
    currentLure = lure
    -- Icon and count can always change; the click target only out of combat.
    if lure then
        lureIcon:SetTexture(ItemIcon(lure.id))
        lureIcon:SetDesaturated(false)
        lureIcon:SetAlpha(1)
        local n = ItemCount(lure.id)
        lureCount:SetText(n > 1 and n or "")
    else
        lureIcon:SetTexture(ItemIcon(6529) or "Interface\\Icons\\INV_Misc_QuestionMark")
        lureIcon:SetDesaturated(true)
        lureIcon:SetAlpha(0.5)
        lureCount:SetText("")
    end
    if lureButton.autoMark then lureButton.autoMark:SetShown(db.autoLure and true or false) end
    if InCombatLockdown() then
        lurePending = true
        return
    end
    lurePending = false
    if lure then
        lureButton:SetAttribute("type", "macro")
        lureButton:SetAttribute("macrotext", "/use item:" .. lure.id .. "\n/use 16")
    else
        lureButton:SetAttribute("type", nil)
        lureButton:SetAttribute("macrotext", nil)
    end
end

local UpdateCastAction, HasLuremaster -- defined with auto lure, below

lureButton:SetScript("OnEnter", function(self)
    WindowTip()
    local lure = currentLure
    if lure then
        GameTooltip:SetText(ItemName(lure.id) or "Lure")
        GameTooltip:AddLine("+" .. lure.bonus .. " Fishing  ·  " .. ItemCount(lure.id) .. " in bags", 1, 1, 1)
    else
        GameTooltip:SetText("No usable lure")
        GameTooltip:AddLine("No lure in your bags that your Fishing skill can use.", 0.8, 0.8, 0.8, true)
    end
    local hasLure, msLeft = GetWeaponEnchantInfo()
    if hasLure and msLeft and HasPoleEquipped() then
        GameTooltip:AddLine(" ")
        GameTooltip:AddLine("Lure on pole: " .. math.ceil(msLeft / 60000) .. " min left", 0.3, 1, 0.3)
    end
    GameTooltip:AddLine(" ")
    GameTooltip:AddLine("Auto lure: " .. (db.autoLure and "|cff40ff40on|r" or "|cffff4040off|r") ..
        (db.autoLure and HasLuremaster and HasLuremaster() and "  (Luremaster)" or ""), 1, 1, 1)
    GameTooltip:AddLine("Right-click to turn auto lure on or off.", 0.5, 0.5, 0.5, true)
    GameTooltip:Show()
end)
lureButton:SetScript("OnLeave", HideWindowTip)

---------------------------------------------------------------------------
-- Auto lure
---------------------------------------------------------------------------
-- With auto lure on, the cast key (Space, the keybind or a double
-- right-click) puts the best lure on your pole first when it has none: the
-- cast button's click is switched to the lure macro until the lure is on.
-- Secure attributes only change out of combat, which is also the only time
-- the fishing keys are active. Right-click the lure button to toggle it.

do
    -- The Luremaster Legacy perk: an extra fish 25/50% of the time with a
    -- lure on, so a lure is worth it even above Recommended.
    function HasLuremaster()
        local name = "Luremaster"
        if C_Spell and C_Spell.GetSpellInfo then
            local ok, info = pcall(C_Spell.GetSpellInfo, name)
            if ok and info then return true end
        end
        if GetSpellInfo then
            local ok, found = pcall(GetSpellInfo, name)
            if ok and found then return true end
        end
        return false
    end

    -- Why a lure is (or isn't) worth putting on now.
    local function LureWanted()
        if not (db.autoLure and HasPoleEquipped() and currentLure) then return false end
        if GetWeaponEnchantInfo() then return false end -- already has one
        if not db.autoLureSmart or HasLuremaster() then return true end
        local rank, bonus = GetFishingSkill()
        local entry, key = Lookup()
        local shown = Effective(entry, key)
        if not (rank and shown and shown.full) then return true end -- unknown water: lure up
        return rank + (bonus or 0) < shown.full
    end

    local castIsLure
    function UpdateCastAction()
        if InCombatLockdown() then return end
        local want = LureWanted() and true or false
        if want == castIsLure and (not want or castButton:GetAttribute("macrotext") == lureButton:GetAttribute("macrotext")) then return end
        castIsLure = want
        if want then
            castButton:SetAttribute("type", "macro")
            castButton:SetAttribute("macrotext", "/use item:" .. currentLure.id .. "\n/use 16")
        else
            castButton:SetAttribute("type", "spell")
            castButton:SetAttribute("spell", FishingName())
            castButton:SetAttribute("macrotext", nil)
        end
    end

    -- The auto-cast corners, like a pet's autocast ability.
    local autoMark = lureButton:CreateTexture(nil, "OVERLAY", nil, 2)
    autoMark:SetTexture("Interface\\Buttons\\UI-AutoCastableOverlay")
    autoMark:SetPoint("TOPLEFT", -10, 10)
    autoMark:SetPoint("BOTTOMRIGHT", 10, -10)
    lureButton.autoMark = autoMark

    -- Right-click: toggle auto lure. The right button's own action is an
    -- empty macro so it doesn't also put the lure on.
    lureButton:SetAttribute("type2", "macro")
    lureButton:SetAttribute("macrotext2", "")
    local lastToggle = 0
    lureButton:HookScript("OnClick", function(_, button)
        if button ~= "RightButton" or GetTime() - lastToggle < 0.3 then return end
        lastToggle = GetTime()
        db.autoLure = not db.autoLure
        autoMark:SetShown(db.autoLure)
        UpdateCastAction()
        print("|cff40c0ffForever Fishing Utilities:|r auto lure " .. (db.autoLure and "|cff40ff40on|r" or "|cffff4040off|r") .. ".")
        if GameTooltip:IsOwned(frame) then lureButton:GetScript("OnEnter")(lureButton) end
    end)
end

---------------------------------------------------------------------------
-- Food button
---------------------------------------------------------------------------
-- WoW: Forever gave six fish dishes a Fishing bonus once you're Well Fed
-- (eat for 10 seconds). Picks the biggest bonus you can eat that's in your
-- bags. Like the lure button, its target only changes out of combat.

local FOODS = { -- best first
    { id = 13930, bonus = 18, level = 35 }, -- Filet of Redgill
    { id = 8957,  bonus = 18, level = 45 }, -- Spinefin Halibut
    { id = 4594,  bonus = 12, level = 25 }, -- Rockscale Cod
    { id = 4593,  bonus = 8,  level = 15 }, -- Bristle Whisker Catfish
    { id = 5476,  bonus = 5,  level = 5  }, -- Fillet of Frenzy
    { id = 6316,  bonus = 3,  level = 5  }, -- Loch Frenzy Delight
}

local function BestFood()
    local level = UnitLevel("player") or 1
    for _, food in ipairs(FOODS) do
        if level >= food.level and ItemCount(food.id) > 0 then return food end
    end
end

local foodButton = CreateFrame("Button", "ForeverFishingUtilitiesFoodButton", frame, "SecureActionButtonTemplate")
foodButton:SetSize(16, 16)
foodButton:RegisterForClicks("AnyUp", "AnyDown")
local foodIcon = foodButton:CreateTexture(nil, "ARTWORK")
foodIcon:SetAllPoints()
foodIcon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
local foodCount = foodButton:CreateFontString(nil, "OVERLAY", "NumberFontNormalSmall")
foodCount:SetPoint("BOTTOMRIGHT", 3, -2)
foodButton:SetHighlightTexture("Interface\\Buttons\\ButtonHilight-Square", "ADD")

local currentFood
local foodPending = false

local function UpdateFood()
    if not db then return end
    local food = BestFood()
    currentFood = food
    if food then
        foodIcon:SetTexture(ItemIcon(food.id))
        foodIcon:SetDesaturated(false)
        foodIcon:SetAlpha(1)
        local n = ItemCount(food.id)
        foodCount:SetText(n > 1 and n or "")
    else
        foodIcon:SetTexture(ItemIcon(5476) or "Interface\\Icons\\INV_Misc_Fish_31")
        foodIcon:SetDesaturated(true)
        foodIcon:SetAlpha(0.5)
        foodCount:SetText("")
    end
    if InCombatLockdown() then
        foodPending = true
        return
    end
    foodPending = false
    if food then
        foodButton:SetAttribute("type", "macro")
        foodButton:SetAttribute("macrotext", "/use item:" .. food.id)
    else
        foodButton:SetAttribute("type", nil)
        foodButton:SetAttribute("macrotext", nil)
    end
end

foodButton:SetScript("OnEnter", function(self)
    WindowTip()
    local food = currentFood
    if food then
        GameTooltip:SetText(ItemName(food.id) or "Fishing food")
        GameTooltip:AddLine("+" .. food.bonus .. " Fishing  ·  " .. ItemCount(food.id) .. " in bags", 1, 1, 1)
    else
        GameTooltip:SetText("No Fishing food")
        GameTooltip:AddLine("None in your bags that you can eat. Fish dishes that give Fishing skill: Loch Frenzy Delight, Fillet of Frenzy, Bristle Whisker Catfish, Rockscale Cod, Filet of Redgill and Spinefin Halibut.", 0.8, 0.8, 0.8, true)
    end
    GameTooltip:Show()
end)
foodButton:SetScript("OnLeave", HideWindowTip)

---------------------------------------------------------------------------
-- Pole / weapon swap button
---------------------------------------------------------------------------
-- Remembers (per character) the weapons you wear whenever the main hand isn't
-- a fishing pole, and the last pole you wore. On click, a secure snippet checks
-- "[equipped:Fishing Poles]" right then and picks the matching /equipslot
-- macro, so it toggles correctly even in combat. The macros themselves are
-- rebuilt only out of combat.

local function CharData()
    db.chars = db.chars or {}
    local key = (UnitName("player") or "?") .. "-" .. (GetRealmName() or "?")
    db.chars[key] = db.chars[key] or {}
    return db.chars[key]
end

local function IsPole(itemID)
    if not itemID then return false end
    local info = (C_Item and C_Item.GetItemInfoInstant) or GetItemInfoInstant
    local _, _, _, _, _, classID, subclassID = info(itemID)
    return classID == 2 and subclassID == 20
end

local function PoleTypeName()
    if C_Item and C_Item.GetItemSubClassInfo then
        local name = C_Item.GetItemSubClassInfo(2, 20)
        if name then return name end
    end
    if GetItemSubClassInfo then
        local name = GetItemSubClassInfo(2, 20)
        if name then return name end
    end
    return "Fishing Poles"
end

local function FindPoleInBags()
    if not C_Container then return nil end
    for bag = 0, (NUM_BAG_SLOTS or 4) do
        for slot = 1, C_Container.GetContainerNumSlots(bag) or 0 do
            local id = C_Container.GetContainerItemID(bag, slot)
            if IsPole(id) then return id end
        end
    end
end

local swapHeader = CreateFrame("Frame", nil, UIParent, "SecureHandlerBaseTemplate")
local swapButton = CreateFrame("Button", "ForeverFishingUtilitiesSwapButton", frame, "SecureActionButtonTemplate")
swapButton:SetSize(16, 16)
swapButton:RegisterForClicks("AnyUp", "AnyDown")
swapButton:SetAttribute("type", "macro")
swapButton:SetAttribute("macrotext", "")
swapButton:SetAttribute("poleCond", "[equipped:" .. PoleTypeName() .. "] pole; weapons")
local swapIcon = swapButton:CreateTexture(nil, "ARTWORK")
swapIcon:SetAllPoints()
swapIcon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
swapButton:SetHighlightTexture("Interface\\Buttons\\ButtonHilight-Square", "ADD")

SecureHandlerWrapScript(swapButton, "OnClick", swapHeader, [[
    if SecureCmdOptionParse(self:GetAttribute("poleCond")) == "pole" then
        self:SetAttribute("macrotext", self:GetAttribute("toWeapons") or "")
    else
        self:SetAttribute("macrotext", self:GetAttribute("toPole") or "")
    end
]])

-- Keybind: a normal entry in Key Bindings (so it's listed reliably). The key it
-- gets is pointed at the swap button with an override binding, which stays in
-- place through combat, so the key swaps even mid-fight.
BINDING_NAME_FOREVERFISHINGUTILITIES_SWAP = "Swap Fishing Pole / Weapons"
local swapKeyOwner = CreateFrame("Frame")
local swapKeysPending = false

local function UpdateSwapKeys()
    if InCombatLockdown() then
        swapKeysPending = true
        return
    end
    swapKeysPending = false
    ClearOverrideBindings(swapKeyOwner)
    for _, key in ipairs({ GetBindingKey("FOREVERFISHINGUTILITIES_SWAP") }) do
        SetOverrideBindingClick(swapKeyOwner, false, key, "ForeverFishingUtilitiesSwapButton")
    end
end

-- Only runs if the override isn't in place yet (e.g. bound during combat).
function ForeverFishingUtilities_SwapKey()
    print("|cff40c0ffForever Fishing Utilities:|r the swap key will work as soon as combat ends.")
end

local swapPending = false
local recordTimer

local function PoleToEquip()
    local data = CharData()
    if data.pole and (ItemCount(data.pole) > 0) then return data.pole end
    return FindPoleInBags() or data.pole
end

local function UpdateSwap()
    if not db then return end
    local data = CharData()
    local poleOn = HasPoleEquipped()
    -- Icon: what a click would put on.
    if poleOn then
        local w = data.weapons
        swapIcon:SetTexture((w and w.mh and ItemIcon(w.mh)) or "Interface\\Icons\\INV_Sword_04")
        swapIcon:SetDesaturated(not (w and w.mh))
    else
        local pole = PoleToEquip()
        swapIcon:SetTexture((pole and ItemIcon(pole)) or "Interface\\Icons\\INV_Fishingpole_02")
        swapIcon:SetDesaturated(not pole)
    end
    if InCombatLockdown() then
        swapPending = true
        return
    end
    swapPending = false
    local toWeapons = ""
    local w = data.weapons
    if w and w.mh then
        toWeapons = "/equipslot 16 item:" .. w.mh
        -- Two identical weapons share an item ID, so a second "/equipslot 17
        -- item:<id>" would grab the copy that's still moving into the main
        -- hand. In that case the off-hand is equipped right after, from its
        -- exact bag slot (see FinishOffhand).
        if w.oh and w.oh ~= w.mh then
            toWeapons = toWeapons .. "\n/equipslot 17 item:" .. w.oh
        end
    end
    local pole = PoleToEquip()
    swapButton:SetAttribute("toWeapons", toWeapons)
    swapButton:SetAttribute("toPole", pole and ("/equipslot 16 item:" .. pole) or "")
end

-- Off-hand follow-up for identical weapons (e.g. two Copper Daggers).
-- Set when the swap button puts weapons back on and both are the same item.
local offhandWanted, offhandUntil = nil, 0

local function FindInBags(itemID)
    if not C_Container then return nil end
    for bag = 0, (NUM_BAG_SLOTS or 4) do
        for slot = 1, C_Container.GetContainerNumSlots(bag) or 0 do
            local info = C_Container.GetContainerItemInfo(bag, slot)
            if info and info.itemID == itemID and not info.isLocked then
                return bag, slot
            end
        end
    end
end

local function FinishOffhand()
    if not offhandWanted then return end
    local mh = GetInventoryItemID("player", 16)
    if GetInventoryItemID("player", 17) then
        offhandWanted = nil -- off-hand already filled
        return
    end
    if mh ~= offhandWanted then
        -- The main-hand swap hasn't landed yet; give up after a few seconds.
        if GetTime() > offhandUntil then offhandWanted = nil end
        return
    end
    local bag, slot = FindInBags(offhandWanted)
    if not bag then
        if GetTime() > offhandUntil then offhandWanted = nil end
        return
    end
    offhandWanted = nil
    ClearCursor()
    C_Container.PickupContainerItem(bag, slot)
    EquipCursorItem(17)
end

-- Jumping while moving with the pole out: swap back to the remembered weapons.
-- Out of combat only (in combat the fishing keys are off and the swap button
-- or its keybind does the job). When Space is a fishing key, that first press
-- swaps instead of jumping; Space jumps again as soon as the pole is away.
-- Puts the remembered weapons on. Plain (not secure) equip calls, which the
-- game allows for weapons in or out of combat. Returns true if it tried.
local function EquipWeapons()
    if CursorHasItem and CursorHasItem() then return false end
    local w = CharData().weapons
    if not (w and w.mh) then return false end
    local equip = (C_Item and C_Item.EquipItemByName) or EquipItemByName
    equip(w.mh, 16)
    if w.oh then
        if w.oh == w.mh then
            offhandWanted = w.oh -- identical pair: FinishOffhand fills the off-hand
            offhandUntil = GetTime() + 5
        else
            equip(w.oh, 17)
        end
    end
    return true
end

local lastJumpSwap = 0
function JumpSwap()
    if not (db and db.moving == "swap") or InCombatLockdown() or not HasPoleEquipped() then return end
    local moving = (IsPlayerMoving and IsPlayerMoving()) or (GetUnitSpeed("player") or 0) > 0
    if not moving then return end
    if GetTime() - lastJumpSwap < 1 then return end
    if EquipWeapons() then lastJumpSwap = GetTime() end
end

-- Combat swap: pulled into a fight with the pole out, the weapons go on as
-- combat starts; when it ends, the pole comes back, but only if this swap put
-- the weapons on and they're still what you're holding.
local combatSwapped -- the pole to put back after combat
local function CombatStarted()
    combatSwapped = nil
    if not (db and db.combatSwap) or not HasPoleEquipped() then return end
    local pole = GetInventoryItemID("player", 16)
    if EquipWeapons() then combatSwapped = pole end
end

local function CombatEnded()
    local pole = combatSwapped
    combatSwapped = nil
    if not pole or not db.combatSwap then return end
    if UnitIsDeadOrGhost and UnitIsDeadOrGhost("player") then return end
    if HasPoleEquipped() then return end -- already back on the pole
    local w = CharData().weapons
    if not (w and GetInventoryItemID("player", 16) == w.mh) then return end -- you changed weapons yourself
    if CursorHasItem and CursorHasItem() then return end
    if ItemCount(pole) == 0 then return end
    local equip = (C_Item and C_Item.EquipItemByName) or EquipItemByName
    equip(pole, 16)
end

---------------------------------------------------------------------------
-- Learning from your own fishing
---------------------------------------------------------------------------

local castSkill, lastFishing = nil, 0

local function EffectiveSkill()
    local rank, bonus = GetFishingSkill()
    return rank and (rank + (bonus or 0))
end

local function Learned(key)
    db.learned = db.learned or {}
    db.learned[key] = db.learned[key] or {}
    return db.learned[key]
end

-- A cast landed. If your skill is under the listed Minimum, that Minimum
-- is too high for this water: lower it to your skill, rounded down to a 5.
local function LearnFromCast()
    castSkill, lastFishing = EffectiveSkill(), GetTime()
    if not (db.learn and castSkill) then return end
    local entry, key = Lookup()
    if not key or key == "" then return end
    local shown = Effective(entry, key)
    local newMin = math.floor(castSkill / 5) * 5
    if shown and shown.min and newMin >= shown.min then return end
    Learned(key).min = newMin
    if entry then
        Say(string.format("you cast in %s with %d skill, so its Minimum is now %d (was %d).", key, castSkill, newMin, shown.min))
    else
        -- No listed numbers: each cast that lands narrows the Minimum down.
        Say(string.format("no listed numbers for %s; you cast there with %d skill, so its Minimum is %d or less.", key, castSkill, newMin))
    end
end

-- A fish got away. If your skill is at or above the listed Recommended,
-- it's too low: raise it to the next 5 above your skill.
local function LearnFromGetaway()
    if not db.learn or GetTime() - lastFishing > 30 then return end
    local skill = castSkill or EffectiveSkill()
    if not skill then return end
    local entry, key = Lookup()
    if not key or key == "" then return end
    local shown = Effective(entry, key)
    -- Listed water: only a getaway at or above Recommended says it's too low.
    -- Unlisted water: every getaway tells us Recommended is above your skill.
    if entry and skill < shown.full then return end
    local newFull = math.floor(skill / 5) * 5 + 5
    if shown and shown.full and newFull <= shown.full then return end
    Learned(key).full = newFull
    if entry then
        Say(string.format("a fish got away in %s at %d skill, so its Recommended is now %d (was %d).", key, skill, newFull, shown.full))
    else
        Say(string.format("no listed numbers for %s; a fish got away at %d skill, so its Recommended is at least %d.", key, skill, newFull))
    end
end

local FISH_ESCAPED = ERR_FISH_ESCAPED or "Your fish got away!"
-- Jump keys that aren't fishing keys (Space fishing off, or another jump key).
if JumpOrAscendStart then
    hooksecurefunc("JumpOrAscendStart", function() JumpSwap() end)
end

swapButton:HookScript("OnClick", function()
    -- Runs right after the swap macro. If we're going pole -> two identical
    -- weapons, remember to fill the off-hand once the main hand is on.
    local w = CharData().weapons
    if HasPoleEquipped() and w and w.mh and w.oh and w.oh == w.mh then
        offhandWanted = w.oh
        offhandUntil = GetTime() + 5
    end
end)

-- Equipment changes arrive one slot at a time, so wait until they settle
-- before deciding what "your weapons" are.
local function RecordGear()
    if recordTimer then recordTimer:Cancel() end
    recordTimer = C_Timer.NewTimer(0.5, function()
        recordTimer = nil
        local data = CharData()
        local mh = GetInventoryItemID("player", 16)
        local oh = GetInventoryItemID("player", 17)
        if IsPole(mh) then
            data.pole = mh
        elseif mh and not (offhandWanted and not oh) then
            -- (skip while the off-hand follow-up is still pending, so an
            -- empty off-hand isn't remembered by mistake)
            data.weapons = { mh = mh, oh = oh }
        end
        UpdateSwap()
    end)
end

swapButton:SetScript("OnEnter", function(self)
    WindowTip()
    local data = CharData()
    if HasPoleEquipped() then
        local w = data.weapons
        if w and w.mh then
            GameTooltip:SetText("Swap to weapons")
            GameTooltip:AddLine(ItemName(w.mh) or ("item " .. w.mh), 1, 1, 1)
            if w.oh then GameTooltip:AddLine(ItemName(w.oh) or ("item " .. w.oh), 1, 1, 1) end
        else
            GameTooltip:SetText("No weapons remembered yet")
            GameTooltip:AddLine("Equip your weapons once and they'll be remembered.", 0.8, 0.8, 0.8, true)
        end
    else
        local pole = PoleToEquip()
        if pole then
            GameTooltip:SetText("Swap to fishing pole")
            GameTooltip:AddLine(ItemName(pole) or ("item " .. pole), 1, 1, 1)
        else
            GameTooltip:SetText("No fishing pole found")
            GameTooltip:AddLine("No fishing pole in your bags.", 0.8, 0.8, 0.8, true)
        end
    end
    GameTooltip:AddLine("Works in combat. Keybind: Key Bindings > Forever Fishing Utilities.", 0.6, 0.6, 0.6, true)
    GameTooltip:Show()
end)
swapButton:SetScript("OnLeave", HideWindowTip)

---------------------------------------------------------------------------
-- Buff glow on the lure and food buttons
---------------------------------------------------------------------------
-- The same green border the toggles use, shown while the buff is up: a lure
-- on the fishing pole, or a Well Fed buff that adds Fishing skill.

local UpdateGlows
do
local function AddGlow(button)
    local glow = button:CreateTexture(nil, "OVERLAY")
    glow:SetPoint("TOPLEFT", -2, 2)
    glow:SetPoint("BOTTOMRIGHT", 2, -2)
    glow:SetTexture("Interface\\Buttons\\UI-ActionButton-Border")
    glow:SetBlendMode("ADD")
    glow:SetVertexColor(0.3, 1, 0.3)
    glow:SetTexCoord(0.2, 0.8, 0.2, 0.8)
    glow:Hide()
    return glow
end
local lureGlow = AddGlow(lureButton)
local foodGlow = AddGlow(foodButton)

-- Reads buff tooltips to find one that mentions Fishing.
local scanTip = CreateFrame("GameTooltip", "ForeverFishingUtilitiesScanTip", nil, "GameTooltipTemplate")
scanTip:SetOwner(WorldFrame, "ANCHOR_NONE")
local FISHING_WORD = FishingName()

-- Forever makes auras "secret" in combat (and maybe elsewhere): addon code
-- that reads them then raises an error. Returns nil when they can't be read.
local function AurasSecret()
    if InCombatLockdown() then return true end
    if C_Secrets and C_Secrets.ShouldAurasBeSecret and C_Secrets.ShouldAurasBeSecret() then
        return true
    end
    return false
end

local function BuffName(i)
    if C_UnitAuras and C_UnitAuras.GetBuffDataByIndex then
        local ok, aura = pcall(C_UnitAuras.GetBuffDataByIndex, "player", i)
        if not ok then return nil, true end
        return aura and aura.name
    elseif UnitBuff then
        return UnitBuff("player", i)
    end
end

local function HasFishingFoodBuff()
    if AurasSecret() then return nil end
    for i = 1, 40 do
        local name, failed = BuffName(i)
        if failed then return nil end
        if not name then return false end
        scanTip:ClearLines()
        scanTip:SetUnitBuff("player", i)
        for line = 2, scanTip:NumLines() or 0 do
            local fs = _G["ForeverFishingUtilitiesScanTipTextLeft" .. line]
            local text = fs and fs:GetText()
            if text and text:find(FISHING_WORD, 1, true) then return true end
        end
    end
    return false
end

function UpdateGlows()
    local hasLure = HasPoleEquipped() and GetWeaponEnchantInfo() and true or false
    lureGlow:SetShown(hasLure)
    -- While buffs can't be read, the food glow keeps its last state.
    local hasFood = HasFishingFoodBuff()
    if hasFood ~= nil then foodGlow:SetShown(hasFood) end
end
end

---------------------------------------------------------------------------
-- Button layout
---------------------------------------------------------------------------
-- Each button can be hidden in the options. The ones that show close up
-- from the right: top row swap, Space, sound; bottom row lure, food. Some are
-- secure buttons, so this only runs out of combat.

local layoutPending = false
local function LayoutButtons()
    if InCombatLockdown() then
        layoutPending = true
        return
    end
    layoutPending = false
    local function Place(list, point, y)
        local n = 0
        for _, item in ipairs(list) do
            local button, shown = item[1], db[item[2]]
            button:ClearAllPoints()
            if shown then
                button:SetPoint(point, -6 - 20 * n, y)
                button:Show()
                n = n + 1
            else
                button:Hide()
            end
        end
        return n
    end
    topCount = Place({ { swapButton, "showSwap" }, { spaceButton, "showSpace" }, { soundButton, "showSound" } }, "TOPRIGHT", -4)
    bottomCount = Place({ { lureButton, "showLure" }, { foodButton, "showFood" } }, "BOTTOMRIGHT", 7)
    line1:SetPoint("TOPRIGHT", -(topCount > 0 and (6 + 20 * topCount) or 8), -7)
    bookShown = db.showBook and true or false
    trainIcon:SetShown(bookShown)
    Refresh()
end

---------------------------------------------------------------------------
-- Events
---------------------------------------------------------------------------

frame:RegisterEvent("ADDON_LOADED")
frame:RegisterEvent("PLAYER_ENTERING_WORLD")
frame:RegisterEvent("PLAYER_LOGOUT")
frame:RegisterEvent("ZONE_CHANGED")
frame:RegisterEvent("ZONE_CHANGED_INDOORS")
frame:RegisterEvent("ZONE_CHANGED_NEW_AREA")
frame:RegisterEvent("SKILL_LINES_CHANGED")
frame:RegisterEvent("PLAYER_EQUIPMENT_CHANGED")
frame:RegisterEvent("CHAT_MSG_SKILL")
frame:RegisterEvent("PLAYER_REGEN_DISABLED")
frame:RegisterEvent("PLAYER_REGEN_ENABLED")
frame:RegisterEvent("UPDATE_BINDINGS")
frame:RegisterEvent("BAG_UPDATE_DELAYED")
frame:RegisterEvent("GLOBAL_MOUSE_DOWN")
frame:RegisterEvent("GLOBAL_MOUSE_UP")
frame:RegisterEvent("UI_ERROR_MESSAGE")
frame:RegisterEvent("PLAYER_LEVEL_UP")
frame:RegisterUnitEvent("UNIT_AURA", "player")
frame:RegisterUnitEvent("UNIT_INVENTORY_CHANGED", "player")
frame:RegisterEvent("PLAYER_STARTED_MOVING")
frame:RegisterEvent("PLAYER_STOPPED_MOVING")
frame:RegisterUnitEvent("UNIT_SPELLCAST_CHANNEL_START", "player")
frame:RegisterUnitEvent("UNIT_SPELLCAST_CHANNEL_STOP", "player")

frame:SetScript("OnEvent", function(self, event, arg1, arg2, arg3)
    if event == "ADDON_LOADED" then
        if arg1 ~= ADDON then return end
        ForeverFishingUtilitiesDB = ForeverFishingUtilitiesDB or {}
        db = ForeverFishingUtilitiesDB
        for k, v in pairs(DEFAULTS) do
            if db[k] == nil then
                db[k] = type(v) == "table" and CopyTable(v) or v
            end
        end
        -- 1.9: Space fishing defaults to on and stays on across pole swaps.
        if not db.spaceDefaultOn then
            db.spaceOn = true
            db.spaceDefaultOn = true
        end
        -- 2.1: double right-click and sound mode became opt-in; switch them
        -- off once for existing setups, and drop data from removed features.
        -- 2.2: the window only shows with a pole equipped by default.
        if not db.poleOnlyDefault then
            db.poleOnly = true
            db.poleOnlyDefault = true
        end
        if not db.optInDefaults then
            db.doubleClick = false
            db.sound = false
            db.optInDefaults = true
        end
        -- 1.2: the jump-swap on/off became a choice: swap, or just jump.
        db.jumpSwap = nil
        -- "Just jumps" became the default; switch existing setups over once.
        if not db.movingJumpDefault then
            db.moving = "jump"
            db.movingJumpDefault = true
        end
        db.custom, db.stats, db.showStats, db.statsLineRemoved = nil, nil, nil, nil
        db.swapKey, db.mapInfo, db.doubleClickSpeed = nil, nil, nil
        self:ClearAllPoints()
        local p = db.point
        self:SetPoint(p[1], UIParent, p[3], p[4], p[5])
        -- Lures and their expiry don't fire a reliable event, so check every second.
        C_Timer.NewTicker(1, function()
            Refresh()
            UpdateGlows()
            -- The right lure depends on the water and your bonus, too.
            if BestLure(currentLure) ~= currentLure then UpdateLure() end
            UpdateCastAction()
        end)
        RegisterOptions()
        self:UnregisterEvent("ADDON_LOADED")
        return
    end
    if not db then return end

    if event == "GLOBAL_MOUSE_DOWN" then
        if arg1 == "RightButton" then OnRightDown() end
        return
    elseif event == "GLOBAL_MOUSE_UP" then
        if arg1 == "RightButton" then OnRightUp() end
        return
    elseif event == "PLAYER_STARTED_MOVING" or event == "PLAYER_STOPPED_MOVING" then
        if db.moving == "jump" and db.spaceOn and HasPoleEquipped() then UpdateKeys() end
        return
    elseif event == "UI_ERROR_MESSAGE" then
        -- (messageType, message) on current clients; just the message on old ones.
        if arg2 == FISH_ESCAPED or arg1 == FISH_ESCAPED then LearnFromGetaway() end
        return
    elseif event == "UNIT_SPELLCAST_CHANNEL_START" then
        if IsFishingSpell(arg3) then
            fishingActive = true
            LearnFromCast()
            -- Safety net: never leave the camera stuck following the mouse.
            if IsMouselooking and IsMouselooking() and not IsMouseButtonDown("RightButton") then
                MouselookStop()
            end
            if not InCombatLockdown() then ApplyFishingSettings() end
            UpdateKeys()
        end
        return
    elseif event == "UNIT_SPELLCAST_CHANNEL_STOP" then
        if fishingActive then
            fishingActive = false
            lastFishing = GetTime()
            UpdateKeys()
            RestoreSoon()
        end
        return
    elseif event == "BAG_UPDATE_DELAYED" then
        UpdateLure()
        UpdateFood()
        UpdateCastAction()
        UpdateSwap()
        if offhandWanted then FinishOffhand() end
        return
    elseif event == "SKILL_LINES_CHANGED" or event == "CHAT_MSG_SKILL" then
        UpdateLure()
    elseif event == "UNIT_AURA" or event == "UNIT_INVENTORY_CHANGED" then
        UpdateGlows()
        if event == "UNIT_INVENTORY_CHANGED" then UpdateCastAction() end
        return
    elseif event == "PLAYER_LEVEL_UP" then
        C_Timer.After(0.5, UpdateFood)
    elseif event == "PLAYER_ENTERING_WORLD" then
        RestoreSettings() -- left over from a crash, if any
        HookWorldMap()
        if not mapHooked and EventUtil and EventUtil.ContinueOnAddOnLoaded then
            EventUtil.ContinueOnAddOnLoaded("Blizzard_WorldMap", HookWorldMap)
        end
        C_Timer.After(1, function()
            MigrateOldSwap()
            UpdateKeys()
            UpdateSpaceButton()
            UpdateLure()
            UpdateFood()
            LayoutButtons()
            RecordGear()
            UpdateSwapKeys()
        end)
        if C_AddOns and C_AddOns.IsAddOnLoaded and C_AddOns.IsAddOnLoaded("BetterFishing") and not self.warned then
            self.warned = true
            Say("Better Fishing is also loaded. Disable it so the two don't fight over your keys.")
        end
    elseif event == "PLAYER_EQUIPMENT_CHANGED" then
        if arg1 == 16 or arg1 == 17 then
            RecordGear()
            if offhandWanted then C_Timer.After(0.2, FinishOffhand) end
        end
        UpdateKeys() -- Space only casts while the pole is on; otherwise it jumps
    elseif event == "UPDATE_BINDINGS" then
        UpdateKeys()
        UpdateSwapKeys()
        return
    elseif event == "PLAYER_REGEN_DISABLED" then
        -- Last moment before lockdown: give the keys back for combat.
        ClearOverrideBindings(keyOwner)
        ClearOverrideBindings(mouseOwner)
        keysPending = true
        CombatStarted()
        return
    elseif event == "PLAYER_REGEN_ENABLED" then
        if keysPending then
            UpdateKeys()
            UpdateSpaceButton()
        end
        if lurePending then UpdateLure() end
        if foodPending then UpdateFood() end
        if layoutPending then LayoutButtons() end
        if swapPending then UpdateSwap() end
        if swapKeysPending then UpdateSwapKeys() end
        if offhandWanted then
            offhandUntil = GetTime() + 5 -- swapped mid-fight: finish now
            FinishOffhand()
        end
        CombatEnded()
        -- falls through to Refresh, which can resize the window again
    elseif event == "PLAYER_LOGOUT" then
        RestoreSettings()
        return
    end
    Refresh()
end)

---------------------------------------------------------------------------
-- Options panel (Options > AddOns > Forever Fishing Utilities)
---------------------------------------------------------------------------

local function ResetPosition()
    db.point = CopyTable(DEFAULTS.point)
    if InCombatLockdown() then
        Say("the window can't move in combat; it will reset after combat.")
    else
        frame:ClearAllPoints()
        frame:SetPoint("TOP", UIParent, "TOP", 0, -120)
        Say("window moved back to its default spot: centred near the top of the screen.")
    end
end

local panel = CreateFrame("Frame", "ForeverFishingUtilitiesOptions")
panel.name = "Forever Fishing Utilities"
panel:Hide()
local optionsCategory
local panelWidgets = {} -- each has :Sync() to show the saved setting

local function PanelHeader(text, anchor, yOffset)
    local fs = panel:CreateFontString(nil, "ARTWORK", "GameFontNormal")
    fs:SetPoint("TOPLEFT", anchor, "BOTTOMLEFT", 0, yOffset or -14)
    fs:SetText(text)
    return fs
end

local function PanelCheck(label, hint, anchor, get, set, xOffset, yOffset)
    local cb = CreateFrame("CheckButton", nil, panel, "UICheckButtonTemplate")
    cb:SetSize(26, 26)
    cb:SetPoint("TOPLEFT", anchor, "BOTTOMLEFT", xOffset or 0, yOffset or -2)
    local text = cb:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
    text:SetPoint("LEFT", cb, "RIGHT", 2, 0)
    text:SetText(label)
    cb:SetHitRectInsets(0, -text:GetStringWidth() - 4, 0, 0)
    cb:SetScript("OnClick", function(self)
        set(self:GetChecked() and true or false)
        for _, w in ipairs(panelWidgets) do w:Sync() end
        Refresh()
    end)
    if hint then
        cb:SetScript("OnEnter", function(self)
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            GameTooltip:SetText(label)
            GameTooltip:AddLine(hint, 1, 1, 1, true)
            GameTooltip:Show()
        end)
        cb:SetScript("OnLeave", function() GameTooltip:Hide() end)
    end
    function cb:Sync() self:SetChecked(get() and true or false) end
    panelWidgets[#panelWidgets + 1] = cb
    return cb
end

do
    local title = panel:CreateFontString(nil, "ARTWORK", "GameFontNormalLarge")
    title:SetPoint("TOPLEFT", 16, -16)
    title:SetText("Forever Fishing Utilities")

    local hWindow = PanelHeader("Window", title, -16)
    local cShown = PanelCheck("Show the window", "Same as typing /ffu.", hWindow,
        function() return db.shown end, function(v) db.shown = v end, 0, -4)
    local cPole = PanelCheck("Only with a fishing pole equipped",
        "Hide the window whenever you aren't holding a fishing pole.", cShown,
        function() return db.poleOnly end, function(v) db.poleOnly = v end)
    local cLock = PanelCheck("Lock the window in place", "Stops the window from being dragged.", cPole,
        function() return db.locked end, function(v) db.locked = v end)

    local reset = CreateFrame("Button", nil, panel, "UIPanelButtonTemplate")
    reset:SetSize(130, 22)
    reset:SetPoint("LEFT", cLock, "RIGHT", 220, 0)
    reset:SetText("Reset position")
    reset:SetScript("OnClick", ResetPosition)

    -- Buttons, in a column on the right.
    local hButtons = panel:CreateFontString(nil, "ARTWORK", "GameFontNormal")
    hButtons:SetPoint("TOPLEFT", hWindow, "TOPLEFT", 420, 0)
    hButtons:SetText("Buttons")
    local prev = hButtons
    for i, b in ipairs({
        { "Space fishing toggle", "showSpace", "The fishing icon in the top-right corner that turns Space fishing on and off." },
        { "Fishing sound toggle", "showSound", "The speaker in the top-right corner that turns fishing sound mode on and off." },
        { "Pole / weapon swap", "showSwap", "Swaps between your fishing pole and your weapons. The keybind works even when it's hidden." },
        { "Best lure", "showLure", "Puts the best lure in your bags on your pole." },
        { "Fishing food", "showFood", "Eats the best food in your bags that gives Fishing skill." },
        { "Training book", "showBook", "Next to Your Skill: how to learn the next Fishing rank." },
    }) do
        local key = b[2]
        prev = PanelCheck(b[1], b[3], prev, function() return db[key] end,
            function(v) db[key] = v; LayoutButtons() end, 0, i == 1 and -4 or -2)
    end

    local hCatch = PanelHeader("Catches list", cLock)
    local cDrops = PanelCheck("Show catches when hovering the zone name",
        "Hover the zone name at the top of the window to list what the water here can give, with catch rates.",
        hCatch, function() return db.dropTip end, function(v) db.dropTip = v end, 0, -4)
    local dirLabel = panel:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
    dirLabel:SetPoint("TOPLEFT", cDrops, "BOTTOMLEFT", 30, -6)
    dirLabel:SetText("Opens:")
    local function Direction(label, hint, value, anchor, x)
        local cb = PanelCheck(label, hint, dirLabel,
            function() return (db.flyout or "smart") == value end,
            function() db.flyout = value end)
        cb:ClearAllPoints()
        cb:SetPoint("LEFT", anchor, "RIGHT", x, 0)
        return cb
    end
    local dSmart = Direction("Smart", "Opens away from the nearer screen edge: downward when the window is in the top half of the screen, upward when it's in the bottom half.", "smart", dirLabel, 8)
    local dUp = Direction("Up", "Always opens above the window.", "up", dSmart, 60)
    Direction("Down", "Always opens below the window.", "down", dUp, 40)

    local hFish = PanelHeader("Fishing", cDrops, -44)
    local cSpace = PanelCheck("Space casts and clicks the bobber",
        "Only while a fishing pole is equipped. Without one, or in combat, Space jumps.", hFish,
        function() return db.spaceOn end, function(v) SetSpace(v) end, 0, -4)
    local cDbl = PanelCheck("Double right-click to cast", "Double right-click anywhere to cast while a fishing pole is equipped.", cSpace,
        function() return db.doubleClick end, function(v) db.doubleClick = v end)
    local moveLabel = panel:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
    moveLabel:SetPoint("TOPLEFT", cDbl, "BOTTOMLEFT", 4, -8)
    moveLabel:SetText("Jump while moving with the pole out:")
    local function Moving(label, hint, value, anchor, x)
        local cb = PanelCheck(label, hint, moveLabel,
            function() return (db.moving or "jump") == value end,
            function() db.moving = value; UpdateKeys() end)
        cb:ClearAllPoints()
        cb:SetPoint("LEFT", anchor, "RIGHT", x, 0)
        return cb
    end
    local mSwap = Moving("Swaps to weapons", "Out of combat, pressing jump while moving puts your weapons back on. If Space is your fishing key, that press swaps instead of jumping.", "swap", moveLabel, 8)
    Moving("Just jumps", "While you're moving, Space always jumps. Standing still with the pole out, it casts and clicks the bobber as usual.", "jump", mSwap, 130)
    local cCombat = PanelCheck("Swap to weapons when combat starts",
        "Pulled into a fight with your fishing pole out? Your weapons go on as combat starts, and the pole comes back when it ends (only if the pole was on when the fight began).", moveLabel,
        function() return db.combatSwap end, function(v) db.combatSwap = v end, -4, -8)
    local cLearn = PanelCheck("Correct Minimum and Recommended from my fishing",
        "The listed numbers come from Classic, and WoW: Forever's own values aren't fully known yet, so your fishing is used as a check. If you cast below a zone's Minimum, it's lowered to your skill (rounded down to a 5). If a fish gets away at or above Recommended, that's raised. In water with no listed numbers, your casts and getaways give a rough idea. Corrected numbers show a grey *. /ffu learn reset clears them.", cCombat,
        function() return db.learn end, function(v) db.learn = v end)
    local cAuto = PanelCheck("Auto lure: the cast key puts a lure on first",
        "When your pole has no lure, pressing the cast key (or double right-clicking) puts the best lure from your bags on instead of casting. Press again to fish. Right-click the lure button to turn this on or off.", cLearn,
        function() return db.autoLure end, function(v) db.autoLure = v; UpdateLure(); UpdateCastAction() end)
    local cAutoSmart = PanelCheck("Only below Recommended (always with Luremaster)",
        "Skip the lure when your skill already reaches the water's Recommended, since it can't help you there. If you have the Luremaster Legacy perk, a lure is always put on, for its extra fish.", cAuto,
        function() return db.autoLureSmart end, function(v) db.autoLureSmart = v; UpdateCastAction() end, 24)
    local cMap = PanelCheck("Fishing info on the world map",
        "Hover a zone on the world map to see its Minimum and Recommended fishing skill. Hold Shift to add its catches.", cAutoSmart,
        function() return db.mapTip end,
        function(v) db.mapTip = v; if not v then mapTip:Hide() end end)

    -- Sound goes in the right column, under Buttons.
    local hSound = PanelHeader("Sound", prev, -16)
    local cSound = PanelCheck("Quiet sounds while fishing",
        "While fishing, music, ambience, dialog and pet sounds are turned off and effects are loud. Your own settings come back afterwards.",
        hSound, function() return db.sound end, function(v) SetSound(v) end, 0, -4)

    local volLabel = panel:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
    volLabel:SetPoint("TOPLEFT", cSound, "BOTTOMLEFT", 4, -8)
    local slider = CreateFrame("Slider", nil, panel)
    slider:SetOrientation("HORIZONTAL")
    slider:SetSize(170, 16)
    slider:SetPoint("TOPLEFT", volLabel, "BOTTOMLEFT", 0, -8)
    slider:SetMinMaxValues(0, 100)
    slider:SetValueStep(5)
    if slider.SetObeyStepOnDrag then slider:SetObeyStepOnDrag(true) end
    local track = slider:CreateTexture(nil, "BACKGROUND")
    track:SetColorTexture(1, 1, 1, 0.2)
    track:SetPoint("LEFT")
    track:SetPoint("RIGHT")
    track:SetHeight(4)
    local thumb = slider:CreateTexture(nil, "OVERLAY")
    thumb:SetTexture("Interface\\Buttons\\UI-SliderBar-Button-Horizontal")
    thumb:SetSize(24, 24)
    slider:SetThumbTexture(thumb)
    local function VolumeText()
        volLabel:SetText("Volume while fishing: " .. math.floor(db.volume * 100 + 0.5) .. "%")
    end
    slider:SetScript("OnValueChanged", function(self, value)
        if self.syncing then return end
        db.volume = math.floor(value / 5 + 0.5) * 5 / 100
        VolumeText()
        if db.sound and db.cvarCache then ApplySound() end
    end)
    function slider:Sync()
        self.syncing = true
        self:SetValue(math.floor(db.volume * 100 + 0.5))
        self.syncing = false
        VolumeText()
    end
    panelWidgets[#panelWidgets + 1] = slider

    local keys = panel:CreateFontString(nil, "ARTWORK", "GameFontDisable")
    keys:SetPoint("TOPLEFT", cMap, "BOTTOMLEFT", 0, -18)
    keys:SetText("Keybinds: Options > Keybindings > AddOns > Forever Fishing Utilities")
end

panel:SetScript("OnShow", function()
    if not db then return end
    for _, w in ipairs(panelWidgets) do w:Sync() end
end)

function RegisterOptions()
    if Settings and Settings.RegisterCanvasLayoutCategory then
        optionsCategory = Settings.RegisterCanvasLayoutCategory(panel, panel.name)
        Settings.RegisterAddOnCategory(optionsCategory)
    elseif InterfaceOptions_AddCategory then
        InterfaceOptions_AddCategory(panel)
    end
end

local function OpenOptions()
    if InCombatLockdown() then
        Say("the options can't open in combat.")
        return
    end
    if optionsCategory and Settings and Settings.OpenToCategory then
        Settings.OpenToCategory(optionsCategory.GetID and optionsCategory:GetID() or optionsCategory.ID)
    elseif InterfaceOptionsFrame_OpenToCategory then
        InterfaceOptionsFrame_OpenToCategory(panel)
        InterfaceOptionsFrame_OpenToCategory(panel)
    end
end

---------------------------------------------------------------------------
-- Slash commands
---------------------------------------------------------------------------

local function OnOff(v) return v and "|cff40c040on|r" or "|cff9d9d9doff|r" end

SLASH_FOREVERFISHINGUTILITIES1 = "/ffu"
SlashCmdList.FOREVERFISHINGUTILITIES = function(msg)
    local cmd, a = strsplit(" ", strtrim(msg or ""):lower())
    if cmd == "" then
        db.shown = not db.shown
        Say(db.shown and "window shown." or "window hidden. Type /ffu to show it again.")
    elseif cmd == "pole" then
        db.poleOnly = not db.poleOnly
        Say(db.poleOnly and "window only shows with a fishing pole equipped." or "window always shown.")
    elseif cmd == "lock" then
        db.locked = not db.locked
        Say(db.locked and "window locked." or "window unlocked. Drag to move it.")
    elseif cmd == "reset" then
        ResetPosition()
    elseif cmd == "options" or cmd == "config" then
        OpenOptions()
        return
    elseif cmd == "catches" then
        if a == "smart" or a == "up" or a == "down" then
            db.flyout = a
            db.dropTip = true
            Say("catches list opens " .. (a == "smart" and "away from the nearer screen edge" or a) .. ".")
        else
            db.dropTip = not db.dropTip
            Say("catches list on hovering the zone name " .. OnOff(db.dropTip) .. ".")
        end
    elseif cmd == "space" then
        ToggleSpace()
        Say("Space fishing " .. OnOff(db.spaceOn) .. ".")
    elseif cmd == "dblclick" then
        db.doubleClick = not db.doubleClick
        Say("double right-click to cast " .. OnOff(db.doubleClick) .. ".")
    elseif cmd == "autolure" then
        if a == "smart" then
            db.autoLureSmart = not db.autoLureSmart
            Say("auto lure only below Recommended " .. OnOff(db.autoLureSmart) .. ".")
        else
            db.autoLure = not db.autoLure
            Say("auto lure " .. OnOff(db.autoLure) .. ".")
        end
        UpdateLure()
        UpdateCastAction()
    elseif cmd == "combatswap" then
        db.combatSwap = not db.combatSwap
        Say("swapping to weapons when combat starts " .. OnOff(db.combatSwap) .. ".")
    elseif cmd == "learn" then
        if a == "reset" then
            db.learned = {}
            Say("corrected Minimum and Recommended numbers cleared; back to the listed values.")
        else
            db.learn = not db.learn
            Say("correcting Minimum and Recommended from your fishing " .. OnOff(db.learn) .. ".")
        end
    elseif cmd == "moving" then
        if a == "swap" or a == "jump" then
            db.moving = a
        else
            db.moving = (db.moving == "jump") and "swap" or "jump"
        end
        UpdateKeys()
        Say("jumping while moving with the pole out " .. (db.moving == "jump" and "just jumps." or "swaps to your weapons."))
    elseif cmd == "map" then
        db.mapTip = not db.mapTip
        if not db.mapTip then mapTip:Hide() end
        Say("world map fishing info " .. OnOff(db.mapTip) .. ".")
    elseif cmd == "sound" then
        local vol = tonumber(a)
        if vol then
            db.volume = math.max(0, math.min(1, vol > 1 and vol / 100 or vol))
            SetSound(true)
            Say("fishing sound mode " .. OnOff(true) .. ", volume " .. math.floor(db.volume * 100 + 0.5) .. "%.")
        else
            SetSound(not db.sound)
            Say("fishing sound mode " .. OnOff(db.sound) .. ".")
        end
    else
        Say("commands:")
        print("  |cffffd100/ffu|r  show or hide the window")
        print("  |cffffd100/ffu pole|r  only show it with a pole equipped (" .. OnOff(db.poleOnly) .. ")")
        print("  |cffffd100/ffu lock|r  lock the window in place (" .. OnOff(db.locked) .. ")")
        print("  |cffffd100/ffu reset|r  move the window back to its default spot (centred near the top of the screen)")
        print("  |cffffd100/ffu space|r  Space casts and clicks the bobber (" .. OnOff(db.spaceOn) .. ")")
        print("  |cffffd100/ffu dblclick|r  double right-click to cast (" .. OnOff(db.doubleClick) .. ")")
        print("  |cffffd100/ffu moving [swap|jump]|r  what jumping while moving with the pole out does (" .. (db.moving or "jump") .. ")")
        print("  |cffffd100/ffu autolure [smart]|r  cast key puts a lure on first (" .. OnOff(db.autoLure) .. "; only below Recommended " .. OnOff(db.autoLureSmart) .. ")")
        print("  |cffffd100/ffu combatswap|r  swap to weapons when combat starts, back to the pole after (" .. OnOff(db.combatSwap) .. ")")
        print("  |cffffd100/ffu learn [reset]|r  correct Minimum/Recommended from your casts and getaways (" .. OnOff(db.learn) .. ")")
        print("  |cffffd100/ffu map|r  fishing info when hovering zones on the world map (" .. OnOff(db.mapTip) .. ")")
        print("  |cffffd100/ffu sound [0-100]|r  quiet all but the splash while fishing (" .. OnOff(db.sound) .. ")")
        print("  |cffffd100/ffu catches [smart|up|down]|r  list catches when hovering the zone name (" .. OnOff(db.dropTip) .. ", opens " .. (db.flyout or "smart") .. ")")
        print("  |cffffd100/ffu options|r  open the options panel")
        print("  Keybinds: Options > Keybindings > AddOns > Forever Fishing Utilities")
        return
    end
    Refresh()
end
