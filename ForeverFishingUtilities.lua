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
    jumpSwap = true,      -- jumping while moving with the pole out swaps back to weapons
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

-- Returns base rank, bonus (pole, lure, gear) and current cap, or nil if Fishing isn't learned.
local function GetFishingSkill()
    if GetProfessions and GetProfessionInfo then
        local _, _, _, fishing = GetProfessions()
        if fishing then
            local _, _, rank, maxRank, _, _, skillLine, modifier = GetProfessionInfo(fishing)
            if rank and (skillLine == nil or skillLine == FISHING_SKILLLINE) then
                return rank, modifier or 0, maxRank
            end
        end
    end
    if GetNumSkillLines and GetSkillLineInfo then
        local name = FishingName()
        for i = 1, GetNumSkillLines() do
            local skillName, isHeader, _, rank, temp, modifier, maxRank = GetSkillLineInfo(i)
            if not isHeader and skillName == name then
                return rank, (modifier or 0) + (temp or 0), maxRank
            end
        end
    end
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

-- Sizes the window to fit its lines.
local function Fit(lines)
    local w = 160
    for _, fs in ipairs(lines) do
        w = math.max(w, fs:GetStringWidth() + ((fs == line1 and 56) or (fs == lineSkill and 54) or 18))
    end
    frame:SetWidth(w)
    frame:SetHeight(20 + 14 * #lines) -- a little extra so the corner buttons clear line 2
end

-- Character level needed to learn the next Fishing rank, by current cap.
local NEXT_RANK_LEVEL = { [75] = 10, [150] = 20, [225] = 35 }
local SKILL_MAX = 300

-- True when skill is stuck at its cap and the next rank can be learned now.
local function NeedsNextRank(rank, maxRank)
    if not maxRank or maxRank <= 0 or rank < maxRank then return false end
    if maxRank >= SKILL_MAX then return false end
    local needLevel = NEXT_RANK_LEVEL[maxRank]
    if needLevel and UnitLevel("player") < needLevel then return false end
    return true
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
local function Thresholds(entry)
    return COLOR.orange .. "Minimum: " .. entry.min .. "|r   " ..
        COLOR.yellow .. "Recommended: " .. entry.full .. "|r"
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

    local place = zone
    if sub ~= "" and sub ~= zone then place = zone .. " - " .. sub end
    line1:SetText(place)

    if entry then
        local note = (matched == sub and sub ~= "") and (COLOR.grey .. "  (subzone)|r") or ""
        line2:SetText(Thresholds(entry) .. note)
    else
        line2:SetText(COLOR.grey .. "No fishing data for this zone yet|r")
    end

    lineSkill:SetText(SkillText())

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
    local dir = db.flyout
    if dir ~= "up" and dir ~= "down" then
        -- Smart: open away from whichever of the top and bottom screen edges is nearer.
        local _, y = frame:GetCenter()
        local scale = frame:GetEffectiveScale() / UIParent:GetEffectiveScale()
        dir = (y and y * scale > UIParent:GetHeight() / 2) and "down" or "up"
    end
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
    local entry = ns.ZONES[name]
    local added = false
    if entry then
        mapTip:AddLine(COLOR.orange .. "Minimum: " .. entry.min .. "|r   " ..
            COLOR.yellow .. "Recommended: " .. entry.full .. "|r")
        added = true
    end
    -- Bodies of water in this zone that need a different skill.
    for subName, parent in pairs(ns.SUBZONE_PARENT) do
        local subEntry = ns.SUBZONES[subName]
        if parent == name and subEntry then
            mapTip:AddLine(COLOR.grey .. subName .. ":|r " .. COLOR.orange .. subEntry.min ..
                "|r / " .. COLOR.yellow .. subEntry.full .. "|r")
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
    if not name or not (ns.ZONES[name] or ns.SUBZONE_PARENT[name]) then
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
    for _, key in ipairs(FishingKeys()) do
        if fishingActive then
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
    button:SetScript("OnLeave", function() GameTooltip:Hide() end)
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
    GameTooltip:SetOwner(self, "ANCHOR_BOTTOMLEFT")
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
    GameTooltip:SetOwner(self, "ANCHOR_BOTTOMLEFT")
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
-- Picks the lure with the biggest bonus that your base skill can use and that
-- you have in your bags. Clicking runs "/use <lure>" then "/use 16" (main
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

local function BestLure()
    local rank = GetFishingSkill()
    if not rank then return nil end
    for _, lure in ipairs(LURES) do
        if rank >= lure.req and ItemCount(lure.id) > 0 then return lure end
    end
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
    local lure = BestLure()
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

lureButton:SetScript("OnEnter", function(self)
    GameTooltip:SetOwner(self, "ANCHOR_BOTTOMLEFT")
    local lure = currentLure
    if lure then
        GameTooltip:SetText(ItemName(lure.id) or "Lure")
        GameTooltip:AddLine("+" .. lure.bonus .. " Fishing  ·  " .. ItemCount(lure.id) .. " in bags", 1, 1, 1)
        GameTooltip:AddLine("Click to put it on your fishing pole.", 0.8, 0.8, 0.8, true)
    else
        GameTooltip:SetText("No usable lure")
        GameTooltip:AddLine("No lure in your bags that your Fishing skill can use.", 0.8, 0.8, 0.8, true)
    end
    local hasLure, msLeft = GetWeaponEnchantInfo()
    if hasLure and msLeft and HasPoleEquipped() then
        GameTooltip:AddLine(" ")
        GameTooltip:AddLine("Lure on pole: " .. math.ceil(msLeft / 60000) .. " min left", 0.3, 1, 0.3)
    end
    GameTooltip:Show()
end)
lureButton:SetScript("OnLeave", function() GameTooltip:Hide() end)

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
swapButton:SetPoint("BOTTOMRIGHT", -26, 4)
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
    if InCombatLockdown() then return end -- tried again when combat ends
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
local lastJumpSwap = 0
function JumpSwap()
    if not (db and db.jumpSwap) or InCombatLockdown() or not HasPoleEquipped() then return end
    local moving = (IsPlayerMoving and IsPlayerMoving()) or (GetUnitSpeed("player") or 0) > 0
    if not moving then return end
    if GetTime() - lastJumpSwap < 1 then return end
    if CursorHasItem and CursorHasItem() then return end
    local w = CharData().weapons
    if not (w and w.mh) then return end
    lastJumpSwap = GetTime()
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
end
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
    GameTooltip:SetOwner(self, "ANCHOR_BOTTOMLEFT")
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
swapButton:SetScript("OnLeave", function() GameTooltip:Hide() end)

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
        db.custom, db.stats, db.showStats, db.statsLineRemoved = nil, nil, nil, nil
        db.swapKey, db.mapInfo, db.doubleClickSpeed = nil, nil, nil
        self:ClearAllPoints()
        local p = db.point
        self:SetPoint(p[1], UIParent, p[3], p[4], p[5])
        -- Lures and their expiry don't fire a reliable event, so check every second.
        C_Timer.NewTicker(1, Refresh)
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
    elseif event == "UNIT_SPELLCAST_CHANNEL_START" then
        if IsFishingSpell(arg3) then
            fishingActive = true
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
            UpdateKeys()
            RestoreSoon()
        end
        return
    elseif event == "BAG_UPDATE_DELAYED" then
        UpdateLure()
        UpdateSwap()
        if offhandWanted then FinishOffhand() end
        return
    elseif event == "SKILL_LINES_CHANGED" or event == "CHAT_MSG_SKILL" then
        UpdateLure()
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
        return
    elseif event == "PLAYER_REGEN_ENABLED" then
        if keysPending then
            UpdateKeys()
            UpdateSpaceButton()
        end
        if lurePending then UpdateLure() end
        if swapPending then UpdateSwap() end
        if swapKeysPending then UpdateSwapKeys() end
        if offhandWanted then
            offhandUntil = GetTime() + 5 -- swapped mid-fight: finish now
            FinishOffhand()
        end
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
    local cJump = PanelCheck("Jumping on the move swaps back to weapons",
        "With your fishing pole out, press jump while moving to put your weapons back on. Out of combat only. If Space is your fishing key, that press swaps instead of jumping.", cDbl,
        function() return db.jumpSwap end, function(v) db.jumpSwap = v end)
    local cMap = PanelCheck("Fishing info on the world map",
        "Hover a zone on the world map to see its Minimum and Recommended fishing skill. Hold Shift to add its catches.", cJump,
        function() return db.mapTip end,
        function(v) db.mapTip = v; if not v then mapTip:Hide() end end)

    local hSound = PanelHeader("Sound", cMap)
    local cSound = PanelCheck("Quiet everything but the splash while fishing",
        "While fishing, music, ambience, dialog and pet sounds are turned off and effects are loud. Your own settings come back afterwards.",
        hSound, function() return db.sound end, function(v) SetSound(v) end, 0, -4)

    local volLabel = panel:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
    volLabel:SetPoint("TOPLEFT", cSound, "BOTTOMLEFT", 30, -8)
    local slider = CreateFrame("Slider", nil, panel)
    slider:SetOrientation("HORIZONTAL")
    slider:SetSize(180, 16)
    slider:SetPoint("LEFT", volLabel, "LEFT", 190, 0)
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
        volLabel:SetText("Master volume while fishing: " .. math.floor(db.volume * 100 + 0.5) .. "%")
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
    keys:SetPoint("TOPLEFT", volLabel, "BOTTOMLEFT", -30, -22)
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
    elseif cmd == "jumpswap" then
        db.jumpSwap = not db.jumpSwap
        Say("jumping on the move swaps back to weapons " .. OnOff(db.jumpSwap) .. ".")
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
        print("  |cffffd100/ffu jumpswap|r  jump while moving to swap back to weapons (" .. OnOff(db.jumpSwap) .. ")")
        print("  |cffffd100/ffu map|r  fishing info when hovering zones on the world map (" .. OnOff(db.mapTip) .. ")")
        print("  |cffffd100/ffu sound [0-100]|r  quiet all but the splash while fishing (" .. OnOff(db.sound) .. ")")
        print("  |cffffd100/ffu catches [smart|up|down]|r  list catches when hovering the zone name (" .. OnOff(db.dropTip) .. ", opens " .. (db.flyout or "smart") .. ")")
        print("  |cffffd100/ffu options|r  open the options panel")
        print("  Keybinds: Options > Keybindings > AddOns > Forever Fishing Utilities")
        return
    end
    Refresh()
end
