-- Muster: guild recruitment, without the spam. Built on NorgannonDB_Core.
-- Plan and client findings: docs/muster-v1.md; the look: design/suite/muster.html.
--
-- The one rule everything here keeps: one click sends one message to one person. Nothing is sent by a timer, an event
-- or a queue. The harness checks it by failing any send that doesn't happen inside a click.

local ADDON = ...
local Core = NorgannonCore

if not (Core and Core.NewAddon) then
  Muster = { disabled = true }
  print("Muster needs NorgannonDB Core 1.20 or newer; it is turned off.")
  return
end

Muster = Muster or {}
local M = Muster

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
  guilds = {},         -- [realm/guild] = { people, needs, adverts }
  chars = {},          -- [name@realm] = this character's own sending record
}
M.HOUR_CEILING = 40
M.MIN_GAP = 5          -- the floor: never faster than this
M.SAFE_GAP = 15        -- under this, Muster warns: it reads as a bot to players and to reports
M.SAFE_HOUR = 20       -- over this, Muster warns
M.LOW_LEFT = 3         -- this many whispers left in the hour, and Find says so
M.MIN_ADVERT_MINUTES = 15

-- The suite's plumbing (Core:NewAddon): version check, MusterDB with its defaults, the slash command, the minimap row
-- and the add-on menu. Left-click and /muster open the window; right-click opens settings.
Core:NewAddon("muster", {
  folder = ADDON, api = { 1, 20 },
  db = "MusterDB", defaults = M.DEFAULTS,
  slash = { "/muster" },
  commands = {
    find = { function() M.Window:Open("find") end, "the Find tab" },
    people = { function() M.Window:Open("people") end, "everyone you've found or asked" },
    asking = { function() M.Window:Open("asking") end, "what you whisper and advertise" },
    results = { function() M.Window:Open("results") end, "who joined" },
    add = { function(rest)
      local name = M.Clean(rest)
      if not name then return M:Print("/muster add First Last") end
      local p = M.People:Add(name, { source = "added" })
      if p then
        M:Print(M.Colored(p.name, p.class) .. " is in People.")
        M.Window:Open("people", p.key)
      end
    end, "First Last: put someone in People" },
    status = { function() M:PrintStatus() end, "where things stand" },
  },
  minimap = {
    status = function()
      local waiting = M.People and M.db and M:Guild() and M.People:CountWaiting() or 0
      if waiting > 0 then return waiting .. (waiting == 1 and " reply waits" or " replies wait") .. " for you" end
    end,
  },
})
if M.disabled then return end

-------------------------------------------------------------------------------------------
-- Calling the client: Core's helpers. Any call may be missing, refuse, or answer in secret values.
-------------------------------------------------------------------------------------------

M.Global, M.In, M.Has, M.Now = Core.Global, Core.In, Core.Has, Core.Now

---Sends one chat line: a whisper or a channel message. Only ever called from a click. The client has both the namespaced
---call and the old global (/rprobe found both); the namespaced one is the one that stays.
function M.Say(text, kind, target)
  local api = rawget(_G, "C_ChatInfo")
  local send = (type(api) == "table" and api.SendChatMessage) or rawget(_G, "SendChatMessage")
  send(text, kind, nil, target)
end

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

local Names = Core.Names
M.Clean = Names.Full                 -- "Elowen Brightwater-Realm" is "Elowen Brightwater"; nil if secret or empty
M.First = Names.First                -- who the roster and UnitName say
M.HasSurname = Names.HasSurname

---The key a person is saved under: the full name in lower case (People has always keyed on it).
function M.Key(name)
  name = Names.Full(name)
  return name and string.lower(name)
end

function M.Me() return M.Clean((M.Global("UnitName", "player"))) end

---Your own first and last name ("Tyrant Kuma").
function M.MyFullName() return Names.Me() end

-- Full names are learned from chat by the Core (Core.Names); a roster's first name becomes one a whisper reaches.
function M.LearnName(name) Names:Learn(name) end
function M.FullName(name)
  return Names:Address(name) or Names.Full(name)
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
-- This guild's part of the saved data
-------------------------------------------------------------------------------------------

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

M:OnReady(function()
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
