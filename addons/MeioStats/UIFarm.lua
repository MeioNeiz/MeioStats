-- Farming tab: the farm going now (or a Start button), then past farms with time, gold
-- looted, item worth and the total per hour, best per hour marked, every character.
local _, K = ...
local W, G, F = K.Widgets, K.Gold, K.Farm
local C = W.C

local ROWS = 10
local COLS = {
  { key = "time", w = 54, text = "time", tip = "Farming time, AFK left out" },
  { key = "gold", w = 70, text = "gold", tip = "Gold looted" },
  { key = "items", w = 70, text = "items", tip = "What the looted items are worth" },
  { key = "rate", w = 70, text = "per hour", tip = "Gold and items per hour" },
}

local function Dim(text) return "|cff808080" .. text .. "|r" end

local function FarmTooltip(row)
  local f = row.farm
  if not f then return end
  local tt = GameTooltip
  tt:SetOwner(row, "ANCHOR_RIGHT")
  tt:SetText(f.zone or "?")
  tt:AddLine(date("%d %b %Y %H:%M", f.start) .. "  " .. ((f.char or ""):match("^[^-]+") or ""),
    0.6, 0.6, 0.6)
  tt:AddDoubleLine("Time", K.Duration(f.secs), 1, 0.82, 0, 1, 1, 1)
  tt:AddDoubleLine("Gold looted", K.Coins(f.gold), 1, 0.82, 0, 1, 1, 1)
  tt:AddDoubleLine("Items worth", K.Coins(f.value or 0), 1, 0.82, 0, 1, 1, 1)
  if (f.loots or 0) > 0 then tt:AddDoubleLine("Looted", f.loots, 1, 0.82, 0, 1, 1, 1) end
  local top = F.Top(f.items or {})
  if #top > 0 then
    tt:AddLine(" ")
    for i = 1, math.min(8, #top) do
      local e = top[i]
      tt:AddDoubleLine(W.ItemName(e.id) .. (e.n > 1 and (" x" .. e.n) or ""),
        e.each and K.Coins(e.value) or Dim("no price"), 1, 1, 1, 1, 1, 1)
    end
  end
  tt:Show()
end

local function Build(p)
  local w = p:GetWidth()
  local tw = (w - 3 * 8 - 128) / 4
  p.tiles = {}
  for i = 1, 4 do
    local t = W.Tile(p, tw, 58)
    t:SetPoint("TOPLEFT", (i - 1) * (tw + 8), 0)
    p.tiles[i] = t
  end
  p.toggle = CreateFrame("Button", nil, p, "UIPanelButtonTemplate")
  p.toggle:SetSize(120, 26)
  p.toggle:SetPoint("TOPRIGHT", 0, -6)
  p.toggle:SetScript("OnClick", function() F.Toggle() K.UI.pages.farm.Refresh(p) end)
  p.zone = W.Text(p, "GameFontDisableSmall", "CENTER")
  p.zone:SetPoint("TOP", p.toggle, "BOTTOM", 0, -6)
  p.zone:SetWidth(124)

  p.list = W.Box(p)
  p.list:SetPoint("TOPLEFT", 0, -66)
  p.list:SetPoint("BOTTOMRIGHT")
  p.listTitle = W.Header(p.list, "Past farms")
  local t = W.Table(p.list, COLS, { rows = ROWS, lead = 300, bar = true })
  p.rows = t.rows
  for _, r in ipairs(t.rows) do
    r.name:SetFontObject("GameFontHighlightSmall")
    r:SetScript("OnEnter", FarmTooltip)
  end
  p.empty = W.Text(p.list, "GameFontDisable", "CENTER")
  p.empty:SetPoint("CENTER", 0, -8)
  p.empty:SetWidth(w - 60)
  p.empty:SetWordWrap(true)
end

local function Refresh(p)
  local f = F.Active()
  if f then
    local value, unpriced = F.Worth(f.items)
    local ph = F.PerHour(f, value)
    p.tiles[1]:Set("Farming", K.Duration(f.secs), f.loots .. " looted")
    p.tiles[2]:Set("Gold looted", K.Coins(f.gold))
    p.tiles[3]:Set("Items worth", K.Coins(value), unpriced > 0 and (unpriced .. " without a price")
      or nil)
    p.tiles[4]:Set("Per hour", ph and K.Coins(ph), ph and "gold + items" or "after a minute")
    p.toggle:SetText("Stop farming")
    p.zone:SetText(F.MainZone(f))
  else
    p.tiles[1]:Set("Farming", Dim("off"), "/stats farm")
    p.tiles[2]:Set("Gold looted", nil)
    p.tiles[3]:Set("Items worth", nil)
    p.tiles[4]:Set("Per hour", nil)
    p.toggle:SetText("Start farming")
    p.zone:SetText("")
  end

  local farms = G.DB().farms
  local best, bestRate = nil, 0
  for _, x in ipairs(farms) do
    local r = F.PerHour(x, x.value)
    if r and r > bestRate then best, bestRate = x, r end
  end
  local peak = math.max(1, bestRate)
  for i, row in ipairs(p.rows) do
    local x = farms[#farms - i + 1]
    row.farm = x
    row:SetShown(x ~= nil)
    if x then
      local rate = F.PerHour(x, x.value)
      row.name:SetText((x.zone or "?") .. Dim("  " .. date("%d %b", x.start))
        .. (x == best and W.Paint(C.good, "  best") or ""))
      row.bar:SetSegments({ { rate or 0, x == best and C.good or C.gold, 0.8 } }, peak)
      row.cells.time:SetText(K.Duration(x.secs))
      row.cells.gold:SetText(K.Coins(x.gold))
      row.cells.items:SetText(K.Coins(x.value or 0))
      row.cells.rate:SetText(rate and K.Coins(rate) or Dim("-"))
    end
  end
  p.listTitle:SetText(("Past farms (%d)"):format(#farms))
  p.empty:SetText(#farms == 0 and ("Start farming, kill and loot, then stop: each farm shows"
    .. " here with its gold and items per hour, so you can compare spots") or "")
end

K.UI.pages.farm = { Build = Build, Refresh = Refresh }
