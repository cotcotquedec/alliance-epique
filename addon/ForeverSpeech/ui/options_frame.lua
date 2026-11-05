-- ForeverSpeech: the options window (2026-10-15), apart from the main window: the settings sorted by theme, the
-- themes listed on the left, the chosen theme's settings on the right. Opened by the main window's gear, a right
-- click on the minimap icon, /fs options (and instead of the main window while the audio is off). Movable, its
-- position and its last theme kept. The same frame as the main window (PortraitFrameTemplate, else a tooltip
-- backdrop: PlayerFrame.Kit). No Escape to close it: that needs a named frame, and the addon owns one global only.
-- Unverified on Forever: the theme icons (Classic icons).
-- 2026-10-21: in the game's own options (Escape > Options > AddOns > Alliance Épique), when the client has the
-- Settings API (Retail's, as Spoken uses on Forever): the addon's category (H.TITLE) holding the General theme, a
-- subcategory for each other theme, each a canvas with the same widgets. The gear, a right click on the minimap icon
-- and /fs options open it on the theme asked (or the last one). Without the API, the addon's own window as before.
-- Not in combat (the game's options panel cannot open then). Unverified on Forever: T46.
local H = ForeverSpeech
local L = H.L
local PlayerFrame = H.PlayerFrame
local Kit = PlayerFrame.Kit

local Options = {}
H.Options = Options

local WIDTH, HEIGHT, NAV_WIDTH, NAV_ROW = 620, 470, 180, 30
local TOP = 30 -- below the title bar
local ROW_GAP = 10

local frame -- built on first use
local widgets = {} -- every widget with refresh(), all pages

local function db(key, after)
  return function()
    return ForeverSpeechDB[key]
  end, function(value)
    ForeverSpeechDB[key] = value
    if after then
      after(value)
    end
  end
end

-- A setting that defaults to on (nil counts as on).
local function on(key, after)
  return function()
    return ForeverSpeechDB[key] ~= false
  end, function(value)
    ForeverSpeechDB[key] = value
    if after then
      after(value)
    end
  end
end

local function sideTabs()
  if H.SideTabs then
    H.SideTabs.Update()
  end
end

local function mapButton()
  if H.MapButton then
    H.MapButton.Update()
  end
end

local GAPS = { { 0, L.GAP_NONE } }
for _, s in ipairs({ 1, 2, 3, 5 }) do
  GAPS[#GAPS + 1] = { s, string.format(L.GAP_SECONDS, s) }
end

-- The themes and their settings, in order. Items: check (label, get, set, strong), cycle (label, values, get, set),
-- action (label, run), info (text()).
local PAGES = {
  { key = "general", title = L.OPT_PAGE_GENERAL, icon = "Interface\\Icons\\INV_Misc_Note_01", items = {
    { kind = "check", label = L.OPT_ENABLED, strong = true, get = H.IsEnabled, set = H.SetEnabled,
      hint = function() return not H.IsEnabled() and L.OPT_ENABLED_OFF or nil end },
    { kind = "check", label = L.OPT_OPEN_ON_PLAY, db = { "openOnPlay" } },
    { kind = "check", label = L.OPT_FOLLOW_TRACKED, db = { "followTracked" } },
    { kind = "check", label = L.OPT_SHOW_LIST, db = { "showList", function() PlayerFrame.UpdateList() end } },
    { kind = "check", label = L.OPT_READ_IN_BG, db = { "readInBattleground" } }, -- 2026-10-21, core/silence.lua
    { kind = "check", label = L.OPT_MINIMAP,
      get = function() return not ForeverSpeechDB.minimapHide end,
      set = function(value)
        ForeverSpeechDB.minimapHide = not value
        if H.MinimapButton then
          H.MinimapButton.Update()
        end
      end },
  } },
  { key = "reading", title = L.OPT_PAGE_READING, icon = "Interface\\Icons\\INV_Misc_Book_09", items = {
    { kind = "check", label = L.OPT_AUTOPLAY, db = { "autoplay" } },
    { kind = "check", label = L.OPT_PAGE_SOUND, db = { "pageSound" } },
    { kind = "check", label = L.OPT_MUTE_GAME_VOICES, db = { "muteGameVoices", function() H.GameVoices.Update() end } },
    -- 2026-10-21: ducking (core/ducking.lua), books (core/books.lua), NPC dialogues (core/dialogues.lua)
    { kind = "check", label = L.OPT_DUCK, on = { "duck", function(value) H.Ducking.SetEnabled(value) end } },
    { kind = "check", label = L.OPT_READ_BOOKS, on = { "readBooks" } },
    { kind = "check", label = L.OPT_READ_GOSSIP, on = { "readGossip", function() H.GameVoices.Update() end } },
    { kind = "cycle", label = L.OPT_GAP, values = GAPS, db = { "gap" } },
    { kind = "cycle", label = L.OPT_FALLBACK, db = { "fallback" },
      values = { { "tts", L.FALLBACK_TTS }, { "test", L.FALLBACK_TEST }, { "none", L.FALLBACK_NONE } } },
    { kind = "cycle", label = L.OPT_CHANNEL, db = { "channel" },
      values = { { "Dialog", "Dialog" }, { "Master", "Master" }, { "SFX", "SFX" } } },
  } },
  { key = "window", title = L.OPT_PAGE_WINDOW, icon = "Interface\\Icons\\INV_Misc_Note_02", items = {
    { kind = "check", label = L.OPT_SHOW_TEXT, db = { "showText", function() PlayerFrame.RefreshQuestText() end } },
    { kind = "check", label = L.OPT_SHOW_QUEST_LEVEL,
      on = { "showQuestLevel", function() PlayerFrame.UpdateQuestLevel() end } },
    { kind = "check", label = L.OPT_DOCK_FLARE, db = { "dockFlare", function() PlayerFrame.Redock() end } },
    { kind = "cycle", label = L.OPT_ZOOM, db = { "modelZoom", function() PlayerFrame.ApplyZoom() end },
      values = { { 0, L.ZOOM_BODY }, { 0.3, L.ZOOM_BUST }, { 0.6, L.ZOOM_HEAD }, { 1, L.ZOOM_FACE } } },
  } },
  { key = "elise", title = L.OPT_PAGE_ELISE, icon = "Interface\\Icons\\Spell_Holy_ElunesGrace", items = {
    { kind = "check", label = L.OPT_ZONE_INTROS, db = { "zoneIntros" } },
    { kind = "check", label = L.OPT_LEVEL_LINES, db = { "levelLines" } },
    { kind = "check", label = L.OPT_COMPANION_LINES, db = { "companionLines" } },
    { kind = "action", label = L.OPT_FORGET_ZONES, run = function()
      H.Zones.Forget()
      mapButton()
      return L.OPT_FORGET_DONE
    end },
  } },
  { key = "companions", title = L.OPT_PAGE_COMPANIONS, icon = "Interface\\Icons\\Spell_Holy_PrayerOfFortitude",
    items = {
      { kind = "check", label = L.OPT_COMPANIONS_TRACK,
        on = { "companionsTrack", function() H.Companions.Update() end } },
      { kind = "check", label = L.OPT_COMPANIONS_TOOLTIP, on = { "companionsTooltip" } },
      { kind = "check", label = L.OPT_COMPANIONS_CHAT, on = { "companionsChat" } },
    } },
  { key = "comfort", title = L.OPT_PAGE_COMFORT, icon = "Interface\\Icons\\Trade_Fishing", items = {
    { kind = "check", label = L.OPT_FISHING_TAB, on = { "fishingTab", sideTabs } },
    { kind = "check", label = L.OPT_EMOTE_WHEEL, on = { "emoteWheel" } },
    { kind = "binding", label = L.OPT_EMOTE_WHEEL_KEY, command = "FOREVERSPEECH_EMOTEWHEEL" },
    { kind = "check", label = L.OPT_PROFESSION_TABS, on = { "professionTabs", sideTabs } },
    { kind = "check", label = L.OPT_FADE_MOVE, on = { "fadeOnMove", function(value) H.Fade.SetEnabled(value) end } },
    { kind = "check", label = L.OPT_DISENCHANT_TAB, on = { "disenchantTab", sideTabs } },
    { kind = "check", label = L.OPT_BAG_ROWS, on = { "bagRows", function(value) H.BagFrame.SetRows(value) end } },
    { kind = "action", label = L.OPT_BAG_RESET, run = function()
      H.BagFrame.Reset()
      return L.BAG_RESET_DONE
    end },
    { kind = "check", label = L.OPT_MAP_BUTTON, on = { "mapButton", mapButton } },
    { kind = "check", label = L.OPT_MAP_PANEL, on = { "mapPanel", mapButton } },
    { kind = "check", label = L.OPT_QUEST_AREA, on = { "questAreaHighlight", function() H.QuestArea.Refresh() end } },
    { kind = "check", label = L.OPT_SORT_BY_LEVEL, on = { "sortByLevel", function() H.QuestSort.Schedule() end } },
    { kind = "cycle", label = L.OPT_SORT_ORDER, db = { "sortOrder", function() H.QuestSort.Schedule() end },
      values = { { "asc", L.SORT_ASC_SHORT }, { "desc", L.SORT_DESC_SHORT } } },
    { kind = "check", label = L.OPT_ANNOUNCE, on = { "announceComplete" } },
    { kind = "cycle", label = L.OPT_ANNOUNCE_CHANNEL, db = { "announceChannel" },
      values = { { "party", L.ANNOUNCE_PARTY }, { "say", L.ANNOUNCE_SAY } } },
  } },
  { key = "advanced", title = L.OPT_PAGE_ADVANCED, icon = "Interface\\Icons\\INV_Misc_Gear_01", items = {
    { kind = "check", label = L.OPT_DEBUG, db = { "debug", function() PlayerFrame.UpdateDebugBar() end } },
    { kind = "action", label = L.OPT_RESET, confirm = true, run = function()
      H.ResetSettings()
      Options.ApplyAll()
      return L.OPT_RESET_DONE
    end },
    { kind = "info", text = function() return string.format(L.OPT_INFO, H.version, H.Capture.Count()) end },
  } },
}

-- Every page's after-change functions, once (after a reset: each feature reads its settings again).
function Options.ApplyAll()
  for _, page in ipairs(PAGES) do
    for _, item in ipairs(page.items) do
      local spec = item.db or item.on
      if spec and spec[2] then
        pcall(spec[2], ForeverSpeechDB[spec[1]])
      end
    end
  end
  for _, fn in ipairs({ sideTabs, mapButton, H.MinimapButton and H.MinimapButton.Update, H.GameVoices.Update }) do
    if fn then
      pcall(fn)
    end
  end
  Options.Refresh()
end

-- Widgets ----------------------------------------------------------------------------------------------------------

local function accessors(item)
  if item.db then
    return db(item.db[1], item.db[2])
  elseif item.on then
    return on(item.on[1], item.on[2])
  end
  return item.get, item.set
end

local function checkbox(parent, item)
  local get, set = accessors(item)
  local cb, templated = Kit.create("CheckButton", parent, "UICheckButtonTemplate")
  cb:SetSize(24, 24)
  if H.Style.CheckButton(cb) then -- the game's minimal check box (2026-10-21), a little smaller
    cb:SetSize(20, 20)
  elseif not templated then
    cb:SetNormalTexture("Interface\\Buttons\\UI-CheckBox-Up")
    cb:SetPushedTexture("Interface\\Buttons\\UI-CheckBox-Down")
    cb:SetHighlightTexture("Interface\\Buttons\\UI-CheckBox-Highlight")
    cb:SetCheckedTexture("Interface\\Buttons\\UI-CheckBox-Check")
  end
  cb.label = cb:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
  cb.label:SetPoint("LEFT", cb, "RIGHT", 4, 0)
  cb.label:SetText(item.strong and ("|cffffd200" .. item.label .. "|r") or item.label)
  cb:SetScript("OnClick", function(self)
    set(self:GetChecked() and true or false)
    Options.Refresh()
  end)
  local hint -- a local: a missing field of a frame is not nil in every client
  if item.hint then
    hint = parent:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    hint:SetPoint("TOPLEFT", cb, "BOTTOMLEFT", 28, 0)
  end
  cb.refresh = function()
    cb:SetChecked(get() and true or false)
    if hint then
      hint:SetText(item.hint() or "")
    end
  end
  cb.height = item.hint and 36 or 24
  return cb
end

local function cycle(parent, item)
  local get, set = accessors(item)
  local holder = CreateFrame("Frame", nil, parent)
  holder:SetSize(WIDTH - NAV_WIDTH - 40, 24)
  holder.label = holder:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
  holder.label:SetPoint("LEFT", 4, 0)
  holder.label:SetText(item.label)
  local b = Kit.button(holder, "", 150)
  b:SetPoint("RIGHT", holder, "RIGHT", 0, 0)
  holder.button = b
  local function labelOf(value)
    for _, v in ipairs(item.values) do
      if v[1] == value then
        return v[2]
      end
    end
    return tostring(value)
  end
  b:SetScript("OnClick", function()
    local current, nextIndex = get(), 1
    for i, v in ipairs(item.values) do
      if v[1] == current then
        nextIndex = i % #item.values + 1
      end
    end
    set(item.values[nextIndex][1])
    holder.refresh()
  end)
  holder.refresh = function()
    b:SetText(labelOf(get()))
  end
  holder.height = 24
  return holder
end

-- A button; with confirm, the first click asks ("Confirmer ?") and the second runs. What run returns is printed.
local function action(parent, item)
  local b = Kit.button(parent, item.label, 220)
  local armed = false
  b:SetScript("OnClick", function(self)
    if item.confirm and not armed then
      armed = true
      self:SetText(L.OPT_RESET_CONFIRM)
      C_Timer.After(4, function()
        armed = false
        self:SetText(item.label)
      end)
      return
    end
    armed = false
    self:SetText(item.label)
    local said = item.run()
    if said then
      H.Print("%s", said)
    end
  end)
  b.refresh = function() end
  b.height = 22
  return b
end

local function info(parent, item)
  local fs = parent:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
  fs:SetJustifyH("LEFT")
  fs.refresh = function()
    fs:SetText(item.text())
  end
  fs.height = 14
  return fs
end

-- A key binding (2026-10-21): its key on a button; a click waits for a key (with its modifiers) or a mouse button,
-- Escape cancels; a right click removes it. SetBinding then SaveBindings, never in combat. A gamepad button: the game's
-- own key binding panel (catching one needs EnableGamePadButton, protected on Forever).
local MODIFIER_KEYS = { LSHIFT = true, RSHIFT = true, LCTRL = true, RCTRL = true, LALT = true, RALT = true,
  LMETA = true, RMETA = true, UNKNOWN = true }
local MOUSE_KEYS = { MiddleButton = "BUTTON3", Button4 = "BUTTON4", Button5 = "BUTTON5" }

local function bindingKey(key)
  local prefix = ""
  if IsAltKeyDown and IsAltKeyDown() then
    prefix = prefix .. "ALT-"
  end
  if IsControlKeyDown and IsControlKeyDown() then
    prefix = prefix .. "CTRL-"
  end
  if IsShiftKeyDown and IsShiftKeyDown() then
    prefix = prefix .. "SHIFT-"
  end
  return prefix .. key
end

local function saveBindings()
  if SaveBindings then
    pcall(SaveBindings, GetCurrentBindingSet and GetCurrentBindingSet() or 1)
  end
end

local function currentKeys(command)
  if not GetBindingKey then
    return {}
  end
  return { GetBindingKey(command) }
end

-- Binds key to command alone (its other keys removed). Returns ok, the action the key had before.
function Options.Bind(command, key)
  if InCombatLockdown and InCombatLockdown() then
    H.Print(L.BIND_COMBAT)
    return false
  end
  local before = GetBindingAction and GetBindingAction(key) or ""
  for _, old in ipairs(currentKeys(command)) do
    SetBinding(old)
  end
  local ok = SetBinding(key, command)
  if not ok then
    H.Print(L.BIND_FAILED, key)
    return false
  end
  saveBindings()
  if before ~= "" and before ~= command then
    local name = _G["BINDING_NAME_" .. before] or before
    H.Print(L.BIND_REPLACED, key, name)
  else
    H.Print(L.BIND_SET, key)
  end
  return true, before
end

function Options.Unbind(command)
  if InCombatLockdown and InCombatLockdown() then
    H.Print(L.BIND_COMBAT)
    return false
  end
  for _, old in ipairs(currentKeys(command)) do
    SetBinding(old)
  end
  saveBindings()
  H.Print(L.BIND_CLEARED)
  return true
end

local function binding(parent, item)
  local holder = CreateFrame("Frame", nil, parent)
  holder:SetSize(WIDTH - NAV_WIDTH - 40, 36)
  holder.label = holder:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
  holder.label:SetPoint("TOPLEFT", 4, -5)
  holder.label:SetText(item.label)
  local hint = holder:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
  hint:SetPoint("TOPLEFT", holder.label, "BOTTOMLEFT", 0, -2)
  hint:SetPoint("RIGHT", holder, "RIGHT", -156, 0)
  hint:SetJustifyH("LEFT")
  hint:SetText(L.BIND_HINT)
  local b = Kit.button(holder, "", 150)
  b:SetPoint("TOPRIGHT", holder, "TOPRIGHT", 0, 0)
  holder.button = b
  local waiting = false
  local function stop()
    waiting = false
    if b.EnableKeyboard then
      b:EnableKeyboard(false)
    end
    holder.refresh()
  end
  local function take(key)
    stop()
    Options.Bind(item.command, key)
    holder.refresh()
  end
  if b.RegisterForClicks then
    b:RegisterForClicks("LeftButtonUp", "RightButtonUp")
  end
  b:SetScript("OnClick", function(_, mouse)
    if waiting then
      return
    end
    if mouse == "RightButton" then
      Options.Unbind(item.command)
      holder.refresh()
      return
    end
    if InCombatLockdown and InCombatLockdown() then
      H.Print(L.BIND_COMBAT)
      return
    end
    waiting = true
    b:SetText(L.BIND_PRESS)
    if b.EnableKeyboard then
      b:EnableKeyboard(true)
    end
  end)
  b:SetScript("OnKeyDown", function(_, key)
    if not waiting or MODIFIER_KEYS[key] then
      return
    end
    if key == "ESCAPE" then
      stop()
      return
    end
    take(bindingKey(key))
  end)
  b:SetScript("OnMouseDown", function(_, mouse)
    if waiting and MOUSE_KEYS[mouse] then
      take(bindingKey(MOUSE_KEYS[mouse]))
    end
  end)
  b:SetScript("OnHide", function()
    if waiting then
      stop()
    end
  end)
  holder.refresh = function()
    if waiting then
      return
    end
    local key = currentKeys(item.command)[1]
    b:SetText(key and (GetBindingText and GetBindingText(key) or key) or L.BIND_NONE)
  end
  holder.height = 36
  return holder
end

local BUILD = { check = checkbox, cycle = cycle, action = action, info = info, binding = binding }

local function buildPage(f, page, left, top)
  local p = CreateFrame("Frame", nil, f)
  p:SetPoint("TOPLEFT", f, "TOPLEFT", left or NAV_WIDTH + 16, -(top or TOP + 8))
  p:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -16, 12)
  local title = p:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
  title:SetPoint("TOPLEFT", 0, -4)
  title:SetText(page.title)
  local rule = p:CreateTexture(nil, "ARTWORK")
  rule:SetColorTexture(1, 1, 1, 0.15)
  rule:SetHeight(1)
  rule:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -8)
  rule:SetPoint("RIGHT", p, "RIGHT", 0, 0)
  p.widgets = {}
  local y = 40
  for _, item in ipairs(page.items) do
    local w = BUILD[item.kind](p, item)
    w:SetPoint("TOPLEFT", p, "TOPLEFT", 0, -y)
    if item.kind == "info" then
      w:SetPoint("RIGHT", p, "RIGHT", 0, 0)
    end
    y = y + w.height + ROW_GAP
    p.widgets[#p.widgets + 1] = w
    widgets[#widgets + 1] = w
  end
  p:Hide()
  return p
end

local function navButton(f, i, page)
  local b = CreateFrame("Button", nil, f)
  b:SetSize(NAV_WIDTH - 20, NAV_ROW - 2)
  b:SetPoint("TOPLEFT", f, "TOPLEFT", 12, -(TOP + 8 + (i - 1) * NAV_ROW))
  b.icon = b:CreateTexture(nil, "ARTWORK")
  b.icon:SetSize(20, 20)
  b.icon:SetPoint("LEFT", 4, 0)
  b.icon:SetTexture(page.icon)
  b.text = b:CreateFontString(nil, "OVERLAY", "GameFontNormal")
  b.text:SetPoint("LEFT", b.icon, "RIGHT", 8, 0)
  b.text:SetText(page.title)
  b.selected = b:CreateTexture(nil, "BACKGROUND")
  b.selected:SetAllPoints()
  b.selected:SetColorTexture(1, 0.82, 0, 0.18)
  local hl = b:CreateTexture(nil, "HIGHLIGHT")
  hl:SetAllPoints()
  hl:SetColorTexture(1, 1, 1, 0.08)
  b:SetScript("OnClick", function()
    Options.Show(page.key)
  end)
  return b
end

local function savePosition(f)
  local point, _, relativePoint, x, y = f:GetPoint(1)
  ForeverSpeechDB.optionsPos = { point = point, relativePoint = relativePoint, x = x, y = y }
end

local function build()
  local f, templated
  local portrait = _G.PortraitFrameMixin ~= nil
  if portrait then
    f, portrait = Kit.create("Frame", UIParent, "PortraitFrameTemplate")
  end
  if not portrait then
    f, templated = Kit.create("Frame", UIParent, "BackdropTemplate")
    Kit.backdrop(f, templated, 0.95)
    local close = CreateFrame("Button", nil, f, "UIPanelCloseButton")
    close:SetPoint("TOPRIGHT", -2, -2)
    local name = f:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    name:SetPoint("TOPLEFT", 12, -10)
    name:SetText(H.TITLE .. " · " .. L.OPTIONS)
  else
    Kit.dressPortrait(f, H.TITLE .. " · " .. L.OPTIONS)
  end
  H.Style.FlareWindow(f, "options") -- FlareUI's look while it runs (2026-11-05)
  f:SetSize(WIDTH, HEIGHT)
  f:SetFrameStrata("DIALOG")
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
  local pos = ForeverSpeechDB.optionsPos
  f:ClearAllPoints()
  if pos and pos.point then
    f:SetPoint(pos.point, UIParent, pos.relativePoint or pos.point, pos.x or 0, pos.y or 0)
  else
    f:SetPoint("CENTER", UIParent, "CENTER", 0, 40)
  end
  -- the theme list, with a line between it and the settings
  local sep = f:CreateTexture(nil, "ARTWORK")
  sep:SetColorTexture(1, 1, 1, 0.12)
  sep:SetWidth(1)
  sep:SetPoint("TOPLEFT", f, "TOPLEFT", NAV_WIDTH, -(TOP + 4))
  sep:SetPoint("BOTTOMLEFT", f, "BOTTOMLEFT", NAV_WIDTH, 12)
  H.Style.FlareLine(sep)
  f.nav, f.pages = {}, {}
  for i, page in ipairs(PAGES) do
    f.nav[page.key] = navButton(f, i, page)
    f.pages[page.key] = buildPage(f, page)
  end
  f:SetScript("OnShow", function()
    Options.Refresh()
    PlayerFrame.UpdateOptionsButton()
  end)
  f:SetScript("OnHide", PlayerFrame.UpdateOptionsButton)
  H.Trace("options: PortraitFrameTemplate=%s BackdropTemplate=%s", portrait, templated)
  H.Style.FlareTheme(f, "options") -- after the window's own scripts
  return f
end

-- The game's options (Settings API) ----------------------------------------------------------------------------------

local settings -- { categories = { [key] = category }, pages = { [key] = page } } once registered

-- Registers the themes in the game's options; nil when the client has no Settings API or refuses it.
local function registerSettings()
  local api = _G.Settings
  if not (api and api.RegisterCanvasLayoutCategory and api.RegisterCanvasLayoutSubcategory
      and api.RegisterAddOnCategory and api.OpenToCategory) then
    return nil
  end
  local made = { categories = {}, pages = {} }
  local ok, err = pcall(function()
    local root
    for _, page in ipairs(PAGES) do
      local canvas = CreateFrame("Frame")
      canvas:Hide()
      -- what the game's panel may call on a canvas: nothing to commit (each setting applies at once), refresh on show
      canvas.OnCommit = function() end
      canvas.OnDefault = function() end
      canvas.OnRefresh = Options.Refresh
      canvas:SetScript("OnShow", function()
        ForeverSpeechDB.optionsPage = page.key
        Options.Refresh()
      end)
      local p = buildPage(canvas, page, 16, 8)
      p:Show()
      made.pages[page.key] = p
      local category
      if not root then
        category = api.RegisterCanvasLayoutCategory(canvas, H.TITLE)
        api.RegisterAddOnCategory(category)
        root = category
      else
        category = api.RegisterCanvasLayoutSubcategory(root, canvas, page.title)
      end
      made.categories[page.key] = category
    end
  end)
  if not ok then
    H.Trace("options: Settings API refused (%s), own window", tostring(err))
    return nil
  end
  local panel = _G.SettingsPanel
  if panel and panel.HookScript then
    panel:HookScript("OnShow", PlayerFrame.UpdateOptionsButton)
    panel:HookScript("OnHide", PlayerFrame.UpdateOptionsButton)
  end
  H.Trace("options: in the game's options (Settings API), %d themes", #PAGES)
  return made
end

local function settingsShown()
  local panel = _G.SettingsPanel
  return panel ~= nil and panel:IsShown() == true
end

local function openSettings(key)
  if InCombatLockdown and InCombatLockdown() then
    H.Print(L.OPTIONS_IN_COMBAT)
    return
  end
  key = (key and settings.categories[key]) and key or ForeverSpeechDB.optionsPage or "general"
  if not settings.categories[key] then
    key = "general"
  end
  ForeverSpeechDB.optionsPage = key
  local category = settings.categories[key]
  local id = category.GetID and category:GetID() or category.ID
  _G.Settings.OpenToCategory(id)
  Options.Refresh()
end

local function closeSettings()
  local panel = _G.SettingsPanel
  if not settingsShown() then
    return
  end
  if HideUIPanel then
    HideUIPanel(panel)
  else
    panel:Hide()
  end
end

-- Public ------------------------------------------------------------------------------------------------------------

function Options.Refresh()
  for _, w in ipairs(widgets) do
    w.refresh()
  end
end

-- Shows a theme ("general", "reading", "window", "elise", "companions", "comfort", "advanced"; default: the last one).
function Options.Show(key)
  if settings then
    return openSettings(key)
  end
  frame = frame or build()
  key = (key and frame.pages[key]) and key or ForeverSpeechDB.optionsPage or "general"
  if not frame.pages[key] then
    key = "general"
  end
  ForeverSpeechDB.optionsPage = key
  for k, p in pairs(frame.pages) do
    p:SetShown(k == key)
    frame.nav[k].selected:SetShown(k == key)
    frame.nav[k].text:SetFontObject(k == key and "GameFontHighlight" or "GameFontNormal")
  end
  frame.page = key
  frame:Show()
  Options.Refresh()
  PlayerFrame.UpdateOptionsButton()
end

function Options.Open(key)
  Options.Show(key)
end

function Options.Toggle(key)
  if settings then
    if settingsShown() and (not key or ForeverSpeechDB.optionsPage == key) then
      closeSettings()
    else
      openSettings(key)
    end
    return
  end
  if frame and frame:IsShown() and (not key or frame.page == key) then
    frame:Hide()
  else
    Options.Show(key)
  end
end

function Options.Hide()
  if settings then
    return closeSettings()
  end
  if frame then
    frame:Hide()
  end
end

function Options.IsShown()
  if settings then
    return settingsShown()
  end
  return frame ~= nil and frame:IsShown()
end

-- True once the themes are in the game's options (Settings API).
function Options.InGameOptions()
  return settings ~= nil
end

-- The theme shown, and its page's widgets (tests and debugging).
function Options.Page()
  if settings then
    return settingsShown() and ForeverSpeechDB.optionsPage or nil
  end
  return frame and frame:IsShown() and frame.page or nil
end

function Options.Widgets(key)
  if settings then
    return settings.pages[key] and settings.pages[key].widgets or {}
  end
  return frame and frame.pages[key] and frame.pages[key].widgets or {}
end

H.OnInit(function()
  settings = settings or registerSettings()
end)

H.OnEnabledChange(function()
  if frame and frame:IsShown() then
    Options.Refresh()
  end
end)

H.RegisterCommand("options", function(arg)
  Options.Open(arg ~= "" and arg or nil)
end, "options [theme] - the options window")
