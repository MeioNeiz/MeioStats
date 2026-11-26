-- MeioStats: levelling (Level.lua), loot luck (Loot.lua), money (Money.lua), window
-- (UI*.lua). Public for other addons: MeioStats.Money.ItemTotals(itemID).
local addonName, K = ...
MeioStats = K

-- scenarios swap in fixed clocks
function K.Now() return time() end
function K.Clock() return GetTime() end

function K.Print(msg) DEFAULT_CHAT_FRAME:AddMessage("|cffb090ffMeioStats:|r " .. msg) end

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

-- on/off options: the chat toggle and Settings checkbox share key, label and default
K.OPTIONS = {
  questBar = { label = "quest XP band", default = false },
  questOpen = { label = "quests in progress", default = false },
  dingLine = { label = "level-up summary", default = true },
}

function K.Option(key)
  local v = K.db and K.db[key]
  if v == nil then return K.OPTIONS[key].default end
  return v
end

function K.SetOption(key, on)
  K.db[key] = on
  if K.QuestXP then K.QuestXP.Refresh() end
end

local function Cmd(text) return "|cffffd100" .. text .. "|r" end

local function OnOff(on) return on and "|cff80ff80on|r" or "|cffff8080off|r" end

local function Now(key) return " (now " .. (K.Option(key) and "on" or "off") .. ")" end

local HELP = {
  { "/stats", "open or close the window, on the last tab" },
  { "/stats level||xp", "levelling: played time per level, XP per hour, where XP came from" },
  { "/stats zones||runs", "zones: dungeon runs and XP per hour in each zone" },
  { "/stats loot||luck", "loot luck: quest drops against Questie's drop rates, all loot" },
  { "/stats money||gold", "money: sales, purchases and profit from TSM's ledger" },
  { "/stats questxp on||off", function()
    return "quest XP band: how far your finished quests take the XP bar" .. Now("questBar")
  end },
  { "/stats questxp progress on||off", function()
    return "quests in progress: a fainter band past it" .. Now("questOpen")
  end },
  { "/stats ding on||off", function()
    return "level-up summary: time, kills and quests in chat at each level"
      .. Now("dingLine")
  end },
  { "/stats reset", "put the window back in the middle of the screen" },
}

local function Help()
  K.Print("levelling times, loot luck and money per item")
  for _, h in ipairs(HELP) do
    local text = h[2]
    if type(text) == "function" then text = text() end
    DEFAULT_CHAT_FRAME:AddMessage("  " .. Cmd(h[1] --[[@as string]]) .. " - " .. text)
  end
  DEFAULT_CHAT_FRAME:AddMessage("  Settings: Esc > Options > AddOns > MeioStats ("
    .. Cmd("/stats settings") .. ")")
end

function K.ResetWindow()
  K.UI.ResetPosition()
  K.Print("window moved back to the middle of the screen")
end

-- on / off sets it, nothing flips it
local function OptionCmd(key, word, typed)
  local on
  if word == "on" then on = true
  elseif word == "off" then on = false
  elseif word == "" then on = not K.Option(key)
  else
    K.Print('unknown command "' .. typed .. '"')
    return Help()
  end
  K.SetOption(key, on)
  K.Print(K.OPTIONS[key].label .. " " .. OnOff(on))
end

local function QuestXPCmd(rest)
  local word = rest:lower()
  local sub = word:match("^progress%s*(.-)$")
  if sub then return OptionCmd("questOpen", sub, "questxp " .. rest) end
  return OptionCmd("questBar", word, "questxp " .. rest)
end

local commands = {
  help = Help,
  questxp = QuestXPCmd,
  ding = function(rest) return OptionCmd("dingLine", rest:lower(), "ding " .. rest) end,
  ["?"] = Help,
  reset = K.ResetWindow,
  settings = function() K.OpenSettings() end,
  options = function() K.OpenSettings() end,
}

local function Slash(msg)
  local cmd, rest = (msg or ""):match("^%s*(%S*)%s*(.-)%s*$")
  cmd = cmd:lower()
  local fn = commands[cmd]
  if fn then return fn(rest) end
  if cmd ~= "" and not K.UI.Tab(cmd) then
    K.Print('unknown command "' .. cmd .. '"')
    return Help()
  end
  K.UI.Toggle(K.UI.Tab(cmd))
end

SLASH_MEIOSTATS1 = "/stats"
SLASH_MEIOSTATS2 = "/meiostats"
SlashCmdList.MEIOSTATS = Slash

-- KafStats (MeioStats before 1.0.0) also claims /stats, and which addon wins a shared slash
-- word is down to table order. Point its command at ours so /stats always opens MeioStats.
local function TakeOverKafStats()
  local loaded = C_AddOns and C_AddOns.IsAddOnLoaded or IsAddOnLoaded
  if not (loaded and loaded("KafStats")) then return end
  SlashCmdList.KAFSTATS = Slash
  if hash_SlashCmdList then hash_SlashCmdList["/STATS"] = nil end
  K.Print("the old KafStats addon is still enabled; disable it in the AddOns list"
    .. " (MeioStats replaces it)")
end
K.On("PLAYER_LOGIN", TakeOverKafStats)

-- minimap addon compartment (.toc AddonCompartmentFunc)
function MeioStats_OnAddonCompartmentClick() K.UI.Toggle() end
