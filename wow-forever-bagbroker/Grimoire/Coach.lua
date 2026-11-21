-- Grimoire: combat coach.
-- Four situation buttons (for the Voidwalker: 1 mob, 2, 3, pack of 4-5) sit at the side of the
-- screen, and one key binding drives them all (no modifier = plan 1, Shift = 2, Ctrl = 3, Alt = 4).
-- Each press casts the next step of the plan; the panel lists every step with a one-line reason and
-- highlights the next one. Steps that switch target put a raid icon on the new enemy (skull =
-- demon's target, cross/square/triangle = DoT targets, moon = feared or seduced).
--
-- Plans follow the demon that is out: Voidwalker (tanking packs), Succubus (Seduction),
-- Felhunter (casters) or Imp (one mob at a time), each with its own utility row.
--
-- What adapts, and what cannot: the game evaluates macro conditions at every press, so a step picks
-- a new enemy when the target is missing, dead or friendly, sends the demon only at a living enemy,
-- and casts only on a living enemy; plans restart when combat ends. Forever applies Midnight's addon
-- rules: in combat an addon cannot read enemy health, auras, crits, misses or the combat log, and
-- cannot change what a button casts, and Blizzard forbids automated decision-making beyond that.
-- When the client offers Blizzard's own Assisted Combat, its live suggestion is shown as well.
local _, ns = ...

local Coach = { buttons = {}, utility = {} }
ns.Coach = Coach

local PLAN_BUTTONS, UTILITY_BUTTONS = 4, 6

-- Plan set for the demon that is out (Voidwalker, Succubus/Sayaad, Felhunter, Imp, or none).
function Coach:CurrentSet()
	local family = UnitExists("pet") and UnitCreatureFamily("pet") or nil
	if ns.IsSecret(family) then family = nil end
	local key = family and (ns.PET_ALIASES[family] or family) or "none"
	self.petKey = ns.PET_PLANS[key] and key or "none"
	return ns.PET_PLANS[self.petKey]
end

function Coach:Plans() return (self.set or ns.PET_PLANS.Voidwalker).plans end

local PLAN_SIZE = 40
local ROW_HEIGHT = 18
local MAX_ROWS = 9

local SEQUENCE_SNIPPET = [[
	if button == "RightButton" then
		self:SetAttribute("index", 1)
		return false
	end
	local count = self:GetAttribute("count") or 0
	if count == 0 then return false end
	local i = self:GetAttribute("index") or 1
	if i > count then i = self:GetAttribute("loopStart") or 1 end
	self:SetAttribute("macrotext", self:GetAttribute("step" .. i))
	self:SetAttribute("index", i + 1)
]]

-- Known spell check; Voidwalker abilities count when the spell exists and a demon is out.
function Coach.Available(step, level)
	if step.maxLevel and level > step.maxLevel then return nil end
	if step.petSpell then
		local info = C_Spell and C_Spell.GetSpellInfo and C_Spell.GetSpellInfo(step.spell)
		if info and UnitExists("pet") then return info.spellID, info.iconID end
		return nil
	end
	return ns.KnownSpell(step.spell)
end

-- Spells cast without an enemy target (self, demon or area).
local UNTARGETED = { ["Health Funnel"] = true, ["Life Tap"] = true, ["Sacrifice"] = true, ["Suffering"] = true,
	["Fire Shield"] = true, ["Howl of Terror"] = true, ["Devour Magic"] = false }

-- The game evaluates these macro conditions itself at each press: pick an enemy when the target
-- is missing, dead or friendly; send the demon only at a living enemy; cast only at a living enemy.
function Coach.MacroText(step)
	local lines = {}
	if step.next then
		lines[#lines + 1] = "/targetenemy"
	else
		lines[#lines + 1] = "/targetenemy [noexists][dead][noharm]"
	end
	if step.mark then lines[#lines + 1] = "/tm " .. step.mark end
	if step.pet == "attack" then lines[#lines + 1] = "/petattack [@target,harm,nodead]" end
	if UNTARGETED[step.spell] then
		lines[#lines + 1] = "/cast " .. step.spell
	else
		lines[#lines + 1] = "/cast [@target,harm,nodead] " .. step.spell
	end
	return table.concat(lines, "\n")
end

-- One key for every plan: no modifier = plan 1, Shift = 2, Ctrl = 3, Alt = 4.
Coach.ROUTER_MACRO = "/click [mod:alt] GrimoirePlan4; [mod:ctrl] GrimoirePlan3; [mod:shift] GrimoirePlan2; GrimoirePlan1"

-- Fills a plan button's attributes with the steps the character can cast. Out of combat only.
function Coach:BuildPlan(plan, button)
	local level = UnitLevel("player") or 1
	local steps = {}
	for _, part in ipairs({ "opener", "loop" }) do
		for _, step in ipairs(plan[part]) do
			local spellID, icon = self.Available(step, level)
			if spellID then
				steps[#steps + 1] = { spell = step.spell, text = step.text, mark = step.mark, icon = icon,
					loop = part == "loop", macro = self.MacroText(step) }
			end
		end
	end
	local loopStart = #steps + 1
	for i, step in ipairs(steps) do
		if step.loop then loopStart = i break end
	end
	for i = 1, 16 do button:SetAttribute("step" .. i, steps[i] and steps[i].macro or nil) end
	button:SetAttribute("count", #steps)
	button:SetAttribute("loopStart", math.min(loopStart, math.max(1, #steps)))
	button:SetAttribute("index", 1)
	plan.steps = steps
end

function Coach:Build()
	if InCombatLockdown() then
		self.pendingBuild = true
		return
	end
	self.pendingBuild = false
	if not self.frame then return end
	self.set = self:CurrentSet()
	for i = 1, PLAN_BUTTONS do
		local plan = self.set.plans[i]
		local b = self.buttons[i]
		if plan then
			self:BuildPlan(plan, b)
			b.label:SetText(plan.label)
			b:Show()
		else
			b:SetAttribute("count", 0)
			b:Hide()
		end
	end
	local level = UnitLevel("player") or 1
	for i, u in ipairs(self.utility) do
		u.data = self.set.utility[i]
		local spellID, icon
		if u.data then spellID, icon = self.Available(u.data, level) end
		u.button:SetAttribute("macrotext", spellID and ("/cast " .. u.data.spell) or nil)
		u.icon:SetTexture(icon or 134400)
		u.icon:SetDesaturated(not spellID)
		u.button:SetShown(u.data ~= nil)
	end
	self.frame.advice:SetText(self.set.advice)
	self:RefreshButtons()
	self:ShowPlan(self.activePlan or 1)
end

-- Index of the step the next press will cast.
function Coach:NextIndex(planIndex)
	local b = self.buttons[planIndex]
	local plan = self:Plans()[planIndex]
	if not plan then return nil end
	local count = #(plan.steps or {})
	if count == 0 then return nil end
	local i = b:GetAttribute("index") or 1
	if i > count then i = b:GetAttribute("loopStart") or 1 end
	return i
end

function Coach:RefreshButtons()
	for i, plan in ipairs(self:Plans()) do
		local b = self.buttons[i]
		if not b then break end
		local nextIndex = self:NextIndex(i)
		local step = nextIndex and plan.steps[nextIndex]
		b.icon:SetTexture(step and step.icon or 134400)
		b.icon:SetDesaturated(step == nil)
		local key = GetBindingKey and GetBindingKey("CLICK " .. b:GetName() .. ":LeftButton")
		b.hotkey:SetText(key or "")
	end
end

function Coach:ShowPlan(planIndex)
	local plan = self:Plans()[planIndex]
	if not plan then
		planIndex = 1
		plan = self:Plans()[1]
	end
	self.activePlan = planIndex
	local f = self.frame
	f.planTitle:SetText(plan.title)
	local nextIndex = self:NextIndex(planIndex)
	local steps = plan.steps or {}
	for r = 1, MAX_ROWS do
		local row = f.rows[r]
		local step = steps[r]
		if step then
			row.icon:SetTexture(step.icon)
			local marker = step.mark and (ns.MARKERS[step.mark] .. " ") or ""
			local prefix = step.loop and "|cff9482c9repeat|r " or (r .. ". ")
			row.text:SetText(prefix .. marker .. step.text)
			row.highlight:SetShown(r == nextIndex)
			row:Show()
		else
			row:Hide()
		end
	end
	if #steps == 0 then
		f.rows[1].icon:SetTexture(nil)
		f.rows[1].text:SetText("|cff808080No step available yet: learn the spells of this plan.|r")
		f.rows[1].highlight:Hide()
		f.rows[1]:Show()
	end
	f.tip:SetText(plan.tip)
end

function Coach:OnPlanClicked(planIndex)
	self:ShowPlan(planIndex)
	self:RefreshButtons()
end

---------------------------------------------------------------------------
-- Frame
---------------------------------------------------------------------------
local function Border(button)
	local border = button:CreateTexture(nil, "OVERLAY")
	border:SetPoint("TOPLEFT", -2, 2)
	border:SetPoint("BOTTOMRIGHT", 2, -2)
	border:SetColorTexture(0.58, 0.51, 0.79, 0.35)
	border:SetDrawLayer("BACKGROUND")
end

function Coach:CreatePlanButton(f, index)
	local b = CreateFrame("Button", "GrimoirePlan" .. index, f, "SecureActionButtonTemplate, SecureHandlerStateTemplate")
	b:SetSize(PLAN_SIZE, PLAN_SIZE)
	b:SetPoint("TOPLEFT", 14 + (index - 1) * (PLAN_SIZE + 26), -30)
	b:RegisterForClicks("AnyUp")
	b:SetAttribute("type", "macro")
	Border(b)
	b.icon = b:CreateTexture(nil, "ARTWORK")
	b.icon:SetAllPoints()
	b.label = b:CreateFontString(nil, "OVERLAY", "GameFontNormal")
	b.label:SetPoint("TOP", b, "BOTTOM", 0, -2)
	b.hotkey = b:CreateFontString(nil, "OVERLAY", "NumberFontNormalSmallGray")
	b.hotkey:SetPoint("TOPRIGHT", -1, -2)
	b:SetHighlightTexture("Interface\\Buttons\\ButtonHilight-Square")
	SecureHandlerWrapScript(b, "OnClick", b, SEQUENCE_SNIPPET)
	b:SetAttribute("_onstate-combat", [[ if newstate == "0" then self:SetAttribute("index", 1) end ]])
	RegisterStateDriver(b, "combat", "[combat] 1; 0")
	b:HookScript("PostClick", function() Coach:OnPlanClicked(index) end)
	b:HookScript("OnEnter", function(self)
		local plan = Coach:Plans()[index]
		if not plan then return end
		Coach:ShowPlan(index)
		GameTooltip:SetOwner(self, "ANCHOR_LEFT")
		GameTooltip:AddLine(plan.title)
		GameTooltip:AddLine(plan.tip, 1, 1, 1, true)
		GameTooltip:AddLine("Click: next step. Right-click: restart. Resets when combat ends.", 0.6, 0.6, 0.6, true)
		GameTooltip:Show()
	end)
	b:HookScript("OnLeave", function() GameTooltip:Hide() end)
	self.buttons[index] = b
end

function Coach:CreateUtilityButton(f, index)
	local b = CreateFrame("Button", "GrimoireUtility" .. index, f, "SecureActionButtonTemplate")
	b:SetSize(28, 28)
	b:SetPoint("BOTTOMLEFT", 14 + (index - 1) * 32, 12)
	b:RegisterForClicks("AnyUp")
	b:SetAttribute("type", "macro")
	Border(b)
	local icon = b:CreateTexture(nil, "ARTWORK")
	icon:SetAllPoints()
	b:SetHighlightTexture("Interface\\Buttons\\ButtonHilight-Square")
	local entry = { button = b, icon = icon }
	b:HookScript("OnEnter", function(self)
		local data = entry.data
		if not data then return end
		GameTooltip:SetOwner(self, "ANCHOR_LEFT")
		GameTooltip:AddLine(data.spell)
		GameTooltip:AddLine(data.text, 1, 1, 1, true)
		GameTooltip:Show()
	end)
	b:HookScript("OnLeave", function() GameTooltip:Hide() end)
	self.utility[index] = entry
end

function Coach:Create()
	if self.frame then return self.frame end
	local f = ns:CreateWindow("GrimoireCoach", UIParent, "Grimoire coach")
	f:SetSize(14 + PLAN_BUTTONS * (PLAN_SIZE + 26) + 6, 154 + MAX_ROWS * ROW_HEIGHT + 86)
	f:SetPoint("RIGHT", UIParent, "RIGHT", -40, 40)
	f:SetClampedToScreen(true)
	f:SetMovable(true)
	f:EnableMouse(true)
	f:RegisterForDrag("LeftButton")
	f:SetScript("OnDragStart", function(self) if not InCombatLockdown() then self:StartMoving() end end)
	f:SetScript("OnDragStop", f.StopMovingOrSizing)
	f:SetScale(ns.settings.coachScale or 1)
	self.frame = f

	for i = 1, PLAN_BUTTONS do self:CreatePlanButton(f, i) end

	f.advice = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	f.advice:SetPoint("TOPLEFT", 14, -94)
	f.advice:SetPoint("TOPRIGHT", -14, -94)
	f.advice:SetJustifyH("LEFT")
	f.advice:SetTextColor(0.75, 0.68, 0.95)
	f.planTitle = f:CreateFontString(nil, "OVERLAY", "GameFontNormal")
	f.planTitle:SetPoint("TOPLEFT", 14, -116)
	f.rows = {}
	for r = 1, MAX_ROWS do
		local row = CreateFrame("Frame", nil, f)
		row:SetSize(f:GetWidth() - 24, ROW_HEIGHT)
		row:SetPoint("TOPLEFT", 12, -134 - (r - 1) * ROW_HEIGHT)
		row.highlight = row:CreateTexture(nil, "BACKGROUND")
		row.highlight:SetAllPoints()
		row.highlight:SetColorTexture(0.58, 0.51, 0.79, 0.30)
		row.icon = row:CreateTexture(nil, "ARTWORK")
		row.icon:SetSize(16, 16)
		row.icon:SetPoint("LEFT", 2, 0)
		row.text = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
		row.text:SetPoint("LEFT", row.icon, "RIGHT", 4, 0)
		row.text:SetPoint("RIGHT", -2, 0)
		row.text:SetJustifyH("LEFT")
		row.text:SetWordWrap(false)
		f.rows[r] = row
	end
	f.tip = f:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
	f.tip:SetPoint("TOPLEFT", 14, -138 - MAX_ROWS * ROW_HEIGHT)
	f.tip:SetPoint("TOPRIGHT", -14, -138 - MAX_ROWS * ROW_HEIGHT)
	f.tip:SetJustifyH("LEFT")
	f.tip:SetHeight(28)
	for i = 1, UTILITY_BUTTONS do self:CreateUtilityButton(f, i) end

	-- One-key router (bind "Coach: one key for all plans"); invisible, driven by its binding.
	local router = CreateFrame("Button", "GrimoireMain", f, "SecureActionButtonTemplate")
	router:SetSize(1, 1)
	router:RegisterForClicks("AnyUp")
	router:SetAttribute("type", "macro")
	router:SetAttribute("macrotext", self.ROUTER_MACRO)
	self.router = router

	f.oneKey = f:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
	f.oneKey:SetPoint("BOTTOMLEFT", 14, 44)
	f.oneKey:SetPoint("BOTTOMRIGHT", -14, 44)
	f.oneKey:SetJustifyH("LEFT")

	-- Blizzard's own rotation assistant, when the client offers it.
	f.assist = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	f.assist:SetPoint("BOTTOMLEFT", 14, 58)
	f.assist:SetPoint("BOTTOMRIGHT", -14, 58)
	f.assist:SetJustifyH("LEFT")
	local elapsed = 0
	f:HookScript("OnUpdate", function(_, dt)
		elapsed = elapsed + dt
		if elapsed < 0.25 then return end
		elapsed = 0
		Coach:UpdateAssistant()
	end)
	return f
end

-- Shows Blizzard's Assisted Combat suggestion (the game decides; Grimoire only displays it).
function Coach:AssistantSuggestion()
	if not (C_AssistedCombat and C_AssistedCombat.IsAvailable and C_AssistedCombat.GetNextCastSpell) then return nil end
	local ok, available = pcall(C_AssistedCombat.IsAvailable)
	if not ok or not available or ns.IsSecret(available) then return nil end
	local okNext, spellID = pcall(C_AssistedCombat.GetNextCastSpell, false)
	if not okNext or not spellID or ns.IsSecret(spellID) then return false end
	local info = C_Spell.GetSpellInfo(spellID)
	return info and info.name, info and info.iconID
end

function Coach:UpdateAssistant()
	local f = self.frame
	if not f then return end
	local name, icon = self:AssistantSuggestion()
	if name == nil then
		f.assist:SetText("")
	elseif name == false then
		f.assist:SetText("|cff9482c9Blizzard assistant|r: available (Single-Button Assistant spell in your spellbook)")
	else
		f.assist:SetText(("|cff9482c9Blizzard assistant suggests|r: |T%s:0|t %s"):format(icon or 134400, name))
	end
	local key = GetBindingKey and GetBindingKey("CLICK GrimoireMain:LeftButton")
	f.oneKey:SetText(("One key%s: plan 1, Shift = 2, Ctrl = 3, Alt = 4"):format(key and (" [" .. key .. "]") or " (bind it in Key Bindings)"))
end

function Coach:SetShown(shown)
	if InCombatLockdown() then
		ns:Print("The coach can only be shown or hidden out of combat.")
		return
	end
	ns.settings.coachShown = shown and true or false
	local f = self:Create()
	f:SetShown(ns.settings.coachShown)
	if ns.settings.coachShown then self:Build() end
end

function Grimoire_ToggleCoach()
	Coach:SetShown(not ns.settings.coachShown)
end

ns:On("LOGIN", function()
	if not ns.isWarlock then return end
	Coach:Create()
	Coach.frame:SetShown(ns.settings.coachShown)
	Coach:Build()
end)

local function Rebuild()
	if ns.isWarlock and Coach.frame then Coach:Build() end
end
ns:RegisterEvent("SPELLS_CHANGED", Rebuild)
ns:RegisterEvent("PLAYER_LEVEL_UP", function() C_Timer.After(1, Rebuild) end)
ns:RegisterEvent("UNIT_PET", function(_, unit) if unit == "player" then Rebuild() end end)
ns:RegisterEvent("UPDATE_BINDINGS", function() if Coach.frame then Coach:RefreshButtons() end end)
ns:RegisterEvent("PLAYER_REGEN_ENABLED", function()
	if Coach.pendingBuild then Coach:Build() end
	if Coach.frame then
		C_Timer.After(0.1, function()
			Coach:RefreshButtons()
			Coach:ShowPlan(Coach.activePlan or 1)
		end)
	end
end)
