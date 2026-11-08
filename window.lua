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
-- (Core's state colours: Muster's "warn" is red, the suite's "bad"; "amber" is the suite's "warn")
Window.CODES = { good = UI.State("good"), warn = UI.State("bad"), amber = UI.State("warn"), accent = UI.Code(UI.Accent("muster")),
  muted = UI.Code(Colors.muted), faint = UI.Code(Colors.faint) }

function Window.Tag(text, color)
  return (Window.CODES[color] or Window.CODES.muted) .. text .. "|r"
end

local win

-------------------------------------------------------------------------------------------
-- A list of rows: { group } or { title, sub, right, actions = { { text, run(shift), off, tip, width, style } }, onClick }
-------------------------------------------------------------------------------------------

Window.Tip = UI.Tip

---The row list every tab shares (Core's UI.ActionList): { group } or { title, sub, right, tip, onClick,
---actions = { { text, run(shift), off, tip, width } } }.
function Window.RowList(parent, rowHeight)
  return UI.ActionList(parent, { rowHeight = rowHeight })
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

---A text box (Core's UI.Input). onChange(text) on every edit the player makes.
function Window.Edit(parent, onChange, multiline)
  return UI.Input(parent, { onChange = onChange, multiline = multiline })
end

-------------------------------------------------------------------------------------------
-- The window
-------------------------------------------------------------------------------------------

---A pane: { build(frame), fill(frame) }.
function Window:AddPane(key, pane)
  self.panes[key] = pane
end

local function footerText()
  if not M:Guild() then return Window.CODES.amber .. "*|r You're not in a guild, so Muster has nobody to recruit for." end
  local muted = M.Guards:Muted()
  if muted then return Window.CODES.warn .. "*|r " .. muted end
  if Core.Guild:CanInvite() then return Window.CODES.good .. "*|r You can invite. One click sends one message to one person." end
  return Window.CODES.amber .. "*|r You can't invite on this character, so Ask an officer takes the Invite button's place."
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
