-- Journey: where you went, for the trail, grind spots and replay on the world map.
--   db.journey = { since, segs, marks, heat, zones, dist }
--   segs[i] = { cont, map, lvl, t, kind, p = { x1, y1, dt1, x2, y2, dt2, ... } }
--     world yards (rounded) on continent `cont`, dt = seconds after t; kind walk / taxi /
--     ghost. A new seg on a jump (hearth, release, instance), another zone, taxi or ghost
--     on/off, or a level-up; one that carries on from the last starts at its last point.
--   marks[i] = { kind = ding / death / run, t, lvl, cont, x, y, map, text, gear }
--     x/y nil when it happened where the map has no position (inside a dungeon)
--   heat[cont]["cx:cy"] = kills in that HEAT_CELL square
--   zones[mapID] = { t, lvl }: first visit
--   dist = { walk, ride, fly, ghost } in yards
-- Records from install; nothing before it can be recovered.
local _, K = ...
local J = {}
K.Journey = J

J.STEP = 2          -- seconds between position checks
J.MIN_MOVE = 25     -- yards before a new point
J.JUMP = 180        -- yards in one check: a teleport, not travel (taxis do about 64)
J.HEAT_CELL = 40
J.MAX_POINTS = 60000

local db, jd
local seg           -- the open segment
local last          -- { cont, map, x, y } at the last check
local lastOutside   -- the last position with a map, for marks inside dungeons
local points = 0

local function Usable(...)
  for i = 1, select("#", ...) do
    if not K.Usable((select(i, ...))) then return false end
  end
  return true
end

-- cont, x, y, mapID in world yards; nil where the map has no position
function J.Where()
  if not (C_Map and C_Map.GetBestMapForUnit and C_Map.GetWorldPosFromMapPos) then return end
  local map = C_Map.GetBestMapForUnit("player")
  if not K.Usable(map) or not map then return end
  local pos = C_Map.GetPlayerMapPosition(map, "player")
  if not pos then return end
  local mx, my = pos:GetXY()
  if not Usable(mx, my) or (mx == 0 and my == 0) then return end
  local cont, world = C_Map.GetWorldPosFromMapPos(map, pos)
  if not (cont and world) then return end
  local x, y = world:GetXY()
  if not Usable(cont, x, y) then return end
  return cont, math.floor(x + 0.5), math.floor(y + 0.5), map
end

local function Kind()
  if UnitOnTaxi("player") then return "taxi" end
  if UnitIsGhost("player") then return "ghost" end
  return "walk"
end

local function CountPoints()
  points = 0
  for _, s in ipairs(jd.segs) do points = points + #s.p / 3 end
end

-- over the cap: every other point of the older half goes (ends kept)
local function Thin()
  local half = math.floor(#jd.segs / 2)
  for i = 1, math.max(1, half) do
    local s, p = jd.segs[i], {}
    local n = #s.p / 3
    for k = 1, n do
      if k == 1 or k == n or k % 2 == 1 then
        local b = (k - 1) * 3
        p[#p + 1], p[#p + 2], p[#p + 3] = s.p[b + 1], s.p[b + 2], s.p[b + 3]
      end
    end
    s.p = p
  end
  CountPoints()
end

local function Add(s, x, y, now)
  local p = s.p
  p[#p + 1], p[#p + 2], p[#p + 3] = x, y, now - s.t
  points = points + 1
  if points > J.MAX_POINTS then Thin() end
  if K.JourneyMap then K.JourneyMap.Added() end
end

local function NewSeg(cont, map, kind, carry)
  local now = K.Now()
  seg = { cont = cont, map = map, lvl = UnitLevel("player"), t = now, kind = kind, p = {} }
  table.insert(jd.segs, seg)
  if carry then Add(seg, carry.x, carry.y, now) end
end

local function Visit(map)
  if jd.zones[map] then return end
  local info = C_Map.GetMapInfo(map)
  if info and info.mapType == (Enum.UIMapType and Enum.UIMapType.Zone or 3) then
    jd.zones[map] = { t = K.Now(), lvl = UnitLevel("player") }
  end
end

function J.Check()
  if not jd then return end
  local cont, x, y, map = J.Where()
  if not cont then
    last = nil
    return
  end
  lastOutside = { cont = cont, x = x, y = y, map = map }
  Visit(map)
  local kind = Kind()
  local moved = last and last.cont == cont and math.sqrt((x - last.x) ^ 2 + (y - last.y) ^ 2)
  if moved and moved > J.JUMP then moved = nil end
  if moved and moved < J.MIN_MOVE then return end
  if moved then
    local dist = jd.dist
    if kind == "taxi" then dist.fly = dist.fly + moved
    elseif kind == "ghost" then dist.ghost = dist.ghost + moved
    elseif IsMounted() then dist.ride = dist.ride + moved
    else dist.walk = dist.walk + moved end
  end
  local same = seg and seg.cont == cont and seg.map == map and seg.kind == kind
    and seg.lvl == UnitLevel("player")
  if moved and same then
    Add(seg, x, y, K.Now())
  else
    NewSeg(cont, map, kind, moved and last)
    if not (moved and last.x == x and last.y == y) then Add(seg, x, y, K.Now()) end
  end
  last = { cont = cont, map = map, x = x, y = y }
end

-- equipped item IDs by slot, without shirt and tabard
local function Gear()
  local gear = {}
  for slot = 1, 18 do
    if slot ~= 4 then gear[slot] = GetInventoryItemID("player", slot) end
  end
  return gear
end

function J.Mark(kind, text, lvl)
  if not jd then return end
  local cont, x, y, map = J.Where()
  if not cont and lastOutside then
    cont, x, y, map = lastOutside.cont, lastOutside.x, lastOutside.y, lastOutside.map
  end
  local inInstance = IsInInstance()
  local m = { kind = kind, t = K.Now(), lvl = lvl or UnitLevel("player"), cont = cont, x = x,
    y = y, map = map,
    text = text or (inInstance and GetInstanceInfo()) or GetRealZoneText() or GetZoneText() }
  if kind == "ding" then m.gear = Gear() end
  table.insert(jd.marks, m)
  if K.JourneyMap then K.JourneyMap.Dirty() end
  if K.UI then K.UI.Dirty("journey") end
  return m
end

function J.Kill()
  if not jd then return end
  local cont, x, y = J.Where()
  if not cont then return end
  local cell = math.floor(x / J.HEAT_CELL) .. ":" .. math.floor(y / J.HEAT_CELL)
  jd.heat[cont] = jd.heat[cont] or {}
  jd.heat[cont][cell] = (jd.heat[cont][cell] or 0) + 1
  if K.JourneyMap then K.JourneyMap.Dirty() end
end

function J.Data() return jd end
function J.Points() return points end

-- marks of one kind, oldest first
function J.Marks(kind)
  local out = {}
  for _, m in ipairs(jd and jd.marks or {}) do
    if not kind or m.kind == kind then out[#out + 1] = m end
  end
  return out
end

function J.ZoneCount()
  local n = 0
  for _ in pairs(jd and jd.zones or {}) do n = n + 1 end
  return n
end

K.OnLoad(function(d)
  db = d
  db.journey = db.journey or {}
  jd = db.journey
  jd.since = jd.since or K.Now()
  jd.segs = jd.segs or {}
  jd.marks = jd.marks or {}
  jd.heat = jd.heat or {}
  jd.zones = jd.zones or {}
  jd.dist = jd.dist or {}
  for _, k in ipairs({ "walk", "ride", "fly", "ghost" }) do jd.dist[k] = jd.dist[k] or 0 end
  CountPoints()
end)

local ticker
K.On("PLAYER_ENTERING_WORLD", function()
  last, seg = nil, nil
  J.Check()
  ticker = ticker or C_Timer.NewTicker(J.STEP, J.Check)
end)
K.On("PLAYER_LEVEL_UP", function(newLevel)
  J.Mark("ding", nil, newLevel)
  J.Check()
end)
K.On("PLAYER_DEAD", function() J.Mark("death") end)
