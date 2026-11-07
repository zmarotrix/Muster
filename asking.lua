-- Asking: whisper templates, the one whisper a click sends, and what comes back.
--
-- A template's numbers (asked, replied, joined) are counted from People rather than kept as counters, so they can't
-- drift from what actually happened.

local Core = NorgannonCore
local M = Muster
if M.disabled then return end

local Asking = {}
M.Asking = Asking

Asking.MAX_LENGTH = 255
Asking.FIELDS = "{name} {class} {level} {guild} {zone} {need}"

local DEFAULT_TEMPLATES = {
  { id = "friendly", name = "Friendly", text = "Hi {name}, no pressure: {guild} is a small, relaxed guild and we run dungeons most evenings. Want to know more?" },
  { id = "need", name = "We need you", text = "Hi {name}, {guild} is looking for {need}, and a {class} would be very welcome. Interested?" },
  { id = "asked", name = "You asked", text = "Hi {name}, saw you were looking for a guild. {guild} is small and friendly, happy to tell you more." },
}

function Asking:EnsureTemplates()
  if type(M.db.templates) ~= "table" or #M.db.templates == 0 then
    M.db.templates = {}
    for _, t in ipairs(DEFAULT_TEMPLATES) do
      M.db.templates[#M.db.templates + 1] = { id = t.id, name = t.name, text = t.text }
    end
  end
  if not self:Template(M.db.template) then M.db.template = M.db.templates[1].id end
end

function Asking:Templates() return M.db.templates end

function Asking:Template(id)
  for _, t in ipairs(M.db.templates or {}) do if t.id == id then return t end end
end

---The template Find whispers with: the chosen one, or "You asked" for someone heard asking for a guild.
function Asking:TemplateFor(source)
  if source == "heard" and self:Template("asked") then return self:Template("asked") end
  return self:Template(M.db.template) or M.db.templates[1]
end

function Asking:AddTemplate(name, text)
  local id = "t" .. M.Now() .. math.random(100, 999)
  local t = { id = id, name = name or "New", text = text or "Hi {name}, " }
  table.insert(M.db.templates, t)
  M.Changed()
  return t
end

function Asking:RemoveTemplate(id)
  if #M.db.templates <= 1 then return false end
  for i, t in ipairs(M.db.templates) do
    if t.id == id then table.remove(M.db.templates, i) break end
  end
  if M.db.template == id then M.db.template = M.db.templates[1].id end
  M.Changed()
  return true
end

---Asked, replied and joined counts for a template, from People.
function Asking:Stats(id)
  local asked, replied, joined = 0, 0, 0
  for _, p in ipairs(M.People:All()) do
    if p.template == id then
      asked = asked + 1
      if p.repliedAt then replied = replied + 1 end
      if p.joinedAt then joined = joined + 1 end
    end
  end
  return asked, replied, joined
end

---"priests and shamans": the classes marked Wanted, for {need}.
function Asking:NeedText()
  local g = M:Guild()
  local wanted = {}
  for _, c in ipairs(M.Classes()) do
    if g and g.needs[c.file] == "want" then wanted[#wanted + 1] = string.lower(c.name) .. "s" end
  end
  if #wanted == 0 then return "a few good people" end
  if #wanted == 1 then return wanted[1] end
  return table.concat(wanted, ", ", 1, #wanted - 1) .. " and " .. wanted[#wanted]
end

---The text a template becomes for one person. p: { name, class, level, zone }.
function Asking:Fill(template, p)
  local text = template and template.text or ""
  local values = {
    name = M.First(p.name) or "there",
    class = p.class and string.lower(M.ClassName(p.class)) or "player",
    level = p.level and tostring(p.level) or "",
    guild = M.Global("GetGuildInfo", "player") or "our guild",
    zone = p.zone or "",
    need = self:NeedText(),
  }
  return (text:gsub("{(%a+)}", function(field) return values[field] end))
end

---Why this text can't be sent as it is, or nil.
function Asking.CheckText(text)
  if type(text) ~= "string" or strtrim(text) == "" then return "There's nothing to send." end
  if #text > Asking.MAX_LENGTH then return string.format("That's %d characters; the game takes %d.", #text, Asking.MAX_LENGTH) end
  if text:find("{%a+}") then return "Something in {braces} isn't a field Muster knows: " .. Asking.FIELDS end
  return nil
end

-------------------------------------------------------------------------------------------
-- Sending. Only ever called from a button's OnClick.
-------------------------------------------------------------------------------------------

local pending = {}   -- lower-case target -> { person, previous state, at }

---Whispers one person with a template. who: { name, class, level, zone, race } or a person. source: "who", "heard"...
---Returns true if it went.
function Asking:Whisper(who, source, template)
  local why = M.Guards:WhyNotWhisper()
  if why then
    M:Print(why)
    return false
  end
  template = template or self:TemplateFor(source)
  local target = M.FullName(who.name)
  local text = self:Fill(template, who)
  local bad = Asking.CheckText(text)
  if bad then
    M:Print(bad)
    return false
  end
  local existing = M.People:Get(target)
  local before = existing and existing.state
  -- one ask per person: someone asked recently, who said no, or who you chose never to see, isn't asked again
  if existing and M.People:Hidden(target) then
    M:Print("You've already asked " .. existing.name .. " (" .. (M.People.STATES[existing.state] or {}).label .. ", " .. M.Ago(existing.last) .. ").")
    return false
  end
  M.Say(text, "WHISPER", target)
  M.Guards:Whispered()
  local p = M.People:Add(target, { source = source, class = who.class, level = who.level, zone = who.zone, race = who.race })
  if not p then return true end
  p.template, p.by, p.unreachable = template.id, M.Me(), nil
  if not existing then p.source = source end
  M.People:Set(p, "asked", "Asked with \"" .. (template.name or "?") .. "\"")
  pending[string.lower(target)] = { person = p, before = before, isNew = existing == nil, at = M.Clock() }
  if M.Find then M.Find:Forget(target) end
  return true
end

-------------------------------------------------------------------------------------------
-- What comes back
-------------------------------------------------------------------------------------------

-- "No player named 'X' is currently playing.": the name was wrong. Give the whisper back and say so.
local function noSuchPlayer(text)
  local pattern = M.Pattern(rawget(_G, "ERR_CHAT_PLAYER_NOT_FOUND_S") or "No player named '%s' is currently playing.")
  local name = pattern and text:match(pattern)
  if not name then return false end
  local entry = pending[string.lower(name)]
  if not entry or M.Clock() - entry.at > 15 then return false end
  pending[string.lower(name)] = nil
  M.Guards:Refund()
  local p = entry.person
  if entry.isNew then
    M.People:Forget(p)
  else
    p.state = entry.before or "found"
    M.People:Log(p, "Couldn't be reached as \"" .. name .. "\"")
  end
  p.unreachable = true
  local hint = M.HasSurname(name) and "" or " Forever needs the first and last name: /muster add First Last."
  M:Print("Nobody called " .. name .. " is online, so that whisper didn't count." .. hint)
  M.Changed()
  return true
end
Asking.NoSuchPlayer = noSuchPlayer

-- Words that suggest a whisper is about joining, for someone who wrote after an advert.
local INTEREST = { "guild", "inv", "join", "interested", "recruit", "info", "more", "details", "app" }

local function looksInterested(text)
  local t = string.lower(text)
  for _, w in ipairs(INTEREST) do if t:find(w, 1, true) then return true end end
  return false
end

---A whisper to you. Someone we asked who answers moves to Replied, or to Said no for a clear no. Someone new who
---writes about joining soon after one of your adverts becomes a person too.
function Asking:OnWhisper(text, sender)
  if Core.IsSecret(text) or Core.IsSecret(sender) or type(sender) ~= "string" then return end
  M.LearnName(sender)
  local p = M.People:Get(sender)
  local said = type(text) == "string" and text or ""
  local quote = "\"" .. (said:len() > 80 and (said:sub(1, 77) .. "...") or said) .. "\""
  if p then
    if (p.state == "asked" or p.state == "found" or p.state == "replied") and M.People.IsNo(said) then
      M.People:Set(p, "no", "Said no: " .. quote .. ". Never asked again")
    elseif p.state == "asked" or p.state == "found" then
      M.People:Set(p, "replied", "Replied: " .. quote)
    else
      M.People:Log(p, "Whispered: " .. quote)
      M.Changed()
    end
    if M.HasSurname(sender) and not M.HasSurname(p.name) then M.People:Add(sender) end
    return
  end
  if M.Adverts and M.Adverts:Recent(30 * 60) and looksInterested(said) and not Core.Guild:IsMember(sender) then
    p = M.People:Add(sender, { source = "advert" })
    if p then M.People:Set(p, "replied", "Whispered after your advert: " .. quote) end
  end
end

function Asking:OnSystem(text)
  if type(text) ~= "string" or Core.IsSecret(text) then return end
  noSuchPlayer(text)
end

Core:On("CHAT_MSG_WHISPER", "muster.asking", function(_, text, sender) if M.db then Asking:OnWhisper(text, sender) end end)
Core:On("CHAT_MSG_SYSTEM", "muster.asking", function(_, text) if M.db then Asking:OnSystem(text) end end)
for _, event in ipairs({ "CHAT_MSG_WHISPER_INFORM", "CHAT_MSG_GUILD", "CHAT_MSG_OFFICER", "CHAT_MSG_PARTY", "CHAT_MSG_PARTY_LEADER",
  "CHAT_MSG_RAID", "CHAT_MSG_RAID_LEADER", "CHAT_MSG_SAY" }) do
  Core:On(event, "muster.names", function(_, _, sender) M.LearnName(sender) end)
end
