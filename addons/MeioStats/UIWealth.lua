-- Wealth tab: what the account is worth (every character, Meionomics' places: gold, bags,
-- bank, gear, mail, on AH) now and day by day, and where gold came from and went.
local _, K = ...
local W, G = K.Widgets, K.Gold
local C = W.C

local DAYS = 30
local ROWS = 9
local PLACE_COLOURS = {
  money = { 1, 0.82, 0 }, bags = { 0.35, 0.8, 0.4 }, bank = { 0.25, 0.55, 1 },
  equipped = { 0.58, 0.3, 0.75 }, mail = { 0.85, 0.55, 0.25 }, auctions = { 0.9, 0.3, 0.45 },
}
local COLS = {
  { key = "i", w = 74, text = "in", tip = "Gold that came in" },
  { key = "o", w = 74, text = "out", tip = "Gold that went out" },
  { key = "net", w = 80, text = "net", tip = "In minus out" },
}

local function Dim(text) return "|cff808080" .. text .. "|r" end
local function Signed(c)
  if c == 0 then return Dim("0") end
  return W.Paint(c > 0 and C.good or C.bad, K.Coins(c, true))
end

-- the worth snapshot at or before `days` days ago
local function Back(days, list)
  local day = G.Day(K.Now() - days * 86400)
  local hit
  for _, e in ipairs(list) do
    if e.day <= day then hit = e end
  end
  return hit
end

local function ColumnTooltip(col)
  local e = col.entry
  if not e then return end
  local tt = GameTooltip
  tt:SetOwner(col, "ANCHOR_RIGHT")
  tt:SetText(tostring(date("%d %b %Y", e.w.t)))
  tt:AddDoubleLine("Account value", K.Coins(e.w.total), 1, 0.82, 0, 1, 1, 1)
  for _, p in ipairs(G.PLACES) do
    if (e.w[p] or 0) > 0 then
      local c = PLACE_COLOURS[p]
      tt:AddDoubleLine(G.PLACE_NAMES[p], K.Coins(e.w[p]), c[1], c[2], c[3], 1, 1, 1)
    end
  end
  if IsShiftKeyDown() then
    tt:AddLine(" ")
    local chars = {}
    for name, v in pairs(e.w.chars or {}) do chars[#chars + 1] = { name = name, v = v } end
    table.sort(chars, function(a, b) return a.v.total > b.v.total end)
    for _, c in ipairs(chars) do
      tt:AddDoubleLine(c.name, K.Coins(c.v.total), 1, 1, 1, 1, 1, 1)
    end
  elseif not tt.meioShiftHint then
    tt:AddLine("Shift: more", 0.6, 0.6, 0.6)
    tt.meioShiftHint = true
  end
  tt:Show()
end

local function FlowTooltip(row)
  if not row.source then return end
  GameTooltip:SetOwner(row, "ANCHOR_RIGHT")
  GameTooltip:SetText(G.NAMES[row.source] or row.source)
  GameTooltip:AddDoubleLine("In", K.Coins(row.flow.i), 1, 0.82, 0, 1, 1, 1)
  GameTooltip:AddDoubleLine("Out", K.Coins(row.flow.o), 1, 0.82, 0, 1, 1, 1)
  GameTooltip:Show()
end

local function Build(p)
  local w = p:GetWidth()
  local tw = (w - 3 * 8) / 4
  p.tiles = {}
  for i = 1, 4 do
    local t = W.Tile(p, tw, 58)
    t:SetPoint("TOPLEFT", (i - 1) * (tw + 8), 0)
    p.tiles[i] = t
  end

  p.chart = W.Box(p)
  p.chart:SetPoint("TOPLEFT", 0, -66)
  p.chart:SetPoint("TOPRIGHT", 0, -66)
  p.chart:SetHeight(128)
  W.Header(p.chart, "Account value, last 30 days")
  p.legend = W.Legend(p.chart)
  p.legend:SetPoint("TOPRIGHT", -8, -8)
  p.legend:SetWidth(330)
  local list = {}
  for _, pl in ipairs(G.PLACES) do list[#list + 1] = { G.PLACE_NAMES[pl], PLACE_COLOURS[pl] } end
  p.legend:Set(list)
  p.area = CreateFrame("Frame", nil, p.chart)
  p.area:SetPoint("TOPLEFT", 8, -28)
  p.area:SetPoint("BOTTOMRIGHT", -8, 18)
  local base = p.area:CreateTexture(nil, "BORDER")
  base:SetPoint("BOTTOMLEFT")
  base:SetPoint("BOTTOMRIGHT")
  base:SetHeight(1)
  base:SetColorTexture(1, 1, 1, 0.2)
  p.columns = {}
  local ago = W.Text(p.chart, "GameFontDisableSmall")
  ago:SetPoint("BOTTOMLEFT", 8, 5)
  ago:SetText("30 days ago")
  local today = W.Text(p.chart, "GameFontDisableSmall", "RIGHT")
  today:SetPoint("BOTTOMRIGHT", -8, 5)
  today:SetText("today")
  p.peak = W.Text(p.chart, "GameFontDisableSmall", "CENTER")
  p.peak:SetPoint("BOTTOM", 0, 5)

  p.flows = W.Box(p)
  p.flows:SetPoint("TOPLEFT", p.chart, "BOTTOMLEFT", 0, -8)
  p.flows:SetPoint("BOTTOMRIGHT")
  p.flowTitle = W.Header(p.flows, "")
  p.days, p.mine = 7, false
  p.span = CreateFrame("Button", nil, p.flows, "UIPanelButtonTemplate")
  p.span:SetSize(90, 20)
  p.span:SetPoint("TOPRIGHT", -6, -3)
  p.span:SetScript("OnClick", function()
    p.days = p.days == 7 and 30 or (p.days == 30 and 1 or 7)
    K.UI.pages.wealth.Refresh(p)
  end)
  p.who = CreateFrame("Button", nil, p.flows, "UIPanelButtonTemplate")
  p.who:SetSize(110, 20)
  p.who:SetPoint("RIGHT", p.span, "LEFT", -4, 0)
  p.who:SetScript("OnClick", function()
    p.mine = not p.mine
    K.UI.pages.wealth.Refresh(p)
  end)
  -- column heads under the buttons
  local t = W.Table(p.flows, COLS, { rows = ROWS, lead = 110, bar = true, top = -44 })
  for _, h in pairs(t.heads) do
    local _, _, _, x = h:GetPoint(1)
    h:ClearAllPoints()
    h:SetPoint("TOPRIGHT", p.flows, "TOPRIGHT", x, -26)
  end
  p.rows = t.rows
  for _, r in ipairs(t.rows) do
    r.name:SetFontObject("GameFontHighlightSmall")
    r:SetScript("OnEnter", FlowTooltip)
  end
  p.empty = W.Text(p.flows, "GameFontDisable", "CENTER")
  p.empty:SetPoint("CENTER", 0, -10)
end

local function Column(p, i)
  local c = p.columns[i]
  if not c then
    c = CreateFrame("Frame", nil, p.area)
    c.segs = {}
    c:EnableMouse(true)
    c:SetScript("OnEnter", ColumnTooltip)
    c:SetScript("OnLeave", function() GameTooltip:Hide() end)
    local hl = c:CreateTexture(nil, "HIGHLIGHT")
    hl:SetAllPoints()
    hl:SetColorTexture(1, 1, 1, 0.08)
    p.columns[i] = c
  end
  return c
end

local function DrawChart(p, days)
  local byDay = {}
  for _, e in ipairs(days) do byDay[e.day] = e end
  local peak = 0
  for _, e in ipairs(days) do peak = math.max(peak, e.w.total) end
  local aw, ah = p.area:GetWidth(), p.area:GetHeight()
  local slot = aw / DAYS
  local now = K.Now()
  for i = 1, DAYS do
    local e = byDay[G.Day(now - (DAYS - i) * 86400)]
    local c = Column(p, i)
    c.entry = e
    c:ClearAllPoints()
    c:SetPoint("BOTTOMLEFT", (i - 1) * slot, 1)
    c:SetSize(math.max(1, slot - 3), ah - 1)
    local y = 0
    for k, pl in ipairs(G.PLACES) do
      local seg = c.segs[k]
      if not seg then
        seg = c:CreateTexture(nil, "ARTWORK")
        seg:SetTexture("Interface\\TargetingFrame\\UI-StatusBar")
        c.segs[k] = seg
      end
      local hgt = e and peak > 0 and (ah - 1) * (e.w[pl] or 0) / peak or 0
      if hgt >= 0.5 then
        local col = PLACE_COLOURS[pl]
        seg:ClearAllPoints()
        seg:SetPoint("BOTTOMLEFT", 0, y)
        seg:SetPoint("BOTTOMRIGHT", 0, y)
        seg:SetHeight(hgt)
        seg:SetVertexColor(col[1], col[2], col[3], 0.9)
        seg:Show()
        y = y + hgt
      else
        seg:Hide()
      end
    end
  end
  p.peak:SetText(peak > 0 and ("highest " .. K.Coins(peak)) or "")
end

local function Refresh(p)
  local days = G.WorthDays()
  local now = days[#days]
  local today = now and now.day == G.Day() and now or nil
  if not today then
    G.SnapWorth()
    days = G.WorthDays()
    now = days[#days]
  end
  local w = now and now.w
  local gold = w and w.goldOnly
  p.tiles[1]:Set("Account value", w and K.Coins(w.total),
    gold and "gold only: needs Meionomics" or (w and ("%d characters"):format(
      (function() local n = 0 for _ in pairs(w.chars) do n = n + 1 end return n end)())))
  p.tiles[2]:Set("Gold", w and K.Coins(w.money), "every character")
  for i, span in ipairs({ 7, 30 }) do
    local b = Back(span, days)
    local change = b and w and b ~= now and w.total - b.w.total
    p.tiles[2 + i]:Set(("Last %d days"):format(span), change and Signed(change),
      change and ("from " .. K.Coins(b.w.total)) or "needs more days")
  end
  DrawChart(p, days)

  local flows = G.Flows(p.days, p.mine and G.Me() or nil)
  local list, peak, tin, tout = {}, 1, 0, 0
  for s, f in pairs(flows) do
    if f.i > 0 or f.o > 0 then
      list[#list + 1] = { source = s, flow = f }
      peak = math.max(peak, f.i, f.o)
      tin, tout = tin + f.i, tout + f.o
    end
  end
  table.sort(list, function(a, b) return a.flow.i + a.flow.o > b.flow.i + b.flow.o end)
  local span = p.days == 1 and "today" or ("last %d days"):format(p.days)
  p.flowTitle:SetText("Gold in and out, " .. span .. Dim(("   net %s"):format(
    K.Coins(tin - tout, true))))
  p.span:SetText(p.days == 1 and "Today" or (p.days .. " days"))
  p.who:SetText(p.mine and "This character" or "All characters")
  for i, row in ipairs(p.rows) do
    local e = list[i]
    row:SetShown(e ~= nil)
    row.source, row.flow = e and e.source, e and e.flow
    if e then
      row.name:SetText(G.NAMES[e.source] or e.source)
      row.bar:SetSegments({ { e.flow.i, C.good, 0.8 }, { e.flow.o, C.bad, 0.8 } }, peak * 2)
      row.cells.i:SetText(e.flow.i > 0 and K.Coins(e.flow.i) or Dim("-"))
      row.cells.o:SetText(e.flow.o > 0 and K.Coins(e.flow.o) or Dim("-"))
      row.cells.net:SetText(Signed(e.flow.i - e.flow.o))
    end
  end
  p.empty:SetText(#list == 0 and "Gold you loot, earn and spend shows here by where it came"
    .. " from" or "")
end

K.UI.pages.wealth = { Build = Build, Refresh = Refresh }
