-- Grimoire: slash commands (/grim) and key binding labels.
local _, ns = ...

BINDING_HEADER_GRIMOIRE = "Grimoire (warlock coach)"
_G["BINDING_NAME_CLICK GrimoireMain:LeftButton"] = "Coach: one key (DoTs; Shift drain, Ctrl control, Alt funnel)"
_G["BINDING_NAME_CLICK GrimoireDot:LeftButton"] = "Coach: DoTs on the target"
_G["BINDING_NAME_CLICK GrimoireFiller:LeftButton"] = "Coach: Drain Life on the target"
_G["BINDING_NAME_CLICK GrimoireControl:LeftButton"] = "Coach: Fear or Seduce the target"
_G["BINDING_NAME_CLICK GrimoireSave:LeftButton"] = "Coach: Health Funnel (Death Coil without a demon)"
BINDING_NAME_GRIMOIRE_TOGGLE_COACH = "Show or hide the coach"
BINDING_NAME_GRIMOIRE_TOGGLE_GUIDE = "Show or hide the talent guide"

function Grimoire_ToggleGuide()
	ns.Talents:Toggle()
end

local HELP = {
	"/grim coach - show or hide the combat coach (out of combat)",
	"/grim assist on|off - live recommendations",
	"/grim plates on|off - spell queues on enemy nameplates",
	"/grim glow on|off - light up the action button to press",
	"/grim shards <n> - suggest Drain Soul finishes below this many Soul Shards",
	"/grim forget - forget learned enemy health and DoT damage",
	"/grim talents - talent plan, demons and tips",
	"/grim gear - how to open the gear upgrades tab",
	"/grim budget <price>|auto - max price per item for gear upgrades (auto = 5% of your gold)",
	"/grim scale <0.6-1.5> - coach size",
	"/grim reminders on|off - talent point reminders on level up",
}

SLASH_GRIMOIRE1 = "/grim"
SLASH_GRIMOIRE2 = "/grimoire"
SlashCmdList.GRIMOIRE = function(msg)
	local command, rest = (msg or ""):match("^%s*(%S*)%s*(.-)%s*$")
	command = (command or ""):lower()
	if command == "coach" then
		Grimoire_ToggleCoach()
	elseif command == "talents" or command == "guide" then
		ns.Talents:Toggle()
	elseif command == "gear" then
		ns:Print("Open the auction house: the Gear tab sits under the BagBroker panel (needs BagBroker).")
	elseif command == "budget" then
		if rest == "auto" or rest == "" then
			ns.settings.budget = nil
		elseif BagBrokerAPI then
			local copper = BagBrokerAPI.ParseMoney(rest)
			if copper and copper > 0 then ns.settings.budget = copper end
		end
		ns:Print("Gear budget: " .. (ns.settings.budget and ns.FormatMoney(ns.settings.budget) or "5% of your gold"))
	elseif command == "scale" then
		local v = tonumber(rest)
		if v and v >= 0.6 and v <= 1.5 and not InCombatLockdown() then
			ns.settings.coachScale = v
			if ns.Coach.frame then ns.Coach.frame:SetScale(v) end
		end
	elseif command == "assist" or command == "plates" or command == "glow" then
		local key = ({ assist = "assist", plates = "plateQueues", glow = "buttonGlow" })[command]
		ns.settings[key] = rest ~= "off"
		ns:Print(command .. " " .. (ns.settings[key] and "on" or "off") .. ".")
		if ns.Assist then ns.Assist:RequestUpdate() end
	elseif command == "shards" then
		local n = tonumber(rest)
		if n and n >= 0 and n <= 40 then ns.settings.shardTarget = math.floor(n) end
		ns:Print(("Drain Soul finishes below %d Soul Shards."):format(ns.settings.shardTarget))
	elseif command == "forget" then
		ns.db.health, ns.db.dotMultiplier = {}, nil
		ns:Print("Learned enemy health and DoT damage cleared.")
	elseif command == "reminders" then
		ns.settings.talentReminders = rest ~= "off"
		ns:Print("Talent reminders " .. (ns.settings.talentReminders and "on" or "off") .. ".")
	else
		ns:Print("Commands:")
		for _, line in ipairs(HELP) do ns:Print("  " .. line) end
	end
end
