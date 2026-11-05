-- ForeverSpeech: the companion journal's display (D18, 2026-10-15; criteria: docs/companions.md). Its own window
-- (2026-10-21; before: a panel of the main window, then a side tab), opened by the icon in the main window's title bar
-- and /fs friends: the player's time in group, then the top 10 (rank, name in its class color, tier, time together) on
-- the left; a click on a name shows its stats in the box on the right. Movable, its position kept. A player's tooltip
-- (party frames, world, target) gets two lines for a known companion: tier and time, groups and share of time played.
-- Unverified on Forever: RAID_CLASS_COLORS, the unit tooltip hook (TooltipDataProcessor of Retail, else the
-- OnTooltipSetUnit script of Classic), the tab icon (painted for the addon, 2026-10-15, tools/tab_icons.sh; T30).
local H = ForeverSpeech
local L = H.L
local Companions = H.Companions
local PlayerFrame = H.PlayerFrame

local ICON = H.MEDIA .. "tabs\\companions"
local TOP, ROW_HEIGHT = 10, 22 -- the top 10
local DETAIL_LINES = 8 -- the right-hand box: name, tier, one stat per line (long ones wrap)
local WIDTH, HEIGHT, LIST_WIDTH, BAR = 660, 330, 410, 30 -- the window, its list part, its title bar

local panel -- the list part, built with the window
local window -- built on first use

local function classColor(class)
  local colors = _G.RAID_CLASS_COLORS
  local c = type(colors) == "table" and class and colors[class]
  if type(c) == "table" and c.r then
    return string.format("|cff%02x%02x%02x", c.r * 255, c.g * 255, c.b * 255)
  end
  return "|cffffffff"
end

local function day(t)
  return t and date("%d/%m/%Y", t) or "?"
end

-- The stats of a companion, one per line (the shares only once the time played is known).
function Companions.StatLines(guid)
  local entry = Companions.Get(guid)
  if not entry then
    return {}
  end
  local summary = Companions.Summary()
  local lines = { string.format(L.COMPANION_TIME, Companions.FormatDuration(entry.seconds)) }
  local played = Companions.Share(entry.seconds, summary.total)
  if played then
    lines[#lines + 1] = string.format(L.COMPANION_PLAYED_SHARE, played)
  end
  local group = Companions.Share(entry.seconds, summary.groupSeconds)
  if group then
    lines[#lines + 1] = string.format(L.COMPANION_GROUP_SHARE, group)
  end
  lines[#lines + 1] = string.format(L.COMPANION_GROUP_COUNT, entry.groups or 0)
  lines[#lines + 1] = string.format(L.COMPANION_LONGEST_SESSION, Companions.FormatDuration(entry.longest or 0))
  lines[#lines + 1] = string.format(L.COMPANION_MET, day(entry.firstAt), entry.firstZone or "?", entry.firstLevel or 0)
  lines[#lines + 1] = string.format(L.COMPANION_LAST, day(entry.lastAt or entry.firstAt))
  lines[#lines + 1] = string.format(L.COMPANION_DONE, entry.dungeons or 0, entry.quests or 0, entry.levels or 0)
  return lines
end

-- The right-hand box: the companion clicked (its row lit; kept while it stays in the journal), else a hint.
local function showDetail(guid)
  panel.selected = guid
  for _, row in ipairs(panel.rows) do
    row.lit:SetShown(guid ~= nil and row.guid == guid)
  end
  local box = panel.side
  if not box then
    return
  end
  local entry = guid and Companions.Get(guid)
  if not entry then
    box.title:SetText(L.COMPANIONS)
    box.tier:SetText("")
    for i, line in ipairs(box.lines) do
      line:SetText(i == 1 and Companions.Top(1)[1] and L.COMPANION_PICK or "")
    end
    return
  end
  local tier = Companions.Tier(guid)
  box.title:SetText(classColor(entry.class) .. (entry.name or "?") .. "|r")
  box.tier:SetText(tier and tier.name or "")
  local lines = Companions.StatLines(guid)
  for i, line in ipairs(box.lines) do
    line:SetText(lines[i] or "")
  end
end

local function refresh()
  if not panel then
    return
  end
  local summary = Companions.Summary()
  local text = string.format(L.COMPANIONS_GROUP_TIME, Companions.FormatDuration(summary.groupSeconds))
  local share = Companions.Share(summary.groupSeconds, summary.total)
  if share then
    text = text .. " (" .. string.format(L.COMPANION_SHARE_PLAYED, share) .. ")"
  end
  panel.summary:SetText(text .. " · " .. string.format(L.COMPANIONS_COUNT, summary.companions))
  local top = Companions.Top(TOP)
  for i, row in ipairs(panel.rows) do
    local item = top[i]
    row.guid = item and item.guid or nil
    if item then
      local tier = Companions.Tier(item.guid)
      row.rank:SetText(item.rank .. ".")
      row.name:SetText(classColor(item.entry.class) .. (item.entry.name or "?") .. "|r")
      row.tier:SetText(tier and tier.name or "")
      row.time:SetText(Companions.FormatDuration(item.entry.seconds))
      row:Show()
    else
      row:Hide()
    end
  end
  panel.empty:SetShown(#top == 0)
  local selected = panel.selected and Companions.Get(panel.selected) and panel.selected
  showDetail(selected or nil)
end

local function newRow(parent, i)
  local row = CreateFrame("Button", nil, parent)
  row:SetHeight(ROW_HEIGHT)
  row:SetPoint("TOPLEFT", parent, "TOPLEFT", 12, -(36 + (i - 1) * ROW_HEIGHT))
  row:SetPoint("RIGHT", parent, "RIGHT", -12, 0)
  local hl = row:CreateTexture(nil, "HIGHLIGHT")
  hl:SetAllPoints()
  hl:SetColorTexture(1, 1, 1, 0.08)
  row.lit = row:CreateTexture(nil, "BACKGROUND") -- the companion shown on the right
  row.lit:SetAllPoints()
  row.lit:SetColorTexture(1, 0.82, 0, 0.12)
  row.lit:Hide()
  row.rank = row:CreateFontString(nil, "OVERLAY", "GameFontNormal")
  row.rank:SetPoint("LEFT", 0, 0)
  row.rank:SetWidth(24)
  row.rank:SetJustifyH("RIGHT")
  row.name = row:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
  row.name:SetPoint("LEFT", row.rank, "RIGHT", 8, 0)
  row.name:SetWidth(150)
  row.name:SetJustifyH("LEFT")
  row.tier = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
  row.tier:SetPoint("LEFT", row.name, "RIGHT", 6, 0)
  row.tier:SetWidth(130)
  row.tier:SetJustifyH("LEFT")
  row.time = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  row.time:SetPoint("RIGHT", 0, 0)
  row.time:SetJustifyH("RIGHT")
  row:SetScript("OnClick", function(self)
    showDetail(self.guid)
  end)
  return row
end

local function build(p)
  panel = p
  p.summary = p:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  p.summary:SetPoint("TOPLEFT", 12, -12)
  p.summary:SetPoint("RIGHT", p, "RIGHT", -12, 0)
  p.summary:SetJustifyH("LEFT")
  p.rows = {}
  for i = 1, TOP do
    p.rows[i] = newRow(p, i)
  end
  p.empty = p:CreateFontString(nil, "OVERLAY", "GameFontDisable")
  p.empty:SetPoint("TOPLEFT", 12, -40)
  p.empty:SetPoint("RIGHT", p, "RIGHT", -12, 0)
  p.empty:SetJustifyH("LEFT")
  p.empty:SetText(L.COMPANIONS_EMPTY)
end

-- The right-hand box (the game's inset frame, its title the companion's name): tier, then the stats.
local function buildSide(box)
  box.title = box:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
  box.title:SetPoint("TOPLEFT", 12, -12)
  box.title:SetPoint("RIGHT", box, "RIGHT", -12, 0)
  box.title:SetJustifyH("LEFT")
  box.tier = box:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
  box.tier:SetPoint("TOPLEFT", box.title, "BOTTOMLEFT", 0, -4)
  box.tier:SetJustifyH("LEFT")
  box.lines = {}
  local previous = box.tier
  for i = 1, DETAIL_LINES do
    local line = box:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    line:SetPoint("TOPLEFT", previous, "BOTTOMLEFT", 0, i == 1 and -10 or -5)
    line:SetPoint("RIGHT", box, "RIGHT", -10, 0)
    line:SetJustifyH("LEFT")
    box.lines[i] = line
    previous = line
  end
  if panel then
    panel.side = box
  end
end

local function savePosition(f)
  local point, _, relativePoint, x, y = f:GetPoint(1)
  ForeverSpeechDB.companionsPos = { point = point, relativePoint = relativePoint, x = x, y = y }
end

-- The window: the game's portrait frame without a portrait (as the main window and the options), else a dark
-- tooltip frame; the list on the left, the companion's box on the right.
local function buildWindow()
  local Kit = PlayerFrame.Kit
  local f, portrait
  if _G.PortraitFrameMixin ~= nil then
    f, portrait = Kit.create("Frame", UIParent, "PortraitFrameTemplate")
  end
  if portrait then
    Kit.dressPortrait(f, L.COMPANIONS)
  else
    local templated
    f, templated = Kit.create("Frame", UIParent, "BackdropTemplate")
    Kit.backdrop(f, templated, 0.95)
    local close = CreateFrame("Button", nil, f, "UIPanelCloseButton")
    close:SetPoint("TOPRIGHT", -2, -2)
    local name = f:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    name:SetPoint("TOPLEFT", 12, -10)
    name:SetText(L.COMPANIONS)
  end
  H.Style.FlareWindow(f, "companions") -- FlareUI's look while it runs (2026-11-05)
  f:SetSize(WIDTH, HEIGHT)
  f:SetFrameStrata("MEDIUM")
  f:SetToplevel(true)
  f:SetClampedToScreen(true)
  f:SetMovable(true)
  f:EnableMouse(true)
  f:RegisterForDrag("LeftButton")
  f:SetScript("OnDragStart", f.StartMoving)
  f:SetScript("OnDragStop", function(self)
    self:StopMovingOrSizing()
    savePosition(self)
  end)
  local pos = ForeverSpeechDB.companionsPos
  f:ClearAllPoints()
  if pos and pos.point then
    f:SetPoint(pos.point, UIParent, pos.relativePoint or pos.point, pos.x or 0, pos.y or 0)
  else
    f:SetPoint("CENTER", UIParent, "CENTER", -120, 60)
  end
  local list = CreateFrame("Frame", nil, f)
  list:SetPoint("TOPLEFT", f, "TOPLEFT", 6, -BAR)
  list:SetPoint("BOTTOMLEFT", f, "BOTTOMLEFT", 6, 8)
  list:SetWidth(LIST_WIDTH)
  build(list)
  local box, inset = Kit.create("Frame", f, "InsetFrameTemplate")
  if not inset then
    local templated
    box, templated = Kit.create("Frame", f, "BackdropTemplate")
    Kit.backdrop(box, templated, 0.9)
  end
  H.Style.FlareInset(box)
  box:SetPoint("TOPLEFT", list, "TOPRIGHT", 6, -4)
  box:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -8, 10)
  buildSide(box)
  panel.side = box
  f:SetScript("OnShow", function()
    refresh()
    PlayerFrame.UpdateHeaderButtons()
  end)
  f:SetScript("OnHide", PlayerFrame.UpdateHeaderButtons)
  H.Style.FlareTheme(f, "companions") -- after the window's own scripts
  f:Hide()
  return f
end

function Companions.Open()
  window = window or buildWindow()
  window:Show()
  refresh()
  PlayerFrame.UpdateHeaderButtons()
end

function Companions.Close()
  if window then
    window:Hide()
  end
  PlayerFrame.UpdateHeaderButtons()
end

function Companions.Toggle()
  if window and window:IsShown() then
    Companions.Close()
  else
    Companions.Open()
  end
end

function Companions.WindowShown()
  return window ~= nil and window:IsShown()
end

function Companions.Window()
  return window
end

-- The rows shown, for tests and debugging: { {rank, name, tier, time}, ... }.
function Companions.PanelRows()
  local rows = {}
  for _, row in ipairs(panel and panel.rows or {}) do
    if row:IsShown() then
      rows[#rows + 1] = { rank = row.rank:GetText(), name = row.name:GetText(), tier = row.tier:GetText(),
                          time = row.time:GetText(), guid = row.guid }
    end
  end
  return rows
end

function Companions.Panel()
  return panel
end

-- The right-hand box: { title, tier, lines = { ... } } as shown, for tests and debugging.
function Companions.DetailText()
  local box = panel and panel.side
  if not box then
    return nil
  end
  local lines = {}
  for _, line in ipairs(box.lines) do
    if (line:GetText() or "") ~= "" then
      lines[#lines + 1] = line:GetText()
    end
  end
  return { title = box.title:GetText(), tier = box.tier:GetText(), lines = lines, shown = box:IsShown() }
end

Companions.OnChange(function()
  if Companions.WindowShown() then
    refresh()
  end
end)

-- In the main window's title bar, left of the options gear (2026-10-21; before: a side tab, which overlapped the emotes
-- in a short window): opens and closes the companions' window.
PlayerFrame.RegisterHeaderButton({
  key = "companions",
  icon = ICON,
  flareIcon = "social", -- FlareUI's own icon in its theme
  isOn = Companions.WindowShown,
  onClick = Companions.Toggle,
  tooltip = function(tooltip)
    tooltip:SetText(L.COMPANIONS)
    tooltip:AddLine(Companions.WindowShown() and L.COMPANIONS_CLOSE or L.COMPANIONS_HINT, 1, 1, 1, true)
  end,
})

-- Tooltip of a player -----------------------------------------------------------------------------------------------

-- Two lines for a known companion: "Bon ami · 12 h 40 ensemble", "23 groupe(s) · 17 % de votre temps de jeu".
function Companions.AddTooltipLines(tooltip)
  if ForeverSpeechDB and ForeverSpeechDB.companionsTooltip == false then -- option (2026-10-15)
    return false
  end
  if type(tooltip) ~= "table" or type(tooltip.GetUnit) ~= "function" then
    return false
  end
  local _, unit = tooltip:GetUnit()
  unit = H.NotSecret(unit) -- secret values (instances, combat: Forever) read as unknown (2026-10-21)
  local guid = unit and H.Safe(UnitGUID, unit)
  local entry = guid and Companions.Get(guid)
  if not entry then
    return false
  end
  local tier = Companions.Tier(guid)
  local first = string.format(L.COMPANION_TOGETHER, Companions.FormatDuration(entry.seconds))
  tooltip:AddLine((tier and tier.name .. " · " or "") .. first, 0.4, 0.78, 1)
  local second = string.format(L.COMPANION_GROUPS, entry.groups or 0)
  local share = Companions.Share(entry.seconds, Companions.Summary().total)
  if share then
    second = second .. " · " .. string.format(L.COMPANION_SHARE_PLAYED, share)
  end
  tooltip:AddLine(second, 0.8, 0.8, 0.8)
  return true
end

local processor, types = _G.TooltipDataProcessor, _G.Enum and _G.Enum.TooltipDataType
if processor and processor.AddTooltipPostCall and types and types.Unit then
  processor.AddTooltipPostCall(types.Unit, function(tooltip)
    if tooltip == _G.GameTooltip then
      Companions.AddTooltipLines(tooltip)
    end
  end)
  H.Trace("companions: tooltip hook TooltipDataProcessor")
elseif _G.GameTooltip and _G.GameTooltip.HookScript then
  pcall(_G.GameTooltip.HookScript, _G.GameTooltip, "OnTooltipSetUnit", function(tooltip)
    if Companions.AddTooltipLines(tooltip) then
      tooltip:Show() -- resized for the new lines
    end
  end)
  H.Trace("companions: tooltip hook OnTooltipSetUnit")
end
