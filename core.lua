-- Muster: guild recruitment, without the spam. Built on NorgannonDB_Core.
-- Plan and client findings: docs/muster-v1.md; the look: design/suite/muster.html.
--
-- The one rule everything here keeps: one click sends one message to one person. Nothing is sent by a timer, an event
-- or a queue. The harness checks it by failing any send that doesn't happen inside a click.

local ADDON = ...
local Core = NorgannonCore

Muster = Muster or {}
local M = Muster
M.addonName = ADDON or "Muster"

if not (Core and Core:Require(1, 17)) then
  M.disabled = true
  C_Timer.After(5, function()
    print("|cffe87ad6Muster|r needs NorgannonDB Core 1.17 or newer; it is turned off.")
  end)
  return
end

M.PREFIX = "|cffe87ad6Muster|r"
function M:Print(msg) Core:Print(msg, self.PREFIX) end

-------------------------------------------------------------------------------------------
-- Calling the client. Any call may be missing, refuse, or answer in secret values, which count as no answer.
-------------------------------------------------------------------------------------------

local function clean(ok, ...)
  if not ok then return nil end
  local n = select("#", ...)
  if n == 0 then return nil end
  local out = { ... }
  for i = 1, n do
    if Core.IsSecret(out[i]) then out[i] = nil end
  end
  return unpack(out, 1, n)
end

---The global function name(...), with errors and secret values turned into nil.
function M.Global(name, ...)
  local fn = rawget(_G, name)
  if type(fn) ~= "function" then return nil end
  return clean(pcall(fn, ...))
end

---The namespaced client function ns.name(...).
function M.In(ns, name, ...)
  local t = rawget(_G, ns)
  local fn = type(t) == "table" and t[name]
  if type(fn) ~= "function" then return nil end
  return clean(pcall(fn, ...))
end

---Does the client have ns.name (or the global name when ns is nil)?
function M.Has(ns, name)
  if not ns then return type(rawget(_G, name)) == "function" end
  local t = rawget(_G, ns)
  return type(t) == "table" and type(t[name]) == "function"
end

---Sends one chat line: a whisper or a channel message. Only ever called from a click. The client has both the namespaced
---call and the old global (/rprobe found both); the namespaced one is the one that stays.
function M.Say(text, kind, target)
  local api = rawget(_G, "C_ChatInfo")
  local send = (type(api) == "table" and api.SendChatMessage) or rawget(_G, "SendChatMessage")
  send(text, kind, nil, target)
end

function M.Now() return M.Global("GetServerTime") or time() end
function M.Clock() return GetTime() end

---A game format string ("%s has joined the guild.") as a Lua pattern with its arguments captured.
function M.Pattern(text)
  if type(text) ~= "string" then return nil end
  text = text:gsub("%%%d%$([sd])", "%%%1")   -- "%1$s" is "%s" here: every format Muster reads has one name in it
  local pattern = text:gsub("([%(%)%.%+%-%*%?%[%]%^%$])", "%%%1")
  pattern = pattern:gsub("%%s", "(.-)"):gsub("%%d", "(%%d+)")
  return "^" .. pattern .. "$"
end

-------------------------------------------------------------------------------------------
-- Names
--
-- Forever characters have a first and a last name. Chat gives both ("Tyrant Kuma"); the roster and UnitName give the
-- first; a whisper to the first alone fails. So a person is kept under the fullest name seen, and found by either.
-------------------------------------------------------------------------------------------

---The name with any realm taken off, nil if secret or empty. "Elowen Brightwater-Realm" is "Elowen Brightwater".
function M.Clean(name)
  if type(name) ~= "string" or Core.IsSecret(name) then return nil end
  name = strtrim(name)
  if name == "" then return nil end
  local short = M.Global("Ambiguate", name, "none")
  return short or name
end

---The first name: who the roster and UnitName say.
function M.First(name)
  name = M.Clean(name)
  return name and (name:match("^%S+") or name)
end

---The key a person is saved under.
function M.Key(name)
  name = M.Clean(name)
  return name and string.lower(name)
end

function M.HasSurname(name)
  name = M.Clean(name)
  return name ~= nil and name:find(" ", 1, true) ~= nil
end

function M.Me() return M.Clean((M.Global("UnitName", "player"))) end

---Your own first and last name. GetUnitName gave "Tyrant Kuma" where UnitName gave "Tyrant" (seen by /rprobe).
function M.MyFullName()
  local full = M.Clean(M.Global("GetUnitName", "player", false))
  if full and M.HasSurname(full) then return full end
  return M.FullName(M.Me())
end

-- Full names learned from any chat line, by first name, so a roster name can be turned into something a whisper reaches.
M.fullNames = {}
function M.LearnName(name)
  name = M.Clean(name)
  if name and M.HasSurname(name) then M.fullNames[string.lower(M.First(name))] = name end
end
function M.FullName(name)
  name = M.Clean(name)
  if not name then return nil end
  if M.HasSurname(name) then return name end
  return M.fullNames[string.lower(name)] or name
end

-------------------------------------------------------------------------------------------
-- Classes: from the client, since Forever adds its own races and may add classes
-------------------------------------------------------------------------------------------

local FALLBACK = { "WARRIOR", "PALADIN", "HUNTER", "ROGUE", "PRIEST", "SHAMAN", "MAGE", "WARLOCK", "DRUID" }
M.HEALERS = { PRIEST = true, SHAMAN = true, DRUID = true, PALADIN = true }

---{ { file = "PRIEST", name = "Priest", id = 5 }, ... } in the client's order.
function M.Classes()
  if M.classes then return M.classes end
  local out, byName = {}, {}
  for i = 1, M.Global("GetNumClasses") or 0 do
    local name, file, id = M.Global("GetClassInfo", i)
    if file and name then
      out[#out + 1] = { file = file, name = name, id = id }
    end
  end
  if #out == 0 then
    local names = rawget(_G, "LOCALIZED_CLASS_NAMES_MALE") or {}
    for i, file in ipairs(FALLBACK) do
      out[#out + 1] = { file = file, name = names[file] or (file:sub(1, 1) .. file:sub(2):lower()), id = i }
    end
  end
  for _, c in ipairs(out) do byName[string.lower(c.name)] = c.file end
  M.classes, M.classByName = out, byName
  return out
end

---The class token from a localized class name ("Priest" from /who), or the token itself.
function M.ClassFile(text)
  if type(text) ~= "string" then return nil end
  M.Classes()
  return M.classByName[string.lower(text)] or (rawget(_G, "RAID_CLASS_COLORS") and RAID_CLASS_COLORS[text] and text) or nil
end

function M.ClassName(file)
  for _, c in ipairs(M.Classes()) do if c.file == file then return c.name end end
  return file and (file:sub(1, 1) .. file:sub(2):lower()) or "?"
end

---A name in its class colour.
function M.Colored(name, class)
  local colors = rawget(_G, "RAID_CLASS_COLORS")
  local color = class and colors and colors[class]
  if color and color.colorStr then return "|c" .. color.colorStr .. (name or "?") .. "|r" end
  return name or "?"
end

---"3 min ago", "2 days ago".
function M.Ago(t)
  if not t then return "" end
  local d = math.max(0, M.Now() - t)
  if d < 60 then return "just now" end
  if d < 3600 then return math.floor(d / 60) .. " min ago" end
  if d < 86400 then return math.floor(d / 3600) .. " h ago" end
  local days = math.floor(d / 86400)
  return days == 1 and "yesterday" or (days .. " days ago")
end

-------------------------------------------------------------------------------------------
-- A small scheduler, for things that only wait (cooldown labels, expiring chat leads). Nothing sends from here.
-------------------------------------------------------------------------------------------

local later = {}
function M.Later(seconds, fn)
  later[#later + 1] = { at = M.Clock() + seconds, fn = fn }
end

function M.Tick()
  if M.disabled or not M.db then return end
  local now = M.Clock()
  local due
  for i = #later, 1, -1 do
    if later[i].at <= now then
      due = due or {}
      table.insert(due, 1, later[i].fn)
      table.remove(later, i)
    end
  end
  if due then
    for _, fn in ipairs(due) do Core.SafeCall(fn) end
  end
  Core.Guild:Tick(now)
  if M.Find then M.Find:Tick() end
  if M.Window then M.Window:Tick() end
end

-------------------------------------------------------------------------------------------
-- Saved data. Account-wide, so alts share who's been asked. People are kept per guild.
-------------------------------------------------------------------------------------------

M.DEFAULTS = {
  gap = 15,            -- seconds between whispers (5 at least; under 15 warns)
  perHour = 20,        -- whispers an hour (up to M.HOUR_CEILING; over 20 warns)
  advertMinutes = 15,  -- per channel (longer only)
  minLevel = 10,       -- people below this aren't shown
  reaskDays = 90,      -- an asked person shows again after this long
  listen = true,       -- Heard in chat
  template = nil,      -- the template Find whispers with
}
M.HOUR_CEILING = 40
M.MIN_GAP = 5          -- the floor: never faster than this
M.SAFE_GAP = 15        -- under this, Muster warns: it reads as a bot to players and to reports
M.SAFE_HOUR = 20       -- over this, Muster warns
M.LOW_LEFT = 3         -- this many whispers left in the hour, and Find says so
M.MIN_ADVERT_MINUTES = 15

local function guildKey()
  local name = M.Global("GetGuildInfo", "player")
  if not name then return nil end
  return (M.Global("GetRealmName") or "?") .. "/" .. name
end

---This guild's saved part: people, needs and adverts. nil when not in a guild.
function M:Guild()
  local key = guildKey()
  if not key or not self.db then return nil end
  local g = self.db.guilds[key]
  if not g then
    g = { people = {}, needs = {}, adverts = { lines = {}, posted = {} } }
    self.db.guilds[key] = g
  end
  g.people = g.people or {}
  g.needs = g.needs or {}
  g.adverts = g.adverts or { lines = {}, posted = {} }
  g.adverts.posted = g.adverts.posted or {}
  return g, key
end

---This character's own sending record (the game mutes a character, not an account).
function M:Mine()
  local me = (self.Me() or "?") .. "@" .. (M.Global("GetRealmName") or "?")
  self.db.chars[me] = self.db.chars[me] or { sent = {} }
  return self.db.chars[me]
end

local function changed()
  if M.Window then M.Window:Changed() end
end
M.Changed = changed

Core:On("ADDON_LOADED", M, function(_, name)
  if name ~= M.addonName then return end
  Core:Off("ADDON_LOADED", M)
  local saved = rawget(_G, "MusterDB")
  MusterDB = type(saved) == "table" and saved or {}
  M.db = MusterDB
  for k, v in pairs(M.DEFAULTS) do
    if M.db[k] == nil then M.db[k] = v end
  end
  M.db.guilds = M.db.guilds or {}
  M.db.chars = M.db.chars or {}
  if M.Asking then M.Asking:EnsureTemplates() end
end)

Core:OnLogin(function()
  if not M.db then return end
  Core.Guild:Watch("muster")
  if C_Timer and C_Timer.NewTicker then C_Timer.NewTicker(1, M.Tick) end
end)

-------------------------------------------------------------------------------------------
-- Opening
-------------------------------------------------------------------------------------------

function M:Toggle()
  local win = self.Window and self.Window:Get()
  if not win then return end
  if win:IsShown() then win:Hide() else self.Window:Open() end
end

Core:RegisterAddon("muster", {
  version = C_AddOns and C_AddOns.GetAddOnMetadata(M.addonName, "Version") or "0.1.0",
  open = function() M:Toggle() end,
})

SLASH_MUSTER1 = "/muster"
SlashCmdList["MUSTER"] = function(msg)
  msg = strtrim(msg or "")
  local lower = string.lower(msg)
  if lower == "" then
    M:Toggle()
  elseif lower == "settings" or lower == "options" then
    M:OpenSettings()
  elseif lower == "find" or lower == "people" or lower == "asking" or lower == "results" then
    M.Window:Open(lower)
  elseif lower:match("^add ") then
    local name = M.Clean(msg:sub(5))
    if name then
      local p = M.People:Add(name, { source = "added" })
      if p then
        M:Print(M.Colored(p.name, p.class) .. " is in People.")
        M.Window:Open("people", p.key)
      end
    end
  elseif lower == "status" then
    M:PrintStatus()
  else
    M:Print("/muster opens the window. Also: /muster add First Last, find, people, asking, results, settings, status")
  end
end

---A short account of where things stand, for checking in game.
function M:PrintStatus()
  local g = self:Guild()
  if not g then return self:Print("You're not in a guild, so there's nobody to recruit for.") end
  local n = 0
  for _ in pairs(g.people) do n = n + 1 end
  self:Print(string.format("%d people kept for %s. You %s.", n, M.Global("GetGuildInfo", "player") or "?",
    Core.Guild:CanInvite() and "can invite" or "can't invite on this character"))
  self:Print("Whispers: " .. (self.Guards:WhyNotWhisper() or "ready") .. " " .. self.Guards:HourText() .. ".")
  self:Print("/who: " .. (self.Find:Status()))
end

local function onClick(button)
  if button == "RightButton" then M:OpenSettings() else M:Toggle() end
end
local function tooltip(tt)
  tt:AddLine("Muster", .91, .478, .839)
  tt:AddLine("Guild recruitment, without the spam", 1, 1, 1)
  local waiting = M.People and M.People:CountWaiting() or 0
  if waiting > 0 then tt:AddLine(waiting .. (waiting == 1 and " reply waits" or " replies wait") .. " for you", .91, .478, .839) end
  tt:AddLine("Click: open or close  ·  Right-click: settings  ·  Drag: move", .43, .4, .32)
end
Core:OnLogin(function() Core.MinimapButton:Add("muster", { onClick = onClick, tooltip = tooltip }) end)
function Muster_OnAddonCompartmentClick(_, button) onClick(button) end
function Muster_OnAddonCompartmentEnter(_, frame)
  GameTooltip:SetOwner(frame, "ANCHOR_LEFT")
  tooltip(GameTooltip)
  GameTooltip:Show()
end
function Muster_OnAddonCompartmentLeave() GameTooltip:Hide() end
