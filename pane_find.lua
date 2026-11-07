-- Find: Heard in chat on top (they asked, so start there), then Around now from one /who per press of Next.
-- The right side picks the template, shows exactly what they'll read, and says where the limits stand.

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
  -- the list, left
  f.left = CreateFrame("Frame", nil, f)
  f.left:SetPoint("TOPLEFT")
  f.left:SetPoint("BOTTOMRIGHT", -SIDE - 14, 0)
  f.next = UI.Button(f.left, "Next", "primary", function() M.Find:Next() end)
  f.next:SetSize(170, 24)
  f.next:SetPoint("TOPLEFT")
  f.status = Window.Line(f.left, 12)
  f.status:SetPoint("LEFT", f.next, "RIGHT", 10, 0)
  f.status:SetPoint("RIGHT", f.left, "RIGHT")
  f.notice = Window.Line(f.left, 12, Colors.text)
  f.notice:SetPoint("TOPLEFT", f.left, "TOPLEFT", 0, -32)
  f.notice:SetPoint("TOPRIGHT", f.left, "TOPRIGHT", 0, -32)
  f.pane = UI.Pane(f.left)
  f.pane:SetPoint("TOPLEFT", f.notice, "BOTTOMLEFT", 0, -6)
  f.pane:SetPoint("BOTTOMRIGHT")
  f.list = Window.RowList(f.pane, 40)
  f.list:SetPoint("TOPLEFT", 2, -2)
  f.list:SetPoint("BOTTOMRIGHT", -2, 2)
  f.empty = Window.Line(f.pane, 13)
  f.empty:SetPoint("TOPLEFT", 14, -14)
  f.empty:SetPoint("TOPRIGHT", -14, -14)

  -- the side
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
  local h2 = Window.Heading(f.side, "What they'll read")
  h2:SetPoint("TOPLEFT", f.stats, "BOTTOMLEFT", 0, -14)
  f.preview = Window.Line(f.side, 13, Colors.text)
  f.preview:SetPoint("TOPLEFT", h2, "BOTTOMLEFT", 0, -6)
  f.preview:SetWidth(SIDE)
  local h3 = Window.Heading(f.side, "Limits")
  h3:SetPoint("TOPLEFT", f.preview, "BOTTOMLEFT", 0, -16)
  f.limits = Window.Line(f.side, 12)
  f.limits:SetPoint("TOPLEFT", h3, "BOTTOMLEFT", 0, -6)
  f.limits:SetWidth(SIDE)
end

local function tick(f)
  local band = M.Find:NextBand()
  local wait = M.Find:Wait()
  f.next:SetLabel(wait > 0 and ("Next in " .. wait .. " s") or ("Next: levels " .. M.Find.BandText(band)))
  f.next:SetAlpha((wait > 0 or M.Find.waiting) and .5 or 1)
  local why = M.Guards:WhyNotWhisper()
  f.limits:SetText((why and (why .. "\n") or "Ready.\n") .. M.Guards:HourText() .. ", at least " .. M.Guards.Gap() .. " s apart.")
end

local function fill(f)
  if not M:Guild() then
    f.list:SetData({})
    f.empty:SetText("Join a guild first: Muster recruits for the guild you're in.")
    f.empty:Show()
    return
  end
  local F = M.Find
  -- the template picker
  local options = {}
  for _, t in ipairs(M.Asking:Templates()) do options[#options + 1] = { t.id, t.name } end
  f.template.options = options
  f.template.value = nil
  f.template:SetValue(M.db.template, true)
  local t = M.Asking:Template(M.db.template)
  local asked, replied, joined = M.Asking:Stats(M.db.template)
  f.stats:SetText(string.format("%d asked, %d replied, %d joined", asked, replied, joined))
  local sample = preview or F.rows[1] or F:Heard()[1] or { name = "Elowen", class = "PRIEST", level = 31 }
  f.preview:SetText(M.Asking:Fill(M.Asking:TemplateFor(sample.source) or t, sample))

  -- status of the last /who
  if F.waiting then
    f.status:SetText("Asking the server...")
  elseif F.refused then
    f.status:SetText(Window.Tag("No answer. The server may limit how often /who works; try again in a moment.", "amber"))
  elseif F.asking then
    local txt = string.format("Levels %s: %d online, %d in guilds hidden.", M.Find.BandText(F.asking), F.total or 0, F.hidden or 0)
    if F.cut then txt = txt .. " " .. Window.Tag("More than the server lists: that band is split in two next time.", "amber") end
    f.status:SetText(txt)
  else
    f.status:SetText("One press is one question to the server.")
  end

  local notice = M.Guards:Muted()
  local quiet = M.Guards:Unanswered()
  if not notice and quiet >= 20 then
    notice = Window.Tag("Your last " .. quiet .. " whispers got no answer. A different template might do better.", "amber")
  end
  f.notice:SetText(notice or ("Levels under " .. (M.db.minLevel or 10) .. " and anyone already asked are hidden."))

  local items = {}
  local heard = F:Heard()
  if #heard > 0 then
    items[#items + 1] = { group = "Heard in chat: they asked, so start here" }
    for _, h in ipairs(heard) do items[#items + 1] = rowFor(h) end
  end
  if #F.rows > 0 then
    items[#items + 1] = { group = "Around now: levels " .. M.Find.BandText(F.asking) }
    for _, r in ipairs(F.rows) do items[#items + 1] = rowFor(r) end
  end
  f.list:SetData(items)
  if #items == 0 then
    f.empty:SetText(F.asking and "Nobody new at these levels. Press Next for the next band."
      or "Press Next to ask the game who's around.\n\nPeople asking for a guild in channels you're in show up here by themselves (not during boss fights).")
    f.empty:Show()
  else
    f.empty:Hide()
  end
  tick(f)
end

Window:AddPane("find", { build = build, fill = fill, tick = tick })
