-- Muster's window (design/suite/muster.html): four tabs, a row list they share, and a footer that says whether you
-- can invite. Each tab is its own file.

local Core = NorgannonCore
local M = Muster
if M.disabled then return end
local UI = Core.UI
local Colors = UI.C

local Window = { panes = {} }
M.Window = Window

local W, H = 900, 600

local TABS = { { key = "find", label = "Find" }, { key = "people", label = "People" }, { key = "asking", label = "Asking" }, { key = "results", label = "Results" } }

-- colours for states and tags, as text codes
Window.CODES = { good = "|cff8fe08f", warn = "|cffe08a7a", amber = "|cffe7b04f", accent = "|cffe87ad6", muted = "|cffa8a08a", faint = "|cff6e6552" }

function Window.Tag(text, color)
  return (Window.CODES[color] or Window.CODES.muted) .. text .. "|r"
end

local win

-------------------------------------------------------------------------------------------
-- A list of rows: { group } or { title, sub, right, actions = { { text, run(shift), off, tip, width, style } }, onClick }
-------------------------------------------------------------------------------------------

local function tip(owner, text)
  if not text or text == "" then return end
  GameTooltip:SetOwner(owner, "ANCHOR_TOP")
  GameTooltip:AddLine(text, 1, 1, 1, true)
  GameTooltip:Show()
end
Window.Tip = tip

local function actionButton(row, i)
  local b = UI.Button(row, "", "quiet", function(self)
    local action = self.action
    if action and not action.off then action.run(IsShiftKeyDown()) end
  end)
  b:SetHeight(22)
  -- a tip may be a function, for text that changes while you hover (a countdown)
  b:SetScript("OnEnter", function(self)
    local t = self.action and self.action.tip
    if type(t) == "function" then t = t() end
    tip(self, t)
  end)
  b:SetScript("OnLeave", function() GameTooltip:Hide() end)
  row.buttons[i] = b
  return b
end

local function createRow(row, content)
  row.buttons = {}
  row.title = UI.Text(content, "body", 14)
  row.title:SetPoint("TOPLEFT", row, "TOPLEFT", 10, -4)
  row.title:SetWordWrap(false)
  row.title:SetJustifyH("LEFT")
  row.sub = UI.Text(content, "body", 12, Colors.muted)
  row.sub:SetPoint("TOPLEFT", row.title, "BOTTOMLEFT", 0, -2)
  row.sub:SetWordWrap(false)
  row.sub:SetJustifyH("LEFT")
  row.right = UI.Text(content, "body", 12, Colors.muted)
  row.right:SetJustifyH("RIGHT")
end

local function updateRow(row, item, titleY)
  row.title:ClearAllPoints()
  row.title:SetPoint("TOPLEFT", row, "TOPLEFT", 10, (item.sub and item.sub ~= "") and -4 or titleY)
  row.title:SetText(item.title or "")
  row.sub:SetText(item.sub or "")
  local previous
  for i = 1, math.max(#row.buttons, #(item.actions or {})) do
    local action = item.actions and item.actions[i]
    local b = row.buttons[i] or (action and actionButton(row, i))
    if b then
      b.action = action
      b:SetShown(action ~= nil)
      if action then
        b:SetLabel(action.text)
        b:SetWidth(action.width or 70)
        b:SetAlpha(action.off and .4 or 1)
        b:ClearAllPoints()
        if previous then b:SetPoint("RIGHT", previous, "LEFT", -4, 0) else b:SetPoint("RIGHT", row, "RIGHT", -12, 0) end
        previous = b
      end
    end
  end
  row.right:ClearAllPoints()
  if previous then row.right:SetPoint("RIGHT", previous, "LEFT", -10, 0) else row.right:SetPoint("RIGHT", row, "RIGHT", -12, 0) end
  row.right:SetText(item.right or "")
  -- the title and the line under it stop short of the buttons and the right-hand text
  local reserve = 12
  for _, action in ipairs(item.actions or {}) do reserve = reserve + (action.width or 70) + 4 end
  if item.right and item.right ~= "" then reserve = reserve + math.floor(row.right:GetStringWidth()) + 18 end
  row.title:SetPoint("TOPRIGHT", row, "TOPRIGHT", -reserve, (item.sub and item.sub ~= "") and -4 or titleY)
  row.sub:ClearAllPoints()
  row.sub:SetPoint("TOPLEFT", row.title, "BOTTOMLEFT", 0, -2)
  row.sub:SetPoint("TOPRIGHT", row.title, "BOTTOMRIGHT", 0, -2)
end

---A virtual list of these rows.
function Window.RowList(parent, rowHeight)
  local height = rowHeight or 38
  local titleY = -math.floor((height - 14) / 2)
  local list = UI.List(parent, {
    rowHeight = height,
    createRow = createRow,
    updateRow = function(row, item) updateRow(row, item, titleY) end,
    groupBand = true,
    onClick = function(item, _, button) if item.onClick then item.onClick(button) end end,
    onEnter = function(row, item) if item.tip then tip(row, item.tip) end end,
    onLeave = function() GameTooltip:Hide() end,
  })
  return list
end

---A line of text, left aligned, wrapping.
function Window.Line(parent, size, color, role)
  local text = UI.Text(parent, role or "body", size or 13, color or Colors.muted)
  text:SetJustifyH("LEFT")
  text:SetJustifyV("TOP")
  text:SetWordWrap(true)
  return text
end

---A small heading in the title face.
function Window.Heading(parent, text)
  local h = UI.Text(parent, "title", 14, Colors.goldSoft)
  h:SetJustifyH("LEFT")
  h:SetText(text)
  return h
end

---A single-line text box. onChange(text) on every edit the player makes.
function Window.Edit(parent, onChange, multiline)
  local holder = UI.Pane(parent)
  local edit = CreateFrame("EditBox", nil, holder)
  edit:SetAutoFocus(false)
  edit:SetFontObject(UI.Font("body", 13))
  edit:SetTextInsets(6, 6, 4, 4)
  edit:SetPoint("TOPLEFT", 2, -2)
  edit:SetPoint("BOTTOMRIGHT", -2, 2)
  if multiline then edit:SetMultiLine(true) end
  edit:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
  if not multiline then edit:SetScript("OnEnterPressed", function(self) self:ClearFocus() end) end
  edit:SetScript("OnTextChanged", function(self, user) if user and onChange then onChange(self:GetText()) end end)
  holder.edit = edit
  function holder:SetText(text) edit:SetText(text or "") end
  function holder:GetText() return edit:GetText() end
  return holder
end

-------------------------------------------------------------------------------------------
-- The window
-------------------------------------------------------------------------------------------

---A pane: { build(frame), fill(frame) }.
function Window:AddPane(key, pane)
  self.panes[key] = pane
end

local function footerText()
  if not M:Guild() then return "|cffe7b04f*|r You're not in a guild, so Muster has nobody to recruit for." end
  local muted = M.Guards:Muted()
  if muted then return "|cffe08a7a*|r " .. muted end
  if Core.Guild:CanInvite() then return "|cff8fe08f*|r You can invite. One click sends one message to one person." end
  return "|cffe7b04f*|r You can't invite on this character, so Ask an officer takes the Invite button's place."
end

local function fillPane()
  if not win then return end
  local key = Window.tab or "find"
  for k, p in pairs(Window.panes) do
    if p.frame then p.frame:SetShown(k == key) end
  end
  local p = Window.panes[key]
  if not p then return end
  if not p.frame then
    p.frame = CreateFrame("Frame", nil, win.paneArea)
    p.frame:SetAllPoints()
    p.build(p.frame)
  end
  p.frame:Show()
  p.fill(p.frame)
  win.footerText:SetText(footerText())
  win:SetSub(M.Global("GetGuildInfo", "player") or "No guild")
  local waiting = M.People:CountWaiting()
  win.tabs:SetCount("people", waiting > 0 and (waiting .. " waiting") or nil)
  local leads = M.Find and (#M.Find:Heard() + #M.Find.rows) or 0
  win.tabs:SetCount("find", leads > 0 and leads or nil)
end

local function build()
  win = UI.Window({ name = "MusterWindow", addon = "muster", title = "Muster", width = W, height = H, footer = true })
  win:SetAccent("muster")
  win:Hide()
  win.tabs = UI.Tabs(win.body, TABS, function(key)
    Window.tab = key
    fillPane()
  end)
  win.tabs:SetPoint("TOPLEFT")
  win.tabs:SetPoint("TOPRIGHT")
  win.tabs:ApplyAccent(UI.Accent("muster"))
  win.paneArea = CreateFrame("Frame", nil, win.body)
  win.paneArea:SetPoint("TOPLEFT", win.tabs, "BOTTOMLEFT", 14, -10)
  win.paneArea:SetPoint("BOTTOMRIGHT", -14, 10)
  win.gear = UI.Button(win.footer, "Settings", "quiet", function() M:OpenSettings() end)
  win.gear:SetSize(76, 20)
  win.gear:SetPoint("RIGHT", -12, 0)
end

function Window:Get()
  if not win and M.db then build() end
  return win
end

---Opens on a tab, or where it was. select: a person's key, for People.
function Window:Open(tab, select)
  if not self:Get() then return end
  if tab and self.panes[tab] then self.tab = tab end
  self.tab = self.tab or "find"
  if select then self.selected = select end
  win.tabs:Select(self.tab, true)
  win:Show()
  fillPane()
end

function Window:Refresh()
  if win and win:IsShown() then fillPane() end
end

---Something the window shows changed. Bursts become one redraw.
function Window:Changed()
  Core:NextFrame(function() Window:Refresh() end, "muster.changed")
end

-- Countdowns (next whisper, next /who, next advert) tick once a second while the window is open.
function Window:Tick()
  if not win or not win:IsShown() then return end
  local p = self.panes[self.tab or "find"]
  if p and p.tick and p.frame then p.tick(p.frame) end
end
