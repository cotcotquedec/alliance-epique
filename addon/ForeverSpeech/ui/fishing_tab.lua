-- ForeverSpeech: the fishing tab (2026-10-13), a side tab (ui/side_tabs.lua) over the fishing mode
-- (core/fishing.lua); on the backpack's bar since 2026-10-20 (ui/bag_tabs.lua: above Disenchant), no longer the
-- main window's: shown with the backpack. Click: fishing mode on (pole equipped, weapons remembered); click again:
-- weapons back. Fishing itself is cast from the player's action bars. Locked in combat (greyed, tooltip says why).
-- Shown only to a character who knows Fishing and has a pole (bags or hand), and always while fishing mode is on (to
-- get the weapons back).
local H = ForeverSpeech
local L = H.L
local Fishing = H.Fishing

local ICON = H.MEDIA .. "tabs\\fishing" -- painted for the addon (2026-10-15, tools/tab_icons.sh; T30)

H.SideTabs.Register({
  key = "fishing",
  bar = "bag",
  icon = ICON,
  isOn = Fishing.IsOn,
  shown = function() -- always while fishing mode is on (to get the weapons back), else per the option (2026-10-15)
    local wanted = not ForeverSpeechDB or ForeverSpeechDB.fishingTab ~= false
    return Fishing.IsOn() or (wanted and Fishing.SpellID() ~= nil and Fishing.HasPole())
  end,
  locked = Fishing.InCombat,
  onClick = Fishing.ToggleAndReport,
  tooltip = function(tooltip)
    tooltip:SetText(L.FISHING)
    if Fishing.IsOn() then
      tooltip:AddLine(L.FISHING_ON, 0.4, 1, 0.4)
      tooltip:AddLine(L.FISHING_CLICK_OFF, 1, 1, 1, true)
    else
      tooltip:AddLine(L.FISHING_CLICK_ON, 1, 1, 1, true)
    end
  end,
})

Fishing.OnChange(H.SideTabs.Update)
