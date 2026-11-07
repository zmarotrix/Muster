-- Asking: your whisper templates and how each does, your advert lines and a button per channel, and the class needs
-- that sort Find and fill {need}.

local Core = NorgannonCore
local M = Muster
if M.disabled then return end
local UI = Core.UI
local Colors = UI.C
local Window = M.Window

local SIDE = 300
local SAMPLE = { name = "Ashwyndolyn Brightwater-Blackmantle", class = "PALADIN", level = 60, zone = "The Hinterlands and Alterac Foothills" }
local editing          -- the template open in the editor
local channelKey       -- the advert channel picked

local function build(f)
  f.left = CreateFrame("Frame", nil, f)
  f.left:SetPoint("TOPLEFT")
  f.left:SetPoint("BOTTOMRIGHT", -SIDE - 18, 0)

  local h1 = Window.Heading(f.left, "Whispers")
  h1:SetPoint("TOPLEFT", 0, -2)
  local fields = Window.Line(f.left, 11, Colors.faint)
  fields:SetPoint("LEFT", h1, "RIGHT", 8, 0)
  fields:SetText(M.Asking.FIELDS)
  f.pane = UI.Pane(f.left)
  f.pane:SetPoint("TOPLEFT", f.left, "TOPLEFT", 0, -24)
  f.pane:SetPoint("TOPRIGHT", f.left, "TOPRIGHT", 0, -24)
  f.pane:SetHeight(150)
  f.list = Window.RowList(f.pane, 36)
  f.list:SetPoint("TOPLEFT", 2, -2)
  f.list:SetPoint("BOTTOMRIGHT", -2, 2)

  -- the editor for the chosen template
  f.name = Window.Edit(f.left, function(text)
    if editing then editing.name = text ~= "" and text or editing.name end
  end)
  f.name:SetSize(180, 24)
  f.name:SetPoint("TOPLEFT", f.pane, "BOTTOMLEFT", 0, -8)
  f.use = UI.Button(f.left, "Use in Find", "quiet", function()
    if editing then M.db.template = editing.id Window:Refresh() end
  end)
  f.use:SetSize(96, 22)
  f.use:SetPoint("LEFT", f.name, "RIGHT", 6, 0)
  f.new = UI.Button(f.left, "New", "quiet", function()
    editing = M.Asking:AddTemplate("New template", "Hi {name}, ")
    Window:Refresh()
  end)
  f.new:SetSize(50, 22)
  f.new:SetPoint("LEFT", f.use, "RIGHT", 4, 0)
  f.delete = UI.Button(f.left, "Delete", "quiet", function()
    if editing and M.Asking:RemoveTemplate(editing.id) then editing = nil end
    Window:Refresh()
  end)
  f.delete:SetSize(60, 22)
  f.delete:SetPoint("LEFT", f.new, "RIGHT", 4, 0)
  f.text = Window.Edit(f.left, function(text)
    if editing then
      editing.text = text
      f.checkText()
    end
  end, true)
  f.text:SetPoint("TOPLEFT", f.pane, "BOTTOMLEFT", 0, -38)
  f.text:SetPoint("TOPRIGHT", f.pane, "BOTTOMRIGHT", 0, -38)
  f.text:SetHeight(58)
  f.check = Window.Line(f.left, 12)
  f.check:SetPoint("TOPLEFT", f.text, "BOTTOMLEFT", 0, -4)
  f.check:SetPoint("TOPRIGHT", f.text, "BOTTOMRIGHT", 0, -4)
  f.check:SetHeight(16)
  -- the length is checked on a long name in a long zone, so a template that passes here fits anyone
  function f.checkText()
    if not editing then return f.check:SetText("") end
    local bad = M.Asking.CheckText(M.Asking:Fill(editing, SAMPLE))
    f.check:SetText(bad and Window.Tag(bad, "warn") or Window.Tag("Fits, for a long name in a long zone.", "faint"))
  end

  -- adverts
  local h2 = Window.Heading(f.left, "Advert")
  h2:SetPoint("TOPLEFT", f.check, "BOTTOMLEFT", 0, -12)
  local hint = Window.Line(f.left, 11, Colors.faint)
  hint:SetPoint("LEFT", h2, "RIGHT", 8, 0)
  hint:SetText("one press, one line, in a channel you're already in")
  f.advert = Window.Edit(f.left, function(text) M.Adverts:SetLine(1, text) end, true)
  f.advert:SetPoint("TOPLEFT", f.check, "BOTTOMLEFT", 0, -36)
  f.advert:SetPoint("TOPRIGHT", f.check, "BOTTOMRIGHT", 0, -36)
  f.advert:SetHeight(48)
  f.channel = UI.Dropdown(f.left, {}, function(key) channelKey = key Window:Refresh() end)
  f.channel:SetSize(180, 24)
  f.channel:SetPoint("TOPLEFT", f.advert, "BOTTOMLEFT", 0, -8)
  f.post = UI.Button(f.left, "Post", "primary", function()
    for _, c in ipairs(M.Adverts:Channels()) do
      if c.name == channelKey then M.Adverts:Post(M.Adverts:Lines()[1], c) end
    end
  end)
  f.post:SetSize(90, 24)
  f.post:SetPoint("LEFT", f.channel, "RIGHT", 8, 0)
  f.postWhy = Window.Line(f.left, 12)
  f.postWhy:SetPoint("LEFT", f.post, "RIGHT", 10, 0)
  f.postWhy:SetPoint("RIGHT", f.left, "RIGHT")

  -- needs
  f.side = CreateFrame("Frame", nil, f)
  f.side:SetPoint("TOPRIGHT")
  f.side:SetPoint("BOTTOMRIGHT")
  f.side:SetWidth(SIDE)
  local h3 = Window.Heading(f.side, "Needs")
  h3:SetPoint("TOPLEFT")
  local note = Window.Line(f.side, 11, Colors.faint)
  note:SetPoint("LEFT", h3, "RIGHT", 8, 0)
  note:SetText("by class: the game never says a spec")
  f.needs = {}
  local previous = h3
  for _, c in ipairs(M.Classes()) do
    local row = CreateFrame("Frame", nil, f.side)
    row:SetSize(SIDE, 26)
    row:SetPoint("TOPLEFT", previous, "BOTTOMLEFT", 0, previous == h3 and -8 or -2)
    row.name = UI.Text(row, "body", 13)
    row.name:SetPoint("LEFT")
    row.name:SetText(M.Colored(c.name, c.file) .. (M.HEALERS[c.file] and ("  " .. Window.Tag("can heal", "faint")) or ""))
    row.seg = UI.Segmented(row, { { key = "want", label = "Wanted" }, { key = "open", label = "Open" }, { key = "full", label = "Full" } }, function(key)
      local g = M:Guild()
      if g then g.needs[c.file] = key ~= "open" and key or nil end
      M.Changed()
    end, 20)
    row.seg:SetPoint("RIGHT")
    f.needs[c.file] = row
    previous = row
  end
end

local function tick(f)
  local why = channelKey and M.Guards:WhyNotAdvert(channelKey)
  f.post:SetAlpha((why or not channelKey) and .4 or 1)
  f.postWhy:SetText(why or (channelKey and "Ready." or "Join a channel first: Muster never joins one for you."))
end

local function fill(f)
  local g = M:Guild()
  -- templates
  if not editing or not M.Asking:Template(editing.id) then editing = M.Asking:Template(M.db.template) end
  local items = {}
  for _, t in ipairs(M.Asking:Templates()) do
    local asked, replied, joined = M.Asking:Stats(t.id)
    local item = {
      title = t.name .. (t.id == M.db.template and ("  " .. Window.Tag("used in Find", "accent")) or ""),
      sub = t.text,
      right = string.format("%d/%d replied, %d joined", replied, asked, joined),
      onClick = function() editing = t Window:Refresh() end,
    }
    items[#items + 1] = item
    if t == editing then f.list.selected = item end
  end
  f.list:SetData(items, true)
  if editing then
    if not f.name.edit:HasFocus() then f.name:SetText(editing.name) end
    if not f.text.edit:HasFocus() then f.text:SetText(editing.text) end
  end
  f.checkText()
  -- adverts
  if g then
    if not f.advert.edit:HasFocus() then f.advert:SetText(M.Adverts:Lines()[1] or "") end
  end
  local options = {}
  for _, c in ipairs(M.Adverts:Channels()) do options[#options + 1] = { c.name, c.name } end
  f.channel.options = options
  local still = false
  for _, o in ipairs(options) do if o[1] == channelKey then still = true end end
  if not still then channelKey = options[1] and options[1][1] or nil end
  f.channel.value = nil
  f.channel:SetValue(channelKey or "No channels", true)
  -- needs
  for file, row in pairs(f.needs) do
    row.seg:Select(g and g.needs[file] or "open", true)
  end
  tick(f)
end

Window:AddPane("asking", { build = build, fill = fill, tick = tick })
