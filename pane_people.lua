-- People: everyone Muster keeps, with a filter. The right side is one person: the next step (Invite, or Ask an
-- officer), your notes, and what happened so far.

local Core = NorgannonCore
local M = Muster
if M.disabled then return end
local UI = Core.UI
local Colors = UI.C
local Window = M.Window

local SIDE = 300

local FILTERS = {
  { key = "all", label = "Everyone" }, { key = "waiting", label = "Waiting on me" }, { key = "asked", label = "Asked" },
  { key = "joined", label = "Joined" }, { key = "no", label = "Said no" },
}
local MATCH = {
  all = function() return true end,
  waiting = function(p) return p.state == "replied" end,
  asked = function(p) return p.state == "asked" or p.state == "invited" end,
  joined = function(p) return p.state == "joined" or p.state == "left" end,
  no = function(p) return p.state == "no" or p.state == "declined" or p.state == "never" end,
}
local filter = "all"

local function stateText(p)
  local s = M.People.STATES[p.state] or M.People.STATES.found
  return Window.Tag(s.label, s.color)
end

local function selected()
  local key = Window.selected
  local g = M:Guild()
  return key and g and g.people[key]
end

local function select(p)
  Window.selected = p and p.key
  Window:Refresh()
end

local function build(f)
  f.left = CreateFrame("Frame", nil, f)
  f.left:SetPoint("TOPLEFT")
  f.left:SetPoint("BOTTOMRIGHT", -SIDE - 14, 0)
  f.filter = UI.Segmented(f.left, FILTERS, function(key)
    filter = key
    Window:Refresh()
  end, 22)
  f.filter:SetPoint("TOPLEFT")
  f.filter:Select(filter, true)
  f.pane = UI.Pane(f.left)
  f.pane:SetPoint("TOPLEFT", f.filter, "BOTTOMLEFT", 0, -8)
  f.pane:SetPoint("BOTTOMRIGHT")
  f.list = Window.RowList(f.pane, 38)
  f.list:SetPoint("TOPLEFT", 2, -2)
  f.list:SetPoint("BOTTOMRIGHT", -2, 2)
  f.empty = Window.Line(f.pane, 13)
  f.empty:SetPoint("TOPLEFT", 14, -14)
  f.empty:SetPoint("TOPRIGHT", -14, -14)

  local s = CreateFrame("Frame", nil, f)
  f.side = s
  s:SetPoint("TOPRIGHT")
  s:SetPoint("BOTTOMRIGHT")
  s:SetWidth(SIDE)
  s.name = UI.Text(s, "title", 18, Colors.text)
  s.name:SetPoint("TOPLEFT")
  s.name:SetJustifyH("LEFT")
  s.facts = Window.Line(s, 12)
  s.facts:SetPoint("TOPLEFT", s.name, "BOTTOMLEFT", 0, -4)
  s.facts:SetWidth(SIDE)
  s.act = UI.Button(s, "Invite", "primary", function()
    local p = selected()
    if not p then return end
    if Core.Guild:CanInvite() then M.Invite:Send(p, IsShiftKeyDown()) else M.Invite:AskOfficer(p) end
  end)
  s.act:SetSize(140, 24)
  s.act:SetPoint("TOPLEFT", s.facts, "BOTTOMLEFT", 0, -10)
  s.act:SetScript("OnEnter", function(self) Window.Tip(self, self.why) end)
  s.act:SetScript("OnLeave", function() GameTooltip:Hide() end)
  s.whisper = UI.Button(s, "Whisper", "quiet", function()
    local p = selected()
    if p then M.Asking:Whisper(p, p.source) end
  end)
  s.whisper:SetSize(80, 24)
  s.whisper:SetPoint("LEFT", s.act, "RIGHT", 6, 0)
  s.whisper:SetScript("OnEnter", function(self) Window.Tip(self, self.why) end)
  s.whisper:SetScript("OnLeave", function() GameTooltip:Hide() end)
  local states = {}
  for _, key in ipairs({ "found", "asked", "replied", "invited", "joined", "left", "no", "declined", "never" }) do
    states[#states + 1] = { key, "Mark: " .. M.People.STATES[key].label }
  end
  s.state = UI.Dropdown(s, states, function(key)
    local p = selected()
    if p and key ~= p.state then M.People:Set(p, key, "Marked " .. M.People.STATES[key].label .. " by hand") end
  end)
  s.state:SetSize(SIDE, 24)
  s.state:SetPoint("TOPLEFT", s.act, "BOTTOMLEFT", 0, -8)

  local hRole = Window.Heading(s, "Role")
  hRole:SetPoint("TOPLEFT", s.state, "BOTTOMLEFT", 0, -12)
  s.role = Window.Edit(s, function(text)
    local p = selected()
    if p then p.role = text end
  end)
  s.role:SetSize(SIDE, 24)
  s.role:SetPoint("TOPLEFT", hRole, "BOTTOMLEFT", 0, -4)
  local hNote = Window.Heading(s, "Notes")
  hNote:SetPoint("TOPLEFT", s.role, "BOTTOMLEFT", 0, -10)
  local noteHint = Window.Line(s, 11, Colors.faint)
  noteHint:SetPoint("LEFT", hNote, "RIGHT", 8, 0)
  noteHint:SetText("stay on this machine")
  s.note = Window.Edit(s, function(text)
    local p = selected()
    if p then p.note = text end
  end, true)
  s.note:SetSize(SIDE, 70)
  s.note:SetPoint("TOPLEFT", hNote, "BOTTOMLEFT", 0, -4)
  local hLog = Window.Heading(s, "What happened")
  hLog:SetPoint("TOPLEFT", s.note, "BOTTOMLEFT", 0, -10)
  s.log = Window.Line(s, 12, Colors.text)
  s.log:SetPoint("TOPLEFT", hLog, "BOTTOMLEFT", 0, -4)
  s.log:SetPoint("BOTTOMRIGHT", 0, 30)
  s.forget = UI.Button(s, "Forget them", "quiet", function()
    local p = selected()
    if p then
      M.People:Forget(p)
      Window.selected = nil
    end
  end)
  s.forget:SetSize(110, 20)
  s.forget:SetPoint("BOTTOMLEFT")
end

local function fillSide(f, p)
  local s = f.side
  s:SetShown(p ~= nil)
  if not p then return end
  s.name:SetText(M.Colored(p.name, p.class))
  local facts = {}
  if p.level or p.class then facts[#facts + 1] = (p.class and M.ClassName(p.class) or "Class unknown") .. (p.level and (", level " .. p.level) or "") end
  facts[#facts + 1] = stateText(p) .. " · from " .. (M.People.SOURCES[p.source] or p.source or "?") .. (p.by and (", by " .. p.by) or "")
  local t = p.template and M.Asking:Template(p.template)
  if t then facts[#facts + 1] = "Asked with \"" .. t.name .. "\"" end
  if not M.HasSurname(M.FullName(p.name)) then
    facts[#facts + 1] = Window.Tag("Only the first name is known. If a whisper fails, /muster add First Last.", "amber")
  end
  s.facts:SetText(table.concat(facts, "\n"))

  local canInvite = Core.Guild:CanInvite()
  if canInvite then
    local ok, why = M.Invite:Check(p, false)
    local okShift = M.Invite:Check(p, true)
    s.act:SetLabel(p.state == "invited" and "Invite again" or "Invite")
    s.act:SetAlpha(ok and 1 or (okShift and .7 or .4))
    s.act.why = ok and "Sends a guild invite." or why
  else
    s.act:SetLabel("Ask an officer")
    s.act:SetAlpha((p.state == "replied" or p.state == "found") and 1 or .5)
    local inviters = Core.Guild:Inviters()
    s.act.why = "Puts a line in guild chat for you to send: you can't invite on this character."
      .. (#inviters > 0 and ("\nOnline and able to invite: " .. inviters[1].name .. (#inviters > 1 and (" and " .. (#inviters - 1) .. " more") or "")) or "\nNobody who can invite is online.")
  end
  s.act:SetShown(p.state ~= "joined" and p.state ~= "no" and p.state ~= "never" and p.state ~= "left")
  local why = M.Guards:WhyNotWhisper()
  local hidden = M.People:Hidden(p.name)
  s.whisper:SetShown(p.state == "found" or (p.state == "asked" and not hidden))
  s.whisper:SetAlpha(why and .4 or 1)
  s.whisper.why = why or ("Sends, as you:\n" .. M.Asking:Fill(M.Asking:TemplateFor(p.source), p))
  s.state.value = nil
  s.state:SetValue(p.state, true)
  if not s.role.edit:HasFocus() then s.role:SetText(p.role or "") end
  if not s.note.edit:HasFocus() then s.note:SetText(p.note or "") end
  local lines = {}
  for i = #(p.log or {}), math.max(1, #(p.log or {}) - 9), -1 do
    local e = p.log[i]
    lines[#lines + 1] = Window.Tag(M.Ago(e[1]), "faint") .. "  " .. e[2]
  end
  s.log:SetText(table.concat(lines, "\n"))
end

local function fill(f)
  if not M:Guild() then
    f.list:SetData({})
    f.side:Hide()
    f.empty:SetText("Join a guild first: Muster keeps people per guild.")
    f.empty:Show()
    return
  end
  local items, chosen = {}, selected()
  local match = MATCH[filter] or MATCH.all
  for _, p in ipairs(M.People:All()) do
    if match(p) then
      local sub = {}
      if p.level then sub[#sub + 1] = "Level " .. p.level end
      if p.class then sub[#sub + 1] = M.ClassName(p.class) end
      sub[#sub + 1] = M.People.SOURCES[p.source] or p.source or ""
      if p.note and p.note ~= "" then sub[#sub + 1] = Window.Tag(p.note:sub(1, 40), "faint") end
      local item = {
        person = p,
        title = M.Colored(p.name, p.class),
        sub = table.concat(sub, " · "),
        right = stateText(p) .. "  " .. Window.Tag(M.Ago(p.last), "faint"),
        onClick = function() select(p) end,
      }
      items[#items + 1] = item
      if chosen and p == chosen then f.list:Select(item) end
    end
  end
  if not chosen and items[1] then
    chosen = items[1].person
    Window.selected = chosen.key
    f.list:Select(items[1])
  end
  f.list:SetData(items, true)
  f.empty:SetShown(#items == 0)
  f.empty:SetText(filter == "all" and "Nobody yet. People you whisper from Find, and anyone you add with /muster add First Last, are kept here." or "Nobody here.")
  fillSide(f, chosen)
end

Window:AddPane("people", { build = build, fill = fill })
