local wow = require("tests.lua.helpers.wow")

-- A quest log of one quest (18) whose objective counter is `have`, and a chat that records what is sent.
local function setup(opts)
  opts = opts or {}
  wow.reset()
  wow.loadAddon()
  wow.fire("ADDON_LOADED", "ForeverSpeech")
  local log = { have = opts.have or 3, inLog = true, group = opts.group ~= false, raid = false }
  _G.C_QuestLog = {
    GetNumQuestLogEntries = function() return log.inLog and 2 or 1 end,
    GetInfo = function(i)
      if i == 1 then
        return { isHeader = true, title = "Forêt d'Elwynn" }
      end
      return { questID = 18, title = "Brigands" }
    end,
    GetLogIndexForQuestID = function() return log.inLog and 2 or nil end,
    GetTitleForQuestID = function() return "Brigands" end,
    GetQuestObjectives = function()
      return {
        { text = "Masque rouge : " .. log.have .. "/12", finished = log.have >= 12 },
        { text = "Bandana : 1/1", finished = true },
      }
    end,
  }
  _G.IsInGroup = function() return log.group end
  _G.IsInRaid = function() return log.raid end
  log.sent = {}
  _G.SendChatMessage = function(msg, channel) log.sent[#log.sent + 1] = { msg, channel } end
  return log
end

local function update()
  wow.fire("QUEST_LOG_UPDATE")
  wow.advance(0.5)
end

describe("quest announcements", function()
  it("tells the group once when the objectives get all done", function()
    local log = setup()
    update() -- first look: states only
    log.have = 12
    update()
    assert.same({ { "{rt1} J'ai terminé « Brigands » : Masque rouge : 12/12 ; Bandana : 1/1.", "PARTY" } }, log.sent)
    update()
    assert.equals(1, #log.sent)
  end)

  it("never for a quest already done at login, nor outside a group, nor with the setting off", function()
    local log = setup({ have = 12 })
    update()
    update()
    assert.equals(0, #log.sent)

    log = setup({ group = false })
    update()
    log.have = 12
    update()
    assert.equals(0, #log.sent)

    log = setup()
    ForeverSpeechDB.announceComplete = false
    update()
    log.have = 12
    update()
    assert.equals(0, #log.sent)
  end)

  it("writes in the raid or in /say by the setting", function()
    local log = setup()
    log.raid = true
    update()
    log.have = 12
    update()
    assert.equals("RAID", log.sent[1][2])

    log = setup()
    ForeverSpeechDB.announceChannel = "say"
    update()
    log.have = 12
    update()
    assert.equals("SAY", log.sent[1][2])
  end)

  it("keeps the line within 255 bytes, never inside a character", function()
    setup()
    _G.C_QuestLog.GetQuestObjectives = function()
      local list = {}
      for i = 1, 20 do
        list[i] = { text = "Écaille d'élémentaire n° " .. i .. " : 0/1", finished = false }
      end
      return list
    end
    local message = ForeverSpeech.Announce.Message(18)
    assert.is_true(#message <= 255)
    assert.equals("…", message:sub(-3))
    assert.is_nil(message:sub(1, -4):match("[\192-\255][\128-\191]*$"))
  end)

  it("/fs announce sends now, or shows the line here outside a group", function()
    local log = setup()
    wow.slash("announce 18")
    assert.equals(1, #log.sent)
    log.group = false
    wow.slash("announce 18")
    assert.equals(1, #log.sent)
    assert.truthy(wow.chatText():find("J'ai terminé « Brigands »", 1, true))
  end)
end)
