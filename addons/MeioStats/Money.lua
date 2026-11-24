-- Money: what was sold, bought and earned, per item and in total, from TSM's accounting
-- ledger (TradeSkillMasterDB csv*, every character on this realm, as of login: TSM writes
-- on logout). Auction sale prices there are already net of the AH cut. Nothing is
-- recorded here.
-- Parsed once, on the first call. Public, read by Meionomics' Shift ledger:
--   MeioStats.Money.ItemTotals(itemID) -> nil (never sold or bought) or { sold, revenue,
--     bought, spent, profit, basis = "buy" | "craft" | nil, vendor }; integers, copper.
--   profit = revenue - sold x unit cost: the average buy price, else Meionomics' craft
--   cost (R.CostEach, today's mat prices), else nil (looted: no cost basis)
local _, K = ...
local M = {}
K.Money = M

local DAY = 86400
local items, totals

local function Item(id)
  local r = items[id]
  if not r then
    r = { sold = 0, revenue = 0, bought = 0, spent = 0, vendor = 0, vendorRevenue = 0,
      ah = 0, ahRevenue = 0, last = 0 }
    items[id] = r
  end
  return r
end

-- day number of t's local date (noon of it, so a DST change can't shift it); per hour cache
local dayOfHour = {}
local function Day(t)
  local h = math.floor(t / 3600)
  local d = dayOfHour[h]
  if not d then
    local l = date("*t", t)
    d = math.floor(time({ year = l.year, month = l.month, day = l.day, hour = 12 }) / DAY)
    dayOfHour[h] = d
  end
  return d
end

local function Parse()
  items = {}
  totals = { revenue = 0, spent = 0, ahRevenue = 0, vendorRevenue = 0, expense = 0,
    income = 0, expenses = {}, days = {}, first = math.huge }
  local db = type(TradeSkillMasterDB) == "table" and TradeSkillMasterDB
  if not db then return end
  local row = "\ni:(%d+)[^,\n]*,%d+,(%d+),(%d+),[^,\n]*,[^,\n]*,(%d+),([^,\n]*)"
  local money = "\n([^,\n]*),(%d+),[^,\n]*,[^,\n]*,(%d+)"
  -- keys are r@<realm>@internalData@csv<Kind>; some clients scope by realm type ("PvP")
  -- rather than realm name, so with no key for this realm every realm is read
  local ledgers, here = {}, false
  local realm = GetRealmName()
  for key, csv in pairs(db) do
    local r, kind
    if type(key) == "string" and type(csv) == "string" then
      r, kind = key:match("^r@(.-)@internalData@csv(%a+)$")
    end
    if kind then
      ledgers[#ledgers + 1] = { kind, csv, r == realm }
      here = here or r == realm
    end
  end
  for _, ledger in ipairs(ledgers) do
    local kind, csv = ledger[1], ledger[2]
    if here and not ledger[3] then kind = nil end
    if kind == "Sales" or kind == "Buys" then
      local sale = kind == "Sales"
      for id, qty, price, t, source in csv:gmatch(row) do
        id, qty, price, t = tonumber(id), tonumber(qty), tonumber(price), tonumber(t)
        local r, value = Item(id), qty * price
        local d = Day(t)
        totals.days[d] = totals.days[d] or { 0, 0 }
        totals.first = math.min(totals.first, t)
        if sale then
          r.sold, r.revenue, r.last = r.sold + qty, r.revenue + value, math.max(r.last, t)
          totals.revenue = totals.revenue + value
          totals.days[d][1] = totals.days[d][1] + value
          if source == "Vendor" then
            r.vendor, r.vendorRevenue = r.vendor + qty, r.vendorRevenue + value
            totals.vendorRevenue = totals.vendorRevenue + value
          elseif source == "Auction" then
            r.ah, r.ahRevenue = r.ah + qty, r.ahRevenue + value
            totals.ahRevenue = totals.ahRevenue + value
          end
        else
          r.bought, r.spent = r.bought + qty, r.spent + value
          totals.spent = totals.spent + value
          totals.days[d][2] = totals.days[d][2] + value
        end
      end
    elseif kind == "Expense" or kind == "Income" then
      for what, amount in csv:gmatch(money) do
        amount = tonumber(amount)
        if kind == "Expense" then
          totals.expense = totals.expense + amount
          totals.expenses[what] = (totals.expenses[what] or 0) + amount
        else
          totals.income = totals.income + amount
        end
      end
    end
  end
end

local function Ensure() if not items then Parse() end end

function M.HasLedger() return type(TradeSkillMasterDB) == "table" end

local function CraftCost(id)
  local R = Meionomics and Meionomics.Recipes
  if not (R and R.CostEach) then return nil end
  local ok, each = pcall(R.CostEach, id)
  return ok and type(each) == "number" and each or nil
end

-- unit cost and its basis
function M.Basis(id, r)
  if r.bought > 0 then return r.spent / r.bought, "buy" end
  local each = CraftCost(id)
  if each then return each, "craft" end
end

function M.ItemTotals(itemID)
  Ensure()
  local r = itemID and items[itemID]
  if not r then return nil end
  local out = { sold = r.sold, revenue = r.revenue, bought = r.bought, spent = r.spent,
    vendor = r.vendor }
  if r.sold > 0 then
    local unit, basis = M.Basis(itemID, r)
    if unit then
      out.profit, out.basis = math.floor(r.revenue - r.sold * unit + 0.5), basis
    end
  end
  return out
end

function M.Totals() Ensure() return totals end

-- items sold, by revenue: { id, r, profit, basis }
function M.TopSold()
  Ensure()
  local list = {}
  for id, r in pairs(items) do
    if r.sold > 0 then
      local t = M.ItemTotals(id)
      list[#list + 1] = { id = id, r = r, profit = t.profit, basis = t.basis }
    end
  end
  table.sort(list, function(a, b)
    if a.r.revenue ~= b.r.revenue then return a.r.revenue > b.r.revenue end
    return a.id < b.id
  end)
  return list
end

-- items bought and not sold, by spend
function M.TopBought()
  Ensure()
  local list = {}
  for id, r in pairs(items) do
    if r.bought > 0 and r.sold == 0 then list[#list + 1] = { id = id, r = r } end
  end
  table.sort(list, function(a, b)
    if a.r.spent ~= b.r.spent then return a.r.spent > b.r.spent end
    return a.id < b.id
  end)
  return list
end

-- the last n days: { earned, spent } each, oldest first
function M.Daily(n)
  Ensure()
  local today, out = Day(K.Now()), {}
  for i = n - 1, 0, -1 do
    local d = totals.days[today - i]
    out[#out + 1] = d and { d[1], d[2] } or { 0, 0 }
  end
  return out
end

-- live: gold change since login; kept over /reload (K.db.loginMoney)
local loginMoney
K.On("PLAYER_ENTERING_WORLD", function(_, reload)
  if loginMoney then return end
  loginMoney = reload and K.db.loginMoney or GetMoney()
  K.db.loginMoney = loginMoney
end)
function M.SessionChange() return loginMoney and GetMoney() - loginMoney end
K.On("PLAYER_MONEY", function() if K.UI then K.UI.Dirty("money") end end)

M._test = { Reset = function() items = nil end }
