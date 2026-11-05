-- ForeverSpeech: the player window (CLAUDE.md 9.5). Movable, position saved; NPC model with the
-- quest icon as fallback, title, giver, status and Play/Next/Stop icons, the quest text (option, small
-- print), objectives, rewards. The window closes with its top-right cross.
-- S8: SetCreature only works for NPCs in the client cache, SetDisplayInfo for any display ID.
local H = ForeverSpeech
local L = H.L

local PlayerFrame = {}
H.PlayerFrame = PlayerFrame

-- The window is compact on the quest tab (it grows downwards with the quest text when it is shown); the options
-- have their own window since 2026-10-15 (ui/options_frame.lua).
-- Layout of the quest tab (2026-10-21, third pass: lighter and balanced). One spacing scale, 4 / 8 / 12 / 16: PAD
-- around the content, GAP between the portrait and its column, SECTION between two blocks, 6 under a section title.
-- One focal point, the quest title; the rest quieter: small round controls grouped under it (the list toggle with
-- them), a smaller level badge, section titles small and muted, their dividers faint.
-- Fourth pass (2026-10-21, after a look in game: still cramped, unfinished): 30 pixels wider, more air between blocks,
-- the window's height measured on the real layout (the estimate fell short: the rewards ran over the footer).
-- The height is first estimated (questHeight), then measured once the client has laid the tab out (fitQuestTab).
local WIDTH = 450
local PAD, PAD_TOP, SECTION, TITLE_GAP, TITLE_H = 16, 12, 16, 6, 14
local SECTION_TITLE_SIZE = 12
-- Quest text (option showText, 2026-10-07): small print, at most TEXT_MAX_LINES lines (ellipsis after).
-- The client has no italic font: a muted parchment colour sets it apart instead.
local TEXT_MAX_LINES, TEXT_LINE_HEIGHT, TEXT_GAP, TEXT_SPACING = 14, 13, 12, 2
local TEXT_COLOR = { 0.81, 0.78, 0.68 }
local SOFT = { 0.88, 0.86, 0.80 } -- body text: off-white, softer than the title
-- Quest part markers, as on the game's quest NPCs: "!" a quest to take, "?" a quest to turn in.
local PART_MARK = { detail = "|cffffd200!|r ", complete = "|cffffd200?|r " }
-- Quest level badge (2026-10-18), centered in the free space right of the Play / Next / Stop buttons, from the status
-- line down to the model's bottom: a shield painted for each difficulty, plainer for an easy quest, majestic then
-- deadly for a hard one (media/difficulty/<key>.tga, 128 x 128, centered on the shield's dark plate;
-- tools/difficulty_badges.ts), the level written on the plate in the difficulty color. Without a difficulty key (a
-- client color outside its table), "[12]" in the title as before. Unverified: T35.
-- 2026-10-21: smaller (108 before), in the top right corner beside the title.
local BADGE_SIZE, BADGE_FONT, BADGE_FONT_2 = 52, 13, 11 -- font size: one digit, two digits
-- The level is centred in the whole badge (justified), then nudged onto the plate's optical centre: seen in game
-- (2026-10-21), a single digit anchored by its centre sat about 3 pixels left and 2 up of the plate (the outline and
-- the digits' missing descender). x right, y up; per number of digits. Unverified: T49.
local BADGE_NUDGE = { [1] = { 2, -2 }, [2] = { 1, -2 } }
local BADGE_DIR = H.MEDIA .. "difficulty\\"
-- Objectives (2026-10-10): the summary (SUMMARY_LINES at most), then one row per objective of the quest log, a
-- checkbox and a bar with the objective written inside, filled as far as its counter goes (no fill without a
-- counter), greyed and checked once done. The block is at least OBJECTIVES_MIN high (the former 5 text lines) and
-- grows with the rows. Spaced out and larger after the first in-game look (2026-10-10).
-- 2026-10-21: the block's least height is the summary's three lines (70 before: an empty band under short texts).
-- A row (fourth pass): a bullet, or a gold check once done, and the objective's text; under it a thin gold progress
-- line, only for an objective with a counter (before: the text inside a boxed bar, which read like an input field).
local SUMMARY_LINES, LINE_HEIGHT, OBJECTIVES_MIN, SUMMARY_GAP = 3, 15, 45, 8
local OBJECTIVE_ROWS, OBJ_ROW_HEIGHT, OBJ_ROW_GAP, BAR_HEIGHT, CHECK_SIZE = 5, 18, 4, 3, 12
local BAR_COLOR, BAR_DONE_COLOR = { 0.85, 0.65, 0.15 }, { 0.32, 0.32, 0.32 }
local PARTY_ROWS, PARTY_LINE, PARTY_GAP, PARTY_INDENT = 20, 15, 8, 14 -- the group's progress, under the objectives
local HEADER_HEIGHT = 34
-- (The money and level band at the window's bottom, 2026-10-13, was removed on 2026-11-05: asked by the player.)
-- Window frame (2026-10-13): the game's frame, as the world map's (PortraitFrameTemplate: title bar, close button,
-- round portrait at the top left; unverified on Forever), else the tooltip backdrop of before. The portrait shows
-- PORTRAIT_ICON, the icon the user chose for a macro (its file ID, from macros-cache.txt), hidden while it is nil
-- (an icon path also works). The content starts under the
-- title bar, or under the portrait: the header is PORTRAIT_HEADER (no portrait) or PORTRAIT_ICON_HEADER (portrait)
-- taller than without the template. No tabs: the options button, next to the close button, opens the options and
-- goes back to the quest.
local PORTRAIT_ICON = nil -- the macro icon, 134167, was tried: no portrait looks better (2026-10-13)
local PORTRAIT_HEADER, PORTRAIT_ICON_HEADER = -6, 18
-- The gear of the world map's quest log settings (atlas, Retail; unverified on Forever), else the Classic one.
local OPTIONS_ATLAS, OPTIONS_ICON = "questlog-icon-setting", "Interface\\Buttons\\UI-OptionsButton"
-- The speaker in a medallion (2026-10-21, chosen among four layouts: "B"): the addon's bronze and gold ring, the face
-- inside it, round (the game's portrait mask) when the client can mask a texture. The face: a painted portrait of the
-- addon's own speakers (Elise, cropped to her face), else the game's 2D portrait of the NPC's display
-- (SetPortraitTextureFromCreatureDisplayID), else its 3D model framed on the head in the medallion's inner square,
-- else the quest icon. The header is the medallion's height, taller when the title takes two lines.
local MEDALLION, FACE = 72, 58 -- the ring, the face inside it
local MODEL_IN = 42 -- the 3D model's square inside the ring (a model cannot be masked round)
local HEAD_H, HEAD_H_2 = 72, 82 -- the header: one title line, two
local FACE_MASK = "Interface\\CharacterFrame\\TempPortraitAlphaMask"
local MAX_REWARD_ICONS, REWARD_SIZE, REWARD_STEP = 8, 24, 28
local QUEST_ICON = "Interface\\GossipFrame\\AvailableQuestIcon"
-- Lines of Elise (2026-10-11), in the list and, without her portrait, in place of the NPC model: a map for a zone
-- introduction, a holy light for a level-up line (unverified on Forever: icons of the Classic client).
local LINE_ICON = { zone = "Interface\\Icons\\INV_Misc_Map_01", level = "Interface\\Icons\\Spell_Holy_HolyBolt",
  companion = "Interface\\Icons\\Spell_Holy_PrayerOfFortitude", -- companion: a friendship tier (D18, 2026-10-15)
  book = "Interface\\Icons\\INV_Misc_Book_09", gossip = "Interface\\GossipFrame\\GossipGossipIcon" } -- 2026-10-21
-- Portraits of the addon's own speakers, in place of a model (2026-10-15): Elise (D9), painted for the addon
-- (docs/elise/), a 256 x 256 uncompressed TGA like the other media, cropped to the model's frame. Unverified on
-- Forever (T30); a file the client refuses falls back to the icons.
local PORTRAIT = { [1000000] = H.MEDIA .. "elise" }
local PORTRAIT_FACE = { [1000000] = { 0.18, 0.82, 0.08, 0.72 } } -- the face in each painting (texture coordinates)
local BACKDROP = {
  bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
  edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
  tile = true, tileSize = 16, edgeSize = 16,
  insets = { left = 4, right = 4, top = 4, bottom = 4 },
}

local frame -- built on first use
local headerDefs, headerButtons = {}, {} -- the title bar's buttons left of the options gear (RegisterHeaderButton)
local updateHeaderButtons -- their look, lit while on (defined with them)
local loggingOut = false -- PLAYER_LOGOUT seen (also on /reload): the window's open state is no longer recorded

-- CreateFrame with a template, falling back to no template if the client lacks it.
local function create(kind, parent, template)
  if template then
    local ok, f = pcall(CreateFrame, kind, nil, parent, template)
    if ok and f then
      return f, true
    end
  end
  return CreateFrame(kind, nil, parent), false
end

local function button(parent, text, width)
  local b, templated = create("Button", parent, "UIPanelButtonTemplate")
  b:SetSize(width, 22)
  if templated then
    b:SetText(text)
  else
    local label = b:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    label:SetPoint("CENTER")
    label:SetText(text)
  end
  return b
end

-- Round icon button (2026-10-21, ui/style.lua): the addon's ring and a gold glyph, with a tooltip; greyed when
-- disabled.
local ROUND_SIZE, ROUND_GAP = 20, 6 -- 32 before the third pass, 22 before the medallion
local function iconButton(parent, glyph, tooltip)
  return H.Style.RoundButton(parent, glyph, ROUND_SIZE, tooltip)
end

local function moneyString(copper)
  if C_CurrencyInfo and C_CurrencyInfo.GetCoinTextureString then
    local ok, s = pcall(C_CurrencyInfo.GetCoinTextureString, copper)
    if ok and s then
      return s
    end
  end
  local g, s, c = math.floor(copper / 10000), math.floor(copper / 100) % 100, copper % 100
  return string.format("%dg %ds %dc", g, s, c)
end

local function savePosition(f)
  local point, _, relativePoint, x, y = f:GetPoint(1)
  ForeverSpeechDB.playerPos = { point = point, relativePoint = relativePoint, x = x, y = y }
end

local function restorePosition(f)
  local pos = ForeverSpeechDB.playerPos
  f:ClearAllPoints()
  if pos and pos.point then
    f:SetPoint(pos.point, UIParent, pos.relativePoint or pos.point, pos.x or 0, pos.y or 0)
  else
    f:SetPoint("CENTER", UIParent, "CENTER", 300, 0)
  end
end


-- Docked to FlareUI's quest tracker (2026-11-05, setting dockFlare, on by default): while FlareUI's tracker runs, the
-- window stands against it on the side facing the middle of the screen, top edges aligned, never shorter than the
-- tracker. FlareUI places the pair (its edit mode); the window is not dragged. Off, or without FlareUI: where the
-- player left it (playerPos). Unverified on Forever: T66.
local DOCK_GAP = 4

local function dockTarget()
  local Tracker = H.TrackerButtons
  if ForeverSpeechDB.dockFlare == false or not (Tracker and Tracker.FlareUI()) then
    return nil
  end
  local holder = Tracker.FlareHolder()
  if not holder then
    return nil
  end
  return holder, Tracker.FlareOnRight()
end

-- Places the window, docked or free; true when its place changed.
local function place(f)
  local holder, right = dockTarget()
  local side = holder and (right and "right" or "left") or nil
  if rawget(f, "placed") and side == rawget(f, "docked") and holder == rawget(f, "dockedTo") then
    return false
  end
  f.placed, f.docked, f.dockedTo = true, side, holder
  f:ClearAllPoints()
  if side == "right" then -- the tracker on the right half of the screen: the window on its left
    f:SetPoint("TOPRIGHT", holder, "TOPLEFT", -DOCK_GAP, 0)
  elseif side == "left" then
    f:SetPoint("TOPLEFT", holder, "TOPRIGHT", DOCK_GAP, 0)
  else
    restorePosition(f)
  end
  H.Trace("frame: docked %s", side or "no")
  return true
end

local function rewardIcon(parent, i)
  local b = CreateFrame("Button", nil, parent)
  b:SetSize(REWARD_SIZE, REWARD_SIZE)
  b:SetPoint("LEFT", parent, "LEFT", (i - 1) * REWARD_STEP, 0)
  b.icon = b:CreateTexture(nil, "ARTWORK")
  b.icon:SetAllPoints()
  b.count = b:CreateFontString(nil, "OVERLAY", "NumberFontNormal")
  b.count:SetPoint("BOTTOMRIGHT", -1, 1)
  b:SetScript("OnEnter", function(self)
    if not (GameTooltip and self.item) then
      return
    end
    GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
    if self.item.itemID and GameTooltip.SetItemByID then
      GameTooltip:SetItemByID(self.item.itemID)
    else
      GameTooltip:SetText(self.item.name or "?")
    end
    if self.choice then
      GameTooltip:AddLine(L.CHOICES, 0.6, 0.6, 0.6)
    end
    GameTooltip:Show()
  end)
  b:SetScript("OnLeave", function()
    if GameTooltip then
      GameTooltip:Hide()
    end
  end)
  return b
end

-- One objective: a bullet (a gold check once done), its text, and a thin progress line under it when it has a counter.
local function objectiveRow(parent)
  local row = CreateFrame("Frame", nil, parent)
  row:SetHeight(OBJ_ROW_HEIGHT)
  row.bullet = row:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
  row.bullet:SetPoint("TOPLEFT", 2, -1)
  row.bullet:SetText("•")
  row.box = row:CreateTexture(nil, "ARTWORK") -- kept for the check's place; never drawn
  row.box:SetSize(CHECK_SIZE, CHECK_SIZE)
  row.box:SetPoint("TOPLEFT", -1, 1)
  row.check = row:CreateTexture(nil, "OVERLAY")
  row.check:SetAllPoints(row.box)
  if not H.Style.SetAtlas(row.check, "checkmark-minimal") then
    row.check:SetTexture("Interface\\Buttons\\UI-CheckBox-Check")
  end
  row.label = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  row.label:SetPoint("TOPLEFT", CHECK_SIZE + 2, 0)
  row.label:SetPoint("RIGHT", row, "RIGHT", 0, 0)
  row.label:SetJustifyH("LEFT")
  row.label:SetWordWrap(false)
  row.bar = CreateFrame("StatusBar", nil, row)
  row.bar:SetPoint("BOTTOMLEFT", row, "BOTTOMLEFT", CHECK_SIZE + 2, 1)
  row.bar:SetPoint("RIGHT", row, "RIGHT", 0, 0)
  row.bar:SetHeight(BAR_HEIGHT)
  row.bar:SetMinMaxValues(0, 1)
  row.bar:SetStatusBarTexture("Interface\\TargetingFrame\\UI-StatusBar")
  local bg = row.bar:CreateTexture(nil, "BACKGROUND")
  bg:SetAllPoints()
  bg:SetColorTexture(1, 1, 1, 0.08)
  row:Hide()
  return row
end


-- One line of the group's progress: a member (the game's colour), or one of their objectives under them (a bullet, a
-- gold check once done). Without the line types, every line flush left, a check before the done ones.
local function partyRow(parent)
  local row = CreateFrame("Frame", nil, parent)
  row:SetHeight(PARTY_LINE)
  row.check = row:CreateTexture(nil, "OVERLAY")
  row.check:SetSize(CHECK_SIZE - 2, CHECK_SIZE - 2)
  if not H.Style.SetAtlas(row.check, "checkmark-minimal") then
    row.check:SetTexture("Interface\\Buttons\\UI-CheckBox-Check")
  end
  row.bullet = row:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
  row.bullet:SetPoint("TOPLEFT", PARTY_INDENT + 1, -1)
  row.bullet:SetText("•")
  row.label = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  row.label:SetJustifyH("LEFT")
  row.label:SetWordWrap(false)
  row:Hide()
  return row
end

local function setPartyRow(row, line)
  local indent = line.member == false and PARTY_INDENT or 0
  row.check:ClearAllPoints()
  row.check:SetPoint("TOPLEFT", indent - 1, 0)
  row.check:SetShown(line.done)
  row.bullet:SetShown(line.member == false and not line.done)
  row.label:ClearAllPoints()
  row.label:SetPoint("TOPLEFT", line.member and 0 or indent + CHECK_SIZE, 0)
  row.label:SetPoint("RIGHT", row, "RIGHT", 0, 0)
  row.label:SetText(line.text)
  if line.done then
    row.label:SetTextColor(0.6, 0.6, 0.6)
  else
    row.label:SetTextColor(line.r, line.g, line.b)
  end
  row:Show()
end

-- What the group's lines say, to draw them again only when it changed.
local function partySignature(lines)
  local parts = {}
  for i, line in ipairs(lines or {}) do
    parts[i] = line.text .. (line.done and "+" or "-")
  end
  return table.concat(parts, "\n")
end

local function backdrop(f, templated, alpha)
  if templated and f.SetBackdrop then
    f:SetBackdrop(BACKDROP)
    f:SetBackdropColor(0.05, 0.05, 0.08, alpha)
  else
    local bg = f:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints()
    bg:SetColorTexture(0.05, 0.05, 0.08, alpha)
  end
end

-- Head and bust framing (setting modelZoom, /fs zoom). SetPortraitZoom is unverified on Forever:
-- without it the model stays full body. Applied again once the model is loaded, since loading a
-- model can reset the camera.
local function applyZoom(model)
  local ok = pcall(model.SetPortraitZoom, model, tonumber(ForeverSpeechDB.modelZoom) or 0)
  return ok
end

-- Quest tab: model, title, giver, status, Play / Next / Stop, quest text, objectives, rewards.
-- A section title (2026-10-21): small, muted gold, the game's quest title face. No divider after it (asked after a look
-- in game: the friezes beside the titles were one ornament too many).
local function sectionTitle(qp, text)
  local fs = qp:CreateFontString(nil, "OVERLAY", "GameFontNormal")
  fs:SetText(text)
  H.Style.Header(fs, SECTION_TITLE_SIZE)
  return fs
end

-- A texture masked round by the game's portrait mask, when the client can mask textures (true), else left square.
local function maskRound(parent, tex)
  if not parent.CreateMaskTexture then
    return false
  end
  return pcall(function()
    local mask = parent:CreateMaskTexture()
    mask:SetTexture(FACE_MASK, "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
    mask:SetAllPoints(tex)
    tex:AddMaskTexture(mask)
  end) == true
end

local function buildQuestPanel(f, qp)
  local head = CreateFrame("Frame", nil, qp)
  head:SetPoint("TOPLEFT", qp, "TOPLEFT", PAD, -PAD_TOP)
  head:SetPoint("RIGHT", qp, "RIGHT", -PAD, 0)
  head:SetHeight(HEAD_H)
  f.head, f.headHeight = head, HEAD_H

  -- the medallion: ring, then the face (or the model, or the icon) inside it
  local med = CreateFrame("Frame", nil, head)
  med:SetSize(MEDALLION, MEDALLION)
  med:SetPoint("TOPLEFT", head, "TOPLEFT", 0, 0)
  local ring = med:CreateTexture(nil, "BACKGROUND")
  ring:SetAllPoints()
  ring:SetTexture(H.Style.RING)
  H.Style.FlareTint(ring) -- FlareUI's bronze while it runs
  f.portrait = med:CreateTexture(nil, "ARTWORK")
  f.portrait:SetSize(FACE, FACE)
  f.portrait:SetPoint("CENTER")
  f.faceRound = maskRound(med, f.portrait)
  if not f.faceRound then -- square: kept inside the ring
    f.portrait:SetSize(MODEL_IN, MODEL_IN)
  end
  f.portrait:Hide()
  f.model = CreateFrame("PlayerModel", nil, med)
  f.model:SetSize(MODEL_IN, MODEL_IN)
  f.model:SetPoint("CENTER")
  pcall(f.model.SetScript, f.model, "OnModelLoaded", applyZoom)
  f.model:Hide()
  f.icon = med:CreateTexture(nil, "ARTWORK")
  f.icon:SetSize(f.faceRound and FACE or MODEL_IN, f.faceRound and FACE or MODEL_IN)
  f.icon:SetPoint("CENTER")
  f.icon:SetTexture(QUEST_ICON)
  if f.faceRound then
    maskRound(med, f.icon)
  end

  -- the level badge in the top right corner
  f.badge = CreateFrame("Frame", nil, head)
  f.badge:SetSize(BADGE_SIZE, BADGE_SIZE)
  f.badge:SetPoint("TOPRIGHT", head, "TOPRIGHT", 6, 6) -- the shield's art has a margin
  f.badge.shield = f.badge:CreateTexture(nil, "ARTWORK")
  f.badge.shield:SetAllPoints()
  f.badge.level = f.badge:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
  f.badge.level:SetJustifyH("CENTER")
  f.badge.level:SetJustifyV("MIDDLE")
  f.badge:Hide()

  -- beside the medallion: the title (two lines at most), then "NPC · status", then the controls
  f.title = head:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
  f.title.fsFontKind = "title" -- FlareUI's title face while it runs
  f.title:SetPoint("TOPLEFT", med, "TOPRIGHT", 12, -3)
  f.title:SetPoint("RIGHT", head, "RIGHT", -(BADGE_SIZE + 2), 0)
  f.title:SetJustifyH("LEFT")
  pcall(f.title.SetMaxLines, f.title, 2)

  f.giver = head:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
  f.giver:SetPoint("TOPLEFT", f.title, "BOTTOMLEFT", 0, -3)
  f.giver:SetJustifyH("LEFT")
  f.giver:SetTextColor(SOFT[1], SOFT[2], SOFT[3])
  f.dot = head:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
  f.dot:SetPoint("LEFT", f.giver, "RIGHT", 5, 0)
  f.dot:SetText("·")
  f.status = head:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
  f.status:SetPoint("LEFT", f.dot, "RIGHT", 5, 0)
  f.status:SetPoint("RIGHT", f.title, "RIGHT", 0, 0)
  f.status:SetJustifyH("LEFT")
  f.status:SetWordWrap(false)

  -- quest text under the model; the objectives title follows it (setQuestText anchors it)
  f.visual = head -- what the text, else the objectives, hang under
  f.questText = qp:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  f.questText:SetPoint("TOPLEFT", head, "BOTTOMLEFT", 0, -TEXT_GAP)
  f.questText:SetWidth(WIDTH - 2 * PAD)
  f.questText:SetJustifyH("LEFT")
  f.questText:SetJustifyV("TOP")
  f.questText:SetTextColor(TEXT_COLOR[1], TEXT_COLOR[2], TEXT_COLOR[3])
  pcall(f.questText.SetSpacing, f.questText, TEXT_SPACING)
  pcall(f.questText.SetMaxLines, f.questText, TEXT_MAX_LINES)
  f.questText:Hide()
  f.textHeight = 0

  local objHeader = sectionTitle(qp, L.OBJECTIVES)
  objHeader:SetPoint("TOPLEFT", head, "BOTTOMLEFT", 0, -SECTION)
  f.objHeader = objHeader
  -- objectives block: summary, then one row per objective (setObjectives); the rewards follow it
  f.objectivesArea = CreateFrame("Frame", nil, qp)
  f.objectivesArea:SetPoint("TOPLEFT", objHeader, "BOTTOMLEFT", 0, -TITLE_GAP)
  f.objectivesArea:SetSize(WIDTH - 2 * PAD, OBJECTIVES_MIN)
  f.objectivesHeight = OBJECTIVES_MIN
  f.objectives = f.objectivesArea:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
  f.objectives:SetPoint("TOPLEFT", 0, 0)
  f.objectives:SetWidth(WIDTH - 2 * PAD)
  f.objectives:SetJustifyH("LEFT")
  f.objectives:SetJustifyV("TOP")
  f.objectives:SetTextColor(SOFT[1], SOFT[2], SOFT[3])
  pcall(f.objectives.SetMaxLines, f.objectives, SUMMARY_LINES) -- ellipsis on the last line
  f.objectiveRows = {}
  for i = 1, OBJECTIVE_ROWS do
    f.objectiveRows[i] = objectiveRow(f.objectivesArea)
  end
  -- the group's progress (2026-11-05): a small title, then the game's lines (members, their objectives)
  f.partyHeader = f.objectivesArea:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
  f.partyHeader:SetText(L.PARTY_PROGRESS)
  H.Style.Header(f.partyHeader, SECTION_TITLE_SIZE - 1)
  f.partyHeader:Hide()
  f.partyRows = {}
  for i = 1, PARTY_ROWS do
    f.partyRows[i] = partyRow(f.objectivesArea)
  end

  -- Play / Next / Stop, small, under "NPC · status"; the list toggle joins them (buildListToggle)
  local play = iconButton(f.head, "play", L.TOOLTIP_PLAY_FROM_START)
  play:SetPoint("TOPLEFT", f.giver, "BOTTOMLEFT", 2, -7)
  local nextButton = iconButton(f.head, "next", L.TOOLTIP_NEXT)
  nextButton:SetPoint("LEFT", play, "RIGHT", ROUND_GAP, 0)
  local stop = iconButton(f.head, "stop", L.TOOLTIP_STOP)
  stop:SetPoint("LEFT", nextButton, "RIGHT", ROUND_GAP, 0)
  play:SetScript("OnClick", function()
    if frame.line then
      H.Player.PlayLineNow(frame.line, frame.lineID)
    elseif frame.questID then
      H.Player.PlayNow(frame.questID, frame.part)
    end
  end)
  nextButton:SetScript("OnClick", function()
    H.Player.Next()
  end)
  stop:SetScript("OnClick", function()
    H.Player.Stop()
  end)
  f.playButton, f.nextButton, f.stopButton = play, nextButton, stop

  -- rewards right under the objectives: money and experience on the title's line, at its right end (fourth pass), the
  -- items' icons under it only when there are some
  local rewardHeader = sectionTitle(qp, L.REWARDS)
  rewardHeader:SetPoint("TOPLEFT", f.objectivesArea, "BOTTOMLEFT", 0, -SECTION)
  f.rewardHeader = rewardHeader
  local line = CreateFrame("Frame", nil, qp)
  line:SetPoint("TOPLEFT", rewardHeader, "TOPLEFT", 0, 0)
  line:SetPoint("BOTTOMRIGHT", rewardHeader, "BOTTOMRIGHT", 0, 0)
  line:SetPoint("RIGHT", qp, "RIGHT", -PAD, 0)
  f.rewardLine = line
  f.rewardText = line:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  f.rewardText:SetPoint("RIGHT", line, "RIGHT", 0, 0)
  f.rewardText:SetJustifyH("RIGHT")
  f.rewardText:SetTextColor(SOFT[1], SOFT[2], SOFT[3])
  local rewards = CreateFrame("Frame", nil, qp)
  rewards:SetHeight(REWARD_SIZE)
  rewards:SetPoint("TOPLEFT", rewardHeader, "BOTTOMLEFT", 0, -TITLE_GAP)
  rewards:SetPoint("RIGHT", qp, "RIGHT", -PAD, 0)
  rewards:Hide()
  f.rewards = rewards
  f.rewardIcons = {}
  for i = 1, MAX_REWARD_ICONS do
    f.rewardIcons[i] = rewardIcon(rewards, i)
  end
end

-- Play list panel (history, current, queue) ------------------------------------------
-- Part of the window, as the quest log is part of the world map (2026-10-13): shown, the window widens to the right
-- to hold it (and grows taller if its rows need it); hidden, the window is back to its own width.

local LIST_WIDTH, ROW_HEIGHT = 230, 20
local ROW_HIGHLIGHT = "Interface\\QuestFrame\\UI-QuestTitleHighlight"
local REMOVE_ICON = "Interface\\Buttons\\UI-GroupLoot-Pass-Up"
local LIST_LEFT, LIST_TOP, LIST_MARGIN = WIDTH - 6, 30, 8 -- the panel's box inside the window
local MAX_ROWS = 19 -- the list cap (Player LIST_MAX); the window grows taller if needed

local function listRow(panel, i)
  local row = CreateFrame("Button", nil, panel)
  row:SetHeight(ROW_HEIGHT)
  row:SetPoint("TOPLEFT", panel, "TOPLEFT", 8, -30 - (i - 1) * ROW_HEIGHT)
  row:SetPoint("RIGHT", panel, "RIGHT", -8, 0)
  -- the quest log's title highlight (2026-10-21): soft on hover, gold on the row the window shows
  local hl = row:CreateTexture(nil, "HIGHLIGHT")
  hl:SetAllPoints()
  hl:SetTexture(ROW_HIGHLIGHT)
  hl:SetBlendMode("ADD")
  hl:SetAlpha(0.35)
  row.current = row:CreateTexture(nil, "BACKGROUND")
  row.current:SetAllPoints()
  row.current:SetTexture(ROW_HIGHLIGHT)
  row.current:SetBlendMode("ADD")
  row.current:SetVertexColor(1, 0.82, 0)
  row.current:SetAlpha(0.6)
  row.current:Hide()
  row.icon = row:CreateTexture(nil, "ARTWORK")
  row.icon:SetSize(16, 16)
  row.icon:SetPoint("LEFT", 0, 0)
  row.text = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  row.text:SetPoint("LEFT", row.icon, "RIGHT", 4, 0)
  row.text:SetPoint("RIGHT", row, "RIGHT", -18, 0)
  row.text:SetJustifyH("LEFT")
  row.text:SetWordWrap(false)
  row.line = false
  row.remove = CreateFrame("Button", nil, row)
  row.remove:SetSize(14, 14)
  row.remove:SetPoint("RIGHT", 0, 0)
  row.remove:SetNormalTexture(REMOVE_ICON) -- the game's red cross (2026-10-21; before: a "×" written in red)
  row.remove:SetHighlightTexture(REMOVE_ICON, "ADD")
  row.remove:SetScript("OnClick", function()
    if row.line then
      H.Player.RemoveLine(row.line, row.lineID)
    elseif row.questID then
      H.Player.Remove(row.questID, row.part)
    end
  end)
  row:SetScript("OnClick", function(self)
    if self.line then
      PlayerFrame.ShowLine(self.line, self.lineID)
    elseif self.questID then
      PlayerFrame.ShowQuest(self.questID, self.part)
    end
  end)
  row:SetScript("OnDoubleClick", function(self)
    if self.line then
      H.Player.PlayLineNow(self.line, self.lineID)
    elseif self.questID then
      H.Player.PlayNow(self.questID, self.part)
    end
  end)
  row:SetScript("OnEnter", function(self)
    if (self.questID or self.line) and GameTooltip then
      GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
      GameTooltip:SetText(self.line == "zone" and L.PART_ZONE or self.line == "level" and L.PART_LEVEL
        or self.line == "companion" and L.PART_COMPANION
        or self.line == "book" and L.PART_BOOK or self.line == "gossip" and L.PART_GOSSIP
        or self.part == "complete" and L.PART_COMPLETE or L.PART_DETAIL)
      GameTooltip:AddLine(L.PLAYLIST_HINT, 0.8, 0.8, 0.8)
      GameTooltip:Show()
    end
  end)
  row:SetScript("OnLeave", function()
    if GameTooltip then
      GameTooltip:Hide()
    end
  end)
  return row
end

-- The right-hand box of the play list. The game's inset frame (2026-10-21: its sunken border and dark marble, as the
-- world map's quest log), else the tooltip backdrop of before; its title in the quest title face.
local function sideBox(f, text)
  local panel, inset = create("Frame", f, "InsetFrameTemplate")
  if not inset then
    local templated
    panel, templated = create("Frame", f, "BackdropTemplate")
    backdrop(panel, templated, 0.9)
  end
  H.Style.FlareInset(panel)
  panel:SetWidth(LIST_WIDTH)
  panel:SetPoint("TOPLEFT", f, "TOPLEFT", LIST_LEFT, -(LIST_TOP + f.headerExtra))
  panel:SetPoint("BOTTOMLEFT", f, "BOTTOMLEFT", LIST_LEFT, LIST_MARGIN)
  panel.title = panel:CreateFontString(nil, "OVERLAY", "GameFontNormal")
  panel.title:SetPoint("TOPLEFT", 10, -10)
  panel.title:SetPoint("RIGHT", panel, "RIGHT", -10, 0)
  panel.title:SetJustifyH("LEFT")
  panel.title:SetText(text or "")
  H.Style.Header(panel.title, SECTION_TITLE_SIZE)
  return panel
end

local function buildListPanel(f)
  local panel = sideBox(f, L.PLAYLIST)
  panel.reset = button(panel, L.PLAYLIST_RESET, 60)
  panel.reset:SetHeight(18)
  panel.reset:SetPoint("TOPRIGHT", -8, -7)
  panel.reset:SetScript("OnClick", function()
    H.Player.Reset()
  end)
  panel.empty = panel:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
  panel.empty:SetPoint("TOPLEFT", 10, -34)
  panel.empty:SetPoint("RIGHT", panel, "RIGHT", -10, 0)
  panel.empty:SetJustifyH("LEFT")
  panel.empty:SetText(L.PLAYLIST_EMPTY)
  panel.rows = {}
  for i = 1, MAX_ROWS do
    panel.rows[i] = listRow(panel, i)
  end
  f.listPanel = panel
end

-- The quest tab's height, estimated: portrait, text, objectives, rewards (title, then the icons' row with items).
local function questHeight()
  local h = PAD_TOP + frame.headHeight + (frame.textHeight > 0 and frame.textHeight + TEXT_GAP or 0)
    + SECTION + TITLE_H + TITLE_GAP + frame.objectivesHeight + PAD_TOP
  if frame.rewardHeader:IsShown() then
    h = h + SECTION + TITLE_H + ((rawget(frame, "rewardItems") or 0) > 0 and TITLE_GAP + REWARD_SIZE or 0)
  end
  return h
end

-- (2026-10-21: the quest tab is the window's only tab; the companions, its other panel, have their own window)
local function tabHeight()
  -- the quest panel starts under the title bar (HEADER_HEIGHT, forgotten by the third pass: 34 pixels short)
  return frame.headerExtra + HEADER_HEIGHT + (rawget(frame, "questFit") or questHeight())
end

-- Sizes the window for its tab and the list (rows: the list rows shown, nil when hidden). The top-left corner stays in
-- place (2026-10-13): the list opens and closes on the right; widened past the right screen edge, the window moves
-- left to stay on screen.
local function layout(rows)
  -- never shorter than its side tabs need (2026-10-21: the compact window let the emotes overlap)
  -- and docked, never shorter than FlareUI's tracker (2026-11-05)
  local width, height = WIDTH, math.max(tabHeight(), H.SideTabs and H.SideTabs.MinHeight("main") or 0,
    rawget(frame, "dockHeight") or 0)
  if rows then
    width = LIST_LEFT + LIST_WIDTH + LIST_MARGIN
    height = math.max(height, frame.headerExtra + LIST_TOP + 40 + rows * ROW_HEIGHT + LIST_MARGIN)
  end
  local changed = width ~= frame.layoutWidth or height ~= frame.layoutHeight
  frame.layoutWidth, frame.layoutHeight = width, height
  -- the corner before resizing: the window may be anchored by another point (its centre, by default), which a new
  -- size would move
  local left, top = frame:GetLeft(), frame:GetTop()
  frame:SetWidth(width)
  frame:SetHeight(height)
  if not (changed and left and top) or rawget(frame, "docked") then -- docked: it grows away from FlareUI's tracker
    return
  end
  local screen = UIParent:GetRight()
  if screen and left + width > screen then
    left = math.max(0, screen - width)
  end
  frame:ClearAllPoints()
  frame:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", left, top)
  savePosition(frame)
end

-- The list toggle (2026-10-21): a small round button of the addon's set with the list glyph, in the controls row after
-- Play / Next / Stop and a thin rule; full gold while the list is shown, quieter while it is closed. Before: a copy of
-- the world map's own toggle (an arrow and a quest mark) at the bottom right, judged too heavy.
local TOGGLE_SIZE = ROUND_SIZE

local function setToggleLook(b, open)
  if rawget(b, "bronze") then -- FlareUI's theme: lighter bronze while the list is shown
    b.lit = open
    H.Style.RefreshButton(b)
    return
  end
  b.glyph:SetVertexColor(1, 1, 1, open and 1 or 0.7)
end

local function buildListToggle(f)
  local qp, stop = f.head, f.stopButton
  -- a thin rule between the playback buttons and the list toggle
  local rule = qp:CreateTexture(nil, "ARTWORK")
  rule:SetColorTexture(0.55, 0.45, 0.25, 0.6)
  H.Style.FlareLine(rule)
  rule:SetSize(1, 14)
  rule:SetPoint("LEFT", stop, "RIGHT", 8, 0)
  local b = H.Style.RoundButton(qp, "list", TOGGLE_SIZE, function()
    return ForeverSpeechDB.showList and L.LIST_CLOSE or L.LIST_OPEN
  end)
  b:SetPoint("LEFT", rule, "RIGHT", 8, 0)
  b:SetScript("OnClick", function(self)
    ForeverSpeechDB.showList = not ForeverSpeechDB.showList
    PlayerFrame.UpdateList()
    if GameTooltip and GameTooltip:IsOwned(self) then
      self:GetScript("OnEnter")(self)
    end
  end)
  f.listToggle = b
end

function PlayerFrame.ListToggle()
  return frame and frame.listToggle
end

function PlayerFrame.ListPanel()
  return frame and frame.listPanel
end

-- Entries shown, in play list order: played (grey), playing (green), not played yet (yellow).
function PlayerFrame.ListEntries()
  return H.Player.List()
end

function PlayerFrame.UpdateList()
  if not frame then
    return
  end
  local panel = frame.listPanel
  setToggleLook(frame.listToggle, ForeverSpeechDB.showList)
  if not ForeverSpeechDB.showList then
    panel:Hide()
    layout(nil)
    return
  end
  local entries = PlayerFrame.ListEntries()
  layout(math.min(#entries, MAX_ROWS))
  panel:Show()
  panel.empty:SetShown(#entries == 0)
  for i, row in ipairs(panel.rows) do
    local entry = entries[i]
    if entry then
      local title
      local icon = entry.line and LINE_ICON[entry.line]
      if entry.line then -- a line of Elise: its name (zone, level) and its icon, whatever its state
        title = (H.Index.Line(entry.line, entry.lineID) or {}).name or ("#" .. entry.lineID)
      elseif entry.test then
        title = L.TEST_SOUND
      else
        title = PART_MARK[entry.part or "detail"] .. (H.QuestData.Title(entry.questID) or ("#" .. entry.questID))
      end
      row.questID, row.part, row.line, row.lineID = entry.questID, entry.part, entry.line or false, entry.lineID
      if entry.state == "done" then
        row.icon:SetTexture(icon or nil)
        row.icon:SetVertexColor(0.55, 0.55, 0.55)
        row.text:SetText("|cff888888" .. title .. "|r")
      elseif entry.state == "playing" then
        row.icon:SetTexture(icon or H.Style.Glyph("play"))
        row.icon:SetVertexColor(icon and 1 or 0.55, 1, icon and 1 or 0.55)
        row.text:SetText("|cff40ff40" .. title .. "|r")
      else
        row.icon:SetTexture(icon or H.Style.Glyph("play"))
        row.icon:SetVertexColor(1, 1, 1)
        row.text:SetText("|cffffd200" .. entry.position .. ".|r " .. title)
      end
      row.remove:SetShown(entry.state == "queued" and (entry.questID ~= nil or entry.line ~= nil))
      local shown = (entry.line and frame.line == entry.line and frame.lineID == entry.lineID)
        or (frame.questID and entry.questID == frame.questID and (entry.part or "detail") == (frame.part or "detail"))
      row.current:SetShown(shown and true or false) -- before 2026-10-21: a "<" after the title
      row:Show()
    else
      row.questID, row.part, row.line, row.lineID = nil, nil, false, nil
      row:Hide()
    end
  end
end

-- Debug bar (under the window, only in debug mode): test step markers, screenshot, reload,
-- so an in-game test can be run without typing commands.
local function markLabel()
  return string.format(L.DEBUG_MARK, (ForeverSpeechDB.debugStep or 0) + 1)
end

local function buildDebugBar(f)
  local bar, templated = create("Frame", f, "BackdropTemplate")
  bar:SetHeight(32)
  bar:SetPoint("TOPLEFT", f, "BOTTOMLEFT", 0, 2)
  bar:SetPoint("TOPRIGHT", f, "BOTTOMRIGHT", 0, 2)
  backdrop(bar, templated, 0.9)
  local label = bar:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
  label:SetPoint("LEFT", 12, 0)
  label:SetText(L.DEBUG_BAR)
  local mark = button(bar, markLabel(), 110)
  mark:SetPoint("LEFT", label, "RIGHT", 10, 0)
  mark:SetScript("OnClick", function(self)
    ForeverSpeechDB.debugStep = (ForeverSpeechDB.debugStep or 0) + 1
    H.Trace("=== MARK step %s ===", ForeverSpeechDB.debugStep)
    self:SetText(markLabel())
  end)
  local shot = button(bar, L.DEBUG_SHOT, 90)
  shot:SetPoint("LEFT", mark, "RIGHT", 6, 0)
  shot:SetScript("OnClick", function()
    C_Timer.After(0.3, function()
      local ok, err = pcall(Screenshot)
      H.Trace("debug: screenshot ok=%s %s", ok, err)
    end)
  end)
  local reload = button(bar, L.DEBUG_RELOAD, 90)
  reload:SetPoint("LEFT", shot, "RIGHT", 6, 0)
  reload:SetScript("OnClick", function()
    H.Trace("debug: reload")
    ReloadUI()
  end)
  bar.mark, bar.reload = mark, reload
  f.debugBar = bar
end

function PlayerFrame.DebugBar()
  return frame and frame.debugBar
end

function PlayerFrame.UpdateDebugBar()
  if not frame then
    return
  end
  frame.debugBar:SetShown(ForeverSpeechDB.debug and true or false)
  frame.debugBar.mark:SetText(markLabel())
end

-- Window -----------------------------------------------------------------------------

-- Once the client has laid the quest tab out, its height is measured from the window's top to the last block's bottom
-- (rewards' icons, else the rewards' title, else the objectives), plus the bottom margin: font metrics of the client
-- differ from the estimate (2026-10-21: the rewards ran over the footer). Without geometry (tests), the estimate stays.
local function fitQuestTab()
  if not (frame and frame.tab == "quest" and frame:IsShown()) then
    return
  end
  local last = (frame.rewards:IsShown() and frame.rewards) or (frame.rewardHeader:IsShown() and frame.rewardLine)
    or frame.objectivesArea
  local top, bottom = frame.questPanel:GetTop(), last:GetBottom()
  if not (top and bottom) then
    return
  end
  local measured = math.ceil(top - bottom) + PAD_TOP
  if math.abs(measured - (rawget(frame, "questFit") or questHeight())) > 1 then
    frame.questFit = measured
    PlayerFrame.UpdateList()
  end
end

function PlayerFrame.SelectTab(name)
  if not frame then
    return
  end
  if name == "options" then -- its own window since 2026-10-15
    H.Options.Open()
    return
  end
  frame.tab = name
  frame.questFit = nil -- the content may have changed: estimate, then measure (fitQuestTab)
  PlayerFrame.UpdateList() -- sizes the window for this tab
  if name == "quest" then
    C_Timer.After(0, fitQuestTab)
  end

  frame.questPanel:SetShown(name == "quest")
  if H.SideTabs then -- a side tab may be lit by the tab shown
    H.SideTabs.Update()
  end
  updateHeaderButtons()
end

-- The tab shown while the window is open ("quest"), else nil.
function PlayerFrame.Tab()
  return frame and frame:IsShown() and frame.tab or nil
end

-- The portrait frame's title and portrait, through its mixin when it has one (Retail), else its regions. Without
-- an icon, the portrait is hidden, with the border made for no portrait (ButtonFrameTemplate_HidePortrait, else by
-- hand).
local function dressPortrait(f, text)
  text = text or H.TITLE
  if f.SetTitle then
    pcall(f.SetTitle, f, text)
  else
    local title = (f.TitleContainer and f.TitleContainer.TitleText) or f.TitleText
    if title then
      title:SetText(text)
    end
  end
  if PORTRAIT_ICON then
    if f.SetPortraitToAsset then
      pcall(f.SetPortraitToAsset, f, PORTRAIT_ICON)
      return
    end
    local portrait = (f.PortraitContainer and f.PortraitContainer.portrait) or f.portrait
    if portrait and _G.SetPortraitToTexture then
      _G.SetPortraitToTexture(portrait, PORTRAIT_ICON)
    elseif portrait then
      portrait:SetTexture(PORTRAIT_ICON)
    end
    return
  end
  if _G.ButtonFrameTemplate_HidePortrait and pcall(_G.ButtonFrameTemplate_HidePortrait, f) then
    return
  end
  local portrait = f.PortraitContainer or f.portrait
  if portrait then
    portrait:Hide()
  end
  if _G.NineSliceUtil and f.NineSlice then
    pcall(_G.NineSliceUtil.ApplyLayoutByName, f.NineSlice, "ButtonFrameTemplateNoPortrait")
  end
end

local function optionsTooltip(b)
  if GameTooltip then
    GameTooltip:SetOwner(b, "ANCHOR_TOP")
    GameTooltip:SetText(H.Options.IsShown() and L.OPTIONS_CLOSE or L.OPTIONS_OPEN)
    GameTooltip:Show()
  end
end

-- The options button: opens the options; again, back to the quest. Lit while the options are shown.
local function buildOptionsButton(f, close)
  local b = CreateFrame("Button", nil, f)
  b:SetSize(20, 20)
  if close then
    b:SetPoint("RIGHT", close, "LEFT", -2, 0)
  else
    b:SetPoint("TOPRIGHT", f, "TOPRIGHT", -28, -6)
  end
  -- above the frame's border and title bar, as its close button (the portrait frame draws them high, ~500)
  local closeLevel = close and close.GetFrameLevel and close:GetFrameLevel()
  b:SetFrameLevel(closeLevel or (f:GetFrameLevel() or 0) + 5)
  b.tex = b:CreateTexture(nil, "ARTWORK")
  b.tex:SetAllPoints()
  local textures = _G.C_Texture
  local atlas = textures and textures.GetAtlasInfo and textures.GetAtlasInfo(OPTIONS_ATLAS)
  if atlas and b.tex.SetAtlas then
    b.tex:SetAtlas(OPTIONS_ATLAS)
  else
    b.tex:SetTexture(OPTIONS_ICON)
  end
  -- FlareUI's theme: its own gear, in its struck bronze, lighter when pointed at or while the options are shown
  b.bronze = H.Style.FlareIcon(b.tex, false, H.Style.FLARE_ICONS.settings)
  if b.bronze then
    b.tex:ClearAllPoints()
    b.tex:SetSize(14, 14)
    b.tex:SetPoint("CENTER")
  end
  local level = b:GetFrameLevel()
  H.Trace("frame: options button atlas=%s close=%s level=%s", atlas ~= nil, close ~= nil, level)
  if not b.bronze then
    local hl = b:CreateTexture(nil, "HIGHLIGHT")
    hl:SetAllPoints()
    hl:SetTexture("Interface\\Buttons\\UI-Common-MouseHilight")
    hl:SetBlendMode("ADD")
  end
  b:SetScript("OnClick", function(self)
    H.Options.Toggle()
    if GameTooltip and GameTooltip:IsOwned(self) then
      optionsTooltip(self)
    end
  end)
  b:SetScript("OnEnter", function(self)
    if rawget(self, "bronze") then
      H.Style.FlareIcon(self.tex, true)
    end
    optionsTooltip(self)
  end)
  b:SetScript("OnLeave", function(self)
    if rawget(self, "bronze") then
      H.Style.FlareIcon(self.tex, H.Options.IsShown())
    end
    if GameTooltip then
      GameTooltip:Hide()
    end
  end)
  function b.SetLit(self, lit)
    if rawget(self, "bronze") then
      H.Style.FlareIcon(self.tex, lit)
      return
    end
    self.tex:SetVertexColor(lit and 1 or 0.8, lit and 0.82 or 0.8, lit and 0 or 0.8)
  end
  f.optionsButton = b
end

-- Buttons in the title bar, left of the options gear (2026-10-21; the companions' side tab moved here): def = { key,
-- icon, tooltip(fn(tooltip)), isOn(fn), onClick(fn) }; registered at load time, built with the window, lit while on.
function updateHeaderButtons()
  for _, b in ipairs(headerButtons) do
    local on = b.def.isOn and b.def.isOn() or false
    if rawget(b, "bronze") then -- FlareUI's own icon in its struck bronze, lighter while on
      H.Style.FlareIcon(b.icon, on)
      b.checked:Hide()
    else
      b.icon:SetAlpha(on and 1 or 0.8)
      b.icon:SetDesaturated(false)
      b.checked:SetShown(on)
    end
  end
end

local function buildHeaderButton(f, def)
  local b = CreateFrame("Button", nil, f)
  b:SetSize(18, 18)
  local previous = headerButtons[#headerButtons] or f.optionsButton
  b:SetPoint("RIGHT", previous, "LEFT", -6, 0)
  b:SetFrameLevel(previous:GetFrameLevel() or ((f:GetFrameLevel() or 0) + 5))
  b.def = def
  b.icon = b:CreateTexture(nil, "ARTWORK")
  b.icon:SetAllPoints()
  b.icon:SetTexture(def.icon)
  -- FlareUI's theme: its own icon (def.flareIcon, a key of Style.FLARE_ICONS) in its struck bronze
  local flareIcon = def.flareIcon and H.Style.FLARE_ICONS[def.flareIcon]
  b.bronze = flareIcon ~= nil and H.Style.FlareIcon(b.icon, false, flareIcon)
  if b.bronze then
    b.icon:ClearAllPoints()
    b.icon:SetSize(14, 14)
    b.icon:SetPoint("CENTER")
  end
  b.checked = b:CreateTexture(nil, "OVERLAY")
  b.checked:SetAllPoints()
  b.checked:SetTexture("Interface\\Buttons\\CheckButtonHilight")
  b.checked:SetBlendMode("ADD")
  if not b.bronze then
    local hl = b:CreateTexture(nil, "HIGHLIGHT")
    hl:SetAllPoints()
    hl:SetTexture("Interface\\Buttons\\ButtonHilight-Square")
    hl:SetBlendMode("ADD")
  end
  b:SetScript("OnClick", function(self)
    def.onClick()
    updateHeaderButtons()
    if GameTooltip and GameTooltip:IsOwned(self) then
      self:GetScript("OnEnter")(self)
    end
  end)
  b:SetScript("OnEnter", function(self)
    if rawget(self, "bronze") then
      H.Style.FlareIcon(self.icon, true)
    end
    if GameTooltip then
      GameTooltip:SetOwner(self, "ANCHOR_BOTTOM")
      def.tooltip(GameTooltip)
      GameTooltip:Show()
    end
  end)
  b:SetScript("OnLeave", function()
    updateHeaderButtons()
    if GameTooltip then
      GameTooltip:Hide()
    end
  end)
  headerButtons[#headerButtons + 1] = b
  return b
end

function PlayerFrame.UpdateHeaderButtons()
  updateHeaderButtons()
end

-- The home button (2026-11-05, asked after a look in game: the window moves freely, and a button puts it back for
-- whoever lost it on another screen size): against FlareUI's tracker while it runs (docked again), else at its
-- default place. Shown only while the window is elsewhere; left of the title bar's buttons; the glyph "replay" (white
-- in FlareUI's struck bronze in its theme).
local function updateHome()
  local b = frame and rawget(frame, "homeButton")
  if not b then
    return
  end
  local Tracker = H.TrackerButtons
  local away
  if Tracker and Tracker.FlareHolder() then
    away = not rawget(frame, "docked")
  else
    away = ForeverSpeechDB.playerMoved == true
  end
  b:SetShown(away)
end

local function homeTooltip(b)
  local Tracker = H.TrackerButtons
  local docks = Tracker and Tracker.FlareHolder() ~= nil
  H.Style.Tooltip(b, "ANCHOR_BOTTOM", docks and L.HOME_DOCK or L.HOME_RESET, nil, L.HOME_HINT)
end

-- FlareUI's theme (2026-11-05, after a look in game): the title bar's buttons as its tracker's header: icons of one
-- size on the title's line, six pixels apart, the box button at the right edge. FlareUI's gear sits high in its image:
-- one pixel down.
local FLARE_ICON, FLARE_BUTTON, FLARE_GAP = 13, 16, 6
local function layoutFlareHeader(f)
  local options, close = f.optionsButton, rawget(f, "CloseButton")
  if not (options and rawget(options, "bronze") and close) then
    return
  end
  local slack = (FLARE_BUTTON - FLARE_ICON) / 2 -- the button's margin around its icon
  local function fit(b, icon, previous, offset, nudge)
    b:SetSize(FLARE_BUTTON, FLARE_BUTTON)
    b:ClearAllPoints()
    b:SetPoint("RIGHT", previous, "LEFT", -offset, 0)
    icon:ClearAllPoints()
    icon:SetSize(FLARE_ICON, FLARE_ICON)
    icon:SetPoint("CENTER", 0, nudge or 0)
  end
  fit(options, options.tex, close, FLARE_GAP - slack, -1)
  local previous = options
  for _, b in ipairs(headerButtons) do
    if rawget(b, "bronze") then
      fit(b, b.icon, previous, FLARE_GAP - 2 * slack)
    end
    previous = b
  end
  local home = rawget(f, "homeButton")
  if home and rawget(home, "bronze") then
    fit(home, home.icon, previous, FLARE_GAP - 2 * slack)
  end
end

local function buildHomeButton(f)
  local b = CreateFrame("Button", nil, f)
  b:SetSize(18, 18)
  local previous = headerButtons[#headerButtons] or f.optionsButton
  b:SetPoint("RIGHT", previous, "LEFT", -6, 0)
  b:SetFrameLevel(previous:GetFrameLevel() or ((f:GetFrameLevel() or 0) + 5))
  b.icon = b:CreateTexture(nil, "ARTWORK")
  b.icon:SetSize(14, 14)
  b.icon:SetPoint("CENTER")
  b.bronze = H.Style.FlareIcon(b.icon, false, H.Style.Glyph("replay") .. "_white")
  if not b.bronze then
    b.icon:SetTexture(H.Style.Glyph("replay"))
    local hl = b:CreateTexture(nil, "HIGHLIGHT")
    hl:SetAllPoints()
    hl:SetTexture("Interface\\Buttons\\ButtonHilight-Square")
    hl:SetBlendMode("ADD")
  end
  b:SetScript("OnClick", function(self)
    PlayerFrame.GoHome()
    H.Style.HideTooltip()
    if rawget(self, "bronze") then
      H.Style.FlareIcon(self.icon, false)
    end
  end)
  b:SetScript("OnEnter", function(self)
    if rawget(self, "bronze") then
      H.Style.FlareIcon(self.icon, true)
    end
    homeTooltip(self)
  end)
  b:SetScript("OnLeave", function(self)
    if rawget(self, "bronze") then
      H.Style.FlareIcon(self.icon, false)
    end
    H.Style.HideTooltip()
  end)
  b:Hide()
  f.homeButton = b
end

function PlayerFrame.RegisterHeaderButton(def)
  headerDefs[#headerDefs + 1] = def
  if frame then
    buildHeaderButton(frame, def)
    updateHeaderButtons()
  end
end

-- A title bar button by its key (tests and debugging).
function PlayerFrame.HeaderButton(key)
  for _, b in ipairs(headerButtons) do
    if b.def.key == key then
      return b
    end
  end
  return nil
end

function PlayerFrame.OptionsButton()
  return frame and frame.optionsButton
end

-- The options button is lit while the options window is shown.
function PlayerFrame.UpdateOptionsButton()
  if frame and frame.optionsButton then
    frame.optionsButton:SetLit(H.Options.IsShown())
  end
end

-- What the options window uses (2026-10-15): the same frame, buttons and title as this window.
PlayerFrame.Kit = { create = create, button = button, backdrop = backdrop, dressPortrait = dressPortrait }

-- Settings changed from the options window: the quest text (showText), the model framing (modelZoom).
function PlayerFrame.RefreshQuestText()
  if frame then
    PlayerFrame.SetQuestText(frame.shownText)
  end
end

-- The compact window (2026-10-21, /fs compact): without the quest's description, the one optional block (asked: the
-- header, the objectives and the rewards always stay). It is the setting showText, turned off.
function PlayerFrame.SetCompact(on)
  ForeverSpeechDB.showText = not on
  PlayerFrame.RefreshQuestText()
end

-- A first version (2026-10-21) had its own setting, compact, also hiding the rewards: its choice becomes showText.
H.OnInit(function()
  if ForeverSpeechDB.compact ~= nil then
    if ForeverSpeechDB.compact then
      ForeverSpeechDB.showText = false
    end
    ForeverSpeechDB.compact = nil
  end
end)

-- Docks the window to FlareUI's tracker, or frees it (setting dockFlare, FlareUI's redraws); docked, the window is
-- never shorter than the tracker.
function PlayerFrame.Redock()
  if not frame then
    return
  end
  local moved = place(frame)
  local holder = rawget(frame, "docked") and rawget(frame, "dockedTo")
  local height = holder and holder:GetHeight() or nil
  if moved or height ~= rawget(frame, "dockHeight") then
    frame.dockHeight = height
    PlayerFrame.UpdateList()
  end
  updateHome()
end

-- Puts the window back (the home button): against FlareUI's tracker while it runs, else at its default place.
function PlayerFrame.GoHome()
  if not frame then
    return
  end
  local Tracker = H.TrackerButtons
  if Tracker and Tracker.FlareHolder() then
    ForeverSpeechDB.dockFlare = true
  else
    ForeverSpeechDB.playerPos = nil
  end
  ForeverSpeechDB.playerMoved = nil
  frame.placed = nil -- placed again
  H.Trace("frame: home")
  PlayerFrame.Redock()
end

-- The home button, for tests: nil before the window is built.
function PlayerFrame.HomeButton()
  return frame and rawget(frame, "homeButton")
end

-- "right" or "left" (the tracker's side of the screen) while docked to FlareUI's tracker, else nil.
function PlayerFrame.Docked()
  return frame and rawget(frame, "docked") or nil
end

function PlayerFrame.ApplyZoom()
  if frame then
    applyZoom(frame.model)
  end
end

local function build()
  local f, templated
  local portrait = _G.PortraitFrameMixin ~= nil
  if portrait then
    f, portrait = create("Frame", UIParent, "PortraitFrameTemplate")
  end
  if not portrait then
    f, templated = create("Frame", UIParent, "BackdropTemplate")
  end
  f.headerExtra = not portrait and 0 or PORTRAIT_ICON and PORTRAIT_ICON_HEADER or PORTRAIT_HEADER
  f.line = false -- the line of Elise shown ("zone" or "level", its ID in f.lineID), false for a quest
  f:SetSize(WIDTH, 320) -- sized for its tab when shown (SelectTab)
  f:SetFrameStrata("MEDIUM")
  f:SetToplevel(true)
  f:SetClampedToScreen(true)
  f:SetMovable(true)
  f:EnableMouse(true)
  f:RegisterForDrag("LeftButton")
  f:SetScript("OnDragStart", function(self)
    if rawget(self, "docked") then -- dragged away from FlareUI's tracker: free from now on (the home button docks it)
      local left, top = self:GetLeft(), self:GetTop()
      ForeverSpeechDB.dockFlare = false
      self.docked, self.dockedTo, self.dockHeight = nil, nil, nil
      if left and top then
        self:ClearAllPoints()
        self:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", left, top)
      end
      H.Trace("frame: undocked by a drag")
    end
    self:StartMoving()
  end)
  f:SetScript("OnDragStop", function(self)
    self:StopMovingOrSizing()
    savePosition(self)
    ForeverSpeechDB.playerMoved = true
    PlayerFrame.UpdateList()
    updateHome()
  end)
  H.Trace("frame: PortraitFrameTemplate=%s BackdropTemplate=%s", portrait, templated)

  -- header: title bar (portrait frame; its own close button), else the addon name; the options button by the close
  local close
  if portrait then
    dressPortrait(f)
    close = f.CloseButton
  else
    backdrop(f, templated, 0.92)
    close = CreateFrame("Button", nil, f, "UIPanelCloseButton")
    close:SetPoint("TOPRIGHT", -2, -2)
    local name = f:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    name:SetPoint("TOPLEFT", 12, -12)
    name:SetText("|T" .. H.MEDIA .. "icon:16:16|t " .. H.TITLE)
  end
  H.Style.FlareWindow(f, "main") -- FlareUI's look while it runs (2026-11-05)
  buildOptionsButton(f, close)
  for _, def in ipairs(headerDefs) do
    buildHeaderButton(f, def)
  end
  buildHomeButton(f)
  layoutFlareHeader(f)

  local function content()
    local panel = CreateFrame("Frame", nil, f)
    panel:SetPoint("TOPLEFT", 0, -(HEADER_HEIGHT + f.headerExtra))
    panel:SetPoint("BOTTOMLEFT", 0, 0)
    panel:SetWidth(WIDTH) -- the window's own part; the list takes the rest when shown
    return panel
  end
  f.questPanel = content()
  frame = f -- the panel builders' scripts refer to `frame`
  buildQuestPanel(f, f.questPanel)
  buildListPanel(f)
  buildListToggle(f)
  buildDebugBar(f)
  f:SetScript("OnShow", function()
    PlayerFrame.UpdateList()
    PlayerFrame.UpdateDebugBar()
  end)

  place(f)
  if H.SideTabs then -- after the window's own scripts: it hooks them
    H.SideTabs.Attach(f)
  end
  f:Hide()
  -- Open or closed is remembered (2026-10-21, windowShown): reopened at the next login or /reload. Recorded after the
  -- build's own Hide; a hide because UIParent is hidden (Alt+Z, a cinematic) keeps the window "shown" (IsShown), and
  -- the UI torn down at logout records nothing.
  f:HookScript("OnShow", function()
    ForeverSpeechDB.windowShown = true
  end)
  f:HookScript("OnHide", function(self)
    if not self:IsShown() and not loggingOut then
      ForeverSpeechDB.windowShown = false
    end
  end)
  H.Style.FlareTheme(f, "main") -- after the window's own scripts
  PlayerFrame.SelectTab("quest")
  return f
end

-- Shows a speaker's portrait: false if it has none, or if the client refuses the file (SetTexture returns false).
local function showPortrait(speakerID)
  local file = PORTRAIT[tonumber(speakerID) or -1]
  if not file then
    return false
  end
  local ok, set = pcall(frame.portrait.SetTexture, frame.portrait, file)
  H.Trace("frame: portrait speaker=%s ok=%s set=%s", speakerID, ok, set)
  if not ok or set == false then
    return false
  end
  frame.portrait:SetTexCoord(unpack(PORTRAIT_FACE[tonumber(speakerID)] or { 0, 1, 0, 1 }))
  frame.portrait:Show()
  frame.faceKind = "portrait"
  return true
end

-- The game's 2D portrait of an NPC's display in the medallion (SetPortraitTextureFromCreatureDisplayID, Retail;
-- unverified on Forever: T50); false without the function or a display ID.
local function showFace(displayID)
  local render = _G.SetPortraitTextureFromCreatureDisplayID
  if not (render and displayID) then
    return false
  end
  local ok = pcall(render, frame.portrait, displayID)
  H.Trace("frame: face display=%s ok=%s", displayID, ok)
  if not ok then
    return false
  end
  frame.portrait:SetTexCoord(0, 1, 0, 1)
  frame.portrait:Show()
  frame.faceKind = "face"
  return true
end

-- What stands in the visual frame ("portrait", "model" or "icon") and its texture, for tests and debugging.
function PlayerFrame.Visual()
  if not frame then
    return nil
  end
  if frame.portrait:IsShown() then
    return rawget(frame, "faceKind") or "portrait", frame.portrait:GetTexture()
  elseif frame.model:IsShown() then
    return "model"
  end
  return "icon", frame.icon:GetTexture()
end

local function setVisual(data)
  local model, icon = frame.model, frame.icon
  icon:Hide()
  model:Hide()
  frame.portrait:Hide()
  if showPortrait(data.npcID or data.speakerID) then
    return
  end
  if not (data.displayID or data.npcID) then
    icon:Show()
    return
  end
  if showFace(data.displayID) then
    return
  end
  model:Show()
  pcall(model.ClearModel, model)
  if data.displayID then
    pcall(model.SetDisplayInfo, model, data.displayID)
  else
    pcall(model.SetCreature, model, data.npcID)
  end
  applyZoom(model)
  -- An uncached NPC loads no model (S8): fall back to the quest icon.
  C_Timer.After(1.5, function()
    if frame.questID ~= data.questID or frame.portrait:IsShown() then
      return
    end
    local ok, fileID = pcall(model.GetModelFileID, model)
    H.Trace("frame: model quest=%s npc=%s display=%s fileID=%s zoom=%s ok=%s", data.questID, data.npcID,
      data.displayID, ok and fileID, ForeverSpeechDB.modelZoom, applyZoom(model))
    if not ok or not fileID then
      model:Hide()
      icon:Show()
    end
  end)
end

local function setRewards(rewards)
  local i = 0
  local function add(item, choice)
    i = i + 1
    local b = frame.rewardIcons[i]
    if not b then
      return
    end
    b.item, b.choice = item, choice
    b.icon:SetTexture(item.texture)
    b.icon:SetDesaturated(choice and true or false)
    H.Style.ItemBorder(b, item.quality) -- the game's icon frame in the item's quality colour (2026-10-21)
    b.count:SetText((item.count and item.count > 1) and item.count or "")
    b:Show()
  end
  for _, item in ipairs(rewards.items or {}) do
    add(item, false)
  end
  for _, item in ipairs(rewards.choices or {}) do
    add(item, true)
  end
  for j = i + 1, MAX_REWARD_ICONS do
    frame.rewardIcons[j]:Hide()
  end
  local parts = {}
  if rewards.money and rewards.money > 0 then
    parts[#parts + 1] = moneyString(rewards.money)
  end
  if rewards.xp and rewards.xp > 0 then
    parts[#parts + 1] = string.format(L.XP, rewards.xp)
  end
  local text = table.concat(parts, "   ")
  frame.rewardText:SetText(text)
  frame.rewards:SetShown(i > 0 and frame.rewardHeader:IsShown())
  frame.rewardItems = frame.rewardHeader:IsShown() and i or 0
end

function PlayerFrame.Refresh()
  if not frame then
    return
  end
  PlayerFrame.UpdateList()
  if not frame.questID and not frame.line then
    return
  end
  local Player = H.Player
  local questID, part = frame.questID, frame.part or "detail"
  local queued = #Player.Queue()
  local status
  local isQueued, position
  local playing
  if frame.line then
    isQueued, position = Player.IsLineQueued(frame.line, frame.lineID)
    playing = Player.IsLinePlaying(frame.line, frame.lineID)
  else
    isQueued, position = Player.IsQueued(questID, part)
    playing = Player.IsPlaying(questID, part)
  end
  if playing then
    status = "|cff40ff40" .. L.STATUS_PLAYING .. "|r"
  elseif isQueued then
    status = "|cffffd200" .. string.format(L.STATUS_QUEUED, position) .. "|r"
  else
    status = "|cff999999" .. L.STATUS_IDLE .. "|r"
  end
  if queued > 0 then
    status = status .. "  ·  " .. string.format(L.STATUS_QUEUE, queued)
  end
  frame.status:SetText(status)
  frame.stopButton:SetActive(Player.IsBusy())
  frame.nextButton:SetActive(queued > 0)
end

-- Height of the shown quest text: the client's measure, else an estimate (about 70 characters a line).
local function textHeight(fs, text)
  local ok, height = pcall(fs.GetStringHeight, fs)
  height = ok and tonumber(height)
  if height and height > 0 then
    return math.min(height, TEXT_MAX_LINES * TEXT_LINE_HEIGHT)
  end
  local lines = 0
  for paragraph in (text .. "\n"):gmatch("(.-)\n") do
    lines = lines + math.max(1, math.ceil(#paragraph / 70))
  end
  return math.min(lines, TEXT_MAX_LINES) * TEXT_LINE_HEIGHT
end

-- Shows the quest text (option showText) between the model and the objectives, and resizes the quest
-- tab to fit it. The text is the game's own (D1): the capture or the quest log, never the data files.
function PlayerFrame.SetQuestText(text)
  if not frame then
    return
  end
  frame.shownText = text
  local fs, header = frame.questText, frame.objHeader
  header:ClearAllPoints()
  if ForeverSpeechDB.showText and text and text ~= "" then
    fs:SetText(text)
    fs:Show()
    frame.textHeight = textHeight(fs, text)
    header:SetPoint("TOPLEFT", fs, "BOTTOMLEFT", 0, -SECTION)
  else
    fs:SetText("")
    fs:Hide()
    frame.textHeight = 0
    header:SetPoint("TOPLEFT", frame.visual, "BOTTOMLEFT", 0, -SECTION)
  end
  if frame.tab == "quest" then
    PlayerFrame.SelectTab("quest") -- new height, top-left corner kept
  end
end

function PlayerFrame.QuestText()
  return frame and frame.questText:IsShown() and frame.questText:GetText() or nil
end

-- Height of the objective summary: the client's measure, else an estimate (about 60 characters a line).
local function summaryHeight(fs, text)
  if not text or text == "" then
    return 0
  end
  local ok, height = pcall(fs.GetStringHeight, fs)
  height = ok and tonumber(height)
  if height and height > 0 then
    return math.min(height, SUMMARY_LINES * LINE_HEIGHT)
  end
  return math.min(math.max(1, math.ceil(#text / 60)), SUMMARY_LINES) * LINE_HEIGHT
end

local function setRow(row, line)
  local done = line.finished
  local color = done and BAR_DONE_COLOR or BAR_COLOR
  row.bar:SetValue(done and 1 or line.share or 0)
  row.bar:SetStatusBarColor(color[1], color[2], color[3])
  row.bar:SetShown(line.share ~= nil and not done) -- a line only for a counter still running
  row.label:SetText(line.text)
  if done then
    row.label:SetTextColor(0.6, 0.6, 0.6)
  else
    row.label:SetTextColor(SOFT[1], SOFT[2], SOFT[3])
  end
  row.check:SetShown(done)
  row.bullet:SetShown(not done)
  row:Show()
end

-- Objective summary (capture or quest log), then one row per live objective of the quest log: checkbox and progress
-- bar with the objective inside, greyed and checked once done. The window grows when the rows need it.
local function setObjectives(summary, questID)
  local lines = H.QuestData.Progress(questID) or {}
  if (not summary or summary == "") and #lines == 0 then
    summary = L.NO_TEXT
  end
  frame.objectives:SetText(summary or "")
  local top = summaryHeight(frame.objectives, summary)
  top = top > 0 and top + SUMMARY_GAP or 0
  local shown = 0
  for i, row in ipairs(frame.objectiveRows) do
    row:ClearAllPoints()
    if lines[i] then
      row:SetPoint("TOPLEFT", frame.objectivesArea, "TOPLEFT", 0, -(top + (i - 1) * (OBJ_ROW_HEIGHT + OBJ_ROW_GAP)))
      row:SetPoint("RIGHT", frame.objectivesArea, "RIGHT", 0, 0)
      setRow(row, lines[i])
      shown = i
    else
      row:Hide()
    end
  end
  -- the group's progress under the objectives, while grouped
  local partyTop = top + shown * (OBJ_ROW_HEIGHT + OBJ_ROW_GAP)
  local party = H.QuestData.PartyProgress(questID)
  frame.partySig = partySignature(party)
  local partyHeight = 0
  frame.partyHeader:ClearAllPoints()
  if party then
    frame.partyHeader:SetPoint("TOPLEFT", frame.objectivesArea, "TOPLEFT", 0, -(partyTop + PARTY_GAP))
    frame.partyHeader:Show()
    partyHeight = PARTY_GAP + PARTY_LINE
  else
    frame.partyHeader:Hide()
  end
  for i, row in ipairs(frame.partyRows) do
    row:ClearAllPoints()
    local line = party and party[i]
    if line then
      row:SetPoint("TOPLEFT", frame.objectivesArea, "TOPLEFT", 0, -(partyTop + partyHeight))
      row:SetPoint("RIGHT", frame.objectivesArea, "RIGHT", 0, 0)
      setPartyRow(row, line)
      partyHeight = partyHeight + PARTY_LINE
    else
      row:Hide()
    end
  end
  local height = math.max(OBJECTIVES_MIN, partyTop + partyHeight)
  frame.objectivesArea:SetHeight(height)
  if height ~= frame.objectivesHeight then
    frame.objectivesHeight = height
    if frame.tab == "quest" then
      PlayerFrame.SelectTab("quest") -- new height, top-left corner kept
    end
  end
end

-- The group's lines shown, for tests and debugging: { {text, done}, ... }.
function PlayerFrame.PartyRows()
  local rows = {}
  for _, row in ipairs(frame and frame.partyRows or {}) do
    if row:IsShown() then
      rows[#rows + 1] = { text = row.label:GetText(), done = row.check:IsShown() }
    end
  end
  return rows
end

-- Objective rows shown, for tests and debugging: { {text, share, done}, ... }.
function PlayerFrame.ObjectiveRows()
  local rows = {}
  for _, row in ipairs(frame and frame.objectiveRows or {}) do
    if row:IsShown() then
      rows[#rows + 1] = { text = row.label:GetText(), share = row.bar:GetValue(), done = row.check:IsShown() }
    end
  end
  return rows
end

-- The quest title with its level (2026-10-14): its badge (2026-10-18), else as the game writes it in the objective
-- tracker, "[12] Title" in the color of its difficulty for the player (gray, green, yellow, orange, red). The title
-- alone without a known level.
-- playerLevel: see QuestData.Difficulty.
-- The badge (key and level), or none (nil).
local function setBadge(key, level, color)
  local badge = frame.badge
  local shown = key ~= nil and badge.shield:SetTexture(BADGE_DIR .. key) ~= false
  if shown then
    local font = badge.level:GetFont() -- GameFontNormalLarge's, outlined thick and sized to the plate
    if font then
      badge.level:SetFont(font, level < 10 and BADGE_FONT or BADGE_FONT_2, "THICKOUTLINE")
    end
    badge.level:SetText(level)
    badge.level:SetTextColor(color.r, color.g, color.b)
    local nudge = BADGE_NUDGE[level < 10 and 1 or 2]
    badge.level:ClearAllPoints()
    badge.level:SetPoint("TOPLEFT", badge, "TOPLEFT", nudge[1], nudge[2])
    badge.level:SetPoint("BOTTOMRIGHT", badge, "BOTTOMRIGHT", nudge[1], nudge[2])
  end
  badge:SetShown(shown)
  return shown
end

-- The header's height: taller when the title takes two lines (the client's line count, else its width).
local function fitHead()
  local title, lines = frame.title, 1
  local ok, n = pcall(title.GetNumLines, title)
  if ok and tonumber(n) then
    lines = n
  else
    local okW, w = pcall(title.GetStringWidth, title)
    local okR, r = pcall(title.GetWidth, title)
    if okW and okR and tonumber(w) and tonumber(r) and r > 0 and w > r then
      lines = 2
    end
  end
  local h = lines > 1 and HEAD_H_2 or HEAD_H
  if h ~= frame.headHeight then
    frame.headHeight = h
    frame.head:SetHeight(h)
  end
end

local function setTitle(playerLevel)
  local title = frame.questTitle or ("#" .. frame.questID)
  local level, source
  if ForeverSpeechDB.showQuestLevel ~= false then -- option (2026-10-15)
    level, source = H.QuestData.Level(frame.questID)
  end
  local key, color = H.QuestData.Difficulty(level, playerLevel)
  H.Trace("frame: quest=%s level=%s source=%s player=%s difficulty=%s", frame.questID, level, source, playerLevel,
    key)
  if not setBadge(key, level, color) and color then
    title = string.format("|cff%02x%02x%02x[%d] %s|r", math.floor(color.r * 255 + 0.5),
      math.floor(color.g * 255 + 0.5), math.floor(color.b * 255 + 0.5), level, title)
  end
  frame.title:SetText(PART_MARK[frame.part] .. title)
  fitHead()
end

-- A level gained: the shown quest's color follows the new level (PLAYER_LEVEL_UP gives it before UnitLevel does).
-- The title shown (with its color codes), for tests and debugging.
function PlayerFrame.Title()
  return frame and frame.title:GetText() or nil
end

-- The level badge shown: its texture and level, or nil. For tests and debugging.
function PlayerFrame.Badge()
  if frame and frame.badge:IsShown() then
    return frame.badge.shield:GetTexture(), frame.badge.level:GetText()
  end
  return nil
end

function PlayerFrame.UpdateQuestLevel(playerLevel)
  if frame and frame.questID then
    setTitle(playerLevel)
  end
end

H.TryRegisterEvent("PLAYER_LEVEL_UP", function(_, level)
  PlayerFrame.UpdateQuestLevel(level)
end)

-- Puts a quest part in the quest tab, without opening the window nor changing its tab.
local function fill(questID, part)
  local data = H.QuestData.Get(questID, part) or { questID = questID, rewards = {} }
  H.Trace("frame: show quest=%s part=%s source=%s npc=%s descLen=%s", questID, part, data.source, data.npcID,
    data.description and #data.description)
  frame.questID, frame.part, frame.line, frame.lineID = questID, part, false, nil
  frame.icon:SetTexture(QUEST_ICON)
  frame.objHeader:SetText(L.OBJECTIVES)
  frame.rewardHeader:Show()
  frame.rewardLine:Show()
  frame.questTitle = data.title or false -- false, not nil: see PlayerFrame.Line
  setTitle()
  frame.giver:SetText(data.giverName or "")
  frame.dot:SetShown((data.giverName or "") ~= "")
  frame.objectiveSummary = data.objectives
  setObjectives(data.objectives, questID)
  for i, line in ipairs(H.QuestData.Progress(questID) or {}) do
    H.Trace("frame: objective %s quest=%s type=%s have=%s need=%s finished=%s share=%s text=%s", i, questID,
      line.type, line.have, line.need, line.finished, line.share, line.text)
  end
  setVisual(data)
  setRewards(data.rewards or {})
  PlayerFrame.SetQuestText(part == "complete" and H.QuestData.Text(questID, "complete") or data.description)
end

-- Shows the window on the quest tab with the given quest part ("detail" by default; "complete": the
-- turn-in, with the NPC it is turned in to).
function PlayerFrame.ShowQuest(questID, part)
  questID = tonumber(questID)
  if not questID then
    return false
  end
  part = part == "complete" and "complete" or "detail"
  frame = frame or build()
  fill(questID, part)
  PlayerFrame.SelectTab("quest")
  frame:Show()
  PlayerFrame.Refresh()
  return true
end

-- Puts a line of Elise in the quest tab (2026-10-11): its name (the zone, the level), Elise, its icon in place of a
-- model, her text (option showText); no objectives, no rewards.
local SUMMARY = { zone = "ZONE_SUMMARY", level = "LEVEL_SUMMARY", companion = "COMPANION_SUMMARY",
  book = "BOOK_SUMMARY", gossip = "GOSSIP_SUMMARY" }
local HEADER = { zone = "EXPLORATION", level = "LEVEL_HEADER", companion = "COMPANIONS", book = "BOOK_HEADER",
  gossip = "GOSSIP_HEADER" }

local function fillLine(kind, id)
  local entry = H.Index.Line(kind, id) or {}
  H.Trace("frame: show line=%s %s name=%s", kind, id, entry.name)
  frame.questID, frame.part, frame.line, frame.lineID = false, nil, kind, id
  setBadge(nil)
  frame.title:SetText(entry.name or ("#" .. id))
  fitHead()
  local speakerID = entry.intro and entry.intro.npc or 1000000
  local speaker = H.Index.NPC(speakerID)
  frame.giver:SetText(speaker and speaker.name or "Elise")
  frame.dot:Show()
  frame.objHeader:SetText(L[HEADER[kind]])
  frame.objectiveSummary = L[SUMMARY[kind]]
  setObjectives(frame.objectiveSummary, nil)
  frame.model:Hide()
  frame.icon:Hide()
  frame.portrait:Hide()
  frame.icon:SetTexture(LINE_ICON[kind])
  if speaker and speaker.display and not PORTRAIT[speakerID] then -- an NPC's dialogue (2026-10-21): its model
    setVisual({ speakerID = speakerID, displayID = speaker.display })
  elseif not showPortrait(speakerID) then
    frame.icon:Show()
  end
  setRewards({})
  frame.rewardHeader:Hide()
  frame.rewardLine:Hide()
  PlayerFrame.SetQuestText(entry.text)
end

function PlayerFrame.ShowLine(kind, id)
  id = tonumber(id)
  if not id or not H.Index.Line(kind, id) then
    return false
  end
  frame = frame or build()
  fillLine(kind, id)
  PlayerFrame.SelectTab("quest")
  frame:Show()
  PlayerFrame.Refresh()
  return true
end

-- The line of Elise shown: kind ("zone", "level") and ID, or nil. (false, not nil, when none: a frame's missing
-- field is not always nil)
function PlayerFrame.Line()
  if frame and frame.line then
    return frame.line, frame.lineID
  end
  return nil
end

-- Logbook (option followTracked, 2026-10-10): while nothing plays, the window shows the quest the player
-- follows (QuestData.Tracked). It goes back to it when the play list has nothing left to play, and follows it
-- when it changes; a quest picked by hand stays until then. Never while a quest plays or the list waits between
-- two quests, never opening the window nor changing its tab (a closed window opens on it: Open).
local function logbookQuest()
  if not ForeverSpeechDB.followTracked or H.Player.IsBusy() then
    return nil
  end
  return (H.QuestData.Tracked())
end

-- A quest the player clicked (2026-10-21): its title in the objective tracker, or its details opened in the quest log.
-- The open window shows it (only shown: nothing is played or queued), as a click on a row of the play list does. On
-- Forever a click does not focus the quest (the followed quest stays the tracker's first, seen in the trace), so the
-- logbook alone never followed it. The window closed: nothing.
function PlayerFrame.ShowClicked(questID, from)
  questID = tonumber(questID)
  if not (questID and frame and frame:IsShown()) then
    return false
  end
  H.Trace("frame: clicked quest=%s (%s)", questID, from or "?")
  if frame.questID == questID and frame.part == "detail" and frame.tab == "quest" then
    return false
  end
  PlayerFrame.ShowQuest(questID, "detail")
  return true
end

function PlayerFrame.FollowTracked()
  if not (frame and frame:IsShown()) then
    return false
  end
  local questID = logbookQuest()
  if not questID or (frame.questID == questID and frame.part == "detail") then
    return false
  end
  H.Trace("frame: logbook quest=%s", questID)
  fill(questID, "detail")
  PlayerFrame.Refresh()
  return true
end

-- Opens the window: closed, on the followed quest while nothing plays (logbook); else on the shown quest, else
-- the last opened quest, else an empty quest tab. Audio off, or tab "options": the options window instead, where the
-- audio is turned back on.
function PlayerFrame.Open(tab)
  if tab == "options" or not H.IsEnabled() then
    H.Options.Open()
    return
  end
  local followed = not PlayerFrame.IsShown() and logbookQuest()
  if not followed and frame and frame.line then
    PlayerFrame.ShowLine(frame.line, frame.lineID)
    if tab then
      PlayerFrame.SelectTab(tab)
    end
    return
  end
  local questID = followed or (frame and frame.questID) or H.Capture.lastQuestID
    or (H.Capture.Recent(1)[1] or {}).questID
  if questID then
    PlayerFrame.ShowQuest(questID, not followed and frame and frame.questID == questID and frame.part or nil)
  else
    frame = frame or build()
    setBadge(nil)
    frame.title:SetText(L.NO_QUEST_TITLE)
    frame.objectiveSummary = nil
    frame.objectives:SetText(L.NO_QUEST)
    PlayerFrame.SetQuestText(nil)
    frame.icon:Show()
    frame.model:Hide()
    frame.portrait:Hide()
    frame:Show()
    PlayerFrame.Refresh()
  end
  if tab then
    PlayerFrame.SelectTab(tab)
  end
end

function PlayerFrame.Toggle(tab)
  if tab == "options" or not H.IsEnabled() then
    H.Options.Toggle()
    return
  end
  if frame and frame:IsShown() and (not tab or frame.tab == tab) then
    frame:Hide()
  else
    PlayerFrame.Open(tab)
  end
end

function PlayerFrame.Hide()
  if frame then
    frame:Hide()
  end
end

function PlayerFrame.IsShown()
  return frame ~= nil and frame:IsShown()
end

-- The quest shown, and its part.
function PlayerFrame.QuestID()
  return frame and frame.questID or nil, frame and frame.part
end

-- A quest starting, or requested again while playing or queued, opens the window (option) or
-- updates it when open; the list follows the queue. Once the list has nothing left to play, the window
-- goes back to the followed quest (logbook).
H.Player.OnChange(function(event, info)
  if event == "idle" then
    if not PlayerFrame.FollowTracked() then
      PlayerFrame.Refresh()
    end
    return
  end
  if (event == "start" or event == "focus") and info.line then
    local kind, id = PlayerFrame.Line()
    if (ForeverSpeechDB.openOnPlay or PlayerFrame.IsShown()) and (kind ~= info.line or id ~= info.lineID) then
      PlayerFrame.ShowLine(info.line, info.lineID)
    else
      PlayerFrame.Refresh()
    end
    return
  end
  local starting = (event == "start" or event == "focus") and info.questID
  local shownID, shownPart = PlayerFrame.QuestID()
  local other = info.questID ~= shownID or (info.part or "detail") ~= (shownPart or "detail")
  if starting and (ForeverSpeechDB.openOnPlay or PlayerFrame.IsShown()) and (not PlayerFrame.IsShown() or other) then
    PlayerFrame.ShowQuest(info.questID, info.part)
  else
    PlayerFrame.Refresh()
  end
end)

-- Objective progress follows the quest log while the window shows a quest.
H.TryRegisterEvent("QUEST_LOG_UPDATE", function()
  if frame and frame:IsShown() and frame.questID then
    setObjectives(frame.objectiveSummary, frame.questID)
  end
end)

-- The group's progress (2026-11-05): read again when a member's quest log or the group changes, and once a second (the
-- events are unverified on Forever); drawn again only when it changed.
local function refreshParty()
  local questID = frame and frame:IsShown() and rawget(frame, "questID")
  if questID then
    if partySignature(H.QuestData.PartyProgress(questID)) ~= (rawget(frame, "partySig") or "") then
      setObjectives(rawget(frame, "objectiveSummary"), questID)
    end
  end
end
for _, event in ipairs({ "UNIT_QUEST_LOG_CHANGED", "GROUP_ROSTER_UPDATE" }) do
  H.TryRegisterEvent(event, refreshParty)
end
local partyPoll, partyElapsed = CreateFrame("Frame"), 0
partyPoll:SetScript("OnUpdate", function(_, elapsed)
  partyElapsed = partyElapsed + elapsed
  if partyElapsed >= 1 then
    partyElapsed = 0
    refreshParty()
  end
end)

-- Logbook: a change of the followed quest moves the window to it (only a change: a quest picked by hand
-- stays). SUPER_TRACKING_CHANGED is unverified on Forever (2026-10-10); the quest log and watch list events
-- catch the change anyway.
local lastTracked
local function onTrackingChange()
  local questID, from = H.QuestData.Tracked()
  if questID == lastTracked then
    return
  end
  H.Trace("frame: followed quest %s -> %s (%s)", lastTracked, questID, from)
  lastTracked = questID
  PlayerFrame.FollowTracked()
end
for _, event in ipairs({ "SUPER_TRACKING_CHANGED", "QUEST_WATCH_LIST_CHANGED", "QUEST_LOG_UPDATE" }) do
  H.TryRegisterEvent(event, onTrackingChange)
end
-- FlareUI's tracker (ui/tracker_buttons.lua) redraws after these events: it says when its first quest changed.
PlayerFrame.TrackingChanged = onTrackingChange

H.RegisterCommand("show", function(arg)
  local questID = tonumber(arg)
  if questID then
    PlayerFrame.ShowQuest(questID)
  else
    PlayerFrame.Open()
  end
end, "show [questID] - open the main window")

H.RegisterCommand("compact", function(arg)
  local on = arg == "on" or (arg ~= "off" and ForeverSpeechDB.showText ~= false)
  PlayerFrame.SetCompact(on)
  H.Print(on and L.COMPACT_ON or L.COMPACT_OFF)
end, "compact [on|off] - the window without the quest's description")

H.RegisterCommand("zoom", function(arg)
  local value = tonumber(arg)
  if value then
    ForeverSpeechDB.modelZoom = math.max(0, math.min(1, value))
    if frame then
      applyZoom(frame.model)
    end
  end
  H.Print("model zoom: %s (0 = full body, 1 = face)", tostring(ForeverSpeechDB.modelZoom))
end, "zoom [0-1] - NPC model framing")

-- Small play/stop toggle shared by the tracker and quest log buttons. Left click: play (or
-- queue) / stop; right click: open the player window.
local toggles = setmetatable({}, { __mode = "k" })

local function updateToggle(b)
  local questID, Player = b.questID, H.Player
  b:SetShown(questID ~= nil and H.IsEnabled()) -- audio off: no button in the game UI
  local playing = questID and Player.IsPlaying(questID)
  b:SetGlyph(playing and "stop" or "play")
  -- a quest waiting in the list: full gold; playing: the stop glyph, a touch of green; else a quieter play glyph.
  -- FlareUI's theme: its bronze, lighter while playing or waiting (a colour would cover the bronze, 2026-11-05).
  if rawget(b, "bronze") then
    b.lit = playing or (questID ~= nil and Player.IsQueued(questID)) or false
    H.Style.RefreshButton(b)
  elseif playing then
    b.glyph:SetVertexColor(0.6, 1, 0.6)
  elseif questID and Player.IsQueued(questID) then
    b.glyph:SetVertexColor(1, 1, 1)
  else
    b.glyph:SetVertexColor(0.8, 0.8, 0.8)
  end
end

-- A row button (2026-10-21, ui/style.lua): the gold glyph on the game's minimal check box.
function PlayerFrame.MakeToggleButton(parent, size)
  local b = H.Style.RowButton(parent, "play", size, function(self)
    return H.Player.IsPlaying(self.questID) and L.TOOLTIP_STOP or L.TOOLTIP_PLAY, nil, L.TOOLTIP_HINT
  end)
  b:RegisterForClicks("LeftButtonUp", "RightButtonUp")
  b:SetScript("OnClick", function(self, mouseButton)
    local questID = self.questID
    if not questID then
      return
    end
    if mouseButton == "RightButton" then
      PlayerFrame.ShowQuest(questID)
    elseif H.Player.IsPlaying(questID) then
      H.Player.Stop()
    else
      H.Player.PlayQuest(questID)
    end
  end)
  -- Sets the quest and shows the button (hidden while the audio is off).
  function b.SetQuest(self, questID)
    self.questID = questID
    updateToggle(self)
  end
  toggles[b] = true
  return b
end

local function updateToggles()
  for b in pairs(toggles) do
    updateToggle(b)
  end
end
H.Player.OnChange(updateToggles)

H.OnEnabledChange(function()
  updateToggles()
  if frame then
    PlayerFrame.Refresh()
  end
end)

-- The window open at the last logout or /reload opens again (2026-10-21), once the world is entered, the audio on.
H.TryRegisterEvent("PLAYER_LOGOUT", function()
  loggingOut = true
end)
local restored = false
H.TryRegisterEvent("PLAYER_ENTERING_WORLD", function()
  if restored then
    return
  end
  restored = true
  C_Timer.After(1, function()
    if ForeverSpeechDB.windowShown and H.IsEnabled() and not PlayerFrame.IsShown() then
      H.Trace("frame: reopened (open at the last logout)")
      PlayerFrame.Open()
    end
  end)
end)
