-- Money tab: totals, the last 30 days earned vs spent, best sellers with profit.
local _, K = ...
local W, M = K.Widgets, K.Money
local C = W.C

local ROWS = 7
local DAYS = 30

local function Build(p)
  local w = p:GetWidth()
  local tw = (w - 4 * 8) / 5
  p.tiles = {}
  for i = 1, 5 do
    local t = W.Tile(p, tw, 58)
    t:SetPoint("TOPLEFT", (i - 1) * (tw + 8), 0)
    p.tiles[i] = t
  end

  p.days = W.Box(p)
  p.days:SetPoint("TOPLEFT", 0, -66)
  p.days:SetPoint("TOPRIGHT", 0, -66)
  p.days:SetHeight(108)
  local h = W.Text(p.days, "GameFontNormal")
  h:SetPoint("TOPLEFT", 8, -6)
  h:SetText("Last 30 days")
  p.daysLegend = W.Legend(p.days)
  p.daysLegend:SetPoint("TOPRIGHT", -8, -6)
  p.daysLegend:SetWidth(160)
  p.daysLegend:Set({ { "Earned", C.good }, { "Spent", C.bad } })
  p.cols = W.Columns(p.days, w - 16, 62)
  p.cols:SetPoint("BOTTOMLEFT", 8, 18)
  local ago = W.Text(p.days, "GameFontDisableSmall")
  ago:SetPoint("BOTTOMLEFT", 8, 5)
  ago:SetText("30 days ago")
  local today = W.Text(p.days, "GameFontDisableSmall", "RIGHT")
  today:SetPoint("BOTTOMRIGHT", -8, 5)
  today:SetText("today")
  p.daysPeak = W.Text(p.days, "GameFontDisableSmall")
  p.daysPeak:SetPoint("TOPLEFT", 120, -8)

  p.list = W.Box(p)
  p.list:SetPoint("TOPLEFT", 0, -182)
  p.list:SetPoint("BOTTOMRIGHT", 0, 0)
  p.listTitle = W.Text(p.list, "GameFontNormal")
  p.listTitle:SetPoint("TOPLEFT", 8, -6)
  p.listHint = W.Text(p.list, "GameFontDisableSmall", "RIGHT")
  p.listHint:SetPoint("TOPRIGHT", -112, -8)
  p.mode = "sold"
  p.toggle = CreateFrame("Button", nil, p.list, "UIPanelButtonTemplate")
  p.toggle:SetSize(100, 20)
  p.toggle:SetPoint("TOPRIGHT", -6, -3)
  p.toggle:SetScript("OnClick", function()
    p.mode, p.offset = p.mode == "sold" and "bought" or "sold", 0
    K.UI.pages.money.Refresh(p)
  end)
  p.rows = {}
  for i = 1, ROWS do
    local r = W.ItemRow(p.list, w - 16, 30)
    r:SetPoint("TOPLEFT", 8, -26 - (i - 1) * 32)
    r.bar = W.Bar(r, 3)
    r.bar:SetPoint("BOTTOMLEFT", r.icon, "BOTTOMRIGHT", 6, -3)
    r.bar:SetPoint("RIGHT", -4, 0)
    p.rows[i] = r
  end
  p.offset = 0
  p.list:EnableMouseWheel(true)
  p.list:SetScript("OnMouseWheel", function(_, delta)
    p.offset = math.max(0, math.min((p.count or 0) - ROWS, p.offset - delta * 3))
    K.UI.pages.money.Refresh(p)
  end)
  p.empty = W.Text(p.list, "GameFontDisable", "CENTER")
  p.empty:SetWordWrap(true)
  p.empty:SetWidth(w - 40)
  p.empty:SetPoint("CENTER", 0, -10)
end

local function Profit(e)
  if not e.profit then return "" end
  local c = e.profit >= 0 and C.good or C.bad
  return W.Paint(c, K.Coins(e.profit, true)) .. "|cff808080 vs "
    .. (e.basis == "buy" and "buy" or "mats") .. "|r"
end

local function Refresh(p)
  local t = M.Totals()
  local ledger = M.HasLedger()
  local function Coins(c) return ledger and K.Coins(c) or nil end
  local net = t.revenue + t.income - t.spent - t.expense
  local sessionChange = M.SessionChange()
  local needs = not ledger and "needs TSM" or nil
  p.tiles[1]:Set("AH sales", Coins(t.ahRevenue), needs or "after the AH cut")
  p.tiles[2]:Set("Vendor sales", Coins(t.vendorRevenue), needs)
  p.tiles[3]:Set("Bought", Coins(t.spent), needs or (t.expense > 0 and ("+ "
    .. K.Coins(t.expense) .. " repairs, fees") or ""))
  p.tiles[4]:Set("Net", ledger and W.Paint(net >= 0 and C.good or C.bad, K.Coins(net, true)),
    needs or (t.first < math.huge and ("since " .. date("%d %b", t.first)) or "nothing yet"))
  local change = sessionChange and W.Paint(sessionChange >= 0 and C.good or C.bad,
    K.Coins(sessionChange, true))
  p.tiles[5]:Set("This session", change, "gold change")

  local days = M.Daily(DAYS)
  local peak = 0
  for _, d in ipairs(days) do peak = math.max(peak, d[1], d[2]) end
  p.cols:SetData(days, { C.good, C.bad }, peak, 4)
  p.daysPeak:SetText(peak > 0 and ("best day " .. K.Coins(peak))
    or (ledger and "nothing in 30 days" or ""))

  local list = p.mode == "sold" and M.TopSold() or M.TopBought()
  p.count = #list
  p.offset = math.max(0, math.min(p.offset, #list - ROWS))
  p.listTitle:SetText(p.mode == "sold" and ("Items sold (%d)"):format(#list)
    or ("Bought, never sold (%d)"):format(#list))
  p.listHint:SetText(#list > ROWS and ("%d-%d, scroll for more"):format(p.offset + 1,
    math.min(#list, p.offset + ROWS)) or "")
  p.toggle:SetText(p.mode == "sold" and "Show bought" or "Show sold")
  p.toggle:SetShown(ledger)
  local top = list[1] and (p.mode == "sold" and list[1].r.revenue or list[1].r.spent) or 1
  for i, row in ipairs(p.rows) do
    local e = list[p.offset + i]
    row:SetShown(e ~= nil)
    if e then
      local r = e.r
      row.itemID = e.id
      row.icon:SetTexture(W.ItemIcon(e.id))
      row.name:SetText(W.ItemName(e.id))
      if p.mode == "sold" then
        local ah, other = r.ah, r.sold - r.ah - r.vendor
        local parts = {}
        if ah > 0 then parts[#parts + 1] = K.Count(ah) .. " on AH" end
        if r.vendor > 0 then parts[#parts + 1] = K.Count(r.vendor) .. " to vendor" end
        if other > 0 then parts[#parts + 1] = K.Count(other) .. " traded" end
        if r.bought > 0 then parts[#parts + 1] = "bought " .. K.Count(r.bought) end
        row.sub:SetText(table.concat(parts, ", "))
        row.right:SetText(K.Coins(r.revenue))
        row.right2:SetText(Profit(e))
        row.bar:SetSegments({ { r.revenue, C.good, 0.7 } }, top)
      else
        row.sub:SetText(("Bought %s, %s each"):format(K.Count(r.bought),
          K.Coins(r.spent / r.bought)))
        row.right:SetText(K.Coins(r.spent))
        row.right2:SetText("")
        row.bar:SetSegments({ { r.spent, C.bad, 0.7 } }, top)
      end
    end
  end
  local none = ledger and (p.mode == "sold" and "Nothing sold in TSM's ledger yet"
    or "Nothing bought that wasn't sold again")
    or "Needs TradeSkillMaster: sales and purchases come from its ledger.\n"
    .. "The This session tile works without it."
  p.empty:SetText(#list == 0 and none or "")
end

K.UI.pages.money = { Build = Build, Refresh = Refresh }
