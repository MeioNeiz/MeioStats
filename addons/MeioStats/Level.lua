-- Levelling: played and real time per level, XP by source, XP/hour, time to level.
--   db.levels[level] = { startPlayed, startReal, played, real, done, partial,
--     xp = { kill, rested, quest, explore, other }, kills, quests }
--   played: seconds of /played spent in that level (exact even mid-level: TIME_PLAYED_MSG
--   gives the time in this level); real: wall clock from ding to ding (partial: the addon
--   wasn't there at the start, so real time is unknown)
--   db.sessions[i] = { start, secs, xp, from, to }, the last MAX_SESSIONS
-- XP sources: every XP change is measured from UnitXP, then explained by the chat lines and
-- quest events around it. A change nothing explains counts as a kill in or just after
-- combat (combat chat can be a secret value), else "other".
local _, K = ...
local L = {}
K.Level = L

L.SOURCES = { "kill", "rested", "quest", "explore", "other" }
local MAX_SESSIONS = 30
local RATE_WINDOW = 900
local BUCKET = 300

local db
local played          -- { total, level, at = K.Clock() } from TIME_PLAYED_MSG
local last            -- { xp, max, level }
local session         -- this session's db.sessions entry
local sessionStart    -- K.Clock()
local gains = {}      -- { t, xp } this session, for the rate now
local pending = {}    -- { src, xp, t } explained but not yet measured
local deltas = {}     -- { xp, level } measured but not yet explained
local lastCombat = -math.huge
L.buckets = {}        -- session XP per BUCKET seconds, for the sparkline

------------------------------------------------------------------------------ played time
-- RequestTimePlayed prints to chat; the chat frames are muted while our request is out
local muted = {}
local function Unmute()
  for _, f in ipairs(muted) do f:RegisterEvent("TIME_PLAYED_MSG") end
  wipe(muted)
end

function L.RequestPlayed()
  if #muted == 0 then
    for i = 1, NUM_CHAT_WINDOWS or 10 do
      local f = _G["ChatFrame" .. i]
      if f and f:IsEventRegistered("TIME_PLAYED_MSG") then
        f:UnregisterEvent("TIME_PLAYED_MSG")
        muted[#muted + 1] = f
      end
    end
    C_Timer.After(10, Unmute)
  end
  RequestTimePlayed()
end

function L.PlayedNow()
  return played and played.total + (K.Clock() - played.at)
end

function L.Current()
  local lvl = UnitLevel("player")
  local rec = db.levels[lvl]
  if not rec then
    rec = { xp = {}, kills = 0, quests = 0, partial = true, firstSeen = K.Now() }
    db.levels[lvl] = rec
  end
  return rec, lvl
end

K.On("TIME_PLAYED_MSG", function(total, levelTime)
  if #muted > 0 then C_Timer.After(0, Unmute) end
  if not (K.Usable(total) and K.Usable(levelTime)) then return end
  played = { total = total, level = levelTime, at = K.Clock() }
  local rec = L.Current()
  rec.startPlayed = total - levelTime
  if session and not session.played0 then session.played0 = total end
end)

------------------------------------------------------------------------------ XP sources
local function Pattern(fmt)
  if not fmt then return nil end
  local p = fmt:gsub("([%(%)%.%+%-%*%?%[%]%^%$])", "%%%1")
  p = p:gsub("%%s", "(.-)"):gsub("%%d", "(%%d+)")
  return "^" .. p
end

local P = {}
local function Patterns()
  P.rested = Pattern(COMBATLOG_XPGAIN_EXHAUSTION1)
  P.kill = Pattern(COMBATLOG_XPGAIN_FIRSTPERSON)
  P.explore = Pattern(ERR_ZONE_EXPLORED_XP)
end

local function Add(rec, src, xp)
  rec.xp[src] = (rec.xp[src] or 0) + xp
  if session then
    session.xp = (session.xp or 0) + xp
    session.src = session.src or {}
    session.src[src] = (session.src[src] or 0) + xp
  end
end

local function Explain()
  local now = K.Clock()
  local combat = UnitAffectingCombat("player") or now - lastCombat < 5
  for _, d in ipairs(deltas) do
    local rec = db.levels[d.level] or L.Current()
    local left = d.xp
    while left > 0 and pending[1] do
      local p = pending[1]
      local take = math.min(p.xp, left)
      Add(rec, p.src, take)
      p.xp, left = p.xp - take, left - take
      if p.xp <= 0 then table.remove(pending, 1) end
    end
    if left > 0 then Add(rec, combat and "kill" or "other", left) end
  end
  wipe(deltas)
  for i = #pending, 1, -1 do
    if now - pending[i].t > 3 then table.remove(pending, i) end
  end
  if K.UI then K.UI.Dirty("level") end
end

local function Explained(src, xp)
  if xp and xp > 0 then pending[#pending + 1] = { src = src, xp = xp, t = K.Clock() } end
end

local scheduled
local function Measure()
  local xp, max, lvl = UnitXP("player"), UnitXPMax("player"), UnitLevel("player")
  if not last then last = { xp = xp, max = max, level = lvl } return end
  local now = K.Clock()
  local function Gain(n, level)
    if n <= 0 then return end
    deltas[#deltas + 1] = { xp = n, level = level }
    gains[#gains + 1] = { t = now, xp = n }
    local b = math.floor((now - sessionStart) / BUCKET) + 1
    L.buckets[b] = (L.buckets[b] or 0) + n
  end
  if lvl > last.level then
    Gain(last.max - last.xp, last.level)
    Gain(xp, lvl)
  else
    Gain(xp - last.xp, lvl)
  end
  last.xp, last.max, last.level = xp, max, lvl
  if #deltas > 0 and not scheduled then
    scheduled = true
    C_Timer.After(0.3, function() scheduled = false Explain() end)
  end
end

local function OnCombatXP(msg)
  if not K.Usable(msg) then return end
  local name, total, bonus = msg:match(P.rested or "^$")
  local rested = bonus and tonumber(bonus:match("%+(%d+)"))
  if not name then name, total = msg:match(P.kill) end
  total = tonumber(total)
  if not (name and total) then return end
  rested = rested and math.min(rested, total) or 0
  Explained("kill", total - rested)
  Explained("rested", rested)
  local rec = L.Current()
  rec.kills = (rec.kills or 0) + 1
  if session then session.kills = (session.kills or 0) + 1 end
  if K.Loot then K.Loot.KilledByName(name) end
end

local lastExplore
local function OnSystem(msg)
  if not K.Usable(msg) or msg == lastExplore then return end
  local _, xp = msg:match(P.explore or "^$")
  if not xp then return end
  lastExplore = msg
  C_Timer.After(1, function() lastExplore = nil end)
  Explained("explore", tonumber(xp))
end

------------------------------------------------------------------------------ rates
function L.SessionSecs() return sessionStart and K.Clock() - sessionStart or 0 end

function L.Session() return session end

-- XP/hour over the last RATE_WINDOW seconds (or the session, if shorter), and this session
function L.Rates()
  local now, secs = K.Clock(), L.SessionSecs()
  local recent = 0
  for i = #gains, 1, -1 do
    if now - gains[i].t > RATE_WINDOW then break end
    recent = recent + gains[i].xp
  end
  local span = math.min(RATE_WINDOW, secs)
  local total = session and session.xp or 0
  return span >= 60 and recent / span * 3600 or nil,
    secs >= 60 and total / secs * 3600 or nil
end

-- seconds of play to the next level, by the rate now (session if quiet lately)
function L.ETA()
  local cap = GetMaxPlayerLevel and GetMaxPlayerLevel() or 60
  if UnitLevel("player") >= cap then return nil end
  local now, sess = L.Rates()
  local rate = (now and now > 0) and now or sess
  if not rate or rate <= 0 then return nil end
  return (UnitXPMax("player") - UnitXP("player")) / rate * 3600
end

-- kills to level at this level's average kill XP (rested included)
function L.KillsToLevel()
  local rec = L.Current()
  local xp = (rec.xp.kill or 0) + (rec.xp.rested or 0)
  if (rec.kills or 0) < 3 or xp <= 0 then return nil end
  return math.ceil((UnitXPMax("player") - UnitXP("player")) / (xp / rec.kills))
end

------------------------------------------------------------------------------ events
K.OnLoad(function(d)
  db = d
  db.levels = db.levels or {}
  db.sessions = db.sessions or {}
  Patterns()
end)

K.On("PLAYER_ENTERING_WORLD", function(initial, reload)
  if session then return end
  -- /reload carries on the session (K.Clock keeps running); db.live holds what isn't in it.
  -- Matched by start: saved variables don't keep shared tables shared.
  local live, lastSession = db.live, db.sessions[#db.sessions]
  if reload and live and lastSession and lastSession.start == live.start then
    session = lastSession
    session.to = nil
    sessionStart = K.Clock() - (session.secs or 0)
    gains, L.buckets = live.gains or {}, live.buckets or {}
  else
    sessionStart = K.Clock()
    session = { start = K.Now(), secs = 0, xp = 0, from = UnitLevel("player") }
    table.insert(db.sessions, session)
    while #db.sessions > MAX_SESSIONS do table.remove(db.sessions, 1) end
  end
  db.live = nil
  L.Current()
  Measure()
  -- other addons ask at login too; ours goes after theirs
  C_Timer.After(4, L.RequestPlayed)
end)

K.On("PLAYER_XP_UPDATE", function(unit)
  if unit == nil or unit == "player" then Measure() end
end)

K.On("PLAYER_LEVEL_UP", function(newLevel)
  local now = K.Now()
  local old = db.levels[newLevel - 1]
  if old then
    local p = L.PlayedNow()
    if p and old.startPlayed then old.played = p - old.startPlayed end
    if old.startReal then old.real = now - old.startReal end
    old.done, old.dinged = true, now
  end
  -- XP already measured into the new level (event order varies) is kept
  local rec = db.levels[newLevel] or { xp = {}, kills = 0, quests = 0 }
  rec.startReal, rec.startPlayed, rec.partial, rec.firstSeen = now, L.PlayedNow(), nil, nil
  db.levels[newLevel] = rec
  -- the client's level time is exact; ours is off by the time since the last request
  C_Timer.After(2, L.RequestPlayed)
  if K.UI then K.UI.Dirty("level") end
end)

K.On("QUEST_TURNED_IN", function(_, xp)
  if K.Usable(xp) then Explained("quest", xp) end
  local rec = L.Current()
  rec.quests = (rec.quests or 0) + 1
end)

K.On("CHAT_MSG_COMBAT_XP_GAIN", OnCombatXP)
K.On("CHAT_MSG_SYSTEM", OnSystem)
K.On("UI_INFO_MESSAGE", function(_, msg) OnSystem(msg) end)
K.On("PLAYER_REGEN_ENABLED", function() lastCombat = K.Clock() end)
K.On("PLAYER_LOGOUT", function()
  if session then
    session.secs, session.to = L.SessionSecs(), UnitLevel("player")
    local now, recent = K.Clock(), {}
    for _, g in ipairs(gains) do
      if now - g.t <= RATE_WINDOW then recent[#recent + 1] = g end
    end
    db.live = { start = session.start, gains = recent, buckets = L.buckets }
  end
end)

L._test = { Pattern = Pattern, Explain = Explain, Measure = Measure,
  OnCombatXP = OnCombatXP, OnSystem = OnSystem }
