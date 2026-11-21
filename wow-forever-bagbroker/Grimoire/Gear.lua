-- Grimoire: gear upgrades tab in BagBroker's auction house panel.
-- For every equipment slot, the biggest upgrade over what you wear that costs at most your budget
-- per item: bind-on-equip items a warlock can use, around your level (items a few levels above are
-- shown with the level they need). Score = spell power x w1 + Stamina x w2 + Intellect x w3 +
-- Spirit x w4 (defaults 1.00 / 0.60 / 0.45 / 0.35, adjustable in the tab). Candidates come from
-- BagBroker's last full auction scan, which keeps the cheapest auction of each item and suffix.
local _, ns = ...

local Gear = { rows = {}, scoreCache = {} }
ns.Gear = Gear

local ROW_HEIGHT = 30
local WIDTH = 390

-- equipLoc -> comparison group and the inventory slots it replaces
local SLOT_GROUPS = {
	INVTYPE_HEAD = { "Head", { 1 } }, INVTYPE_NECK = { "Neck", { 2 } }, INVTYPE_SHOULDER = { "Shoulder", { 3 } },
	INVTYPE_CHEST = { "Chest", { 5 } }, INVTYPE_ROBE = { "Chest", { 5 } }, INVTYPE_WAIST = { "Waist", { 6 } },
	INVTYPE_LEGS = { "Legs", { 7 } }, INVTYPE_FEET = { "Feet", { 8 } }, INVTYPE_WRIST = { "Wrist", { 9 } },
	INVTYPE_HAND = { "Hands", { 10 } }, INVTYPE_FINGER = { "Ring", { 11, 12 }, "lowest" },
	INVTYPE_TRINKET = { "Trinket", { 13, 14 }, "lowest" }, INVTYPE_CLOAK = { "Back", { 15 } },
	INVTYPE_WEAPON = { "Main hand", { 16 } }, INVTYPE_WEAPONMAINHAND = { "Main hand", { 16 } },
	INVTYPE_2HWEAPON = { "Two-hand", { 16, 17 }, "sum" }, INVTYPE_WEAPONOFFHAND = { "Off hand", { 17 } },
	INVTYPE_HOLDABLE = { "Off hand", { 17 } }, INVTYPE_RANGED = { "Wand", { 18 } }, INVTYPE_RANGEDRIGHT = { "Wand", { 18 } },
}

-- What a warlock can equip: cloth and miscellaneous armour; daggers, one-handed swords, staves, wands.
local USABLE = { [4] = { [0] = true, [1] = true }, [2] = { [7] = true, [10] = true, [15] = true, [19] = true } }

local SP_PATTERNS = {
	{ "Increases damage and healing done by magical spells and effects by up to (%d+)", "sp" },
	{ "Increases damage done by Shadow spells and effects by up to (%d+)", "sp" },
	{ "Increases damage done by Fire spells and effects by up to (%d+)", "fire" },
	{ "^%+(%d+) Shadow Spell Damage", "sp" },
	{ "^%+(%d+) Shadow Damage", "sp" },
	{ "^%+(%d+) Damage and Healing Spells", "sp" },
	{ "^%+(%d+) Spell Damage", "sp" },
	{ "^%+(%d+) Fire Spell Damage", "fire" },
}

local function Weights() return ns.settings.weights end

-- Stats of an item link: spell power (from stats or tooltip text), fire damage, Stamina, Intellect, Spirit.
function Gear:ItemStats(link)
	local stats = (C_Item.GetItemStats and C_Item.GetItemStats(link)) or {}
	local s = {
		stamina = stats.ITEM_MOD_STAMINA_SHORT or 0,
		intellect = stats.ITEM_MOD_INTELLECT_SHORT or 0,
		spirit = stats.ITEM_MOD_SPIRIT_SHORT or 0,
		sp = (stats.ITEM_MOD_SPELL_POWER_SHORT or 0) + (stats.ITEM_MOD_SPELL_DAMAGE_DONE_SHORT or 0),
		fire = 0,
	}
	local textSP = 0
	local data = C_TooltipInfo and C_TooltipInfo.GetHyperlink and C_TooltipInfo.GetHyperlink(link)
	for _, line in ipairs(data and data.lines or {}) do
		local text = line.leftText
		if type(text) == "string" and not ns.IsSecret(text) then
			for _, p in ipairs(SP_PATTERNS) do
				local n = tonumber(text:match(p[1]))
				if n then
					if p[2] == "sp" then textSP = textSP + n else s.fire = s.fire + n end
					break
				end
			end
		end
	end
	s.sp = math.max(s.sp, textSP)
	return s
end

function Gear:Score(link)
	if not link then return 0 end
	local cached = self.scoreCache[link]
	if cached then return cached end
	local s = self:ItemStats(link)
	local w = Weights()
	local score = s.sp * w.sp + s.fire * w.sp * 0.25 + s.stamina * w.stamina + s.intellect * w.intellect + s.spirit * w.spirit
	self.scoreCache[link] = score
	return score
end

-- Score of what is worn in the slots a candidate would replace.
function Gear:EquippedScore(group)
	local slots, mode = group[2], group[3]
	if mode == "lowest" then
		local lowest
		for _, slot in ipairs(slots) do
			local v = self:Score(GetInventoryItemLink("player", slot))
			if not lowest or v < lowest then lowest = v end
		end
		return lowest or 0
	end
	local total = 0
	for _, slot in ipairs(slots) do total = total + self:Score(GetInventoryItemLink("player", slot)) end
	return total
end

function Gear:Budget()
	if ns.settings.budget then return ns.settings.budget end
	return math.max(5000, math.min(500000, math.floor(GetMoney() * 0.05)))
end

-- Best upgrade within budget per comparison group. Returns rows sorted by gain, plus counters.
function Gear:Evaluate()
	local level = UnitLevel("player") or 1
	local low, high = level - ns.settings.levelsBelow, level + ns.settings.levelsAbove
	local budget = self:Budget()
	local candidates = BagBrokerAPI and BagBrokerAPI.GetGearCandidates() or {}
	local best, pending, considered = {}, 0, 0
	local mainIsTwoHand = false
	local mh = GetInventoryItemLink("player", 16)
	if mh then mainIsTwoHand = select(9, C_Item.GetItemInfo(mh)) == "INVTYPE_2HWEAPON" end
	for _, entry in ipairs(candidates) do
		local link, price = entry[1], entry[2]
		local name, _, quality, _, minLevel, _, _, _, equipLoc, icon, _, classID, subclassID, bindType = C_Item.GetItemInfo(link)
		if not name then
			pending = pending + 1
			local itemID = tonumber(link:match("item:(%d+)"))
			if itemID and C_Item.RequestLoadItemDataByID then C_Item.RequestLoadItemDataByID(itemID) end
		elseif price <= budget and bindType ~= 1 and USABLE[classID] and USABLE[classID][subclassID]
			and (minLevel or 0) >= low and (minLevel or 0) <= high and SLOT_GROUPS[equipLoc] then
			local group = SLOT_GROUPS[equipLoc]
			local offHandBlocked = mainIsTwoHand and group[1] == "Off hand"
			if not offHandBlocked then
				considered = considered + 1
				local gain = self:Score(link) - self:EquippedScore(group)
				local key = group[1]
				local b = best[key]
				if gain > 0.5 and (not b or gain > b.gain or (gain == b.gain and price < b.price)) then
					best[key] = { link = link, name = name, quality = quality, icon = icon, slot = key, gain = gain,
						price = price, minLevel = minLevel or 0, future = (minLevel or 0) > level }
				end
			end
		end
	end
	local rows = {}
	for _, row in pairs(best) do rows[#rows + 1] = row end
	table.sort(rows, function(a, b)
		if a.future ~= b.future then return not a.future end
		return a.gain > b.gain
	end)
	return rows, considered, pending, budget
end

---------------------------------------------------------------------------
-- Tab page
---------------------------------------------------------------------------
local function SmallButton(parent, width, onClick)
	local b = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
	b:SetSize(width, 20)
	if GameFontHighlightSmall then b:SetNormalFontObject(GameFontHighlightSmall) end
	b:RegisterForClicks("LeftButtonUp", "RightButtonUp")
	b:SetScript("OnClick", onClick)
	return b
end

local WEIGHT_KEYS = { { "sp", "SP" }, { "stamina", "Stam" }, { "intellect", "Int" }, { "spirit", "Spi" } }

function Gear:Build(page)
	self.page = page
	local label = page:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
	label:SetPoint("TOPLEFT", 14, -30)
	label:SetText("Stat weights (left/right click: +/- 0.05)")
	self.weightButtons = {}
	for i, wk in ipairs(WEIGHT_KEYS) do
		local b = SmallButton(page, 84, function(_, mouse)
			local w = Weights()
			w[wk[1]] = math.max(0, math.floor((w[wk[1]] + (mouse == "RightButton" and -0.05 or 0.05)) * 100 + 0.5) / 100)
			wipe(self.scoreCache)
			self:Refresh()
		end)
		b:SetPoint("TOPLEFT", 12 + (i - 1) * 90, -44)
		self.weightButtons[wk[1]] = b
	end

	local budgetLabel = page:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
	budgetLabel:SetPoint("TOPLEFT", 14, -74)
	budgetLabel:SetText("Max price per item:")
	local box = CreateFrame("EditBox", nil, page, "InputBoxTemplate")
	box:SetSize(90, 20)
	box:SetPoint("LEFT", budgetLabel, "RIGHT", 10, 0)
	box:SetAutoFocus(false)
	box:SetScript("OnEnterPressed", function(b)
		local copper = BagBrokerAPI and BagBrokerAPI.ParseMoney and BagBrokerAPI.ParseMoney(b:GetText())
		ns.settings.budget = (copper and copper > 0) and copper or nil
		b:ClearFocus()
		self:Refresh()
	end)
	box:SetScript("OnEscapePressed", function(b) b:ClearFocus() self:Refresh() end)
	self.budgetBox = box
	self.budgetHint = page:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
	self.budgetHint:SetPoint("LEFT", box, "RIGHT", 8, 0)

	self.levelButton = SmallButton(page, 150, function(_, mouse)
		local up = ns.settings.levelsAbove
		ns.settings.levelsAbove = mouse == "RightButton" and math.max(0, up - 1) or (up + 1) % 6
		self:Refresh()
	end)
	self.levelButton:SetPoint("TOPLEFT", 12, -98)

	local header = page:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
	header:SetPoint("TOPLEFT", 14, -124)
	header:SetText("Best upgrade within budget, per slot")
	local headerRight = page:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
	headerRight:SetPoint("TOPRIGHT", -34, -124)
	headerRight:SetText("Gain       Price")

	local scroll = CreateFrame("ScrollFrame", "GrimoireGearScroll", page, "UIPanelScrollFrameTemplate")
	scroll:SetPoint("TOPLEFT", 10, -140)
	scroll:SetPoint("BOTTOMRIGHT", -30, 58)
	local content = CreateFrame("Frame", nil, scroll)
	content:SetSize(WIDTH - 46, 1)
	scroll:SetScrollChild(content)
	self.content = content

	self.summary = page:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	self.summary:SetPoint("BOTTOMLEFT", 12, 38)
	self.summary:SetPoint("BOTTOMRIGHT", -12, 38)
	self.summary:SetJustifyH("LEFT")
	self.status = page:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
	self.status:SetPoint("BOTTOMLEFT", 12, 16)
	self.status:SetPoint("BOTTOMRIGHT", -110, 16)
	self.status:SetJustifyH("LEFT")
	local scan = CreateFrame("Button", nil, page, "UIPanelButtonTemplate")
	scan:SetSize(90, 22)
	scan:SetPoint("BOTTOMRIGHT", -10, 10)
	scan:SetText("Full scan")
	scan:SetScript("OnClick", function() if BagBrokerAPI then BagBrokerAPI.StartFullScan() end end)
end

function Gear:Row(i)
	local rf = self.rows[i]
	if rf then return rf end
	rf = CreateFrame("Button", nil, self.content)
	rf:SetSize(WIDTH - 46, ROW_HEIGHT)
	rf:SetPoint("TOPLEFT", 0, -(i - 1) * ROW_HEIGHT)
	local hl = rf:CreateTexture(nil, "HIGHLIGHT")
	hl:SetAllPoints()
	hl:SetColorTexture(1, 1, 1, 0.08)
	rf.icon = rf:CreateTexture(nil, "ARTWORK")
	rf.icon:SetSize(24, 24)
	rf.icon:SetPoint("LEFT", 2, 0)
	rf.name = rf:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	rf.name:SetPoint("TOPLEFT", rf.icon, "TOPRIGHT", 6, 0)
	rf.name:SetPoint("RIGHT", -150, 0)
	rf.name:SetJustifyH("LEFT")
	rf.name:SetWordWrap(false)
	rf.slot = rf:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
	rf.slot:SetPoint("BOTTOMLEFT", rf.icon, "BOTTOMRIGHT", 6, 0)
	rf.gain = rf:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	rf.gain:SetPoint("RIGHT", -102, 0)
	rf.gain:SetJustifyH("RIGHT")
	rf.price = BagBrokerAPI.CreateMoneyColumns(rf, 96)
	rf.price:SetPoint("RIGHT", -2, 0)
	rf:SetScript("OnEnter", function()
		if not rf.row then return end
		GameTooltip:SetOwner(rf, "ANCHOR_RIGHT")
		GameTooltip:SetHyperlink(rf.row.link)
		GameTooltip:Show()
	end)
	rf:SetScript("OnLeave", function() GameTooltip:Hide() end)
	rf:SetScript("OnClick", function()
		-- Search the item in the default auction house window, where you buy it.
		local bar = AuctionHouseFrame and AuctionHouseFrame.SearchBar
		if rf.row and bar and bar.SetSearchText and bar.StartSearch then
			bar:SetSearchText(rf.row.name)
			bar:StartSearch()
		end
	end)
	self.rows[i] = rf
	return rf
end

function Gear:Refresh()
	if not self.page or not self.page:IsShown() then return end
	for _, wk in ipairs(WEIGHT_KEYS) do
		self.weightButtons[wk[1]]:SetText(("%s %.2f"):format(wk[2], Weights()[wk[1]]))
	end
	self.levelButton:SetText(("Levels -%d to +%d"):format(ns.settings.levelsBelow, ns.settings.levelsAbove))
	local rows, considered, pending, budget = self:Evaluate()
	if not self.budgetBox:HasFocus() then self.budgetBox:SetText(ns.FormatMoney(budget):gsub("|T.-|t", "")) end
	self.budgetHint:SetText(ns.settings.budget and "set by you" or "5% of your gold")
	for i, row in ipairs(rows) do
		local rf = self:Row(i)
		rf.row = row
		rf.icon:SetTexture(row.icon)
		local color = BagBrokerAPI.QualityColor(row.quality)
		rf.name:SetText(color .. row.name .. "|r")
		rf.slot:SetText(row.slot .. (row.future and ("  |cffff8040usable at " .. row.minLevel .. "|r") or ("  level " .. row.minLevel)))
		rf.gain:SetText(("|cff40c040+%.1f|r"):format(row.gain))
		rf.price:SetAmount(row.price)
		rf:Show()
	end
	for i = #rows + 1, #self.rows do self.rows[i]:Hide() end
	self.content:SetHeight(math.max(1, #rows * ROW_HEIGHT))
	local candidates, scanTime = BagBrokerAPI.GetGearCandidates()
	local age = scanTime and math.floor((time() - scanTime) / 60) or nil
	self.summary:SetText(("%d upgrade(s) from %d usable items within budget"):format(#rows, considered))
	if #candidates == 0 then
		self.status:SetText("No scan data yet: run a full scan.")
	else
		self.status:SetText(("Scan: %d items, %s old%s"):format(#candidates, age and (age .. " min") or "?",
			pending > 0 and (", loading " .. pending .. " item(s)") or ""))
	end
	if pending > 0 and not self.retry then
		self.retry = true
		C_Timer.After(1.5, function()
			self.retry = false
			self:Refresh()
		end)
	end
end

ns:On("LOGIN", function()
	if not ns.isWarlock or not BagBrokerAPI then return end
	BagBrokerAPI.RegisterAuctionTab({
		key = "gear", label = "Gear", title = "Grimoire: best upgrades in budget",
		build = function(page) Gear:Build(page) end,
		onShow = function() Gear:Refresh() end,
	})
	BagBrokerAPI.On("SCAN_COMPLETE", function() Gear:Refresh() end)
end)

ns:RegisterEvent("PLAYER_EQUIPMENT_CHANGED", function()
	wipe(Gear.scoreCache)
	Gear:Refresh()
end)
