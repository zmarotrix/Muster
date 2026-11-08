-- Find: Heard in chat on top (they asked, so start there), then Around now: one /who per press of Next (the levels in
-- bands), or per search you type. The right side picks the message, lets you edit it in place, shows exactly what
-- they'll read, and says where the limits stand.

local Core = NorgannonCore
local M = Muster
if M.disabled then return end
local UI = Core.UI
local Colors = UI.C
local Window = M.Window

local SIDE = 270

local function needTag(class)
  local need = M.Find.NeedOf(class)
  if need == "want" then return " " .. Window.Tag("wanted", "accent") end
  if need == "full" then return " " .. Window.Tag("full", "faint") end
  return ""
end

local function whoLine(r)
  local bits = {}
  if r.level then bits[#bits + 1] = "Level " .. r.level end
  if r.class then bits[#bits + 1] = M.ClassName(r.class) end
  if r.zone and r.zone ~= "" then bits[#bits + 1] = r.zone end
  return table.concat(bits, " · ")
end

local preview

local function rowFor(r)
  local template = M.Asking:TemplateFor(r.source)
  local why = M.Guards:WhyNotWhisper()
  local text = M.Asking:Fill(template, r)
  local sub
  if r.source == "heard" then
    sub = Window.Tag("\"" .. r.text .. "\"", "accent") .. "  " .. M.Ago(r.at)
  else
    sub = whoLine(r)
    if r.askedAt then sub = sub .. "  " .. Window.Tag("asked " .. M.Ago(r.askedAt) .. ", once more is fine", "amber") end
  end
  if not M.HasSurname(r.name) and not M.HasSurname(M.FullName(r.name)) then
    sub = sub .. "  " .. Window.Tag("first name only: a whisper may not reach them", "warn")
  end
  return {
    title = M.Colored(r.name, r.class) .. needTag(r.class),
    sub = sub,
    tip = text,
    onClick = function() preview = r Window:Refresh() end,
    actions = {
      { text = "Never", width = 56, tip = "Never show them again, on any character.", run = function() M.Find:Never(r) end },
      { text = "Skip", width = 50, tip = "Hide them until you log out.", run = function() M.Find:Skip(r.name) end },
      { text = "Whisper", width = 74, off = why ~= nil, tip = why or ("Sends, as you:\n" .. text), run = function()
        M.Asking:Whisper(r, r.source, template)
      end },
    },
  }
end

local function build(f)
  -- the list, left: Next and a search on top, your recent searches, then what came back
  f.left = CreateFrame("Frame", nil, f)
  f.left:SetPoint("TOPLEFT")
  f.left:SetPoint("BOTTOMRIGHT", -SIDE - 14, 0)
  f.next = UI.Button(f.left, "Next", "primary", function() M.Find:Next() end)
  f.next:SetSize(150, 26)
  f.next:SetPoint("TOPLEFT", 0, -1)
  f.go = UI.Button(f.left, "Search", "accent", function() M.Find:Search(f.search:GetText()) end)
  f.go:SetSize(64, 26)
  f.go:SetPoint("TOPRIGHT", 0, -1)
  f.search = UI.Search(f.left, "priest 40-50, a zone, a name...", nil, function(text) M.Find:Search(text) end)
  f.search:SetPoint("TOPLEFT", f.next, "TOPRIGHT", 8, 0)
  f.search:SetPoint("TOPRIGHT", f.go, "TOPLEFT", -6, 0)
  f.search:SetScript("OnEnter", function(self)
    Window.Tip(self, "One /who with your own words: a class, a level or a range, a zone, a name. Class names become the game's "
      .. "class filter, so \"priest 40-50\" means priests from 40 to 50. The game's own filters (z-\"Duskwood\") work too. Enter sends it.")
  end)
  f.search:SetScript("OnLeave", function() GameTooltip:Hide() end)
  f.recent = {}
  f.recentLabel = Window.Line(f.left, 11, Colors.faint)
  f.recentLabel:SetPoint("TOPLEFT", 0, -36)
  f.recentLabel:SetText("Recent:")
  f.status = Window.Line(f.left, 12)
  f.status:SetPoint("TOPLEFT", f.left, "TOPLEFT", 0, -60)
  f.status:SetPoint("TOPRIGHT", f.left, "TOPRIGHT", 0, -60)
  f.notice = Window.Line(f.left, 12, Colors.text)
  f.notice:SetPoint("TOPLEFT", f.left, "TOPLEFT", 0, -78)
  f.notice:SetPoint("TOPRIGHT", f.left, "TOPRIGHT", 0, -78)
  f.pane = UI.Pane(f.left)
  f.pane:SetPoint("TOPLEFT", f.left, "TOPLEFT", 0, -98)
  f.pane:SetPoint("BOTTOMRIGHT")
  f.list = Window.RowList(f.pane, 40)
  f.list:SetPoint("TOPLEFT", 2, -2)
  f.list:SetPoint("BOTTOMRIGHT", -2, 2)
  f.empty = Window.Line(f.pane, 13)
  f.empty:SetPoint("TOPLEFT", 14, -14)
  f.empty:SetPoint("TOPRIGHT", -14, -14)

  -- the side: which message, the message itself (edit it right here), what they'll read, the limits
  f.side = CreateFrame("Frame", nil, f)
  f.side:SetPoint("TOPRIGHT")
  f.side:SetPoint("BOTTOMRIGHT")
  f.side:SetWidth(SIDE)
  local h1 = Window.Heading(f.side, "Whisper with")
  h1:SetPoint("TOPLEFT")
  f.template = UI.Dropdown(f.side, {}, function(id)
    M.db.template = id
    Window:Refresh()
  end)
  f.template:SetPoint("TOPLEFT", h1, "BOTTOMLEFT", 0, -6)
  f.template:SetWidth(SIDE)
  f.stats = Window.Line(f.side, 12)
  f.stats:SetPoint("TOPLEFT", f.template, "BOTTOMLEFT", 0, -4)
  f.stats:SetWidth(SIDE)
  local h2 = Window.Heading(f.side, "Message")
  h2:SetPoint("TOPLEFT", f.stats, "BOTTOMLEFT", 0, -12)
  f.more = UI.Button(f.side, "All messages", "quiet", function() Window:Open("asking") end)
  f.more:SetSize(96, 18)
  f.more:SetPoint("TOPRIGHT", f.stats, "BOTTOMRIGHT", 0, -10)
  f.message = Window.Edit(f.side, function(text)
    local t = M.Asking:Template(M.db.template)
    if t then
      t.text = text
      Window:Refresh()
    end
  end, true)
  f.message:SetSize(SIDE, 84)
  f.message:SetPoint("TOPLEFT", h2, "BOTTOMLEFT", 0, -6)
  f.fields = Window.Line(f.side, 11, Colors.faint)
  f.fields:SetPoint("TOPLEFT", f.message, "BOTTOMLEFT", 0, -3)
  f.fields:SetWidth(SIDE)
  f.fields:SetText(M.Asking.FIELDS)
  local h3 = Window.Heading(f.side, "What they'll read")
  h3:SetPoint("TOPLEFT", f.fields, "BOTTOMLEFT", 0, -12)
  f.preview = Window.Line(f.side, 13, Colors.text)
  f.preview:SetPoint("TOPLEFT", h3, "BOTTOMLEFT", 0, -6)
  f.preview:SetWidth(SIDE)
  local h4 = Window.Heading(f.side, "Limits")
  h4:SetPoint("TOPLEFT", f.preview, "BOTTOMLEFT", 0, -16)
  f.limits = Window.Line(f.side, 12)
  f.limits:SetPoint("TOPLEFT", h4, "BOTTOMLEFT", 0, -6)
  f.limits:SetWidth(SIDE)
end

local function tick(f)
  local band = M.Find:NextBand()
  local wait = M.Find:Wait()
  local busy = wait > 0 or M.Find.waiting
  f.next:SetLabel(wait > 0 and ("Next in " .. wait .. " s") or ("Next: levels " .. M.Find.BandText(band)))
  f.next:SetAlpha(busy and .5 or 1)
  f.go:SetAlpha(busy and .5 or 1)
  local why = M.Guards:WhyNotWhisper()
  f.limits:SetText((why and (why .. "\n") or "Ready.\n") .. M.Guards:HourText() .. ", at least " .. M.Guards.Gap() .. " s apart.")
end

-- Your recent searches, as small buttons: one click asks again.
local function fillRecent(f)
  local recent = M.Find:Recent()
  f.recentLabel:SetShown(#recent > 0)
  local previous = f.recentLabel
  for i = 1, math.max(#recent, #f.recent) do
    local text = recent[i]
    local b = f.recent[i]
    if text and not b then
      b = UI.Button(f.left, "", "quiet", function(self) M.Find:Search(self.query) end)
      b:SetHeight(18)
      f.recent[i] = b
    end
    if b then
      b:SetShown(text ~= nil)
      if text then
        b.query = text
        local label = #text > 18 and (text:sub(1, 17) .. "...") or text
        b:SetLabel(label)
        b:SetWidth(math.min(130, #label * 6 + 18))
        b:ClearAllPoints()
        b:SetPoint("LEFT", previous, "RIGHT", 6, 0)
        previous = b
      end
    end
  end
end

local function fill(f)
  if not M:Guild() then
    f.list:SetData({})
    f.empty:SetText("Join a guild first: Muster recruits for the guild you're in.")
    f.empty:Show()
    return
  end
  local F = M.Find
  -- the message picker, and the message itself
  local options = {}
  for _, t in ipairs(M.Asking:Templates()) do options[#options + 1] = { t.id, t.name } end
  f.template.options = options
  f.template.value = nil
  f.template:SetValue(M.db.template, true)
  local t = M.Asking:Template(M.db.template)
  local asked, replied, joined = M.Asking:Stats(M.db.template)
  f.stats:SetText(string.format("%d asked, %d replied, %d joined", asked, replied, joined))
  if t and not f.message.edit:HasFocus() then f.message:SetText(t.text) end
  -- the person you clicked, else the first /who row, else someone made up: never a chat lead you didn't pick, who'd
  -- get "You asked" and make the preview look unlike the message you're editing
  local sample = preview or F.rows[1] or { name = "Elowen", class = "PRIEST", level = 31 }
  local used = M.Asking:TemplateFor(sample.source) or t
  local text = M.Asking:Fill(used, sample)
  local bad = M.Asking.CheckText(text)
  local who = "For " .. M.First(sample.name)
  if used ~= t then who = who .. ", who asked for a guild: they get \"" .. used.name .. "\"" end
  f.preview:SetText(Window.Tag(who, "faint") .. "\n" .. text .. (bad and ("\n" .. Window.Tag(bad, "warn")) or ""))
  fillRecent(f)

  -- status of the last /who
  if F.waiting then
    f.status:SetText("Asking the server...")
  elseif F.refused then
    f.status:SetText(Window.Tag("No answer. The server may limit how often /who works; try again in a moment.", "amber"))
  elseif F.asking then
    local label = F.asking.text:gsub("^%l", string.upper)
    local txt = string.format("%s: %d online, %d in guilds hidden.", label, F.total or 0, F.hidden or 0)
    if F.cut then
      txt = txt .. " " .. Window.Tag(F.asking.band and "More than the server lists: that band is split in two next time."
        or "More than the server lists: narrow the search to see the rest.", "amber")
    end
    f.status:SetText(txt)
  else
    f.status:SetText("Next walks the levels a band at a time. Or search for exactly who you want.")
  end

  local notice = M.Guards:Muted()
  local quiet = M.Guards:Unanswered()
  if not notice and quiet >= 20 then
    notice = Window.Tag("Your last " .. quiet .. " whispers got no answer. A different message might do better.", "amber")
  end
  f.notice:SetText(notice or ("Levels under " .. (M.db.minLevel or 10) .. ", people in guilds and anyone already asked are hidden."))

  local items = {}
  local heard = F:Heard()
  if #heard > 0 then
    items[#items + 1] = { group = "Heard in chat: they asked, so start here" }
    for _, h in ipairs(heard) do items[#items + 1] = rowFor(h) end
  end
  if #F.rows > 0 then
    items[#items + 1] = { group = "Around now: " .. F.asking.text }
    for _, r in ipairs(F.rows) do items[#items + 1] = rowFor(r) end
  end
  f.list:SetData(items)
  if #items == 0 then
    f.empty:SetText(F.asking and "Nobody new here. Press Next for the next levels, or search for someone else."
      or "Press Next to ask the game who's around, or search for exactly who you want.\n\nPeople asking for a guild in channels you're in show up here by themselves (not during boss fights).")
    f.empty:Show()
  else
    f.empty:Hide()
  end
  tick(f)
end

Window:AddPane("find", { build = build, fill = fill, tick = tick })
