-- ForeverSpeech: Elise's zone introductions (2026-10-11). The first time the character sets foot in a zone, her
-- introduction of it goes in the play list (Player.PlayLine): on the ground only, never on a flight path (the
-- intro waits for the landing, in whatever zone the player lands). Automatic only once her audio exists (index v5,
-- zones[mapID].intro); before that, /fs zone reads her text with the client's speech synthesis.
-- A zone counts as seen once its introduction went in the play list: ForeverSpeechDB.zonesSeen[<character>][mapID].
-- The introduction waits until the character has spent STAY seconds in the zone (2026-10-15: at a character's first
-- login, the game's opening cinematic played over it): each new zone, login or landing starts the wait again, and a
-- cinematic or a movie still shown then delays it to its end (InCinematic, CinematicFrame, MovieFrame: unverified).
-- Unverified on Forever (spike S12, docs/ingame/queue.md): the zone events, C_Map.GetBestMapForUnit and its map IDs
-- (the Forever Database's uiMapId), UnitOnTaxi; the zone's name is the fallback when the map ID is unknown.
local H = ForeverSpeech

local Zones = {}
H.Zones = Zones

local STAY = 120         -- seconds in a zone (on the ground) before her introduction: an arrival, a login, a landing
local TAXI_POLL = 2      -- seconds between two looks while on a flight path (the landing event is unverified)
local CINEMATIC_POLL = 5 -- seconds between two looks while a cinematic or a movie plays
local MAP_TYPE_ZONE = 3  -- Enum.UIMapType.Zone; a city district, a cave or a building is a child map below it

local token = 0          -- cancels a scheduled check when a newer one is scheduled
local waitingLanding = false

local function character()
  local name = UnitName and UnitName("player") or "?"
  local realm = GetRealmName and GetRealmName() or "?"
  return tostring(name) .. "-" .. tostring(realm)
end

local function seenTable()
  ForeverSpeechDB.zonesSeen = ForeverSpeechDB.zonesSeen or {}
  local key = character()
  ForeverSpeechDB.zonesSeen[key] = ForeverSpeechDB.zonesSeen[key] or {}
  return ForeverSpeechDB.zonesSeen[key]
end

-- false before SavedVariables are loaded (the world map button looks at load time, 2026-10-14).
function Zones.Seen(mapID)
  if type(ForeverSpeechDB) ~= "table" then
    return false
  end
  return seenTable()[tonumber(mapID) or -1] ~= nil
end

function Zones.MarkSeen(mapID)
  seenTable()[tonumber(mapID)] = time and time() or true
end

-- Forgets the zones seen by this character (/fs zone reset): every introduction plays again on the next arrival.
function Zones.Forget()
  ForeverSpeechDB.zonesSeen = ForeverSpeechDB.zonesSeen or {}
  ForeverSpeechDB.zonesSeen[character()] = {}
end

-- The map of the zone the player stands in: C_Map.GetBestMapForUnit, climbed up to the zone level. nil if unknown.
function Zones.CurrentMap()
  if not (C_Map and C_Map.GetBestMapForUnit) then
    return nil
  end
  local ok, mapID = pcall(C_Map.GetBestMapForUnit, "player")
  if not ok or not mapID then
    return nil
  end
  for _ = 1, 5 do
    if H.Index.Zone(mapID) or not C_Map.GetMapInfo then
      return mapID
    end
    local okInfo, info = pcall(C_Map.GetMapInfo, mapID)
    if not okInfo or type(info) ~= "table" or not info.parentMapID or info.parentMapID == 0
      or (info.mapType and info.mapType <= MAP_TYPE_ZONE) then
      return mapID
    end
    mapID = info.parentMapID
  end
  return mapID
end

-- Map ID and index entry of the zone the player is in, and how it was found ("map" or "name"); nil if unknown.
function Zones.Current()
  local mapID = Zones.CurrentMap()
  local zone = mapID and H.Index.Zone(mapID)
  if zone then
    return mapID, zone, "map"
  end
  for _, getter in ipairs({ GetRealZoneText, GetZoneText }) do
    if type(getter) == "function" then
      local ok, name = pcall(getter)
      local byName, entry = H.Index.ZoneByName(ok and name or nil)
      if byName then
        return byName, entry, "name"
      end
    end
  end
  return nil
end

-- On the ground: not on a flight path, not flying, alive.
function Zones.OnGround()
  if UnitOnTaxi and UnitOnTaxi("player") then
    return false, "taxi"
  end
  if IsFlying and IsFlying() then
    return false, "flying"
  end
  if UnitIsDeadOrGhost and UnitIsDeadOrGhost("player") then
    return false, "dead"
  end
  return true
end

local schedule

-- A cinematic (the in-game camera of a character's first login, Classic) or a movie (prerendered) is playing.
local function inCinematic()
  if type(InCinematic) == "function" then
    local ok, playing = pcall(InCinematic)
    if ok and playing then
      return true
    end
  end
  for _, name in ipairs({ "CinematicFrame", "MovieFrame" }) do
    local f = _G[name]
    if type(f) == "table" and type(f.IsShown) == "function" and f:IsShown() then
      return true
    end
  end
  return false
end

-- Puts the current zone's introduction in the play list if the character never heard it. Returns a status for the
-- trace and the tests: "off", "air", "landed" (the stay starts), "cinematic", "instance", "unknown", "seen",
-- "no audio" or the Player.PlayLine status.
function Zones.Check(reason)
  if not ForeverSpeechDB.zoneIntros or not H.IsEnabled() then
    return "off"
  end
  local ground, why = Zones.OnGround()
  if not ground then
    if why ~= "dead" and not waitingLanding then -- look again until the landing
      waitingLanding = true
      H.Trace("zones: %s on %s: waiting to be on the ground", reason, why)
      schedule("landing", TAXI_POLL)
    end
    return "air"
  end
  waitingLanding = false
  if reason == "landing" then -- on the ground at last: the stay in the zone landed in starts now
    schedule("landed", STAY)
    return "landed"
  end
  if inCinematic() then
    H.Trace("zones: %s: a cinematic plays, waiting for its end", reason)
    schedule(reason, CINEMATIC_POLL)
    return "cinematic"
  end
  if IsInInstance and IsInInstance() then
    return "instance"
  end
  local mapID, zone, how = Zones.Current()
  if not mapID then
    H.Trace("zones: %s: unknown zone (map %s, %s)", reason, Zones.CurrentMap(), GetZoneText and GetZoneText())
    return "unknown"
  end
  if Zones.Seen(mapID) then
    return "seen"
  end
  if not zone.intro then
    H.Trace("zones: %s: %s (%s, by %s) has no audio yet", reason, mapID, zone.name, how)
    return "no audio"
  end
  local status, detail = H.Player.PlayLine("zone", mapID, H.Player.AUTO)
  H.Trace("zones: %s: first visit of %s (%s, by %s): %s %s", reason, mapID, zone.name, how, status, detail)
  if status == "playing" or status == "queued" or status == "duplicate" then
    Zones.MarkSeen(mapID)
  end
  return status, detail
end

schedule = function(reason, delay)
  token = token + 1
  local mine = token
  C_Timer.After(delay or STAY, function()
    if mine ~= token then
      return
    end
    if reason == "landing" then
      waitingLanding = false
    end
    Zones.Check(reason)
  end)
end
Zones.Schedule = schedule
Zones.STAY = STAY

H.TryRegisterEvent("ZONE_CHANGED_NEW_AREA", function()
  schedule("zone")
end)
H.TryRegisterEvent("PLAYER_ENTERING_WORLD", function()
  schedule("login")
end)
-- The end of a flight path gives the controls back (Classic); the taxi poll above catches it anyway.
H.TryRegisterEvent("PLAYER_CONTROL_GAINED", function()
  if waitingLanding then
    schedule("landing", 1)
  end
end)

-- Commands -------------------------------------------------------------------------

H.RegisterCommand("zone", function(arg)
  arg = (arg or ""):lower()
  if arg == "on" or arg == "off" then
    ForeverSpeechDB.zoneIntros = arg == "on"
    H.Print("zone introductions: %s", arg)
    return
  end
  if arg == "reset" then
    Zones.Forget()
    H.Print("zones forgotten for %s: each introduction plays again on the next arrival", H.Escape(character()))
    return
  end
  if arg == "where" then
    local mapID, zone, how = Zones.Current()
    H.Print("map %s, zone %s / %s, index: %s (%s), seen: %s, on the ground: %s", tostring(Zones.CurrentMap()),
      H.Escape(tostring(GetZoneText and GetZoneText())), H.Escape(tostring(GetSubZoneText and GetSubZoneText())),
      H.Escape(tostring(zone and zone.name)), tostring(how), tostring(mapID and Zones.Seen(mapID)),
      tostring((Zones.OnGround())))
    return
  end
  local mapID = tonumber(arg) or Zones.Current()
  if not mapID then
    H.Print("unknown zone: /fs zone where")
    return
  end
  local status, detail = H.Player.PlayLine("zone", mapID)
  H.Print("zone %s: %s %s", tostring(mapID), tostring(status), tostring(detail))
end, "zone [mapID|where|reset|on|off] - Elise's introduction of the current zone (or of a map ID)")
