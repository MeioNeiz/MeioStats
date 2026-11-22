-- Settings panel (Esc > Options > AddOns > MeioStats, or /stats settings): no options yet,
-- so it says where the window is and has its buttons.
local _, K = ...

local category

local function Register()
  if category or not (Settings and Settings.RegisterVerticalLayoutCategory) then return end
  local layout
  category, layout = Settings.RegisterVerticalLayoutCategory("MeioStats")
  if layout and CreateSettingsListSectionHeaderInitializer then
    layout:AddInitializer(CreateSettingsListSectionHeaderInitializer("The /stats window",
      "Levelling: played time per level, XP per hour and where it came from. Loot luck: quest"
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
