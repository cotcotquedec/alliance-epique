local wow = require("tests.lua.helpers.wow")

-- The voices in their own folder, AllianceEpique_Voix (2026-11-05): read there when it is installed, else in the
-- addon's own folder.
local OWN = "Interface\\AddOns\\ForeverSpeech\\audio\\823\\783_detail.ogg"
local VOICES = "Interface\\AddOns\\AllianceEpique_Voix\\audio\\823\\783_detail.ogg"
local entry = { file = OWN }

local function setup(addons)
  wow.reset()
  wow.loadAddon()
  wow.fire("ADDON_LOADED", "ForeverSpeech")
  _G.C_AddOns = addons
end

after_each(function()
  _G.C_AddOns, _G.GetAddOnInfo = nil, nil
end)

describe("the voices' folder", function()
  it("reads the files there when it is installed", function()
    setup({ DoesAddOnExist = function(name) return name == "AllianceEpique_Voix" end })
    assert.equals(VOICES, ForeverSpeech.Index.FileFor(entry))
    assert.truthy(table.concat(ForeverSpeechDB.trace, "\n"):find("index: voices folder installed", 1, true))
  end)

  it("reads them in the addon's own folder without it", function()
    setup({ DoesAddOnExist = function() return false end })
    assert.equals(OWN, ForeverSpeech.Index.FileFor(entry))
  end)

  it("asks the addon's info on a client without DoesAddOnExist", function()
    setup(nil)
    _G.GetAddOnInfo = function(name)
      if name == "AllianceEpique_Voix" then
        return name, "Alliance Épique — Voix", "", false, "DEMAND_LOADED"
      end
    end
    assert.equals(VOICES, ForeverSpeech.Index.FileFor(entry))
  end)

  it("leaves alone a file outside the addon's audio", function()
    setup({ DoesAddOnExist = function() return true end })
    assert.equals("Sound\\x.ogg", ForeverSpeech.Index.FileFor({ file = "Sound\\x.ogg" }))
  end)
end)
