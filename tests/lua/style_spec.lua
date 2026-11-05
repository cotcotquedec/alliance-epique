local wow = require("tests.lua.helpers.wow")

local function load()
  wow.reset()
  wow.loadAddon()
  wow.fire("ADDON_LOADED", "ForeverSpeech")
  return ForeverSpeech.Style
end

describe("interface style", function()
  it("tints an item's border by its quality, a plain bronze below uncommon", function()
    local Style = load()
    _G.ITEM_QUALITY_COLORS = { [3] = { r = 0, g = 0.44, b = 0.87 } }
    local b = CreateFrame("Button")
    Style.ItemBorder(b, 3)
    local border = rawget(b, "border")
    local r, g, bl = border:GetVertexColor()
    assert.same({ 0, 0.44, 0.87 }, { r, g, bl })
    Style.ItemBorder(b, 1)
    assert.equals(0.55, (border:GetVertexColor()))
  end)

  it("keeps the classic check box when the client has no minimal atlas", function()
    local Style = load()
    _G.C_Texture = nil
    assert.is_false(Style.CheckButton(CreateFrame("CheckButton")))
  end)

  it("uses an atlas only once the client knows it", function()
    local Style = load()
    _G.C_Texture = { GetAtlasInfo = function(atlas) return atlas == "checkbox-minimal" and {} or nil end }
    assert.is_true(Style.HasAtlas("checkbox-minimal"))
    assert.is_false(Style.HasAtlas("widgetstatusbar-fill-yellow"))
  end)
end)
