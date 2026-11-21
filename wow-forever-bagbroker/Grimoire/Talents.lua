-- Grimoire: talent plan and tips window, with level-up reminders.
-- Current ranks are read from the talent system (C_ClassTalents / C_Traits) by node ID.
local _, ns = ...

local Talents = { rows = {} }
ns.Talents = Talents

local ROW_HEIGHT = 16
local WIDTH = 420

-- Ranks currently learned per node, or nil when the talent API is unavailable.
function Talents:LearnedRanks()
	if not (C_ClassTalents and C_ClassTalents.GetActiveConfigID and C_Traits and C_Traits.GetNodeInfo) then return nil end
	local configID = C_ClassTalents.GetActiveConfigID()
	if not configID then return nil end
	local ranks = {}
	for nodeID in pairs(ns.TALENT_NODES) do
		local info = C_Traits.GetNodeInfo(configID, nodeID)
		if info then ranks[nodeID] = info.activeRank or info.ranksPurchased or 0 end
	end
	return ranks
end

-- Plan steps with a status: "done", "next" (affordable now), "later".
function Talents:Status(level, ranks)
	local out, nextFound = {}, false
	local available = math.max(0, level - 9)
	local spent = 0
	if ranks then for _, r in pairs(ranks) do spent = spent + r end end
	for i, step in ipairs(ns.TALENT_PLAN) do
		local stepLevel, nodeID, rank = step[1], step[2], step[3]
		local status = "later"
		if ranks and (ranks[nodeID] or 0) >= rank then
			status = "done"
		elseif stepLevel <= level and not nextFound then
			status = "next"
			nextFound = true
		elseif stepLevel <= level then
			status = "due"
		end
		out[i] = { level = stepLevel, nodeID = nodeID, rank = rank, why = step[4], status = status }
	end
	return out, spent, available
end

-- Talent ranks by name and points per tree, cached until the talents change.
function Talents:Cache()
	if not self.cache then
		self.cache = { ranks = {}, trees = { Affliction = 0, Demonology = 0, Destruction = 0 } }
		local ranks = self:LearnedRanks() or {}
		for nodeID, node in pairs(ns.TALENT_NODES) do
			local r = ranks[nodeID] or 0
			if r > 0 then
				self.cache.ranks[node[1]] = r
				self.cache.trees[node[2]] = (self.cache.trees[node[2]] or 0) + r
			end
		end
	end
	return self.cache
end

function Talents:Has(name) return (self:Cache().ranks[name] or 0) > 0 end
function Talents:Rank(name) return self:Cache().ranks[name] or 0 end

-- Specialization: the tree with the most points (Affliction before any point, as guides advise).
function Talents:Spec()
	local trees, best = self:Cache().trees, "Affliction"
	for _, tree in ipairs({ "Affliction", "Demonology", "Destruction" }) do
		if trees[tree] > trees[best] then best = tree end
	end
	return best
end

function Talents:NextSteps(level, ranks)
	local steps = self:Status(level, ranks)
	local due = {}
	for _, s in ipairs(steps) do
		if s.status == "next" or s.status == "due" then due[#due + 1] = s end
	end
	return due
end

local COLORS = { done = "|cff40c040", next = "|cffffd200", due = "|cffffd200", later = "|cff808080" }

function Talents:Create()
	if self.frame then return self.frame end
	local f = ns:CreateWindow("GrimoireGuide", UIParent, "Grimoire: Affliction levelling")
	f:SetSize(WIDTH, 470)
	f:SetPoint("CENTER", -200, 0)
	f:SetFrameStrata("HIGH")
	f:SetMovable(true)
	f:EnableMouse(true)
	f:RegisterForDrag("LeftButton")
	f:SetScript("OnDragStart", f.StartMoving)
	f:SetScript("OnDragStop", f.StopMovingOrSizing)
	f:SetClampedToScreen(true)
	f:Hide()
	tinsert(UISpecialFrames, "GrimoireGuide")
	self.frame = f

	f.summary = f:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
	f.summary:SetPoint("TOPLEFT", 14, -30)
	f.summary:SetPoint("TOPRIGHT", -14, -30)
	f.summary:SetJustifyH("LEFT")

	local scroll = CreateFrame("ScrollFrame", "GrimoireGuideScroll", f, "UIPanelScrollFrameTemplate")
	scroll:SetPoint("TOPLEFT", 10, -50)
	scroll:SetPoint("BOTTOMRIGHT", -30, 130)
	local content = CreateFrame("Frame", nil, scroll)
	content:SetSize(WIDTH - 44, 1)
	scroll:SetScrollChild(content)
	self.content = content

	f.tipsTitle = f:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
	f.tipsTitle:SetPoint("BOTTOMLEFT", 14, 110)
	f.tipsTitle:SetText("Demons and tips")
	f.tips = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	f.tips:SetPoint("TOPLEFT", f.tipsTitle, "BOTTOMLEFT", 0, -4)
	f.tips:SetPoint("RIGHT", -14, 0)
	f.tips:SetJustifyH("LEFT")
	f.tips:SetJustifyV("TOP")
	f.tips:SetHeight(90)
	f.source = f:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
	f.source:SetPoint("BOTTOMLEFT", 14, 8)
	f.source:SetPoint("BOTTOMRIGHT", -14, 8)
	f.source:SetJustifyH("LEFT")
	f.source:SetText("Talent order: consensus of current Forever guides (Wowhead, Icy Veins, Conquest Capped). Tree: game files.")
	f:SetScript("OnShow", function() self:Refresh() end)
	return f
end

function Talents:Refresh()
	local f = self.frame
	if not f or not f:IsShown() then return end
	local level = UnitLevel("player") or 1
	local ranks = self:LearnedRanks()
	local steps, spent, available = self:Status(level, ranks)
	local due = self:NextSteps(level, ranks)
	local nextText = due[1] and ("%s %d/%d"):format(ns.TALENT_NODES[due[1].nodeID][1], due[1].rank, ns.TALENT_NODES[due[1].nodeID][4]) or "none"
	if ranks then
		f.summary:SetText(("Level %d: %d of %d points spent. Next: %s"):format(level, spent, available, nextText))
	else
		f.summary:SetText(("Level %d. Talent ranks unavailable: the plan is shown without progress."):format(level))
	end
	for i, s in ipairs(steps) do
		local row = self.rows[i]
		if not row then
			row = self.content:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
			row:SetPoint("TOPLEFT", 4, -(i - 1) * ROW_HEIGHT)
			row:SetPoint("RIGHT", -4, 0)
			row:SetJustifyH("LEFT")
			row:SetWordWrap(false)
			self.rows[i] = row
		end
		local node = ns.TALENT_NODES[s.nodeID]
		local mark = s.status == "done" and "|cff40c040+|r" or (s.status == "later" and " " or "|cffffd200>|r")
		row:SetText(("%s %s%2d  %s %d/%d|r  |cff9d9d9d%s|r"):format(mark, COLORS[s.status], s.level, node[1], s.rank, node[4], s.why or ""))
	end
	self.content:SetHeight(#steps * ROW_HEIGHT)
	local tips = {}
	for _, t in ipairs(ns.DEMON_ADVICE) do tips[#tips + 1] = "|cff9482c9-|r " .. t end
	for _, t in ipairs(ns.TIPS) do tips[#tips + 1] = "- " .. t end
	f.tips:SetText(table.concat(tips, "\n"))
end

function Talents:Toggle()
	local f = self:Create()
	f:SetShown(not f:IsShown())
end

ns:RegisterEvent("PLAYER_LEVEL_UP", function(_, newLevel)
	Talents.cache = nil
	if not ns.isWarlock or not ns.settings.talentReminders then return end
	C_Timer.After(2, function()
		local due = Talents:NextSteps(tonumber(newLevel) or UnitLevel("player"), Talents:LearnedRanks())
		if due[1] then
			local node = ns.TALENT_NODES[due[1].nodeID]
			ns:Print(("Talent point: %s %d/%d (%s). /grim talents for the plan."):format(node[1], due[1].rank, node[4], due[1].why or ""))
		end
		if Talents.frame and Talents.frame:IsShown() then Talents:Refresh() end
	end)
end)

ns:RegisterEvent("TRAIT_CONFIG_UPDATED", function()
	Talents.cache = nil
	if Talents.frame and Talents.frame:IsShown() then Talents:Refresh() end
end)
