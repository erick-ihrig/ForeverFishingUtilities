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
    poleOnly = false,
    locked = false,
    point = { "TOP", "UIParent", "TOP", 0, -120 },
    spaceOn = true,       -- Space casts and interacts while a pole is equipped (jumps otherwise)
    doubleClick = false,  -- double right-click casts (opt-in)
    doubleClickSpeed = 0.4,
    sound = false,        -- quiet everything but effects while fishing (opt-in)
    volume = 1,           -- master volume while fishing
}

local db

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
lineSkill:SetPoint("TOPLEFT", line2, "BOTTOMLEFT", 0, -3)
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
    frame:SetHeight(17 + 14 * #lines) -- a little extra so the corner buttons clear line 2
end

local function SkillText()
    local rank, bonus = GetFishingSkill()
    if not rank then
        return "Your Skill: " .. COLOR.grey .. "not learned|r"
    end
    local text = "Your Skill: " .. COLOR.white .. (rank + (bonus or 0)) .. "|r"
    if bonus and bonus ~= 0 then
        text = text .. COLOR.grey .. "  (" .. rank .. (bonus > 0 and " +" or " ") .. bonus .. ")|r"
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

local lastMapZone
local function UpdateMapTip()
    local map = WorldMapFrame
    local scroll = map and map.ScrollContainer
    if not (map and map:IsShown() and scroll and scroll:IsMouseOver()) then
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
    -- Rebuild only when the zone changes; a cursor-anchored tooltip follows
    -- the mouse by itself.
    if name ~= lastMapZone or not mapTip:IsShown() then
        lastMapZone = name
        mapTip:SetOwner(UIParent, "ANCHOR_CURSOR_RIGHT", 20, 0)
        mapTip:AddLine(name .. " fishing", 1, 0.82, 0)
        AddZoneLines(name)
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
    for _, key in ipairs(FishingKeys()) do
        if fishingActive then
            SetOverrideBinding(keyOwner, true, key, "INTERACTTARGET")
        else
            SetOverrideBindingClick(keyOwner, true, key, CAST_BUTTON_NAME)
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
    if gap < 0.04 or gap > db.doubleClickSpeed then return end
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
        if w.oh then toWeapons = toWeapons .. "\n/equipslot 17 item:" .. w.oh end
    end
    local pole = PoleToEquip()
    swapButton:SetAttribute("toWeapons", toWeapons)
    swapButton:SetAttribute("toPole", pole and ("/equipslot 16 item:" .. pole) or "")
end

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
        elseif mh then
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
        if not db.optInDefaults then
            db.doubleClick = false
            db.sound = false
            db.optInDefaults = true
        end
        db.custom, db.stats, db.showStats, db.statsLineRemoved = nil, nil, nil, nil
        db.swapKey, db.mapInfo = nil, nil
        self:ClearAllPoints()
        local p = db.point
        self:SetPoint(p[1], UIParent, p[3], p[4], p[5])
        -- Lures and their expiry don't fire a reliable event, so check every second.
        C_Timer.NewTicker(1, Refresh)
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
        if arg1 == 16 or arg1 == 17 then RecordGear() end
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
        -- falls through to Refresh, which can resize the window again
    elseif event == "PLAYER_LOGOUT" then
        RestoreSettings()
        return
    end
    Refresh()
end)

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
        db.point = CopyTable(DEFAULTS.point)
        if InCombatLockdown() then
            Say("the window can't move in combat; it will reset after combat.")
        else
            frame:ClearAllPoints()
            frame:SetPoint("TOP", UIParent, "TOP", 0, -120)
            Say("window moved back to the top.")
        end
    elseif cmd == "space" then
        ToggleSpace()
        Say("Space fishing " .. OnOff(db.spaceOn) .. ".")
    elseif cmd == "dblclick" then
        local speed = tonumber(a)
        if speed then
            db.doubleClickSpeed = math.max(0.1, math.min(0.8, speed))
            db.doubleClick = true
            Say("double right-click to cast " .. OnOff(true) .. " (" .. db.doubleClickSpeed .. "s between clicks).")
        else
            db.doubleClick = not db.doubleClick
            Say("double right-click to cast " .. OnOff(db.doubleClick) .. ".")
        end
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
        print("  |cffffd100/ffu reset|r  move the window back to the top")
        print("  |cffffd100/ffu space|r  Space casts and clicks the bobber (" .. OnOff(db.spaceOn) .. ")")
        print("  |cffffd100/ffu dblclick [sec]|r  double right-click to cast (" .. OnOff(db.doubleClick) .. ")")
        print("  |cffffd100/ffu sound [0-100]|r  quiet all but the splash while fishing (" .. OnOff(db.sound) .. ")")
        print("  Keybinds: Options > Keybindings > AddOns > Forever Fishing Utilities")
        return
    end
    Refresh()
end
