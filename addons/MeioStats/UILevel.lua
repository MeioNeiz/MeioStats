-- Levelling tab: XP bar, rate tiles, XP sources, session sparkline, played time per level.
local _, K = ...
local W, L = K.Widgets, K.Level
local C = W.C

local NAMES = { kill = "Kills", rested = "Rested", quest = "Quests", explore = "Explore",
  other = "Other" }
local HISTORY_ROWS = 9

local function Header(parent, text)
  local fs = W.Text(parent, "GameFontNormal")
  fs:SetPoint("TOPLEFT", 8, -6)
  fs:SetText(text)
  return fs
end

local function Sources(xp)
  local segs, legend, total = {}, {}, 0
  for _, s in ipairs(L.SOURCES) do total = total + (xp[s] or 0) end
  for _, s in ipairs(L.SOURCES) do
    local v = xp[s] or 0
    if v > 0 then
      segs[#segs + 1] = { v, C[s] }
      local pct = math.floor(v / total * 100 + 0.5)
      legend[#legend + 1] = { ("%s %d%%"):format(NAMES[s], pct), C[s] }
    end
  end
  return segs, legend, total
end

local function Build(p)
  local w = p:GetWidth()
  p.level = W.Text(p, "GameFontNormalHuge")
  p.level:SetPoint("TOPLEFT", 2, 0)
  p.rested = W.Text(p, "GameFontHighlight", "RIGHT")
  p.rested:SetPoint("TOPRIGHT", -2, -6)
  p.bar = W.Bar(p, 20)
  p.bar:SetPoint("TOPLEFT", 0, -30)
  p.bar:SetPoint("TOPRIGHT", 0, -30)
  p.bar.text:SetFontObject("GameFontHighlight")

  local tw = (w - 3 * 8) / 4
  p.tiles = {}
  for i = 1, 4 do
    local t = W.Tile(p, tw, 58)
    t:SetPoint("TOPLEFT", (i - 1) * (tw + 8), -60)
    p.tiles[i] = t
  end

  local half = (w - 8) / 2
  p.src = W.Box(p)
  p.src:SetSize(half, 104)
  p.src:SetPoint("TOPLEFT", 0, -128)
  Header(p.src, "Where the XP came from")
  p.srcLevelLabel = W.Text(p.src, "GameFontDisableSmall")
  p.srcLevelLabel:SetPoint("TOPLEFT", 8, -26)
  p.srcLevel = W.Bar(p.src, 12)
  p.srcLevel:SetPoint("TOPLEFT", 8, -38)
  p.srcLevel:SetPoint("TOPRIGHT", -8, -38)
  p.srcSessLabel = W.Text(p.src, "GameFontDisableSmall")
  p.srcSessLabel:SetPoint("TOPLEFT", 8, -56)
  p.srcSess = W.Bar(p.src, 12)
  p.srcSess:SetPoint("TOPLEFT", 8, -68)
  p.srcSess:SetPoint("TOPRIGHT", -8, -68)
  p.legend = W.Legend(p.src)
  p.legend:SetPoint("BOTTOMLEFT", 8, 6)
  p.legend:SetPoint("BOTTOMRIGHT", -8, 6)

  p.spark = W.Box(p)
  p.spark:SetSize(half, 104)
  p.spark:SetPoint("TOPRIGHT", 0, -128)
  p.sparkTitle = Header(p.spark, "This session, XP per 5 min")
  p.sparkPeak = W.Text(p.spark, "GameFontDisableSmall", "RIGHT")
  p.sparkPeak:SetPoint("TOPRIGHT", -8, -8)
  p.cols = W.Columns(p.spark, half - 16, 66)
  p.cols:SetPoint("BOTTOMLEFT", 8, 8)
  p.sparkEmpty = W.Text(p.spark, "GameFontDisable", "CENTER")
  p.sparkEmpty:SetPoint("CENTER", 0, -8)

  p.hist = W.Box(p)
  p.hist:SetPoint("TOPLEFT", 0, -240)
  p.hist:SetPoint("BOTTOMRIGHT", 0, 0)
  Header(p.hist, "Played time per level")
  p.histKey = W.Text(p.hist, "GameFontDisableSmall", "RIGHT")
  p.histKey:SetPoint("TOPRIGHT", -8, -8)
  p.histKey:SetText("played  |cff808080real time since the ding|r")
  p.rows = {}
  for i = 1, HISTORY_ROWS do
    local r = CreateFrame("Frame", nil, p.hist)
    r:SetHeight(20)
    r:SetPoint("TOPLEFT", 8, -26 - (i - 1) * 21)
    r:SetPoint("TOPRIGHT", -8, -26 - (i - 1) * 21)
    r.lv = W.Text(r, "GameFontNormalSmall")
    r.lv:SetPoint("LEFT", 0, 0)
    r.lv:SetWidth(42)
    r.bar = W.Bar(r, 12)
    r.bar:SetPoint("LEFT", 46, 0)
    r.bar:SetPoint("RIGHT", -170, 0)
    r.val = W.Text(r, "GameFontHighlightSmall", "RIGHT")
    r.val:SetPoint("RIGHT", 0, 0)
    r.val:SetWidth(164)
    p.rows[i] = r
  end
  p.histEmpty = W.Text(p.hist, "GameFontDisable", "CENTER")
  p.histEmpty:SetPoint("CENTER", 0, -10)
end

local function Refresh(p)
  local rec, lvl = L.Current()
  local xp, max = UnitXP("player"), math.max(UnitXPMax("player"), 1)
  local rested = GetXPExhaustion() or 0
  local maxed = lvl >= (GetMaxPlayerLevel and GetMaxPlayerLevel() or 60)
  p.level:SetText(("Level %d"):format(lvl))
  p.rested:SetText(rested > 0 and W.Paint(C.rested, "Rested " .. K.Count(rested)
    .. (" (%d%% of a level)"):format(math.floor(rested / max * 100 + 0.5))) or "")
  p.bar:SetSegments({ { xp, C.xp }, { math.min(rested, max - xp), C.restedXP, 0.45 } }, max)
  p.bar.text:SetText(maxed and "Max level" or ("%s / %s XP   %d%%   %s to go"):format(
    K.Count(xp), K.Count(max), math.floor(xp / max * 100), K.Count(max - xp)))

  local now, sess = L.Rates()
  local s = L.Session() or {}
  local secs = L.SessionSecs()
  local eta, kills = L.ETA(), L.KillsToLevel()
  local playedLvl = L.PlayedNow() and rec.startPlayed and L.PlayedNow() - rec.startPlayed
  local real = rec.startReal and K.Now() - rec.startReal
  p.tiles[1]:Set("XP per hour now", now and (K.Count(now) .. "/h") or nil, "last 15 min")
  p.tiles[2]:Set("This session", sess and (K.Count(sess) .. "/h") or nil,
    ("%s, %s XP"):format(K.Duration(secs), K.Count(s.xp or 0)))
  p.tiles[3]:Set("Next level in", eta and K.Duration(eta) or nil,
    eta and (kills and ("~%d kills at this rate"):format(kills) or "at this rate")
    or "needs a few minutes of XP")
  p.tiles[4]:Set("This level so far", playedLvl and K.Duration(playedLvl) or "...",
    real and ("played, over " .. K.Duration(real)) or "played")

  local segs, legend, total = Sources(rec.xp)
  p.srcLevelLabel:SetText(("This level: %s XP"):format(K.Count(total)))
  p.srcLevel:SetSegments(segs)
  local ssegs, slegend, stotal = Sources(s.src or {})
  p.srcSessLabel:SetText(("This session: %s XP"):format(K.Count(stotal)))
  p.srcSess:SetSegments(ssegs)
  p.legend:Set(#legend > 0 and legend or slegend)

  local buckets, n = {}, math.max(1, math.floor(secs / 300) + 1)
  local first = math.max(1, n - 39)
  local peak = 0
  for i = first, n do
    local v = L.buckets[i] or 0
    buckets[#buckets + 1] = v
    peak = math.max(peak, v)
  end
  p.cols:SetData(buckets, function(i) return i == #buckets and C.gold or C.xp end, peak)
  p.sparkPeak:SetText(peak > 0 and ("peak " .. K.Count(peak)) or "")
  p.sparkEmpty:SetText(peak > 0 and "" or "No XP yet this session")

  -- newest levels first, current on top
  local levels = {}
  for l, r in pairs(K.db.levels) do
    local played = r.played or (l == lvl and playedLvl) or nil
    if played then levels[#levels + 1] = { l = l, r = r, played = played } end
  end
  table.sort(levels, function(a, b) return a.l > b.l end)
  local longest = 1
  for i = 1, math.min(#levels, HISTORY_ROWS) do
    longest = math.max(longest, levels[i].played)
  end
  for i, row in ipairs(p.rows) do
    local e = levels[i]
    row:SetShown(e ~= nil)
    if e then
      local live = e.l == lvl
      row.lv:SetText(("Lv %d"):format(e.l))
      row.bar:SetSegments({ { e.played, live and C.gold or C.xp } }, longest)
      local realT = e.r.real or (live and real)
      local realText = realT and ("  |cff808080" .. K.Duration(realT) .. "|r") or ""
      local nowText = live and "  |cffffd100now|r" or ""
      row.val:SetText(K.Duration(e.played) .. realText .. nowText)
    end
  end
  p.histEmpty:SetText(#levels == 0 and "Waiting for /played (a few seconds after login)"
    or "")
end

K.UI.pages.level = { Build = Build, Refresh = Refresh }
