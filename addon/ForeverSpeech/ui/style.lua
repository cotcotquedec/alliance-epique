-- ForeverSpeech: the interface's shared look (2026-10-21), so every window, row and map button reads as one set.
-- - Round buttons: the addon's own bronze-gold ring around a dark disc (media/ui/ring.tga) and a gold glyph
--   (media/ui/glyph_<name>.tga: play, stop, next, replay, list), painted for the addon (Codex image generation,
--   tools/ui_icons.ts). The glyph is a little dim at rest and full on hover, sinks a pixel when pressed, and greys out
--   when disabled; a click plays the game's small button sound.
-- - Small row buttons (quest tracker, quest log): the glyph alone on the game's minimal check box when the client has
--   that atlas; the options' check boxes in the same minimal style.
-- - The game's modern atlases only after C_Texture.GetAtlasInfo knows them: a missing atlas draws nothing on these
--   clients, so each has a plainer fallback (idea from Spoken, MIT).
-- - Item buttons framed in their quality colour; section titles in the game's quest title face.
-- - Tooltips in three tiers: the action, a gold help line, a grey hint.
-- Unverified on Forever: T43.
local H = ForeverSpeech

local Style = {}
H.Style = Style

local UI = H.MEDIA .. "ui\\"
Style.RING = UI .. "ring"
Style.PARCHMENT = UI .. "parchment" -- 256 x 256, an aged page (the zone story panel)
Style.DIVIDER = UI .. "divider" -- 512 x 32, a thin ink line with a flourish (under a title on parchment)
local SECTION_GOLD = { 0.88, 0.72, 0.29 } -- muted: a section title is a landmark, not a focal point (third pass)
local GLYPH_ALPHA = 0.85
local SOUND_CLICK = "U_CHAT_SCROLL_BUTTON"

function Style.Glyph(name)
  return UI .. "glyph_" .. name
end

-- True when the client draws this atlas.
function Style.HasAtlas(atlas)
  if not (C_Texture and C_Texture.GetAtlasInfo) then
    return false
  end
  local ok, info = pcall(C_Texture.GetAtlasInfo, atlas)
  return ok and info ~= nil
end

-- Sets the atlas when the client has it and returns true; false leaves the texture to the caller's fallback.
function Style.SetAtlas(tex, atlas, useAtlasSize)
  if Style.HasAtlas(atlas) and tex.SetAtlas then
    return pcall(tex.SetAtlas, tex, atlas, useAtlasSize) == true
  end
  return false
end

-- A SOUNDKIT sound by name, when the client has it.
function Style.Sound(name)
  local kit = SOUNDKIT and SOUNDKIT[name or SOUND_CLICK]
  if kit and PlaySound then
    pcall(PlaySound, kit)
  end
end

-- The action, then a gold help line and a grey hint (both optional).
function Style.Tooltip(owner, anchor, title, help, hint)
  if not GameTooltip then
    return
  end
  GameTooltip:SetOwner(owner, anchor or "ANCHOR_TOP")
  GameTooltip:SetText(title or "")
  if help then
    GameTooltip:AddLine(help, 1, 0.82, 0.2, true)
  end
  if hint then
    GameTooltip:AddLine(hint, 0.6, 0.6, 0.6, true)
  end
  GameTooltip:Show()
end

function Style.HideTooltip()
  if GameTooltip then
    GameTooltip:Hide()
  end
end

-- The glyph shown on a button (round or small), at rest, hovered, pressed or disabled.
local function glyphState(b)
  local g = b.glyph
  local enabled = not b.IsEnabled or b:IsEnabled() ~= false
  if rawget(b, "bronze") then -- FlareUI's struck bronze, lighter when hovered or lit (the theme, below)
    Style.FlareIcon(g, rawget(b, "hovered") or rawget(b, "lit"))
    g:SetAlpha(not enabled and 0.4 or 1)
  else
    if g.SetDesaturated then
      g:SetDesaturated(not enabled)
    end
    g:SetAlpha(not enabled and 0.4 or rawget(b, "hovered") and 1 or GLYPH_ALPHA)
  end
  g:ClearAllPoints()
  g:SetPoint("CENTER", b, "CENTER", rawget(b, "glyphX") or 0, -(rawget(b, "pressed") and 1 or 0))
end

local function wire(b, tooltip)
  b:SetScript("OnEnter", function(self)
    self.hovered = true
    glyphState(self)
    local t = rawget(self, "tooltip")
    if type(t) == "function" then
      Style.Tooltip(self, self.tooltipAnchor, t(self))
    elseif t then
      Style.Tooltip(self, self.tooltipAnchor, t, rawget(self, "help"), rawget(self, "hint"))
    end
  end)
  b:SetScript("OnLeave", function(self)
    self.hovered, self.pressed = false, false
    glyphState(self)
    Style.HideTooltip()
  end)
  b:SetScript("OnMouseDown", function(self)
    self.pressed = true
    glyphState(self)
  end)
  b:SetScript("OnMouseUp", function(self)
    self.pressed = false
    glyphState(self)
  end)
  b:HookScript("OnHide", function(self)
    self.hovered, self.pressed = false, false
    if GameTooltip and GameTooltip.IsOwned and GameTooltip:IsOwned(self) then
      GameTooltip:Hide()
    end
  end)
  b.tooltip = tooltip
  -- Changes the glyph (play <-> stop).
  function b.SetGlyph(self, name)
    self.glyphName = name
    -- FlareUI's theme: the white glyph in its struck bronze; else the gold one
    if not (rawget(self, "bronze") and Style.FlareIcon(self.glyph, false, Style.Glyph(name) .. "_white")) then
      self.glyph:SetTexture(Style.Glyph(name))
    end
    -- a play triangle looks centered a little right of the box's center
    self.glyphX = name == "play" and math.max(1, math.floor(self.glyphSize / 12)) or 0
    glyphState(self)
  end
  -- Enabled or greyed out.
  function b.SetActive(self, active)
    if active then
      self:Enable()
    else
      self:Disable()
    end
    glyphState(self)
  end
end

-- A round button: ring, dark disc, gold glyph. `tooltip` is a string, or a function(button) returning the three
-- tooltip lines. The caller sets OnClick; the click sound is played here. ownLook: the ring in every theme (the world
-- map's buttons: the game's map, which FlareUI leaves alone).
function Style.RoundButton(parent, glyph, size, tooltip, ownLook)
  local b = CreateFrame("Button", nil, parent)
  size = size or 30
  b:SetSize(size, size)
  b.ring = b:CreateTexture(nil, "BACKGROUND")
  b.ring:SetPoint("TOPLEFT", -2, 2)
  b.ring:SetPoint("BOTTOMRIGHT", 2, -2)
  b.ring:SetTexture(Style.RING)
  b.bronze = not ownLook and Style.FlareBronze() -- FlareUI's theme: the glyph alone, in its struck bronze
  b.ring:SetShown(not b.bronze)
  b.glyphSize = math.floor(size * (b.bronze and 0.75 or 0.5) + 0.5)
  b.glyph = b:CreateTexture(nil, "ARTWORK")
  b.glyph:SetSize(b.glyphSize, b.glyphSize)
  b.tooltipAnchor = "ANCHOR_TOP"
  wire(b, tooltip)
  b:HookScript("OnClick", function()
    Style.Sound()
  end)
  b:SetGlyph(glyph)
  return b
end

-- Draws a button's glyph again (its state, or lit set by the caller).
function Style.RefreshButton(b)
  glyphState(b)
end

-- A small square button for list rows: the glyph alone, on the game's minimal check box when the client has it.
function Style.RowButton(parent, glyph, size, tooltip)
  local b = CreateFrame("Button", nil, parent)
  b:SetSize(size, size)
  b.box = b:CreateTexture(nil, "BACKGROUND")
  b.box:SetAllPoints()
  if not Style.SetAtlas(b.box, "checkbox-minimal") then
    b.box:Hide()
  end
  local hl = b:CreateTexture(nil, "HIGHLIGHT")
  hl:SetAllPoints()
  if Style.SetAtlas(hl, "checkbox-minimal") then
    hl:SetBlendMode("ADD")
    hl:SetAlpha(0.6)
  else
    hl:SetColorTexture(1, 1, 1, 0.12)
  end
  b.bronze = Style.FlareBronze() -- FlareUI's theme: the glyph alone, in its struck bronze
  if b.bronze then
    b.box:Hide()
  end
  b.glyphSize = b.box:IsShown() and math.floor(size * 0.7 + 0.5) or size
  b.glyph = b:CreateTexture(nil, "ARTWORK")
  b.glyph:SetSize(b.glyphSize, b.glyphSize)
  b.tooltipAnchor = "ANCHOR_LEFT"
  wire(b, tooltip)
  b:SetGlyph(glyph)
  return b
end

-- A section title on a dark window: the game's quest title face (the one of its quest frame's "Objectifs"), small and
-- muted gold, with a shadow; the font object's own face when the client has no QuestTitleFont.
function Style.Header(fs, size)
  local font = _G.QuestTitleFont
  local face = font and font.GetFont and font:GetFont()
  if face then
    fs:SetFont(face, size or 12, "")
  end
  local flare = Style.Flare and Style.Flare()
  local color = flare and flare.border or SECTION_GOLD -- FlareUI's bronze while it runs (2026-11-05)
  fs:SetTextColor(color[1], color[2], color[3])
  fs:SetShadowColor(0, 0, 0, 1)
  fs:SetShadowOffset(1, -1)
  fs.fsFontKind = "header" -- FlareUI's header face while it runs (Style.FlareFonts)
end


-- An item's quality colour: the client's, else the classic table, else nil (no colour for a poor or common item).
local function qualityColor(quality)
  quality = tonumber(quality)
  if not quality or quality < 2 then
    return nil
  end
  if C_Item and C_Item.GetItemQualityColor then
    local ok, r, g, b = pcall(C_Item.GetItemQualityColor, quality)
    if ok and r then
      return r, g, b
    end
  end
  local colors = _G.ITEM_QUALITY_COLORS
  local c = colors and colors[quality]
  if c then
    return c.r, c.g, c.b
  end
  return nil
end

-- The border of an item button (`b`, its `icon` filling it): the game's icon frame, tinted by the item's quality
-- (uncommon green and up), plain for the others, as in the bags.
function Style.ItemBorder(b, quality)
  local border = rawget(b, "border") -- a missing field of a frame is not nil in every client
  if not border then
    border = b:CreateTexture(nil, "OVERLAY")
    border:SetAllPoints()
    if border:SetTexture("Interface\\Common\\WhiteIconFrame") == false then
      border:SetTexture("Interface\\Buttons\\UI-Quickslot2")
      border:SetTexCoord(0.2, 0.8, 0.2, 0.8)
    end
    b.border = border
  end
  local r, g, bl = qualityColor(quality)
  if r then
    border:SetVertexColor(r, g, bl)
  else
    border:SetVertexColor(0.55, 0.47, 0.3)
  end
end

-- A check button in the game's minimal style when the client has its atlases (the options), else as it is.
function Style.CheckButton(cb)
  if not (Style.HasAtlas("checkbox-minimal") and Style.HasAtlas("checkmark-minimal") and cb.SetNormalAtlas) then
    return false
  end
  return pcall(function()
    cb:SetNormalAtlas("checkbox-minimal")
    cb:SetPushedAtlas("checkbox-minimal")
    cb:SetCheckedAtlas("checkmark-minimal")
    cb:SetDisabledCheckedAtlas(Style.HasAtlas("checkmark-minimal-disabled") and "checkmark-minimal-disabled"
      or "checkmark-minimal")
    cb:SetHighlightAtlas("checkbox-minimal", "ADD")
    local hl = cb:GetHighlightTexture()
    if hl then
      hl:SetAlpha(0.5)
    end
  end) == true
end

-- FlareUI (2026-11-05; MIT, its code read for the look of its windows, nothing copied): while FlareUI runs, the addon's
-- windows look like its own (its settings window). The game's frame art is hidden: the border and title bar
-- (NineSlice), the rock background (Bg) and its streaks. Then the tooltip edge in FlareUI's bronze
-- (FlareUI.WINDOW_STYLE.border), the collections tile under a black wash, a muted bronze line under the title bar, the
-- title on the left, the close button in the corner. An inset box (the play list, a companion's details) gets a light
-- black wash in a muted bronze line instead of the game's sunken frame. Without FlareUI (or with a FlareUI that has no
-- WINDOW_STYLE), the game's frames as before. FlareUI's names are read in _G: a third-party addon, never listed by the
-- game check. Unverified on Forever: T64 (H39).
local FLARE_TILE = "Interface\\Collections\\CollectionsBackgroundTile"
local FLARE_EDGE = "Interface\\Tooltips\\UI-Tooltip-Border"
local FLARE_LINE = { 0.61, 0.48, 0.29, 0.6 } -- FlareUI's muted bronze lines
local FLARE_ART = { "NineSlice", "Bg", "TopTileStreaks", "PortraitContainer" }

-- The quest tracker's look (2026-11-05, after a look in game: beside FlareUI's tracker the window must look like
-- it). Its backdrop: LibSharedMedia's "Blizzard Dialog Background Dark" stretched at the tracker's opacity, its
-- border ("FlareUI Frames" unless the player chose another) in FlareUI's bronze. Its header: a 30-pixel band, the
-- title 14 pixels in from the left in its header font and gold, the buttons on the right 8 pixels in, the game's
-- tooltip divider under it.
-- trackerLook() is nil without LibSharedMedia: the collections tile of before.
local FLARE_HEADER, FLARE_HEADER_INSET, FLARE_PAD = 30, 8, 14 -- FlareUI's tracker
local FLARE_HEADER_Y = -(3 + (FLARE_HEADER - 3) / 2) -- the header band's middle (its band starts 3 pixels down)
local FLARE_TITLE_GOLD = { 1, 0.82, 0 }
local FLARE_DIVIDER = "Interface\\Common\\UI-TooltipDivider-Transparent"
local FLARE_DIALOG_DARK = "Interface\\DialogFrame\\UI-DialogBox-Background-Dark"

local function trackerLook()
  local flare = _G["FlareUI"]
  local libStub = _G["LibStub"]
  local found, lsm = pcall(libStub, "LibSharedMedia-3.0", true)
  if not (found and type(lsm) == "table") then
    return nil
  end
  local db = rawget(flare, "db")
  local profile = type(db) == "table" and db.profile
  local tracker = type(profile) == "table" and profile.objectivetracker
  if type(tracker) ~= "table" then
    tracker = {}
  end
  local okBg, bg = pcall(lsm.Fetch, lsm, "background", "Blizzard Dialog Background Dark", true)
  local name = tracker.borderTexture
  local okValid, valid = pcall(lsm.IsValid, lsm, "border", name)
  if not (type(name) == "string" and okValid and valid) then
    name = "FlareUI Frames"
  end
  local edge
  if name ~= "None" then
    local okEdge, path = pcall(lsm.Fetch, lsm, "border", name, true)
    edge = okEdge and type(path) == "string" and path or nil
  end
  local okSize, size = pcall(rawget(flare, "BorderEdgeSize"), edge, 16)
  return {
    bg = okBg and type(bg) == "string" and bg or FLARE_DIALOG_DARK,
    edge = edge,
    edgeSize = okSize and tonumber(size) or 16,
    opacity = tonumber(tracker.opacity) or 0.6,
    border = rawget(flare, "BORDER_COLOR"),
  }
end

-- FlareUI's window style ({ border = { r, g, b }, ... }) while it runs, else nil.
function Style.Flare()
  local flare = _G["FlareUI"]
  local style = type(flare) == "table" and rawget(flare, "WINDOW_STYLE")
  if type(style) == "table" and type(style.border) == "table" then
    return style
  end
  return nil
end

local function hideArt(f)
  for _, key in ipairs(FLARE_ART) do
    local art = rawget(f, key)
    if type(art) == "table" and art.Hide then
      art:Hide()
    end
  end
  if f.SetBackdrop then
    pcall(f.SetBackdrop, f, nil) -- the tooltip backdrop of a window built without the game's frame
  end
end

local function flareLine(parent, layer)
  local t = parent:CreateTexture(nil, layer or "ARTWORK")
  t:SetColorTexture(FLARE_LINE[1], FLARE_LINE[2], FLARE_LINE[3], FLARE_LINE[4])
  return t
end

-- A separator line in FlareUI's muted bronze while it runs.
function Style.FlareLine(tex)
  if Style.Flare() then
    tex:SetColorTexture(FLARE_LINE[1], FLARE_LINE[2], FLARE_LINE[3], FLARE_LINE[4])
  end
end

-- A window in FlareUI's look while it runs: true once dressed, false without FlareUI (the frame left as it is).
function Style.FlareWindow(f, label)
  local style = Style.Flare()
  if not style then
    return false
  end
  if rawget(f, "ForeverSpeechFlare") then
    return true
  end
  local ok, edge = pcall(CreateFrame, "Frame", nil, f, "BackdropTemplate")
  if not (ok and edge and edge.SetBackdrop) then
    return false
  end
  hideArt(f)
  edge:SetAllPoints(f)
  local look = trackerLook()
  if look then -- the quest tracker's backdrop
    local bg = f:CreateTexture(nil, "BACKGROUND", nil, -8)
    bg:SetPoint("TOPLEFT", 3, -3)
    bg:SetPoint("BOTTOMRIGHT", -3, 3)
    bg:SetTexture(look.bg)
    bg:SetVertexColor(1, 1, 1, look.opacity)
    if look.edge then
      edge:SetBackdrop({ edgeFile = look.edge, edgeSize = look.edgeSize })
      local c = type(look.border) == "table" and look.border
        or { r = style.border[1], g = style.border[2], b = style.border[3] }
      edge:SetBackdropBorderColor(c.r, c.g, c.b, c.a or 1)
    end
  else -- its settings window's: the collections tile under a black wash, the tooltip edge
    local tile = f:CreateTexture(nil, "BACKGROUND", nil, -8)
    tile:SetPoint("TOPLEFT", 5, -5)
    tile:SetPoint("BOTTOMRIGHT", -5, 5)
    tile:SetTexture(FLARE_TILE, "REPEAT", "REPEAT")
    tile:SetHorizTile(true)
    tile:SetVertTile(true)
    local wash = f:CreateTexture(nil, "BACKGROUND", nil, -7)
    wash:SetAllPoints(tile)
    wash:SetColorTexture(0, 0, 0, 0.5)
    edge:SetBackdrop({ edgeFile = FLARE_EDGE, edgeSize = 16 })
    edge:SetBackdropBorderColor(style.border[1], style.border[2], style.border[3], 1)
  end
  -- the tracker's header band: the divider under it, the title on the left, the buttons on the right
  local divider = f:CreateTexture(nil, "ARTWORK")
  divider:SetTexture(FLARE_DIVIDER)
  divider:SetPoint("TOPLEFT", FLARE_HEADER_INSET, -FLARE_HEADER + 2)
  divider:SetPoint("TOPRIGHT", -FLARE_HEADER_INSET, -FLARE_HEADER + 2)
  divider:SetHeight(8)
  local container = rawget(f, "TitleContainer")
  local title = (type(container) == "table" and rawget(container, "TitleText")) or rawget(f, "TitleText")
  if type(title) == "table" then
    title.fsFontKind, title.fsFlareSize = "header", true -- its header font, at its size
    title:ClearAllPoints()
    title:SetPoint("LEFT", f, "TOPLEFT", FLARE_PAD, FLARE_HEADER_Y)
    title:SetJustifyH("LEFT")
    title:SetTextColor(FLARE_TITLE_GOLD[1], FLARE_TITLE_GOLD[2], FLARE_TITLE_GOLD[3])
  end
  local close = rawget(f, "CloseButton")
  if type(close) == "table" then
    close:ClearAllPoints()
    close:SetPoint("RIGHT", f, "TOPRIGHT", -FLARE_HEADER_INSET, FLARE_HEADER_Y)
    Style.FlareCloseButton(close) -- FlareUI's box button
  end
  f.ForeverSpeechFlare = edge
  H.Trace("style: FlareUI look on the %s window (%s)", label or "?", look and "tracker" or "tile")
  return true
end

-- An inset box in FlareUI's look while it runs: true once dressed, false without FlareUI.
function Style.FlareInset(box)
  if not Style.Flare() then
    return false
  end
  if rawget(box, "ForeverSpeechFlare") then
    return true
  end
  hideArt(box)
  local wash = box:CreateTexture(nil, "BACKGROUND", nil, -8)
  wash:SetAllPoints()
  wash:SetColorTexture(0, 0, 0, 0.25)
  local edges = {}
  local sides = { { "TOPLEFT", "TOPRIGHT" }, { "BOTTOMLEFT", "BOTTOMRIGHT" }, { "TOPLEFT", "BOTTOMLEFT" },
    { "TOPRIGHT", "BOTTOMRIGHT" } }
  for i, side in ipairs(sides) do
    local t = flareLine(box, "BORDER")
    t:SetPoint(side[1])
    t:SetPoint(side[2])
    if i <= 2 then
      t:SetHeight(1)
    else
      t:SetWidth(1)
    end
    edges[i] = t
  end
  box.ForeverSpeechFlare = edges
  return true
end


-- The FlareUI theme (2026-11-05, asked by the player: FlareUI's windows, buttons, colours and font while it runs,
-- always the game's elements without it). The painted content (Elise's portrait, the difficulty badges, the zone
-- paintings, the wheel's and the tabs' icons) stays in both; the decor follows FlareUI:
-- - its window frame (Style.FlareWindow, Style.FlareInset, above);
-- - its quest tracker's font faces (FlareUI.db.profile.objectivetracker: headerFont for the window and section titles,
--   titleFont for the quest title, objectiveFont for the rest), their outline and shadow; the addon's sizes kept;
-- - its bronze: section titles, rules, the medallion's ring;
-- - its struck-bronze icons (FlareUI.BronzeIcon.Paint, the colour of its header icons): the round buttons' glyphs
--   without their ring, the row buttons' glyphs without their box, the title bar's icons; lighter when lit or hovered.
-- Unverified on Forever: T67.
local FLARE_ICON = { r = 0.61, g = 0.48, b = 0.29, a = 1 } -- FlareUI's header icons

-- A font face of FlareUI's quest tracker ("header", "title" or "objective"): its path, outline and settings, else nil.
function Style.FlareFont(kind)
  local flare = Style.Flare() and _G["FlareUI"]
  local db = flare and rawget(flare, "db")
  local profile = type(db) == "table" and db.profile
  local tracker = type(profile) == "table" and profile.objectivetracker
  local cfg = type(tracker) == "table" and tracker[kind .. "Font"]
  local getPath = flare and rawget(flare, "GetFontPath")
  if type(cfg) ~= "table" or type(getPath) ~= "function" then
    return nil
  end
  local ok, path = pcall(getPath, cfg.face or "Friz Quadrata TT")
  if not ok or type(path) ~= "string" then
    return nil
  end
  local flags = cfg.flags
  if flags == nil or flags == "NONE" then
    flags = ""
  end
  return path, flags, cfg
end

local function flareFont(fs, kind)
  local path, flags, cfg = Style.FlareFont(kind)
  if not path then
    return false
  end
  local ok, _, current = pcall(fs.GetFont, fs)
  -- the addon's size, or FlareUI's for a font string that asks for it (the window's title, as the tracker's)
  local size = rawget(fs, "fsFlareSize") and tonumber(cfg.size) or (ok and tonumber(current))
  if not size or not pcall(fs.SetFont, fs, path, size, flags) then
    return false
  end
  local shadow = rawget(_G["FlareUI"], "ApplyShadow")
  if type(shadow) == "function" then
    pcall(shadow, fs, cfg)
  end
  return true
end

-- Every font string of a window and its children in FlareUI's faces (fs.fsFontKind: "header", "title", else
-- "objective"); their sizes kept. The number changed (0 without FlareUI).
function Style.FlareFonts(root)
  if not Style.Flare() then
    return 0
  end
  local count = 0
  local function walk(frame)
    for _, region in ipairs({ frame:GetRegions() }) do
      if type(region) == "table" and region.GetObjectType and region:GetObjectType() == "FontString"
        and flareFont(region, rawget(region, "fsFontKind") or "objective") then
        count = count + 1
      end
    end
    for _, child in ipairs({ frame:GetChildren() }) do
      if type(child) == "table" then
        walk(child)
      end
    end
  end
  walk(root)
  return count
end

-- A window in FlareUI's faces now and at each show (the font strings made since); nothing without FlareUI. Called
-- once its own scripts are set (a SetScript would drop the hook).
function Style.FlareTheme(f, label)
  if not Style.Flare() then
    return false
  end
  H.Trace("style: FlareUI fonts on the %s window (%d)", label or "?", Style.FlareFonts(f))
  f:HookScript("OnShow", function(self)
    Style.FlareFonts(self)
  end)
  return true
end

-- FlareUI's own icons (its chat and damage meter headers): the addon's title bar uses them in its theme.
local FLARE_MEDIA = "Interface\\AddOns\\FlareUI\\Media\\Icons\\"
Style.FLARE_ICONS = { settings = FLARE_MEDIA .. "DMSettings.tga", social = FLARE_MEDIA .. "ChatSocial.tga" }

local function bronzeIcon()
  local flare = Style.Flare() and _G["FlareUI"]
  local bronze = flare and rawget(flare, "BronzeIcon")
  if type(bronze) == "table" and type(bronze.Apply) == "function" and type(bronze.Paint) == "function" then
    return bronze
  end
  return nil
end

-- True when FlareUI runs with its struck bronze (the round and row buttons take it).
function Style.FlareBronze()
  return bronzeIcon() ~= nil
end

-- An icon in FlareUI's struck bronze, as its header icons: with a path, the icon set to that white image with its
-- dark copy under it and its light copy over it (BronzeIcon.Apply); then only the bronze again (BronzeIcon.Paint),
-- lighter when lit or hovered. False without FlareUI. (A first try greyed the addon's gold glyphs: the bronze did not
-- take on them, 2026-11-05; the round buttons now use white glyphs, tools/white_glyphs.ts.)
function Style.FlareIcon(tex, lit, path)
  local bronze = bronzeIcon()
  if not bronze then
    return false
  end
  if path and not pcall(bronze.Apply, tex, path, FLARE_ICON) then
    return false
  end
  return pcall(bronze.Paint, tex, FLARE_ICON, lit and true or false) == true
end

-- The close button as FlareUI's box buttons (its tracker's "−", redone 2026-11-05 after a look in game): a square of
-- whole screen pixels (an even number), a one-pixel bronze outline with its corners cut in steps, a dark fill, and an
-- x of two-pixel strokes; lighter when pointed at; laid out again at each show (the UI scale may change). The game's
-- art hidden. Without rotated textures, an x character. False without FlareUI.
local BOX_EDGE, BOX_EDGE_LIT, BOX_SIZE, BOX_CHAMFER = { 0.50, 0.38, 0.21 }, { 0.65, 0.49, 0.27 }, 12, 2

-- The size of a screen pixel in the frame's units (FlareUI's own reading), else 1.
local function pixelSize(frame)
  local flare = _G["FlareUI"]
  local ok, px = pcall(flare and rawget(flare, "PixelSize"), frame)
  px = ok and tonumber(px)
  return px and px > 0 and px or 1
end

function Style.FlareCloseButton(close)
  if not Style.Flare() or rawget(close, "ForeverSpeechBox") then
    return false
  end
  for _, region in ipairs({ close:GetRegions() }) do
    if type(region) == "table" and region.GetObjectType and region:GetObjectType() == "Texture" then
      region:SetAlpha(0)
    end
  end
  for _, getter in ipairs({ "GetNormalTexture", "GetPushedTexture", "GetHighlightTexture", "GetDisabledTexture" }) do
    local ok, tex = pcall(close[getter], close)
    if ok and type(tex) == "table" and tex.SetAlpha then
      tex:SetAlpha(0)
    end
  end
  local function tex(layer)
    local t = close:CreateTexture(nil, layer)
    pcall(t.SetSnapToPixelGrid, t, false)
    pcall(t.SetTexelSnappingBias, t, 0)
    return t
  end
  local box = { edges = {}, steps = {}, fill = {}, strokes = {} }
  for i = 1, 4 do
    box.edges[i] = tex("ARTWORK")
    box.steps[i] = tex("ARTWORK")
  end
  for i = 1, BOX_CHAMFER do
    box.fill[i] = tex("BACKGROUND")
    box.fill[i]:SetColorTexture(0, 0, 0, 0.85)
  end
  box.strokes[1], box.strokes[2] = tex("OVERLAY"), tex("OVERLAY")
  local rotates = pcall(box.strokes[1].SetRotation, box.strokes[1], 0)
  local x
  if not rotates then
    x = close:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    x:SetPoint("CENTER", 0, 1)
    x:SetText("×")
  end
  local function paint(lit)
    local c = lit and BOX_EDGE_LIT or BOX_EDGE
    for _, list in ipairs({ box.edges, box.steps, box.strokes }) do
      for _, t in ipairs(list) do
        t:SetColorTexture(c[1], c[2], c[3], 1)
      end
    end
    if x then
      x:SetTextColor(c[1] + 0.2, c[2] + 0.2, c[3] + 0.2)
    end
  end
  local function layout()
    local px = pixelSize(close)
    local n = math.max(BOX_CHAMFER * 2 + 4, math.floor(BOX_SIZE / px + 0.5)) -- the side, in pixels
    if n % 2 == 1 then
      n = n + 1 -- even, so the x centres
    end
    local c = BOX_CHAMFER
    local function place(t, left, top, w, h)
      t:ClearAllPoints()
      t:SetPoint("TOPLEFT", close, "TOPLEFT", left * px, -top * px)
      t:SetSize(w * px, h * px)
      t:Show()
    end
    close:SetSize(n * px, n * px)
    place(box.edges[1], c, 0, n - 2 * c, 1) -- the sides, stopping short of the corners
    place(box.edges[2], c, n - 1, n - 2 * c, 1)
    place(box.edges[3], 0, c, 1, n - 2 * c)
    place(box.edges[4], n - 1, c, 1, n - 2 * c)
    local corners = { { 1, c - 1 }, { n - 2, c - 1 }, { 1, n - c }, { n - 2, n - c } } -- the steps joining them
    for i, xy in ipairs(corners) do
      place(box.steps[i], xy[1], xy[2], 1, 1)
    end
    for k = 1, c do -- the fill: rectangles a pixel narrower and taller each, stopping at the steps
      local inset = c - k + 1
      place(box.fill[k], k, inset, n - 2 * k, n - 2 * inset)
    end
    local arm = math.floor(n * 0.5 + 0.5)
    for s, angle in ipairs({ math.pi / 4, -math.pi / 4 }) do
      local t = box.strokes[s]
      t:ClearAllPoints()
      t:SetPoint("CENTER", close, "CENTER", 0, 0)
      t:SetSize(arm * px * 1.3, 2 * px)
      if rotates then
        t:SetRotation(angle)
      else
        t:Hide()
      end
    end
  end
  layout()
  paint(false)
  close:HookScript("OnShow", layout)
  close:HookScript("OnEnter", function() paint(true) end)
  close:HookScript("OnLeave", function() paint(false) end)
  close.ForeverSpeechBox = box
  return true
end

-- A texture tinted in FlareUI's bronze (its windows' edge): the medallion's ring. False without FlareUI.
function Style.FlareTint(tex)
  local style = Style.Flare()
  if not style then
    return false
  end
  if tex.SetDesaturated then
    tex:SetDesaturated(true)
  end
  tex:SetVertexColor(style.border[1], style.border[2], style.border[3])
  return true
end

