-- BagBroker: selling panel docked to the right of the default auction house window.
-- Lists every bag item that can be auctioned, with a tick box, a suggested unit price based on
-- the current listings and a duration based on the item category. Each click on "Post next"
-- posts one ticked item (the game only allows one auction post per click).
local _, ns = ...

local Panel = { rows = {}, byKey = {}, state = {}, cache = {}, rowFrames = {}, postedCount = 0 }
ns.Panel = Panel

local WIDTH = 390
local ROW_HEIGHT = 22
local LIVE_TTL = 300
local DURATION_LABELS = { "12h", "24h", "48h" }
local CATEGORIES = { "consumable", "trade", "gear", "rare", "other" }
local CATEGORY_LABELS = {
	consumable = "Consumables", trade = "Trade goods", gear = "BoE gear", rare = "Rare+ / recipes", other = "Other",
}
local SOURCE_COLORS = { live = "|cffffffff", estimate = "|cffa0a0a0", manual = "|cffffd200" }

---------------------------------------------------------------------------
-- State
---------------------------------------------------------------------------
function Panel:GetState(key)
	local st = self.state[key]
	if not st then
		st = {}
		self.state[key] = st
	end
	return st
end

local function SilverOnly()
	return C_AuctionHouse.SupportsCopperValues ~= nil and not C_AuctionHouse.SupportsCopperValues()
end

function Panel:ComputePrice(row)
	local st = self.state[row.key]
	if st and st.manual and st.price then
		row.price, row.reason, row.details = st.price, "manual", nil
	else
		row.price, row.reason, row.details = ns.Pricing.SuggestPrice(row.listings, {
			stats = ns:GetStats(row.itemID),
			wallFraction = ns.settings.wallFraction,
			silverOnly = SilverOnly(),
		})
	end
	row.source = (row.reason == "manual" and "manual") or (row.listings and "live") or "estimate"
	row.vendorBetter = row.price ~= nil and ns.Pricing.NetAfterCut(row.price, ns.AH_CUT) <= (row.sellPrice or 0)
end

function Panel:ApplyState(row)
	local st = self.state[row.key]
	if st and st.manualDuration and st.duration then
		row.duration = st.duration
	else
		row.duration = ns.settings.durations[row.category] or 2
	end
	if st and st.userChecked ~= nil then
		row.checked = st.userChecked
	else
		-- Proposal: tick everything with a price that beats the vendor.
		row.checked = row.price ~= nil and not row.vendorBetter
	end
	row.status = st and st.status
end

---------------------------------------------------------------------------
-- Rows
---------------------------------------------------------------------------
function Panel:BuildRows()
	local rows, byKey = {}, {}
	ns:ForEachBagSlot(function(bag, slot)
		local info = ns:GetSlotInfo(bag, slot)
		if not info or not info.loaded or not info.tradeable or not info.loc then return end
		if C_AuctionHouse.IsSellItemValid and not C_AuctionHouse.IsSellItemValid(info.loc, false) then return end
		local isCommodity = C_AuctionHouse.GetItemCommodityStatus(info.loc) == ns.Scanner.COMMODITY
		local itemKey = C_AuctionHouse.GetItemKeyFromItem(info.loc)
			or { itemID = info.itemID, itemLevel = 0, itemSuffix = 0, battlePetSpeciesID = 0 }
		local key = isCommodity and ("c" .. info.itemID)
			or ("i" .. info.itemID .. ":" .. (itemKey.itemLevel or 0) .. ":" .. (itemKey.itemSuffix or 0))
		local row = byKey[key]
		if row then
			row.count = row.count + info.count
			return
		end
		row = {
			key = key, itemID = info.itemID, itemKey = itemKey, isCommodity = isCommodity,
			link = info.link, name = info.name, quality = info.quality, icon = info.icon,
			count = info.count, sellPrice = info.sellPrice, bag = bag, slot = slot,
			category = ns:GetCategory(info.classID, info.quality),
		}
		byKey[key] = row
		rows[#rows + 1] = row
	end)
	local now = GetTime()
	for _, row in ipairs(rows) do
		local cached = self.cache[row.key]
		if cached and now - cached.time < LIVE_TTL then row.listings = cached.listings end
		self:ComputePrice(row)
		self:ApplyState(row)
	end
	self.rows, self.byKey = rows, byKey
	self:SortRows()
end

-- Most valuable first; "Post next" walks the list from the top.
function Panel:SortRows()
	table.sort(self.rows, function(a, b)
		local va, vb = (a.price or 0) * a.count, (b.price or 0) * b.count
		if va ~= vb then return va > vb end
		return (a.name or "") < (b.name or "")
	end)
end

function Panel:QueueLiveSearches()
	for _, row in ipairs(self.rows) do
		if not row.listings then
			row.searching = true
			local key = row.key
			ns.Scanner:QueueSearch(
				{ key = key, itemID = row.itemID, itemKey = row.itemKey, isCommodity = row.isCommodity },
				function(listings) Panel:OnListings(key, listings) end)
		end
	end
end

function Panel:OnListings(key, listings)
	self.cache[key] = { time = GetTime(), listings = listings }
	local row = self.byKey[key]
	if row then
		row.listings = listings
		row.searching = false
		self:ComputePrice(row)
		self:ApplyState(row)
	end
	-- Re-sort once all live prices are in, so rows do not jump around while they load.
	if ns.Scanner:PendingSearches() == 0 then self:SortRows() end
	self:Refresh()
end

function Panel:Rebuild()
	if not self.frame or not ns.ahOpen then return end
	self:BuildRows()
	self:QueueLiveSearches()
	self:Refresh()
end

function Panel:FindItemLocation(row)
	local found
	ns:ForEachBagSlot(function(bag, slot)
		local c = C_Container.GetContainerItemInfo(bag, slot)
		if c and c.itemID == row.itemID and not c.isLocked and not c.isBound then
			local loc = ItemLocation:CreateFromBagAndSlot(bag, slot)
			if row.isCommodity then
				found = loc
				return false
			end
			local key = C_AuctionHouse.GetItemKeyFromItem(loc)
			if key and (key.itemLevel or 0) == (row.itemKey.itemLevel or 0)
				and (key.itemSuffix or 0) == (row.itemKey.itemSuffix or 0) then
				found = loc
				return false
			end
		end
	end)
	return found
end

---------------------------------------------------------------------------
-- User actions
---------------------------------------------------------------------------
function Panel:SetChecked(row, checked)
	self:GetState(row.key).userChecked = checked and true or false
	row.checked = checked and true or false
	self:Refresh()
end

function Panel:SetAllChecked(checked)
	for _, row in ipairs(self.rows) do
		if row.price then
			self:GetState(row.key).userChecked = checked and true or false
			row.checked = checked and true or false
		end
	end
	self:Refresh()
end

function Panel:Select(key)
	self.selected = key
	self:Refresh()
end

function Panel:CycleCategory(category, direction)
	local current = ns.settings.durations[category] or 2
	ns.settings.durations[category] = ((current - 1 + direction) % 3) + 1
	for _, row in ipairs(self.rows) do self:ApplyState(row) end
	self:Refresh()
end

function Panel:CycleRowDuration(direction)
	local row = self.byKey[self.selected or ""]
	if not row then return end
	local st = self:GetState(row.key)
	st.manualDuration = true
	st.duration = ((row.duration - 1 + direction) % 3) + 1
	self:ApplyState(row)
	self:Refresh()
end

function Panel:ApplyPriceText(text)
	local row = self.byKey[self.selected or ""]
	if not row then return end
	local copper = ns.Pricing.ParseMoney(text)
	if not copper or copper <= 0 then
		self.message = "Could not read that price. Examples: 1g 20s, 35s, 80c, 1.5"
		self:Refresh()
		return
	end
	local st = self:GetState(row.key)
	st.manual, st.price, st.userChecked = true, copper, true
	self:ComputePrice(row)
	self:ApplyState(row)
	self.message = nil
	self:Refresh()
end

function Panel:ResetPrice()
	local row = self.byKey[self.selected or ""]
	if not row then return end
	local st = self:GetState(row.key)
	st.manual, st.price = nil, nil
	self:ComputePrice(row)
	self:ApplyState(row)
	self:Refresh()
end

-- Must run from a click: auction posting requires a hardware event, one post per click.
function Panel:PostNext()
	if self.pending then
		local p = self.pending
		self.pending = nil
		if p.isCommodity then
			C_AuctionHouse.ConfirmPostCommodity(p.args[1], p.args[2], p.args[3], p.args[4])
		else
			C_AuctionHouse.ConfirmPostItem(p.args[1], p.args[2], p.args[3], p.args[4], p.args[5])
		end
		self:GetState(p.row.key).status = "posting"
		p.row.status = "posting"
		self.message = nil
		self:Refresh()
		return
	end
	if not C_AuctionHouse.IsThrottledMessageSystemReady() then
		self.message = "Server busy, click again in a moment."
		self:Refresh()
		return
	end
	local row
	for _, r in ipairs(self.rows) do
		if r.checked and r.price and r.status ~= "posting" then
			row = r
			break
		end
	end
	if not row then return end

	local loc = self:FindItemLocation(row)
	if not loc then
		self.message = "Item not found in bags: " .. (row.link or "?")
		self:SetChecked(row, false)
		return
	end
	local quantity = row.count
	if C_AuctionHouse.GetAvailablePostCount then
		local available = C_AuctionHouse.GetAvailablePostCount(loc)
		if available and available > 0 then quantity = math.min(quantity, available) end
	end
	local price = row.price
	if SilverOnly() then price = math.max(100, math.floor(price / 100) * 100) end
	local deposit
	if row.isCommodity then
		deposit = C_AuctionHouse.CalculateCommodityDeposit(row.itemID, row.duration, quantity)
	else
		deposit = C_AuctionHouse.CalculateItemDeposit(loc, row.duration, quantity)
	end
	if deposit and deposit > GetMoney() then
		self.message = "Not enough money for the deposit (" .. ns.FormatMoney(deposit) .. ")."
		self:Refresh()
		return
	end

	local args, needsConfirmation
	if row.isCommodity then
		args = { loc, row.duration, quantity, price }
		needsConfirmation = C_AuctionHouse.PostCommodity(loc, row.duration, quantity, price)
	else
		args = { loc, row.duration, quantity, nil, price }
		needsConfirmation = C_AuctionHouse.PostItem(loc, row.duration, quantity, nil, price)
	end
	if needsConfirmation then
		self.pending = { row = row, isCommodity = row.isCommodity, args = args }
		self.message = "The server asks for confirmation (price far from market): click Confirm post."
		-- The default dialog would confirm the default sell frame, not this post: hide it.
		C_Timer.After(0, function()
			if StaticPopup_Hide then StaticPopup_Hide("AUCTION_HOUSE_POST_WARNING") end
		end)
	else
		self:GetState(row.key).status = "posting"
		row.status = "posting"
		self.message = nil
		-- If the server never confirms, release the row so it can be posted again.
		local key = row.key
		C_Timer.After(10, function()
			local st = Panel.state[key]
			if st and st.status == "posting" then
				st.status = nil
				local r = Panel.byKey[key]
				if r then r.status = nil end
				Panel:Refresh()
			end
		end)
	end
	self:Refresh()
end

---------------------------------------------------------------------------
-- Frame
---------------------------------------------------------------------------
local function CreateButton(parent, text, width, onClick)
	local b = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
	b:SetSize(width, 22)
	b:SetText(text)
	b:SetScript("OnClick", onClick)
	return b
end

function Panel:CreateRow(i)
	local rf = CreateFrame("Button", nil, self.content)
	rf:SetSize(WIDTH - 46, ROW_HEIGHT)
	rf:SetPoint("TOPLEFT", 0, -(i - 1) * ROW_HEIGHT)

	local highlight = rf:CreateTexture(nil, "HIGHLIGHT")
	highlight:SetAllPoints()
	highlight:SetColorTexture(1, 1, 1, 0.08)
	rf.sel = rf:CreateTexture(nil, "BACKGROUND")
	rf.sel:SetAllPoints()
	rf.sel:SetColorTexture(1, 0.82, 0, 0.15)
	rf.sel:Hide()

	rf.check = CreateFrame("CheckButton", nil, rf, "UICheckButtonTemplate")
	rf.check:SetSize(20, 20)
	rf.check:SetPoint("LEFT", 0, 0)
	rf.check:SetScript("OnClick", function(btn)
		if rf.row then self:SetChecked(rf.row, btn:GetChecked()) end
	end)

	rf.icon = rf:CreateTexture(nil, "ARTWORK")
	rf.icon:SetSize(18, 18)
	rf.icon:SetPoint("LEFT", rf.check, "RIGHT", 2, 0)

	rf.dur = rf:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	rf.dur:SetPoint("RIGHT", -2, 0)
	rf.dur:SetWidth(30)
	rf.dur:SetJustifyH("RIGHT")

	rf.price = rf:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	rf.price:SetPoint("RIGHT", rf.dur, "LEFT", -6, 0)
	rf.price:SetWidth(112)
	rf.price:SetJustifyH("RIGHT")

	rf.name = rf:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	rf.name:SetPoint("LEFT", rf.icon, "RIGHT", 4, 0)
	rf.name:SetPoint("RIGHT", rf.price, "LEFT", -4, 0)
	rf.name:SetJustifyH("LEFT")
	rf.name:SetWordWrap(false)

	rf:SetScript("OnClick", function()
		if rf.row then self:Select(rf.row.key) end
	end)
	rf:SetScript("OnEnter", function()
		local row = rf.row
		if not row then return end
		GameTooltip:SetOwner(rf, "ANCHOR_RIGHT")
		GameTooltip:SetBagItem(row.bag, row.slot)
		if row.price then
			ns.AddTooltipLine(GameTooltip, "Suggested: " .. ns.Pricing.DescribeReason(row.reason, row.details, ns.FormatMoney))
		end
		if row.vendorBetter then
			GameTooltip:AddLine("A vendor pays at least as much as this auction would after the cut.", 1, 0.5, 0.25, true)
		end
		GameTooltip:Show()
	end)
	rf:SetScript("OnLeave", function() GameTooltip:Hide() end)

	self.rowFrames[i] = rf
	return rf
end

function Panel:FillRow(rf, row)
	rf.row = row
	rf.check:SetChecked(row.checked and true or false)
	rf.check:SetEnabled(row.price ~= nil)
	rf.icon:SetTexture(row.icon)
	local countText = row.count > 1 and (" x" .. row.count) or ""
	rf.name:SetText(ns.QualityColor(row.quality) .. (row.name or "?") .. "|r" .. countText)
	local text
	if row.status == "posting" then
		text = "|cffffd200Posting...|r"
	elseif row.status == "failed" then
		text = "|cffff4040Failed|r"
	elseif row.price then
		local color = row.vendorBetter and "|cffff8040" or SOURCE_COLORS[row.source] or "|cffffffff"
		text = color .. ns.FormatMoney(row.price) .. "|r"
	elseif row.searching then
		text = "|cff808080...|r"
	else
		text = "|cff808080no data|r"
	end
	rf.price:SetText(text)
	rf.dur:SetText(DURATION_LABELS[row.duration] or "")
	rf.sel:SetShown(self.selected == row.key)
	rf:Show()
end

function Panel:CreateEditor(f)
	local ed = CreateFrame("Frame", nil, f)
	ed:SetPoint("BOTTOMLEFT", 12, 58)
	ed:SetPoint("BOTTOMRIGHT", -12, 58)
	ed:SetHeight(104)
	self.editor = ed

	ed.name = ed:CreateFontString(nil, "OVERLAY", "GameFontNormal")
	ed.name:SetPoint("TOPLEFT", 0, 0)
	ed.name:SetPoint("TOPRIGHT", 0, 0)
	ed.name:SetJustifyH("LEFT")
	ed.name:SetWordWrap(false)

	local priceLabel = ed:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	priceLabel:SetPoint("TOPLEFT", 0, -24)
	priceLabel:SetText("Unit price:")

	ed.priceBox = CreateFrame("EditBox", nil, ed, "InputBoxTemplate")
	ed.priceBox:SetSize(110, 20)
	ed.priceBox:SetPoint("TOPLEFT", 72, -19)
	ed.priceBox:SetAutoFocus(false)
	ed.priceBox:SetScript("OnEnterPressed", function(box)
		self:ApplyPriceText(box:GetText())
		box:ClearFocus()
	end)
	ed.priceBox:SetScript("OnEscapePressed", function(box)
		box:ClearFocus()
		self:Refresh()
	end)

	ed.setButton = CreateButton(ed, "Set", 46, function() self:ApplyPriceText(ed.priceBox:GetText()) end)
	ed.setButton:SetPoint("LEFT", ed.priceBox, "RIGHT", 6, 0)
	ed.autoButton = CreateButton(ed, "Auto", 52, function() self:ResetPrice() end)
	ed.autoButton:SetPoint("LEFT", ed.setButton, "RIGHT", 4, 0)

	local durLabel = ed:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	durLabel:SetPoint("TOPLEFT", 0, -50)
	durLabel:SetText("Duration:")
	ed.durButton = CreateButton(ed, "24h", 52, nil)
	ed.durButton:SetPoint("TOPLEFT", 72, -45)
	ed.durButton:RegisterForClicks("LeftButtonUp", "RightButtonUp")
	ed.durButton:SetScript("OnClick", function(_, button) self:CycleRowDuration(button == "RightButton" and -1 or 1) end)

	ed.info = ed:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	ed.info:SetPoint("TOPLEFT", 0, -72)
	ed.info:SetPoint("TOPRIGHT", 0, -72)
	ed.info:SetJustifyH("LEFT")
	ed.info:SetJustifyV("TOP")
	ed.info:SetHeight(34)
end

function Panel:Create()
	if self.frame then return self.frame end
	if not AuctionHouseFrame then return nil end
	local f = ns:CreateWindow("BagBrokerAuctionPanel", AuctionHouseFrame, "BagBroker: sell from bags")
	f:SetWidth(WIDTH)
	f:SetPoint("TOPLEFT", AuctionHouseFrame, "TOPRIGHT", 4, 0)
	f:SetPoint("BOTTOMLEFT", AuctionHouseFrame, "BOTTOMRIGHT", 4, 0)
	f:EnableMouse(true)
	self.frame = f

	local catLabel = f:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
	catLabel:SetPoint("TOPLEFT", 14, -30)
	catLabel:SetText("Default duration per category (left/right click to change)")

	self.catButtons = {}
	local columnWidth = (WIDTH - 28) / 3
	for i, category in ipairs(CATEGORIES) do
		local b = CreateButton(f, "", columnWidth - 4, nil)
		b:SetHeight(20)
		if GameFontHighlightSmall then b:SetNormalFontObject(GameFontHighlightSmall) end
		b:SetPoint("TOPLEFT", 12 + ((i - 1) % 3) * columnWidth, -44 - math.floor((i - 1) / 3) * 22)
		b:RegisterForClicks("LeftButtonUp", "RightButtonUp")
		b:SetScript("OnClick", function(_, button) self:CycleCategory(category, button == "RightButton" and -1 or 1) end)
		self.catButtons[category] = b
	end

	self.allCheck = CreateFrame("CheckButton", nil, f, "UICheckButtonTemplate")
	self.allCheck:SetSize(22, 22)
	self.allCheck:SetPoint("TOPLEFT", 10, -90)
	self.allCheck:SetScript("OnClick", function(btn) self:SetAllChecked(btn:GetChecked()) end)
	local header = f:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
	header:SetPoint("LEFT", self.allCheck, "RIGHT", 2, 0)
	header:SetText("Item")
	local headerRight = f:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
	headerRight:SetPoint("TOPRIGHT", -34, -96)
	headerRight:SetText("Unit price      Time")

	local scroll = CreateFrame("ScrollFrame", "BagBrokerAuctionPanelScroll", f, "UIPanelScrollFrameTemplate")
	scroll:SetPoint("TOPLEFT", 10, -114)
	scroll:SetPoint("BOTTOMRIGHT", -30, 168)
	local content = CreateFrame("Frame", nil, scroll)
	content:SetSize(WIDTH - 46, 1)
	scroll:SetScrollChild(content)
	self.content = content

	self:CreateEditor(f)

	self.summary = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	self.summary:SetPoint("BOTTOMLEFT", 12, 38)
	self.summary:SetPoint("BOTTOMRIGHT", -12, 38)
	self.summary:SetJustifyH("LEFT")

	self.postButton = CreateButton(f, "Post next", 130, function() self:PostNext() end)
	self.postButton:SetPoint("BOTTOMRIGHT", -10, 10)
	self.scanButton = CreateButton(f, "Full scan", 84, function() ns.Scanner:StartFullScan(true) end)
	self.scanButton:SetPoint("RIGHT", self.postButton, "LEFT", -4, 0)

	self.status = f:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
	self.status:SetPoint("BOTTOMLEFT", 12, 16)
	self.status:SetPoint("RIGHT", self.scanButton, "LEFT", -6, 0)
	self.status:SetJustifyH("LEFT")
	self.status:SetWordWrap(false)

	-- Reopen button on the auction house frame while the panel is hidden.
	local reopen = CreateButton(AuctionHouseFrame, "Sell bags", 80, function() f:Show() end)
	reopen:SetPoint("TOPLEFT", AuctionHouseFrame, "TOPRIGHT", 4, -28)
	reopen:Hide()
	self.reopenButton = reopen

	f:SetScript("OnShow", function()
		reopen:Hide()
		self:Rebuild()
	end)
	f:SetScript("OnHide", function()
		if ns.ahOpen then reopen:Show() end
	end)
	return f
end

function Panel:RefreshEditor()
	local ed = self.editor
	local row = self.byKey[self.selected or ""]
	local controls = { ed.priceBox, ed.setButton, ed.autoButton, ed.durButton }
	if not row then
		ed.name:SetText("|cffa0a0a0Click an item to edit its price or duration.|r")
		for _, c in ipairs(controls) do c:Hide() end
		ed.info:SetText("")
		return
	end
	for _, c in ipairs(controls) do c:Show() end
	ed.name:SetText(ns.QualityColor(row.quality) .. (row.name or "?") .. "|r" .. (row.count > 1 and (" x" .. row.count) or ""))
	if not ed.priceBox:HasFocus() then
		ed.priceBox:SetText(row.price and ns.Pricing.FormatMoneyText(row.price) or "")
	end
	ed.durButton:SetText(DURATION_LABELS[row.duration] or "?")
	local lines = { ns.Pricing.DescribeReason(row.reason, row.details, ns.FormatMoney) }
	local net = row.price and ns.Pricing.NetAfterCut(row.price, ns.AH_CUT)
	lines[#lines + 1] = ("Vendor %s each, auction net %s each"):format(
		ns.FormatMoney(row.sellPrice or 0), net and ns.FormatMoney(net) or "?")
	ed.info:SetText(table.concat(lines, "\n"))
end

function Panel:RefreshStatus()
	if not self.frame or not self.status then return end
	local text = ns.Scanner:GetProgressText()
	local pending = ns.Scanner:PendingSearches()
	if not text and pending > 0 then text = ("Checking live prices: %d left"):format(pending) end
	if not text and self.postedCount > 0 then text = ("Posted this visit: %d"):format(self.postedCount) end
	self.status:SetText(self.message or text or "")
end

function Panel:Refresh()
	local f = self.frame
	if not f or not f:IsShown() then return end
	for i, row in ipairs(self.rows) do
		self:FillRow(self.rowFrames[i] or self:CreateRow(i), row)
	end
	for i = #self.rows + 1, #self.rowFrames do
		self.rowFrames[i]:Hide()
		self.rowFrames[i].row = nil
	end
	self.content:SetHeight(math.max(1, #self.rows * ROW_HEIGHT))

	for category, b in pairs(self.catButtons) do
		b:SetText(("%s: %s"):format(CATEGORY_LABELS[category], DURATION_LABELS[ns.settings.durations[category]] or "?"))
	end

	local ticked, priced, total = 0, 0, 0
	for _, row in ipairs(self.rows) do
		if row.price then priced = priced + 1 end
		if row.checked and row.price and row.status ~= "posting" then
			ticked = ticked + 1
			total = total + row.price * row.count
		end
	end
	self.allCheck:SetChecked(priced > 0 and ticked == priced)
	self.summary:SetText(("%d ticked: %s, %s after the %d%% cut"):format(
		ticked, ns.FormatMoney(total), ns.FormatMoney(total * (1 - ns.AH_CUT)), ns.AH_CUT * 100))
	if self.pending then
		self.postButton:SetText("Confirm post")
		self.postButton:SetEnabled(true)
	else
		self.postButton:SetText(("Post next (%d)"):format(ticked))
		self.postButton:SetEnabled(ticked > 0)
	end
	self:RefreshEditor()
	self:RefreshStatus()
end

function Panel:Toggle()
	if not ns.ahOpen then
		ns:Print("Open the auction house first.")
		return
	end
	local f = self:Create()
	if f then f:SetShown(not f:IsShown()) end
end

function BagBroker_ToggleAuctionPanel()
	Panel:Toggle()
end

---------------------------------------------------------------------------
-- Events
---------------------------------------------------------------------------
local function MarkPosting(status)
	for key, st in pairs(Panel.state) do
		if st.status == "posting" then
			st.status = status
			if status == nil then st.userChecked = false end
			local row = Panel.byKey[key]
			if row then
				row.status = status
				if status == nil then row.checked = false end
			end
		end
	end
end

ns:RegisterEvent("AUCTION_HOUSE_SHOW", function()
	C_Timer.After(0.1, function()
		if not ns.ahOpen or not Panel:Create() then return end
		Panel.state, Panel.cache, Panel.pending, Panel.message, Panel.postedCount = {}, {}, nil, nil, 0
		Panel.selected = nil
		if ns.settings.panelAutoShow then
			if Panel.frame:IsShown() then Panel:Rebuild() else Panel.frame:Show() end
		else
			Panel.frame:Hide()
			Panel.reopenButton:Show()
		end
	end)
end)

ns:RegisterEvent("AUCTION_HOUSE_CLOSED", function()
	Panel.pending = nil
	if Panel.reopenButton then Panel.reopenButton:Hide() end
end)

ns:RegisterEvent("BAG_UPDATE_DELAYED", function()
	if not ns.ahOpen or not Panel.frame or not Panel.frame:IsShown() or Panel.rebuildQueued then return end
	Panel.rebuildQueued = true
	C_Timer.After(0.3, function()
		Panel.rebuildQueued = false
		Panel:Rebuild()
	end)
end)

ns:RegisterEvent("AUCTION_HOUSE_AUCTION_CREATED", function()
	Panel.postedCount = Panel.postedCount + 1
	MarkPosting(nil)
	Panel:Refresh()
end)

ns:RegisterEvent("AUCTION_HOUSE_SHOW_ERROR", function()
	MarkPosting("failed")
	Panel:Refresh()
end)

ns:RegisterEvent("AUCTION_HOUSE_POST_ERROR", function()
	Panel.pending = nil
	MarkPosting("failed")
	Panel:Refresh()
end)

ns:RegisterEvent("AUCTION_HOUSE_POST_WARNING", function()
	if Panel.pending then
		C_Timer.After(0, function()
			if StaticPopup_Hide then StaticPopup_Hide("AUCTION_HOUSE_POST_WARNING") end
		end)
	end
end)

ns:On("SCAN_STATE", function() Panel:RefreshStatus() end)
ns:On("SCAN_COMPLETE", function()
	for _, row in ipairs(Panel.rows) do
		Panel:ComputePrice(row)
		Panel:ApplyState(row)
	end
	Panel:Refresh()
end)
