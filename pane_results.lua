-- Results: what's working. Totals for the last 90 days, then by source, template and recruiter, then who joined and
-- whether they stayed.

local Core = NorgannonCore
local M = Muster
if M.disabled then return end
local UI = Core.UI
local Colors = UI.C
local Window = M.Window

local function build(f)
  f.totals = UI.Text(f, "title", 15, Colors.text)
  f.totals:SetPoint("TOPLEFT")
  f.totals:SetPoint("TOPRIGHT")
  f.totals:SetJustifyH("LEFT")
  f.pane = UI.Pane(f)
  f.pane:SetPoint("TOPLEFT", f.totals, "BOTTOMLEFT", 0, -10)
  f.pane:SetPoint("BOTTOMRIGHT", 0, 22)
  f.list = Window.RowList(f.pane, 30)
  f.list:SetPoint("TOPLEFT", 2, -2)
  f.list:SetPoint("BOTTOMRIGHT", -2, 2)
  f.foot = Window.Line(f, 11, Colors.faint)
  f.foot:SetPoint("BOTTOMLEFT")
  f.foot:SetPoint("BOTTOMRIGHT")
  f.foot:SetText("Facts only, from what Muster saw and the guild roster. Notes and names stay on this machine.")
end

local function counts(r)
  return string.format("asked %d  ·  replied %d  ·  joined %d  ·  stayed 30 days %d", r.asked, r.replied, r.joined, r.stayed)
end

local function fill(f)
  if not M:Guild() then
    f.totals:SetText("Not in a guild.")
    f.list:SetData({})
    return
  end
  local s = M.Results:Summary()
  f.totals:SetText(string.format("%d joined in %d days  ·  %d still here after 30 days  ·  %d asked  ·  %d said no",
    s.joined, M.Results.DAYS, s.stayed30, s.asked, s.saidNo))
  local items = {}
  local function section(title, rows)
    if #rows == 0 then return end
    items[#items + 1] = { group = title }
    for _, r in ipairs(rows) do items[#items + 1] = { title = r.label, right = counts(r) } end
  end
  section("Where they came from", M.Results:BySource())
  section("Which whisper", M.Results:ByTemplate())
  section("Through whom", M.Results:ByRecruiter())
  local joined = M.Results:Joined()
  if #joined > 0 then
    items[#items + 1] = { group = "Who joined" }
    for _, p in ipairs(joined) do
      local stayed, color = M.Results.Stayed(p)
      items[#items + 1] = {
        title = M.Colored(p.name, p.class) .. "  " .. Window.Tag(M.People.SOURCES[p.source] or p.source or "", "faint"),
        right = (p.invitedBy or p.by or "?") .. "  ·  " .. date("%d %b", p.joinedAt) .. "  ·  " .. Window.Tag(stayed, color),
        onClick = function() Window:Open("people", p.key) end,
      }
    end
  end
  if #items == 0 then items[1] = { title = "Nothing yet: results start with the first person you ask.", right = "" } end
  f.list:SetData(items)
end

Window:AddPane("results", { build = build, fill = fill })
