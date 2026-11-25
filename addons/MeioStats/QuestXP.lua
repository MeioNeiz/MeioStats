-- Quest XP on Blizzard's XP bar: a gold band from the fill to where handing in the finished
-- quests takes it (to the bar's end when that's a level), a fainter one past it for quests
-- still in progress (off by default), and a line on the bar's tooltip.
--   options (Core K.OPTIONS): questBar, the band and line; questOpen, the faint band
-- FlareUI hides Blizzard's bar for its own, which has this built in (its Quest XP setting).
local _, K = ...
local Q = {}
K.QuestXP = Q

local GOLD = { 1, 0.78, 0.1 }
local READY_ALPHA, OPEN_ALPHA = 0.75, 0.3

local function Call(fn, ...)
  if type(fn) ~= "function" then return nil end
  local ok, a = pcall(fn, ...)
  if ok then return a end
end

function Q.On() return K.Option("questBar") end
function Q.OpenOn() return K.Option("questOpen") end

local stale, ready, open = true, 0, 0

-- quests under a collapsed header drop out of the log's indices (and Blizzard's quest log
-- collapses other zones at each loading screen), so every quest seen or accepted is
-- remembered (saved) and asked for by ID
local known = {}
K.OnLoad(function(db)
  db.questIDs = db.questIDs or {}
  known = db.questIDs
end)

local function Rows(QL)
  local rows = {}
  for i = 1, Call(QL.GetNumQuestLogEntries) or 0 do
    rows[i] = Call(QL.GetInfo, i) or {}
  end
  return rows
end

-- quests taken before install under a header collapsed since: open the headers for one
-- read and close them again, as Blizzard's quest search does. Bottom up, so opening or
-- closing one doesn't move the headers above it. Once a session, out of combat, map shut.
local seeded
local function Seed(QL)
  if seeded or Call(InCombatLockdown) or (WorldMapFrame and WorldMapFrame:IsShown()) then
    return
  end
  seeded = true
  local closed = {}
  local rows = Rows(QL)
  for i = #rows, 1, -1 do
    if rows[i].isHeader and rows[i].isCollapsed then
      closed[rows[i].title or ""] = true
      Call(ExpandQuestHeader, i)
    end
  end
  rows = Rows(QL)
  for i = #rows, 1, -1 do
    local info = rows[i]
    if info.isHeader then
      if closed[info.title or ""] then Call(CollapseQuestHeader, i) end
    elseif (info.questID or 0) > 0 then
      known[info.questID] = true
    end
  end
end

-- reward XP of the quests in the log: ready to hand in, still in progress
function Q.Totals()
  if not stale then return ready, open end
  stale, ready, open = false, 0, 0
  local QL = C_QuestLog
  if not QL then return 0, 0 end
  local counted, n = {}, 0
  local function Count(id)
    if counted[id] then return end
    counted[id], n = true, n + 1
    local xp = Call(GetQuestLogRewardXP, id) or 0
    -- talk-to quests have no objectives: ReadyForTurnIn, not IsComplete
    if Call(QL.ReadyForTurnIn, id) or Call(QL.IsComplete, id) then
      ready = ready + xp
    else
      open = open + xp
    end
  end
  local function CountAll()
    for _, info in ipairs(Rows(QL)) do
      local id = not info.isHeader and info.questID
      if id and id > 0 then
        known[id] = true
        Count(id)
      end
    end
    for id in pairs(known) do
      local on = Call(QL.IsOnQuest, id)
      if on then Count(id) elseif on == false then known[id] = nil end
    end
  end
  CountAll()
  local ok, _, quests = pcall(QL.GetNumQuestLogEntries)
  if ok and type(quests) == "number" and n < quests and not seeded then
    Seed(QL)
    CountAll()
  end
  stale = false
  return ready, open
end

local function Levelling()
  if Call(IsXPUserDisabled) then return false end
  local cap = Call(GetMaxPlayerLevel) or 60
  return UnitLevel("player") < cap and (UnitXPMax("player") or 0) > 0
end

------------------------------------------------------------------------------ bands
local bars = {}

-- every ExpBar in Blizzard's status tracking containers (XP can sit in either)
local function FindBars()
  local found = {}
  local mgr = StatusTrackingBarManager
  local enum = StatusTrackingBarInfo and StatusTrackingBarInfo.BarsEnum
  local xpIndex = enum and enum.Experience
  for _, c in ipairs(mgr and mgr.barContainers or {}) do
    for _, bar in pairs(c.bars or {}) do
      if bar.isExpBar and bar.StatusBar and (not xpIndex or bar.barIndex == xpIndex) then
        found[#found + 1] = bar
      end
    end
  end
  return found
end

-- x offsets of a band from the fill's end, clamped to the bar
local function Span(cur, max, from, add, width)
  local x0 = math.min(1, (cur + from) / max) * width
  local x1 = math.min(1, (cur + from + add) / max) * width
  return x0, x1 - x0
end

local function PlaceBand(tex, sb, x, w)
  if w < 0.5 then tex:Hide() return end
  tex:ClearAllPoints()
  tex:SetPoint("TOPLEFT", sb, "TOPLEFT", x, 0)
  tex:SetPoint("BOTTOMLEFT", sb, "BOTTOMLEFT", x, 0)
  tex:SetWidth(w)
  tex:Show()
end

local function Place(bar)
  local b = bar.meioQuest
  local sb = bar.StatusBar
  local width = sb:GetWidth() or 0
  if not (Q.On() and Levelling() and width > 0) then
    b.ready:Hide()
    b.open:Hide()
    return
  end
  local cur, max = UnitXP("player"), UnitXPMax("player")
  local r, o = Q.Totals()
  PlaceBand(b.ready, sb, Span(cur, max, 0, r, width))
  if Q.OpenOn() then
    PlaceBand(b.open, sb, Span(cur, max, r, o, width))
  else
    b.open:Hide()
  end
end

local Tooltip

local function Setup(bar)
  local sb = bar.StatusBar
  -- own frame in the text's strata, just under the text and rested pip: in the bar's LOW
  -- strata Blizzard's rested prediction can draw over it
  local holder = CreateFrame("Frame", nil, sb)
  holder:SetAllPoints()
  holder:SetFrameStrata("MEDIUM")
  local overlay = bar.OverlayFrame
  local top = overlay and overlay:GetFrameLevel() or sb:GetFrameLevel() + 1
  holder:SetFrameLevel(math.max(1, top - 1))
  local function Band(sub, alpha)
    local t = holder:CreateTexture(nil, "ARTWORK", nil, sub)
    t:SetColorTexture(GOLD[1], GOLD[2], GOLD[3], alpha)
    t:Hide()
    return t
  end
  bar.meioQuest = { ready = Band(-3, READY_ALPHA), open = Band(-4, OPEN_ALPHA) }
  if type(bar.Update) == "function" then hooksecurefunc(bar, "Update", Place) end
  sb:HookScript("OnSizeChanged", function() Place(bar) end)
  bar:HookScript("OnEnter", Tooltip)
  if bar.ExhaustionTick then bar.ExhaustionTick:HookScript("OnEnter", Tooltip) end
  bars[#bars + 1] = bar
end

function Q.Refresh()
  -- off: nothing hooked onto Blizzard's bar
  if #bars == 0 and Q.On() then
    for _, bar in ipairs(FindBars()) do Setup(bar) end
  end
  for _, bar in ipairs(bars) do Place(bar) end
end

function Q.Bars() return bars end

------------------------------------------------------------------------------ tooltip
-- "Quests ready: 2,340 XP (43% of the level)", or "(Level 23 when handed in)"
function Q.Line()
  if not (Q.On() and Levelling()) then return nil end
  local r, o = Q.Totals()
  local cur, max, lvl = UnitXP("player"), UnitXPMax("player"), UnitLevel("player")
  local lines = {}
  if r > 0 then
    local tail
    if cur + r >= max then
      tail = ("|cff80ff80Level %d when handed in|r"):format(lvl + 1)
    else
      tail = ("%d%% of the level"):format(math.floor(r / max * 100 + 0.5))
    end
    lines[1] = ("|cffffd100Quests ready:|r %s XP (%s)"):format(BreakUpLargeNumbers(r), tail)
  end
  if Q.OpenOn() and o > 0 then
    lines[#lines + 1] = ("|cffffd100Quests in progress:|r %s XP")
      :format(BreakUpLargeNumbers(o))
  end
  return lines[1] and lines
end

function Tooltip()
  local lines = Q.Line()
  if not lines then return end
  local tt = GameTooltip
  -- Blizzard shows nothing here without a rest state
  if not tt:IsShown() then GameTooltip_SetDefaultAnchor(tt, UIParent) end
  for _, line in ipairs(lines) do tt:AddLine(line, 1, 1, 1) end
  tt:Show()
end

------------------------------------------------------------------------------ events
local pending
local function Soon()
  if pending then return end
  pending = true
  C_Timer.After(0.2, function() pending = false Q.Refresh() end)
end

local function QuestsChanged()
  stale = true
  Soon()
end

K.On("PLAYER_LOGIN", Q.Refresh)
K.On("PLAYER_ENTERING_WORLD", QuestsChanged)
K.On("QUEST_LOG_UPDATE", QuestsChanged)
-- questID alone on this client, (logIndex, questID) on older ones
K.On("QUEST_ACCEPTED", function(a, b)
  local id = b or a
  if type(id) == "number" and id > 0 then known[id] = true end
  QuestsChanged()
end)
K.On("QUEST_TURNED_IN", QuestsChanged)
K.On("PLAYER_LEVEL_UP", QuestsChanged)
K.On("PLAYER_XP_UPDATE", Soon)
K.On("UPDATE_EXHAUSTION", Soon)
