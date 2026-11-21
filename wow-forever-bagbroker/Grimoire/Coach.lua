-- Grimoire: combat coach window and keys.
--
-- The window shows the assistant's live recommendation (ns.Assist): the spell to cast now, on
-- which enemy, why, and which key casts it, then what follows, the pull-size advice for your
-- demon, warnings, and two health/mana hints the game draws without telling the addon.
--
-- Four secure buttons, driven by one key binding (no modifier, Shift, Ctrl, Alt):
--   DoTs:    picks an enemy when you have none, sends the demon when it has no target, then
--            /castsequence through your DoTs and Drain Life. /castsequence only moves on when a
--            spell is actually cast (not when pressed during the global cooldown, out of range or
--            while channelling) and starts over on a new target.
--   Shift:   Drain Life (or Shadow Bolt) on the target.
--   Ctrl:    control the target: Seduction (Succubus out) or Fear.
--   Alt:     Health Funnel your demon (Death Coil without one).
-- Each press casts at most one spell, and the game checks every condition: one key press, one
-- action, as Blizzard requires. Macros are rebuilt out of combat when spells or demons change.
local _, ns = ...
local Spells = ns.Spells

local Coach = { roles = {}, utility = {} }
ns.Coach = Coach

local ROLE_SIZE, UTILITY_BUTTONS = 40, 6
local WIDTH = 14 + 4 * (ROLE_SIZE + 26) + 6

Coach.ROLES = {
	{ key = "dot", name = "GrimoireDot", label = "DoTs", mod = "" },
	{ key = "filler", name = "GrimoireFiller", label = "Drain", mod = "Shift+" },
	{ key = "control", name = "GrimoireControl", label = "Control", mod = "Ctrl+" },
	{ key = "save", name = "GrimoireSave", label = "Funnel", mod = "Alt+" },
}
Coach.ROUTER_MACRO = "/click [mod:alt] GrimoireSave; [mod:ctrl] GrimoireControl; [mod:shift] GrimoireFiller; GrimoireDot"

---------------------------------------------------------------------------
-- Macros (out of combat only)
---------------------------------------------------------------------------
function Coach.MacroDot(sequence)
	local lines = { "/targetenemy [noexists][dead][noharm]" }
	if #sequence > 0 then
		lines[#lines + 1] = "/castsequence [@target,harm,nodead,nochanneling] reset=target/combat " .. table.concat(sequence, ", ")
	end
	lines[#lines + 1] = "/stopmacro [@pettarget,exists,nodead]"
	lines[#lines + 1] = "/petattack [@target,harm,nodead]"
	return table.concat(lines, "\n")
end

function Coach.MacroFiller(spell)
	if not spell then return nil end
	return "/targetenemy [noexists][dead][noharm]\n/cast [@target,harm,nodead,nochanneling] " .. spell
end

function Coach.MacroControl(spells, family)
	local clauses = {}
	for _, spell in ipairs(spells) do
		if spell == "Seduction" then
			if family then clauses[#clauses + 1] = "[@target,harm,nodead,pet:" .. family .. "] Seduction" end
		else
			clauses[#clauses + 1] = "[@target,harm,nodead] " .. spell
		end
	end
	return #clauses > 0 and ("/cast " .. table.concat(clauses, "; ")) or nil
end

function Coach.MacroSave(funnel, coil)
	local clauses = {}
	if funnel then clauses[#clauses + 1] = "[@pet,exists,nodead,nochanneling] Health Funnel" end
	if coil then clauses[#clauses + 1] = "[@target,harm,nodead] Death Coil" end
	return #clauses > 0 and ("/cast " .. table.concat(clauses, "; ")) or nil
end

local function Known(name)
	if Spells.IsPetSpell(name) then
		if not UnitExists("pet") then return nil end
		local info = C_Spell and C_Spell.GetSpellInfo and C_Spell.GetSpellInfo(name)
		return type(info) == "table" and info.spellID or nil
	end
	return ns.KnownSpell(name)
end

function Coach:Build()
	if InCombatLockdown() then
		self.pendingBuild = true
		return
	end
	self.pendingBuild = false
	if not self.frame then return end
	local set, key, family = ns.CurrentSet()
	self.set, self.petKey, self.family = set, key, family
	local level = UnitLevel("player") or 1

	-- The DoT key follows your specialization's order, with the DoTs every enemy gets (the
	-- conditional ones, like Immolate for Affliction, are left to the assistant and your bars;
	-- spells with a cooldown would stall /castsequence). The tail fills until the first DoT is due.
	local spec = ns.Talents and ns.Talents:Spec() or "Affliction"
	self.spec = spec
	local rotation = ns.ROTATIONS[spec] or ns.ROTATIONS.Affliction
	local dots = {}
	for _, entry in ipairs(rotation.dots) do
		local def = ns.DOT_BY_NAME[entry.spell]
		if Known(entry.spell) and entry.lives <= 0.8 and not (def.maxLevel and level > def.maxLevel and spec == "Affliction") then
			dots[#dots + 1] = entry.spell
		end
	end
	local drain, bolt, wand = Known("Drain Life"), Known("Shadow Bolt"), Known("Shoot")
	local tail, tailCount
	if spec == "Destruction" then
		self.fillerSpell = bolt and "Shadow Bolt" or (drain and "Drain Life") or nil
		tail, tailCount = self.fillerSpell, 4
	elseif spec == "Demonology" and level < 30 then
		self.fillerSpell = (wand and "Shoot") or (bolt and "Shadow Bolt") or nil
		tail, tailCount = bolt and "Shadow Bolt" or nil, 3
	else
		self.fillerSpell = (drain and "Drain Life") or (bolt and "Shadow Bolt") or nil
		tail, tailCount = self.fillerSpell, 3
	end
	local sequence = {}
	for _, spell in ipairs(dots) do sequence[#sequence + 1] = spell end
	if tail then for _ = 1, tailCount do sequence[#sequence + 1] = tail end end
	self.dotSequence = sequence

	local control = {}
	for _, spell in ipairs(set.control) do
		if Known(spell) then control[#control + 1] = spell end
	end
	self.controlSpells = {}
	if control[1] then self.controlSpells[control[1]] = true end
	local funnel, coil = Known("Health Funnel") and UnitExists("pet"), Known("Death Coil")
	self.saveSpell = funnel and "Health Funnel" or (coil and "Death Coil" or nil)

	local macros = {
		dot = self.MacroDot(sequence),
		filler = self.MacroFiller(self.fillerSpell),
		control = self.MacroControl(control, family),
		save = self.MacroSave(funnel, coil),
	}
	local spells = { dot = sequence[1], filler = self.fillerSpell, control = control[1], save = self.saveSpell }
	for _, role in ipairs(self.ROLES) do
		local b = self.roles[role.key]
		b:SetAttribute("macrotext", macros[role.key])
		b.spell = spells[role.key]
		b.icon:SetTexture(b.spell and Spells:Icon(b.spell) or 134400)
		b.icon:SetDesaturated(macros[role.key] == nil)
		b.label:SetText(b.spell and (role.key == "dot" and "DoTs" or b.spell:gsub("^Health ", "")) or role.label)
	end
	for i, u in ipairs(self.utility) do
		u.data = set.utility[i]
		local id = u.data and Known(u.data.spell)
		u.button:SetAttribute("macrotext", id and ("/cast " .. u.data.spell) or nil)
		u.icon:SetTexture(id and Spells:Icon(u.data.spell) or 134400)
		u.icon:SetDesaturated(not id)
		u.button:SetShown(u.data ~= nil)
	end
	self.frame.advice:SetText(set.advice)
	self:RefreshKeys()
	if ns.Assist then ns.Assist:RequestUpdate() end
end

function Coach:RefreshKeys()
	local main = ns.ShortKey(GetBindingKey and GetBindingKey("CLICK GrimoireMain:LeftButton"))
	for _, role in ipairs(self.ROLES) do
		local b = self.roles[role.key]
		local own = ns.ShortKey(GetBindingKey and GetBindingKey("CLICK " .. role.name .. ":LeftButton"))
		b.hotkey:SetText(own or (main and (role.mod:gsub("Shift%+", "s"):gsub("Ctrl%+", "c"):gsub("Alt%+", "a") .. main)) or "")
	end
	if self.frame then
		self.frame.oneKey:SetText(main and ("One key [" .. main .. "]: DoTs, Shift drain, Ctrl control, Alt funnel")
			or "Bind \"Coach: one key\" in Key Bindings (Grimoire)")
	end
end

---------------------------------------------------------------------------
-- Live recommendation
---------------------------------------------------------------------------
local function Where(mob)
	if not mob or not mob.token then return "" end
	local name = ns.Readable(UnitName(mob.token))
	local mark = ns.Readable(GetRaidTargetIndex and GetRaidTargetIndex(mob.token))
	local icon = mark and ns.MARKERS[mark] and (ns.MARKERS[mark] .. " ") or ""
	return icon .. (name or "the glowing nameplate")
end

local curves = {}
local function Curve(key, threshold, below, above)
	if curves[key] == nil then curves[key] = ns.StepCurve(threshold, below, above) or false end
	return curves[key] or nil
end

function Coach:ShowRecommendation(rec)
	local f = self.frame
	if not f then return end
	local dotButton = self.roles.dot
	local seq = self.dotSequence or {}
	local nextDot = seq[ns.Assist and ns.Assist.seqIndex or 1]
	if nextDot then dotButton.icon:SetTexture(Spells:Icon(nextDot)) end
	if not rec or not rec.spell then
		f.nowIcon:SetTexture(134400)
		f.nowIcon:SetDesaturated(true)
		f.nowSpell:SetText(rec and rec.n > 0 and "Nothing to add" or "No enemy")
		f.nowWhere:SetText(rec and rec.n > 0 and "every enemy carries your DoTs" or "target an enemy to see the opener")
		f.nowKey:SetText("")
		f.after:SetText("")
		f.pull:SetText(self.set and self.set.playbook[1] or "")
		f.alert:SetText("")
		return
	end
	f.nowIcon:SetTexture(Spells:Icon(rec.spell))
	f.nowIcon:SetDesaturated(false)
	f.nowSpell:SetText(rec.spell)
	local where
	if rec.self then
		local onDemon = rec.spell == "Health Funnel" or rec.spell == "Sacrifice"
		where = (onDemon and "your demon: " or "around you: ") .. (rec.reason or "")
	elseif rec.switch then
		where = "|cffffd200switch|r to " .. Where(rec.focus) .. " (Tab or click it): " .. (rec.reason or "")
	else
		where = "on your target: " .. (rec.reason or "")
	end
	f.nowWhere:SetText(where)
	local key = ns.Assist:KeyHint(rec.spell)
	f.nowKey:SetText(key and ("Press |cff40ff40[" .. key .. "]|r") or ("|cff808080Put " .. rec.spell .. " on an action bar to see its key|r"))
	local parts = {}
	for _, spell in ipairs(rec.after or {}) do parts[#parts + 1] = ("|T%s:0|t %s"):format(Spells:Icon(spell), spell) end
	f.after:SetText(#parts > 0 and ("Then: " .. table.concat(parts, "  ")) or "")
	local playbook = (self.set or ns.PET_SETS.none).playbook
	local n = math.max(1, rec.n)
	f.pull:SetText((n >= 2 and (n .. " enemies. ") or "") .. playbook[math.min(4, n)])
	local state = { rec.spec or "Affliction" }
	if rec.playerShare then state[#state + 1] = ("you ~%d%%"):format(rec.playerShare * 100 + 0.5) end
	if rec.petShare then state[#state + 1] = ("demon ~%d%%"):format(rec.petShare * 100 + 0.5) end
	if rec.onPlayer and rec.onPlayer > 0 then state[#state + 1] = rec.onPlayer .. " on you" end
	f.state:SetText(table.concat(state, " | "))
	local alert = rec.alert or ""
	if (not GetCVar or GetCVar("nameplateShowEnemies") == "0") and rec.n > 0 then
		alert = "Turn on enemy nameplates (V) for per-enemy queues"
	end
	f.alert:SetText(alert)
end

-- Health Funnel and Life Tap hints: bright when the game's curve says so, dim otherwise.
function Coach:UpdateHints()
	local f = self.frame
	if not f then return end
	local petOut = UnitExists("pet")
	f.funnelHint:SetShown(petOut and Spells:Known("Health Funnel"))
	if petOut then
		ns.CurveAlpha(f.funnelHint, function(c) return UnitHealthPercent("pet", true, c) end, Curve("pet", 0.5, 1, 0.2), 0.6)
	end
	f.tapHint:SetShown(Spells:Known("Life Tap"))
	ns.CurveAlpha(f.tapHint, function(c) return UnitPowerPercent("player", 0, false, c) end, Curve("mana", 0.35, 1, 0.2), 0.6)
end

---------------------------------------------------------------------------
-- Frame
---------------------------------------------------------------------------
local function Border(button)
	local border = button:CreateTexture(nil, "BACKGROUND")
	border:SetPoint("TOPLEFT", -2, 2)
	border:SetPoint("BOTTOMRIGHT", 2, -2)
	border:SetColorTexture(0.58, 0.51, 0.79, 0.35)
end

function Coach:CreateRoleButton(f, index, role)
	local b = CreateFrame("Button", role.name, f, "SecureActionButtonTemplate")
	b:SetSize(ROLE_SIZE, ROLE_SIZE)
	b:SetPoint("TOPLEFT", 14 + (index - 1) * (ROLE_SIZE + 26), -30)
	b:RegisterForClicks("AnyUp")
	b:SetAttribute("type", "macro")
	Border(b)
	b.icon = b:CreateTexture(nil, "ARTWORK")
	b.icon:SetAllPoints()
	b.label = b:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
	b.label:SetPoint("TOP", b, "BOTTOM", 0, -2)
	b.hotkey = b:CreateFontString(nil, "OVERLAY", "NumberFontNormalSmallGray")
	b.hotkey:SetPoint("TOPRIGHT", -1, -2)
	b:SetHighlightTexture("Interface\\Buttons\\ButtonHilight-Square")
	b:HookScript("OnEnter", function(self)
		GameTooltip:SetOwner(self, "ANCHOR_LEFT")
		GameTooltip:AddLine(role.label .. (role.mod ~= "" and (" (one key + " .. role.mod:gsub("%+", "") .. ")") or " (one key)"))
		local text = self:GetAttribute("macrotext")
		GameTooltip:AddLine(text or "No spell for this role yet.", 1, 1, 1, true)
		GameTooltip:Show()
	end)
	b:HookScript("OnLeave", function() GameTooltip:Hide() end)
	self.roles[role.key] = b
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

local function Text(f, template, x, y, width)
	local fs = f:CreateFontString(nil, "OVERLAY", template)
	fs:SetPoint("TOPLEFT", x, y)
	fs:SetWidth(width or (WIDTH - x - 14))
	fs:SetJustifyH("LEFT")
	return fs
end

function Coach:Create()
	if self.frame then return self.frame end
	local f = ns:CreateWindow("GrimoireCoach", UIParent, "Grimoire coach")
	f:SetSize(WIDTH, 352)
	f:SetPoint("RIGHT", UIParent, "RIGHT", -40, 40)
	f:SetClampedToScreen(true)
	f:SetMovable(true)
	f:EnableMouse(true)
	f:RegisterForDrag("LeftButton")
	f:SetScript("OnDragStart", function(self) if not InCombatLockdown() then self:StartMoving() end end)
	f:SetScript("OnDragStop", f.StopMovingOrSizing)
	f:SetScale(ns.settings.coachScale or 1)
	self.frame = f

	for i, role in ipairs(self.ROLES) do self:CreateRoleButton(f, i, role) end
	f.advice = Text(f, "GameFontHighlightSmall", 14, -90)
	f.advice:SetTextColor(0.75, 0.68, 0.95)

	f.nowIcon = f:CreateTexture(nil, "ARTWORK")
	f.nowIcon:SetSize(38, 38)
	f.nowIcon:SetPoint("TOPLEFT", 14, -118)
	f.nowTitle = Text(f, "GameFontDisableSmall", 60, -114)
	f.nowTitle:SetText("NOW")
	f.state = Text(f, "GameFontDisableSmall", 14, -102)
	f.nowSpell = Text(f, "GameFontNormalLarge", 60, -126)
	f.nowWhere = Text(f, "GameFontHighlightSmall", 60, -144)
	f.nowKey = Text(f, "GameFontHighlightSmall", 60, -158)
	f.after = Text(f, "GameFontHighlightSmall", 14, -180)
	f.pull = Text(f, "GameFontDisableSmall", 14, -198)
	f.pull:SetHeight(26)
	f.alert = Text(f, "GameFontNormalSmall", 14, -228)
	f.alert:SetTextColor(1, 0.55, 0.2)

	f.funnelHint = f:CreateTexture(nil, "ARTWORK")
	f.funnelHint:SetSize(20, 20)
	f.funnelHint:SetPoint("TOPLEFT", 14, -246)
	f.funnelHint:SetTexture(Spells:Icon("Health Funnel"))
	f.funnelText = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	f.funnelText:SetPoint("LEFT", f.funnelHint, "RIGHT", 4, 0)
	f.funnelText:SetText("demon below half")
	f.tapHint = f:CreateTexture(nil, "ARTWORK")
	f.tapHint:SetSize(20, 20)
	f.tapHint:SetPoint("TOPLEFT", 150, -246)
	f.tapHint:SetTexture(Spells:Icon("Life Tap"))
	f.tapText = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	f.tapText:SetPoint("LEFT", f.tapHint, "RIGHT", 4, 0)
	f.tapText:SetText("mana low")

	for i = 1, UTILITY_BUTTONS do self:CreateUtilityButton(f, i) end

	-- One key (bind "Coach: one key"): routes to the four role buttons by modifier.
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
		Coach:UpdateHints()
	end)
	return f
end

-- Blizzard's Assisted Combat suggestion, when the client offers it (the game decides).
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
ns:On("ASSIST_UPDATE", function(rec) Coach:ShowRecommendation(rec) end)

local function Rebuild()
	if ns.isWarlock and Coach.frame then Coach:Build() end
end
ns:RegisterEvent("SPELLS_CHANGED", Rebuild)
ns:RegisterEvent("PLAYER_LEVEL_UP", function() C_Timer.After(1, Rebuild) end)
ns:RegisterEvent("UNIT_PET", function(_, unit) if unit == "player" then Rebuild() end end)
ns:RegisterEvent("TRAIT_CONFIG_UPDATED", Rebuild)
ns:RegisterEvent("UPDATE_BINDINGS", function() if Coach.frame then Coach:RefreshKeys() end end)
ns:RegisterEvent("PLAYER_REGEN_ENABLED", function()
	if Coach.pendingBuild then Coach:Build() end
end)
