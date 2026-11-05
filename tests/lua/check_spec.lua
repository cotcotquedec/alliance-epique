local wow = require("tests.lua.helpers.wow")

local ADDON = "addon/ForeverSpeech/"

-- The addon's Lua files, core/check.lua apart (it lists every name, it does not use them).
local function sources()
  local out = {}
  for line in io.lines(ADDON .. "ForeverSpeech.toc") do
    line = line:gsub("%s+$", "")
    if line ~= "" and not line:find("^#") and not line:find("^data\\") and line ~= "core\\check.lua" then
      local f = assert(io.open(ADDON .. line:gsub("\\", "/")))
      out[#out + 1] = f:read("*a")
      f:close()
    end
  end
  return out
end

-- What the addon's code asks of the client, read from its source and from .luacheckrc's read_globals.
local function used()
  local names = { globals = {}, events = {}, templates = {}, atlases = {}, textures = {} }
  local f = assert(io.open(".luacheckrc"))
  local rc = f:read("*a")
  f:close()
  local block = rc:match("\nread_globals = (%b{})")
  for line in block:gmatch("[^\n]+") do
    if not line:find("^%s*%-%-") then
      for name in line:gmatch('"([%w_]+)"') do
        names.globals[name] = true
      end
    end
  end
  -- Lua's own, and the API documentation that only /fs api loads (load-on-demand)
  names.globals.date, names.globals.time, names.globals.APIDocumentation = nil, nil, nil
  for _, src in ipairs(sources()) do
    for name in src:gmatch("[^%w_%.](C_%w+%.%w+)") do
      names.globals[name] = true
    end
    for name in src:gmatch('_G%.([%w_]+)') do
      names.globals[name] = true
    end
    for event in src:gmatch('RegisterEvent%("([%u_]+)"') do
      names.events[event] = true
    end
    for list in src:gmatch("for _, event in ipairs%((%b{})%)") do
      for event in list:gmatch('"([%u_]+)"') do
        names.events[event] = true
      end
    end
    for event in src:gmatch('EVENT = "([%u_]+)"') do
      names.events[event] = true
    end
    for template in src:gmatch('"(%w+Template)"') do
      names.templates[template] = true
    end
    for atlas in src:gmatch('Atlas%([^"\n]-"([%w_%-]+)"') do
      names.atlases[atlas] = true
    end
    for path in src:gmatch('"(Interface\\\\[%w_\\%-]+)"') do
      if not path:find("^Interface\\\\AddOns") then
        names.textures[(path:gsub("\\\\", "\\"))] = true
      end
    end
  end
  return names
end

local function listed()
  local Check = ForeverSpeech.Check
  local out = { globals = {}, events = {}, templates = {}, atlases = {}, textures = {} }
  for _, entry in ipairs(Check.GLOBALS) do
    for _, name in ipairs(type(entry) == "table" and entry or { entry }) do
      out.globals[name] = true
    end
  end
  for _, event in ipairs(Check.EVENTS) do
    out.events[event] = true
  end
  for template in pairs(Check.TEMPLATES) do
    out.templates[template] = true
  end
  for _, atlas in ipairs(Check.ATLASES) do
    out.atlases[atlas] = true
  end
  for _, path in ipairs(Check.TEXTURES) do
    out.textures[path] = true
  end
  return out
end

describe("game check", function()
  before_each(function()
    wow.reset()
    wow.loadAddon()
    wow.fire("ADDON_LOADED", "ForeverSpeech")
  end)

  after_each(function()
    _G.C_Texture, _G.GetFileIDFromPath, _G.InCombatLockdown = nil, nil, nil
  end)

  it("lists every name the addon's code asks of the client", function()
    local want, have = used(), listed()
    local namespaces = {} -- C_QuestLog is checked through its functions
    for name in pairs(have.globals) do
      namespaces[name:match("^([%w_]+)%.") or ""] = true
    end
    local lacking = {}
    for kind, set in pairs(want) do
      for name in pairs(set) do
        if not have[kind][name] and not (kind == "globals" and namespaces[name]) then
          lacking[#lacking + 1] = kind .. " " .. name
        end
      end
    end
    table.sort(lacking)
    assert.same({}, lacking)
  end)

  it("runs once per client build, a few seconds after entering the world, quietly when nothing is missing", function()
    local Check = ForeverSpeech.Check -- lists of names the stubs have: the run's logic, not the client
    Check.GLOBALS, Check.EVENTS = { "CreateFrame", { "NotOnThisClient", "GetTime" } }, { "PLAYER_LOGIN" }
    Check.TEMPLATES, Check.ATLASES, Check.TEXTURES = { UIPanelButtonTemplate = "Button" }, { "checkbox-minimal" },
      { "Interface\\Icons\\Trade_Fishing" }
    _G.C_Texture = { GetAtlasInfo = function() return { width = 1 } end }
    _G.GetFileIDFromPath = function() return 1 end
    wow.fire("PLAYER_ENTERING_WORLD")
    assert.is_nil(ForeverSpeechDB.check)
    wow.advance(5)
    local check = ForeverSpeechDB.check
    assert.equals("1.60.1.70205", check.build)
    assert.same({}, check.missing)
    assert.falsy(wow.chatText():find("game check", 1, true))
    check.at = "kept"
    wow.fire("PLAYER_ENTERING_WORLD")
    wow.advance(5)
    assert.equals("kept", ForeverSpeechDB.check.at)
  end)

  it("says in one chat line what is missing, and /fs check lists it", function()
    _G.C_Texture = { GetAtlasInfo = function(name) return name ~= "checkbox-minimal" and {} or nil end }
    wow.fire("PLAYER_ENTERING_WORLD")
    wow.advance(5)
    local check = ForeverSpeechDB.check
    assert.truthy(#check.missing > 0)
    assert.equals("no GetFileIDFromPath", check.unchecked.texture)
    assert.truthy(table.concat(check.missing, "\n"):find("atlas checkbox-minimal", 1, true))
    assert.truthy(wow.chatText():find("names missing (/fs check for the list)", 1, true))
    assert.same({ 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12 }, check.counted.Radial_Wheel_Select_Wedge_Count_)
    wow.slash("check")
    assert.truthy(wow.chatText():find("  atlas checkbox-minimal", 1, true))
  end)

  it("counts an event the client refuses as missing", function()
    wow.reset({ knownEvents = { ADDON_LOADED = true, PLAYER_LOGIN = true, PLAYER_ENTERING_WORLD = true,
                                QUEST_DETAIL = true } })
    wow.loadAddon()
    wow.fire("ADDON_LOADED", "ForeverSpeech")
    wow.slash("check")
    local missing = table.concat(ForeverSpeechDB.check.missing, "\n")
    assert.truthy(missing:find("event QUEST_ACCEPTED", 1, true))
    assert.falsy(missing:find("event QUEST_DETAIL", 1, true))
  end)

  it("waits for the end of a fight", function()
    _G.InCombatLockdown = function() return true end
    wow.slash("check")
    assert.is_nil(ForeverSpeechDB.check)
    assert.truthy(wow.chatText():find("after the fight", 1, true))
  end)
end)
