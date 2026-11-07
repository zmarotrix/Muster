-- Adverts: a few lines of your own, posted by a button to a channel you're already in, at most once per channel every
-- 15 minutes. Muster never joins a channel for you, never posts to the newcomers' channel, and nothing posts by itself.

local M = Muster
if M.disabled then return end

local Adverts = {}
M.Adverts = Adverts

-- Channels an advert never goes to: defence alerts, and the channel for new players, who are often not ready for a guild
-- and are the ones most put off by recruiters.
local NEVER = { localdefense = true, worlddefense = true, newcomers = true, newcomerchat = true, ["newcomer chat"] = true }

function Adverts:Lines()
  local g = M:Guild()
  if not g then return {} end
  if #g.adverts.lines == 0 then
    g.adverts.lines[1] = (M.Global("GetGuildInfo", "player") or "Our guild") .. " is a small, relaxed guild running dungeons most evenings. Whisper me for a chat."
  end
  return g.adverts.lines
end

function Adverts:SetLine(i, text)
  local lines = self:Lines()
  if text and strtrim(text) ~= "" then lines[i] = strtrim(text) else table.remove(lines, i) end
  M.Changed()
end

---Channels you're in that an advert may go to: { { id, name } }.
function Adverts:Channels()
  local out = {}
  local list = { M.Global("GetChannelList") }
  for i = 1, #list, 3 do
    local id, name, disabled = list[i], list[i + 1], list[i + 2]
    if type(id) == "number" and type(name) == "string" and not disabled then
      local base = string.lower(name):gsub("%s*%-.*$", "")
      if not NEVER[base] and not NEVER[string.lower(name)] then out[#out + 1] = { id = id, name = name } end
    end
  end
  return out
end

---Posts an advert line to a channel. Only ever called from a click.
function Adverts:Post(line, channel)
  if not channel or not line then return false end
  local why = M.Guards:WhyNotAdvert(channel.name)
  if why then
    M:Print(why)
    return false
  end
  local bad = M.Asking.CheckText(line)
  if bad then
    M:Print(bad)
    return false
  end
  M.Say(line, "CHANNEL", channel.id)
  M.Guards:Advertised(channel.name)
  self.lastPost = M.Now()
  M.Changed()
  return true
end

---Was an advert posted within the last seconds? Whispers soon after one count as answers to it.
function Adverts:Recent(seconds)
  local g = M:Guild()
  if not g then return false end
  local now = M.Now()
  for _, t in pairs(g.adverts.posted) do
    if now - t <= seconds then return true end
  end
  return false
end
