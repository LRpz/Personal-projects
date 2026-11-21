-- Grimoire: class trainer helper. A panel next to the trainer marks every spell as core (train
-- every rank), useful (situational) or skip, with the reason, and learns all core spells in one click.
local _, ns = ...

local Trainer = { rows = {} }
ns.Trainer = Trainer

local WIDTH = 300
local ROW_HEIGHT = 18
local TAGS = { core = "|cff40c040core|r", useful = "|cffffd200useful|r", skip = "|cff808080skip|r" }

-- Mainline returns name, type ("available", "unavailable", "used", "header"), icon, required level.
function Trainer:Services()
	local list = {}
	for i = 1, (GetNumTrainerServices and GetNumTrainerServices() or 0) do
		local name, kind, icon, reqLevel = GetTrainerServiceInfo(i)
		if name and kind ~= "header" then
			local advice = ns.TRAINER[name]
			list[#list + 1] = {
				index = i, name = name, kind = kind, icon = icon, level = reqLevel or 0,
				cost = (GetTrainerServiceCost and GetTrainerServiceCost(i)) or 0,
				tag = advice and advice[1] or "useful", why = advice and advice[2] or "not rated",
			}
		end
	end
	local order = { core = 1, useful = 2, skip = 3 }
	table.sort(list, function(a, b)
		if (a.kind == "available") ~= (b.kind == "available") then return a.kind == "available" end
		if order[a.tag] ~= order[b.tag] then return order[a.tag] < order[b.tag] end
		return a.level < b.level
	end)
	return list
end

function Trainer:CoreAvailable(services)
	local core, cost = {}, 0
	for _, s in ipairs(services) do
		if s.kind == "available" and s.tag == "core" then
			core[#core + 1] = s
			cost = cost + s.cost
		end
	end
	return core, cost
end

-- Learns every available core spell (highest index first, so earlier indices stay valid).
function Trainer:LearnCore()
	local core = self:CoreAvailable(self:Services())
	table.sort(core, function(a, b) return a.index > b.index end)
	local learned = 0
	for _, s in ipairs(core) do
		if GetMoney() >= s.cost then
			BuyTrainerService(s.index)
			learned = learned + 1
		end
	end
	ns:Print(("Learned %d core spell(s)."):format(learned))
	C_Timer.After(0.5, function() self:Refresh() end)
end

function Trainer:Create()
	if self.frame then return self.frame end
	if not ClassTrainerFrame then return nil end
	local f = ns:CreateWindow("GrimoireTrainer", ClassTrainerFrame, "Grimoire: what to train")
	f:SetSize(WIDTH, 420)
	f:SetPoint("TOPLEFT", ClassTrainerFrame, "TOPRIGHT", 4, 0)
	f:EnableMouse(true)
	self.frame = f
	local scroll = CreateFrame("ScrollFrame", "GrimoireTrainerScroll", f, "UIPanelScrollFrameTemplate")
	scroll:SetPoint("TOPLEFT", 10, -30)
	scroll:SetPoint("BOTTOMRIGHT", -30, 60)
	local content = CreateFrame("Frame", nil, scroll)
	content:SetSize(WIDTH - 44, 1)
	scroll:SetScrollChild(content)
	self.content = content
	f.summary = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	f.summary:SetPoint("BOTTOMLEFT", 12, 38)
	f.summary:SetPoint("BOTTOMRIGHT", -12, 38)
	f.summary:SetJustifyH("LEFT")
	local learn = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
	learn:SetSize(180, 22)
	learn:SetPoint("BOTTOMRIGHT", -10, 10)
	learn:SetScript("OnClick", function() self:LearnCore() end)
	f.learn = learn
	return f
end

function Trainer:Refresh()
	local f = self.frame
	if not f or not f:IsShown() then return end
	local services = self:Services()
	for i, s in ipairs(services) do
		local row = self.rows[i]
		if not row then
			row = CreateFrame("Frame", nil, self.content)
			row:SetSize(WIDTH - 44, ROW_HEIGHT)
			row:SetPoint("TOPLEFT", 0, -(i - 1) * ROW_HEIGHT)
			row.icon = row:CreateTexture(nil, "ARTWORK")
			row.icon:SetSize(16, 16)
			row.icon:SetPoint("LEFT", 2, 0)
			row.text = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
			row.text:SetPoint("LEFT", row.icon, "RIGHT", 4, 0)
			row.text:SetPoint("RIGHT", -2, 0)
			row.text:SetJustifyH("LEFT")
			row.text:SetWordWrap(false)
			self.rows[i] = row
		end
		row.icon:SetTexture(s.icon)
		local state = s.kind == "available" and "" or (s.kind == "used" and " |cff808080(known)|r" or (" |cff808080(level " .. s.level .. ")|r"))
		row.text:SetText(("%s  %s%s  |cff9d9d9d%s|r"):format(TAGS[s.tag], s.name, state, s.why))
		row:Show()
	end
	for i = #services + 1, #self.rows do self.rows[i]:Hide() end
	self.content:SetHeight(math.max(1, #services * ROW_HEIGHT))
	local core, cost = self:CoreAvailable(services)
	f.summary:SetText(("%d core spell(s) available for %s"):format(#core, ns.FormatMoney(cost)))
	f.learn:SetText(("Learn core spells (%d)"):format(#core))
	f.learn:SetEnabled(#core > 0)
end

ns:RegisterEvent("TRAINER_SHOW", function()
	if not ns.isWarlock then return end
	C_Timer.After(0.1, function()
		local f = Trainer:Create()
		if not f then return end
		if f:IsShown() then Trainer:Refresh() else f:Show() Trainer:Refresh() end
	end)
end)

ns:RegisterEvent("TRAINER_UPDATE", function()
	if Trainer.frame and Trainer.frame:IsShown() then Trainer:Refresh() end
end)
