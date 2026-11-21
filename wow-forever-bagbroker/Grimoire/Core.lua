-- Grimoire: warlock coach for WoW Forever. Namespace, saved variables, events and helpers.
local ADDON_NAME, ns = ...

local issecret = issecretvalue or function() return false end
function ns.IsSecret(value) return value ~= nil and issecret(value) and true or false end
-- The value when the game lets addons read it, else nil.
function ns.Readable(value) if value == nil or issecret(value) then return nil end return value end
-- True only for a readable true value.
function ns.IsTrue(value) return value ~= nil and not issecret(value) and value and true or false end

-- A curve the game evaluates on a unit's health or mana share (0 to 1): "below" under the
-- threshold, "above" from it on. The result can drive a widget's alpha even when the share is
-- secret: the game draws it, the addon never learns the value (Blizzard's Midnight pattern).
function ns.StepCurve(threshold, below, above)
	if not (C_CurveUtil and C_CurveUtil.CreateCurve) then return nil end
	local ok, curve = pcall(C_CurveUtil.CreateCurve)
	if not ok or not curve then return nil end
	if Enum and Enum.LuaCurveType and Enum.LuaCurveType.Step and curve.SetType then
		curve:SetType(Enum.LuaCurveType.Step)
		curve:AddPoint(0, below)
		curve:AddPoint(threshold, above)
	else
		curve:AddPoint(0, below)
		curve:AddPoint(math.max(0, threshold - 0.005), below)
		curve:AddPoint(threshold, above)
		curve:AddPoint(1, above)
	end
	return curve
end

-- Sets a region's alpha from getter(curve); falls back to a fixed alpha when the client lacks
-- curves or refuses the value (then curves stay off for the session).
function ns.CurveAlpha(region, getter, curve, fallback)
	if curve and not ns.curvesBroken then
		local ok = pcall(function()
			local v = getter(curve)
			if v == nil or (not issecret(v) and (type(v) ~= "number" or v > 1.0001)) then error("no curve support") end
			region:SetAlpha(v)
		end)
		if ok then return true end
		ns.curvesBroken = true
	end
	region:SetAlpha(fallback)
	return false
end

ns.defaults = {
	coachShown = true,
	coachScale = 1,
	weights = { sp = 1.0, stamina = 0.6, intellect = 0.45, spirit = 0.35 }, -- spell power > stamina > intellect > spirit
	levelsBelow = 6,      -- gear advisor: items down to this many levels below yours
	levelsAbove = 3,      -- ... and up to this many above (shown with the level they need)
	budget = nil,         -- copper per item; nil = 5% of your gold (50s to 50g)
	talentReminders = true,
	assist = true,        -- live recommendations in the coach
	plateQueues = true,   -- spell queues on enemy nameplates
	buttonGlow = true,    -- light up the action button of the recommended spell
	shardTarget = 5,      -- suggest Drain Soul finishes while you carry fewer Soul Shards than this
}

local frame = CreateFrame("Frame")
local handlers, callbacks = {}, {}
local safecall = securecallfunction or function(fn, ...) return fn(...) end

function ns:RegisterEvent(event, fn)
	local list = handlers[event]
	if not list then
		if not pcall(frame.RegisterEvent, frame, event) then return end
		list = {}
		handlers[event] = list
	end
	list[#list + 1] = fn
end

frame:SetScript("OnEvent", function(_, event, ...)
	for _, fn in ipairs(handlers[event] or {}) do safecall(fn, event, ...) end
end)

function ns:On(message, fn)
	callbacks[message] = callbacks[message] or {}
	table.insert(callbacks[message], fn)
end

function ns:Fire(message, ...)
	for _, fn in ipairs(callbacks[message] or {}) do safecall(fn, ...) end
end

local function CopyDefaults(src, dst)
	for k, v in pairs(src) do
		if type(v) == "table" then
			if type(dst[k]) ~= "table" then dst[k] = {} end
			CopyDefaults(v, dst[k])
		elseif dst[k] == nil then
			dst[k] = v
		end
	end
	return dst
end

ns:RegisterEvent("ADDON_LOADED", function(_, name)
	if name ~= ADDON_NAME then return end
	GrimoireDB = GrimoireDB or {}
	GrimoireDB.settings = CopyDefaults(ns.defaults, GrimoireDB.settings or {})
	ns.db = GrimoireDB
	ns.settings = GrimoireDB.settings
	ns:Fire("DB_READY")
end)

ns:RegisterEvent("PLAYER_LOGIN", function()
	local _, class = UnitClass("player")
	ns.isWarlock = class == "WARLOCK"
	ns:Fire("LOGIN")
end)

function ns:Print(msg)
	if DEFAULT_CHAT_FRAME then DEFAULT_CHAT_FRAME:AddMessage("|cff9482c9Grimoire|r: " .. tostring(msg)) end
end

-- A spell the character knows, by English name (returns spell ID and icon), or nil.
function ns.KnownSpell(name)
	if not name then return nil end
	local info = C_Spell and C_Spell.GetSpellInfo and C_Spell.GetSpellInfo(name)
	if type(info) ~= "table" or not info.spellID then return nil end
	if IsPlayerSpell and not IsPlayerSpell(info.spellID) and not (IsSpellKnown and IsSpellKnown(info.spellID, true)) then
		return nil
	end
	return info.spellID, info.iconID
end

-- Spell set for the demon that is out (Voidwalker, Succubus/Sayaad, Felhunter, Imp, or none).
function ns.CurrentSet()
	local family = UnitExists("pet") and UnitCreatureFamily("pet") or nil
	if ns.IsSecret(family) then family = nil end
	local key = family and (ns.PET_ALIASES[family] or family) or "none"
	if not ns.PET_SETS[key] then key = "none" end
	return ns.PET_SETS[key], key, family
end

ns.MARKERS = {
	[8] = "|TInterface\\TargetingFrame\\UI-RaidTargetingIcon_8:0|t", -- skull
	[7] = "|TInterface\\TargetingFrame\\UI-RaidTargetingIcon_7:0|t", -- cross
	[6] = "|TInterface\\TargetingFrame\\UI-RaidTargetingIcon_6:0|t", -- square
	[5] = "|TInterface\\TargetingFrame\\UI-RaidTargetingIcon_5:0|t", -- moon
	[4] = "|TInterface\\TargetingFrame\\UI-RaidTargetingIcon_4:0|t", -- triangle
}

-- Window helper: reuses BagBroker's look when it is installed.
function ns:CreateWindow(name, parent, title)
	if BagBrokerAPI and BagBrokerAPI.CreateWindow then return BagBrokerAPI.CreateWindow(name, parent, title) end
	local ok, f = pcall(CreateFrame, "Frame", name, parent, "BasicFrameTemplateWithInset")
	if not ok or not f then f = CreateFrame("Frame", name, parent, "BackdropTemplate") end
	if not f.TitleText then
		f.TitleText = f:CreateFontString(nil, "OVERLAY", "GameFontNormal")
		f.TitleText:SetPoint("TOP", 0, -6)
	end
	f.TitleText:SetText(title)
	return f
end

function ns.FormatMoney(copper)
	if BagBrokerAPI then return BagBrokerAPI.FormatMoney(copper) end
	if GetMoneyString then return GetMoneyString(math.floor(copper + 0.5), true) end
	return tostring(math.floor(copper + 0.5)) .. "c"
end
