-- ForeverSpeech: dumps the client's API documentation, to verify a signature on Forever instead of assuming it
-- (CLAUDE.md §2). What is left of the phase-0 spike helpers (dev/spikes.lua, removed on 2026-10-07: see docs/spikes/
-- and the git history).
--   /fs api        stores every function and event signature in ForeverSpeechDB.api (on disk after /reload)
--   /fs api show   the stored lines in a copy box
local H = ForeverSpeech

local function loadDocs()
  if not (APIDocumentation and APIDocumentation.systems) then
    local load = (C_AddOns and C_AddOns.LoadAddOn) or LoadAddOn
    if type(load) == "function" then
      for _, name in ipairs({ "Blizzard_APIDocumentation", "Blizzard_APIDocumentationGenerated" }) do
        pcall(load, name)
      end
    end
  end
  return APIDocumentation and type(APIDocumentation.systems) == "table" and APIDocumentation or nil
end

local function signature(fields)
  local out = {}
  for _, field in ipairs(fields or {}) do
    out[#out + 1] = tostring(field.Name) .. ":" .. tostring(field.Type) .. (field.Nilable and "?" or "")
  end
  return table.concat(out, ", ")
end

local function dump()
  local docs = loadDocs()
  if not docs then
    H.Print("API documentation unavailable")
    return
  end
  local lines = {}
  for _, system in ipairs(docs.systems) do
    local ns = system.Namespace or system.Name or "?"
    for _, fn in ipairs(system.Functions or {}) do
      lines[#lines + 1] = string.format("fn %s.%s(%s) -> %s", ns, tostring(fn.Name),
        signature(fn.Arguments), signature(fn.Returns))
    end
    for _, ev in ipairs(system.Events or {}) do
      lines[#lines + 1] = string.format("ev %s(%s)", tostring(ev.LiteralName or ev.Name), signature(ev.Payload))
    end
  end
  ForeverSpeechDB.api = lines
  H.Print("stored %s API lines (%s systems). /reload to write them to disk.", #lines, #docs.systems)
end

local copyFrame

local function show(text)
  if not copyFrame then
    local f = CreateFrame("Frame", nil, UIParent)
    f:SetSize(640, 420)
    f:SetPoint("CENTER")
    f:SetFrameStrata("DIALOG")
    local bg = f:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints()
    bg:SetColorTexture(0, 0, 0, 0.9)
    local close = CreateFrame("Button", nil, f, "UIPanelCloseButton")
    close:SetPoint("TOPRIGHT")
    local scroll = CreateFrame("ScrollFrame", nil, f, "UIPanelScrollFrameTemplate")
    scroll:SetPoint("TOPLEFT", 10, -30)
    scroll:SetPoint("BOTTOMRIGHT", -30, 10)
    local edit = CreateFrame("EditBox", nil, scroll)
    edit:SetMultiLine(true)
    edit:SetMaxLetters(0)
    edit:SetFontObject(ChatFontNormal)
    edit:SetWidth(590)
    edit:SetAutoFocus(false)
    edit:SetScript("OnEscapePressed", function()
      f:Hide()
    end)
    scroll:SetScrollChild(edit)
    f.edit = edit
    copyFrame = f
  end
  copyFrame.edit:SetText(text)
  copyFrame:Show()
  copyFrame.edit:SetFocus()
  copyFrame.edit:HighlightText()
end

H.RegisterCommand("api", function(arg)
  if arg == "show" then
    show(table.concat(ForeverSpeechDB.api or { "nothing stored: /fs api" }, "\n"))
  else
    dump()
  end
end, "api [show] - store the client's API signatures (ForeverSpeechDB.api), or show them")

H.OnInit(function()
  ForeverSpeechDB.spikes = nil -- phase-0 spike logs (results in docs/spikes/)
  -- in-game checks H15 and H16 of 2026-10-18 (results in docs/ingame/queue.md)
  ForeverSpeechDB.h15, ForeverSpeechDB.h16, ForeverSpeechDB.zonetest = nil, nil, nil
  ForeverSpeechDB.h18 = nil -- in-game check H18 of 2026-10-18 (/fs bagtest, removed)
end)
