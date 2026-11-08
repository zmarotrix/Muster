-- Muster's settings page, under NorgannonDB in the game's Settings window (/muster settings). The limits can only be
-- made stricter than the defaults, except whispers an hour, which stops at 40.

local Core = NorgannonCore
local M = Muster
if M.disabled then return end
local UI = Core.UI

Core:OnLogin(function()
  if not M.db then return end
  local page = CreateFrame("Frame")
  page:Hide()
  local list = UI.SettingsList(page)

  list:Header("Limits")
  list:Slider("Whispers an hour", "A rolling hour, per character. 20 is plenty for a good list and useless for a spammer. Over 20, Muster warns you; never more than 40.",
    1, M.HOUR_CEILING, 1, function() return M.db.perHour end, function(v) M.db.perHour = v M.Changed() end, "%.0f", 1)
  list:Slider("Seconds between whispers", "At least 5. Under 15, Muster warns you: fast whispers to strangers read as a bot, and get reported.", M.MIN_GAP, 120, 5, function() return M.db.gap end, function(v) M.db.gap = v end, "%.0f", 1)
  list:Slider("Minutes between adverts in one channel", "At least 15.", M.MIN_ADVERT_MINUTES, 120, 5,
    function() return M.db.advertMinutes end, function(v) M.db.advertMinutes = v end, "%.0f", 1)

  list:Header("Find")
  list:Slider("Lowest level shown", "People below this are often new players or spam alts.", 1, 60, 1,
    function() return M.db.minLevel end, function(v) M.db.minLevel = v M.Changed() end, "%.0f", 1)
  list:Slider("Days before someone asked shows again", "They show as \"asked 97 days ago\", and you can ask once more.", 30, 365, 5,
    function() return M.db.reaskDays end, function(v) M.db.reaskDays = v M.Changed() end, "%.0f", 1)
  list:Toggle("Listen for people asking for a guild", "In channels you're in. It only reads; nothing is sent.",
    function() return M.db.listen end, function(on) M.db.listen = on end)


  page:SetScript("OnShow", function() list:Refresh() end)
  M.settingsPage, M.settingsList = page, list
  M:AddSettingsPage(page)

  local function perf(label, tbl, method) Core:RegisterPerf("Muster: " .. label, tbl, method, "muster") end
  perf("window refresh", M.Window, "Refresh")
  perf("channel line", M.Find, "OnChannel")
  perf("who answer", M.Find, "OnWhoList")
end)
