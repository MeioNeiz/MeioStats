-- Loot luck: kills per mob, corpses with each item, compared with the drop rate when known.
--   db.npcs[npcID] = { name, kills, loot = { [itemID] = corpses with it },
--     qty = { [itemID] = n } }
--   db.rated[itemID][npcID] = { k = kills while the item was wanted, d = corpses with it }
-- Kills: no combat log on Forever, so a kill is an XP line ("X dies, you gain") or a looted
-- corpse (grey mobs give no XP); the two are matched per mob so one kill counts once.
-- Rates: Questie's drop tables (quest items only: Wowhead / cMaNGOS / its corrections,
-- in %); which items a quest wants: QuestieDB (LibQuestieDB).
-- Quest items drop only while the quest is in the log, so their kills count only then.
-- Luck: binomial (Poisson-binomial over several mobs) percentile of the drops seen.
local _, K = ...
local L = {}
K.Loot = L

local PENDING_TTL = 300

local db
local nameToID = {}    -- this session: mob name -> npcID, from units seen
local pending = {}     -- npcID -> { times of kills counted from XP, not yet looted }
local seen = {}        -- corpse GUIDs already looted
local wanted, wantedDirty = {}, true   -- itemID -> true while a quest in the log needs it
local rateCache = {}

------------------------------------------------------------------------------ Questie
-- What a quest needs comes from QuestieDB's public API (LibQuestieDB). Drop rates only
-- Questie itself has, behind QuestieLoader, which Questie is shutting other addons out of:
-- asked once, and when it refuses there are no rates and no error.
local CONTRACT = 4

local function QDB()
  local lib = rawget(_G, "LibQuestieDB")
  if type(lib) ~= "table" or type(lib.RequireContract) ~= "function" then return nil end
  local ok, fits = pcall(lib.RequireContract, CONTRACT)
  return ok and fits and lib or nil
end

local function QuestField(questID, key)
  local lib = QDB()
  local quest = lib and lib.Quest
  if not (type(quest) == "table" and quest.Get) then return nil end
  local ok, v = pcall(quest.Get, questID, key)
  return ok and type(v) == "table" and v or nil
end

local dropRates   -- Questie's QuestieDB module, false once it can't be had
local function DropRates()
  if dropRates == nil then
    dropRates = false
    local QL = rawget(_G, "QuestieLoader")
    if type(QL) == "table" and type(QL.ImportModule) == "function" then
      local ok, q = pcall(QL.ImportModule, QL, "QuestieDB")
      if ok and type(q) == "table" and type(q.GetItemDroprate) == "function" then
        dropRates = q
      end
    end
  end
  return dropRates or nil
end

-- rates need both: Questie's drop tables, and QuestieDB to know which items are wanted
function L.HasRates() return DropRates() ~= nil and QDB() ~= nil end

-- why there are no rates: Questie isn't there, or it doesn't let us read them
function L.NoRatesReason()
  local loaded = C_AddOns and C_AddOns.IsAddOnLoaded and C_AddOns.IsAddOnLoaded("Questie")
  return loaded and "unreadable" or "noquestie"
end

-- drop rate 0..1 and its source, or nil
function L.Rate(itemID, npcID)
  local key = itemID .. ":" .. npcID
  local c = rateCache[key]
  if c == nil then
    local q = DropRates()
    if not q then return nil end
    local ok, r = pcall(q.GetItemDroprate, itemID, npcID)
    local pct = ok and type(r) == "table" and tonumber(r[1])
    c = pct and pct ~= 0 and { math.min(math.abs(pct), 100) / 100, r[2] } or false
    if ok then rateCache[key] = c end
  end
  if c then return c[1], c[2] end
end

local function QuestLogIDs()
  local ids = {}
  for i = 1, C_QuestLog.GetNumQuestLogEntries() do
    local info = C_QuestLog.GetInfo(i)
    if info and not info.isHeader and info.questID then ids[#ids + 1] = info.questID end
  end
  return ids
end

local function Complete(questID)
  if C_QuestLog and C_QuestLog.IsComplete then return C_QuestLog.IsComplete(questID) end
end

local function Wanted()
  if not wantedDirty then return wanted end
  wantedDirty = false
  wipe(wanted)
  if not QDB() then return wanted end
  for _, id in ipairs(QuestLogIDs()) do
    if not Complete(id) then
      local obj = QuestField(id, "objectives")
      for _, it in ipairs(obj and type(obj[3]) == "table" and obj[3] or {}) do
        if type(it) == "table" and it[1] then wanted[it[1]] = true end
      end
      for _, it in ipairs(QuestField(id, "requiredSourceItems") or {}) do
        wanted[it] = true
      end
    end
  end
  return wanted
end

------------------------------------------------------------------------------ counting
local function Npc(id, name)
  local n = db.npcs[id]
  if not n then
    n = { kills = 0, loot = {}, qty = {} }
    db.npcs[id] = n
  end
  if name then n.name = name end
  return n
end

local function CountKill(npcID, name)
  local n = Npc(npcID, name)
  n.kills = n.kills + 1
  for itemID in pairs(Wanted()) do
    if L.Rate(itemID, npcID) then
      db.rated[itemID] = db.rated[itemID] or {}
      local pair = db.rated[itemID][npcID] or { k = 0, d = 0 }
      db.rated[itemID][npcID] = pair
      pair.k = pair.k + 1
    end
  end
  if K.UI then K.UI.Dirty("loot") end
end

local function Remember(unit)
  local guid = UnitGUID(unit)
  local id = K.NpcID(guid)
  local name = id and UnitName(unit)
  if id and name and (not canaccessvalue or canaccessvalue(name)) then
    nameToID[name] = id
    if db.npcs[id] then db.npcs[id].name = name end
  end
end

function L.KilledByName(name)
  local id = nameToID[name]
  if not id then
    db.unknown[name] = (db.unknown[name] or 0) + 1
    return
  end
  CountKill(id, name)
  pending[id] = pending[id] or {}
  table.insert(pending[id], K.Clock())
end

-- a kill already counted from its XP line, still waiting to be looted?
local function TakePending(npcID)
  local list = pending[npcID]
  local now = K.Clock()
  while list and list[1] and now - list[1] > PENDING_TTL do table.remove(list, 1) end
  if list and list[1] then
    table.remove(list, 1)
    return true
  end
end

local function ItemID(link)
  return K.Usable(link) and tonumber(link:match("item:(%d+)")) or nil
end

local function OnLoot()
  local corpses = {}
  for slot = 1, GetNumLootItems() do
    local id = ItemID(GetLootSlotLink(slot))
    local src = { GetLootSourceInfo(slot) }
    for i = 1, #src, 2 do
      local guid, qty = src[i], src[i + 1] or 1
      if K.Usable(guid) and not seen[guid] then
        corpses[guid] = corpses[guid] or {}
        if id then corpses[guid][id] = (corpses[guid][id] or 0) + qty end
      end
    end
  end
  local want = Wanted()
  for guid, got in pairs(corpses) do
    seen[guid] = true
    local npcID = K.NpcID(guid)
    if npcID then
      local n = Npc(npcID)
      if not TakePending(npcID) then CountKill(npcID) end
      for id, qty in pairs(got) do
        n.loot[id] = (n.loot[id] or 0) + 1
        n.qty[id] = (n.qty[id] or 0) + qty
        local pair = want[id] and db.rated[id] and db.rated[id][npcID]
        if pair then pair.d = pair.d + 1 end
      end
    end
  end
  if K.UI then K.UI.Dirty("loot") end
end

------------------------------------------------------------------------------ statistics
-- binomial pmf for 0..cap, in log space so long kill counts don't underflow
local function Pmf(n, p, cap)
  local out = {}
  cap = math.min(cap, n)
  if p >= 1 then
    for j = 0, cap do out[j] = j == n and 1 or 0 end
    return out
  end
  p = math.max(p, 1e-9)
  local lp, lq = math.log(p), math.log(1 - p)
  local l = n * lq
  for j = 0, cap do
    out[j] = math.exp(l)
    l = l + math.log((n - j) / (j + 1)) + lp - lq
  end
  return out
end

-- P(X < d) and P(X = d) for X = sum of Binomial(k_i, p_i)
function L.Percentile(groups, d)
  local dist = { [0] = 1 }
  for _, g in ipairs(groups) do
    local pmf = Pmf(g.k, g.p, d)
    local nxt = {}
    for i = 0, d do
      local s = 0
      for j = 0, i do
        local a, b = dist[j], pmf[i - j]
        if a and b then s = s + a * b end
      end
      nxt[i] = s
    end
    dist = nxt
  end
  local below = 0
  for i = 0, d - 1 do below = below + (dist[i] or 0) end
  return below, dist[d] or 0
end

-- luck for one item over the mobs with a known rate:
--   { kills, drops, expected, rate (kill-weighted), top = P(X >= d), bottom = P(X <= d),
--     score = mid-percentile 0..1 (0.5 = as expected), verdict, mobs }
function L.Luck(itemID)
  local pairsOf = db.rated[itemID]
  if not pairsOf then return nil end
  local groups, kills, drops, expected, mobs = {}, 0, 0, 0, 0
  for npcID, pair in pairs(pairsOf) do
    local p = L.Rate(itemID, npcID)
    if p and pair.k > 0 then
      groups[#groups + 1] = { k = pair.k, p = p }
      kills, drops = kills + pair.k, drops + math.min(pair.d, pair.k)
      expected = expected + pair.k * p
      mobs = mobs + 1
    end
  end
  if kills == 0 then return nil end
  local below, at = L.Percentile(groups, drops)
  local r = { kills = kills, drops = drops, expected = expected, rate = expected / kills,
    top = 1 - below, bottom = below + at, score = below + at / 2, mobs = mobs }
  if drops > expected and r.top <= 0.05 then r.verdict = "very lucky"
  elseif drops > expected and r.top <= 0.3 then r.verdict = "lucky"
  elseif drops < expected and r.bottom <= 0.05 then r.verdict = "very unlucky"
  elseif drops < expected and r.bottom <= 0.3 then r.verdict = "unlucky"
  else r.verdict = "as expected" end
  return r
end

-- items with a known rate: { id, luck }, most surprising first
function L.RatedList()
  local list = {}
  for itemID in pairs(db.rated) do
    local luck = L.Luck(itemID)
    if luck then list[#list + 1] = { id = itemID, luck = luck } end
  end
  table.sort(list, function(a, b)
    local sa, sb = math.abs(a.luck.score - 0.5), math.abs(b.luck.score - 0.5)
    if sa ~= sb then return sa > sb end
    return a.id < b.id
  end)
  return list
end

-- everything looted, by item: { id, drops, qty, kills (of mobs that dropped it), rate,
-- best = { npcID, name, drops, kills }, mobs }
function L.ObservedList()
  local by = {}
  for npcID, n in pairs(db.npcs) do
    for id, d in pairs(n.loot) do
      local e = by[id]
      if not e then
        e = { id = id, drops = 0, qty = 0, kills = 0, mobs = 0 }
        by[id] = e
      end
      e.drops, e.qty, e.kills = e.drops + d, e.qty + (n.qty[id] or d), e.kills + n.kills
      e.mobs = e.mobs + 1
      if not e.best or d > e.best.drops then
        e.best = { npcID = npcID, name = n.name, drops = d, kills = n.kills }
      end
    end
  end
  local list = {}
  for _, e in pairs(by) do
    e.rate = e.kills > 0 and e.drops / e.kills or nil
    list[#list + 1] = e
  end
  return list
end

function L.Totals()
  local kills, mobs = 0, 0
  for _, n in pairs(db.npcs) do
    kills, mobs = kills + n.kills, mobs + 1
  end
  return { kills = kills, mobs = mobs }
end

------------------------------------------------------------------------------ events
K.OnLoad(function(d)
  db = d
  db.npcs = db.npcs or {}
  db.rated = db.rated or {}
  db.unknown = db.unknown or {}
end)

K.On("PLAYER_TARGET_CHANGED", function() Remember("target") end)
K.On("UPDATE_MOUSEOVER_UNIT", function() Remember("mouseover") end)
K.On("NAME_PLATE_UNIT_ADDED", function(unit) Remember(unit) end)
K.On("LOOT_READY", OnLoot)
local QUEST_EVENTS = { "QUEST_LOG_UPDATE", "QUEST_ACCEPTED", "QUEST_REMOVED",
  "QUEST_TURNED_IN" }
for _, e in ipairs(QUEST_EVENTS) do
  K.On(e, function() wantedDirty = true end)
end

L._test = { OnLoot = OnLoot, Remember = Remember, Pmf = Pmf,
  SetWanted = function(t) wanted, wantedDirty = t, false end,
  Wanted = function() wantedDirty = true return Wanted() end,
  ResetQuestie = function() dropRates = nil wipe(rateCache) end }
