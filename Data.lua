-- Forever Fishing Utilities: reference data
-- Each entry is { min = skill needed to cast, full = skill where no fish get away }.
-- Values are the Classic-era tables (Warcraft Tavern, Legacy WoW, Blizzard Watch),
-- which WoW Forever guides match so far. Keys are the enUS names returned by
-- GetRealZoneText() and GetSubZoneText().

local _, ns = ...

local STARTER = { min = 1,   full = 25  }
local T1      = { min = 1,   full = 75  }
local T2      = { min = 55,  full = 150 }
local T3      = { min = 130, full = 225 }
local T4      = { min = 205, full = 300 }
local T5      = { min = 330, full = 425 }

-- Every water's Minimum is its Recommended minus this, but never below 1
-- (so the starter and tier 1 gaps look smaller).
ns.GAP = 95

ns.ZONES = {
    -- Starter zones
    ["Dun Morogh"] = STARTER, ["Durotar"] = STARTER, ["Elwynn Forest"] = STARTER,
    ["Mulgore"] = STARTER, ["Teldrassil"] = STARTER, ["Tirisfal Glades"] = STARTER,

    -- Tier 1: cities, second-ring zones, low dungeons
    ["Stormwind City"] = T1, ["Ironforge"] = T1, ["Darnassus"] = T1,
    ["Orgrimmar"] = T1, ["Thunder Bluff"] = T1, ["Undercity"] = T1,
    ["The Barrens"] = T1, ["Darkshore"] = T1, ["Loch Modan"] = T1,
    ["Silverpine Forest"] = T1, ["Westfall"] = T1,
    ["Blackfathom Deeps"] = T1, ["The Deadmines"] = T1, ["Wailing Caverns"] = T1,

    -- Tier 2
    ["Ashenvale"] = T2, ["Duskwood"] = T2, ["Hillsbrad Foothills"] = T2,
    ["Redridge Mountains"] = T2, ["Stonetalon Mountains"] = T2, ["Wetlands"] = T2,

    -- Tier 3
    ["Alterac Mountains"] = T3, ["Arathi Highlands"] = T3, ["Desolace"] = T3,
    ["Dustwallow Marsh"] = T3, ["Stranglethorn Vale"] = T3, ["Swamp of Sorrows"] = T3,
    ["Thousand Needles"] = T3, ["Scarlet Monastery"] = T3,

    -- Tier 4
    ["Azshara"] = T4, ["Felwood"] = T4, ["Feralas"] = T4, ["Moonglade"] = T4,
    ["Tanaris"] = T4, ["The Hinterlands"] = T4, ["Un'Goro Crater"] = T4,
    ["Western Plaguelands"] = T4, ["Maraudon"] = T4,
    ["Sunken Temple"] = T4, ["The Temple of Atal'Hakkar"] = T4,

    -- Tier 5 (above the natural 300 cap: needs pole/lure bonuses to cast)
    ["Burning Steppes"] = T5, ["Deadwind Pass"] = T5, ["Eastern Plaguelands"] = T5,
    ["Silithus"] = T5, ["Winterspring"] = T5,
    ["Scholomance"] = T5, ["Stratholme"] = T5, ["Zul'Gurub"] = T5,
}

-- Subzones that differ from their parent zone.
ns.SUBZONES = {
    ["Bay of Storms"]     = T5, -- Azshara
    ["Hetaera's Clutch"]  = T5, -- Azshara
    ["Scalebeard's Cave"] = T5, -- Azshara
    ["Jademir Lake"]      = T5, -- Feralas
    ["Jaguero Isle"]      = T4, -- Stranglethorn Vale
}

-- Which zone each subzone above belongs to (for the world map).
ns.SUBZONE_PARENT = {
    ["Bay of Storms"]     = "Azshara",
    ["Hetaera's Clutch"]  = "Azshara",
    ["Scalebeard's Cave"] = "Azshara",
    ["Jademir Lake"]      = "Feralas",
    ["Jaguero Isle"]      = "Stranglethorn Vale",
}
