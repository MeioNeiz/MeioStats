-- Journey tab: how far you went (on foot, mounted, by flight path, as a ghost), zones, deaths
-- and dungeons since recording started, and where you were at each level-up. A level's row
-- replays the trail on the world map from there.
local _, K = ...
local W, J = K.Widgets, K.Journey

local ROWS = 11
local COLS = {
  { key = "when", w = 90, text = "when", tip = "When you reached the level" },
  { key = "took", w = 60, text = "took", tip = "Played time the level before took" },
}

local function Dim(text) return "|cff808080" .. text .. "|r" end

-- yards to 850 m / 12.3 km
local function Distance(yd)
  local m = (yd or 0) * 0.9144
  if m < 1000 then return ("%d m"):format(m) end
  return ("%.1f km"):format(m / 1000)
end

local function RowTooltip(row)
  local m = row.mark
  if not m then return end
  local tt = GameTooltip
  tt:SetOwner(row, "ANCHOR_RIGHT")
  tt:SetText("Level " .. m.lvl)
  tt:AddLine(m.text or "", 1, 1, 1)
  tt:AddLine(tostring(date("%d %b %Y %H:%M", m.t)), 0.6, 0.6, 0.6)
  tt:AddLine("Click: replay your trail from here", 0.6, 0.6, 0.6)
  tt:Show()
end

local function Build(p)
  local tw = (K.UI.W - 32 - 3 * 8) / 4
  p.tiles = {}
  for i = 1, 8 do
    local t = W.Tile(p, tw)
    local col, row = (i - 1) % 4, math.floor((i - 1) / 4)
    t:SetPoint("TOPLEFT", col * (tw + 8), -row * 62)
    p.tiles[i] = t
  end

  p.list = W.Box(p)
  p.list:SetPoint("TOPLEFT", 0, -124)
  p.list:SetPoint("BOTTOMRIGHT", 0, 30)
  W.Header(p.list, "Level by level")
  local t = W.Table(p.list, COLS, { rows = ROWS, lead = 380 })
  p.rows = t.rows
  for _, r in ipairs(t.rows) do
    r.name:SetFontObject("GameFontHighlightSmall")
    r:SetScript("OnEnter", RowTooltip)
    r:SetScript("OnMouseUp", function(self)
      if self.mark then K.JourneyMap.Replay(self.mark.lvl) end
    end)
  end
  p.empty = W.Text(p.list, "GameFontDisable", "CENTER")
  p.empty:SetPoint("CENTER", 0, -8)
  p.empty:SetWidth(K.UI.W - 80)
  p.empty:SetWordWrap(true)

  p.replay = CreateFrame("Button", nil, p, "UIPanelButtonTemplate")
  p.replay:SetSize(170, 22)
  p.replay:SetPoint("BOTTOMLEFT", 0, 2)
  p.replay:SetText("Replay on the world map")
  p.replay:SetScript("OnClick", function() K.JourneyMap.Replay() end)
  p.trail = CreateFrame("CheckButton", nil, p, "UICheckButtonTemplate")
  p.trail:SetSize(24, 24)
  p.trail:SetPoint("LEFT", p.replay, "RIGHT", 12, 0)
  p.trail.text = W.Text(p.trail, "GameFontHighlightSmall")
  p.trail.text:SetPoint("LEFT", p.trail, "RIGHT", 0, 1)
  p.trail.text:SetText("Trail on the world map")
  p.trail:SetScript("OnClick", function(self)
    K.SetOption("trail", self:GetChecked() and true or false)
  end)
  p.since = W.Text(p, "GameFontDisableSmall", "RIGHT")
  p.since:SetPoint("BOTTOMRIGHT", -4, 8)
end

local function Refresh(p)
  local d = J.Data()
  local dist = d.dist
  local deaths, runs, dings = J.Marks("death"), J.Marks("run"), J.Marks("ding")
  p.tiles[1]:Set("On foot", Distance(dist.walk))
  p.tiles[2]:Set("Mounted", Distance(dist.ride))
  p.tiles[3]:Set("Flight paths", Distance(dist.fly))
  p.tiles[4]:Set("As a ghost", Distance(dist.ghost), dist.ghost > 0 and "corpse runs" or nil)
  p.tiles[5]:Set("Zones visited", tostring(J.ZoneCount()))
  p.tiles[6]:Set("Deaths", tostring(#deaths))
  p.tiles[7]:Set("Dungeon runs", tostring(#runs))
  p.tiles[8]:Set("Levels", tostring(#dings), #dings > 0 and ("%d to %d"):format(
    dings[1].lvl - 1, dings[#dings].lvl) or nil)

  for i, row in ipairs(p.rows) do
    local m = dings[#dings - i + 1]
    row.mark = m
    row:SetShown(m ~= nil)
    if m then
      local rec = K.db.levels and K.db.levels[m.lvl - 1]
      row.name:SetText("Level " .. m.lvl .. "   " .. (m.text or Dim("?")))
      row.cells.when:SetText(date("%d %b %H:%M", m.t))
      row.cells.took:SetText(rec and rec.played and K.Duration(rec.played) or Dim("-"))
    end
  end
  p.empty:SetText(#dings == 0 and ("Each level-up shows here with where you were. Your trail,"
    .. " deaths and dungeons go on the world map as you play.") or "")
  p.trail:SetChecked(K.Option("trail"))
  p.since:SetText("Recording since " .. date("%d %b %Y", d.since))
end

K.UI.pages.journey = { Build = Build, Refresh = Refresh }
