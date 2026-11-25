-- Zones tab: dungeon runs (time, XP per hour against questing and grinding at that level,
-- kills, deaths, gold), then XP per hour per zone around your level.
local _, K = ...
local W, R = K.Widgets, K.Runs
local C = W.C

local RUN_ROWS, ZONE_ROWS = 6, 8
local BAND = 2   -- zones at your level and the BAND levels below

local KILLS = "Interface\\Icons\\INV_Sword_04"
local DEATHS = "Interface\\TargetingFrame\\UI-TargetingFrame-Skull"
local GOLD = "Interface\\MoneyFrame\\UI-GoldIcon"
local CLOCK = "Interface\\Icons\\INV_Misc_PocketWatch_01"
local TRIM = { 0.08, 0.92, 0.08, 0.92 }

local RUN_COLS = {
  { key = "time", w = 46, icon = CLOCK, coords = TRIM, tip = "Time inside" },
  { key = "rate", w = 48, text = "XP/h", tip = "XP per hour inside" },
  { key = "kills", w = 30, icon = KILLS, coords = TRIM, tip = "Kills" },
  { key = "deaths", w = 22, icon = DEATHS, tip = "Deaths" },
  { key = "gold", w = 58, icon = GOLD, tip = "Gold looted, minus repairs" },
}
local ZONE_COLS = {
  { key = "levels", w = 40, text = "level", tip = "Your level while there" },
  { key = "time", w = 46, icon = CLOCK, coords = TRIM, tip = "Played time there" },
  { key = "rate", w = 48, text = "XP/h", tip = "XP per hour there" },
  { key = "gold", w = 58, icon = GOLD, tip = "Gold per hour there" },
}

local function Dim(text) return "|cff808080" .. text .. "|r" end

local function Ago(t)
  local days = math.floor((K.Now() - t) / 86400)
  if days <= 0 then return "today" end
  if days == 1 then return "yesterday" end
  return days .. " days ago"
end

local function Rate(xp, secs) return secs >= 60 and xp / secs * 3600 or nil end

-- one format down the column: 9.8k, 13.0k
local function PerHour(n) return n >= 1000 and ("%.1fk"):format(n / 1000) or K.Count(n) end

-- "+40% vs questing" against open-world XP/h at that level
local function Versus(rate, base)
  if not (rate and base and base > 0) then return nil end
  local pct = math.floor((rate / base - 1) * 100 + 0.5)
  if math.abs(pct) < 5 then return "same as outside" end
  return W.Paint(pct > 0 and C.good or C.bad, ("%+d%%"):format(pct)) .. " vs outside"
end

local function RunTooltip(row)
  local r = row.run
  if not r then return end
  local tt = GameTooltip
  tt:SetOwner(row, "ANCHOR_RIGHT")
  tt:SetText(r.name)
  tt:AddLine(("Level %d, %s"):format(r.level, date("%d %b %H:%M", r.start)), 0.6, 0.6, 0.6)
  tt:AddDoubleLine("Time inside", K.Duration(r.secs), 1, 0.82, 0, 1, 1, 1)
  tt:AddDoubleLine("XP", K.Count(r.xp), 1, 0.82, 0, 1, 1, 1)
  local rate, base = Rate(r.xp, r.secs), R.OpenWorldRate(r.level - BAND, r.level)
  if rate then tt:AddDoubleLine("XP per hour", K.Count(rate), 1, 0.82, 0, 1, 1, 1) end
  if base then
    tt:AddDoubleLine(("Outside dungeons, level %d-%d"):format(math.max(1, r.level - BAND),
      r.level), K.Count(base) .. "/h", 1, 0.82, 0, 1, 1, 1)
  end
  local vs = Versus(rate, base)
  if vs then tt:AddLine(vs) end
  if R.Open() == r then tt:AddLine("Still going", 0.25, 0.8, 0.3) end
  tt:Show()
end

local function ZoneTooltip(row)
  local z = row.zone
  if not z then return end
  local tt = GameTooltip
  tt:SetOwner(row, "ANCHOR_RIGHT")
  tt:SetText(z.name)
  tt:AddDoubleLine("Played", K.Duration(z.secs), 1, 0.82, 0, 1, 1, 1)
  tt:AddDoubleLine("XP", K.Count(z.xp), 1, 0.82, 0, 1, 1, 1)
  if z.secs > 0 then
    tt:AddDoubleLine("Kills per hour", K.Count(z.kills / z.secs * 3600), 1, 0.82, 0, 1, 1, 1)
  end
  if z.deaths > 0 then tt:AddDoubleLine("Deaths", z.deaths, 1, 0.82, 0, 1, 1, 1) end
  tt:Show()
end

local function Build(p)
  p.runs = W.Box(p)
  p.runs:SetPoint("TOPLEFT")
  p.runs:SetPoint("TOPRIGHT")
  p.runs:SetHeight(28 + RUN_ROWS * 21 + 4)
  W.Header(p.runs, "Dungeon runs")
  local t = W.Table(p.runs, RUN_COLS, { rows = RUN_ROWS, lead = 230, bar = true })
  p.runRows = t.rows
  for _, r in ipairs(t.rows) do
    r.name:SetFontObject("GameFontHighlightSmall")
    r.sub = W.Text(r, "GameFontDisableSmall", "RIGHT")
    r.sub:SetPoint("RIGHT", r.name, "RIGHT", 0, 0)
    r:SetScript("OnEnter", RunTooltip)
  end
  p.runsEmpty = W.Text(p.runs, "GameFontDisable", "CENTER")
  p.runsEmpty:SetPoint("CENTER", 0, -8)

  p.zones = W.Box(p)
  p.zones:SetPoint("TOPLEFT", p.runs, "BOTTOMLEFT", 0, -8)
  p.zones:SetPoint("BOTTOMRIGHT")
  p.zoneTitle = W.Header(p.zones, "")
  t = W.Table(p.zones, ZONE_COLS, { rows = ZONE_ROWS, lead = 186, bar = true })
  p.zoneRows = t.rows
  for _, r in ipairs(t.rows) do
    r.name:SetFontObject("GameFontHighlightSmall")
    r:SetScript("OnEnter", ZoneTooltip)
  end
  p.zonesEmpty = W.Text(p.zones, "GameFontDisable", "CENTER")
  p.zonesEmpty:SetPoint("CENTER", 0, -8)
end

local function Refresh(p)
  local runs = R.Runs()
  local best = 1
  for i = 1, math.min(#runs, RUN_ROWS) do
    best = math.max(best, Rate(runs[i].xp, runs[i].secs) or 0)
  end
  for i, row in ipairs(p.runRows) do
    local r = runs[i]
    row:SetShown(r ~= nil)
    row.run = r
    if r then
      local rate = Rate(r.xp, r.secs)
      local live = R.Open() == r
      row.name:SetText(r.name)
      row.sub:SetText(live and W.Paint(C.good, "now") or ("Lv %d, %s"):format(r.level,
        Ago(r.start)))
      row.bar:SetSegments({ { rate or 0, live and C.gold or C.xp } }, best)
      row.cells.time:SetText(K.Duration(r.secs))
      row.cells.rate:SetText(rate and PerHour(rate) or Dim("-"))
      row.cells.kills:SetText(r.kills > 0 and r.kills or Dim("0"))
      row.cells.deaths:SetText(r.deaths > 0 and r.deaths or Dim("0"))
      row.cells.gold:SetText(r.gold ~= 0 and K.Coins(r.gold, r.gold < 0) or Dim("0"))
    end
  end
  p.runsEmpty:SetText(#runs == 0
    and "Each dungeon you run shows here: time, XP per hour, kills, deaths, gold" or "")

  local lvl = UnitLevel("player")
  local from = math.max(1, lvl - BAND)
  local zones = R.Zones(from, lvl, 120)
  local base = R.OpenWorldRate(from, lvl)
  p.zoneTitle:SetText(("Zones at level %d-%d"):format(from, lvl)
    .. (base and Dim(("   outside dungeons %s XP/h"):format(K.Count(base))) or ""))
  best = 1
  for i = 1, math.min(#zones, ZONE_ROWS) do best = math.max(best, zones[i].rate) end
  for i, row in ipairs(p.zoneRows) do
    local z = zones[i]
    row:SetShown(z ~= nil)
    row.zone = z
    if z then
      local here = R.Zone() and R.Zone().name == z.name
      row.name:SetText(z.name .. (z.dungeon and Dim("  dungeon") or ""))
      row.bar:SetSegments({ { z.rate, here and C.gold or (z.dungeon and C.rested or C.xp) } },
        best)
      row.cells.levels:SetText(Dim(z.from == z.to and z.from or (z.from .. "-" .. z.to)))
      row.cells.time:SetText(K.Duration(z.secs))
      row.cells.rate:SetText(PerHour(z.rate))
      local gph = z.secs >= 300 and z.gold / z.secs * 3600
      row.cells.gold:SetText(gph and gph ~= 0 and K.Coins(gph, gph < 0) or Dim("-"))
    end
  end
  p.zonesEmpty:SetText(#zones == 0 and "Zones you level in show here after a few minutes"
    or "")
end

K.UI.pages.zones = { Build = Build, Refresh = Refresh }
