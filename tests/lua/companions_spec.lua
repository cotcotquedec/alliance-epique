local wow = require("tests.lua.helpers.wow")

local ME = "Jhou-Forever"
local function line(id, file)
  local place = math.floor(id / 100)
  local tiers = { "encounter", "travel_companion", "comrade", "good_friend", "close_friend", "brother_in_arms",
                  "best_friend" }
  local entry = { tier = tiers[place], text = "Réplique " .. id }
  if file then
    entry.intro = { npc = 1000000, voice = "npc1000000@G6INpmIs", file = "c" .. id .. ".ogg", dur = 4, src = "elise" }
  end
  return entry
end

local INDEX = {
  version = 8, quests = {}, npcs = { [1000000] = { name = "Elise" } }, zones = {}, levels = {},
  companions = {
    tiers = {
      { key = "encounter", name = "Rencontre", nameF = "Rencontre", from = 300 },
      { key = "travel_companion", name = "Compagnon de route", nameF = "Compagne de route", from = 1800 },
      { key = "comrade", name = "Camarade", nameF = "Camarade", from = 10800 },
      { key = "good_friend", name = "Bon ami", nameF = "Bonne amie", from = 36000 },
      { key = "close_friend", name = "Ami proche", nameF = "Amie proche", from = 108000 },
      { key = "brother_in_arms", name = "Frère d'armes", nameF = "Sœur d'armes", from = 270000 },
      { key = "best_friend", name = "Meilleur ami", nameF = "Meilleure amie", from = 36000, rank = 1 },
    },
    lines = {
      [101] = line(101, true), [102] = line(102, true), [103] = line(103),
      [201] = line(201, true), [701] = line(701, true),
    },
  },
}

-- The party: { {guid, name, class, sex, online}, ... } as party1..n.
local party = {}
local function partyIndex(unit)
  return tonumber(type(unit) == "string" and unit:match("^party(%d)$"))
end

local function stubGroup()
  _G.IsInGroup = function() return #party > 0 end
  _G.IsInRaid = function() return false end
  _G.GetNumSubgroupMembers = function() return #party end
  _G.UnitGUID = function(unit)
    local m = party[partyIndex(unit) or 0]
    return m and m.guid
  end
  _G.UnitName = function(unit)
    if unit == "player" then return "Jhou" end
    local m = party[partyIndex(unit) or 0]
    return m and m.name
  end
  _G.GetRealmName = function() return "Forever" end
  _G.UnitClass = function(unit)
    local m = party[partyIndex(unit) or 0]
    return m and "Classe", m and m.class
  end
  _G.UnitSex = function(unit)
    local m = party[partyIndex(unit) or 0]
    return m and m.sex or 2
  end
  _G.UnitIsConnected = function(unit)
    local m = party[partyIndex(unit) or 0]
    return m and m.online ~= false
  end
  _G.UnitLevel = function() return 12 end
  _G.GetRealZoneText = function() return "Forêt d'Elwynn" end
end

local function setGroup(list)
  party = list
  wow.fire("GROUP_ROSTER_UPDATE")
end

local function load(db)
  wow.reset()
  party = {}
  stubGroup()
  wow.loadAddon()
  _G.ForeverSpeechIndex = INDEX
  if db then
    _G.ForeverSpeechDB = db
  end
  wow.fire("ADDON_LOADED", "ForeverSpeech")
  ForeverSpeechDB.gap = 0
  return ForeverSpeech.Companions
end

local ARTHAS = { guid = "Player-1-0000AAAA", name = "Arthas", class = "PALADIN", sex = 2 }
local JAINA = { guid = "Player-1-0000BBBB", name = "Jaina", class = "MAGE", sex = 3 }
local UTHER = { guid = "Player-1-0000CCCC", name = "Uther", class = "PALADIN", sex = 2 }

local function journal()
  return ForeverSpeechDB.companions[ME]
end

local function chat(pattern)
  for _, msg in ipairs(wow.chat) do
    if msg:find(pattern, 1, true) then
      return true
    end
  end
  return false
end

describe("companion journal", function()
  it("a group counts after 5 minutes together: the companion enters the table, Elise greets the encounter", function()
    local Companions = load()
    setGroup({ ARTHAS })
    wow.advance(240)
    assert.is_nil(Companions.Get(ARTHAS.guid)) -- 4 minutes: not yet
    wow.advance(60)
    local entry = Companions.Get(ARTHAS.guid)
    assert.equals(300, entry.seconds)
    assert.equals(1, entry.groups)
    assert.equals("PALADIN", entry.class)
    assert.equals("Forêt d'Elwynn", entry.firstZone)
    assert.equals(12, entry.firstLevel)
    assert.is_true(chat("Rencontre : Arthas."))
    wow.advance(2)
    local played = wow.sounds[#wow.sounds].path
    assert.truthy(played == "c101.ogg" or played == "c102.ogg") -- an encounter line with audio
    assert.equals("Rencontre · Arthas", ForeverSpeech.Index.Companion(tonumber(played:match("%d+"))).name)
  end)

  it("counts a member's time only while connected, and the time in group", function()
    local Companions = load()
    setGroup({ ARTHAS })
    wow.advance(300)
    ARTHAS.online = false
    wow.fire("UNIT_CONNECTION", "party1")
    wow.advance(600)
    ARTHAS.online = nil
    wow.fire("UNIT_CONNECTION", "party1")
    wow.advance(60)
    assert.equals(360, Companions.Get(ARTHAS.guid).seconds)
    assert.equals(360, journal().groupSeconds)
  end)

  it("ends the session when the member leaves; a new group counts again", function()
    local Companions = load()
    setGroup({ ARTHAS })
    wow.advance(300)
    setGroup({})
    wow.advance(600)
    setGroup({ ARTHAS })
    wow.advance(300)
    local entry = Companions.Get(ARTHAS.guid)
    assert.equals(2, entry.groups)
    assert.equals(600, entry.seconds)
    assert.equals(300, entry.longest)
  end)

  it("a new tier: a chat line and Elise's line of that tier", function()
    local Companions = load({ companions = { [ME] = { groupSeconds = 0, bags = {}, list = {
      [ARTHAS.guid] = { name = "Arthas", seconds = 1600, groups = 3, longest = 600, tier = 1, dungeons = 0,
                        quests = 0, levels = 0 } } } } })
    setGroup({ ARTHAS })
    wow.advance(300)
    assert.equals(2, Companions.Tier(ARTHAS.guid).place)
    assert.is_true(chat("Arthas devient votre compagnon de route."))
    wow.advance(2)
    assert.equals("c201.ogg", wow.sounds[#wow.sounds].path)
  end)

  it("the best friend: the first of the table with 10 h, announced when someone passes the former one", function()
    local Companions = load({ companions = { [ME] = { groupSeconds = 0, bags = {}, best = ARTHAS.guid, list = {
      [ARTHAS.guid] = { name = "Arthas", seconds = 40000, groups = 30, longest = 9000, tier = 4 },
      [JAINA.guid] = { name = "Jaina", sex = 3, seconds = 39900, groups = 30, longest = 9000, tier = 4 },
    } } } })
    setGroup({ JAINA })
    wow.advance(300)
    assert.equals(JAINA.guid, journal().best)
    assert.equals("Meilleure amie", Companions.Tier(JAINA.guid).name)
    assert.equals("Bon ami", Companions.Tier(ARTHAS.guid).name)
    assert.is_true(chat("Jaina devient votre meilleure amie."))
    wow.advance(2)
    assert.equals("c701.ogg", wow.sounds[#wow.sounds].path)
  end)

  it("Rencontre: one line for several newcomers, and once per group", function()
    load()
    setGroup({ ARTHAS, JAINA })
    wow.advance(300)
    assert.is_true(chat("Rencontre : "))
    wow.advance(2)
    assert.equals(1, #wow.sounds)
    setGroup({ ARTHAS, JAINA, UTHER })
    wow.advance(360) -- the counters fold every minute
    assert.is_true(chat("Rencontre : Uther."))
    wow.advance(2)
    assert.equals(1, #wow.sounds) -- not twice in the same group
  end)

  it("draws Elise's lines without repeat", function()
    load()
    local heard = {}
    for _, m in ipairs({ ARTHAS, JAINA }) do
      setGroup({ m })
      wow.advance(362) -- the counters fold every minute
      heard[#heard + 1] = wow.sounds[#wow.sounds].path
      setGroup({})
      ForeverSpeech.Player.Stop("test")
    end
    assert.are_not.equal(heard[1], heard[2])
  end)

  it("says nothing without audio, or with the option off", function()
    local Companions = load({ companionLines = false })
    setGroup({ ARTHAS })
    wow.advance(302)
    assert.equals(0, #wow.sounds)
    assert.is_not_nil(Companions.Get(ARTHAS.guid))
  end)

  it("in a raid, only the player's subgroup; never in a battleground", function()
    local Companions = load()
    local raid = { { ARTHAS, 1 }, { JAINA, 2 }, { { guid = "Player-1-ME" }, 1 } }
    _G.IsInRaid = function() return true end
    _G.GetNumGroupMembers = function() return #raid end
    _G.GetRaidRosterInfo = function(i) return "x", 0, raid[i][2] end
    _G.UnitIsUnit = function(a, b) return a == "raid3" and b == "player" end
    local function at(unit)
      local i = tonumber(unit:match("^raid(%d)$"))
      return i and raid[i][1]
    end
    _G.UnitGUID = function(unit) return (at(unit) or {}).guid end
    _G.UnitName = function(unit) return unit == "player" and "Jhou" or (at(unit) or {}).name end
    _G.UnitIsConnected = function() return true end
    party = { 1 }
    wow.fire("GROUP_ROSTER_UPDATE")
    wow.advance(300)
    assert.is_not_nil(Companions.Get(ARTHAS.guid))
    assert.is_nil(Companions.Get(JAINA.guid))
    _G.IsInInstance = function() return true, "pvp" end
    wow.fire("ZONE_CHANGED_NEW_AREA")
    local before = Companions.Get(ARTHAS.guid).seconds
    wow.advance(600)
    assert.equals(before, Companions.Get(ARTHAS.guid).seconds)
  end)

  it("keeps 100 companions: the one with the least time, not in the group, leaves", function()
    local list = {}
    for i = 1, 100 do
      list["Player-1-" .. i] = { name = "P" .. i, seconds = 1000 + i, groups = 1, longest = 0, tier = 1 }
    end
    local Companions = load({ companions = { [ME] = { groupSeconds = 0, bags = {}, list = list } } })
    setGroup({ ARTHAS })
    wow.advance(300)
    assert.is_not_nil(Companions.Get(ARTHAS.guid))
    assert.is_nil(Companions.Get("Player-1-1"))
    assert.is_not_nil(Companions.Get("Player-1-2"))
  end)

  it("resumes the open group after a /reload: the same group, not a new one", function()
    load()
    setGroup({ ARTHAS })
    wow.advance(400)
    wow.fire("PLAYER_LOGOUT")
    local Companions = load(ForeverSpeechDB)
    party = { ARTHAS }
    wow.fire("GROUP_ROSTER_UPDATE")
    wow.advance(60)
    assert.equals(1, Companions.Get(ARTHAS.guid).groups)
    assert.equals(460, Companions.Get(ARTHAS.guid).seconds)
  end)

  it("stats together: quests turned in, levels gained, dungeons entered once per group", function()
    local Companions = load()
    setGroup({ ARTHAS })
    _G.IsInInstance = function() return true, "party" end
    _G.GetInstanceInfo = function() return "Les Mortemines" end
    wow.fire("PLAYER_ENTERING_WORLD") -- before the group counts: kept for later
    wow.advance(300)
    wow.fire("PLAYER_ENTERING_WORLD") -- the same instance again (a death)
    wow.fire("QUEST_TURNED_IN", 155)
    wow.fire("PLAYER_LEVEL_UP", 13)
    local entry = Companions.Get(ARTHAS.guid)
    assert.equals(1, entry.dungeons)
    assert.equals(1, entry.quests)
    assert.equals(1, entry.levels)
  end)

  local function twoCompanions()
    return load({ companions = { [ME] = { groupSeconds = 72000, bags = {}, list = {
      [ARTHAS.guid] = { name = "Arthas", class = "PALADIN", seconds = 45600, groups = 23, longest = 11100, tier = 4,
                        firstAt = os.time({ year = 2026, month = 10, day = 12 }), firstZone = "Forêt d'Elwynn",
                        firstLevel = 8, dungeons = 4, quests = 37, levels = 6 },
      [JAINA.guid] = { name = "Jaina", class = "MAGE", sex = 3, seconds = 1900, groups = 2, longest = 1200, tier = 2 },
    } } } })
  end

  it("the window shows the top 10, a click shows the stats; the tooltip of a companion gets two lines", function()
    local Companions = twoCompanions()
    wow.fire("TIME_PLAYED_MSG", 270000, 3600) -- 75 h played
    Companions.Open()
    assert.is_true(Companions.WindowShown())
    local rows = Companions.PanelRows()
    assert.equals(2, #rows)
    assert.equals("1.", rows[1].rank)
    assert.truthy(rows[1].name:find("Arthas", 1, true))
    assert.equals("Meilleur ami", rows[1].tier)
    assert.equals("12 h 40", rows[1].time)
    assert.equals("Compagne de route", rows[2].tier)
    local lines = Companions.StatLines(ARTHAS.guid)
    assert.same({
      "Temps ensemble : 12 h 40",
      "Part de votre temps de jeu : 17 %",
      "Part de votre temps en groupe : 63 %",
      "Groupes : 23",
      "Plus longue session : 3 h 05",
      "Rencontre : le 12/10/2026, Forêt d'Elwynn, à votre niveau 8",
      "Dernière fois ensemble : le 12/10/2026",
      "Ensemble : 4 donjon(s), 37 quête(s) rendue(s), 6 niveau(x) gagné(s)",
    }, lines)

    local added = {}
    local tooltip = { GetUnit = function() return "Arthas", "mouseover" end,
                      AddLine = function(_, text) added[#added + 1] = text end }
    _G.UnitGUID = function(unit) return unit == "mouseover" and ARTHAS.guid or nil end
    assert.is_true(Companions.AddTooltipLines(tooltip))
    assert.same({ "Meilleur ami · 12 h 40 ensemble", "23 groupe(s) · 17 % de votre temps de jeu" }, added)
  end)

  it("its own window: the stats of the clicked companion on the right, the main window left alone", function()
    local Companions = twoCompanions()
    wow.fire("TIME_PLAYED_MSG", 270000, 3600)
    local PlayerFrame = ForeverSpeech.PlayerFrame
    PlayerFrame.ShowQuest(1)
    local list = PlayerFrame.ListPanel()
    local listShown = list:IsShown()

    PlayerFrame.HeaderButton("companions"):Click()
    assert.is_true(Companions.WindowShown())
    assert.equals(listShown, list:IsShown()) -- the main window keeps its play list
    assert.equals("quest", PlayerFrame.Tab())
    local detail = Companions.DetailText()
    assert.equals("Compagnons", detail.title)
    assert.same({ "Cliquez sur un nom pour voir vos statistiques ensemble." }, detail.lines)

    local rows = Companions.Panel().rows
    rows[1]:Click()
    detail = Companions.DetailText()
    assert.truthy(detail.title:find("Arthas", 1, true))
    assert.equals("Meilleur ami", detail.tier)
    assert.equals(8, #detail.lines)
    assert.equals("Temps ensemble : 12 h 40", detail.lines[1])
    assert.is_true(rows[1].lit:IsShown())
    assert.is_false(rows[2].lit:IsShown())
    rows[2]:Click()
    assert.truthy(Companions.DetailText().title:find("Jaina", 1, true))
    assert.is_false(rows[1].lit:IsShown())

    PlayerFrame.HeaderButton("companions"):Click() -- closed
    assert.is_false(Companions.WindowShown())
    wow.slash("friends") -- opened again, the selection kept
    assert.is_true(Companions.WindowShown())
    assert.truthy(Companions.DetailText().title:find("Jaina", 1, true))
  end)

  it("formats durations", function()
    local Companions = load()
    assert.equals("0 min", Companions.FormatDuration(59))
    assert.equals("35 min", Companions.FormatDuration(2100))
    assert.equals("12 h 40", Companions.FormatDuration(45600))
    assert.equals("123 h 00", Companions.FormatDuration(442800))
  end)
end)
