-- MeioStats: levelling (Level.lua), loot luck (Loot.lua), money (Money.lua), window
-- (UI*.lua). Public for other addons: MeioStats.Money.ItemTotals(itemID).
local addonName, K = ...
MeioStats = K
-- the name before 1.0.0, still called by Meionomics
KafStats = K

K.ACCENT = "|cff66bbff"

-- scenarios swap in fixed clocks
function K.Now() return time() end
function K.Clock() return GetTime() end

function K.Print(msg) DEFAULT_CHAT_FRAME:AddMessage(K.ACCENT .. "MeioStats|r: " .. msg) end

-- secret values (combat chat, some unit info on this client) can't be compared or parsed
local canaccess = canaccessvalue or function() return true end
function K.Usable(v) return v ~= nil and canaccess(v) end

-- 1h 05m / 12m 30s / 45s; days for long spans
function K.Duration(sec)
  if not sec then return "-" end
  sec = math.max(0, math.floor(sec + 0.5))
  local d, h = math.floor(sec / 86400), math.floor(sec / 3600) % 24
  local m = math.floor(sec / 60) % 60
  if d > 0 then return ("%dd %dh"):format(d, h) end
  if h > 0 then return ("%dh %02dm"):format(h, m) end
  if m >= 10 then return m .. "m" end
  if m > 0 then return ("%dm %02ds"):format(m, sec % 60) end
  return sec .. "s"
end

-- 1,234 / 12.3k / 1.2M
function K.Count(n)
  if not n then return "-" end
  local a = math.abs(n)
  if a >= 1e6 then return ("%.1fM"):format(n / 1e6) end
  if a >= 1e5 then return ("%.0fk"):format(n / 1e3) end
  if a >= 1e4 then return ("%.1fk"):format(n / 1e3) end
  return BreakUpLargeNumbers(math.floor(n + 0.5))
end

-- 12g 34s / 5s 6c: two units at most, coin colours
function K.Coins(c, signed)
  if not c then return "|cff808080-|r" end
  local neg = c < 0
  c = math.floor(math.abs(c) + 0.5)
  local g, s, cp = math.floor(c / 10000), math.floor(c / 100) % 100, c % 100
  local G, S, C = "|cffffd700g|r", "|cffc7c7cfs|r", "|cffeda55fc|r"
  local text
  if g >= 100 then text = BreakUpLargeNumbers(g) .. G
  elseif g > 0 then text = g .. G .. (s > 0 and (" " .. s .. S) or "")
  elseif s > 0 then text = s .. S .. (cp > 0 and (" " .. cp .. C) or "")
  else text = cp .. C end
  return (neg and "-" or (signed and "+" or "")) .. text
end

function K.NpcID(guid)
  if not K.Usable(guid) then return nil end
  local kind, _, _, _, _, id = strsplit("-", guid)
  if kind == "Creature" or kind == "Vehicle" then return tonumber(id) end
end

local events = CreateFrame("Frame")
local handlers = {}
function K.On(event, fn)
  if not handlers[event] then
    handlers[event] = {}
    events:RegisterEvent(event)
  end
  table.insert(handlers[event], fn)
end
events:SetScript("OnEvent", function(_, event, ...)
  for _, fn in ipairs(handlers[event]) do fn(...) end
end)

local loaders = {}
function K.OnLoad(fn) loaders[#loaders + 1] = fn end

K.On("ADDON_LOADED", function(name)
  if name ~= addonName then return end
  if not MeioStatsCharDB and type(KafStatsCharDB) == "table" then
    MeioStatsCharDB = KafStatsCharDB
  end
  KafStatsCharDB = nil
  MeioStatsCharDB = MeioStatsCharDB or {}
  K.db = MeioStatsCharDB
  K.db.version = K.db.version or 1
  for _, fn in ipairs(loaders) do fn(K.db) end
end)

local HELP = {
  "/stats: open or close the window, on the last tab",
  "/stats level (or xp): levelling times, XP per hour, XP sources",
  "/stats loot (or luck): quest drops against their drop rate, everything looted",
  "/stats money (or gold): sales, purchases and profit from TSM's ledger",
}

K.commands = {
  help = function()
    for _, line in ipairs(HELP) do K.Print(line) end
  end,
}

SLASH_MEIOSTATS1 = "/stats"
SLASH_MEIOSTATS2 = "/meiostats"
SlashCmdList.MEIOSTATS = function(msg)
  local cmd, rest = (msg or ""):match("^%s*(%S*)%s*(.-)%s*$")
  cmd = cmd:lower()
  local fn = K.commands[cmd]
  if fn then return fn(rest) end
  if cmd ~= "" and not K.UI.Tab(cmd) then
    K.Print("unknown command '" .. cmd .. "', try /stats help")
    return
  end
  K.UI.Toggle(K.UI.Tab(cmd))
end
