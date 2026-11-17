-- Where to learn each Fishing rank in WoW: Forever.
-- Trainer list and map positions: WoW Forever trainer guides (warcrafttavern.com
-- and wow-professions.com, November 2026). Costs, levels and skill needed:
-- the same guides, which match the Classic values (cMaNGOS classic-db).
-- Map IDs are uiMapIDs; x and y are map percentages.

local _, ns = ...

-- Reputation factions, for the discount at Honored or better.
local SW, IF, DN, BB, TB, OG, UC, DS = 72, 47, 69, 21, 81, 76, 68, 530

-- side: "A" Alliance, "H" Horde, "N" anyone.
ns.TRAINERS = {
    { name = "Arnold Leland",        side = "A", map = 1453, x = 55.1, y = 69.6, place = "Trade District, Stormwind City",          rep = SW },
    { name = "Lee Brown",            side = "A", map = 1429, x = 47.6, y = 62.3, place = "Goldshire, Elwynn Forest",                rep = SW },
    { name = "Matthew Hooper",       side = "A", map = 1433, x = 21.5, y = 51.0, place = "Lakeshire, Redridge Mountains",           rep = SW },
    { name = "Donald Rabonne",       side = "A", map = 1424, x = 50.3, y = 64.3, place = "Southshore, Hillsbrad Foothills",         rep = SW },
    { name = "Harold Riggs",         side = "A", map = 1437, x = 8.2,  y = 58.3, place = "Menethil Harbor, Wetlands",               rep = SW },
    { name = "Hunter Moore",         side = "A", map = 1424, x = 54.0, y = 80.6, place = "island off the coast, Hillsbrad Foothills" },
    { name = "Grimnur Stonebrand",   side = "A", map = 1455, x = 48.5, y = 6.2,  place = "The Forlorn Cavern, Ironforge",           rep = IF },
    { name = "Paxton Ganter",        side = "A", map = 1426, x = 35.6, y = 40.4, place = "Iceflow Lake, Dun Morogh",                rep = IF },
    { name = "Warg Deepwater",       side = "A", map = 1432, x = 40.5, y = 39.4, place = "Thelsamar, Loch Modan",                   rep = IF },
    { name = "Astaia",               side = "A", map = 1457, x = 47.5, y = 56.5, place = "Darnassus",                               rep = DN },
    { name = "Androl Oakhand",       side = "A", map = 1438, x = 55.8, y = 93.5, place = "Rut'theran Village, Teldrassil",          rep = DN },
    { name = "Brannock",             side = "A", map = 1444, x = 32.2, y = 41.4, place = "Feathermoon Stronghold, Feralas",         rep = DN },
    { name = "Lumak",                side = "H", map = 1454, x = 69.7, y = 29.3, place = "Valley of Honor, Orgrimmar",              rep = OG },
    { name = "Kah Mistrunner",       side = "H", map = 1456, x = 56.4, y = 47.6, place = "Middle Rise, Thunder Bluff",              rep = TB },
    { name = "Uthan Stillwater",     side = "H", map = 1412, x = 44.2, y = 63.9, place = "Bloodhoof Village, Mulgore",              rep = TB },
    { name = "Armand Cromwell",      side = "H", map = 1458, x = 81.0, y = 29.5, place = "The Magic Quarter, Undercity",            rep = UC },
    { name = "Clyde Kellen",         side = "H", map = 1420, x = 67.1, y = 51.0, place = "Brightwater Lake, Tirisfal Glades",       rep = UC },
    { name = "Lau'Tiki",             side = "H", map = 1411, x = 53.2, y = 81.5, place = "Sen'jin Village, Durotar",                rep = DS },
    { name = "Lui'Mala",             side = "H", map = 1443, x = 22.7, y = 72.7, place = "Shadowprey Village, Desolace",            rep = DS },
    { name = "Kil'Hiwana",           side = "H", map = 1440, x = 10.7, y = 33.5, place = "Zoram Strand, Ashenvale",                 rep = DS },
    { name = "Katoom the Angler",    side = "H", map = 1425, x = 80.5, y = 81.5, place = "Revantusk Village, The Hinterlands" },
    { name = "Myizz Luckycatch",     side = "N", map = 1434, x = 27.5, y = 77.2, place = "Booty Bay, Stranglethorn Vale",           rep = BB },
    { name = "Krix",                 side = "N", map = 2548, x = 79.3, y = 54.7, place = "Powderfuse Port, Riverglades" },
    { name = "Baelann Swiftcurrent", side = "N", map = 2521, x = 63.2, y = 75.7, place = "Valanaar, Zephras Isle" },
    { name = "Fenn Fairweather",     side = "N", map = 2521, x = 45.0, y = 48.4, place = "Shen'dar Village, Zephras Isle" },
}

-- What each rank needs. "from" is the skill cap you have before learning it
-- (nil = Fishing not learned yet). Costs are in copper, before discounts.
ns.RANKS = {
    { from = nil, name = "Apprentice", cap = 75,  level = 0,  skill = 0,   cost = 100,   how = "trainer" },
    { from = 75,  name = "Journeyman", cap = 150, level = 10, skill = 50,  cost = 500,   how = "trainer" },
    { from = 150, name = "Expert",     cap = 225, level = 20, skill = 125, cost = 10000, how = "book" },
    { from = 225, name = "Artisan",    cap = 300, level = 35, skill = 225,               how = "quest" },
}

ns.EXPERT_BOOK = {
    item = 16083, title = "Expert Fishing - The Bass and You",
    seller = "Old Man Heming", place = "Booty Bay, Stranglethorn Vale", map = 1434, x = 27.5, y = 77.0, rep = BB,
}

ns.ARTISAN_QUEST = {
    title = "Nat Pagle, Angler Extreme",
    giver = "Nat Pagle", place = "Dustwallow Marsh", map = 1445, x = 58.5, y = 59.8,
}
