-- Find: who's worth asking right now.
--
-- Around now: one press of Next sends one /who for one level band, and the answer is filtered here: no guild, not
-- ignored, not you or your guild, at or above the lowest level, and nobody already asked, said no or chose never.
-- Needed classes sort first. A band over 50 people is cut short by the server, so Muster says so and splits it next time.
--
-- Heard in chat: lines in channels you're in where someone asks for a guild. Adverts are left out. Leads last an hour.

local Core = NorgannonCore
local M = Muster
if M.disabled then return end

local Find = { rows = {}, heard = {}, hidden = 0, total = 0, skipped = {} }
M.Find = Find

local WHO_GAP = 5          -- seconds between /who presses; the server's own throttle is unmeasured
local WHO_WAIT = 6         -- no answer by then: the server likely refused
local MAX_WHO = 50         -- the game's MAX_WHOS_FROM_SERVER
local HEARD_FOR = 3600
local NEED_ORDER = { want = 0, open = 1, full = 2 }

-------------------------------------------------------------------------------------------
-- Level bands
-------------------------------------------------------------------------------------------

---The bands, from the lowest level shown to the cap. A band the server cut short is split in two next time.
function Find:Bands()
  local low = math.max(1, M.db.minLevel or 10)
  local cap = M.Global("GetMaxPlayerLevel") or 60
  if self.bandsFor ~= low .. ":" .. cap then
    self.bandsFor = low .. ":" .. cap
    local bands, l = {}, low
    -- tens, then fives in the last ten levels, where most people are, then the cap on its own: 10-19 ... 50-54, 55-59, 60
    while l <= cap do
      local h
      if l == cap then h = cap
      elseif l >= cap - 10 then h = math.min(cap - 1, l - (l % 5) + 4)
      else h = l - (l % 10) + 9 end
      bands[#bands + 1] = { l, h }
      l = h + 1
    end
    self.bands, self.band = bands, 0
  end
  return self.bands
end

function Find.BandText(b)
  if not b then return "" end
  return b[1] == b[2] and tostring(b[1]) or (b[1] .. "-" .. b[2])
end

---The band the next press asks for.
function Find:NextBand()
  local bands = self:Bands()
  return bands[(self.band % #bands) + 1]
end

local function split(self, index)
  local b = self.bands[index]
  if not b or b[1] >= b[2] then return end
  local mid = math.floor((b[1] + b[2]) / 2)
  table.remove(self.bands, index)
  table.insert(self.bands, index, { mid + 1, b[2] })
  table.insert(self.bands, index, { b[1], mid })
end

-------------------------------------------------------------------------------------------
-- Asking the server
-------------------------------------------------------------------------------------------

---Seconds until Next may be pressed again.
function Find:Wait()
  if not self.sentAt then return 0 end
  return math.max(0, math.ceil(self.sentAt + WHO_GAP - M.Clock()))
end

function Find:Status()
  if self.waiting then return "waiting for the server" end
  if self.refused then return "the server didn't answer the last one; it may limit how often /who can be used" end
  local w = self:Wait()
  return w > 0 and ("next in " .. w .. " s") or "ready"
end

-- While our /who is out, the Who window stays shut: otherwise the game opens the social panel over everything.
local function quietWho(on)
  local frame = rawget(_G, "FriendsFrame")
  if not frame or not frame.UnregisterEvent then return end
  if on then
    pcall(frame.UnregisterEvent, frame, "WHO_LIST_UPDATE")
  else
    pcall(frame.RegisterEvent, frame, "WHO_LIST_UPDATE")
  end
end

---The Next button: one /who for the next band. Only ever called from a click.
function Find:Next()
  if self:Wait() > 0 or self.waiting then return false end
  local bands = self:Bands()
  self.band = (self.band % #bands) + 1
  local b = bands[self.band]
  self.asking = b
  self.sentAt, self.waiting, self.refused = M.Clock(), true, nil
  quietWho(true)
  M.In("C_FriendList", "SetWhoToUi", true)
  local origin = rawget(_G, "Enum") and Enum.SocialWhoOrigin and Enum.SocialWhoOrigin.Social
  if M.Has("C_FriendList", "SendWho") then
    C_FriendList.SendWho(Find.BandText(b), origin)
  else
    SendWho(Find.BandText(b))
  end
  M.Changed()
  return true
end

function Find:Tick()
  if self.waiting and M.Clock() - (self.sentAt or 0) > WHO_WAIT then
    self.waiting, self.refused = false, true
    quietWho(false)
    M.Changed()
  end
  -- leads heard in chat expire
  local now, dropped = M.Now(), false
  for key, h in pairs(self.heard) do
    if now - h.at > HEARD_FOR then self.heard[key], dropped = nil, true end
  end
  if dropped then M.Changed() end
end

local function needOf(class)
  local g = M:Guild()
  return (g and class and g.needs[class]) or "open"
end
Find.NeedOf = needOf

local function sortRows(rows)
  table.sort(rows, function(a, b)
    local na, nb = NEED_ORDER[needOf(a.class)], NEED_ORDER[needOf(b.class)]
    if na ~= nb then return na < nb end
    if (a.level or 0) ~= (b.level or 0) then return (a.level or 0) > (b.level or 0) end
    return a.name < b.name
  end)
end

---Should this person show in Find? Returns ok, and the time they were asked if that was long enough ago to ask again.
function Find:Shows(name, level, guildless)
  name = M.Clean(name)
  if not name then return false end
  if level and level < (M.db.minLevel or 10) then return false end
  local key = M.Key(name)
  if key == M.Key(M.MyFullName()) or key == M.Key(M.Me()) then return false end
  -- the roster only gives first names, so a lead from chat who shares one with a member is left out; a /who row
  -- already says they have no guild
  if not guildless and Core.Guild:IsMember(M.First(name)) and not M.People:Get(name) then return false end
  if M.In("C_FriendList", "IsIgnored", name) or M.Global("IsIgnored", name) then return false end
  if self.skipped[string.lower(name)] then return false end
  local hidden, askedAt = M.People:Hidden(name)
  if hidden then return false end
  return true, askedAt
end

---The server's answer to our /who.
function Find:OnWhoList()
  if not self.waiting then return end
  self.waiting = false
  quietWho(false)
  local shown, total = M.In("C_FriendList", "GetNumWhoResults")
  shown, total = shown or 0, total or shown or 0
  local rows, hidden = {}, 0
  for i = 1, shown do
    local info = M.In("C_FriendList", "GetWhoInfo", i)
    if type(info) == "table" and info.fullName and not Core.IsSecret(info.fullName) then
      local guild = info.fullGuildName
      local class = info.filename or M.ClassFile(info.classStr)
      M.LearnName(info.fullName)
      if guild and guild ~= "" then
        hidden = hidden + 1
      else
        local ok, askedAt = self:Shows(info.fullName, info.level, true)
        if ok then
          rows[#rows + 1] = { name = M.Clean(info.fullName), class = class, level = info.level, zone = info.area, race = info.raceStr, askedAt = askedAt, source = "who" }
        end
      end
    end
  end
  sortRows(rows)
  self.rows, self.hidden, self.total, self.shownCount = rows, hidden, total, shown
  self.cut = total > shown or shown >= MAX_WHO
  if self.cut then split(self, self.band) end
  M.Changed()
end

-------------------------------------------------------------------------------------------
-- Heard in chat
-------------------------------------------------------------------------------------------

-- An advert says who's recruiting; a lead asks to be recruited. The match is deliberately narrow, and only a suggestion.
local ADVERT = { "recruit", "<", "we are", "we're", "our guild", "pst", "/w me", "whisper me", "w me", "pm me", "msg me", "apply", "join us", "is looking for", "are looking for", "now accepting" }
local ASKING = {
  "lf guild", "lfguild", "looking for guild", "looking for a guild", "looking for an active guild", "need a guild", "need guild",
  "want a guild", "want to join a guild", "wanting to join a guild", "any guilds", "any guild ", "guild for a", "guild for an",
  "lf a guild", "lf casual guild", "lf friendly guild", "lf active guild", "lf raiding guild", "lf leveling guild", "lf levelling guild",
  "guild that", "guild who", "guild to join", "guilds recruiting", "guilds recrutiing", "guilds looking",
}
local ASKING_LOOSE = { "^lf .*guild", "looking for .*guild", "any .*guilds?", "need .*guild", "recommend .*guild", "join .*guild" }

---Is this channel line someone asking for a guild?
function Find.IsAsking(text)
  if type(text) ~= "string" or Core.IsSecret(text) then return false end
  -- words only, each with a space before it, so "many guilds" never reads as "any guilds"
  local t = " " .. string.lower(text):gsub("[^%w<>/'%?]+", " ") .. " "
  if not t:find("guild", 1, true) then return false end
  local question = t:find(" any ", 1, true) and (t:find("?", 1, true) or t:find("recruit", 1, true))
  for _, w in ipairs(ADVERT) do
    -- "any guilds recruiting?" is a question about adverts, not one
    if t:find(w == "<" and "<" or (" " .. w), 1, true) and not question then return false end
  end
  for _, w in ipairs(ASKING) do
    if t:find(" " .. w, 1, true) then return true end
  end
  for _, p in ipairs(ASKING_LOOSE) do
    if t:find(p:sub(1, 1) == "^" and ("^ " .. p:sub(2)) or (" " .. p)) then return true end
  end
  return false
end

---A channel line. Listening never sends anything.
function Find:OnChannel(text, sender, guid, channel)
  if not M.db.listen then return end
  if Core.IsSecret(text) or Core.IsSecret(sender) or type(sender) ~= "string" then return end
  M.LearnName(sender)
  if not Find.IsAsking(text) then return end
  local name = M.Clean(sender)
  if not name or not self:Shows(name) then return end
  local class, race
  if type(guid) == "string" and not Core.IsSecret(guid) then
    local _, classFile, _, raceName = M.Global("GetPlayerInfoByGUID", guid)
    class, race = classFile, raceName
  end
  local said = text:len() > 120 and (text:sub(1, 117) .. "...") or text
  self.heard[string.lower(name)] = { name = name, class = class, race = race, text = said, channel = channel, at = M.Now(), source = "heard" }
  M.Changed()
end

---Leads heard in chat, newest first.
function Find:Heard()
  local out = {}
  for _, h in pairs(self.heard) do
    if self:Shows(h.name) then out[#out + 1] = h end
  end
  table.sort(out, function(a, b) return a.at > b.at end)
  return out
end

---Takes someone off both lists (asked, skipped or never).
function Find:Forget(name)
  local key = M.Key(name)
  if not key then return end
  self.heard[key] = nil
  for i = #self.rows, 1, -1 do
    if M.Key(self.rows[i].name) == key then table.remove(self.rows, i) end
  end
  M.Changed()
end

---Skip: hidden until you log out.
function Find:Skip(name)
  local key = M.Key(name)
  if key then self.skipped[key] = true end
  self:Forget(name)
end

---Never: kept as a person, so it lasts and other characters see it too.
function Find:Never(row)
  local p = M.People:Add(row.name, { source = row.source, class = row.class, level = row.level, zone = row.zone })
  if p then M.People:Set(p, "never", "You chose never to ask") end
  self:Forget(row.name)
end

Core:On("WHO_LIST_UPDATE", "muster.find", function() if M.db then Find:OnWhoList() end end)
Core:On("CHAT_MSG_CHANNEL", "muster.find", function(_, text, sender, _, channel, _, _, _, _, _, _, _, guid)
  if M.db then Find:OnChannel(text, sender, guid, channel) end
end)
