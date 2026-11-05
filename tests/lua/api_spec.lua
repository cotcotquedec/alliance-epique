local wow = require("tests.lua.helpers.wow")

describe("/fs api", function()
  before_each(function()
    wow.reset()
    wow.loadAddon()
    wow.fire("ADDON_LOADED", "ForeverSpeech")
  end)

  after_each(function()
    _G.APIDocumentation = nil
  end)

  it("stores the function and event signatures of the documentation", function()
    _G.APIDocumentation = { systems = { {
      Namespace = "C_Sound",
      Functions = { { Name = "IsPlaying", Arguments = { { Name = "soundHandle", Type = "number" } },
                      Returns = { { Name = "isPlaying", Type = "bool" } } } },
      Events = { { LiteralName = "SOUNDKIT_FINISHED", Payload = { { Name = "soundHandle", Type = "number",
                                                                    Nilable = true } } } },
    } } }
    wow.slash("api")
    assert.same({ "fn C_Sound.IsPlaying(soundHandle:number) -> isPlaying:bool",
                  "ev SOUNDKIT_FINISHED(soundHandle:number?)" }, ForeverSpeechDB.api)
  end)

  it("drops the phase-0 spike logs", function()
    assert.is_nil(ForeverSpeechDB.spikes)
  end)
end)
