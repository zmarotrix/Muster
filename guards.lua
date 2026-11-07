-- The limits, in one place (docs/muster-v1.md section 4). Every send asks here first and tells here after.
--
--   whispers   one at a time, at least 15 seconds apart, at most 20 an hour (a setting, never above 40)
--   adverts    one per channel every 15 minutes (longer only)
--   muted      if the game has muted or squelched you, nothing is sent, and Muster says why
--
-- The hour is a rolling hour, per character: the game mutes a character, not an account.

local M = Muster
if M.disabled then return end

local Guards = {}
M.Guards = Guards

local HOUR = 3600

local function sent()
  local mine = M:Mine()
  local now = M.Now()
  local keep = {}
  for _, t in ipairs(mine.sent) do
    if now - t < HOUR then keep[#keep + 1] = t end
  end
  mine.sent = keep
  return keep
end

function Guards.PerHour()
  return math.max(1, math.min(M.HOUR_CEILING, math.floor(M.db.perHour or 20)))
end

function Guards.Gap()
  return math.max(M.MIN_GAP, M.db.gap or M.MIN_GAP)
end

function Guards.AdvertSeconds()
  return math.max(M.MIN_ADVERT_MINUTES, M.db.advertMinutes or M.MIN_ADVERT_MINUTES) * 60
end

---Why chat can't go out at all right now, or nil.
function Guards:Muted()
  if M.In("C_SocialRestrictions", "IsSquelched") then return "The game has squelched your chat, so nothing can be sent." end
  if M.In("C_SocialRestrictions", "IsMuted") then return "The game has muted your chat, so nothing can be sent." end
  if M.In("C_SocialRestrictions", "IsSilenced") then return "The game has silenced you, so nothing can be sent." end
  if M.Has("C_SocialRestrictions", "CanSendChat") and M.In("C_SocialRestrictions", "CanSendChat") == false then
    return "The game isn't letting you chat right now."
  end
  if M.In("C_ChatInfo", "InChatMessagingLockdown") then return "Chat is locked during this fight. Try again after it." end
  return nil
end

---Seconds until the next whisper may go, 0 if now.
function Guards:WhisperWait()
  local list = sent()
  local last = list[#list]
  local wait = last and (last + self.Gap() - M.Now()) or 0
  if #list >= self.PerHour() then
    wait = math.max(wait, list[#list - self.PerHour() + 1] + HOUR - M.Now())
  end
  return math.max(0, wait)
end

---Why a whisper can't go now, or nil.
function Guards:WhyNotWhisper()
  local muted = self:Muted()
  if muted then return muted end
  local list = sent()
  if #list >= self.PerHour() then
    local mins = math.ceil(self:WhisperWait() / 60)
    return string.format("That's %d this hour, Muster's limit. The next in %d min.", self.PerHour(), mins)
  end
  local wait = self:WhisperWait()
  if wait > 0 then return string.format("Next whisper in %d s.", math.ceil(wait)) end
  return nil
end

function Guards:CountHour() return #sent() end
function Guards:HourText() return string.format("%d of %d this hour", #sent(), self.PerHour()) end

---Notes a whisper as sent, so the gap and the hour count it.
function Guards:Whispered()
  local mine = M:Mine()
  mine.sent[#mine.sent + 1] = M.Now()
end

---Gives back one whisper the game said didn't arrive ("No player named"), so a wrong name doesn't use up the hour.
function Guards:Refund()
  local mine = M:Mine()
  table.remove(mine.sent)
end

---Why an advert can't go to this channel now, or nil.
function Guards:WhyNotAdvert(channel)
  local muted = self:Muted()
  if muted then return muted end
  local g = M:Guild()
  local last = g and g.adverts.posted[string.lower(channel or "")]
  if last then
    local wait = last + self.AdvertSeconds() - M.Now()
    if wait > 0 then return string.format("Again in %d:%02d. One per %d minutes in each channel.", math.floor(wait / 60), wait % 60, self.AdvertSeconds() / 60) end
  end
  return nil
end

function Guards:Advertised(channel)
  local g = M:Guild()
  if g then g.adverts.posted[string.lower(channel or "")] = M.Now() end
end

---Did the last few whispers get answers? Returns the number of whispers in a row with no reply, from the latest.
function Guards:Unanswered()
  local asked = {}
  for _, p in ipairs(M.People:All()) do
    if p.askedAt and p.by == M.Me() then asked[#asked + 1] = p end
  end
  table.sort(asked, function(a, b) return a.askedAt > b.askedAt end)
  local n = 0
  for _, p in ipairs(asked) do
    if p.repliedAt or p.state ~= "asked" then break end
    n = n + 1
  end
  return n
end
