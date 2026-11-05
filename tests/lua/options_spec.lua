local wow = require("tests.lua.helpers.wow")

local function setup()
  wow.reset()
  wow.loadAddon()
  _G.ForeverSpeechIndex = { version = 8, quests = { [18] = { level = 4 } }, npcs = {} }
  wow.fire("ADDON_LOADED", "ForeverSpeech")
  wow.fire("PLAYER_LOGIN")
  ForeverSpeechDB.gap = 0
end

-- The widget of a page whose label (or button text) contains a text.
local function widget(page, text)
  for _, w in ipairs(ForeverSpeech.Options.Widgets(page)) do
    local label = (w.label and type(w.label) == "table" and w.label.GetText and w.label:GetText()) or w:GetText()
    if type(label) == "string" and label:find(text, 1, true) then
      return w
    end
  end
  error("no widget " .. text .. " on " .. page)
end

local function toggle(w)
  w:SetChecked(not w:GetChecked())
  w:Click()
end

describe("options window", function()
  local Options
  before_each(function()
    setup()
    Options = ForeverSpeech.Options
  end)

  it("seven themes; a theme shows its settings; the last one is kept", function()
    Options.Open()
    assert.equals("general", Options.Page())
    for _, key in ipairs({ "general", "reading", "window", "elise", "companions", "comfort", "advanced" }) do
      Options.Show(key)
      assert.equals(key, Options.Page())
      assert.is_true(#Options.Widgets(key) > 0)
    end
    Options.Hide()
    Options.Open()
    assert.equals("advanced", Options.Page())
    wow.slash("options elise")
    assert.equals("elise", Options.Page())
    Options.Toggle()
    assert.is_false(Options.IsShown())
  end)

  it("every setting of before is still there, by theme", function()
    Options.Open()
    widget("general", "Ouvrir cette fenêtre")
    widget("general", "afficher la quête suivie")
    widget("general", "Afficher la liste de lecture")
    widget("general", "Icône sur la minimap")
    widget("reading", "acceptées et rendues")
    widget("reading", "Son de page")
    widget("reading", "Couper les voix du jeu")
    widget("window", "texte de la quête")
    widget("elise", "présente chaque zone")
    widget("elise", "chaque niveau gagné")
    widget("elise", "palier d'amitié")
    widget("advanced", "Mode debug")
  end)

  it("the quest level in the title can be turned off", function()
    _G.UnitLevel = function() return 3 end
    _G.GetQuestID = function() return 18 end
    _G.GetTitleText = function() return "La confrérie des voleurs" end
    _G.GetQuestText = function() return "Texte." end
    wow.fire("QUEST_DETAIL", 0)
    ForeverSpeech.PlayerFrame.ShowQuest(18)
    assert.is_not_nil(ForeverSpeech.PlayerFrame.Badge())
    Options.Open("window")
    toggle(widget("window", "Niveau de la quête"))
    assert.is_false(ForeverSpeechDB.showQuestLevel)
    assert.equals("|cffffd200!|r La confrérie des voleurs", ForeverSpeech.PlayerFrame.Title())
    assert.is_nil(ForeverSpeech.PlayerFrame.Badge())
  end)


  it("the model framing cycles through four framings and applies at once", function()
    Options.Open("window")
    local zoom = widget("window", "Cadrage")
    assert.equals("Tête et épaules", zoom.button:GetText())
    zoom.button:Click()
    assert.equals(1, ForeverSpeechDB.modelZoom)
    assert.equals("Visage", zoom.button:GetText())
    zoom.button:Click()
    assert.equals(0, ForeverSpeechDB.modelZoom)
  end)

  it("companions: tooltip lines and counting can be turned off", function()
    local guid = "Player-1-0000AAAA"
    ForeverSpeechDB.companions = { ["?-?"] = { groupSeconds = 0, bags = {}, list = {
      [guid] = { name = "Arthas", seconds = 4000, groups = 2, longest = 2000, tier = 2 } } } }
    _G.UnitGUID = function() return guid end
    local tooltip = { GetUnit = function() return "Arthas", "mouseover" end, AddLine = function() end }
    assert.is_true(ForeverSpeech.Companions.AddTooltipLines(tooltip))
    Options.Open("companions")
    toggle(widget("companions", "infobulle"))
    assert.is_false(ForeverSpeech.Companions.AddTooltipLines(tooltip))
    toggle(widget("companions", "Compter le temps"))
    assert.is_false(ForeverSpeechDB.companionsTrack)
  end)

  it("Elise: hear every zone again", function()
    ForeverSpeech.Zones.MarkSeen(1429)
    assert.is_true(ForeverSpeech.Zones.Seen(1429))
    Options.Open("elise")
    widget("elise", "Réentendre"):Click()
    assert.is_false(ForeverSpeech.Zones.Seen(1429))
  end)

  it("reset: the first click asks, the second resets every setting but the minimap icon's place", function()
    ForeverSpeechDB.openOnPlay, ForeverSpeechDB.gap, ForeverSpeechDB.minimapAngle = false, 5, 90
    Options.Open("advanced")
    local reset = widget("advanced", "Réinitialiser")
    reset:Click()
    assert.equals("Confirmer ?", reset:GetText())
    assert.is_false(ForeverSpeechDB.openOnPlay)
    reset:Click()
    assert.is_true(ForeverSpeechDB.openOnPlay)
    assert.equals(2, ForeverSpeechDB.gap)
    assert.equals(90, ForeverSpeechDB.minimapAngle)
    assert.is_true(widget("general", "Ouvrir cette fenêtre"):GetChecked())
  end)
end)

describe("options in the game's own panel (Settings API)", function()
  local opened, registered, panel

  local function setupSettings()
    wow.reset()
    opened, registered = {}, {}
    panel = CreateFrame("Frame")
    panel:Hide()
    _G.SettingsPanel = panel
    _G.HideUIPanel = function(f) f:Hide() end
    local id = 0
    local function category(name)
      id = id + 1
      local c = { ID = id, name = name }
      function c.GetID(self) return self.ID end
      registered[#registered + 1] = c
      return c
    end
    _G.Settings = {
      RegisterCanvasLayoutCategory = function(_, name) return category(name) end,
      RegisterCanvasLayoutSubcategory = function(_, _, name) return category(name) end,
      RegisterAddOnCategory = function() end,
      OpenToCategory = function(categoryID)
        opened[#opened + 1] = categoryID
        panel:Show()
      end,
    }
    wow.loadAddon()
    _G.ForeverSpeechIndex = { version = 9, quests = {}, npcs = {} }
    wow.fire("ADDON_LOADED", "ForeverSpeech")
    wow.fire("PLAYER_LOGIN")
  end

  after_each(function()
    _G.Settings, _G.SettingsPanel, _G.HideUIPanel = nil, nil, nil
  end)

  it("registers the addon's category (its title) and a subcategory per other theme", function()
    setupSettings()
    assert.is_true(ForeverSpeech.Options.InGameOptions())
    assert.equals(7, #registered)
    assert.equals("Alliance Épique", registered[1].name)
    assert.equals(ForeverSpeech.L.OPT_PAGE_ELISE, registered[4].name)
    assert.is_true(#ForeverSpeech.Options.Widgets("comfort") > 0)
  end)

  it("opens the game's panel on the theme asked, then the last one; the gear closes it", function()
    setupSettings()
    local Options = ForeverSpeech.Options
    Options.Open("elise")
    assert.equals(4, opened[#opened])
    assert.is_true(Options.IsShown())
    assert.equals("elise", Options.Page())
    Options.Toggle()
    assert.is_false(Options.IsShown())
    Options.Open()
    assert.equals(4, opened[#opened])
  end)

  it("does not open in combat, and says so", function()
    setupSettings()
    _G.InCombatLockdown = function() return true end
    ForeverSpeech.Options.Open("comfort")
    _G.InCombatLockdown = nil
    assert.equals(0, #opened)
    assert.matches("après le combat", wow.chatText())
  end)
end)
