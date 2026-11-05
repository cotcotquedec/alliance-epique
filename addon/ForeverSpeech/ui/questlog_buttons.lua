-- ForeverSpeech: play/stop buttons in the quest log (CLAUDE.md 9.4).
-- S4: the log is part of the map, WorldMapFrame > QuestMapFrame > QuestScrollFrame.Contents >
-- pooled quest rows carrying `questID`; QuestLogQuests_Update() refreshes the list and
-- QuestMapFrame_ShowQuestDetails(questID) opens a quest. QuestMapFrame.DetailsFrame is the Retail
-- name of the details panel: unverified on Forever, skipped when absent.
local H = ForeverSpeech

local QuestLog = {}
H.QuestLogButtons = QuestLog

local ROW_SIZE, DETAIL_SIZE = 14, 20
local ROW_OFFSET_X = -24 -- leave room for the tracked check mark on the right of a row

-- The quest area highlight (core/quest_area.lua): a gold bar on the title row.
local function highlight(row, questID)
  local bar = rawget(row, "ForeverSpeechArea")
  local on = questID ~= nil and H.QuestArea.Inside(questID)
  if not bar then
    if not on then
      return
    end
    bar = row:CreateTexture(nil, "BACKGROUND")
    bar:SetTexture("Interface\\QuestFrame\\UI-QuestTitleHighlight")
    bar:SetBlendMode("ADD")
    bar:SetVertexColor(1, 0.82, 0)
    bar:SetAlpha(0.6)
    bar:SetAllPoints(row)
    row.ForeverSpeechArea = bar
  end
  bar:SetShown(on)
end

-- Title rows and objective rows both carry `questID` (seen in-game): one button per quest, on its
-- topmost row, which is the title.
local function decorateRows()
  local contents = QuestScrollFrame and QuestScrollFrame.Contents
  if not contents then
    return
  end
  local best = {} -- questID -> { row, top }
  local rows = { contents:GetChildren() }
  for order, row in ipairs(rows) do
    local questID = tonumber(rawget(row, "questID"))
    if questID and row:IsShown() then
      local top = row:GetTop() or -order -- no layout yet: keep the first row
      if not best[questID] or top > best[questID].top then
        best[questID] = { row = row, top = top }
      end
    end
  end
  local decorated = 0
  for _, row in ipairs(rows) do
    local questID = tonumber(rawget(row, "questID"))
    local b = rawget(row, "ForeverSpeechToggle")
    if questID and best[questID] and best[questID].row == row then
      if not b then
        b = H.PlayerFrame.MakeToggleButton(row, ROW_SIZE)
        b:SetPoint("RIGHT", row, "RIGHT", ROW_OFFSET_X, 0)
        b:SetFrameLevel((row:GetFrameLevel() or 0) + 5)
        row.ForeverSpeechToggle = b
      end
      b:SetQuest(questID)
      highlight(row, questID)
      decorated = decorated + 1
    else
      if b then
        b:Hide()
      end
      highlight(row, nil)
    end
  end
  H.Trace("questlog: rows decorated=%s", decorated)
end
QuestLog.DecorateRows = decorateRows

H.QuestArea.OnChange(function()
  if QuestScrollFrame and QuestScrollFrame:IsVisible() then
    decorateRows()
  end
end)

local detailButton

local function decorateDetails(questID)
  local details = QuestMapFrame and QuestMapFrame.DetailsFrame
  questID = tonumber(questID)
  H.Trace("questlog: details quest=%s DetailsFrame=%s", questID, details ~= nil)
  if questID then -- the window follows the quest opened (2026-10-21)
    H.PlayerFrame.ShowClicked(questID, "questlog")
  end
  if not details or not questID then
    return
  end
  if not detailButton then
    detailButton = H.PlayerFrame.MakeToggleButton(details, DETAIL_SIZE)
    detailButton:SetPoint("TOPRIGHT", details, "TOPRIGHT", -8, -8)
    detailButton:SetFrameLevel((details:GetFrameLevel() or 0) + 10)
  end
  detailButton:SetQuest(questID)
end
QuestLog.DecorateDetails = decorateDetails

H.WhenAvailable(function()
  return type(QuestLogQuests_Update) == "function"
end, function()
  hooksecurefunc("QuestLogQuests_Update", decorateRows)
  H.Trace("questlog: row hook installed")
end)

H.WhenAvailable(function()
  return type(QuestMapFrame_ShowQuestDetails) == "function"
end, function()
  hooksecurefunc("QuestMapFrame_ShowQuestDetails", decorateDetails)
  H.Trace("questlog: details hook installed")
end)
