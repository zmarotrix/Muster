-- Invites, and noticing who joined, declined, stayed and left.
--
-- Invite is for people who've answered or asked: a guild invite is a popup in the middle of someone's game. Shift-click
-- sends one anyway, one person at a time. Without the invite right, "Ask an officer" puts a line in guild chat for you
-- to send: officers' full names aren't known (the roster gives first names, and a whisper to a first name fails).
--
-- A join is noticed three ways, so one missed line doesn't lose a recruit: the game's "has joined the guild" line, the
-- roster growing (Core.Guild), and an invite followed by the person turning up in the roster.

local Core = NorgannonCore
local M = Muster
if M.disabled then return end

local Invite = {}
M.Invite = Invite

local DAY = 86400
local INVITABLE = { replied = true, found = true, asked = true, declined = true }
local WAITING = { asked = true, replied = true, invited = true, found = true, declined = true }

---Can this person be invited now? Returns ok, and why not (shift lifts "they haven't answered").
function Invite:Check(p, shift)
  if not p then return false, "Nobody chosen." end
  if not Core.Guild:CanInvite() then return false, "You can't invite on this character." end
  if p.state == "joined" then return false, "They're in the guild." end
  if p.state == "no" or p.state == "never" then return false, "They said no. Change their state by hand first." end
  if not INVITABLE[p.state] and p.state ~= "invited" then return false, "Not now." end
  if p.state == "asked" and not shift then
    return false, "They haven't answered. An invite is a popup in the middle of their game: hold Shift to send one anyway."
  end
  if p.state == "found" and p.source ~= "heard" and not shift then
    return false, "You haven't spoken yet. Hold Shift to invite them anyway."
  end
  return true
end

---Sends a guild invite. Only ever called from a click.
function Invite:Send(p, shift)
  local ok, why = self:Check(p, shift)
  if not ok then
    M:Print(why)
    return false
  end
  local target = M.FullName(p.name)
  if M.Has("C_GuildInfo", "Invite") then
    C_GuildInfo.Invite(target)
  else
    GuildInvite(target)
  end
  M.People:Set(p, "invited", "Invited by " .. (M.Me() or "you"))
  p.invitedBy = M.Me()
  return true
end

---The line Ask an officer puts in guild chat.
function Invite:OfficerLine(p)
  local name = M.FullName(p.name)
  local inviters = Core.Guild:Inviters()
  local to = inviters[1] and (inviters[1].name .. ", or ") or ""
  return string.format("%sanyone who can invite: could you invite %s? They'd like to join.", to, name)
end

---Ask an officer: opens guild chat with the line ready. You press Enter to send it.
function Invite:AskOfficer(p)
  if not p then return end
  local line = self:OfficerLine(p)
  local opener = rawget(_G, "ChatFrame_OpenChat")
  if opener then
    opener("/g " .. line)
  else
    M:Print(line)
  end
  M.People:Log(p, "Passed on to an officer")
  M.Changed()
end

-------------------------------------------------------------------------------------------
-- The game's lines
-------------------------------------------------------------------------------------------

local LINES = {
  { "ERR_GUILD_JOIN_S", "%s has joined the guild.", "joined" },
  { "ERR_GUILD_DECLINE_S", "%s declines your guild invitation.", "declined" },
  { "ERR_ALREADY_IN_GUILD_S", "%s is already in a guild.", "inguild" },
  { "ERR_GUILD_LEAVE_S", "%s has left the guild.", "left" },
  { "ERR_GUILD_REMOVE_SS", "%s has been kicked out of the guild by %s.", "left" },
  { "ERR_GUILD_INVITE_S", "You have invited %s to join your guild.", "invited" },
}

local patterns
local function linePatterns()
  if not patterns then
    patterns = {}
    for _, l in ipairs(LINES) do
      local p = M.Pattern(rawget(_G, l[1]) or l[2])
      if p then patterns[#patterns + 1] = { p, l[3] } end
    end
  end
  return patterns
end

local function recruited(p, how)
  if p.state == "joined" then return end
  M.People:Set(p, "joined", how)
  Core:Send("NORGANNON_GUILD_RECRUITED", p.name, p.source, p.invitedBy or p.by, p.joinedAt)
end

function Invite:OnSystem(text)
  if type(text) ~= "string" or Core.IsSecret(text) then return end
  for _, entry in ipairs(linePatterns()) do
    local name = text:match(entry[1])
    if name then
      local kind = entry[2]
      if kind == "joined" then
        local p = M.People:Matching(name, WAITING)
        if p then recruited(p, "Joined the guild") end
      elseif kind == "declined" then
        local p = M.People:Matching(name, { invited = true })
        if p then M.People:Set(p, "declined", "Declined the invite") end
      elseif kind == "inguild" then
        local p = M.People:Matching(name, { invited = true })
        if p then M.People:Set(p, "never", "Already in a guild") end
      elseif kind == "left" then
        local p = M.People:Matching(name, { joined = true })
        if p then M.People:Set(p, "left", "Left the guild") end
      end
      return
    end
  end
end

-------------------------------------------------------------------------------------------
-- The roster: joins the lines missed, leaves, and who's still here after 7 and 30 days
-------------------------------------------------------------------------------------------

function Invite:OnRoster(joined, left)
  if not M:Guild() then return end
  for _, first in ipairs(joined or {}) do
    local p = M.People:Matching(first, WAITING)
    if p and (p.state == "invited" or p.state == "replied") then recruited(p, "Joined the guild (seen in the roster)") end
  end
  for _, first in ipairs(left or {}) do
    local p = M.People:Matching(first, { joined = true })
    if p then M.People:Set(p, "left", "Left the guild (seen in the roster)") end
  end
  -- invited, and in the roster now: they joined while the line went past unseen
  for _, p in ipairs(M.People:All()) do
    if p.state == "invited" and Core.Guild:IsMember(M.First(p.name)) and #M.People:ByFirst(p.first, { invited = true }) == 1 then
      recruited(p, "Joined the guild (seen in the roster)")
    end
  end
  self:Retention()
end

---Marks recruits still in the guild at 7 and 30 days. Read only from the roster, so nothing is assumed.
function Invite:Retention()
  if not Core.Guild:Known() then return end
  local now = M.Now()
  for _, p in ipairs(M.People:All()) do
    if p.state == "joined" and p.joinedAt and Core.Guild:IsMember(M.First(p.name)) then
      if not p.stayed7 and now - p.joinedAt >= 7 * DAY then
        p.stayed7 = true
        M.People:Log(p, "Still here after 7 days")
      end
      if not p.stayed30 and now - p.joinedAt >= 30 * DAY then
        p.stayed30 = true
        M.People:Log(p, "Still here after 30 days")
      end
    end
  end
end

Core:On("CHAT_MSG_SYSTEM", "muster.invite", function(_, text) if M.db then Invite:OnSystem(text) end end)
Core:Listen("NORGANNON_GUILD_ROSTER", "muster.invite", function(_, _, joined, left) if M.db then Invite:OnRoster(joined, left) M.Changed() end end)
