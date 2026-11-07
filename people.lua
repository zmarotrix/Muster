-- People: everyone Muster has asked, heard from or been told about, per guild, with a state and a short history.
--
-- States, in the order a good recruit goes through them:
--   found     added by hand, not asked yet
--   asked     whispered once; hidden from Find until reaskDays have passed
--   replied   they answered and haven't said no: waiting on you
--   invited   a guild invite went out
--   joined    they're in the guild (from the game's line or the roster)
--   left      they joined and later left
--   no        a clear no: never asked again (undo by hand)
--   declined  turned an invite down
--   never     you chose never to see them

local Core = NorgannonCore
local M = Muster
if M.disabled then return end

local People = {}
M.People = People

People.STATES = {
  found = { label = "Found", color = "muted" },
  asked = { label = "Asked", color = "amber" },
  replied = { label = "Replied", color = "accent" },
  invited = { label = "Invited", color = "amber" },
  joined = { label = "Joined", color = "good" },
  left = { label = "Left", color = "warn" },
  no = { label = "Said no", color = "warn" },
  declined = { label = "Declined", color = "warn" },
  never = { label = "Never", color = "muted" },
}
-- States that keep a person out of Find. "asked" is only for reaskDays.
local HIDDEN = { replied = true, invited = true, joined = true, left = true, no = true, declined = true, never = true }

People.SOURCES = { who = "/who", heard = "Heard in chat", advert = "After an advert", whispered = "Whispered you", added = "Added by hand", roster = "Guild roster" }

local LOG_SIZE = 30

local function store()
  local g = M:Guild()
  return g and g.people
end

---Every person kept for this guild, newest activity first.
function People:All()
  local out = {}
  for _, p in pairs(store() or {}) do out[#out + 1] = p end
  table.sort(out, function(a, b) return (a.last or 0) > (b.last or 0) end)
  return out
end

---The person with this name: by full name, or by first name when only one person has it.
function People:Get(name)
  local list = store()
  local key = M.Key(name)
  if not list or not key then return nil end
  if list[key] then return list[key] end
  local first = string.lower(M.First(name))
  local found
  for k, p in pairs(list) do
    if k == first or string.lower(p.first or "") == first then
      -- "Elowen" can be found from "Elowen Brightwater" and the other way round, but two Elowens are two people
      if M.HasSurname(name) and M.HasSurname(p.name) then
        -- both full and different: not the same person
      else
        if found then return nil end
        found = p
      end
    end
  end
  return found
end

---Adds someone, or brings what we know up to date. info: { source, class, level, race, zone, by, state }. A fuller
---name than the one kept replaces it, so a /who row with a first name and a whisper with both end up as one person.
function People:Add(name, info)
  local list = store()
  name = M.Clean(name)
  if not list or not name then return nil end
  info = info or {}
  local p = self:Get(name)
  if p and M.HasSurname(name) and not M.HasSurname(p.name) then
    list[p.key] = nil
    p.key, p.name = M.Key(name), name
    list[p.key] = p
  end
  if not p then
    local now = M.Now()
    p = { key = M.Key(name), name = name, first = M.First(name), state = info.state or "found", source = info.source or "added",
      by = info.by or M.Me(), seen = now, last = now, log = {} }
    list[p.key] = p
    self:Log(p, "Found: " .. (People.SOURCES[p.source] or p.source))
  end
  p.first = M.First(p.name)
  for _, field in ipairs({ "class", "level", "race", "zone" }) do
    if info[field] ~= nil then p[field] = info[field] end
  end
  M.LearnName(name)
  M.Changed()
  return p
end

function People:Log(p, text)
  p.log = p.log or {}
  p.log[#p.log + 1] = { M.Now(), text }
  while #p.log > LOG_SIZE do table.remove(p.log, 1) end
  p.last = M.Now()
end

---Moves someone to a state, with a line for their history.
function People:Set(p, state, text)
  if not p or not People.STATES[state] then return end
  p.state = state
  p.last = M.Now()
  if state == "asked" then p.askedAt = p.last end
  if state == "replied" then p.repliedAt = p.last end
  if state == "invited" then p.invitedAt = p.last end
  if state == "joined" then p.joinedAt, p.leftAt = p.last, nil end
  if state == "left" then p.leftAt = p.last end
  self:Log(p, text or People.STATES[state].label)
  M.Changed()
end

function People:Forget(p)
  local list = store()
  if list and p then list[p.key] = nil end
  M.Changed()
end

---Is this person kept out of Find? Returns hidden, and for someone asked long enough ago, the time they were asked.
function People:Hidden(name)
  local p = self:Get(name)
  if not p then return false end
  if HIDDEN[p.state] then return true end
  if p.state == "asked" then
    local days = (M.Now() - (p.askedAt or 0)) / 86400
    if days < (M.db.reaskDays or 90) then return true end
    return false, p.askedAt
  end
  return false
end

---People waiting on you: they replied and you haven't invited them yet.
function People:CountWaiting()
  local n = 0
  for _, p in pairs(store() or {}) do if p.state == "replied" then n = n + 1 end end
  return n
end

---Everyone with this first name who's in one of the given states.
function People:ByFirst(first, states)
  local out = {}
  first = first and string.lower(first)
  for _, p in pairs(store() or {}) do
    if string.lower(p.first or "") == first and (not states or states[p.state]) then out[#out + 1] = p end
  end
  return out
end

---The person we asked or invited by this name, when the game only gives a first name (the roster, system lines).
function People:Matching(name, states)
  local p = self:Get(name)
  if p and (not states or states[p.state]) then return p end
  local list = self:ByFirst(M.First(name), states)
  if #list == 1 then return list[1] end
  return nil
end

---A clear no, in a reply to us. Kept deliberately narrow: a short message that's only a refusal, or a phrase nobody
---uses to say yes. "no idea what that is, tell me more" isn't a no.
local WHOLE = { ["no"] = true, ["nope"] = true, ["nah"] = true, ["no ty"] = true, ["nty"] = true, ["no thx"] = true, ["stop"] = true,
  ["pass"] = true, ["im good"] = true, ["i'm good"] = true, ["i am good"] = true, ["not interested"] = true, ["no thanks"] = true,
  ["no thank you"] = true, ["no sorry"] = true, ["sorry no"] = true }
local PHRASES = { "not interested", "no thanks", "no thank you", "no, thanks", "no, thank you", "stop whispering", "stop messaging",
  "don't whisper", "dont whisper", "leave me alone", "not looking for a guild", "already have a guild", "already in a guild",
  "do not whisper", "stop spamming", "not looking" }

function People.IsNo(text)
  if type(text) ~= "string" or Core.IsSecret(text) then return false end
  local t = string.lower(text):gsub("[%.!,%s]+$", ""):gsub("^%s+", "")
  if WHOLE[t] then return true end
  for _, phrase in ipairs(PHRASES) do
    if t:find(phrase, 1, true) then return true end
  end
  return false
end
