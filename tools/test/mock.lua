-- Minimal WoW API stand-in for offline tests (Forever-like: no plain GetItemInfo).
-- Unknown globals become a stub that does nothing and returns nil; their names
-- are kept in UNKNOWN so a test can see what the addon touched.
local unpack = table.unpack or unpack
LOG = {}
function log(...) local t = {} for i = 1, select("#", ...) do t[#t+1] = tostring(select(i, ...)) end LOG[#LOG+1] = table.concat(t, " ") end
print = function(...) log("PRINT", ...) end
UNKNOWN = {}
local Stub = setmetatable({}, { __call = function() return nil end, __index = function(s) return s end })
setmetatable(_G, { __index = function(_, k)
  UNKNOWN[k] = true
  if type(k) == "string" and k:match("^[%u_%d]+$") then return nil end -- CONSTANTS: absent
  return Stub
end })

wipe = function(t) for k in pairs(t) do t[k] = nil end return t end
CopyTable = function(t) local c = {} for k, v in pairs(t) do c[k] = type(v) == "table" and CopyTable(v) or v end return c end
strtrim = function(s) return (s:gsub("^%s+", ""):gsub("%s+$", "")) end
strsplit = function(sep, s) local a, b = s:find(sep, 1, true) if not a then return s end return s:sub(1, a - 1), s:sub(b + 1) end
hooksecurefunc = function() end
GetTime = function() return NOW end
NOW = 1000
SlashCmdList = {}
UISpecialFrames = {}
DOUBLE_CLICK_TIME = 0.4
ERR_FISH_ESCAPED = "Your fish got away!"
GetItemInfo = nil -- Forever has none
GetSpellInfo = nil
ForeverFishingUtilitiesDB = false -- SavedVariables start empty

-- Frames: any unknown method is a no-op; a few are real.
frames = {}
local FrameMT = {}
FrameMT.__index = function(self, k)
  local v = rawget(FrameMT, k)
  if v then return v end
  return function() end
end
function FrameMT:SetScript(n, fn) self.scripts[n] = fn end
function FrameMT:GetScript(n) return self.scripts[n] end
function FrameMT:HookScript(n, fn) local old = self.scripts[n]; self.scripts[n] = function(...) if old then old(...) end fn(...) end end
function FrameMT:RegisterEvent(e) self.events[e] = true end
function FrameMT:RegisterUnitEvent(e) self.events[e] = true end
function FrameMT:UnregisterEvent(e) self.events[e] = nil end
function FrameMT:Show() self.shown = true end
function FrameMT:Hide() self.shown = false end
function FrameMT:SetShown(v) self.shown = v and true or false end
function FrameMT:IsShown() return self.shown end
function FrameMT:IsVisible() return self.shown end
function FrameMT:CreateTexture() return CreateFrame("Texture") end
function FrameMT:CreateFontString() return CreateFrame("FontString") end
function FrameMT:SetText(t) self.text = t end
function FrameMT:GetText() return self.text end
function FrameMT:GetStringWidth() return 100 end
function FrameMT:GetWidth() return 200 end
function FrameMT:GetHeight() return 50 end
function FrameMT:GetTop() return 500 end
function FrameMT:GetBottom() return 450 end
function FrameMT:GetCenter() return 400, 500 end
function FrameMT:GetEffectiveScale() return 1 end
function FrameMT:IsMouseOver() return false end
function FrameMT:IsOwned() return false end
function FrameMT:SetAttribute(k, v) self.attr[k] = v end
function FrameMT:GetAttribute(k) return self.attr[k] end
function FrameMT:GetChecked() return self.checked end
function FrameMT:SetChecked(v) self.checked = v end
function FrameMT:GetValue() return self.value or 0 end
function FrameMT:SetValue(v) self.value = v end
function FrameMT:GetName() return self.name end
-- Tooltips: TIPS[kind][id] = { "line 1", "line 2", ... }
TIPS = { inv = {}, buff = {} }
local function fill(self, lines)
  self.nlines = lines and #lines or 0
  for i = 1, 30 do
    local fs = _G[self.name .. "TextLeft" .. i]
    if rawget(_G, self.name .. "TextLeft" .. i) == nil then fs = CreateFrame("FontString", self.name .. "TextLeft" .. i) end
    fs.text = lines and lines[i]
  end
end
function FrameMT:ClearLines() fill(self, nil) end
function FrameMT:NumLines() return self.nlines or 0 end
function FrameMT:SetInventoryItem(_, slot) fill(self, TIPS.inv[slot]) end
function FrameMT:SetUnitBuff(_, i) fill(self, TIPS.buff[i]) end
function FrameMT:AddLine(t) self.lines = self.lines or {}; self.lines[#self.lines+1] = t end
function FrameMT:SetOwner() self.lines = {} end

function CreateFrame(kind, name, parent, template)
  local f = setmetatable({ kind = kind, name = name, scripts = {}, events = {}, attr = {}, shown = true }, FrameMT)
  frames[#frames+1] = f
  if name then rawset(_G, name, f) end
  return f
end
UIParent = CreateFrame("Frame", "UIParent"); WorldFrame = CreateFrame("Frame", "WorldFrame")
GameTooltip = CreateFrame("GameTooltip", "GameTooltip")

function fire(event, ...) for _, f in ipairs(frames) do if f.events[event] and f.scripts.OnEvent then f.scripts.OnEvent(f, event, ...) end end end
timers, TICKERS = {}, {}
C_Timer = {
  After = function(_, fn) timers[#timers+1] = fn end,
  NewTimer = function(_, fn) local t = { Cancel = function() end }; timers[#timers+1] = fn; return t end,
  NewTicker = function(_, fn) local t = { fn = fn }; function t:Cancel() self.cancelled = true end; TICKERS[#TICKERS+1] = t; return t end,
}
function flushTimers() for _ = 1, 5 do local t = timers; timers = {}; for _, fn in ipairs(t) do fn() end end end
function tick() NOW = NOW + 1.1; for _, t in ipairs(TICKERS) do if not t.cancelled then t.fn() end end end

-- Player state the tests change.
STATE = { rank = 200, modifier = 0, maxRank = 225, zone = "Stranglethorn Vale", sub = "", inv = { [16] = 45858 }, bags = {}, enchant = false, combat = false }
ITEMDB = { [45858] = { 2, 20 } } -- itemID -> classID, subclassID (2/20 = fishing pole)
InCombatLockdown = function() return STATE.combat end
GetProfessions = function() return nil, nil, nil, 4 end
GetProfessionInfo = function() return "Fishing", 1, STATE.rank, STATE.maxRank, 0, 0, 356, STATE.modifier end
GetRealZoneText = function() return STATE.zone end
GetZoneText = function() return STATE.zone end
GetSubZoneText = function() return STATE.sub end
GetInventoryItemID = function(_, slot) return STATE.inv[slot] end
GetWeaponEnchantInfo = function() if STATE.enchant then return true, 300000 end return false end
UnitLevel = function() return 40 end
UnitFactionGroup = function() return "Horde" end
UnitFullName = function() return "Tester", "Realm" end
GetRealmName = function() return "Realm" end
UnitAffectingCombat = function() return STATE.combat end
IsPlayerMoving = function() return false end
C_Item = {
  GetItemInfoInstant = function(id) local d = ITEMDB[id]; if d then return id, nil, nil, nil, nil, d[1], d[2] end end,
  GetItemCount = function(id) return STATE.bags[id] or 0 end,
  GetItemIconByID = function(id) return "icon" .. id end,
  GetItemNameByID = function(id) return "item" .. id end,
}
C_UnitAuras = { GetBuffDataByIndex = function(_, i) if TIPS.buff[i] then return { name = TIPS.buff[i][1] } end end }
C_Spell = { GetSpellName = function(id) if id == 7620 then return "Fishing" end end, GetSpellInfo = function(s) if s == "Fishing" or s == 7620 or s == 131474 then return { name = "Fishing" } end end }
C_Container = {
  GetContainerNumSlots = function() return 0 end,
  GetContainerItemInfo = function() return nil end,
  GetContainerItemID = function() return nil end,
}
GetNumGroupMembers = function() return 0 end
GetBindingKey = function() return nil end
