local wow = require("tests.lua.helpers.wow")

local TEXT = "Un groupe de voleurs traîne depuis peu autour de Northshire."

-- Blizzard frames seen in S4, created before the addon loads like the real client does.
local function blizzardUI()
  _G.QuestFrame = wow.newRegion("Frame")
  _G.QuestFrameDetailPanel = wow.newRegion("Frame")
  _G.QuestFrameAcceptButton = wow.newRegion("Button")
  _G.QuestFrameDeclineButton = wow.newRegion("Button")
  -- the quest log: an accepted quest enters it, a turned-in one leaves it, unless the game refuses
  _G.questLog, _G.acceptRefused, _G.turnInRefused = {}, false, false
  _G.C_QuestLog = { GetLogIndexForQuestID = function(id) return _G.questLog[id] end }
  _G.accepted = 0
  _G.QuestFrameAcceptButton:SetScript("OnClick", function()
    _G.accepted = _G.accepted + 1
    if not _G.acceptRefused then
      _G.questLog[GetQuestID()] = 1
      wow.fire("QUEST_ACCEPTED", GetQuestID())
    end
  end)
  _G.turnedIn = 0
  _G.GetQuestReward = function()
    _G.turnedIn = _G.turnedIn + 1
    if not _G.turnInRefused then
      _G.questLog[GetQuestID()] = nil
      wow.fire("QUEST_TURNED_IN", GetQuestID(), 360, 0)
    end
  end
  -- reward panel ("Terminer la quête"): the native button calls GetQuestReward only once a reward is chosen
  _G.QuestFrameRewardPanel = wow.newRegion("Frame")
  _G.QuestFrameCompleteQuestButton = wow.newRegion("Button")
  _G.QuestFrameCompleteQuestButton._parent = _G.QuestFrameRewardPanel
  _G.QuestFrameCancelButton = wow.newRegion("Button")
  _G.rewardChosen = true
  _G.QuestFrameCompleteQuestButton:SetScript("OnClick", function()
    if _G.rewardChosen then
      GetQuestReward(1)
    end
  end)

  local tracker = { blocks = {} }
  function tracker.GetBlock(self, id)
    local block = wow.newRegion("Frame")
    block.HeaderButton = wow.newRegion("Button")
    self.blocks[id] = block
    return block
  end
  function tracker.AddBlock() end
  _G.QuestObjectiveTracker = tracker

  local rows = {}
  _G.QuestScrollFrame = { Contents = wow.newRegion("Frame") }
  _G.QuestScrollFrame.Contents.GetChildren = function() return unpack(rows) end
  _G.questLogRows = rows
  _G.QuestLogQuests_Update = function() end
  _G.QuestMapFrame = { DetailsFrame = wow.newRegion("Frame") }
  _G.QuestMapFrame_ShowQuestDetails = function() end
end

local function questDetail(questID)
  _G.GetQuestID = function() return questID end
  _G.GetQuestText = function() return TEXT end
  _G.GetTitleText = function() return "La confrérie des voleurs" end
  _G.GetObjectiveText = function() return "Apporter 12 Masques rouges." end
  _G.UnitGUID = function(unit)
    if unit == "npc" then return "Creature-0-4621-0-80-823-0000407152" end
  end
  _G.UnitName = function(unit) if unit == "npc" then return "Adjoint Willem" end end
  _G.GetNumQuestChoices = function() return 1 end
  _G.GetQuestItemInfo = function(kind, i)
    if kind == "choice" and i == 1 then return "Épée", 135274, 1, 2, true, 2224 end
  end
  _G.GetRewardXP = function() return 360 end
  wow.fire("QUEST_DETAIL", 0)
end

-- Reward panel of a quest (QUEST_COMPLETE), turned in to Maréchal McBride (197).
local function questComplete(questID, text)
  _G.GetQuestID = function() return questID end
  _G.GetRewardText = function() return text or "Ah, parfait, un autre volontaire." end
  _G.GetTitleText = function() return "Menace intérieure" end
  _G.UnitGUID = function(unit)
    if unit == "npc" then return "Creature-0-4621-0-80-197-0000407152" end
  end
  _G.UnitName = function(unit) if unit == "npc" then return "Maréchal McBride" end end
  _G.questLog[questID] = 1 -- a quest to turn in is in the log
  wow.fire("QUEST_COMPLETE")
end

local function setup()
  wow.reset()
  blizzardUI()
  wow.loadAddon()
  wow.fire("ADDON_LOADED", "ForeverSpeech")
  wow.fire("PLAYER_LOGIN")
  wow.fire("PLAYER_ENTERING_WORLD")
  ForeverSpeechDB.gap = 0 -- no silence between quests (gap tests are in player_spec)
end

describe("automatic reading of accepted quests", function()
  before_each(setup)

  it("is on by default; reads 2 s after the game's Accept and opens the player", function()
    assert.is_true(ForeverSpeechDB.autoplay)
    questDetail(18)
    _G.QuestFrameAcceptButton:Click()
    assert.equals(1, _G.accepted)
    assert.equals(0, #wow.sounds) -- the NPC speaks first
    wow.advance(1.9)
    assert.is_false(ForeverSpeech.Player.IsPlaying(18))
    wow.advance(0.1)
    assert.is_true(ForeverSpeech.Player.IsPlaying(18))
    assert.is_true(ForeverSpeech.PlayerFrame.IsShown())
    assert.equals(18, ForeverSpeech.PlayerFrame.QuestID())
  end)

  it("has no button of its own next to the game's", function()
    assert.is_nil(ForeverSpeech.AcceptButton)
  end)

  -- Dialogue UI hides QuestFrame and calls its own copy of AcceptQuest: no button is clicked, only QUEST_ACCEPTED
  -- comes.
  it("reads a quest accepted by another interface (Dialogue UI)", function()
    questDetail(19)
    wow.fire("QUEST_ACCEPTED", 19)
    wow.advance(2)
    assert.is_true(ForeverSpeech.Player.IsPlaying(19))
  end)

  it("a quest accepted without its ID in the event is the captured one", function()
    questDetail(18)
    wow.fire("QUEST_ACCEPTED")
    wow.advance(2)
    assert.is_true(ForeverSpeech.Player.IsPlaying(18))
  end)

  it("reads nothing when the game refuses the quest, nor when the option is off", function()
    _G.acceptRefused = true
    questDetail(18)
    _G.QuestFrameAcceptButton:Click()
    wow.advance(3)
    assert.equals(0, #ForeverSpeech.Player.List())
    _G.acceptRefused = false
    ForeverSpeechDB.autoplay = false
    _G.QuestFrameAcceptButton:Click()
    wow.advance(3)
    assert.equals(0, #ForeverSpeech.Player.List())
  end)

  it("/fs autoplay on|off", function()
    ForeverSpeech.HandleSlash("autoplay off")
    assert.is_false(ForeverSpeechDB.autoplay)
    ForeverSpeech.HandleSlash("autoplay on")
    assert.is_true(ForeverSpeechDB.autoplay)
  end)

  local function states()
    local list = {}
    for _, e in ipairs(ForeverSpeech.Player.List()) do
      list[#list + 1] = e.questID .. ":" .. e.state
    end
    return list
  end

  it("queues behind the quest playing", function()
    ForeverSpeech.Player.PlayQuest(1)
    questDetail(18)
    _G.QuestFrameAcceptButton:Click()
    wow.advance(2)
    assert.same({ "1:playing", "18:queued" }, states())
  end)

  it("always reads a quest already in the list, at its place", function()
    local Player = ForeverSpeech.Player
    Player.PlayQuest(18)
    Player.PlayQuest(1)
    Player.Next() -- 18 played, 1 playing
    questDetail(18)
    wow.fire("QUEST_ACCEPTED", 18)
    wow.advance(2)
    assert.same({ "18:queued", "1:playing" }, states()) -- waits, not played any more
    Player.Next()
    assert.equals(18, Player.Current().questID)
    Player.Next() -- nothing playing: it starts now
    wow.fire("QUEST_ACCEPTED", 18)
    wow.advance(2)
    assert.equals(18, Player.Current().questID)
    assert.same({ "18:playing", "1:done" }, states())
  end)
end)

describe("player window", function()
  before_each(setup)

  it("shows the captured quest with its rewards", function()
    questDetail(18)
    assert.is_true(ForeverSpeech.PlayerFrame.ShowQuest(18))
    local data = ForeverSpeech.QuestData.Get(18)
    assert.equals("capture", data.source)
    assert.equals(TEXT, data.description)
    assert.equals(823, data.npcID)
    assert.equals(2224, data.rewards.choices[1].itemID)
    assert.equals(360, data.rewards.xp)
  end)

  it("a second accepted quest waits after the one being read", function()
    local Player = ForeverSpeech.Player
    questDetail(18)
    _G.QuestFrameAcceptButton:Click()
    wow.advance(2)
    assert.equals(18, ForeverSpeech.PlayerFrame.QuestID())
    questDetail(19)
    _G.QuestFrameAcceptButton:Click()
    wow.advance(2)
    assert.equals(2, _G.accepted)
    assert.equals(18, Player.Current().questID)          -- the first one keeps playing
    assert.equals(19, Player.Queue()[1].questID)         -- the second waits in the play list
    assert.equals(18, ForeverSpeech.PlayerFrame.QuestID()) -- the window stays on what is heard
    Player.Next()
    assert.equals(19, Player.Current().questID)
    assert.equals(19, ForeverSpeech.PlayerFrame.QuestID())
  end)

  it("follows the queue to the next quest", function()
    questDetail(18)
    questDetail(19)
    ForeverSpeech.Player.PlayQuest(18)
    ForeverSpeech.Player.PlayQuest(19)
    ForeverSpeech.PlayerFrame.ShowQuest(18)
    ForeverSpeech.Player.Next()
    assert.equals(19, ForeverSpeech.PlayerFrame.QuestID())
  end)

  it("shows the quest text from the game (capture), and grows to fit it", function()
    local PlayerFrame = ForeverSpeech.PlayerFrame
    questDetail(18)
    PlayerFrame.ShowQuest(18)
    assert.equals(TEXT, PlayerFrame.QuestText())
    local f = PlayerFrame.ListPanel():GetParent()
    local heights = {}
    f.SetHeight = function(_, h) heights[#heights + 1] = h end
    PlayerFrame.SelectTab("quest")
    assert.is_true(heights[1] > 34 + 237) -- the same window as without text, and the text
  end)

  it("hides the quest text when the option is off", function()
    local PlayerFrame = ForeverSpeech.PlayerFrame
    questDetail(18)
    PlayerFrame.ShowQuest(18)
    local f = PlayerFrame.ListPanel():GetParent()
    local heights = {}
    f.SetHeight = function(_, h) heights[#heights + 1] = h end
    ForeverSpeechDB.showText = false
    PlayerFrame.RefreshQuestText() -- what the option's checkbox does
    assert.is_nil(PlayerFrame.QuestText())
    -- 34: the title bar; 237: the medallion header, objectives, rewards with their icons
    assert.equals(34 + 237, heights[#heights])
  end)

  it("compact: without the quest's description only, the rewards always shown", function()
    local PlayerFrame = ForeverSpeech.PlayerFrame
    questDetail(18)
    PlayerFrame.ShowQuest(18)
    assert.is_not_nil(PlayerFrame.QuestText())
    wow.slash("compact")
    assert.is_false(ForeverSpeechDB.showText)
    assert.is_nil(PlayerFrame.QuestText())
    local f = PlayerFrame.ListPanel():GetParent()
    assert.is_true(f.rewardHeader:IsShown())
    wow.slash("compact off")
    assert.is_not_nil(PlayerFrame.QuestText())
    assert.is_true(f.rewardHeader:IsShown())
  end)

  it("shows the game's 2D portrait of the NPC in the medallion when the client can render it", function()
    local PlayerFrame = ForeverSpeech.PlayerFrame
    local rendered
    _G.SetPortraitTextureFromCreatureDisplayID = function(_, displayID) rendered = displayID end
    questDetail(18)
    _G.ForeverSpeechIndex = { version = 9, quests = { [18] = { giver = 823 } },
      npcs = { [823] = { display = 2072, name = "Adjoint Willem" } } }
    PlayerFrame.ShowQuest(18)
    _G.SetPortraitTextureFromCreatureDisplayID = nil
    assert.equals(2072, rendered)
    assert.equals("face", (PlayerFrame.Visual()))
  end)

  it("remembers that it was open, and opens again when the world is entered after a reload", function()
    local PlayerFrame = ForeverSpeech.PlayerFrame
    questDetail(18)
    PlayerFrame.ShowQuest(18)
    local f = PlayerFrame.ListPanel():GetParent()
    f:GetScript("OnShow")(f)
    assert.is_true(ForeverSpeechDB.windowShown)
    f:Hide()
    f:GetScript("OnHide")(f)
    assert.is_false(ForeverSpeechDB.windowShown)
    f:Show()
    f:GetScript("OnShow")(f)
    wow.fire("PLAYER_LOGOUT")
    f:Hide()
    f:GetScript("OnHide")(f) -- the UI torn down at logout: nothing recorded
    assert.is_true(ForeverSpeechDB.windowShown)
    wow.fire("PLAYER_ENTERING_WORLD")
    wow.advance(1)
    assert.is_true(PlayerFrame.IsShown())
  end)

  it("is never shorter than its side tabs need, even compact", function()
    local PlayerFrame = ForeverSpeech.PlayerFrame
    questDetail(18)
    PlayerFrame.ShowQuest(18)
    local f = PlayerFrame.ListPanel():GetParent()
    local heights = {}
    f.SetHeight = function(_, h) heights[#heights + 1] = h end
    ForeverSpeechDB.showList = false
    for _, key in ipairs({ "a", "b" }) do -- two action tabs (the edge is empty since the emote wheel, 2026-10-21)
      ForeverSpeech.SideTabs.Register({ key = key, icon = "x", group = "bottom", onClick = function() end })
    end
    PlayerFrame.SetCompact(true)
    -- margins 44 + 44, two tabs of 32 and a gap of 14
    assert.equals(166, ForeverSpeech.SideTabs.MinHeight("main"))
    assert.is_true(heights[#heights] >= 166)
  end)

  it("the companions are a title bar button left of the options gear, opening their own window", function()
    local PlayerFrame = ForeverSpeech.PlayerFrame
    questDetail(18)
    PlayerFrame.ShowQuest(18)
    assert.is_nil(ForeverSpeech.SideTabs.Tab("companions"))
    local b = PlayerFrame.HeaderButton("companions")
    assert.is_not_nil(b)
    b:Click()
    assert.is_true(ForeverSpeech.Companions.WindowShown()) -- its own window (2026-10-21)
    b:Click()
    assert.is_false(ForeverSpeech.Companions.WindowShown())
  end)

  it("shows the quest the player opens in the quest log, while the window is open", function()
    local PlayerFrame = ForeverSpeech.PlayerFrame
    questDetail(18)
    PlayerFrame.ShowQuest(18)
    _G.C_QuestLog = { GetTitleForQuestID = function() return "Une autre quête" end }
    ForeverSpeech.QuestLogButtons.DecorateDetails(33)
    assert.equals(33, (PlayerFrame.QuestID()))
    PlayerFrame.Hide()
    ForeverSpeech.QuestLogButtons.DecorateDetails(18) -- closed: left closed
    assert.is_false(PlayerFrame.IsShown())
  end)

  it("measures its height on the real layout once the client has placed the blocks", function()
    local PlayerFrame = ForeverSpeech.PlayerFrame
    questDetail(18)
    PlayerFrame.ShowQuest(18)
    local f = PlayerFrame.ListPanel():GetParent()
    local heights = {}
    f.SetHeight = function(_, h) heights[#heights + 1] = h end
    f:Show()
    wow.layout = true -- every frame's top at 600 and bottom at 200: the last block ends 400 under the panel's top
    PlayerFrame.SelectTab("quest")
    wow.advance(0)
    wow.layout = nil
    assert.equals(34 + 400 + 12, heights[#heights]) -- title bar, measured content, bottom margin
  end)

  it("shows the captured turn-in text for the end of a quest", function()
    local PlayerFrame = ForeverSpeech.PlayerFrame
    questDetail(783)
    questComplete(783, "Ah, parfait.")
    PlayerFrame.ShowQuest(783, "complete")
    assert.equals("Ah, parfait.", PlayerFrame.QuestText())
  end)

  it("shows the quest level on its difficulty badge, in its difficulty color (index level)", function()
    _G.ForeverSpeechIndex = { version = 8, quests = { [18] = { level = 4 } }, npcs = {} }
    _G.UnitLevel = function() return 3 end
    questDetail(18)
    ForeverSpeech.PlayerFrame.ShowQuest(18)
    assert.equals("|cffffd200!|r La confrérie des voleurs", ForeverSpeech.PlayerFrame.Title())
    local texture, level = ForeverSpeech.PlayerFrame.Badge()
    assert.equals("Interface\\AddOns\\ForeverSpeech\\media\\difficulty\\difficult", texture)
    assert.equals(4, level)
  end)

  it("writes the level in the title as before when the badge texture is refused", function()
    _G.ForeverSpeechIndex = { version = 8, quests = { [18] = { level = 4 } }, npcs = {} }
    _G.UnitLevel = function() return 3 end
    wow.refusedTextures["Interface\\AddOns\\ForeverSpeech\\media\\difficulty\\difficult"] = true
    questDetail(18)
    ForeverSpeech.PlayerFrame.ShowQuest(18)
    assert.equals("|cffffd200!|r |cffffd100[4] La confrérie des voleurs|r", ForeverSpeech.PlayerFrame.Title())
    assert.is_nil(ForeverSpeech.PlayerFrame.Badge())
  end)

  it("prefers the quest log's level, and the title alone without a level", function()
    _G.ForeverSpeechIndex = { version = 8, quests = { [18] = { level = 4 } }, npcs = {} }
    _G.UnitLevel = function() return 3 end
    _G.C_QuestLog = {
      GetLogIndexForQuestID = function() return 2 end,
      GetInfo = function(index) return index == 2 and { level = 9 } or nil end,
    }
    questDetail(18)
    ForeverSpeech.PlayerFrame.ShowQuest(18)
    local texture, level = ForeverSpeech.PlayerFrame.Badge()
    assert.equals("Interface\\AddOns\\ForeverSpeech\\media\\difficulty\\impossible", texture)
    assert.equals(9, level)
    _G.C_QuestLog = nil
    _G.ForeverSpeechIndex = { version = 8, quests = {}, npcs = {} }
    ForeverSpeech.PlayerFrame.ShowQuest(18)
    assert.equals("|cffffd200!|r La confrérie des voleurs", ForeverSpeech.PlayerFrame.Title())
    assert.is_nil(ForeverSpeech.PlayerFrame.Badge())
  end)

  it("recolors the shown quest when a level is gained", function()
    _G.ForeverSpeechIndex = { version = 8, quests = { [18] = { level = 4 } }, npcs = {} }
    _G.UnitLevel = function() return 1 end -- not updated yet when PLAYER_LEVEL_UP fires
    questDetail(18)
    ForeverSpeech.PlayerFrame.ShowQuest(18)
    assert.truthy(ForeverSpeech.PlayerFrame.Badge():find("verydifficult$")) -- orange
    wow.fire("PLAYER_LEVEL_UP", 2)
    assert.truthy(ForeverSpeech.PlayerFrame.Badge():find("\\difficult$")) -- yellow
  end)

  it("shows Elise's portrait for a quest she reads, an NPC's model otherwise", function()
    _G.ForeverSpeechIndex = {
      version = 8,
      quests = { [4081] = { detail = { npc = 1000000, file = "a.ogg", src = "wowhead_fr" } } },
      npcs = { [1000000] = { name = "Elise" } },
    }
    _G.C_QuestLog = { GetTitleForQuestID = function() return "Recherché" end, GetLogIndexForQuestID = function() end }
    local PlayerFrame = ForeverSpeech.PlayerFrame
    PlayerFrame.ShowQuest(4081)
    local kind, texture = PlayerFrame.Visual()
    assert.equals("portrait", kind)
    assert.equals("Interface\\AddOns\\ForeverSpeech\\media\\elise", texture)
    questDetail(18)
    PlayerFrame.ShowQuest(18)
    assert.equals("model", (PlayerFrame.Visual()))
  end)

  it("falls back to the quest icon when the client refuses her portrait", function()
    wow.refusedTextures["Interface\\AddOns\\ForeverSpeech\\media\\elise"] = true
    _G.ForeverSpeechIndex = {
      version = 8,
      quests = { [4081] = { detail = { npc = 1000000, file = "a.ogg", src = "wowhead_fr" } } },
      npcs = { [1000000] = { name = "Elise" } },
    }
    _G.C_QuestLog = { GetTitleForQuestID = function() return "Recherché" end, GetLogIndexForQuestID = function() end }
    ForeverSpeech.PlayerFrame.ShowQuest(4081)
    local kind, texture = ForeverSpeech.PlayerFrame.Visual()
    assert.equals("icon", kind)
    assert.matches("AvailableQuestIcon$", texture)
  end)

  it("/fs show opens the last opened quest", function()
    questDetail(18)
    wow.slash("show")
    assert.is_true(ForeverSpeech.PlayerFrame.IsShown())
  end)
end)

describe("quest data from the quest log", function()
  before_each(setup)

  it("uses the log text when the quest was never captured", function()
    _G.C_QuestLog = {
      GetTitleForQuestID = function() return "Les loups traversent la frontière" end,
      GetLogIndexForQuestID = function() return 2 end,
    }
    _G.GetQuestLogQuestText = function(index)
      if index == 2 then return "Texte du journal", "Objectifs du journal" end
    end
    local data = ForeverSpeech.QuestData.Get(33)
    assert.equals("questlog", data.source)
    assert.equals("Texte du journal", data.description)
    assert.equals("Texte du journal\n\nObjectif : Objectifs du journal", ForeverSpeech.QuestData.Text(33))
  end)

  it("falls back to the selected-quest form of GetQuestLogQuestText", function()
    local selected = 5
    _G.C_QuestLog = {
      GetTitleForQuestID = function() return "Titre" end,
      GetLogIndexForQuestID = function() return 2 end,
      GetSelectedQuest = function() return selected end,
      SetSelectedQuest = function(id) selected = id end,
    }
    _G.GetQuestLogQuestText = function(index)
      if index == nil and selected == 33 then return "Texte sélectionné", "" end
    end
    assert.equals("Texte sélectionné", ForeverSpeech.QuestData.Text(33))
    assert.equals(5, selected) -- selection restored
  end)

  it("composes description then objectives, or the description alone", function()
    local Q = ForeverSpeech.QuestData
    assert.equals("D\n\nObjectif : O", Q.ComposeSpeech("D", "O"))
    assert.equals("D", Q.ComposeSpeech("D", ""))
    assert.is_nil(Q.ComposeSpeech(nil, "O"))
  end)

  it("colors a quest level by the Classic quest log's rules", function()
    local Q = ForeverSpeech.QuestData
    _G.UnitLevel = function() return 20 end -- gray level 13
    local keys = {}
    for _, level in ipairs({ 25, 23, 22, 18, 17, 14, 13 }) do
      keys[#keys + 1] = (Q.Difficulty(level))
    end
    assert.same({ "impossible", "verydifficult", "difficult", "difficult", "standard", "standard", "trivial" }, keys)
    assert.equals("standard", (Q.Difficulty(1, 5))) -- up to level 5, nothing is gray
    assert.equals("trivial", (Q.Difficulty(50, 60))) -- gray level 51 at 60
    assert.is_nil(Q.Difficulty(nil))
  end)

  it("takes the client's own quest difficulty color when it has one", function()
    local Q = ForeverSpeech.QuestData
    _G.UnitLevel = function() return 20 end
    _G.QuestDifficultyColors = { difficult = { r = 1, g = 0.82, b = 0 }, standard = { r = 0.25, g = 0.75, b = 0.25 } }
    _G.GetQuestDifficultyColor = function() return _G.QuestDifficultyColors.standard end
    assert.equals("standard", (Q.Difficulty(19))) -- the client says green (a Retail range, say)
    assert.equals("standard", (Q.Difficulty(19, 20))) -- the current level given: the client still decides
    assert.equals("difficult", (Q.Difficulty(19, 21))) -- a level UnitLevel does not know yet: the Classic rules
  end)

  it("takes the giver and its 3D model from the index (contract v2)", function()
    _G.ForeverSpeechIndex = {
      version = 8,
      quests = { [33] = { giver = 196 } },
      npcs = { [196] = { display = 3251, name = "Eagan Peltskinner" } },
    }
    _G.C_QuestLog = {
      GetTitleForQuestID = function() return "Les loups traversent la frontière" end,
      GetLogIndexForQuestID = function() return 2 end,
    }
    _G.GetQuestLogQuestText = function() return "Texte du journal", "" end
    local data = ForeverSpeech.QuestData.Get(33)
    assert.equals(196, data.npcID)
    assert.equals(3251, data.displayID)
    assert.equals("Eagan Peltskinner", data.giverName)
  end)

  it("keeps the captured giver and adds its display ID", function()
    questDetail(18)
    _G.ForeverSpeechIndex = {
      version = 8,
      quests = { [18] = { giver = 999 } },
      npcs = { [823] = { display = 2072, name = "Nom du registre" } },
    }
    local data = ForeverSpeech.QuestData.Get(18)
    assert.equals(823, data.npcID)
    assert.equals(2072, data.displayID)
    assert.equals("Adjoint Willem", data.giverName)
  end)

  it("shows each objective as a checkbox and a progress bar with the objective inside, following the log", function()
    questDetail(18)
    local done = 3
    _G.C_QuestLog = {
      GetLogIndexForQuestID = function() return 3 end,
      GetQuestObjectives = function()
        return {
          { text = "Masque rouge : " .. done .. "/12", finished = done >= 12 },
          { text = "Bandana : 1/1", finished = true },
        }
      end,
    }
    local PlayerFrame = ForeverSpeech.PlayerFrame
    PlayerFrame.ShowQuest(18)
    local objectives = PlayerFrame.ListPanel():GetParent().objectives
    assert.equals("Apporter 12 Masques rouges.", objectives:GetText()) -- the summary, above the rows
    assert.same({
      { text = "Masque rouge : 3/12", share = 0.25, done = false },
      { text = "Bandana : 1/1", share = 1, done = true },
    }, PlayerFrame.ObjectiveRows())
    local f = PlayerFrame.ListPanel():GetParent()
    assert.same({ 0.32, 0.32, 0.32 }, { f.objectiveRows[2].bar:GetStatusBarColor() }) -- done: greyed
    done = 12
    wow.fire("QUEST_LOG_UPDATE")
    assert.same({ text = "Masque rouge : 12/12", share = 1, done = true }, PlayerFrame.ObjectiveRows()[1])
    -- not in the log any more: the summary only
    _G.C_QuestLog.GetLogIndexForQuestID = function() end
    wow.fire("QUEST_LOG_UPDATE")
    assert.equals("Apporter 12 Masques rouges.", objectives:GetText())
    assert.same({}, PlayerFrame.ObjectiveRows())
  end)

  it("fills a bar only for a counter (counts of 2 or more, x/y, %), and grows the window for many rows", function()
    questDetail(18)
    _G.C_QuestLog = {
      GetLogIndexForQuestID = function() return 3 end,
      GetQuestObjectives = function()
        return {
          { text = "Loups tués", numFulfilled = 3, numRequired = 4, finished = false },
          { text = "Exploration : 45 %", finished = false },
          { text = "Parler au Maréchal", finished = false },
          { text = "A : 1/2", finished = false },
          { text = "Atteindre une compétence de 20 en dépeçage", numFulfilled = 1, numRequired = 1, finished = false },
        }
      end,
    }
    local PlayerFrame = ForeverSpeech.PlayerFrame
    ForeverSpeechDB.showText = false
    PlayerFrame.ShowQuest(18)
    local f = PlayerFrame.ListPanel():GetParent()
    local shares = {}
    for _, row in ipairs(PlayerFrame.ObjectiveRows()) do
      shares[#shares + 1] = row.share
    end
    assert.same({ 0.75, 0.45, 0, 0.5, 0 }, shares)
    local heights = {}
    f.SetHeight = function(_, h) heights[#heights + 1] = h end
    PlayerFrame.SelectTab("quest")
    assert.is_true(heights[1] > 344) -- summary and five rows need more than the former five lines
  end)

  it("takes the rewards from the quest log when the capture has none", function()
    ForeverSpeechCaptures.quests = { [18] = { { questID = 18, text = TEXT, title = "La confrérie des voleurs" } } }
    _G.C_QuestLog = { GetLogIndexForQuestID = function() return 3 end }
    _G.GetNumQuestLogChoices = function() return 2 end
    _G.GetQuestLogChoiceInfo = function(i) return "Arme " .. i, 135000 + i, 1, 2, true, 2000 + i end
    _G.GetQuestLogRewardMoney = function() return 75 end
    local rewards = ForeverSpeech.QuestData.Get(18).rewards
    assert.equals(2, #rewards.choices)
    assert.equals(2002, rewards.choices[2].itemID)
    assert.equals(75, rewards.money)
  end)

  it("names the narrator when no NPC says the quest (contract v4)", function()
    _G.ForeverSpeechIndex = {
      version = 8,
      quests = { [4081] = { detail = { npc = 1000000, file = "a.ogg", src = "wowhead_fr" },
                            complete = { npc = 1000000, file = "b.ogg", src = "wowhead_fr" } } },
      npcs = { [1000000] = { name = "Elise" } },
    }
    _G.C_QuestLog = { GetTitleForQuestID = function() return "Recherché" end, GetLogIndexForQuestID = function() end }
    local data = ForeverSpeech.QuestData.Get(4081)
    assert.is_nil(data.npcID)
    assert.is_nil(data.displayID)
    assert.equals("Elise", data.giverName)
    assert.equals(1000000, data.speakerID)
    local complete = ForeverSpeech.QuestData.Get(4081, "complete")
    assert.equals("Elise", complete.giverName)
    assert.equals(1000000, complete.speakerID)
  end)

  it("ignores an index without NPCs or of another version", function()
    _G.C_QuestLog = { GetTitleForQuestID = function() return "Titre" end, GetLogIndexForQuestID = function() end }
    _G.ForeverSpeechIndex = { version = 8, quests = { [33] = { giver = 196 } } }
    assert.is_nil(ForeverSpeech.QuestData.Get(33).displayID)
    _G.ForeverSpeechIndex = { version = 3, quests = { [33] = { giver = 196 } } }
    assert.is_nil(ForeverSpeech.QuestData.Get(33).npcID)
  end)

  it("returns nil for an unknown quest", function()
    _G.C_QuestLog = { GetTitleForQuestID = function() end, GetLogIndexForQuestID = function() end }
    assert.is_nil(ForeverSpeech.QuestData.Get(999))
  end)
end)

describe("tracker buttons", function()
  before_each(setup)

  it("decorates a block with a toggle for the quest passed to GetBlock", function()
    local tracker = _G.QuestObjectiveTracker
    local block = tracker:GetBlock(33)
    tracker:AddBlock(block)
    local b = block.ForeverSpeechToggle
    assert.equals(33, b.questID)
    b:Click("LeftButton")
    assert.is_true(ForeverSpeech.Player.IsPlaying(33))
    b:Click("LeftButton")
    assert.is_false(ForeverSpeech.Player.IsPlaying(33))
  end)

  it("prefers block.id and reuses the button when the block is recycled", function()
    local tracker = _G.QuestObjectiveTracker
    local block = tracker:GetBlock(1)
    block.id = 40
    tracker:AddBlock(block)
    local first = block.ForeverSpeechToggle
    block.id = 41
    tracker:AddBlock(block)
    assert.equals(first, block.ForeverSpeechToggle)
    assert.equals(41, first.questID)
  end)

  it("shows the stop icon while its quest plays", function()
    local tracker = _G.QuestObjectiveTracker
    local block = tracker:GetBlock(33)
    tracker:AddBlock(block)
    ForeverSpeech.Player.PlayQuest(33)
    assert.matches("glyph_stop$", block.ForeverSpeechToggle.glyph:GetTexture())
  end)

  it("right click opens the player window", function()
    local tracker = _G.QuestObjectiveTracker
    local block = tracker:GetBlock(33)
    tracker:AddBlock(block)
    block.ForeverSpeechToggle:Click("RightButton")
    assert.equals(33, ForeverSpeech.PlayerFrame.QuestID())
  end)
end)

describe("quest log buttons", function()
  before_each(setup)

  it("decorates the shown quest rows after QuestLogQuests_Update", function()
    local row = wow.newRegion("Button")
    row.questID = 33
    row:Show()
    local header = wow.newRegion("Button")
    header:Show()
    _G.questLogRows[1], _G.questLogRows[2] = row, header
    _G.QuestLogQuests_Update()
    assert.equals(33, row.ForeverSpeechToggle.questID)
    assert.is_nil(rawget(header, "ForeverSpeechToggle"))
  end)

  it("puts a single button per quest, on the title row (topmost)", function()
    local title, objective = wow.newRegion("Button"), wow.newRegion("Frame")
    title.questID, objective.questID = 33, 33
    title.GetTop = function() return 500 end
    objective.GetTop = function() return 480 end
    title:Show()
    objective:Show()
    _G.questLogRows[1], _G.questLogRows[2] = objective, title
    _G.QuestLogQuests_Update()
    assert.equals(33, title.ForeverSpeechToggle.questID)
    assert.is_nil(rawget(objective, "ForeverSpeechToggle"))
  end)

  it("adds a toggle to the details panel", function()
    _G.QuestMapFrame_ShowQuestDetails(33)
    -- the details toggle is created on the DetailsFrame
    ForeverSpeech.QuestLogButtons.DecorateDetails(34)
    ForeverSpeech.Player.PlayQuest(34)
    assert.is_true(ForeverSpeech.Player.IsPlaying(34))
  end)
end)

describe("main window", function()
  before_each(setup)

  it("plays the quest page sound when a quest starts, not for the test sound", function()
    ForeverSpeech.Player.PlayQuest(18)
    assert.same({ 875, 875 }, wow.pageSounds)
    ForeverSpeech.Player.Clear()
    wow.slash("test")
    assert.same({ 875, 875 }, wow.pageSounds)
    ForeverSpeechDB.pageSound = false
    ForeverSpeech.Player.PlayQuest(19)
    assert.same({ 875, 875 }, wow.pageSounds)
  end)

  it("opens on every quest start when openOnPlay is on", function()
    ForeverSpeech.Player.PlayQuest(18)
    assert.is_true(ForeverSpeech.PlayerFrame.IsShown())
    ForeverSpeech.PlayerFrame.Hide()
    ForeverSpeechDB.openOnPlay = false
    ForeverSpeech.Player.Next()
    ForeverSpeech.Player.PlayQuest(19)
    assert.is_false(ForeverSpeech.PlayerFrame.IsShown())
  end)

  it("lists history, current and queue in order", function()
    local Player = ForeverSpeech.Player
    Player.PlayQuest(1)
    Player.Next() -- 1 done, nothing queued
    Player.PlayQuest(2)
    Player.PlayQuest(3)
    Player.PlayQuest(4)
    local states = {}
    for _, e in ipairs(ForeverSpeech.PlayerFrame.ListEntries()) do
      states[#states + 1] = e.questID .. ":" .. e.state
    end
    assert.same({ "1:done", "2:playing", "3:queued", "4:queued" }, states)
    assert.is_true(Player.Remove(3))
    assert.equals(1, #Player.Queue())
    assert.is_false(Player.Remove(2)) -- playing, not queued
  end)

  local function listStates()
    local states = {}
    for _, e in ipairs(ForeverSpeech.PlayerFrame.ListEntries()) do
      states[#states + 1] = e.questID .. ":" .. e.state
    end
    return states
  end

  it("never lists a quest twice; reading a played quest again queues it at its place", function()
    local Player = ForeverSpeech.Player
    Player.PlayQuest(1)
    Player.PlayQuest(2)
    Player.Next() -- 1 done, 2 playing
    assert.same({ "queued", 1 }, { Player.PlayQuest(1) })
    assert.same({ "1:queued", "2:playing" }, listStates())
    Player.Next()
    assert.same({ "1:playing", "2:done" }, listStates())
    Player.Next() -- nothing playing: reading a listed quest starts it now
    assert.equals("playing", (Player.PlayQuest(2)))
    assert.same({ "1:done", "2:playing" }, listStates())
  end)

  it("goes back to a quest requested again", function()
    local Player, PlayerFrame = ForeverSpeech.Player, ForeverSpeech.PlayerFrame
    Player.PlayQuest(1)
    Player.PlayQuest(2)
    PlayerFrame.ShowQuest(1)
    assert.same({ "duplicate", "queued" }, { Player.PlayQuest(2) })
    assert.equals(2, PlayerFrame.QuestID())
    assert.same({ "1:playing", "2:queued" }, listStates())
  end)

  local function doubleClick(index, questID)
    local PlayerFrame = ForeverSpeech.PlayerFrame
    PlayerFrame.UpdateList()
    local row = PlayerFrame.ListPanel().rows[index]
    assert.equals(questID, row.questID)
    row:GetScript("OnDoubleClick")(row)
  end

  it("double-click jumps to an item without changing the order", function()
    local Player = ForeverSpeech.Player
    Player.PlayQuest(1)
    Player.PlayQuest(2)
    Player.PlayQuest(3)
    Player.PlayQuest(4)
    Player.Next() -- 1 done, 2 playing
    doubleClick(1, 1) -- back to a played quest
    assert.equals(1, Player.Current().questID)
    assert.same({ "1:playing", "2:done", "3:queued", "4:queued" }, listStates())
    doubleClick(4, 4) -- forward, skipping 3
    assert.same({ "1:done", "2:done", "3:queued", "4:playing" }, listStates())
    Player.Next() -- goes on with the first item not played yet
    assert.equals(3, Player.Current().questID)
    assert.same({ "1:done", "2:done", "3:playing", "4:done" }, listStates())
    -- the playing quest restarts from the start
    local sounds = #wow.sounds
    doubleClick(3, 3)
    assert.equals(sounds + 1, #wow.sounds)
    assert.equals(3, Player.Current().questID)
  end)

  it("the Play button plays the quest shown, now, at its place", function()
    local Player, PlayerFrame = ForeverSpeech.Player, ForeverSpeech.PlayerFrame
    Player.PlayQuest(1)
    Player.PlayQuest(2)
    Player.PlayQuest(3)
    local play = PlayerFrame.ListPanel():GetParent().playButton
    PlayerFrame.ShowQuest(3) -- browsing the list
    play:Click()
    assert.same({ "1:done", "2:queued", "3:playing" }, listStates())
    local sounds = #wow.sounds
    play:Click() -- the quest playing restarts
    assert.equals(sounds + 1, #wow.sounds)
    PlayerFrame.ShowQuest(7) -- not in the list: added at the end, played now
    play:Click()
    assert.same({ "1:done", "2:queued", "3:done", "7:playing" }, listStates())
  end)

  it("frames the NPC model on head and bust, tunable with /fs zoom", function()
    local zooms = {}
    local realCreate = _G.CreateFrame
    _G.CreateFrame = function(kind, ...)
      local f = realCreate(kind, ...)
      if kind == "PlayerModel" then
        f.SetPortraitZoom = function(_, z) zooms[#zooms + 1] = z end
      end
      return f
    end
    _G.ForeverSpeechIndex = {
      version = 8,
      quests = { [783] = { giver = 823 } },
      npcs = { [823] = { display = 2072, name = "Adjoint Willem" } },
    }
    _G.C_QuestLog = {
      GetTitleForQuestID = function() return "Une menace intérieure" end,
      GetLogIndexForQuestID = function() return 1 end,
    }
    _G.GetQuestLogQuestText = function() return "Texte du journal", "" end
    ForeverSpeech.PlayerFrame.ShowQuest(783)
    assert.equals(0.6, zooms[#zooms])
    wow.slash("zoom 0.8")
    assert.equals(0.8, zooms[#zooms])
    assert.equals(0.8, ForeverSpeechDB.modelZoom)
    wow.slash("zoom 3")
    assert.equals(1, ForeverSpeechDB.modelZoom)
  end)

  it("compact on the quest tab; the options open their own window, the main window keeps its size", function()
    local PlayerFrame = ForeverSpeech.PlayerFrame
    ForeverSpeechDB.showText = false
    PlayerFrame.ShowQuest(1)
    local f = PlayerFrame.ListPanel():GetParent()
    local heights = {}
    f.SetHeight = function(_, h) heights[#heights + 1] = h end
    PlayerFrame.SelectTab("options")
    assert.is_true(ForeverSpeech.Options.IsShown())
    assert.equals("quest", f.tab)
    assert.same({}, heights)
  end)

  it("the arrow at the bottom right opens and closes the play list, the window widening to hold it", function()
    local PlayerFrame = ForeverSpeech.PlayerFrame
    PlayerFrame.ShowQuest(1)
    local f, panel, toggle = PlayerFrame.ListPanel():GetParent(), PlayerFrame.ListPanel(), PlayerFrame.ListToggle()
    local widths, tips = {}, {}
    f.SetWidth = function(_, w) widths[#widths + 1] = w end
    _G.GameTooltip = {
      SetOwner = function(self, owner) self.owner = owner end,
      IsOwned = function(self, owner) return self.owner == owner end,
      SetText = function(_, text) tips[#tips + 1] = text end,
      Show = function() end,
      Hide = function(self) self.owner = nil end,
    }
    assert.is_true(ForeverSpeechDB.showList)
    toggle:GetScript("OnEnter")(toggle)
    toggle:Click()
    assert.is_false(ForeverSpeechDB.showList)
    assert.is_false(panel:IsShown())
    toggle:Click()
    assert.is_true(ForeverSpeechDB.showList)
    assert.is_true(panel:IsShown())
    assert.same({ "Fermer la liste de lecture", "Ouvrir la liste de lecture", "Fermer la liste de lecture" }, tips)
    assert.equals(450, widths[1]) -- the window alone
    assert.is_true(widths[2] > 450 + 200) -- and the list
    _G.GameTooltip = nil
  end)

  it("the list toggle is a small round button with the list glyph, quieter while the list is closed", function()
    local PlayerFrame = ForeverSpeech.PlayerFrame
    PlayerFrame.ShowQuest(1)
    local toggle = PlayerFrame.ListToggle()
    assert.matches("glyph_list$", toggle.glyph:GetTexture())
    ForeverSpeechDB.showList = false
    PlayerFrame.UpdateList()
    assert.equals(0.7, select(4, toggle.glyph:GetVertexColor()))
    toggle:Click()
    assert.equals(1, select(4, toggle.glyph:GetVertexColor()))
  end)

  it("the game's frame, titled, without its portrait", function()
    wow.reset()
    blizzardUI()
    local calls = {}
    _G.PortraitFrameMixin = {}
    local createFrame = _G.CreateFrame
    _G.CreateFrame = function(kind, name, parent, template)
      local f = createFrame(kind, name, parent, template)
      if template == "PortraitFrameTemplate" then
        f.SetTitle = function(_, title) calls.title = title end
        f.PortraitContainer = wow.newRegion("Frame")
        f.PortraitContainer:Show()
        calls.frame = f
        f.CloseButton = wow.newRegion("Button")
      end
      return f
    end
    local ok, err = pcall(function()
      wow.loadAddon()
      wow.fire("ADDON_LOADED", "ForeverSpeech")
      wow.fire("PLAYER_LOGIN")
      ForeverSpeech.PlayerFrame.ShowQuest(1)
    end)
    _G.PortraitFrameMixin = nil
    assert(ok, err)
    assert.equals("Alliance Épique", calls.title)
    assert.is_false(calls.frame.PortraitContainer:IsShown())
  end)

  it("the options button opens the options, and again goes back to the quest", function()
    local PlayerFrame = ForeverSpeech.PlayerFrame
    PlayerFrame.ShowQuest(1)
    local f, options = PlayerFrame.ListPanel():GetParent(), PlayerFrame.OptionsButton()
    local tips = {}
    _G.GameTooltip = {
      SetOwner = function(self, owner) self.owner = owner end,
      IsOwned = function(self, owner) return self.owner == owner end,
      SetText = function(_, text) tips[#tips + 1] = text end,
      Show = function() end,
      Hide = function(self) self.owner = nil end,
    }
    options:GetScript("OnEnter")(options)
    options:Click()
    assert.is_true(ForeverSpeech.Options.IsShown())
    assert.equals("quest", f.tab)
    options:Click()
    assert.is_false(ForeverSpeech.Options.IsShown())
    assert.is_true(f.questPanel:IsShown())
    assert.same({ "Options", "Fermer les options", "Options" }, tips)
    _G.GameTooltip = nil
  end)

  it("resizing keeps the top-left corner where it was before the new size", function()
    local PlayerFrame = ForeverSpeech.PlayerFrame
    PlayerFrame.ShowQuest(1)
    local f = PlayerFrame.ListPanel():GetParent()
    -- anchored by its centre: a new width moves its left edge
    local width = 650
    f.GetLeft = function() return 500 - width / 2 end
    f.GetTop = function() return 600 end
    f.SetWidth = function(_, w) width = w end
    local points = {}
    f.SetPoint = function(_, ...) points[#points + 1] = { ... } end
    PlayerFrame.ListToggle():Click() -- close the list: narrower
    assert.same({ "TOPLEFT", UIParent, "BOTTOMLEFT", 175, 600 }, points[#points])
  end)

  it("asks the total time played once, out of the chat (the companion journal); shows no level nor money", function()
    _G.UnitLevel = function() return 12 end
    local requests = 0
    _G.RequestTimePlayed = function() requests = requests + 1 end
    _G.NUM_CHAT_WINDOWS = 1
    _G.ChatFrame1 = wow.newRegion("Frame")
    _G.ChatFrame1:RegisterEvent("TIME_PLAYED_MSG")
    local PlayerFrame = ForeverSpeech.PlayerFrame
    PlayerFrame.ShowQuest(1)
    local f = PlayerFrame.ListPanel():GetParent()
    assert.is_nil(rawget(f, "played")) -- the level and money band is gone (2026-11-05)
    assert.is_nil(rawget(f, "money"))
    wow.fire("PLAYER_ENTERING_WORLD")
    assert.equals(1, requests)
    assert.is_false(_G.ChatFrame1:IsEventRegistered("TIME_PLAYED_MSG")) -- the addon's own request: not in the chat
    wow.fire("TIME_PLAYED_MSG", 90000, 3725)
    assert.equals(90000, ForeverSpeech.Played.Total())
    wow.advance(0)
    assert.is_true(_G.ChatFrame1:IsEventRegistered("TIME_PLAYED_MSG")) -- back for a /played of the player
    wow.fire("PLAYER_ENTERING_WORLD") -- a zone change: no new request
    wow.fire("PLAYER_LEVEL_UP", 13) -- UnitLevel still says 12
    assert.equals(13, ForeverSpeech.Played.Level())
    assert.equals(1, requests) -- a level gained asks nothing
  end)

  it("the Vider button empties the play list", function()
    local Player, PlayerFrame = ForeverSpeech.Player, ForeverSpeech.PlayerFrame
    Player.PlayQuest(1)
    Player.PlayQuest(2)
    PlayerFrame.ListPanel().reset:Click()
    assert.is_nil(Player.Current())
    assert.same({}, listStates())
    assert.equals("playing", (Player.PlayQuest(1))) -- can be played again
  end)

  it("Clear keeps the played quests, drops the others", function()
    local Player = ForeverSpeech.Player
    Player.PlayQuest(1)
    Player.PlayQuest(2)
    Player.PlayQuest(3)
    Player.Next()
    Player.Clear()
    assert.same({ "1:done", "2:done" }, listStates())
  end)

  it("Play / Next / Stop icon buttons under the status line", function()
    local Player, PlayerFrame = ForeverSpeech.Player, ForeverSpeech.PlayerFrame
    Player.PlayQuest(1)
    Player.PlayQuest(2)
    local f = ForeverSpeech.PlayerFrame.ListPanel():GetParent()
    assert.matches("glyph_next$", f.nextButton.glyph:GetTexture())
    f.nextButton:Click()
    assert.equals(2, Player.Current().questID)
    f.stopButton:Click()
    assert.is_false(Player.IsBusy())
    assert.equals(2, PlayerFrame.QuestID())
    f.playButton:Click()
    assert.equals(2, Player.Current().questID)
  end)

  it("options checkboxes write the settings", function()
    ForeverSpeech.PlayerFrame.Open("options")
    assert.is_true(ForeverSpeech.Options.IsShown())
    local openOnPlay = ForeverSpeech.Options.Widgets("general")[2]
    assert.is_true(openOnPlay:GetChecked())
    openOnPlay:SetChecked(false)
    openOnPlay:Click()
    assert.is_false(ForeverSpeechDB.openOnPlay)
    wow.slash("debug off")
    assert.is_false(ForeverSpeechDB.debug)
  end)

  it("debug bar: markers numbered in the trace, reload button", function()
    local reloaded = false
    _G.ReloadUI = function() reloaded = true end
    ForeverSpeechDB.debug = true
    ForeverSpeech.PlayerFrame.Open()
    ForeverSpeech.PlayerFrame.UpdateDebugBar()
    local bar = ForeverSpeech.PlayerFrame.DebugBar()
    assert.is_true(bar:IsShown())
    bar.mark:Click()
    bar.mark:Click()
    local trace = table.concat(ForeverSpeechDB.trace, "\n")
    assert.matches("MARK step 1", trace, 1, true)
    assert.matches("MARK step 2", trace, 1, true)
    assert.matches("3$", bar.mark:GetText())
    bar.reload:Click()
    assert.is_true(reloaded)
    ForeverSpeechDB.debug = false
    ForeverSpeech.PlayerFrame.UpdateDebugBar()
    assert.is_false(bar:IsShown())
  end)

  it("opens empty when no quest is known", function()
    ForeverSpeech.PlayerFrame.Open()
    assert.is_true(ForeverSpeech.PlayerFrame.IsShown())
    assert.not_equals("number", type(ForeverSpeech.PlayerFrame.QuestID()))
  end)

  it("registers in the minimap addon compartment when the client has it", function()
    local registered
    wow.reset()
    blizzardUI()
    _G.AddonCompartmentFrame = { RegisterAddon = function(_, info) registered = info end }
    wow.loadAddon()
    wow.fire("ADDON_LOADED", "ForeverSpeech")
    assert.equals("Alliance Épique", registered.text)
    registered.func(nil, { buttonName = "LeftButton" })
    assert.is_true(ForeverSpeech.PlayerFrame.IsShown())
    registered.func(nil, { buttonName = "RightButton" })
    _G.AddonCompartmentFrame = nil
  end)

  it("minimap button toggles the window and can be hidden", function()
    local b = ForeverSpeech.MinimapButton.button
    assert.is_not_nil(b)
    b:Click("LeftButton")
    assert.is_true(ForeverSpeech.PlayerFrame.IsShown())
    b:Click("LeftButton")
    assert.is_false(ForeverSpeech.PlayerFrame.IsShown())
    ForeverSpeechDB.minimapHide = true
    ForeverSpeech.MinimapButton.Update()
    assert.is_false(b:IsShown())
  end)
end)


describe("turn-in", function()
  before_each(setup)

  local function states()
    local list = {}
    for _, e in ipairs(ForeverSpeech.Player.List()) do
      list[#list + 1] = e.questID .. ":" .. (e.part or "detail") .. ":" .. e.state
    end
    return list
  end

  it("captures the turn-in text and its NPC", function()
    questComplete(783)
    local rec = ForeverSpeech.Capture.LatestCompletion(783)
    assert.equals("Ah, parfait, un autre volontaire.", rec.text)
    assert.equals(197, rec.npcID)
    assert.equals("Maréchal McBride", rec.enderName)
    assert.equals(783, ForeverSpeech.Capture.lastCompleteQuestID)
  end)

  it("reads the end 2 s after the game's Terminer la quête, with the ender's audio", function()
    _G.ForeverSpeechIndex = { version = 8, quests = { [783] = { giver = 823, ender = 197,
      complete = { npc = 197, file = "783_complete.ogg", src = "test" } } },
      npcs = { [197] = { display = 1, name = "Maréchal McBride" } } }
    questComplete(783)
    wow.advance(1)
    assert.equals(0, #wow.sounds) -- the reward panel alone reads nothing
    _G.QuestFrameCompleteQuestButton:Click()
    assert.equals(1, _G.turnedIn)
    wow.advance(1.9)
    assert.equals(0, #wow.sounds) -- the NPC speaks first
    wow.advance(0.1)
    assert.equals("783_complete.ogg", wow.sounds[1].path)
    assert.same({ 783, "complete" }, { ForeverSpeech.PlayerFrame.QuestID() })
  end)

  -- Dialogue UI hides QuestFrame and calls its own copy of GetQuestReward: only QUEST_TURNED_IN comes.
  it("reads a quest turned in by another interface (Dialogue UI)", function()
    questComplete(783)
    wow.fire("QUEST_TURNED_IN", 783, 360, 0)
    wow.advance(2)
    assert.is_true(ForeverSpeech.Player.IsPlaying(783, "complete"))
  end)

  it("reads nothing while the game refuses the turn-in (no reward chosen, bags full)", function()
    questComplete(783)
    _G.rewardChosen = false
    _G.QuestFrameCompleteQuestButton:Click()
    _G.rewardChosen, _G.turnInRefused = true, true
    _G.QuestFrameCompleteQuestButton:Click()
    wow.advance(3)
    assert.equals(1, _G.turnedIn)
    assert.equals(0, #ForeverSpeech.Player.List())
  end)

  it("reads nothing when the option is off", function()
    ForeverSpeechDB.autoplay = false
    questComplete(783)
    _G.QuestFrameCompleteQuestButton:Click()
    wow.advance(3)
    assert.equals(0, #ForeverSpeech.Player.List())
  end)

  it("queues a second turn-in, and a quest can be in the list at its start and its end", function()
    questDetail(18)
    _G.QuestFrameAcceptButton:Click()
    wow.advance(2)
    questComplete(783, "Merci.")
    _G.QuestFrameCompleteQuestButton:Click()
    wow.advance(2)
    questComplete(18, "Bien joué.")
    _G.QuestFrameCompleteQuestButton:Click()
    wow.advance(2)
    assert.same({ "18:detail:playing", "783:complete:queued", "18:complete:queued" }, states())
  end)

  it("falls back to the client TTS on the captured turn-in text", function()
    local spoken = {}
    _G.C_VoiceChat = {
      GetTtsVoices = function() return { { voiceID = 1, name = "Thomas [fr-FR]" } } end,
      SpeakText = function(_, text) spoken[#spoken + 1] = text end,
    }
    questComplete(783, "Ah, parfait.")
    _G.QuestFrameCompleteQuestButton:Click()
    wow.advance(2)
    assert.same({ "Ah, parfait." }, spoken)
  end)

  it("marks the start and the end of a quest in the play list", function()
    local Player = ForeverSpeech.Player
    Player.PlayQuest(783)
    Player.PlayQuest(783, "complete")
    local rows = ForeverSpeech.PlayerFrame.ListPanel().rows
    assert.matches("^|cff40ff40|cffffd200!|r ", rows[1].text:GetText())
    assert.matches("?|r ", rows[2].text:GetText(), 1, true)
    assert.equals("complete", rows[2].part)
  end)
end)

describe("audio on/off", function()
  before_each(setup)

  it("off: nothing plays, the game buttons hide, the window opens on Options", function()
    local Player, PlayerFrame = ForeverSpeech.Player, ForeverSpeech.PlayerFrame
    Player.PlayQuest(18)
    Player.PlayQuest(19)
    assert.is_true(Player.IsPlaying(18))
    ForeverSpeech.SetEnabled(false)
    assert.is_false(Player.IsBusy()) -- stopped
    assert.equals(0, #Player.Queue()) -- and what was left dropped
    assert.same({ "failed", "audio off" }, { Player.PlayQuest(18) })
    questDetail(18)
    _G.QuestFrameAcceptButton:Click()
    wow.advance(2)
    assert.is_false(Player.IsBusy()) -- an accepted quest is not read
    local toggle = PlayerFrame.MakeToggleButton(wow.newRegion("Frame"), 14)
    toggle:SetQuest(18)
    assert.is_false(toggle:IsShown())
    PlayerFrame.Open()
    assert.is_true(ForeverSpeech.Options.IsShown())
    assert.equals("general", ForeverSpeech.Options.Page())
    local listed = #Player.List()
    questComplete(783)
    GetQuestReward(1)
    wow.advance(2)
    assert.equals(listed, #Player.List()) -- the turn-in is not read either
  end)

  it("back on from the toggle at the top of Options", function()
    local Player, PlayerFrame = ForeverSpeech.Player, ForeverSpeech.PlayerFrame
    ForeverSpeech.SetEnabled(false)
    PlayerFrame.Open()
    local enabledToggle = ForeverSpeech.Options.Widgets("general")[1]
    assert.is_false(enabledToggle:GetChecked())
    enabledToggle:SetChecked(true)
    enabledToggle:Click()
    assert.is_true(ForeverSpeechDB.enabled)
    local toggle = PlayerFrame.MakeToggleButton(wow.newRegion("Frame"), 14)
    toggle:SetQuest(18)
    assert.is_true(toggle:IsShown())
    assert.equals("playing", (Player.PlayQuest(18)))
  end)
end)

describe("logbook: while nothing plays, the window shows the followed quest", function()
  local focused, Player, PlayerFrame
  before_each(function()
    setup()
    focused = 50
    _G.C_SuperTrack = { GetSuperTrackedQuestID = function() return focused end }
    Player, PlayerFrame = ForeverSpeech.Player, ForeverSpeech.PlayerFrame
  end)
  after_each(function()
    _G.C_SuperTrack, _G.C_QuestLog = nil, nil
  end)

  local function finishCurrent()
    wow.playing[Player.Current().handle] = nil
    wow.tick(0.3)
  end

  local function follow(questID)
    focused = questID
    wow.fire("SUPER_TRACKING_CHANGED")
  end

  it("goes to the followed quest once the play list has nothing left to play", function()
    Player.PlayQuest(18)
    Player.PlayQuest(19)
    assert.equals(18, PlayerFrame.QuestID())
    finishCurrent()
    assert.equals(19, PlayerFrame.QuestID()) -- the list goes on
    finishCurrent()
    assert.same({ 50, "detail" }, { PlayerFrame.QuestID() })
    assert.is_true(PlayerFrame.IsShown())
  end)

  it("also past the last quest (Avancer) or when the list is emptied, not on Stop", function()
    Player.PlayQuest(18)
    Player.Stop()
    assert.equals(18, PlayerFrame.QuestID()) -- stopped: it can be played again
    Player.PlayQuest(19)
    PlayerFrame.ListPanel():GetParent().nextButton:Click() -- Avancer on the last quest
    assert.equals(50, PlayerFrame.QuestID())
    Player.PlayQuest(20)
    assert.equals(20, PlayerFrame.QuestID())
    PlayerFrame.ListPanel().reset:Click()
    assert.equals(50, PlayerFrame.QuestID())
  end)

  it("follows a change of the followed quest while nothing plays, never during a reading", function()
    PlayerFrame.ShowQuest(18)
    follow(60)
    assert.equals(60, PlayerFrame.QuestID())
    Player.PlayQuest(19)
    follow(70)
    assert.equals(19, PlayerFrame.QuestID())
    finishCurrent()
    assert.equals(70, PlayerFrame.QuestID())
  end)

  it("not during the pause between two quests either", function()
    ForeverSpeechDB.gap = 2
    Player.PlayQuest(18)
    Player.PlayQuest(19)
    finishCurrent()
    follow(60)
    assert.equals(18, PlayerFrame.QuestID())
    wow.advance(2)
    assert.equals(19, PlayerFrame.QuestID())
  end)

  it("keeps a quest picked by hand until the followed quest changes", function()
    wow.fire("QUEST_LOG_UPDATE") -- at login: the followed quest is known
    questDetail(18) -- objectives captured (the stub frame returns a function for an unset field)
    PlayerFrame.ShowQuest(18)
    wow.fire("QUEST_LOG_UPDATE")
    wow.fire("QUEST_WATCH_LIST_CHANGED")
    assert.equals(18, PlayerFrame.QuestID())
    focused = 60
    wow.fire("QUEST_WATCH_LIST_CHANGED") -- without SUPER_TRACKING_CHANGED, the log events catch it
    assert.equals(60, PlayerFrame.QuestID())
  end)

  it("never opens the window nor changes its tab; opened, it shows the followed quest", function()
    wow.fire("QUEST_LOG_UPDATE")
    follow(60)
    assert.is_false(PlayerFrame.IsShown())
    PlayerFrame.Open()
    assert.same({ 60, "detail" }, { PlayerFrame.QuestID() })
    PlayerFrame.SelectTab("options")
    follow(70)
    assert.equals(70, PlayerFrame.QuestID())
    assert.is_true(ForeverSpeech.Options.IsShown()) -- the options window stays open
  end)

  it("stays on what it shows when the option is off", function()
    ForeverSpeechDB.followTracked = false
    Player.PlayQuest(18)
    finishCurrent()
    follow(60)
    assert.equals(18, PlayerFrame.QuestID())
  end)

  it("takes the focused quest, else the first quest of the objective tracker", function()
    local QuestData = ForeverSpeech.QuestData
    _G.C_QuestLog = { GetQuestIDForQuestWatchIndex = function(i) return i == 1 and 33 or nil end }
    assert.same({ 50, "focus" }, { QuestData.Tracked() })
    focused = 0 -- no focused quest
    assert.same({ 33, "tracker" }, { QuestData.Tracked() })
    _G.C_SuperTrack = nil -- API missing on the client
    assert.same({ 33, "tracker" }, { QuestData.Tracked() })
    _G.C_QuestLog = {}
    assert.is_nil(QuestData.Tracked())
  end)
end)
