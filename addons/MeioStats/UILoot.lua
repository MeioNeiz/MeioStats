-- Loot luck tab: quest drops against their drop rate (luck gauge), then everything else
-- looted, with the rate observed here.
local _, K = ...
local W, L = K.Widgets, K.Loot
local C = W.C

local RATED_ROWS, OBS_ROWS = 4, 5

local function Pct(f)
  if f >= 0.1 then return ("%d%%"):format(math.floor(f * 100 + 0.5)) end
  if f >= 0.01 then return ("%.1f%%"):format(f * 100) end
  return ("%.2f%%"):format(f * 100)
end

-- centred gauge: red (unlucky) .. grey .. green (lucky), marker at the mid-percentile
local function Gauge(parent, w)
  local f = CreateFrame("Frame", nil, parent)
  f:SetSize(w, 8)
  local half = w / 2
  local left = f:CreateTexture(nil, "BACKGROUND")
  left:SetPoint("TOPLEFT")
  left:SetSize(half, 8)
  left:SetColorTexture(1, 1, 1, 1)
  left:SetGradient("HORIZONTAL", CreateColor(C.bad[1], C.bad[2], C.bad[3], 0.9),
    CreateColor(0.3, 0.3, 0.3, 0.9))
  local right = f:CreateTexture(nil, "BACKGROUND")
  right:SetPoint("TOPRIGHT")
  right:SetSize(half, 8)
  right:SetColorTexture(1, 1, 1, 1)
  right:SetGradient("HORIZONTAL", CreateColor(0.3, 0.3, 0.3, 0.9),
    CreateColor(C.good[1], C.good[2], C.good[3], 0.9))
  local mid = f:CreateTexture(nil, "ARTWORK")
  mid:SetSize(1, 12)
  mid:SetPoint("CENTER")
  mid:SetColorTexture(1, 1, 1, 0.5)
  f.mark = f:CreateTexture(nil, "OVERLAY")
  f.mark:SetSize(4, 14)
  f.mark:SetColorTexture(1, 1, 1, 1)
  function f:Set(score)
    self.mark:ClearAllPoints()
    self.mark:SetPoint("CENTER", self, "LEFT", math.max(2, math.min(w - 2, score * w)), 0)
  end
  return f
end

local function Section(p, title, top, rows, gauge)
  local box = W.Box(p)
  box:SetPoint("TOPLEFT", 0, top)
  box:SetPoint("RIGHT")
  box:SetHeight(26 + rows * 32)
  box.title = W.Text(box, "GameFontNormal")
  box.title:SetPoint("TOPLEFT", 8, -6)
  box.title:SetText(title)
  box.hint = W.Text(box, "GameFontDisableSmall", "RIGHT")
  box.hint:SetPoint("TOPRIGHT", -8, -8)
  box.rows, box.offset = {}, 0
  local w = p:GetWidth() - 16
  for i = 1, rows do
    local r = W.ItemRow(box, w, 30)
    r:SetPoint("TOPLEFT", 8, -26 - (i - 1) * 32)
    if gauge then
      r.gauge = Gauge(r, 150)
      r.gauge:SetPoint("BOTTOMRIGHT", -4, 4)
      r.right:ClearAllPoints()
      r.right:SetPoint("TOPRIGHT", -4, -1)
    end
    box.rows[i] = r
  end
  box.empty = W.Text(box, "GameFontDisable", "CENTER")
  box.empty:SetPoint("CENTER", 0, -10)
  box:EnableMouseWheel(true)
  box:SetScript("OnMouseWheel", function(self, delta)
    self.offset = math.max(0, math.min((self.count or 0) - rows, self.offset - delta * 2))
    K.UI.pages.loot.Refresh(p)
  end)
  return box
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
  p.rated = Section(p, "Quest drops vs drop rate", -66, RATED_ROWS, true)
  local top = -66 - (26 + RATED_ROWS * 32) - 8
  p.obs = Section(p, "Everything else you looted", top, OBS_ROWS)
end

local VERDICT_COLOUR = { ["very lucky"] = C.good, lucky = C.good,
  ["as expected"] = C.neutral, unlucky = C.bad, ["very unlucky"] = C.bad }

local function Verdict(luck)
  local text = luck.verdict
  if luck.drops > luck.expected and luck.verdict ~= "as expected" then
    text = text .. ", top " .. Pct(luck.top)
  elseif luck.drops < luck.expected and luck.verdict ~= "as expected" then
    text = text .. ", bottom " .. Pct(luck.bottom)
  end
  return W.Paint(VERDICT_COLOUR[luck.verdict], text)
end

local function Page(box, list, rows)
  box.count = #list
  box.offset = math.max(0, math.min(box.offset, #list - rows))
  box.hint:SetText(#list > rows and ("%d-%d of %d, scroll"):format(box.offset + 1,
    math.min(#list, box.offset + rows), #list) or "")
end

local function Refresh(p)
  local rated, obs = L.RatedList(), L.ObservedList()
  local t = L.Totals()
  local drops, expected = 0, 0
  for _, e in ipairs(rated) do
    drops, expected = drops + e.luck.drops, expected + e.luck.expected
  end
  local rares, qty = 0, 0
  for _, e in ipairs(obs) do
    local _, _, q = C_Item.GetItemInfo(e.id)
    if q and q >= 2 then rares = rares + e.qty end
    qty = qty + e.qty
  end
  p.tiles[1]:Set("Kills counted", K.Count(t.kills), ("%d kinds of mob"):format(t.mobs))
  p.tiles[2]:Set("Items looted", K.Count(qty), ("%d kinds, %d green or better"):format(#obs,
    rares))
  local rates = L.HasRates()
  local locked = not rates and L.NoRatesReason() == "unreadable"
  local noRates = locked and "no drop rates" or "needs Questie"
  if #rated > 0 then
    p.tiles[3]:Set("Quest drops", K.Count(drops), ("expected %.1f"):format(expected))
  else
    p.tiles[3]:Set("Quest drops", nil, rates and "none yet" or noRates)
  end
  local diff = drops - expected
  local luck = #rated > 0 and W.Paint(diff >= 0 and C.good or C.bad,
    ("%+.1f drops"):format(diff)) or nil
  p.tiles[4]:Set("Overall luck", luck, luck and "vs drop rates"
    or (rates and "kill mobs for a quest item" or noRates))

  Page(p.rated, rated, RATED_ROWS)
  for i, row in ipairs(p.rated.rows) do
    local e = rated[p.rated.offset + i]
    row:SetShown(e ~= nil)
    if e then
      local luck = e.luck
      row.itemID = e.id
      row.icon:SetTexture(W.ItemIcon(e.id))
      row.name:SetText(W.ItemName(e.id))
      row.sub:SetText(("got |cffffffff%d|r in %d kills, expected %.1f (rate %s)"):format(
        luck.drops, luck.kills, luck.expected, Pct(luck.rate)))
      row.right:SetText(Verdict(luck))
      row.gauge:Set(luck.score)
    end
  end
  local none = rates and "Kill mobs for a quest item and its drop luck shows here"
    or locked and "This Questie doesn't share its drop rates. Quest items are still counted"
      .. " below."
    or "Needs Questie for drop rates. Quest items are still counted below."
  p.rated.empty:SetText(#rated == 0 and none or "")

  -- greens and better first, then by how often
  for _, e in ipairs(obs) do
    local _, _, q = C_Item.GetItemInfo(e.id)
    e.quality = q or 1
  end
  -- an item tracked for luck but with no drop rate (no Questie) isn't in the list above
  local shown = {}
  for _, e in ipairs(rated) do shown[e.id] = true end
  local list = {}
  for _, e in ipairs(obs) do
    if e.quality >= 1 and not shown[e.id] then list[#list + 1] = e end
  end
  table.sort(list, function(a, b)
    if a.quality ~= b.quality then return a.quality > b.quality end
    if a.drops ~= b.drops then return a.drops > b.drops end
    return a.id < b.id
  end)
  Page(p.obs, list, OBS_ROWS)
  for i, row in ipairs(p.obs.rows) do
    local e = list[p.obs.offset + i]
    row:SetShown(e ~= nil)
    if e then
      row.itemID = e.id
      row.icon:SetTexture(W.ItemIcon(e.id))
      row.name:SetText(W.ItemName(e.id))
      local from = e.best.name or ("mob " .. e.best.npcID)
      row.sub:SetText(e.mobs > 1 and ("from %s and %d more"):format(from, e.mobs - 1)
        or ("from " .. from))
      row.right:SetText(("%d in %d kills"):format(e.drops, e.kills))
      local rate = e.rate and (W.Paint(C.gold, Pct(e.rate)) .. "|cff808080 per kill|r")
      row.right2:SetText(rate or "")
    end
  end
  p.obs.empty:SetText(#list == 0 and "Nothing looted yet" or "")
end

K.UI.pages.loot = { Build = Build, Refresh = Refresh }
