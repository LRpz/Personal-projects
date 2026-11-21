-- Grimoire: what the character can cast, read out of combat from the spellbook and tooltips
-- (duration, damage and cooldown at the current rank), and where each spell sits on the action
-- bars (button and key), so the assistant can name the key and light up the button.
local _, ns = ...

local Spells = { known = {}, info = {}, buttons = {}, overlays = {} }
ns.Spells = Spells

-- Every spell the assistant reasons about.
local TRACKED = { "Shadow Bolt", "Drain Life", "Drain Soul", "Life Tap", "Health Funnel", "Death Coil",
	"Howl of Terror", "Shoot", "Seduction", "Fear", "Suffering", "Sacrifice", "Spell Lock", "Searing Pain",
	"Shadowburn", "Conflagrate", "Incinerate", "Amplify Curse", "Soul Fire" }
for _, dot in ipairs(ns.DOTS) do TRACKED[#TRACKED + 1] = dot.spell end

local FALLBACK_DURATION = { ["Drain Life"] = 5, ["Drain Soul"] = 15, ["Health Funnel"] = 10 }

function ns.SpellName(spellID)
	if spellID == nil or ns.IsSecret(spellID) then return nil end
	if C_Spell and C_Spell.GetSpellName then
		local name = C_Spell.GetSpellName(spellID)
		if name and not ns.IsSecret(name) then return name end
	end
	local info = C_Spell and C_Spell.GetSpellInfo and C_Spell.GetSpellInfo(spellID)
	if type(info) == "table" and info.name and not ns.IsSecret(info.name) then return info.name end
	return nil
end

local function Number(text) return tonumber((text:gsub(",", ""))) end

-- Damage over time and duration from a tooltip description, e.g. "causing 40 Shadow damage over
-- 12 sec" or "Transfers 15 health from the target to the caster every 3 sec. Lasts 30 sec."
function Spells.ParseDescription(text)
	if type(text) ~= "string" or ns.IsSecret(text) or text == "" then return nil, nil end
	local damage, duration
	for amount, secs in text:gmatch("([%d,]+) %a+ damage over ([%d%.]+) sec") do
		damage, duration = Number(amount), tonumber(secs)
	end
	if not damage then
		local per, every, secs = text:match("([%d,]+) health.-every ([%d%.]+) sec.-([%d%.]+) sec")
		if per and tonumber(every) and tonumber(every) > 0 then
			damage, duration = Number(per) * tonumber(secs) / tonumber(every), tonumber(secs)
		end
	end
	if not damage then
		-- direct damage: "for 91 to 104 Shadow damage" (average) or "for 120 Shadow damage"
		local low, high = text:match("([%d,]+) to ([%d,]+) %a+ damage")
		if low then
			damage = (Number(low) + Number(high)) / 2
		else
			local amount = text:match("([%d,]+) %a+ damage")
			damage = amount and Number(amount) or nil
		end
		if damage then return damage, duration end
	end
	if not duration then
		for secs in text:gmatch("([%d%.]+) sec") do
			local v = tonumber(secs)
			if v and (not duration or v > duration) then duration = v end
		end
		local mins = text:match("([%d%.]+) min")
		if mins and tonumber(mins) then duration = math.max(duration or 0, tonumber(mins) * 60) end
	end
	return damage, duration
end

-- Pet abilities count while a demon is out and the client knows the spell.
local function PetSpell(name)
	if not UnitExists("pet") then return nil end
	local info = C_Spell and C_Spell.GetSpellInfo and C_Spell.GetSpellInfo(name)
	if type(info) == "table" and info.spellID then return info.spellID, info.iconID end
	return nil
end

local PET_SPELLS = { Seduction = true, Suffering = true, Sacrifice = true, ["Spell Lock"] = true,
	["Devour Magic"] = true, ["Fire Shield"] = true }

function Spells.IsPetSpell(name) return PET_SPELLS[name] or false end

-- Rebuilds the known spells with their tooltip values. Call out of combat (tooltips are static).
function Spells:Refresh()
	wipe(self.known)
	for _, name in ipairs(TRACKED) do
		local id, icon
		if PET_SPELLS[name] then id, icon = PetSpell(name) else id, icon = ns.KnownSpell(name) end
		if id then
			self.known[name] = true
			local desc = C_Spell and C_Spell.GetSpellDescription and C_Spell.GetSpellDescription(id)
			local damage, duration = self.ParseDescription(desc)
			local base = ns.DOT_BY_NAME[name] or ns.CONTROL[name] or {}
			local cooldown = GetSpellBaseCooldown and GetSpellBaseCooldown(id)
			if ns.IsSecret(cooldown) then cooldown = nil end
			local cost = type(desc) == "string" and not ns.IsSecret(desc) and desc:match("([%d,]+) health into") or nil
			self.info[name] = {
				id = id, icon = icon, healthCost = cost and tonumber((cost:gsub(",", ""))) or nil,
				duration = duration or base.duration or FALLBACK_DURATION[name],
				damage = damage or base.damage,
				cooldown = cooldown and cooldown > 1500 and cooldown / 1000 or nil,
			}
		end
	end
end

function Spells:Known(name) return self.known[name] or false end
function Spells:Icon(name) return self.info[name] and self.info[name].icon or 134400 end
function Spells:Duration(name) return self.info[name] and self.info[name].duration or 0 end
function Spells:Damage(name) return self.info[name] and self.info[name].damage or 0 end
function Spells:Cooldown(name) return self.info[name] and self.info[name].cooldown or 0 end

---------------------------------------------------------------------------
-- Action bars: which button holds a spell, its key, and a glow on it
---------------------------------------------------------------------------
local BARS = {
	{ "ActionButton", "ACTIONBUTTON" }, { "MultiBarBottomLeftButton", "MULTIACTIONBAR1BUTTON" },
	{ "MultiBarBottomRightButton", "MULTIACTIONBAR2BUTTON" }, { "MultiBarRightButton", "MULTIACTIONBAR3BUTTON" },
	{ "MultiBarLeftButton", "MULTIACTIONBAR4BUTTON" }, { "MultiBar5Button", "MULTIACTIONBAR5BUTTON" },
	{ "MultiBar6Button", "MULTIACTIONBAR6BUTTON" }, { "MultiBar7Button", "MULTIACTIONBAR7BUTTON" },
}

-- Short key text: SHIFT-3 -> s3, CTRL-F -> cF, ALT-BUTTON4 -> aM4.
function ns.ShortKey(key)
	if not key then return nil end
	return (key:gsub("SHIFT%-", "s"):gsub("CTRL%-", "c"):gsub("ALT%-", "a"):gsub("BUTTON", "M")
		:gsub("MOUSEWHEELUP", "WU"):gsub("MOUSEWHEELDOWN", "WD"):gsub("NUMPAD", "N"))
end

function Spells:ScanBars()
	wipe(self.buttons)
	if not (GetActionInfo and HasAction) then return end
	for _, bar in ipairs(BARS) do
		for i = 1, 12 do
			local button = _G[bar[1] .. i]
			local slot = button and (button.action or (button.GetAttribute and button:GetAttribute("action")))
			if type(slot) == "number" and HasAction(slot) then
				local kind, id = GetActionInfo(slot)
				if kind == "macro" and GetMacroSpell then id = GetMacroSpell(id) end
				local name = (kind == "spell" or kind == "macro") and ns.SpellName(id)
				if name and not self.buttons[name] then
					self.buttons[name] = { button = button, key = GetBindingKey and GetBindingKey(bar[2] .. i) }
				end
			end
		end
	end
	if not InCombatLockdown() then self:CreateOverlays() end
end

function Spells:KeyFor(name)
	local entry = self.buttons[name]
	return entry and ns.ShortKey(entry.key) or nil
end

-- Glow frames are our own, parented to UIParent and anchored out of combat; in combat they are
-- only shown and hidden, so Blizzard's secure buttons are never touched.
function Spells:CreateOverlays()
	for _, entry in pairs(self.buttons) do
		local button = entry.button
		if not self.overlays[button] then
			local glow = CreateFrame("Frame", nil, UIParent)
			glow:SetAllPoints(button)
			glow:SetFrameStrata(button.GetFrameStrata and button:GetFrameStrata() or "MEDIUM")
			glow:SetFrameLevel((button.GetFrameLevel and button:GetFrameLevel() or 1) + 5)
			local tex = glow:CreateTexture(nil, "OVERLAY")
			tex:SetPoint("TOPLEFT", -6, 6)
			tex:SetPoint("BOTTOMRIGHT", 6, -6)
			tex:SetTexture("Interface\\Buttons\\CheckButtonHilight")
			tex:SetBlendMode("ADD")
			tex:SetVertexColor(0.75, 0.55, 1)
			glow.texture = tex
			glow:Hide()
			self.overlays[button] = glow
		end
	end
end

function Spells:Glow(name)
	local entry = name and self.buttons[name]
	local target = entry and self.overlays[entry.button]
	for _, glow in pairs(self.overlays) do
		if glow ~= target and glow:IsShown() then glow:Hide() end
	end
	if target and ns.settings.buttonGlow and entry.button:IsVisible() then
		target:Show()
		target.texture:SetAlpha(0.55 + 0.45 * math.abs(math.sin(GetTime() * 4)))
	elseif target then
		target:Hide()
	end
end

local function Rescan()
	Spells:ScanBars()
	if ns.Assist then ns.Assist:RequestUpdate() end
end

ns:On("LOGIN", function()
	if not ns.isWarlock then return end
	Spells:Refresh()
	Spells:ScanBars()
end)
ns:RegisterEvent("SPELLS_CHANGED", function()
	if not ns.isWarlock or InCombatLockdown() then return end
	Spells:Refresh()
	Rescan()
end)
ns:RegisterEvent("UNIT_PET", function(_, unit)
	if unit == "player" and ns.isWarlock and not InCombatLockdown() then Spells:Refresh() end
end)
ns:RegisterEvent("ACTIONBAR_SLOT_CHANGED", function() if ns.isWarlock then Rescan() end end)
ns:RegisterEvent("UPDATE_BINDINGS", function() if ns.isWarlock then Rescan() end end)
ns:RegisterEvent("PLAYER_REGEN_ENABLED", function()
	if ns.isWarlock then
		Spells:Refresh()
		Spells:CreateOverlays()
	end
end)
