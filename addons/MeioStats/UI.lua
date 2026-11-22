-- The /stats window: Blizzard ButtonFrameTemplate, tabs Levelling / Loot luck / Money.
-- Tabs build on first show and redraw only while visible (a 1 s ticker for live times, plus
-- Dirty() from data changes).
local _, K = ...
local UI = {}
K.UI = UI

UI.W, UI.H = 640, 500
local TABS = { "level", "loot", "money" }
local TITLES = { level = "Levelling", loot = "Loot luck", money = "Money" }
UI.pages = {}   -- key -> { Build(page), Refresh(page) }, set by UILevel/UILoot/UIMoney

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

local function Create()
  frame = CreateFrame("Frame", "MeioStatsFrame", UIParent, "ButtonFrameTemplate")
  ButtonFrameTemplate_HidePortrait(frame)
  frame:SetSize(UI.W, UI.H)
  frame:SetPoint("CENTER")
  frame:SetFrameStrata("HIGH")
  frame:SetToplevel(true)
  frame:EnableMouse(true)
  frame:SetMovable(true)
  frame:SetClampedToScreen(true)
  frame:RegisterForDrag("LeftButton")
  frame:SetScript("OnDragStart", function(self) self:StartMoving() end)
  frame:SetScript("OnDragStop", function(self) self:StopMovingOrSizing() end)
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
  frame:SetScript("OnShow", function()
    ticker = ticker or C_Timer.NewTicker(1, function()
      if current == "level" then Refresh() end
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

local ALIASES = { level = "level", xp = "level", loot = "loot", luck = "loot",
  money = "money", gold = "money" }
function UI.Tab(name) return ALIASES[name] end

function UI.Toggle(key)
  if frame and frame:IsShown() and (not key or key == current) then
    frame:Hide()
  else
    UI.Show(key)
  end
end

K.On("GET_ITEM_INFO_RECEIVED", function()
  if frame and frame:IsShown() and current ~= "level" then UI.Dirty(current) end
end)
