-- Farming sessions: /stats farm starts one, again stops it. While on, a small tracker shows
-- the time (AFK left out), gold looted, what the looted items are worth and the total per
-- hour; corpses and chests looted count. Kept across /reload and logout until stopped.
--   K.db.farm = the open session { start, secs, gold, items = { [id] = n }, loots, zones }
--   MeioStatsDB.farms[i] = a finished one, plus char, zone (most time), value, unpriced
-- Item worth: Meionomics' best way to sell it (AH after the cut, vendor, disenchant), else
-- TSM's market value, else the vendor price. Vendor sales while farming aren't counted
-- again: the items already are.
local _, K = ...
local F = {}
K.Farm = F
local W = K.Widgets

local MAX_FARMS = 200

---@class MeioStatsFarmFrame: Frame
---@field title FontString
---@field gold FontString
---@field items FontString
---@field total FontString
---@field rate FontString
---@field icons MeioStatsFarmIcon[]

---@class MeioStatsFarmIcon: Frame
---@field id number?
---@field tex Texture
---@field count FontString

local db, farm, mark
---@type MeioStatsFarmFrame?
local frame

-- copper each, and where the price came from
function F.Value(id)
  local Worth = Meionomics and Meionomics.Worth
  if Worth then
    local ok, each = pcall(Worth.Value, id)
    if ok and each then return each, "Meionomics" end
  end
  if TSM_API and TSM_API.GetCustomPriceValue then
    local ok, v = pcall(TSM_API.GetCustomPriceValue, "DBMarket", "i:" .. id)
    if ok and v and v > 0 then return v, "TSM market" end
  end
  local sell = select(11, C_Item.GetItemInfo(id))
  if sell and sell > 0 then return sell, "vendor" end
end

-- total item worth and how many kinds have no price
function F.Worth(items)
  local value, unpriced = 0, 0
  for id, n in pairs(items) do
    local each = F.Value(id)
    if each then value = value + each * n else unpriced = unpriced + 1 end
  end
  return value, unpriced
end

-- book the active time since the last call to the session and the zone you're in
local function Tick()
  if not farm then return end
  local now = K.Level.ActiveSecs()
  local secs = mark and now - mark or 0
  mark = now
  if secs <= 0 then return end
  farm.secs = farm.secs + secs
  local zone = GetRealZoneText() or "?"
  farm.zones[zone] = (farm.zones[zone] or 0) + secs
end

function F.Active() return farm end

local function MainZone(f)
  local best, secs = "?", -1
  for z, s in pairs(f.zones) do if s > secs then best, secs = z, s end end
  return best
end
F.MainZone = MainZone

-- items, most worth first: { { id, n, each, value }... }
function F.Top(items)
  local out = {}
  for id, n in pairs(items) do
    local each = F.Value(id)
    out[#out + 1] = { id = id, n = n, each = each, value = (each or 0) * n }
  end
  table.sort(out, function(a, b)
    if a.value ~= b.value then return a.value > b.value end
    return a.id < b.id
  end)
  return out
end

function F.PerHour(f, value)
  if f.secs < 60 then return nil end
  return (f.gold + (value or 0)) / f.secs * 3600
end

------------------------------------------------------------------------------ tracker
local function Line(parent, y)
  local l = W.Text(parent, "GameFontNormalSmall")
  l:SetPoint("TOPLEFT", 8, y)
  local r = W.Text(parent, "GameFontHighlightSmall", "RIGHT")
  r:SetPoint("TOPRIGHT", -8, y)
  return l, r
end

local function Update()
  if not (frame and frame:IsShown() and farm) then return end
  Tick()
  local value, unpriced = F.Worth(farm.items)
  frame.title:SetText("Farming  " .. K.Duration(farm.secs))
  frame.gold:SetText(K.Coins(farm.gold))
  frame.items:SetText(K.Coins(value) .. (unpriced > 0 and ("|cff999999 +" .. unpriced
    .. "?|r") or ""))
  frame.total:SetText(K.Coins(farm.gold + value))
  local ph = F.PerHour(farm, value)
  frame.rate:SetText(ph and K.Coins(ph) or "|cff999999after a minute|r")
  local top = F.Top(farm.items)
  for i, icon in ipairs(frame.icons) do
    local e = top[i]
    icon:SetShown(e ~= nil)
    if e then
      icon.tex:SetTexture(W.ItemIcon(e.id))
      icon.count:SetText(e.n > 1 and e.n or "")
      icon.id = e.id
    end
  end
  frame.loots:SetText(farm.loots .. " looted")
  if K.UI then K.UI.Dirty("farm") end
end

local function SavePosition()
  local point, _, relPoint, x, y = frame:GetPoint(1)
  if point then db.farmPos = { point = point, relPoint = relPoint, x = x, y = y } end
end

local function Create()
  frame = CreateFrame("Frame", "MeioStatsFarmFrame", UIParent) --[[@as MeioStatsFarmFrame]]
  frame:SetSize(200, 122)
  local pos = db.farmPos
  if pos and pos.point then
    frame:SetPoint(pos.point, UIParent, pos.relPoint, pos.x, pos.y)
  else
    frame:SetPoint("RIGHT", UIParent, "RIGHT", -260, 80)
  end
  frame:SetFrameStrata("MEDIUM")
  frame:SetClampedToScreen(true)
  frame:EnableMouse(true)
  frame:SetMovable(true)
  frame:RegisterForDrag("LeftButton")
  frame:SetScript("OnDragStart", frame.StartMoving)
  frame:SetScript("OnDragStop", function(self)
    self:StopMovingOrSizing()
    self:SetUserPlaced(false)
    SavePosition()
  end)
  local bg = frame:CreateTexture(nil, "BACKGROUND")
  bg:SetAllPoints()
  bg:SetColorTexture(0, 0, 0, 0.6)
  local edge = frame:CreateTexture(nil, "BORDER")
  edge:SetPoint("TOPLEFT")
  edge:SetPoint("TOPRIGHT")
  edge:SetHeight(1)
  edge:SetColorTexture(1, 0.82, 0, 0.6)
  frame.title = W.Text(frame, "GameFontNormal")
  frame.title:SetPoint("TOPLEFT", 8, -6)
  local stop = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
  stop:SetSize(44, 18)
  stop:SetPoint("TOPRIGHT", -4, -3)
  stop:SetText("Stop")
  stop:SetScript("OnClick", function() F.Stop() end)
  local l
  l, frame.gold = Line(frame, -26)
  l:SetText("Gold looted")
  l, frame.items = Line(frame, -40)
  l:SetText("Items worth")
  l, frame.total = Line(frame, -54)
  l:SetText("Total")
  l, frame.rate = Line(frame, -68)
  l:SetText("Per hour")
  frame.icons = {}
  for i = 1, 5 do
    local b = CreateFrame("Frame", nil, frame) --[[@as MeioStatsFarmIcon]]
    b:SetSize(22, 22)
    b:SetPoint("BOTTOMLEFT", 8 + (i - 1) * 25, 8)
    b.tex = b:CreateTexture(nil, "ARTWORK")
    b.tex:SetAllPoints()
    b.count = b:CreateFontString(nil, "OVERLAY", "NumberFontNormalSmall")
    b.count:SetPoint("BOTTOMRIGHT", 1, 0)
    b:EnableMouse(true)
    b:SetScript("OnEnter", function(self)
      GameTooltip:SetOwner(self, "ANCHOR_TOP")
      GameTooltip:SetItemByID(self.id)
      GameTooltip:Show()
    end)
    b:SetScript("OnLeave", function() GameTooltip:Hide() end)
    frame.icons[i] = b
  end
  frame.loots = W.Text(frame, "GameFontDisableSmall", "RIGHT")
  frame.loots:SetPoint("BOTTOMRIGHT", -8, 12)
  C_Timer.NewTicker(1, Update)
end

function F.ResetPosition()
  db.farmPos = nil
  if frame then
    frame:ClearAllPoints()
    frame:SetPoint("RIGHT", UIParent, "RIGHT", -260, 80)
  end
end

------------------------------------------------------------------------------ start, stop
function F.Start()
  if farm then return end
  farm = { start = K.Now(), secs = 0, gold = 0, items = {}, loots = 0, zones = {} }
  db.farm = farm
  mark = K.Level.ActiveSecs()
  if not frame then Create() end
  frame:Show()
  Update()
  K.Print("farming started: gold and items looted count until " .. "|cffffd100/stats farm|r")
end

function F.Stop()
  if not farm then return end
  Tick()
  local f = farm
  farm, db.farm, mark = nil, nil, nil
  if frame then frame:Hide() end
  local value, unpriced = F.Worth(f.items)
  f.value, f.unpriced, f.zone, f.char = value, unpriced, MainZone(f), K.Gold.Me()
  f.stop = K.Now()
  local farms = K.Gold.DB().farms
  table.insert(farms, f)
  while #farms > MAX_FARMS do table.remove(farms, 1) end
  K.Gold.Log({ kind = "farm", zone = f.zone, secs = f.secs, gold = f.gold, value = value })
  local ph = F.PerHour(f, value)
  K.Print(("farmed %s in %s: %s looted + %s in items = %s%s"):format(K.Duration(f.secs),
    f.zone, K.Coins(f.gold), K.Coins(value), K.Coins(f.gold + value),
    ph and (" (" .. K.Coins(ph) .. " per hour)") or ""))
  if K.UI then K.UI.Dirty("farm") end
end

function F.Toggle()
  if farm then F.Stop() else F.Start() end
end

function F.Money(source, d)
  if farm and source == "loot" then farm.gold = farm.gold + d end
end

function F.Loot(id, n, pushed)
  if farm and not pushed then farm.items[id] = (farm.items[id] or 0) + n end
end

K.OnLoad(function(d)
  db = d
  farm = db.farm
end)
K.On("PLAYER_ENTERING_WORLD", function()
  mark = K.Level.ActiveSecs()
  if farm then
    if not frame then Create() end
    frame:Show()
  end
end)
K.On("LOOT_OPENED", function() if farm then farm.loots = farm.loots + 1 end end)
K.On("PLAYER_LOGOUT", Tick)

F._test = { Update = Update, Tick = Tick, Frame = function() return frame end }
