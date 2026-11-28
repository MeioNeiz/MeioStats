-- History tab: everything that moved gold or items, newest first, every character: trades,
-- auction sales and buys, mail in and out, vendor visits, quest rewards, green or better
-- loot, farming sessions. Filter buttons along the top; the wheel scrolls.
local _, K = ...
local W, G = K.Widgets, K.Gold
local C = W.C

local ROWS = 18
local FILTERS = {
  { key = "all", text = "All" },
  { key = "trade", text = "Trades", kinds = { trade = true } },
  { key = "ah", text = "Auctions", kinds = { ahsale = true, ahbuy = true } },
  { key = "mail", text = "Mail", kinds = { mail = true, sent = true } },
  { key = "vendor", text = "Vendor", kinds = { vendor = true } },
  { key = "quest", text = "Quests", kinds = { quest = true } },
  { key = "loot", text = "Loot", kinds = { loot = true } },
  { key = "farm", text = "Farming", kinds = { farm = true } },
}

local function Dim(text) return "|cff808080" .. text .. "|r" end
local function Signed(c)
  if not c or c == 0 then return "" end
  return W.Paint(c > 0 and C.good or C.bad, K.Coins(c, true))
end

local function Short(char)
  return char and char:match("^([^-]+)") or "?"
end

local function Items(list)
  if not list or #list == 0 then return "" end
  local first = list[1]
  return first .. (#list > 1 and Dim((" +%d more"):format(#list - 1)) or "")
end

-- what a log entry says, and its gold change for you
local function Describe(e)
  local k = e.kind
  if k == "trade" then
    local parts = {}
    if #(e.gotItems or {}) > 0 then parts[#parts + 1] = "got " .. Items(e.gotItems) end
    if #(e.gaveItems or {}) > 0 then parts[#parts + 1] = "gave " .. Items(e.gaveItems) end
    return "Trade with " .. (e.who or "?") .. (#parts > 0 and (": " .. table.concat(parts,
      ", ")) or ""), (e.got or 0) - (e.gave or 0)
  elseif k == "ahsale" then
    return "Sold " .. (e.item or "?") .. (e.who and Dim(" to " .. e.who) or ""), e.money
  elseif k == "ahbuy" then
    return "Bought " .. (e.item or "?") .. (e.who and Dim(" from " .. e.who) or ""),
      e.money and -e.money
  elseif k == "mail" then
    local what = Items(e.items)
    return "Mail from " .. (e.who or "?") .. (what ~= "" and (": " .. what) or
      (e.subject and Dim(": " .. e.subject) or "")), e.money
  elseif k == "sent" then
    local what = Items(e.items)
    return "Sent to " .. (e.who or "?") .. (what ~= "" and (": " .. what) or ""),
      e.money and -e.money
  elseif k == "vendor" then
    local parts = {}
    if e.sold > 0 then parts[#parts + 1] = "sold " .. K.Coins(e.sold) end
    if e.bought > 0 then parts[#parts + 1] = "bought " .. K.Coins(e.bought) end
    if e.repair > 0 then parts[#parts + 1] = "repairs " .. K.Coins(e.repair) end
    return "Vendor: " .. table.concat(parts, ", "), e.sold - e.bought - e.repair
  elseif k == "quest" then
    return "Quest: " .. (e.name or "?"), e.money
  elseif k == "loot" then
    return "Looted " .. (e.item or "?") .. (e.n > 1 and (" x" .. e.n) or "")
      .. (e.zone and Dim("  " .. e.zone) or ""), nil
  elseif k == "farm" then
    return ("Farmed %s in %s: %s looted + %s items"):format(K.Duration(e.secs), e.zone or "?",
      K.Coins(e.gold), K.Coins(e.value or 0)), (e.gold or 0) + (e.value or 0)
  end
  return k, nil
end
K.UI.Describe = Describe

local function AddItems(tt, title, list)
  if not list or #list == 0 then return end
  tt:AddLine(title, 1, 0.82, 0)
  for _, l in ipairs(list) do tt:AddLine("  " .. l, 1, 1, 1) end
end

local function RowTooltip(row)
  local e = row.entry
  if not e then return end
  local tt = GameTooltip
  tt:SetOwner(row, "ANCHOR_RIGHT")
  local text = Describe(e)
  tt:SetText(date("%d %b %Y %H:%M", e.t) .. "  " .. Short(e.char))
  tt:AddLine(text, 1, 1, 1, true)
  if e.kind == "trade" then
    if (e.got or 0) > 0 then tt:AddDoubleLine("Gold got", K.Coins(e.got), 1, 0.82, 0, 1, 1, 1) end
    if (e.gave or 0) > 0 then
      tt:AddDoubleLine("Gold given", K.Coins(e.gave), 1, 0.82, 0, 1, 1, 1)
    end
    AddItems(tt, "Got", e.gotItems)
    AddItems(tt, "Gave", e.gaveItems)
  elseif e.kind == "mail" or e.kind == "sent" then
    AddItems(tt, "Items", e.items)
  end
  tt:Show()
end

local function Build(p)
  local w = p:GetWidth()
  p.filter, p.offset = "all", 0
  p.buttons = {}
  local x = 0
  for i, f in ipairs(FILTERS) do
    local b = CreateFrame("Button", nil, p, "UIPanelButtonTemplate")
    b:SetSize(math.max(54, #f.text * 7 + 16), 20)
    b:SetPoint("TOPLEFT", x, 0)
    b:SetText(f.text)
    b:SetScript("OnClick", function()
      p.filter, p.offset = f.key, 0
      K.UI.pages.history.Refresh(p)
    end)
    x = x + b:GetWidth() + 3
    p.buttons[i] = b
  end
  p.list = W.Box(p)
  p.list:SetPoint("TOPLEFT", 0, -26)
  p.list:SetPoint("BOTTOMRIGHT")
  p.rows = {}
  for i = 1, ROWS do
    local r = CreateFrame("Frame", nil, p.list)
    r:SetHeight(20)
    r:SetPoint("TOPLEFT", 6, -6 - (i - 1) * 22)
    r:SetPoint("TOPRIGHT", -6, -6 - (i - 1) * 22)
    local hl = r:CreateTexture(nil, "HIGHLIGHT")
    hl:SetAllPoints()
    hl:SetColorTexture(1, 1, 1, 0.06)
    r.when = W.Text(r, "GameFontDisableSmall")
    r.when:SetPoint("LEFT", 2, 0)
    r.when:SetWidth(84)
    r.char = W.Text(r, "GameFontDisableSmall")
    r.char:SetPoint("LEFT", 88, 0)
    r.char:SetWidth(70)
    r.money = W.Text(r, "GameFontHighlightSmall", "RIGHT")
    r.money:SetPoint("RIGHT", -2, 0)
    r.money:SetWidth(100)
    r.text = W.Text(r, "GameFontHighlightSmall")
    r.text:SetPoint("LEFT", 160, 0)
    r.text:SetPoint("RIGHT", r.money, "LEFT", -6, 0)
    r:EnableMouse(true)
    r:SetScript("OnEnter", RowTooltip)
    r:SetScript("OnLeave", function() GameTooltip:Hide() end)
    p.rows[i] = r
  end
  p.list:EnableMouseWheel(true)
  p.list:SetScript("OnMouseWheel", function(_, delta)
    p.offset = math.max(0, math.min((p.count or 0) - ROWS, p.offset - delta * 3))
    K.UI.pages.history.Refresh(p)
  end)
  p.hint = W.Text(p, "GameFontDisableSmall", "RIGHT")
  p.hint:SetPoint("TOPRIGHT", -4, -5)
  p.hint:SetWidth(w - x - 8)
  p.empty = W.Text(p.list, "GameFontDisable", "CENTER")
  p.empty:SetPoint("CENTER")
  p.empty:SetWidth(w - 60)
  p.empty:SetWordWrap(true)
end

local function Refresh(p)
  local kinds
  for i, f in ipairs(FILTERS) do
    local on = f.key == p.filter
    if on then kinds = f.kinds end
    if p.buttons[i].LockHighlight then
      if on then p.buttons[i]:LockHighlight() else p.buttons[i]:UnlockHighlight() end
    end
  end
  local list = {}
  local log = G.DB().log
  for i = #log, 1, -1 do
    local e = log[i]
    if not kinds or kinds[e.kind] then list[#list + 1] = e end
  end
  p.count = #list
  p.offset = math.max(0, math.min(p.offset, #list - ROWS))
  local me = G.Me()
  for i, row in ipairs(p.rows) do
    local e = list[p.offset + i]
    row.entry = e
    row:SetShown(e ~= nil)
    if e then
      local text, change = Describe(e)
      row.when:SetText(date("%d %b %H:%M", e.t))
      row.char:SetText(e.char == me and "" or Short(e.char))
      row.text:SetText(text)
      row.money:SetText(Signed(change))
    end
  end
  p.hint:SetText(#list > ROWS and ("%d-%d of %d, scroll for more"):format(p.offset + 1,
    math.min(#list, p.offset + ROWS), #list) or "")
  p.empty:SetText(#list == 0 and ("Trades, auction sales and buys, mail, vendor visits, quest"
    .. " rewards and good loot show here as they happen, for every character") or "")
end

K.UI.pages.history = { Build = Build, Refresh = Refresh }
