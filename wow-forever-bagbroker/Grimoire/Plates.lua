-- Grimoire: spell queues on enemy nameplates.
-- Above each enemy in the fight: the spells to cast on it, in order (they disappear as they land
-- and come back when a refresh is due), the DoTs running on it (green bar: confirmed by a tick,
-- grey: waiting for the first tick), and a note: "resisted", "Fear broken", "dies" (your DoTs
-- finish it, no more casts needed) or the time left on Fear. The enemy to act on next glows,
-- marked NOW (your target) or NEXT (switch to it: Tab or click it).
local _, ns = ...
local Spells = ns.Spells

local Plates = { widgets = {} }
ns.Plates = Plates

local QUEUE, ACTIVE = 4, 5
local SKULL = "|TInterface\\TargetingFrame\\UI-RaidTargetingIcon_8:0|t"

local curves = {}
local function Curve(key, threshold, below, above)
	if curves[key] == nil then curves[key] = ns.StepCurve(threshold, below, above) or false end
	return curves[key] or nil
end

local function PlateFor(token)
	if not (C_NamePlate and C_NamePlate.GetNamePlateForUnit) then return nil end
	local ok, plate = pcall(C_NamePlate.GetNamePlateForUnit, token)
	return ok and plate or nil
end

function Plates:Widget(plate)
	local w = self.widgets[plate]
	if w then return w end
	local anchor = plate.UnitFrame or plate
	w = CreateFrame("Frame", nil, plate)
	w:SetSize(130, 48)
	w:SetPoint("BOTTOM", anchor, "TOP", 0, 2)
	w.queue = {}
	for i = 1, QUEUE do
		local icon = w:CreateTexture(nil, "OVERLAY")
		icon:SetSize(20, 20)
		if i == 1 then icon:SetPoint("BOTTOMLEFT", w, "BOTTOMLEFT", 0, 14) else icon:SetPoint("LEFT", w.queue[i - 1], "RIGHT", 2, 0) end
		w.queue[i] = icon
	end
	w.active = {}
	for i = 1, ACTIVE do
		local icon = w:CreateTexture(nil, "OVERLAY")
		icon:SetSize(11, 11)
		if i == 1 then icon:SetPoint("BOTTOMLEFT", w, "BOTTOMLEFT", 0, 0) else icon:SetPoint("LEFT", w.active[i - 1], "RIGHT", 2, 0) end
		local bar = w:CreateTexture(nil, "OVERLAY")
		bar:SetPoint("TOPLEFT", icon, "BOTTOMLEFT", 0, -1)
		bar:SetPoint("TOPRIGHT", icon, "BOTTOMRIGHT", 0, -1)
		bar:SetHeight(2)
		icon.bar = bar
		w.active[i] = icon
	end
	w.note = w:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
	w.note:SetPoint("LEFT", w.active[ACTIVE], "RIGHT", 4, 0)
	w.label = w:CreateFontString(nil, "OVERLAY", "GameFontNormal")
	w.label:SetPoint("BOTTOMRIGHT", w, "BOTTOMRIGHT", 0, 16)
	w.glow = w:CreateTexture(nil, "BACKGROUND")
	w.glow:SetPoint("TOPLEFT", anchor, "TOPLEFT", -6, 4)
	w.glow:SetPoint("BOTTOMRIGHT", anchor, "BOTTOMRIGHT", 6, -4)
	w.glow:SetColorTexture(0.62, 0.42, 1, 0.35)
	w.soul = w:CreateTexture(nil, "OVERLAY")
	w.soul:SetSize(16, 16)
	w.soul:SetPoint("BOTTOMRIGHT", w, "BOTTOMRIGHT", 0, 0)
	self.widgets[plate] = w
	return w
end

function Plates:HideAll()
	for _, w in pairs(self.widgets) do w:Hide() end
end

local function ShowActive(w, mob, now)
	local i = 0
	for spell, dot in pairs(mob.dots) do
		if dot.expires > now and i < ACTIVE then
			i = i + 1
			local icon = w.active[i]
			icon:SetTexture(Spells:Icon(spell))
			icon.bar:SetColorTexture(dot.status == "landed" and 0.25 or 0.5, dot.status == "landed" and 0.85 or 0.5, dot.status == "landed" and 0.25 or 0.5, 1)
			icon:Show()
			icon.bar:Show()
		end
	end
	for j = i + 1, ACTIVE do
		w.active[j]:Hide()
		w.active[j].bar:Hide()
	end
	return i
end

function Plates:Update(rec)
	if not rec or not ns.settings.plateQueues then
		self:HideAll()
		return
	end
	local now = GetTime()
	local used = {}
	for _, mob in ipairs(rec.mobs) do
		local plate = mob.token and mob.token ~= "target" and PlateFor(mob.token)
		if plate then
			local w = self:Widget(plate)
			used[w] = true
			local queue = rec.queues[mob] or {}
			local status = rec.status[mob] or {}
			local isFocus = mob == rec.focus
			for i, icon in ipairs(w.queue) do
				local spell = queue[i]
				if not spell and i == 1 and isFocus and rec.spell then spell = rec.spell end
				if spell then
					icon:SetTexture(Spells:Icon(spell))
					local size = (i == 1 and isFocus) and 26 or 20
					icon:SetSize(size, size)
					local dot = ns.DOT_BY_NAME[spell]
					if status.health == nil and dot and dot.minHealthShare >= 0.5 then
						-- no health estimate yet: the game fades long DoTs on a low enemy
						ns.CurveAlpha(icon, function(c) return UnitHealthPercent(mob.token, true, c) end, Curve("long", 0.35, 0.35, 1), 1)
					else
						icon:SetAlpha(1)
					end
					icon:Show()
				else
					icon:Hide()
				end
			end
			ShowActive(w, mob, now)
			local note = ""
			if mob.flash and mob.flash.untilTime > now then
				note = "|cffff5050" .. mob.flash.text .. "|r"
			elseif status.dies then
				note = SKULL .. " |cffffd200dies|r"
			elseif mob.control and mob.control.expires > now then
				note = ("|cffbfaef2%s %ds|r"):format(mob.control.spell, math.ceil(mob.control.expires - now))
			end
			w.note:SetText(note)
			w.glow:SetShown(isFocus)
			w.label:SetText(isFocus and (rec.switch and "|cffffd200NEXT|r" or "|cff40ff40NOW|r") or "")
			-- Drain Soul reminder from the game's health curve when no estimate exists
			local shards = C_Item and C_Item.GetItemCount and ns.Readable(C_Item.GetItemCount(ns.SOUL_SHARD)) or 0
			if status.health == nil and Spells:Known("Drain Soul") and shards < (ns.settings.shardTarget or 5) then
				w.soul:SetTexture(Spells:Icon("Drain Soul"))
				w.soul:Show()
				ns.CurveAlpha(w.soul, function(c) return UnitHealthPercent(mob.token, true, c) end, Curve("soul", 0.25, 1, 0), 0)
			else
				w.soul:Hide()
			end
			w:Show()
		end
	end
	for _, w in pairs(self.widgets) do
		if not used[w] then w:Hide() end
	end
end

ns:On("ASSIST_UPDATE", function(rec) Plates:Update(rec) end)
ns:On("ASSIST_PLATE_GONE", function(token)
	local plate = PlateFor(token)
	if plate and Plates.widgets[plate] then Plates.widgets[plate]:Hide() end
end)
