-- Settings panel (Esc > Options > AddOns > MeioStats, or /stats settings): where the window
-- is and its buttons, then the checkboxes, in the same words as their chat toggles.
local _, K = ...

local category

local function Toggle(key, name, tip)
  if not (Settings.RegisterProxySetting and Settings.CreateCheckbox) then return end
  local setting = Settings.RegisterProxySetting(category, "MEIOSTATS_" .. key:upper(),
    Settings.VarType.Boolean, name, K.OPTIONS[key].default,
    function() return K.Option(key) end, function(v) K.SetOption(key, v) end)
  Settings.CreateCheckbox(category, setting, tip)
end

local function Register()
  if category or not (Settings and Settings.RegisterVerticalLayoutCategory) then return end
  local layout
  category, layout = Settings.RegisterVerticalLayoutCategory("MeioStats")
  if layout and CreateSettingsListSectionHeaderInitializer then
    layout:AddInitializer(CreateSettingsListSectionHeaderInitializer("The /stats window",
      "Levelling: played time per level, XP per hour and where it came from. Journey: how far"
      .. " you went and where you levelled. Loot luck: quest"
      .. " drops against Questie's drop rates. Money: sales and profit from TSM's ledger."
      .. " Type /stats help for every command."))
  end
  if layout and CreateSettingsButtonInitializer then
    layout:AddInitializer(CreateSettingsButtonInitializer("Stats window", "Open /stats",
      function()
        if SettingsPanel and SettingsPanel:IsShown() then HideUIPanel(SettingsPanel) end
        K.UI.Show()
      end, "Close Settings and open the MeioStats window.", true))
    layout:AddInitializer(CreateSettingsButtonInitializer("Window position", "Reset",
      K.ResetWindow,
      "Put the window back in the middle of the screen (same as /stats reset).", true))
  end
  if layout and CreateSettingsListSectionHeaderInitializer then
    layout:AddInitializer(CreateSettingsListSectionHeaderInitializer("XP bar",
      "Blizzard's XP bar. FlareUI replaces it with its own, which has a Quest XP setting."))
  end
  Toggle("questBar", "Quest XP band",
    "A gold band on the XP bar shows how far handing in your finished quests takes you, and"
    .. " the bar's tooltip says how much XP that is (/stats questxp on||off).")
  Toggle("questOpen", "Quests in progress",
    "A fainter band past the gold one adds the quests you haven't finished yet"
    .. " (/stats questxp progress on||off).")
  if layout and CreateSettingsListSectionHeaderInitializer then
    layout:AddInitializer(CreateSettingsListSectionHeaderInitializer("World map",
      "Your journey since MeioStats started recording. The bar at the map's bottom left"
      .. " replays it."))
  end
  Toggle("trail", "Your trail", "A dotted line where you've been, with where you levelled,"
    .. " died and went into dungeons (/stats trail on||off).")
  Toggle("heat", "Grind spots", "Faint red squares where you killed the most, on zone maps"
    .. " (/stats heat on||off).")
  if layout and CreateSettingsListSectionHeaderInitializer then
    layout:AddInitializer(CreateSettingsListSectionHeaderInitializer("Chat",
      "What MeioStats says in chat."))
  end
  Toggle("dingLine", "Level-up summary", "At each new level, one chat line: how long the"
    .. " level took against the one before, and its kills and quests"
    .. " (/stats ding on||off).")
  Settings.RegisterAddOnCategory(category)
end

K.On("PLAYER_LOGIN", function()
  local ok, err = pcall(Register)
  if not ok then geterrorhandler()(err) end
end)

function K.OpenSettings()
  if category then
    Settings.OpenToCategory(category:GetID())
  else
    K.Print("the Settings panel isn't available; /stats help lists every command")
  end
end
