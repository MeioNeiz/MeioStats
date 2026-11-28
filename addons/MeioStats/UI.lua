-- The /stats window: Blizzard ButtonFrameTemplate, tabs Levelling / Zones / Journey /
-- Farming / Wealth / History / Loot luck / Money.
-- Tabs build on first show and redraw only while visible (a 1 s ticker for live times, plus
-- Dirty() from data changes).
local _, K = ...
local UI = {}
K.UI = UI

UI.W, UI.H = 700, 500
local TABS = { "level", "zones", "journey", "farm", "wealth", "history", "loot", "money" }
local TITLES = { level = "Levelling", zones = "Zones", journey = "Journey", farm = "Farming",
  wealth = "Wealth", history = "History", loot = "Loot luck", money = "Money" }
UI.pages = {}   -- key -> { Build(page), Refresh(page) }, set by the UI*.lua files

local frame, current, ticker
local built, dirty = {}, {}

local function Refresh()
  if not (frame and frame:IsShown()) then return end
  local def, page = UI.pages[current], frame.pages[current]
  if not built[current] then
    def.Build(page)
    built[current] = true
  end
  dirty[current] = nil
  def.Refresh(page)
end

-- coalesced: item info and loot events can arrive dozens per frame
local scheduled
function UI.Dirty(key)
  dirty[key] = true
  if scheduled or not (frame and frame:IsShown() and key == current) then return end
  scheduled = true
  C_Timer.After(0, function()
    scheduled = false
    if dirty[current] then Refresh() end
  end)
end

function UI.Select(key)
  current = key
  K.db.tab = key
  for i, k in ipairs(TABS) do frame.pages[k]:SetShown(k == key) end
  PanelTemplates_SetTab(frame, tIndexOf(TABS, key))
  Refresh()
end

-- K.db.pos = { point, relPoint, x, y } against UIParent; nil = centred
local function Place()
  local pos = K.db.pos
  frame:ClearAllPoints()
  if pos and pos.point then
    frame:SetPoint(pos.point, UIParent, pos.relPoint, pos.x, pos.y)
  else
    frame:SetPoint("CENTER")
  end
end

local function SavePosition()
  local point, _, relPoint, x, y = frame:GetPoint(1)
  if point then K.db.pos = { point = point, relPoint = relPoint, x = x, y = y } end
end

function UI.ResetPosition()
  K.db.pos = nil
  if frame then Place() end
end

local function Create()
  frame = CreateFrame("Frame", "MeioStatsFrame", UIParent, "ButtonFrameTemplate")
  ButtonFrameTemplate_HidePortrait(frame)
  frame:SetSize(UI.W, UI.H)
  Place()
  frame:SetFrameStrata("MEDIUM") -- with toplevel, comes in front of other windows when clicked
  frame:SetToplevel(true)
  frame:EnableMouse(true)
  frame:SetMovable(true)
  frame:SetClampedToScreen(true)
  frame:RegisterForDrag("LeftButton")
  frame:SetScript("OnDragStart", function(self) self:StartMoving() end)
  frame:SetScript("OnDragStop", function(self)
    self:StopMovingOrSizing()
    -- saved in our SV: the client's layout cache only restores frames that exist at login
    self:SetUserPlaced(false)
    SavePosition()
  end)
  if frame.SetTitle then
    frame:SetTitle((UnitName("player") or "") .. " - Stats")
  end
  tinsert(UISpecialFrames, frame:GetName())
  frame.Inset:ClearAllPoints()
  frame.Inset:SetPoint("TOPLEFT", 8, -28)
  frame.Inset:SetPoint("BOTTOMRIGHT", -8, 8)

  frame.pages, frame.tabs = {}, {}
  for i, key in ipairs(TABS) do
    local page = CreateFrame("Frame", nil, frame.Inset)
    page:SetPoint("TOPLEFT", 8, -8)
    page:SetPoint("BOTTOMRIGHT", -8, 8)
    page:Hide()
    frame.pages[key] = page
    local t = CreateFrame("Button", frame:GetName() .. "Tab" .. i, frame,
      "PanelTabButtonTemplate")
    t:SetID(i)
    t:SetText(TITLES[key])
    if i == 1 then t:SetPoint("TOPLEFT", frame, "BOTTOMLEFT", 12, 2)
    else t:SetPoint("LEFT", frame.tabs[i - 1], "RIGHT", 3, 0) end
    t:SetScript("OnClick", function()
      PlaySound(SOUNDKIT.IG_CHARACTER_INFO_TAB)
      UI.Select(key)
    end)
    frame.tabs[i] = t
  end
  PanelTemplates_SetNumTabs(frame, #TABS)
  frame:SetScript("OnShow", function(self)
    self:Raise()
    ticker = ticker or C_Timer.NewTicker(1, function()
      if current == "level" or current == "zones" or current == "journey" or current == "farm"
      then Refresh() end
    end)
  end)
  frame:SetScript("OnHide", function()
    if ticker then ticker:Cancel() ticker = nil end
  end)
  frame:Hide()
end

function UI.Frame() return frame end

function UI.Show(key)
  if not frame then Create() end
  frame:Show()
  UI.Select(key or current or K.db.tab or "level")
end

local ALIASES = { level = "level", xp = "level", zones = "zones", zone = "zones",
  runs = "zones", dungeons = "zones", journey = "journey", map = "journey", loot = "loot",
  luck = "loot", money = "money", gold = "money", farming = "farm", wealth = "wealth",
  worth = "wealth", value = "wealth", history = "history", log = "history",
  trades = "history" }
function UI.Tab(name) return ALIASES[name] end

function UI.Toggle(key)
  if frame and frame:IsShown() and (not key or key == current) then
    frame:Hide()
  else
    UI.Show(key)
  end
end

K.On("GET_ITEM_INFO_RECEIVED", function()
  if frame and frame:IsShown() and (current == "loot" or current == "money") then
    UI.Dirty(current)
  end
end)
