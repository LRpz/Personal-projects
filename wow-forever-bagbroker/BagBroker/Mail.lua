-- BagBroker: mail panel docked to the right of the mailbox.
-- Lists every bag item worth selling at the auction house (bind-on-equip items, and items whose
-- auction net beats the vendor price), remembers your mule's name per realm, and fills the mail in
-- one click: up to 12 stacks per mail (the game's attachment limit). You then press the default
-- Send button; the panel offers the remaining items for the next mail.
local _, ns = ...

local Mail = { rows = {}, byKey = {}, state = {}, rowFrames = {} }
ns.Mail = Mail

local WIDTH = 340
local ROW_HEIGHT = 20
local SUBJECT = "AH items"

local function MaxAttachments()
	return ATTACHMENTS_MAX_SEND or 12
end

-- Should this bag slot travel to the mule? Returns true and the unit auction net (may be nil).
function Mail:IsAuctionItem(info)
	if not info or not info.loaded or not info.tradeable or info.isLocked then return false end
	local net = ns:GetAHNet(info.itemID, info.sellPrice)
	if info.isBoE then return true, net end
	if net and net > (info.sellPrice or 0) then return true, net end
	return false
end

function Mail:BuildRows()
	local rows, byKey = {}, {}
	ns:ForEachBagSlot(function(bag, slot)
		local info = ns:GetSlotInfo(bag, slot)
		local ok, net = self:IsAuctionItem(info)
		if not ok then return end
		local row = byKey[info.itemID]
		if not row then
			row = { key = info.itemID, itemID = info.itemID, name = info.name, quality = info.quality, icon = info.icon,
				count = 0, slots = {}, net = net, sellPrice = info.sellPrice }
			byKey[info.itemID] = row
			rows[#rows + 1] = row
		end
		row.count = row.count + info.count
		row.slots[#row.slots + 1] = { bag = bag, slot = slot, itemID = info.itemID }
	end)
	for _, row in ipairs(rows) do
		local st = self.state[row.key]
		row.checked = (st == nil) and true or st
		row.value = math.max(0, row.net or row.sellPrice or 0) * row.count
	end
	table.sort(rows, function(a, b)
		if a.value ~= b.value then return a.value > b.value end
		return (a.name or "") < (b.name or "")
	end)
	self.rows, self.byKey = rows, byKey
end

function Mail:Mule()
	return ns.db.mules[ns:GetRealmKey()] or ""
end

function Mail:SetMule(name)
	name = (name or ""):gsub("^%s+", ""):gsub("%s+$", "")
	ns.db.mules[ns:GetRealmKey()] = name ~= "" and name or nil
end

function Mail:FreeAttachmentSlots()
	local free = {}
	for i = 1, MaxAttachments() do
		if not GetSendMailItem(i) then free[#free + 1] = i end
	end
	return free
end

-- Runs from the Attach button: picks up each ticked stack and drops it into a free attachment slot.
function Mail:Attach()
	if not SendMailFrame or not SendMailFrame:IsShown() then
		self.message = "Open the Send Mail tab first."
		self:Refresh()
		return
	end
	if CursorHasItem() then ClearCursor() end
	local mule = self:Mule()
	if mule ~= "" and SendMailNameEditBox then SendMailNameEditBox:SetText(mule) end
	if SendMailSubjectEditBox and SendMailSubjectEditBox:GetText() == "" then SendMailSubjectEditBox:SetText(SUBJECT) end
	local free = self:FreeAttachmentSlots()
	local attached, nextFree = 0, 1
	for _, row in ipairs(self.rows) do
		if row.checked then
			for _, s in ipairs(row.slots) do
				local index = free[nextFree]
				if not index then break end
				local current = C_Container.GetContainerItemInfo(s.bag, s.slot)
				if current and current.itemID == s.itemID and not current.isLocked then
					C_Container.PickupContainerItem(s.bag, s.slot)
					ClickSendMailItemButton(index)
					if CursorHasItem() then
						ClearCursor()
					else
						attached = attached + 1
						nextFree = nextFree + 1
					end
				end
			end
		end
	end
	if attached > 0 then
		self.message = ("Attached %d stack(s)%s. Press Send."):format(attached, mule ~= "" and (" for " .. mule) or "")
	else
		self.message = "Nothing attached: the mail is full or no stack is ticked."
	end
	self:Refresh()
end

---------------------------------------------------------------------------
-- Frame
---------------------------------------------------------------------------
function Mail:CreateRow(i)
	local rf = CreateFrame("Button", nil, self.content)
	rf:SetSize(WIDTH - 46, ROW_HEIGHT)
	rf:SetPoint("TOPLEFT", 0, -(i - 1) * ROW_HEIGHT)
	local highlight = rf:CreateTexture(nil, "HIGHLIGHT")
	highlight:SetAllPoints()
	highlight:SetColorTexture(1, 1, 1, 0.08)
	rf.check = CreateFrame("CheckButton", nil, rf, "UICheckButtonTemplate")
	rf.check:SetSize(20, 20)
	rf.check:SetPoint("LEFT", 0, 0)
	rf.check:SetScript("OnClick", function(btn)
		local row = rf.row
		if not row then return end
		row.checked = btn:GetChecked() and true or false
		self.state[row.key] = row.checked
		self:Refresh()
	end)
	rf.icon = rf:CreateTexture(nil, "ARTWORK")
	rf.icon:SetSize(16, 16)
	rf.icon:SetPoint("LEFT", rf.check, "RIGHT", 2, 0)
	rf.value = ns.CreateMoneyColumns(rf, 96)
	rf.value:SetPoint("RIGHT", -2, 0)
	rf.name = rf:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	rf.name:SetPoint("LEFT", rf.icon, "RIGHT", 4, 0)
	rf.name:SetPoint("RIGHT", rf.value, "LEFT", -4, 0)
	rf.name:SetJustifyH("LEFT")
	rf.name:SetWordWrap(false)
	rf:SetScript("OnEnter", function()
		local row = rf.row
		if not row or not row.slots[1] then return end
		GameTooltip:SetOwner(rf, "ANCHOR_RIGHT")
		GameTooltip:SetBagItem(row.slots[1].bag, row.slots[1].slot)
		GameTooltip:Show()
	end)
	rf:SetScript("OnLeave", function() GameTooltip:Hide() end)
	self.rowFrames[i] = rf
	return rf
end

function Mail:Create()
	if self.frame then return self.frame end
	if not MailFrame then return nil end
	local f = ns:CreateWindow("BagBrokerMailPanel", MailFrame, "BagBroker: send to mule")
	f:SetWidth(WIDTH)
	f:SetHeight(MailFrame:GetHeight() > 300 and MailFrame:GetHeight() or 440)
	f:SetPoint("TOPLEFT", MailFrame, "TOPRIGHT", 4, 0)
	f:EnableMouse(true)
	self.frame = f

	local label = f:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
	label:SetPoint("TOPLEFT", 14, -34)
	label:SetText("Mule:")
	local box = CreateFrame("EditBox", nil, f, "InputBoxTemplate")
	box:SetSize(150, 20)
	box:SetPoint("LEFT", label, "RIGHT", 10, 0)
	box:SetAutoFocus(false)
	box:SetScript("OnEnterPressed", function(b)
		self:SetMule(b:GetText())
		b:ClearFocus()
	end)
	box:SetScript("OnEditFocusLost", function(b) self:SetMule(b:GetText()) end)
	box:SetScript("OnEscapePressed", function(b) b:ClearFocus() end)
	self.muleBox = box
	local hint = f:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
	hint:SetPoint("LEFT", box, "RIGHT", 8, 0)
	hint:SetText("saved per realm")

	self.allCheck = CreateFrame("CheckButton", nil, f, "UICheckButtonTemplate")
	self.allCheck:SetSize(22, 22)
	self.allCheck:SetPoint("TOPLEFT", 10, -56)
	self.allCheck:SetScript("OnClick", function(btn)
		for _, row in ipairs(self.rows) do
			row.checked = btn:GetChecked() and true or false
			self.state[row.key] = row.checked
		end
		self:Refresh()
	end)
	local header = f:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
	header:SetPoint("LEFT", self.allCheck, "RIGHT", 2, 0)
	header:SetText("Auction items in your bags")
	local headerRight = f:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
	headerRight:SetPoint("TOPRIGHT", -34, -62)
	headerRight:SetText("Auction net")

	local scroll = CreateFrame("ScrollFrame", "BagBrokerMailPanelScroll", f, "UIPanelScrollFrameTemplate")
	scroll:SetPoint("TOPLEFT", 10, -80)
	scroll:SetPoint("BOTTOMRIGHT", -30, 74)
	local content = CreateFrame("Frame", nil, scroll)
	content:SetSize(WIDTH - 46, 1)
	scroll:SetScrollChild(content)
	self.content = content

	self.summary = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	self.summary:SetPoint("BOTTOMLEFT", 12, 54)
	self.summary:SetPoint("BOTTOMRIGHT", -12, 54)
	self.summary:SetJustifyH("LEFT")
	self.status = f:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
	self.status:SetPoint("BOTTOMLEFT", 12, 38)
	self.status:SetPoint("BOTTOMRIGHT", -12, 38)
	self.status:SetJustifyH("LEFT")
	self.status:SetWordWrap(false)

	local attach = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
	attach:SetSize(170, 22)
	attach:SetPoint("BOTTOMRIGHT", -10, 10)
	attach:SetScript("OnClick", function() self:Attach() end)
	self.attachButton = attach

	f:SetScript("OnShow", function()
		self.muleBox:SetText(self:Mule())
		self:Rebuild()
	end)
	return f
end

function Mail:Rebuild()
	if not self.frame or not self.frame:IsShown() then return end
	self:BuildRows()
	self:Refresh()
end

function Mail:Refresh()
	local f = self.frame
	if not f or not f:IsShown() then return end
	local stacks, items, value = 0, 0, 0
	for i, row in ipairs(self.rows) do
		local rf = self.rowFrames[i] or self:CreateRow(i)
		rf.row = row
		rf.check:SetChecked(row.checked)
		rf.icon:SetTexture(row.icon)
		local stackText = #row.slots > 1 and (" (%d stacks)"):format(#row.slots) or ""
		rf.name:SetText(ns.QualityColor(row.quality) .. (row.name or "?") .. "|r" .. (row.count > 1 and (" x" .. row.count) or "") .. stackText)
		if row.net then rf.value:SetAmount(row.value) else rf.value:SetLabel("|cff808080no auction data|r") end
		rf:Show()
		if row.checked then
			stacks = stacks + #row.slots
			items = items + 1
			value = value + row.value
		end
	end
	for i = #self.rows + 1, #self.rowFrames do
		self.rowFrames[i]:Hide()
		self.rowFrames[i].row = nil
	end
	self.content:SetHeight(math.max(1, #self.rows * ROW_HEIGHT))
	self.allCheck:SetChecked(#self.rows > 0 and items == #self.rows)
	local free = SendMailFrame and #self:FreeAttachmentSlots() or MaxAttachments()
	local mails = math.ceil(stacks / MaxAttachments())
	self.summary:SetText(("%d item(s) in %d stack(s), %s auction net; %d mail(s)"):format(items, stacks, ns.FormatMoney(value), mails))
	self.attachButton:SetText(("Attach %d of %d stacks"):format(math.min(stacks, free), stacks))
	self.attachButton:SetEnabled(stacks > 0 and free > 0)
	self.status:SetText(self.message or "")
end

function BagBroker_ToggleMailPanel()
	local f = Mail:Create()
	if f then f:SetShown(not f:IsShown()) end
end

ns:RegisterEvent("MAIL_SHOW", function()
	C_Timer.After(0.1, function()
		local f = Mail:Create()
		if not f then return end
		Mail.message = nil
		if f:IsShown() then Mail:Rebuild() else f:Show() end
	end)
end)

ns:RegisterEvent("MAIL_SEND_SUCCESS", function()
	Mail.message = "Sent. Attach the next stacks if any remain."
	C_Timer.After(0.5, function() Mail:Rebuild() end)
end)

ns:RegisterEvent("BAG_UPDATE_DELAYED", function()
	if Mail.frame and Mail.frame:IsShown() then
		C_Timer.After(0.2, function() Mail:Rebuild() end)
	end
end)
