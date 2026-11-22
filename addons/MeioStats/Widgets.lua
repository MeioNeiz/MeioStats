-- Small drawing pieces for the window: tiles, segmented bars, column charts, item rows.
local _, K = ...
local W = {}
K.Widgets = W

local BAR = "Interface\\TargetingFrame\\UI-StatusBar"

W.C = {
  kill = { 0.86, 0.38, 0.24 }, rested = { 0.25, 0.55, 1 }, quest = { 1, 0.78, 0.1 },
  explore = { 0.35, 0.8, 0.4 }, other = { 0.55, 0.55, 0.55 },
  xp = { 0.58, 0.0, 0.55 }, restedXP = { 0.0, 0.39, 0.88 },
  good = { 0.25, 0.8, 0.3 }, bad = { 0.9, 0.25, 0.2 }, neutral = { 0.75, 0.75, 0.75 },
  gold = { 1, 0.82, 0 }, dim = { 0.5, 0.5, 0.5 },
}

function W.Hex(c) return ("|cff%02x%02x%02x"):format(c[1] * 255, c[2] * 255, c[3] * 255) end
function W.Paint(c, text) return W.Hex(c) .. text .. "|r" end

function W.Text(parent, font, justify)
  local fs = parent:CreateFontString(nil, "OVERLAY", font or "GameFontHighlight")
  fs:SetJustifyH(justify or "LEFT")
  fs:SetWordWrap(false)
  return fs
end

-- dark panel behind a group, like the Blizzard insets but lighter
function W.Box(parent)
  local f = CreateFrame("Frame", nil, parent)
  local bg = f:CreateTexture(nil, "BACKGROUND")
  bg:SetAllPoints()
  bg:SetColorTexture(0, 0, 0, 0.35)
  local line = f:CreateTexture(nil, "BORDER")
  line:SetPoint("TOPLEFT")
  line:SetPoint("TOPRIGHT")
  line:SetHeight(1)
  line:SetColorTexture(1, 0.82, 0, 0.25)
  return f
end

-- label (gold, small), value (large), note (grey)
function W.Tile(parent, w, h)
  local f = W.Box(parent)
  f:SetSize(w, h or 54)
  f.label = W.Text(f, "GameFontNormalSmall")
  f.label:SetPoint("TOPLEFT", 8, -6)
  f.value = W.Text(f, "GameFontHighlightLarge")
  f.value:SetPoint("TOPLEFT", f.label, "BOTTOMLEFT", 0, -4)
  f.note = W.Text(f, "GameFontDisableSmall")
  f.note:SetPoint("TOPLEFT", f.value, "BOTTOMLEFT", 0, -3)
  function f:Set(label, value, note)
    self.label:SetText(label)
    self.value:SetText(value or "|cff808080-|r")
    self.note:SetText(note or "")
  end
  return f
end

-- horizontal bar of coloured segments: SetSegments({ { value, colour }, ... }, max)
function W.Bar(parent, h)
  local f = CreateFrame("Frame", nil, parent)
  f:SetHeight(h or 14)
  local bg = f:CreateTexture(nil, "BACKGROUND")
  bg:SetAllPoints()
  bg:SetColorTexture(0.08, 0.08, 0.08, 0.9)
  f.segs = {}
  f.text = W.Text(f, "GameFontHighlightSmall", "CENTER")
  f.text:SetPoint("CENTER", 0, 0)
  function f:SetSegments(list, max)
    local width = self:GetWidth()
    local total = 0
    for _, s in ipairs(list) do total = total + math.max(0, s[1]) end
    max = math.max(max or total, 1)
    local x = 0
    for i, s in ipairs(list) do
      local t = self.segs[i]
      if not t then
        t = self:CreateTexture(nil, "ARTWORK")
        t:SetTexture(BAR)
        self.segs[i] = t
      end
      local w = math.min(width - x, width * math.max(0, s[1]) / max)
      if w >= 0.5 then
        t:ClearAllPoints()
        t:SetPoint("TOPLEFT", x, 0)
        t:SetPoint("BOTTOMLEFT", x, 0)
        t:SetWidth(w)
        t:SetVertexColor(s[2][1], s[2][2], s[2][3], s[3] or 1)
        t:Show()
        x = x + w
      else
        t:Hide()
      end
    end
    for i = #list + 1, #self.segs do self.segs[i]:Hide() end
  end
  return f
end

-- column chart: SetData(values, colourFn(i, v) or colour, max); pairs { a, b } draw side
-- by side
function W.Columns(parent, w, h)
  local f = CreateFrame("Frame", nil, parent)
  f:SetSize(w, h)
  local base = f:CreateTexture(nil, "BORDER")
  base:SetPoint("BOTTOMLEFT")
  base:SetPoint("BOTTOMRIGHT")
  base:SetHeight(1)
  base:SetColorTexture(1, 1, 1, 0.2)
  f.cols = {}
  local function Col(i)
    local t = f.cols[i]
    if not t then
      t = f:CreateTexture(nil, "ARTWORK")
      t:SetTexture(BAR)
      f.cols[i] = t
    end
    return t
  end
  function f:SetData(values, colours, max, gap)
    local n = #values
    local per = type(values[1]) == "table" and #values[1] or 1
    if not max then
      max = 0
      for _, v in ipairs(values) do
        if per > 1 then for _, x in ipairs(v) do max = math.max(max, x) end
        else max = math.max(max, v) end
      end
    end
    max = math.max(max, 1)
    gap = gap or 2
    local slot = self:GetWidth() / math.max(n, 1)
    local cw = math.max(1, (slot - gap) / per)
    local k = 0
    for i, v in ipairs(values) do
      for j = 1, per do
        k = k + 1
        local x = per > 1 and v[j] or v
        local t = Col(k)
        local hgt = self:GetHeight() * x / max
        if hgt >= 1 then
          t:ClearAllPoints()
          t:SetPoint("BOTTOMLEFT", (i - 1) * slot + (j - 1) * cw, 1)
          t:SetSize(cw, hgt)
          local c = type(colours) == "function" and colours(i, x, j)
            or colours[j] or colours
          t:SetVertexColor(c[1], c[2], c[3], c[4] or 1)
          t:Show()
        else
          t:Hide()
        end
      end
    end
    for i = k + 1, #self.cols do self.cols[i]:Hide() end
  end
  return f
end

-- legend: coloured square + text, laid out left to right
function W.Legend(parent)
  local f = CreateFrame("Frame", nil, parent)
  f:SetHeight(14)
  f.items = {}
  function f:Set(list)
    local x = 0
    for i, e in ipairs(list) do
      local it = self.items[i]
      if not it then
        it = { sq = self:CreateTexture(nil, "ARTWORK"),
          fs = W.Text(self, "GameFontHighlightSmall") }
        it.sq:SetSize(9, 9)
        self.items[i] = it
      end
      it.sq:ClearAllPoints()
      it.sq:SetPoint("LEFT", x, 0)
      it.sq:SetColorTexture(e[2][1], e[2][2], e[2][3], 1)
      it.fs:ClearAllPoints()
      it.fs:SetPoint("LEFT", it.sq, "RIGHT", 4, 0)
      it.fs:SetText(e[1])
      it.sq:Show()
      it.fs:Show()
      x = x + 13 + it.fs:GetStringWidth() + 9
    end
    for i = #list + 1, #self.items do
      self.items[i].sq:Hide()
      self.items[i].fs:Hide()
    end
  end
  return f
end

-- item row: icon, name, right-side text, an optional bar under the name; tooltip on hover
function W.ItemRow(parent, w, h)
  local f = CreateFrame("Button", nil, parent)
  f:SetSize(w, h or 30)
  local hl = f:CreateTexture(nil, "HIGHLIGHT")
  hl:SetAllPoints()
  hl:SetColorTexture(1, 1, 1, 0.06)
  f.icon = f:CreateTexture(nil, "ARTWORK")
  f.icon:SetSize(h and h - 4 or 26, h and h - 4 or 26)
  f.icon:SetPoint("LEFT", 2, 0)
  f.name = W.Text(f, "GameFontNormal")
  f.name:SetPoint("TOPLEFT", f.icon, "TOPRIGHT", 6, -1)
  f.sub = W.Text(f, "GameFontDisableSmall")
  f.sub:SetPoint("BOTTOMLEFT", f.icon, "BOTTOMRIGHT", 6, 1)
  f.right = W.Text(f, "GameFontHighlight", "RIGHT")
  f.right:SetPoint("TOPRIGHT", -4, -2)
  f.right2 = W.Text(f, "GameFontHighlightSmall", "RIGHT")
  f.right2:SetPoint("BOTTOMRIGHT", -4, 2)
  f.itemID = nil
  f:SetScript("OnEnter", function()
    if not f.itemID then return end
    GameTooltip:SetOwner(f, "ANCHOR_RIGHT")
    GameTooltip:SetItemByID(f.itemID)
    GameTooltip:Show()
  end)
  f:SetScript("OnLeave", function() GameTooltip:Hide() end)
  return f
end

-- item name in its quality colour; nil while the client hasn't cached it (asks for it)
local asked = {}
function W.ItemName(id)
  local name, _, quality = C_Item.GetItemInfo(id)
  if name then
    local c = ITEM_QUALITY_COLORS and ITEM_QUALITY_COLORS[quality or 1]
    return (c and c.hex or "|cffffffff") .. name .. "|r", quality
  end
  if not asked[id] and C_Item.RequestLoadItemDataByID then
    asked[id] = true
    C_Item.RequestLoadItemDataByID(id)
  end
  return "|cff808080item " .. id .. "|r"
end

function W.ItemIcon(id)
  return C_Item.GetItemIconByID(id)
end
