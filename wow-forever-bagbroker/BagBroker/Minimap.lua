-- BagBroker: minimap button (left click: heatmap, right click: mob loot tooltips,
-- shift click: auction selling panel, ctrl click: farming spots, drag: move around the minimap).
local _, ns = ...

local Mini = {}
ns.Minimap = Mini

function Mini:UpdatePosition()
	local b = self.button
	if not b then return end
	local angle = math.rad(ns.settings.minimapAngle or 215)
	local radius = (Minimap:GetWidth() / 2) + 10
	b:ClearAllPoints()
	b:SetPoint("CENTER", Minimap, "CENTER", math.cos(angle) * radius, math.sin(angle) * radius)
end

function Mini:Create()
	if self.button or not Minimap then return end
	local b = CreateFrame("Button", "BagBrokerMinimapButton", Minimap)
	b:SetSize(31, 31)
	b:SetFrameStrata("MEDIUM")
	b:SetFrameLevel(8)
	b:RegisterForClicks("LeftButtonUp", "RightButtonUp")
	b:RegisterForDrag("LeftButton")
	b:SetHighlightTexture("Interface\\Minimap\\UI-Minimap-ZoomButton-Highlight")

	local background = b:CreateTexture(nil, "BACKGROUND")
	background:SetSize(20, 20)
	background:SetTexture("Interface\\Minimap\\UI-Minimap-Background")
	background:SetPoint("TOPLEFT", 7, -5)
	local icon = b:CreateTexture(nil, "ARTWORK")
	icon:SetSize(17, 17)
	icon:SetTexture("Interface\\Icons\\INV_Misc_Coin_02")
	icon:SetPoint("TOPLEFT", 7, -6)
	local border = b:CreateTexture(nil, "OVERLAY")
	border:SetSize(53, 53)
	border:SetTexture("Interface\\Minimap\\MiniMap-TrackingBorder")
	border:SetPoint("TOPLEFT")

	b:SetScript("OnClick", function(_, button)
		if IsControlKeyDown and IsControlKeyDown() then
			BagBroker_ToggleFarmSpots()
		elseif IsShiftKeyDown() then
			BagBroker_ToggleAuctionPanel()
		elseif button == "RightButton" then
			ns.settings.mobTooltips = not ns.settings.mobTooltips
			ns:Print("Mob loot tooltips " .. (ns.settings.mobTooltips and "on" or "off") .. ".")
		else
			BagBroker_ToggleHeatmap()
		end
	end)
	b:SetScript("OnDragStart", function(self)
		self:SetScript("OnUpdate", function()
			local mx, my = Minimap:GetCenter()
			local cx, cy = GetCursorPosition()
			local scale = Minimap:GetEffectiveScale()
			ns.settings.minimapAngle = math.deg(math.atan2(cy / scale - my, cx / scale - mx))
			Mini:UpdatePosition()
		end)
	end)
	b:SetScript("OnDragStop", function(self) self:SetScript("OnUpdate", nil) end)
	b:SetScript("OnEnter", function(self)
		GameTooltip:SetOwner(self, "ANCHOR_LEFT")
		GameTooltip:AddLine("BagBroker")
		GameTooltip:AddLine("Left click: loot heatmap", 1, 1, 1)
		GameTooltip:AddLine("Right click: mob loot tooltips (" .. (ns.settings.mobTooltips and "on" or "off") .. ")", 1, 1, 1)
		GameTooltip:AddLine("Shift click: auction selling panel", 1, 1, 1)
		GameTooltip:AddLine("Ctrl click: farming spots for your level and professions", 1, 1, 1)
		GameTooltip:AddLine("Drag: move this button", 0.6, 0.6, 0.6)
		GameTooltip:Show()
	end)
	b:SetScript("OnLeave", function() GameTooltip:Hide() end)

	self.button = b
	self:UpdatePosition()
	b:SetShown(ns.settings.showMinimap)
end

function Mini:SetShown(shown)
	ns.settings.showMinimap = shown and true or false
	if shown then self:Create() end
	if self.button then self.button:SetShown(ns.settings.showMinimap) end
end

ns:RegisterEvent("PLAYER_LOGIN", function()
	if ns.settings.showMinimap then Mini:Create() end
end)
