-- Gold history, every character on the account (MeioStatsDB):
--   flows[day][char][source] = { i = copper in, o = copper out }
--   log[i] = { t, char, kind, ... }, oldest first, the last MAX_LOG:
--     trade { who, gave, got, gaveItems, gotItems }   items = { "link xN", ... }
--     ahsale { item, who, money }   ahbuy { item, who, money }   mail { who, money, items }
--     sent { who, money, items }   vendor { sold, bought, repair }   quest { name, money }
--     loot { item, n, zone } (green or better)   farm { zone, secs, gold, value }
--   items[day][char][itemID] = looted count
--   worth[day] = { t, total, money, bags, bank, equipped, mail, auctions,
--     chars = { [char] = { money, total } } }: Meionomics' value of everything, the last of
--     the day; without Meionomics only gold
--   money[char] = gold at the last update, for the account's gold without Meionomics
-- A money change is put down to the source of the last action (a repair, a mail taken, a
-- quest handed in) if within MARK_SECS, else the window open (vendor, mailbox, AH, trade,
-- trainer, flight master, loot), else "other".
local _, K = ...
local G = {}
K.Gold = G

G.SOURCES = { "loot", "quest", "vendor", "repair", "ahsale", "ahbuy", "ahfee", "mail",
  "trade", "taxi", "train", "other" }
G.NAMES = { loot = "Looted", quest = "Quests", vendor = "Vendor", repair = "Repairs",
  ahsale = "AH sales", ahbuy = "AH buys", ahfee = "AH deposits", mail = "Mail",
  trade = "Trades", taxi = "Flight paths", train = "Training", other = "Other" }
G.PLACES = { "money", "bags", "bank", "equipped", "mail", "auctions" }
G.PLACE_NAMES = { money = "Gold", bags = "Bags", bank = "Bank", equipped = "Gear",
  mail = "Mail", auctions = "On AH" }

local MAX_LOG = 4000
local MARK_SECS = 2
local WORTH_EVERY = 15 * 60

local adb, me
local money
local mark            -- { source, until }
local open = {}       -- window -> true, or K.Clock() it stays counted until
local visit           -- vendor visit totals { sold, bought, repair }
local trade           -- the open trade's last view

function G.Day(t) return date("%Y-%m-%d", t or K.Now()) end
function G.Me() return me end
function G.DB() return adb end

local function Log(entry)
  entry.t, entry.char = entry.t or K.Now(), entry.char or me
  table.insert(adb.log, entry)
  while #adb.log > MAX_LOG do table.remove(adb.log, 1) end
  if K.UI then K.UI.Dirty("history") end
  return entry
end
G.Log = Log

function G.Mark(source, secs) mark = { source = source, untilT = K.Clock() + (secs or MARK_SECS) } end

local function IsOpen(w)
  local v = open[w]
  return v == true or (v and K.Clock() < v)
end

local function Source(d)
  if mark and K.Clock() <= mark.untilT then return mark.source end
  if IsOpen("trade") then return "trade" end
  if IsOpen("mail") then return "mail" end
  if IsOpen("ah") then return d < 0 and "ahbuy" or "ahsale" end
  if IsOpen("merchant") then return "vendor" end
  if IsOpen("trainer") then return "train" end
  if IsOpen("taxi") then return "taxi" end
  if IsOpen("loot") then return "loot" end
  if IsOpen("quest") then return "quest" end
  return "other"
end

function G.Flow(day, char)
  adb.flows[day] = adb.flows[day] or {}
  local f = adb.flows[day][char or me]
  if not f then
    f = {}
    adb.flows[day][char or me] = f
  end
  return f
end

local function Book(source, d)
  local f = G.Flow(G.Day())
  local s = f[source]
  if not s then
    s = { i = 0, o = 0 }
    f[source] = s
  end
  if d > 0 then s.i = s.i + d else s.o = s.o - d end
end

local function OnMoney()
  local m = GetMoney()
  local d = money and m - money or 0
  money = m
  adb.money[me] = m
  if d == 0 then return end
  local source = Source(d)
  Book(source, d)
  if visit and source == "vendor" then
    if d > 0 then visit.sold = visit.sold + d else visit.bought = visit.bought - d end
  elseif visit and source == "repair" then
    visit.repair = visit.repair - d
  end
  if K.Farm then K.Farm.Money(source, d) end
  if K.UI then K.UI.Dirty("wealth") end
end

------------------------------------------------------------------------------ items
local function Pattern(fmt)
  if not fmt then return nil end
  local p = fmt:gsub("([%(%)%.%+%-%*%?%[%]%^%$])", "%%%1")
  p = p:gsub("%%s", "(.+)"):gsub("%%d", "(%%d+)"):gsub("%%%.$", "")
  -- this client's loot lines have no full stop; others' do
  return "^" .. p .. "%.?$"
end
local LOOT = {}
for _, f in ipairs({ "LOOT_ITEM_SELF_MULTIPLE", "LOOT_ITEM_SELF", "LOOT_ITEM_PUSHED_SELF_MULTIPLE",
  "LOOT_ITEM_PUSHED_SELF" }) do
  if _G[f] then LOOT[#LOOT + 1] = { Pattern(_G[f]), pushed = f:find("PUSHED") ~= nil } end
end

local function ItemID(link) return tonumber(link:match("item:(%d+)")) end
G.ItemID = ItemID

-- from the item info, else the link's colour (info can be uncached)
local LINK_QUALITY = { ["9d9d9d"] = 0, ffffff = 1, ["1eff00"] = 2, ["0070dd"] = 3,
  a335ee = 4, ff8000 = 5 }
function G.Quality(link)
  local _, _, quality = C_Item.GetItemInfo(link)
  if quality then return quality end
  local hex = link:match("|c%x%x(%x%x%x%x%x%x)")
  return hex and LINK_QUALITY[hex:lower()] or 1
end

-- "You receive loot: [x]x3." -> link, 3, pushed (a reward, not loot)
function G.ParseLoot(msg)
  for _, p in ipairs(LOOT) do
    local link, n = msg:match(p[1])
    if link then return link, tonumber(n) or 1, p.pushed end
  end
end

local function OnLoot(msg)
  if not K.Usable(msg) then return end
  local link, n, pushed = G.ParseLoot(msg)
  local id = link and ItemID(link)
  if not id then return end
  if not pushed then
    local day = G.Day()
    adb.items[day] = adb.items[day] or {}
    local mine = adb.items[day][me] or {}
    adb.items[day][me] = mine
    mine[id] = (mine[id] or 0) + n
    if G.Quality(link) >= 2 then
      Log({ kind = "loot", item = link, n = n, zone = GetRealZoneText() })
    end
  end
  if K.Farm then K.Farm.Loot(id, n, pushed) end
end

------------------------------------------------------------------------------ trades
local function TradeItems(get, linkFn)
  local out = {}
  for i = 1, 6 do
    local link = linkFn and linkFn(i)
    if link then
      local _, _, n = get(i)
      out[#out + 1] = link .. ((n and n > 1) and (" x" .. n) or "")
    end
  end
  return out
end

local function SnapTrade()
  if not trade then return end
  trade.gave = GetPlayerTradeMoney and GetPlayerTradeMoney() or 0
  trade.got = GetTargetTradeMoney and GetTargetTradeMoney() or 0
  trade.gaveItems = TradeItems(GetTradePlayerItemInfo, GetTradePlayerItemLink)
  trade.gotItems = TradeItems(GetTradeTargetItemInfo, GetTradeTargetItemLink)
end

local function TradeDone()
  if not trade then return end
  local t = trade
  trade = nil
  if t.gave == 0 and t.got == 0 and #t.gaveItems == 0 and #t.gotItems == 0 then return end
  Log({ kind = "trade", who = t.who, gave = t.gave, got = t.got, gaveItems = t.gaveItems,
    gotItems = t.gotItems })
end

------------------------------------------------------------------------------ mail
local function MailItems(i, n)
  local out = {}
  for a = 1, (ATTACHMENTS_MAX_RECEIVE or 16) do
    local link = GetInboxItemLink and GetInboxItemLink(i, a)
    if link then
      local _, _, _, count = GetInboxItem(i, a)
      out[#out + 1] = link .. ((count and count > 1) and (" x" .. count) or "")
    end
    if n and #out >= n then break end
  end
  return out
end

-- what a mail is, read before its money or items are taken
local function ReadMail(i, takingMoney, attachment)
  local _, _, sender, subject, cash = GetInboxHeaderInfo(i)
  local kind, item, who, value
  if GetInboxInvoiceInfo then
    local invoice, itemName, player, bid, _, deposit, consignment = GetInboxInvoiceInfo(i)
    if invoice == "seller" then
      kind, item, who = "ahsale", itemName, player
      value = (bid or 0) + (deposit or 0) - (consignment or 0)
    elseif invoice == "buyer" then
      kind, item, who, value = "ahbuy", itemName, player, bid
    end
  end
  return { kind = kind, item = item, who = who, value = value, sender = sender,
    subject = subject, cash = cash, attachment = attachment, takingMoney = takingMoney }
end

local function OnTakeMoney(i)
  local m = ReadMail(i, true)
  if not (m.cash and m.cash > 0) then return end
  if m.kind == "ahsale" then
    G.Mark("ahsale")
    Log({ kind = "ahsale", item = m.item, who = m.who, money = m.cash })
  else
    G.Mark("mail")
    Log({ kind = "mail", who = m.sender, money = m.cash, subject = m.subject, items = {} })
  end
end

local function OnTakeItem(i, a)
  local m = ReadMail(i, false, a)
  local items
  if a then
    local link = GetInboxItemLink(i, a)
    items = link and { link } or {}
  else
    items = MailItems(i)
  end
  if #items == 0 then return end
  if m.kind == "ahbuy" then
    Log({ kind = "ahbuy", item = items[1], who = m.who, money = m.value })
  elseif m.kind ~= "ahsale" then
    -- an expired or cancelled auction comes back from the Auction House too
    Log({ kind = "mail", who = m.sender, money = 0, subject = m.subject, items = items })
  end
end

local function OnAutoLoot(i)
  local m = ReadMail(i, true)
  if m.cash and m.cash > 0 then OnTakeMoney(i) end
  OnTakeItem(i)
end

local function OnSend(to)
  local items = {}
  for a = 1, (ATTACHMENTS_MAX_SEND or 12) do
    local link = GetSendMailItemLink and GetSendMailItemLink(a)
    if link then
      local _, _, _, count = GetSendMailItem(a)
      items[#items + 1] = link .. ((count and count > 1) and (" x" .. count) or "")
    end
  end
  local cash = GetSendMailMoney and GetSendMailMoney() or 0
  G.Mark("mail")
  Log({ kind = "sent", who = to, money = cash, items = items })
end

------------------------------------------------------------------------------ worth
function G.SnapWorth()
  local day = G.Day()
  local w = { t = K.Now(), chars = {} }
  for _, p in ipairs(G.PLACES) do w[p] = 0 end
  local Worth = Meionomics and Meionomics.Worth
  local ok = Worth and pcall(function()
    for _, c in ipairs(Worth.Characters()) do
      local s = Worth.Summary(c.key)
      if s then
        local name = c.full or c.name or c.key
        w.chars[name] = { money = s.money or 0, total = s.total or 0 }
        w.money = w.money + (s.money or 0)
        for _, p in ipairs({ "bags", "bank", "equipped", "mail", "auctions" }) do
          w[p] = w[p] + (s[p] and s[p].value or 0)
        end
      end
    end
  end)
  if not ok or not next(w.chars) then
    w.chars, w.money = {}, 0
    for char, m in pairs(adb.money) do
      w.chars[char] = { money = m, total = m }
      w.money = w.money + m
    end
    w.goldOnly = true
  end
  w.total = 0
  for _, p in ipairs(G.PLACES) do w.total = w.total + w[p] end
  adb.worth[day] = w
  if K.UI then K.UI.Dirty("wealth") end
  return w
end

-- worth days, oldest first: { { day, w }... }
function G.WorthDays()
  local out = {}
  for day, w in pairs(adb.worth) do out[#out + 1] = { day = day, w = w } end
  table.sort(out, function(a, b) return a.day < b.day end)
  return out
end

-- source -> { i, o } summed over the last `days` days (today counts), one char or all
function G.Flows(days, char)
  local out = {}
  for _, s in ipairs(G.SOURCES) do out[s] = { i = 0, o = 0 } end
  local now = K.Now()
  for k = 0, days - 1 do
    local f = adb.flows[G.Day(now - k * 86400)]
    for c, srcs in pairs(f or {}) do
      if not char or c == char then
        for s, v in pairs(srcs) do
          local o = out[s] or { i = 0, o = 0 }
          out[s] = o
          o.i, o.o = o.i + v.i, o.o + v.o
        end
      end
    end
  end
  return out
end

------------------------------------------------------------------------------ events
K.OnLoad(function()
  MeioStatsDB = MeioStatsDB or {}
  adb = MeioStatsDB
  for _, k in ipairs({ "flows", "log", "items", "worth", "money", "farms" }) do
    adb[k] = adb[k] or {}
  end
  me = (UnitName("player") or "?") .. "-" .. (GetRealmName() or "?")
end)

K.On("PLAYER_ENTERING_WORLD", function()
  money = GetMoney()
  adb.money[me] = money
end)
K.On("PLAYER_MONEY", OnMoney)
K.On("PLAYER_LOGIN", function()
  C_Timer.After(30, G.SnapWorth)
  C_Timer.NewTicker(WORTH_EVERY, G.SnapWorth)
end)

local WINDOWS = {
  merchant = { "MERCHANT_SHOW", "MERCHANT_CLOSED" }, mail = { "MAIL_SHOW", "MAIL_CLOSED" },
  ah = { "AUCTION_HOUSE_SHOW", "AUCTION_HOUSE_CLOSED" },
  trade = { "TRADE_SHOW", "TRADE_CLOSED" }, trainer = { "TRAINER_SHOW", "TRAINER_CLOSED" },
  taxi = { "TAXIMAP_OPENED", "TAXIMAP_CLOSED" }, loot = { "LOOT_OPENED", "LOOT_CLOSED" },
  quest = { "QUEST_COMPLETE", "QUEST_FINISHED" },
}
for w, ev in pairs(WINDOWS) do
  K.On(ev[1], function() open[w] = true end)
  -- the last money update can land after the close
  K.On(ev[2], function() open[w] = K.Clock() + 1 end)
end

K.On("MERCHANT_SHOW", function() visit = { sold = 0, bought = 0, repair = 0 } end)
K.On("MERCHANT_CLOSED", function()
  C_Timer.After(1, function()
    local v = visit
    visit = nil
    if v and (v.sold > 0 or v.bought > 0 or v.repair > 0) then
      Log({ kind = "vendor", sold = v.sold, bought = v.bought, repair = v.repair })
    end
  end)
end)

K.On("TRADE_SHOW", function()
  trade = { who = UnitName("NPC") or "?", gave = 0, got = 0, gaveItems = {}, gotItems = {} }
end)
K.On("TRADE_MONEY_CHANGED", SnapTrade)
K.On("TRADE_PLAYER_ITEM_CHANGED", SnapTrade)
K.On("TRADE_TARGET_ITEM_CHANGED", SnapTrade)
K.On("TRADE_ACCEPT_UPDATE", SnapTrade)
K.On("UI_INFO_MESSAGE", function(_, msg)
  if ERR_TRADE_COMPLETE and K.Usable(msg) and msg == ERR_TRADE_COMPLETE then TradeDone() end
end)
K.On("TRADE_CLOSED", function() C_Timer.After(0.5, function() trade = nil end) end)

K.On("QUEST_TURNED_IN", function(questID, _, cash)
  G.Mark("quest")
  local name = C_QuestLog and C_QuestLog.GetTitleForQuestID
    and C_QuestLog.GetTitleForQuestID(questID) or (GetTitleText and GetTitleText())
  Log({ kind = "quest", name = name or ("quest " .. tostring(questID)),
    money = K.Usable(cash) and cash or 0 })
end)
K.On("CHAT_MSG_MONEY", function() G.Mark("loot") end)
K.On("CHAT_MSG_LOOT", OnLoot)

-- C_AuctionHouse is nil on clients without the modern auction house
local function Hook(tbl, name, fn)
  if type(tbl) == "table" and type(tbl[name]) == "function" then
    hooksecurefunc(tbl --[[@as table]], name, fn)
  end
end
Hook(_G, "RepairAllItems", function() G.Mark("repair") end)
Hook(_G, "TakeInboxMoney", OnTakeMoney)
Hook(_G, "TakeInboxItem", OnTakeItem)
Hook(_G, "AutoLootMailItem", OnAutoLoot)
Hook(_G, "SendMail", OnSend)
Hook(_G, "TakeTaxiNode", function() G.Mark("taxi") end)
Hook(_G, "BuyTrainerService", function() G.Mark("train") end)
Hook(_G, "StartAuction", function() G.Mark("ahfee") end)
Hook(_G, "PlaceAuctionBid", function() G.Mark("ahbuy") end)
Hook(C_AuctionHouse, "PostItem", function() G.Mark("ahfee") end)
Hook(C_AuctionHouse, "PostCommodity", function() G.Mark("ahfee") end)
Hook(C_AuctionHouse, "PlaceBid", function() G.Mark("ahbuy") end)
Hook(C_AuctionHouse, "ConfirmCommoditiesPurchase", function() G.Mark("ahbuy") end)

G._test = { OnMoney = OnMoney, OnLoot = OnLoot, Source = Source }
