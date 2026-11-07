-- Results: what's working, counted from People. Facts only: who was asked, who answered, who joined, and who's still
-- in the guild after 7 and 30 days, read from the roster.

local M = Muster
if M.disabled then return end

local Results = {}
M.Results = Results

local DAY = 86400
Results.DAYS = 90

local function within(t, days) return t and (M.Now() - t) <= days * DAY end

---{ joined, stayed30, asked, saidNo } over the last days.
function Results:Summary(days)
  days = days or self.DAYS
  local s = { joined = 0, stayed30 = 0, asked = 0, saidNo = 0, waiting = 0 }
  for _, p in ipairs(M.People:All()) do
    if within(p.joinedAt, days) then s.joined = s.joined + 1 end
    if within(p.joinedAt, days) and p.stayed30 then s.stayed30 = s.stayed30 + 1 end
    if within(p.askedAt, days) then s.asked = s.asked + 1 end
    if p.state == "no" and within(p.last, days) then s.saidNo = s.saidNo + 1 end
    if p.state == "replied" then s.waiting = s.waiting + 1 end
  end
  return s
end

local function grouped(keyOf, labelOf)
  local rows, byKey = {}, {}
  for _, p in ipairs(M.People:All()) do
    local key = keyOf(p)
    if key then
      local r = byKey[key]
      if not r then
        r = { key = key, label = labelOf(key), asked = 0, replied = 0, joined = 0, stayed = 0 }
        byKey[key] = r
        rows[#rows + 1] = r
      end
      if p.askedAt then r.asked = r.asked + 1 end
      if p.repliedAt then r.replied = r.replied + 1 end
      if p.joinedAt then r.joined = r.joined + 1 end
      if p.stayed30 then r.stayed = r.stayed + 1 end
    end
  end
  table.sort(rows, function(a, b)
    if a.joined ~= b.joined then return a.joined > b.joined end
    return a.label < b.label
  end)
  return rows
end

---Where people came from: /who, heard in chat, an advert, by hand.
function Results:BySource()
  return grouped(function(p) return p.source end, function(k) return M.People.SOURCES[k] or k end)
end

---Which template did it.
function Results:ByTemplate()
  return grouped(function(p) return p.template end, function(k)
    local t = M.Asking:Template(k)
    return t and t.name or "A deleted template"
  end)
end

---Through whom: who invited them, else who asked them.
function Results:ByRecruiter()
  return grouped(function(p) return p.invitedBy or p.by end, function(k) return k end)
end

---Everyone who joined, newest first.
function Results:Joined()
  local out = {}
  for _, p in ipairs(M.People:All()) do
    if p.joinedAt then out[#out + 1] = p end
  end
  table.sort(out, function(a, b) return a.joinedAt > b.joinedAt end)
  return out
end

---"30 days", "7 days", "left after 4 days", "new".
function Results.Stayed(p)
  if p.state == "left" and p.leftAt and p.joinedAt then
    return "left after " .. math.max(0, math.floor((p.leftAt - p.joinedAt) / DAY)) .. " days", "warn"
  end
  if p.stayed30 then return "30 days", "good" end
  if p.stayed7 then return "7 days", "good" end
  return "new", "muted"
end
