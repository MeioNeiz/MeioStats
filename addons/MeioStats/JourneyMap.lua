-- The journey on Blizzard's world map: the trail as a dotted line (gold on foot or mounted,
-- blue on flight paths, pale as a ghost), grind spots as faint red squares, and marks where
-- you levelled, died and went into a dungeon. A bar at the map's bottom left turns the trail
-- on and off and replays it: the trail draws itself from the start (or a level) in about
-- REPLAY_SECS, the map following you from zone to zone.
-- Dots, not Line regions: dots read as the Hero's Path trail and the workbench draws them.
-- Sizes are divided by the canvas scale so they stay the same on screen at any zoom.
local _, K = ...
local JM = {}
K.JourneyMap = JM
local J = K.Journey

local DOT_SIZE, DOT_SPACING = 3, 6
local HEAD_SIZE = 9
local MAX_DOTS, MAX_HEAT = 4000, 2500
local MARK_SIZE = 16
local REPLAY_SECS = 90
local REDRAW = 0.2
local COLOURS = {
  walk = { 1, 0.78, 0.15, 0.95 }, taxi = { 0.45, 0.75, 1, 0.8 }, ghost = { 0.85, 0.85, 1, 0.6 },
}
local SKULL = "Interface\\TargetingFrame\\UI-TargetingFrame-Skull"
local DOOR = "Interface\\Icons\\INV_Misc_Key_04"
local ROUND = "Interface\\CharacterFrame\\TempPortraitAlphaMask"

local map, provider, layer, marksLayer, bar
local dots, heat, marks = {}, {}, {}
local nDots, nHeat, nMarks = 0, 0, 0
local head
local replay        -- { pos, rate, total, startAt, lastDraw }
local flat          -- segs with their first global point index: { { seg, first }... }

------------------------------------------------------------------------------ transform
-- world yards on a continent to 0..1 on a map: affine, from three reference points
local transforms = {}
local function Transform(cont, mapID)
  local key = cont .. ":" .. mapID
  local t = transforms[key]
  if t ~= nil then return t or nil end
  local function At(x, y)
    local _, pos = C_Map.GetMapPosFromWorldPos(cont, CreateVector2D(x, y), mapID)
    if pos then return pos:GetXY() end
  end
  local ox, oy = At(0, 0)
  local xx, xy = At(1000, 0)
  local yx, yy = At(0, 1000)
  if not (ox and xx and yx) then
    transforms[key] = false
    return nil
  end
  t = { ox = ox, oy = oy, ax = (xx - ox) / 1000, bx = (yx - ox) / 1000,
    ay = (xy - oy) / 1000, by = (yy - oy) / 1000 }
  transforms[key] = t
  return t
end
JM._Transform = Transform

local function Apply(t, x, y) return t.ox + t.ax * x + t.bx * y, t.oy + t.ay * x + t.by * y end

------------------------------------------------------------------------------ pools
local function Dot(x, y, size, c)
  nDots = nDots + 1
  local d = dots[nDots]
  if not d then
    d = layer:CreateTexture(nil, "ARTWORK")
    dots[nDots] = d
  end
  d:SetSize(size, size)
  d:SetColorTexture(c[1], c[2], c[3], c[4])
  d:ClearAllPoints()
  d:SetPoint("CENTER", layer, "TOPLEFT", x, -y)
  d:Show()
end

local function Heat(x, y, w, h, n)
  nHeat = nHeat + 1
  local q = heat[nHeat]
  if not q then
    q = layer:CreateTexture(nil, "BACKGROUND")
    heat[nHeat] = q
  end
  q:SetSize(w, h)
  q:SetColorTexture(0.9, 0.1, 0.05, math.min(0.45, 0.08 + 0.04 * n))
  q:ClearAllPoints()
  q:SetPoint("CENTER", layer, "TOPLEFT", x, -y)
  q:Show()
end

local function Hide(list, from)
  for i = from + 1, #list do list[i]:Hide() end
end

------------------------------------------------------------------------------ marks
local function Ago(t)
  local days = math.floor((K.Now() - t) / 86400)
  if days <= 0 then return "today" end
  if days == 1 then return "yesterday" end
  return days .. " days ago"
end

local function GearLines(tt, gear)
  local slots = {}
  for slot in pairs(gear) do slots[#slots + 1] = slot end
  table.sort(slots)
  for _, slot in ipairs(slots) do
    local name, _, quality = C_Item.GetItemInfo(gear[slot])
    local r, g, b = 1, 1, 1
    if quality and ITEM_QUALITY_COLORS and ITEM_QUALITY_COLORS[quality] then
      local c = ITEM_QUALITY_COLORS[quality]
      r, g, b = c.r, c.g, c.b
    end
    tt:AddLine(name or ("item " .. gear[slot]), r, g, b)
  end
end

local function MarkTooltip(f)
  local m = f.mark
  local tt = GameTooltip
  tt:SetOwner(f, "ANCHOR_RIGHT")
  if m.kind == "ding" then
    tt:SetText("Level " .. m.lvl)
    local rec = K.db.levels and K.db.levels[m.lvl - 1]
    if rec and rec.played then
      tt:AddDoubleLine("Level " .. (m.lvl - 1) .. " took", K.Duration(rec.played), 1, 0.82, 0,
        1, 1, 1)
    end
  elseif m.kind == "death" then
    tt:SetText("Died")
  else
    tt:SetText(m.text or "Dungeon")
  end
  if m.kind ~= "run" and m.text then tt:AddLine(m.text, 1, 1, 1) end
  tt:AddLine(("Level %d, %s, %s"):format(m.lvl, date("%d %b %H:%M", m.t), Ago(m.t)), 0.6, 0.6,
    0.6)
  if m.kind == "run" then
    for _, r in ipairs(K.db.runs or {}) do
      if r.start == m.t then
        tt:AddDoubleLine("Time inside", K.Duration(r.secs), 1, 0.82, 0, 1, 1, 1)
        tt:AddDoubleLine("XP", K.Count(r.xp), 1, 0.82, 0, 1, 1, 1)
        break
      end
    end
  end
  if m.gear and next(m.gear) then
    if IsShiftKeyDown() then
      tt:AddLine(" ")
      tt:AddLine("Wearing", 1, 0.82, 0)
      GearLines(tt, m.gear)
    elseif not tt.meioShiftHint then
      tt:AddLine("Shift: more", 0.6, 0.6, 0.6)
      tt.meioShiftHint = true
    end
  end
  tt:Show()
end

local function Mark(m, x, y, s)
  nMarks = nMarks + 1
  local f = marks[nMarks]
  if not f then
    f = CreateFrame("Frame", nil, marksLayer)
    f:SetSize(MARK_SIZE, MARK_SIZE)
    f.bg = f:CreateTexture(nil, "BACKGROUND")
    f.bg:SetAllPoints()
    f.bg:SetTexture(ROUND)
    f.bg:SetVertexColor(0, 0, 0, 0.75)
    f.icon = f:CreateTexture(nil, "ARTWORK")
    f.icon:SetPoint("CENTER")
    f.text = f:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    f.text:SetPoint("CENTER", 0, 0)
    f:EnableMouse(true)
    f:SetScript("OnEnter", MarkTooltip)
    f:SetScript("OnLeave", function() GameTooltip:Hide() end)
    marks[nMarks] = f
  end
  f.mark = m
  local ding = m.kind == "ding"
  f.text:SetText(ding and m.lvl or "")
  f.icon:SetShown(not ding)
  if m.kind == "death" then
    f.icon:SetTexture(SKULL)
    f.icon:SetTexCoord(0, 1, 0, 1)
    f.icon:SetSize(MARK_SIZE - 4, MARK_SIZE - 4)
  elseif m.kind == "run" then
    f.icon:SetTexture(DOOR)
    f.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    f.icon:SetSize(MARK_SIZE - 5, MARK_SIZE - 5)
  end
  f:SetScale(s)
  f:ClearAllPoints()
  f:SetPoint("CENTER", marksLayer, "TOPLEFT", x / s, -y / s)
  f:Show()
end

------------------------------------------------------------------------------ drawing
local function Flatten()
  flat = {}
  local n = 0
  for _, s in ipairs(J.Data().segs) do
    flat[#flat + 1] = { seg = s, first = n + 1 }
    n = n + #s.p / 3
  end
  return n
end

-- the global point index -> its seg and that point's x, y, time
local function PointAt(i)
  for k = #flat, 1, -1 do
    local f = flat[k]
    if i >= f.first then
      local b = (math.min(i - f.first + 1, #f.seg.p / 3) - 1) * 3
      return f.seg, f.seg.p[b + 1], f.seg.p[b + 2], f.seg.t + f.seg.p[b + 3]
    end
  end
end

local function Visible(x, y) return x > -0.05 and x < 1.05 and y > -0.05 and y < 1.05 end

-- each seg's visible stretch as canvas points, up to global point `limit`
local function Paths(mapID, w, h, from, limit)
  local paths, length, n = {}, 0, 0
  for _, s in ipairs(J.Data().segs) do
    local count = #s.p / 3
    if n >= limit then break end
    local t = Transform(s.cont, mapID)
    if t and n + count >= from then
      local pts, px, py, prevIn = { kind = s.kind }, nil, nil, false
      for k = 1, count do
        local idx = n + k
        if idx > limit then break end
        if idx >= from then
          local b = (k - 1) * 3
          local mx, my = Apply(t, s.p[b + 1], s.p[b + 2])
          local inside = Visible(mx, my)
          local x, y = mx * w, my * h
          if inside or prevIn then
            if #pts == 0 and px then pts[1], pts[2] = px, py end
            if px and #pts > 0 then length = length + math.sqrt((x - px) ^ 2 + (y - py) ^ 2) end
            pts[#pts + 1], pts[#pts + 2] = x, y
          elseif #pts > 0 then
            paths[#paths + 1] = pts
            pts = { kind = s.kind }
          end
          px, py, prevIn = x, y, inside
        end
      end
      if #pts > 0 then paths[#paths + 1] = pts end
    end
    n = n + count
  end
  return paths, length
end

local function DrawPaths(paths, spacing, size)
  for _, pts in ipairs(paths) do
    local c = COLOURS[pts.kind] or COLOURS.walk
    local acc = spacing
    if #pts == 2 then Dot(pts[1], pts[2], size, c) end
    for i = 3, #pts, 2 do
      local x0, y0, x1, y1 = pts[i - 2], pts[i - 1], pts[i], pts[i + 1]
      local len = math.sqrt((x1 - x0) ^ 2 + (y1 - y0) ^ 2)
      local at = spacing - acc
      while at <= len do
        local f = len > 0 and at / len or 0
        Dot(x0 + (x1 - x0) * f, y0 + (y1 - y0) * f, size, c)
        if nDots >= MAX_DOTS then return end
        at = at + spacing
      end
      acc = len - (at - spacing)
    end
  end
end

local function DrawHeat(mapID, w, h, scale)
  local cell = J.HEAT_CELL
  for cont, cells in pairs(J.Data().heat) do
    local t = Transform(cont, mapID)
    if t then
      local qw = cell * math.max(math.abs(t.ax), math.abs(t.bx)) * w
      local qh = cell * math.max(math.abs(t.ay), math.abs(t.by)) * h
      -- a square under a pixel on screen is noise: continent maps show none
      if qw * scale >= 4 then
        for key, n in pairs(cells) do
          local cx, cy = key:match("^(-?%d+):(-?%d+)$")
          local mx, my = Apply(t, (tonumber(cx) + 0.5) * cell, (tonumber(cy) + 0.5) * cell)
          if Visible(mx, my) then
            Heat(mx * w, my * h, qw, qh, n)
            if nHeat >= MAX_HEAT then return end
          end
        end
      end
    end
  end
end

local function DrawMarks(mapID, w, h, scale, untilT)
  local s = 1 / scale
  for _, m in ipairs(J.Data().marks) do
    if untilT and m.t > untilT then break end
    local t = m.x and m.cont and Transform(m.cont, mapID)
    if t then
      local mx, my = Apply(t, m.x, m.y)
      if mx >= 0 and mx <= 1 and my >= 0 and my <= 1 then Mark(m, mx * w, my * h, s) end
    end
  end
end

local function Draw()
  if not (map and layer and J.Data()) then return end
  nDots, nHeat, nMarks = 0, 0, 0
  local mapID = map:GetMapID()
  local show = replay or K.Option("trail")
  if mapID and show then
    local canvas = map:GetCanvas()
    local w, h = canvas:GetSize()
    local scale = map:GetCanvasScale()
    local total = Flatten()
    local limit, from, untilT = total, 1, nil
    if replay then
      limit, from = math.floor(replay.pos), replay.from
      local _, _, _, t = PointAt(math.max(1, limit))
      untilT = t
    elseif K.Option("heat") then
      DrawHeat(mapID, w, h, scale)
    end
    local paths, length = Paths(mapID, w, h, from, limit)
    local spacing = math.max(DOT_SPACING / scale, length / MAX_DOTS)
    DrawPaths(paths, spacing, DOT_SIZE / scale)
    DrawMarks(mapID, w, h, scale, untilT)
    head:SetShown(replay ~= nil)
  else
    head:Hide()
  end
  Hide(dots, nDots)
  Hide(heat, nHeat)
  Hide(marks, nMarks)
  JM.UpdateBar()
end

-- the replay's moving head between redraws
local function PlaceHead()
  if not replay then return end
  local s, x, y = PointAt(math.max(1, math.floor(replay.pos)))
  local mapID = map:GetMapID()
  local t = s and mapID and Transform(s.cont, mapID)
  if not t then head:Hide() return end
  local mx, my = Apply(t, x, y)
  local canvas = map:GetCanvas()
  local scale = map:GetCanvasScale()
  head:SetSize(HEAD_SIZE / scale, HEAD_SIZE / scale)
  head:ClearAllPoints()
  head:SetPoint("CENTER", layer, "TOPLEFT", mx * canvas:GetWidth(), -my * canvas:GetHeight())
  head:SetShown(Visible(mx, my))
end

local scheduled
function JM.Dirty()
  if scheduled or replay or not (map and map:IsShown()) then return end
  scheduled = true
  C_Timer.After(0, function()
    scheduled = false
    Draw()
  end)
end

-- a new point: redrawn at most once a second while the map is open
local lastAdded = 0
function JM.Added()
  if replay or not (map and map:IsShown()) then return end
  local now = K.Clock()
  if now - lastAdded < 1 then return end
  lastAdded = now
  JM.Dirty()
end

function JM.Refresh()
  transforms = {}
  JM.Dirty()
end

------------------------------------------------------------------------------ replay
local driver = CreateFrame("Frame")

local function ReplayLabel()
  local s, _, _, t = PointAt(math.max(1, math.floor(replay.pos)))
  if not s then return "" end
  local info = s.map and C_Map.GetMapInfo(s.map)
  return ("Level %d, %s, %s"):format(s.lvl, info and info.name or "?", date("%d %b", t))
end

function JM.StopReplay()
  if not replay then return end
  replay = nil
  driver:SetScript("OnUpdate", nil)
  Draw()
end

local function Step(_, elapsed)
  if not (map and map:IsShown()) then return JM.StopReplay() end
  replay.pos = replay.pos + replay.rate * elapsed
  if replay.pos >= replay.total then
    replay.pos = replay.total
    Draw()
    return JM.StopReplay()
  end
  local s = PointAt(math.floor(replay.pos))
  if s and s.map and s.map ~= replay.followed then
    replay.followed = s.map
    if s.map ~= map:GetMapID() then map:SetMapID(s.map) end
  end
  replay.sinceDraw = replay.sinceDraw + elapsed
  if replay.sinceDraw >= REDRAW then
    replay.sinceDraw = 0
    Draw()
  end
  PlaceHead()
  JM.UpdateBar()
end

-- from the first point at or after level `fromLevel` (nil: the start)
function JM.Replay(fromLevel)
  if not (J.Data() and J.Points() > 1) then
    K.Print("no journey to replay yet: it records from now, as you travel")
    return
  end
  if InCombatLockdown() then
    K.Print("the replay waits until you're out of combat")
    return
  end
  local stats = K.UI.Frame()
  if stats and stats:IsShown() then stats:Hide() end
  if not WorldMapFrame:IsShown() then ShowUIPanel(WorldMapFrame) end
  if not map then JM.Attach() end
  local total = Flatten()
  local from = 1
  if fromLevel then
    for _, f in ipairs(flat) do
      if f.seg.lvl >= fromLevel then from = f.first break end
    end
  end
  replay = { pos = from, from = from, total = total, sinceDraw = REDRAW,
    rate = math.max(15, (total - from + 1) / REPLAY_SECS) }
  driver:SetScript("OnUpdate", Step)
  Step(nil, 0)
end

function JM.Replaying() return replay ~= nil end

------------------------------------------------------------------------------ the bar
function JM.UpdateBar()
  if not bar then return end
  local has = J.Data() and J.Points() > 1
  bar:SetShown(has or replay ~= nil)
  bar.trail:SetChecked(K.Option("trail"))
  bar.play:SetText(replay and "Stop" or "Replay")
  bar.progress:SetShown(replay ~= nil)
  bar.label:SetShown(replay ~= nil)
  bar.trail:SetShown(not replay)
  if replay then
    bar.progress:SetMinMaxValues(replay.from, math.max(replay.from + 1, replay.total))
    bar.progress:SetValue(replay.pos)
    bar.label:SetText(ReplayLabel())
  end
end

local function TipOn(self)
  GameTooltip:SetOwner(self, "ANCHOR_TOP")
  GameTooltip:SetText(self.tipTitle)
  GameTooltip:AddLine(self.tip, 1, 1, 1, true)
  GameTooltip:Show()
end

local function Bar(parent)
  local b = CreateFrame("Frame", nil, parent)
  b:SetSize(380, 26)
  b:SetPoint("BOTTOMLEFT", 6, 6)
  b:SetFrameLevel(parent:GetFrameLevel() + 600)
  local bg = b:CreateTexture(nil, "BACKGROUND")
  bg:SetAllPoints()
  bg:SetColorTexture(0, 0, 0, 0.55)

  b.play = CreateFrame("Button", nil, b, "UIPanelButtonTemplate")
  b.play:SetSize(64, 20)
  b.play:SetPoint("LEFT", 3, 0)
  b.play:SetScript("OnClick", function()
    if replay then JM.StopReplay() else JM.Replay() end
  end)
  b.play.tipTitle = "Replay your journey"
  b.play.tip = "The trail draws itself from your first step, the map following you from zone"
    .. " to zone (/stats replay)."
  b.play:SetScript("OnEnter", TipOn)
  b.play:SetScript("OnLeave", function() GameTooltip:Hide() end)

  b.trail = CreateFrame("CheckButton", nil, b, "UICheckButtonTemplate")
  b.trail:SetSize(22, 22)
  b.trail:SetPoint("LEFT", b.play, "RIGHT", 4, 0)
  b.trail.label = b.trail:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  b.trail.label:SetPoint("LEFT", b.trail, "RIGHT", 0, 1)
  b.trail.label:SetText("Your trail")
  b.trail:SetScript("OnClick", function(self)
    K.SetOption("trail", self:GetChecked() and true or false)
  end)
  b.trail.tipTitle = "Your trail"
  b.trail.tip = "Where you've been since MeioStats started recording, where you levelled,"
    .. " died and went into dungeons (/stats trail on||off)."
  b.trail:SetScript("OnEnter", TipOn)
  b.trail:SetScript("OnLeave", function() GameTooltip:Hide() end)

  b.progress = CreateFrame("StatusBar", nil, b)
  b.progress:SetSize(110, 8)
  b.progress:SetPoint("LEFT", b.play, "RIGHT", 6, 0)
  b.progress:SetStatusBarTexture("Interface\\TargetingFrame\\UI-StatusBar")
  b.progress:SetStatusBarColor(1, 0.78, 0.15)
  local pbg = b.progress:CreateTexture(nil, "BACKGROUND")
  pbg:SetAllPoints()
  pbg:SetColorTexture(1, 1, 1, 0.15)
  b.progress:EnableMouse(true)
  b.progress:SetScript("OnMouseDown", function(self)
    if not replay then return end
    local x = GetCursorPosition() / self:GetEffectiveScale()
    local f = math.min(1, math.max(0, (x - self:GetLeft()) / self:GetWidth()))
    replay.pos = replay.from + f * (replay.total - replay.from)
    replay.followed, replay.sinceDraw = nil, REDRAW
  end)
  b.label = b:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  b.label:SetPoint("LEFT", b.progress, "RIGHT", 6, 0)
  b.label:SetPoint("RIGHT", -6, 0)
  b.label:SetJustifyH("LEFT")
  b.label:SetWordWrap(false)
  return b
end

------------------------------------------------------------------------------ attach
function JM.Attach()
  if map or not (WorldMapFrame and MapCanvasDataProviderMixin and J.Data()) then return end
  if not (C_Map and C_Map.GetMapPosFromWorldPos) then return end
  map = WorldMapFrame
  local canvas = map:GetCanvas()
  local levels = map.GetPinFrameLevelsManager and map:GetPinFrameLevelsManager()
  local function Level(kind, fallback)
    local ok, lvl = pcall(levels.GetValidFrameLevel, levels, kind)
    return ok and lvl or canvas:GetFrameLevel() + fallback
  end
  layer = CreateFrame("Frame", nil, canvas)
  layer:SetAllPoints(canvas)
  layer:SetFrameLevel(Level("PIN_FRAME_LEVEL_MAP_HIGHLIGHT", 5))
  marksLayer = CreateFrame("Frame", nil, canvas)
  marksLayer:SetAllPoints(canvas)
  marksLayer:SetFrameLevel(Level("PIN_FRAME_LEVEL_AREA_POI", 20))
  head = layer:CreateTexture(nil, "OVERLAY")
  head:SetTexture(ROUND)
  head:SetVertexColor(1, 0.95, 0.6, 1)
  head:Hide()

  provider = CreateFromMixins(MapCanvasDataProviderMixin)
  function provider:RefreshAllData() Draw() end
  function provider:RemoveAllData() end
  function provider:OnMapChanged()
    MapCanvasDataProviderMixin.OnMapChanged(self)
    if replay then replay.sinceDraw = REDRAW end
    JM.Dirty()
  end
  function provider:OnCanvasScaleChanged()
    if replay then replay.sinceDraw = REDRAW else JM.Dirty() end
  end
  function provider:OnShow() JM.Dirty() end
  map:AddDataProvider(provider)
  bar = Bar(map.ScrollContainer or map)
  JM.UpdateBar()
end

K.On("PLAYER_LOGIN", function()
  local ok, err = pcall(JM.Attach)
  if not ok then geterrorhandler()(err) end
end)

JM._test = { Draw = Draw, Flatten = Flatten, Counts = function() return nDots, nHeat, nMarks end,
  Bar = function() return bar end, Head = function() return head end, Step = Step }
