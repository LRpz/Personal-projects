-- BagBroker: vendor selling.
-- Items are sold when the vendor price is at least the auction net (price minus the 5% cut and the
-- deposit); unbound bind-on-equip items only when "Include bind-on-equip" is on (see
-- ns:ShouldVendor for the full rule set). A small panel next to the merchant window holds the
-- options and a "Sell now" button. Hold Shift while opening a merchant to skip automatic selling.
local _, ns = ...

local Vendor = {}
ns.Vendor = Vendor

local SELL_INTERVAL = 0.15

function Vendor:BuildList()
	local list = {}
	ns:ForEachBagSlot(function(bag, slot)
		local info = ns:GetSlotInfo(bag, slot)
		if info and not info.isLocked then
			local sell = ns:ShouldVendor(info)
			if sell then list[#list + 1] = info end
		end
	end)
	return list
end

function Vendor:Start()
	if self.ticker or not ns.merchantOpen then return end
	local list = self:BuildList()
	if #list == 0 then return end
	self.list, self.index, self.total, self.sold = list, 0, 0, {}
	self.ticker = C_Timer.NewTicker(SELL_INTERVAL, function() self:Step() end)
end

function Vendor:Stop()
	if self.ticker then
		self.ticker:Cancel()
		self.ticker = nil
	end
end

function Vendor:Step()
	if not ns.merchantOpen then
		self:Finish()
		return
	end
	self.index = self.index + 1
	local item = self.list[self.index]
	if not item then
		self:Finish()
		return
	end
	-- Re-check the slot: the player may have moved or used the item since the list was built.
	local current = C_Container.GetContainerItemInfo(item.bag, item.slot)
	if current and current.itemID == item.itemID and not current.isLocked then
		C_Container.UseContainerItem(item.bag, item.slot)
		self.total = self.total + item.sellPrice * (current.stackCount or 1)
		self.sold[#self.sold + 1] = current.hyperlink or item.link
	end
end

function Vendor:Finish()
	self:Stop()
	local sold = self.sold or {}
	if #sold > 0 then
		local detail = #sold <= 8 and (": " .. table.concat(sold, ", ")) or ""
		ns:Print(("Sold %d item(s) for %s%s"):format(#sold, ns.FormatMoney(self.total), detail))
	end
	self.list, self.sold = nil, nil
	self:RefreshPanel()
end

-- Preview used by "/bb preview": what would be sold right now, with reasons for kept items.
function Vendor:Preview()
	local sell, keep = {}, {}
	ns:ForEachBagSlot(function(bag, slot)
		local info = ns:GetSlotInfo(bag, slot)
		if info then
			local ok, reason = ns:ShouldVendor(info)
			local line = ("%s (%s)"):format(info.link or ("item:" .. info.itemID), reason)
			if ok then sell[#sell + 1] = line else keep[#keep + 1] = line end
		end
	end)
	return sell, keep
end

---------------------------------------------------------------------------
-- Panel next to the merchant window
---------------------------------------------------------------------------
local OPTIONS = {
	{ key = "autoSell", label = "Sell automatically when a merchant opens" },
	{ key = "sellBoE", label = "Include bind-on-equip items" },
	{ key = "sellSoulboundGear", label = "Include soulbound gear below your item level" },
}

function Vendor:CreatePanel()
	if self.panel then return self.panel end
	if not MerchantFrame then return nil end
	local f = ns:CreateWindow("BagBrokerVendorPanel", MerchantFrame, "BagBroker: vendor")
	f:SetSize(280, 168)
	f:SetPoint("TOPLEFT", MerchantFrame, "TOPRIGHT", 4, 0)
	f:EnableMouse(true)
	self.panel = f

	f.checks = {}
	for i, option in ipairs(OPTIONS) do
		local cb = CreateFrame("CheckButton", nil, f, "UICheckButtonTemplate")
		cb:SetSize(22, 22)
		cb:SetPoint("TOPLEFT", 10, -26 - (i - 1) * 22)
		local text = cb.Text or cb:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
		if not cb.Text then text:SetPoint("LEFT", cb, "RIGHT", 2, 0) end
		text:SetFontObject("GameFontHighlightSmall")
		text:SetText(option.label)
		cb:SetScript("OnClick", function(btn)
			ns.settings[option.key] = btn:GetChecked() and true or false
			self:RefreshPanel()
		end)
		f.checks[option.key] = cb
	end

	f.summary = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	f.summary:SetPoint("TOPLEFT", 14, -98)
	f.summary:SetPoint("TOPRIGHT", -14, -98)
	f.summary:SetJustifyH("LEFT")
	f.note = f:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
	f.note:SetPoint("TOPLEFT", 14, -114)
	f.note:SetPoint("TOPRIGHT", -14, -114)
	f.note:SetJustifyH("LEFT")
	f.note:SetText("Auction value = price - 5% cut - deposit.")

	local sell = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
	sell:SetSize(130, 22)
	sell:SetPoint("BOTTOMRIGHT", -10, 10)
	sell:SetScript("OnClick", function() self:Start() end)
	f.sell = sell
	local preview = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
	preview:SetSize(90, 22)
	preview:SetPoint("RIGHT", sell, "LEFT", -4, 0)
	preview:SetText("List in chat")
	preview:SetScript("OnClick", function() SlashCmdList.BAGBROKER("preview") end)
	f:SetScript("OnShow", function() self:RefreshPanel() end)
	return f
end

function Vendor:RefreshPanel()
	local f = self.panel
	if not f or not f:IsShown() then return end
	for key, cb in pairs(f.checks) do cb:SetChecked(ns.settings[key] and true or false) end
	local list = self:BuildList()
	local total = 0
	for _, info in ipairs(list) do total = total + (info.sellPrice or 0) * (info.count or 1) end
	f.summary:SetText(("%d stack(s) sell better to the vendor: %s"):format(#list, ns.FormatMoney(total)))
	f.sell:SetText(("Sell now (%d)"):format(#list))
	f.sell:SetEnabled(#list > 0 and not self.ticker)
end

ns:RegisterEvent("MERCHANT_SHOW", function()
	local skip = IsShiftKeyDown()
	C_Timer.After(0.3, function()
		if not ns.merchantOpen then return end
		local panel = Vendor:CreatePanel()
		if panel then
			if panel:IsShown() then Vendor:RefreshPanel() else panel:Show() end
		end
		if ns.settings.autoSell and not skip then Vendor:Start() end
	end)
end)

ns:RegisterEvent("MERCHANT_CLOSED", function()
	if Vendor.ticker then Vendor:Finish() end
end)

ns:RegisterEvent("BAG_UPDATE_DELAYED", function()
	if ns.merchantOpen and Vendor.panel and Vendor.panel:IsShown() and not Vendor.ticker then
		C_Timer.After(0.2, function() Vendor:RefreshPanel() end)
	end
end)
