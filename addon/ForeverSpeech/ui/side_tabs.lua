-- ForeverSpeech: side tabs (2026-10-13), small square buttons stuck to the left edge of the main window, outside it,
-- (2026-10-21: the companions moved to the window's header, the quick emotes to the emote wheel: the main window's
-- edge is empty, the mechanism stays for the backpack's bar)
-- as the spellbook's side tabs; its tooltip says what a click does. Two kinds: a switch (isOn), greyed while off,
-- lit with a golden frame while on, at the top of the edge; an action (no isOn: a quick emote), always lit, at the
-- bottom of the edge (group "bottom"). The tabs live with the window: shown with it, hidden with it.
-- Several bars (2026-10-18): the main window's ("main", the default) and the backpack's ("bag", ui/bag_tabs.lua); a
-- tab names its bar (def.bar), a bar is attached to its frame (Attach), and may move to another frame (Attach again).
-- A secure tab (def.secure, 2026-10-18: the backpack's Disenchant): a SecureActionButtonTemplate button whose click
-- the game runs (its attributes: def.secure), def.onClick after it (PostClick). It is parented to UIParent and placed
-- at its bar's screen position, never anchored to it: a protected frame anchored to a game frame makes that frame
-- protected (seen on Forever, H18: the combined bag) and the game could no longer close it in combat. Taken away when
-- combat starts (PLAYER_REGEN_DISABLED runs before the lockdown), back after it. They follow their bar wherever it
-- moves, whoever moves it (2026-11-05: FlareUI's Move Any Frame drags the bag by its own handle, not the addon's):
-- each frame, a bar's screen place is compared with where its secure tabs were put.
-- Unverified on Forever: the spellbook tab art (Interface\SpellBook\SpellBook-SkillLineTab, mirrored for the left
-- side); without it, the icon alone.
local H = ForeverSpeech

local SideTabs = {}
H.SideTabs = SideTabs

local TAB_SIZE, TAB_GAP, TOP, BOTTOM = 32, 14, 44, 16 + 28 -- the bottom group's margin (it cleared the money band)
local TAB_ART = "Interface\\SpellBook\\SpellBook-SkillLineTab"

local defs = {} -- in order: { key, icon, tooltip(GameTooltip), isOn(), shown(), locked(), onClick(), group, bar }
local bars = {} -- bar key → the bar frame (its tabs in bar.tabs, by the index of their def)
local owners = {} -- bar key → the frame it is attached to
local margins = {} -- bar key → { top, bottom }: the edge's margins it was attached with
local hookedFrames = {} -- frames whose OnShow updates the tabs
local placedAt = {} -- bar key → { right, top, scale } of the bar when its secure tabs were placed

-- def: key, icon, tooltip(fn(tooltip)), onClick(fn); optional isOn(fn) (a switch; without it, an action), shown(fn),
-- locked(fn) (greyed, click ignored, tooltip says combat), dimmed(fn) (greyed, the click still acts: 2026-11-05, a
-- profession whose place is not nearby), group ("bottom": at the bottom of the edge, the first registered on top), bar
-- ("main" by default, or "bag"), secure (attributes of a secure tab).
function SideTabs.Register(def)
  def.bar = def.bar or "main"
  defs[#defs + 1] = def
  SideTabs.Update()
end

local function showTooltip(tab)
  if not GameTooltip then
    return
  end
  GameTooltip:SetOwner(tab, "ANCHOR_LEFT")
  tab.def.tooltip(GameTooltip)
  if tab.def.locked and tab.def.locked() then
    GameTooltip:AddLine(H.L.SIDE_TAB_COMBAT, 1, 0.3, 0.3)
  end
  GameTooltip:Show()
end

local function inCombat()
  return InCombatLockdown and InCombatLockdown() and true or false
end

local function newTab(def, bar)
  local tab
  if def.secure then
    tab = CreateFrame("Button", nil, UIParent, "SecureActionButtonTemplate")
    tab:RegisterForClicks("AnyUp", "AnyDown") -- the template acts on one of them, per ActionButtonUseKeyDown
    for k, v in pairs(def.secure) do
      tab:SetAttribute(k, v)
    end
  else
    tab = CreateFrame("Button", nil, bar)
  end
  tab.def = def
  tab:SetSize(TAB_SIZE, TAB_SIZE)
  local art = tab:CreateTexture(nil, "BACKGROUND")
  art:SetSize(64, 64)
  art:SetPoint("TOPRIGHT", tab, "TOPRIGHT", 3, 11) -- the spellbook's TOPLEFT -3, 11, mirrored
  art:SetTexture(TAB_ART)
  art:SetTexCoord(1, 0, 0, 1)
  tab.icon = tab:CreateTexture(nil, "ARTWORK")
  tab.icon:SetAllPoints()
  tab.icon:SetTexture(def.icon)
  tab.checked = tab:CreateTexture(nil, "OVERLAY")
  tab.checked:SetAllPoints()
  tab.checked:SetTexture("Interface\\Buttons\\CheckButtonHilight")
  tab.checked:SetBlendMode("ADD")
  local hl = tab:CreateTexture(nil, "HIGHLIGHT")
  hl:SetAllPoints()
  hl:SetTexture("Interface\\Buttons\\ButtonHilight-Square")
  hl:SetBlendMode("ADD")
  tab:SetScript(def.secure and "PostClick" or "OnClick", function(self, button, down)
    if self.def.locked and self.def.locked() then
      return
    end
    self.def.onClick(button, down)
    SideTabs.Update()
    if GameTooltip and GameTooltip:IsOwned(self) then
      showTooltip(self)
    end
  end)
  tab:SetScript("OnEnter", showTooltip)
  tab:SetScript("OnLeave", function()
    if GameTooltip then
      GameTooltip:Hide()
    end
  end)
  return tab
end

-- Puts a bar on the left edge of f (PlayerFrame calls it once for "main", when it builds the window; the bag tabs
-- call it for "bag" each time the backpack's frame shows). top, bottom: the edge's margins (default: the main
-- window's, below its title, above its footer). Again with another frame: the bar and its tabs move to it.
function SideTabs.Attach(f, key, top, bottom)
  key = key or "main"
  local bar = bars[key]
  if not bar then
    bar = CreateFrame("Frame", nil, f)
    bar:SetWidth(TAB_SIZE)
    bar.tabs = {}
    bars[key] = bar
  end
  if owners[key] ~= f then
    owners[key] = f
    bar:SetParent(f)
    bar:ClearAllPoints()
    bar:SetPoint("TOPRIGHT", f, "TOPLEFT", 0, -(top or TOP))
    bar:SetPoint("BOTTOMRIGHT", f, "BOTTOMLEFT", 0, bottom or BOTTOM)
    margins[key] = { top or TOP, bottom or BOTTOM }
    if not hookedFrames[f] then
      hookedFrames[f] = true
      f:HookScript("OnShow", SideTabs.Update)
      f:HookScript("OnHide", SideTabs.Update) -- a secure tab is not its child: it leaves with it
    end
  end
  bar:Show()
  SideTabs.Update()
  return bar
end

-- The least height of the frame a bar is attached to, for its shown tabs to fit without overlapping (2026-10-21: the
-- compact window was shorter than its emotes): the edge's margins, each group's tabs and gaps, a gap between groups.
function SideTabs.MinHeight(key)
  key = key or "main"
  local top, bottom = 0, 0
  for _, def in ipairs(defs) do
    if def.bar == key and (def.shown == nil or def.shown()) then
      if def.group == "bottom" then
        bottom = bottom + 1
      else
        top = top + 1
      end
    end
  end
  local function span(n)
    return n > 0 and n * TAB_SIZE + (n - 1) * TAB_GAP or 0
  end
  local m = margins[key] or { TOP, BOTTOM }
  return m[1] + m[2] + span(top) + span(bottom) + ((top > 0 and bottom > 0) and TAB_GAP or 0)
end

function SideTabs.Bar(key)
  return bars[key or "main"]
end

-- The frame a bar is attached to.
function SideTabs.Owner(key)
  return owners[key or "main"]
end

function SideTabs.Tab(key)
  for i, def in ipairs(defs) do
    if def.key == key then
      local bar = bars[def.bar]
      return bar and bar.tabs[i]
    end
  end
  return nil
end

local function place(def, i, bar, top, bottom)
  if def.secure and inCombat() then -- left alone (taken away when combat started)
    return
  end
  local tab = bar.tabs[i] or newTab(def, bar)
  bar.tabs[i] = tab
  if def.secure then
    tab:SetFrameStrata(bar:GetFrameStrata() or "MEDIUM")
    tab:SetFrameLevel((bar:GetFrameLevel() or 0) + 5)
  end
  if (def.shown == nil or def.shown()) and (not def.secure or bar:IsVisible()) then
    local on = (def.isOn == nil or def.isOn()) and true or false
    local locked = def.locked and def.locked() or false
    local dim = not on or locked or (def.dimmed ~= nil and def.dimmed()) or false
    tab.icon:SetDesaturated(dim)
    tab.icon:SetAlpha(dim and 0.6 or 1)
    tab.checked:SetShown(on and def.isOn ~= nil)
    tab:Show()
    local group = def.group == "bottom" and bottom or top
    group[#group + 1] = tab
  else
    tab:Hide()
  end
end

-- A tab at its place on the bar's edge (point TOPRIGHT or BOTTOMRIGHT, y below or above it). A secure tab: the same
-- place in screen coordinates, at the bar's scale, relative to UIParent; hidden until the bar is laid out.
local function anchor(tab, bar, point, y)
  tab:ClearAllPoints()
  if not tab.def.secure then
    tab:SetPoint(point, bar, point, 0, y)
    return
  end
  local right = bar:GetRight()
  local edge = point == "TOPRIGHT" and bar:GetTop() or bar:GetBottom()
  local barScale, uiScale = bar:GetEffectiveScale(), UIParent:GetEffectiveScale()
  if not (right and edge and barScale and uiScale) or uiScale == 0 then
    tab:Hide()
    return
  end
  tab:SetScale(barScale / uiScale) -- the tab's own units are then the bar's: its offsets are the bar's coordinates
  tab:SetPoint(point, UIParent, "BOTTOMLEFT", right, edge + y)
end

-- The bar's screen place: its right edge, its top, its scale (nil before it is laid out).
local function screenPlace(bar)
  local right, top, scale = bar:GetRight(), bar:GetTop(), bar:GetEffectiveScale()
  if right and top and scale then
    return right, top, scale
  end
  return nil
end

-- Places the shown tabs of every bar, the switches from the top, the actions from the bottom; each with its look.
local function updateBar(key, bar)
  local top, bottom = {}, {}
  for i, def in ipairs(defs) do
    if def.bar == key then
      place(def, i, bar, top, bottom)
      bar.hasSecure = bar.hasSecure or def.secure ~= nil
    end
  end
  local right, upper, scale = screenPlace(bar)
  placedAt[key] = right and { right, upper, scale } or nil
  for i, tab in ipairs(top) do
    anchor(tab, bar, "TOPRIGHT", -(i - 1) * (TAB_SIZE + TAB_GAP))
  end
  for i, tab in ipairs(bottom) do
    anchor(tab, bar, "BOTTOMRIGHT", (#bottom - i) * (TAB_SIZE + TAB_GAP))
  end
end

function SideTabs.Update()
  for key, bar in pairs(bars) do
    updateBar(key, bar)
  end
end

-- Combat starts: the secure tabs leave their bars until it ends.
local function detachSecure()
  if inCombat() then
    return
  end
  for _, bar in pairs(bars) do
    for i, tab in pairs(bar.tabs) do
      if defs[i] and defs[i].secure then
        tab:Hide()
        tab:ClearAllPoints()
      end
    end
  end
end

-- True when the bar is no longer where its secure tabs were put (a twentieth of a pixel or more).
local function moved(key, bar)
  local right, top, scale = screenPlace(bar)
  local at = placedAt[key]
  if not (right and at) then
    return (right ~= nil) ~= (at ~= nil)
  end
  return math.abs(right - at[1]) > 0.05 or math.abs(top - at[2]) > 0.05 or math.abs(scale - at[3]) > 0.0005
end

local follow = CreateFrame("Frame")
follow:SetScript("OnUpdate", function()
  if inCombat() then -- the secure tabs are away until it ends
    return
  end
  for key, bar in pairs(bars) do
    if bar.hasSecure and bar:IsVisible() and moved(key, bar) then
      updateBar(key, bar)
    end
  end
end)

H.TryRegisterEvent("PLAYER_REGEN_DISABLED", detachSecure)
H.TryRegisterEvent("PLAYER_REGEN_ENABLED", SideTabs.Update)
