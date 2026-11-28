-- Where the levelling happened: time, XP, kills, gold and deaths per zone per level, and
-- each dungeon run.
--   db.zones[level][zone] = { secs, xp, kills, gold, deaths }
--   db.runs[i] = { name, level, start, secs, xp, kills, gold, deaths }, the last MAX_RUNS
--   db.openRun = { start, left }: the run still going at logout, and when it was last in
-- Time is play time without AFK (Level.ActiveSecs), booked to the zone you were in. A run
-- lasts from entering a dungeon until you are out of it for RUN_GAP (a corpse run or a
-- vendor trip keeps it going) or enter another. Its time is the time inside plus the
-- corpse runs: dead outside it counts to the run, not the zone you run through.
local _, K = ...
local R = {}
K.Runs = R

local MAX_RUNS = 50
R.RUN_GAP = 20 * 60

local db
local zone      -- { name, level, dungeon, mark = Level.ActiveSecs() at the last booking }
local run       -- the open db.runs entry
local outside   -- K.Now() when we left the open run's dungeon
local dead      -- dead or a ghost

local function Where()
  local inInstance, kind = IsInInstance()
  if inInstance then return (GetInstanceInfo()), kind == "party" end
  local name = GetRealZoneText and GetRealZoneText() or GetZoneText()
  return name, false
end

local function Bucket(level, name)
  db.zones[level] = db.zones[level] or {}
  local z = db.zones[level][name]
  if not z then
    z = { secs = 0, xp = 0, kills = 0, gold = 0, deaths = 0 }
    db.zones[level][name] = z
  end
  return z
end

-- book the play time since the last booking to the zone (and run) we're in
local function Book()
  if not zone then return end
  local now = K.Level.ActiveSecs()
  local secs = now - zone.mark
  zone.mark = now
  if secs <= 0 then return end
  local corpseRun = run and dead and not zone.dungeon
  local z = Bucket(zone.level, corpseRun and run.name or zone.name)
  z.secs = z.secs + secs
  if run and (corpseRun or zone.dungeon and zone.name == run.name) then
    run.secs = run.secs + secs
  end
end

local function SetDead(on)
  Book()
  dead = on
end

local function EndRun()
  run, outside = nil, nil
  db.openRun = nil
end

local function RunOver()
  return run and outside and K.Now() - outside >= R.RUN_GAP
end

local function Enter()
  Book()
  local name, dungeon = Where()
  if not name or name == "" then return end
  local lvl = UnitLevel("player")
  if zone and zone.name == name and zone.dungeon == dungeon then
    zone.level = lvl
    return
  end
  zone = { name = name, level = lvl, dungeon = dungeon, mark = K.Level.ActiveSecs() }
  if RunOver() then EndRun() end
  if dungeon then
    if not (run and run.name == name) then
      run = { name = name, level = lvl, start = K.Now(), secs = 0, xp = 0, kills = 0,
        gold = 0, deaths = 0 }
      table.insert(db.runs, run)
      while #db.runs > MAX_RUNS do table.remove(db.runs, 1) end
      -- at the entrance: inside, the map has no position, so the last one outside
      local m = K.Journey and K.Journey.Mark("run", name, lvl)
      if m then m.t = run.start end
    end
    outside = nil
  elseif run and not outside then
    outside = K.Now()
  end
  if K.UI then K.UI.Dirty("zones") end
end

-- Level.lua reports each gain: field is xp, kills, gold or deaths
function R.Add(field, n)
  if not zone then return end
  local z = Bucket(zone.level, zone.name)
  z[field] = z[field] + n
  if run and zone.dungeon and zone.name == run.name then run[field] = run[field] + n end
  if K.UI then K.UI.Dirty("zones") end
end

function R.Zone() return zone end
function R.Open() return run end

-- the runs, newest first, with time booked up to now
function R.Runs()
  Book()
  if RunOver() then EndRun() end
  local list = {}
  for i = #db.runs, 1, -1 do list[#list + 1] = db.runs[i] end
  return list
end

-- zones played at levels from..to, summed, sorted by XP per hour; dungeons included
-- (flagged), minSecs leaves out zones only passed through
function R.Zones(from, to, minSecs)
  Book()
  local sum, dungeons = {}, {}
  for _, r in ipairs(db.runs) do dungeons[r.name] = true end
  for lvl = from, to do
    for name, z in pairs(db.zones[lvl] or {}) do
      local s = sum[name]
      if not s then
        s = { name = name, secs = 0, xp = 0, kills = 0, gold = 0, deaths = 0,
          dungeon = dungeons[name], from = lvl }
        sum[name] = s
      end
      for _, f in ipairs({ "secs", "xp", "kills", "gold", "deaths" }) do s[f] = s[f] + z[f] end
      s.to = lvl
    end
  end
  local list = {}
  for _, s in pairs(sum) do
    if s.secs >= (minSecs or 0) then
      s.rate = s.secs > 0 and s.xp / s.secs * 3600 or 0
      list[#list + 1] = s
    end
  end
  table.sort(list, function(a, b) return a.rate > b.rate end)
  return list
end

-- XP per hour outside dungeons at levels from..to: what a run is measured against
function R.OpenWorldRate(from, to)
  local secs, xp = 0, 0
  for _, z in ipairs(R.Zones(from, to)) do
    if not z.dungeon then secs, xp = secs + z.secs, xp + z.xp end
  end
  return secs >= 600 and xp / secs * 3600 or nil
end

K.OnLoad(function(d)
  db = d
  db.zones = db.zones or {}
  db.runs = db.runs or {}
end)

-- after Level.lua's handler (file order): the session and its active time exist by then
K.On("PLAYER_ENTERING_WORLD", function()
  if not zone and db.openRun then
    for i = #db.runs, 1, -1 do
      if db.runs[i].start == db.openRun.start then run = db.runs[i] break end
    end
    outside = run and db.openRun.left
    if RunOver() then EndRun() end
  end
  Enter()
end)
K.On("ZONE_CHANGED_NEW_AREA", Enter)
K.On("PLAYER_DEAD", function() SetDead(true) end)
-- also fires on release (now a ghost): still dead for us
K.On("PLAYER_ALIVE", function() if not UnitIsGhost("player") then SetDead(false) end end)
K.On("PLAYER_UNGHOST", function() SetDead(false) end)
K.On("PLAYER_LEVEL_UP", function(newLevel)
  Book()
  if zone then zone.level = newLevel end
end)
K.On("PLAYER_LOGOUT", function()
  Book()
  db.openRun = run and { start = run.start, left = outside or K.Now() } or nil
end)
