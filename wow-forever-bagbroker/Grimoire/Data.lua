-- Grimoire: guide data for an Affliction warlock levelling in WoW Forever.
-- Talent nodes and ranks come from the Forever game files (build 1.60.1.70959, read through
-- Everloot's talent_tree tool). The order follows the consensus of current Forever guides:
--   * Wowhead (updated 2026-11-11): instant Corruption first, then Suppression; Affliction-heavy at 40.
--   * Icy Veins (updated November 2026): Corruption, Pandemic, Nightfall, Siphon Life; 40 / 11 at 60.
--   * Conquest Capped, Foreverspec, Talents Forever: Improved Drains and Pandemic in the 20s,
--     Siphon Life at 30, Wrack at 40.
-- Edit TALENT_PLAN to follow another build; the tests check that every step respects the tree.
local _, ns = ...

-- [nodeID] = { name, tree, row, maxRanks, pointsRequiredInTree }
ns.TALENT_NODES = {
	[105921] = { "Improved Life Tap", "Affliction", 1, 2, 0 },
	[105925] = { "Suppression", "Affliction", 1, 5, 0 },
	[105924] = { "Improved Corruption", "Affliction", 1, 5, 0 },
	[105923] = { "Grim Reach", "Affliction", 2, 2, 5 },
	[105922] = { "Soul Harvest", "Affliction", 2, 2, 5 },
	[105920] = { "Improved Drains", "Affliction", 2, 3, 5 },
	[105919] = { "Improved Bane of Agony", "Affliction", 3, 2, 10 },
	[105918] = { "Fel Concentration", "Affliction", 3, 3, 10 },
	[105916] = { "Amplify Curse", "Affliction", 3, 1, 10 },
	[105917] = { "Pandemic", "Affliction", 3, 3, 10 },
	[110876] = { "Malevolence", "Affliction", 4, 5, 15 },
	[105914] = { "Nightfall", "Affliction", 4, 2, 15 },
	[105913] = { "Curse of Exhaustion", "Affliction", 4, 1, 15 },
	[105912] = { "Siphon Life", "Affliction", 5, 1, 20 },
	[105911] = { "Soul Siphon", "Affliction", 5, 3, 20 },
	[105910] = { "Shadow Mastery", "Affliction", 6, 5, 25 },
	[105909] = { "Wrack", "Affliction", 7, 1, 30 },
	[105905] = { "Improved Health Funnel", "Demonology", 1, 2, 0 },
	[105908] = { "Improved Imp", "Demonology", 1, 3, 0 },
	[105907] = { "Demonic Embrace", "Demonology", 1, 5, 0 },
	[105906] = { "Unholy Power", "Demonology", 1, 5, 0 },
	[105902] = { "Demonic Aegis", "Demonology", 2, 2, 5 },
	[105904] = { "Improved Voidwalker", "Demonology", 2, 3, 5 },
	[105903] = { "Fel Vitality", "Demonology", 2, 3, 5 },
	[105899] = { "Demonic Energies", "Demonology", 2, 2, 5 },
	[105900] = { "Demonic Sacrifice", "Demonology", 3, 1, 10 },
}

-- One entry per talent point: { level, nodeID, rank, why }.
ns.TALENT_PLAN = {}
local function Steps(fromLevel, nodeID, ranks, why)
	for r = 1, ranks do
		table.insert(ns.TALENT_PLAN, { fromLevel + r - 1, nodeID, r, why })
	end
end
Steps(10, 105924, 5, "Instant Corruption: the core of Affliction levelling")
Steps(15, 105925, 5, "Fewer resists and less threat on your DoTs")
Steps(20, 105920, 3, "Stronger Drain Life: sustain between and during pulls")
Steps(23, 105917, 3, "Pandemic: DoTs refresh without losing ticks")
Steps(26, 105914, 2, "Nightfall: free instant Shadow Bolts while draining")
Steps(28, 105923, 2, "Grim Reach: more range for DoTs and drains, safer pulls")
Steps(30, 105912, 1, "Siphon Life: a second healing DoT, the step up to 3+ mob pulls")
Steps(31, 110876, 5, "Malevolence")
Steps(36, 105911, 3, "Soul Siphon: drains grow with your DoTs")
Steps(39, 105919, 1, "Improved Bane of Agony")
Steps(40, 105909, 1, "Wrack: the Affliction capstone")
Steps(41, 105919, 1, "Improved Bane of Agony")
ns.TALENT_PLAN[#ns.TALENT_PLAN][3] = 2
Steps(42, 105910, 5, "Shadow Mastery: more Shadow damage")
Steps(47, 105916, 1, "Amplify Curse")
Steps(48, 105922, 2, "Soul Harvest: more Soul Shards")
Steps(50, 105907, 5, "Demonic Embrace: Stamina (your demon scales with you)")
Steps(55, 105903, 3, "Fel Vitality: tougher demon")
Steps(58, 105905, 2, "Improved Health Funnel")
Steps(60, 105900, 1, "Demonic Sacrifice (optional; Icy Veins takes it at 41)")

-- Trainer advice by spell name: "core" (train every rank), "useful" (situational), "skip".
ns.TRAINER = {
	["Shadow Bolt"] = { "core", "filler and Nightfall procs" },
	["Corruption"] = { "core", "main DoT" },
	["Bane of Agony"] = { "core", "main DoT (replaces Curse of Agony)" },
	["Immolate"] = { "core", "opener while levelling below 30" },
	["Drain Life"] = { "core", "your sustain" },
	["Drain Soul"] = { "core", "Soul Shards" },
	["Life Tap"] = { "core", "mana; scales with Spirit in Forever" },
	["Fear"] = { "core", "takes an extra mob out of the fight" },
	["Howl of Terror"] = { "core", "area fear for big pulls" },
	["Death Coil"] = { "core", "emergency fear and heal" },
	["Health Funnel"] = { "core", "keeps the Voidwalker tanking" },
	["Demon Skin"] = { "core", "armour and regeneration" },
	["Demon Armor"] = { "core", "armour and regeneration" },
	["Summon Voidwalker"] = { "core", "your tank" },
	["Create Healthstone"] = { "core", "free emergency heal" },
	["Create Spellstone"] = { "useful", "Shadow damage and haste imbue" },
	["Create Firestone"] = { "useful", "Fire imbue; less useful for Affliction" },
	["Create Soulstone"] = { "useful", "self resurrection" },
	["Shadow Ward"] = { "useful", "against Shadow casters" },
	["Rain of Fire"] = { "useful", "area damage on tanked packs, watch threat" },
	["Hellfire"] = { "useful", "area damage, hurts you too" },
	["Curse of the Elements"] = { "useful", "groups and dungeons" },
	["Banish"] = { "useful", "demons and elementals" },
	["Enslave Demon"] = { "useful", "situational" },
	["Unending Breath"] = { "useful", "underwater quests" },
	["Ritual of Summoning"] = { "useful", "groups" },
	["Summon Succubus"] = { "useful", "situational" },
	["Summon Felhunter"] = { "useful", "against casters" },
	["Searing Pain"] = { "skip", "Destruction spell" },
	["Soul Fire"] = { "skip", "Destruction spell" },
	["Curse of Weakness"] = { "skip", "rarely worth a GCD solo" },
	["Curse of Recklessness"] = { "skip", "rarely useful solo" },
	["Curse of Tongues"] = { "skip", "rarely useful solo" },
	["Detect Invisibility"] = { "skip", "rarely needed" },
	["Sense Demons"] = { "skip", "rarely needed" },
	["Eye of Kilrogg"] = { "skip", "rarely needed" },
}

-- Situation plans for the coach buttons, per demon. Each step: spell (English name), mark (raid
-- icon index), next (switch to the next enemy first), pet ("attack"), petSpell (a demon ability),
-- text, maxLevel (optional). Opener steps run once per fight; loop steps repeat; plans reset when
-- combat ends. Four plans per demon (the four coach buttons) plus six utility spells.
local SINGLE_OPENER = {
	{ spell = "Bane of Agony", mark = 8, pet = "attack", text = "Send your demon, open with Bane of Agony" },
	{ spell = "Corruption", text = "Instant Corruption" },
	{ spell = "Siphon Life", text = "Siphon Life (heals you)" },
	{ spell = "Immolate", maxLevel = 29, text = "Immolate while below 30" },
}
local DRAIN_LOOP = { { spell = "Drain Life", text = "Drain Life until it dies" } }

ns.PET_PLANS = {}

ns.PET_PLANS.Voidwalker = {
	advice = "Voidwalker: the solo tank. Best for pulling several mobs.",
	plans = {
		{ key = "single", label = "1", title = "One mob",
			tip = "Voidwalker tanks, DoTs tick, Drain Life keeps you topped up. Wand instead of draining when healthy.",
			opener = SINGLE_OPENER, loop = DRAIN_LOOP },
		{ key = "two", label = "2", title = "Two mobs",
			tip = "Both mobs on the Voidwalker; DoT both, drain the second. Health Funnel the Voidwalker below half health.",
			opener = {
				{ spell = "Bane of Agony", mark = 8, pet = "attack", text = "Skull: Voidwalker's target, Bane of Agony" },
				{ spell = "Corruption", text = "Skull: Corruption" },
				{ spell = "Bane of Agony", mark = 7, next = true, text = "Cross: next mob, Bane of Agony" },
				{ spell = "Corruption", text = "Cross: Corruption" },
				{ spell = "Siphon Life", text = "Cross: Siphon Life" },
			},
			loop = { { spell = "Drain Life", text = "Drain Life the current mob" } } },
		{ key = "three", label = "3", title = "Three mobs",
			tip = "Fear the third right away, kill the other two on the Voidwalker, re-Fear (utility row) when it returns.",
			opener = {
				{ spell = "Corruption", mark = 8, pet = "attack", text = "Skull: Voidwalker's target, Corruption" },
				{ spell = "Fear", mark = 5, next = true, text = "Moon: next mob, Fear it out of the fight" },
				{ spell = "Corruption", mark = 7, next = true, text = "Cross: next mob, Corruption (tab again if Moon)" },
				{ spell = "Bane of Agony", text = "Cross: Bane of Agony" },
				{ spell = "Siphon Life", text = "Cross: Siphon Life" },
			},
			loop = { { spell = "Drain Life", text = "Drain Life the current mob" } } },
		{ key = "pack", label = "4+", title = "Pack of 4 or 5",
			tip = "Needs Siphon Life (30) and Howl of Terror (40). Spread Corruption, Howl when they reach you, Suffering pulls them back to the Voidwalker.",
			opener = {
				{ spell = "Corruption", mark = 8, pet = "attack", text = "Skull: Voidwalker's target, Corruption" },
				{ spell = "Corruption", mark = 7, next = true, text = "Cross: Corruption" },
				{ spell = "Corruption", mark = 6, next = true, text = "Square: Corruption" },
				{ spell = "Corruption", mark = 4, next = true, text = "Triangle: Corruption" },
				{ spell = "Siphon Life", text = "Siphon Life on the current mob" },
				{ spell = "Howl of Terror", text = "When they reach you: Howl of Terror" },
				{ spell = "Suffering", petSpell = true, text = "Voidwalker Suffering: taunts everything back" },
			},
			loop = {
				{ spell = "Bane of Agony", next = true, text = "Next mob: Bane of Agony" },
				{ spell = "Drain Life", text = "Drain Life" },
			} },
	},
	utility = {
		{ spell = "Health Funnel", text = "Heal the Voidwalker (use below half health)" },
		{ spell = "Sacrifice", petSpell = true, text = "Voidwalker shield when overwhelmed" },
		{ spell = "Fear", text = "Fear the current target" },
		{ spell = "Death Coil", text = "Emergency fear and heal" },
		{ spell = "Life Tap", text = "Health to mana (out of danger)" },
		{ spell = "Drain Soul", text = "Finish with Drain Soul for a shard" },
	},
}

ns.PET_PLANS.Succubus = {
	advice = "Succubus: more damage, no tank. Seduction locks a humanoid out of the fight; switch to the Voidwalker for packs.",
	plans = {
		{ key = "single", label = "1", title = "One mob",
			tip = "The Succubus adds damage while you take the hits: drain-tank with Drain Life, kills are faster than with the Voidwalker.",
			opener = SINGLE_OPENER, loop = DRAIN_LOOP },
		{ key = "seduce", label = "2", title = "Two humanoids",
			tip = "Target the add first: Seduction holds it (humanoids only). Kill the other; re-Seduce when it breaks. Never DoT the seduced mob.",
			opener = {
				{ spell = "Seduction", petSpell = true, mark = 5, text = "Moon: current target, Seduction" },
				{ spell = "Bane of Agony", mark = 8, next = true, text = "Skull: next mob, Bane of Agony" },
				{ spell = "Corruption", text = "Skull: Corruption" },
				{ spell = "Siphon Life", text = "Skull: Siphon Life" },
			},
			loop = DRAIN_LOOP },
		{ key = "three", label = "3", title = "Three mobs",
			tip = "Seduce one humanoid, Fear another, kill the third. Tight: keep Death Coil ready.",
			opener = {
				{ spell = "Seduction", petSpell = true, mark = 5, text = "Moon: current target, Seduction" },
				{ spell = "Fear", mark = 6, next = true, text = "Square: next mob, Fear" },
				{ spell = "Bane of Agony", mark = 8, next = true, text = "Skull: next mob, Bane of Agony" },
				{ spell = "Corruption", text = "Skull: Corruption" },
				{ spell = "Siphon Life", text = "Skull: Siphon Life" },
			},
			loop = DRAIN_LOOP },
		{ key = "pack", label = "4+", title = "Pack: switch demon",
			tip = "Packs need a tank: summon the Voidwalker. In an emergency: Howl of Terror, Death Coil, run.",
			opener = {
				{ spell = "Howl of Terror", text = "Howl of Terror" },
				{ spell = "Death Coil", text = "Death Coil the closest mob" },
			},
			loop = DRAIN_LOOP },
	},
	utility = {
		{ spell = "Seduction", petSpell = true, text = "Seduce the current target (humanoids)" },
		{ spell = "Fear", text = "Fear the current target" },
		{ spell = "Death Coil", text = "Emergency fear and heal" },
		{ spell = "Health Funnel", text = "Heal your demon" },
		{ spell = "Life Tap", text = "Health to mana (out of danger)" },
		{ spell = "Drain Soul", text = "Finish with Drain Soul for a shard" },
	},
}

ns.PET_PLANS.Felhunter = {
	advice = "Felhunter: answers casters. Spell Lock interrupts heals and big spells, Devour Magic strips buffs.",
	plans = {
		{ key = "single", label = "1", title = "One mob",
			tip = "Felhunter fights while you DoT and drain.",
			opener = SINGLE_OPENER, loop = DRAIN_LOOP },
		{ key = "caster", label = "Cast", title = "Caster",
			tip = "Let the caster start a heal or a big spell, then press Spell Lock (utility row or this plan's step 2).",
			opener = {
				{ spell = "Bane of Agony", mark = 8, pet = "attack", text = "Skull: Bane of Agony, demon attacks" },
				{ spell = "Spell Lock", petSpell = true, text = "Spell Lock when it casts" },
				{ spell = "Corruption", text = "Corruption" },
				{ spell = "Siphon Life", text = "Siphon Life" },
			},
			loop = DRAIN_LOOP },
		{ key = "two", label = "2", title = "Two mobs",
			tip = "Fear one, kill the other with the Felhunter.",
			opener = {
				{ spell = "Fear", mark = 5, text = "Moon: current target, Fear" },
				{ spell = "Bane of Agony", mark = 8, next = true, pet = "attack", text = "Skull: next mob, Bane of Agony" },
				{ spell = "Corruption", text = "Skull: Corruption" },
				{ spell = "Siphon Life", text = "Skull: Siphon Life" },
			},
			loop = DRAIN_LOOP },
		{ key = "pack", label = "4+", title = "Pack: switch demon",
			tip = "Packs need a tank: summon the Voidwalker.",
			opener = {
				{ spell = "Howl of Terror", text = "Howl of Terror" },
				{ spell = "Death Coil", text = "Death Coil the closest mob" },
			},
			loop = DRAIN_LOOP },
	},
	utility = {
		{ spell = "Spell Lock", petSpell = true, text = "Interrupt the current target" },
		{ spell = "Devour Magic", petSpell = true, text = "Strip a buff or remove a debuff" },
		{ spell = "Fear", text = "Fear the current target" },
		{ spell = "Death Coil", text = "Emergency fear and heal" },
		{ spell = "Health Funnel", text = "Heal your demon" },
		{ spell = "Life Tap", text = "Health to mana (out of danger)" },
	},
}

ns.PET_PLANS.Imp = {
	advice = "Imp: no tank. Fine for groups (Blood Pact Stamina); solo, one mob at a time or switch to the Voidwalker.",
	plans = {
		{ key = "single", label = "1", title = "One mob",
			tip = "The Imp cannot tank: DoT, drain, and Fear if it reaches you.",
			opener = SINGLE_OPENER, loop = DRAIN_LOOP },
		{ key = "two", label = "2", title = "Two mobs",
			tip = "Fear one, kill the other.",
			opener = {
				{ spell = "Fear", mark = 5, text = "Moon: current target, Fear" },
				{ spell = "Bane of Agony", mark = 8, next = true, pet = "attack", text = "Skull: next mob, Bane of Agony" },
				{ spell = "Corruption", text = "Skull: Corruption" },
				{ spell = "Siphon Life", text = "Skull: Siphon Life" },
			},
			loop = DRAIN_LOOP },
		{ key = "group", label = "Grp", title = "Group play",
			tip = "In a group, let the tank hold aggro: DoT the tank's target, avoid Fear, Life Tap freely.",
			opener = {
				{ spell = "Corruption", text = "Corruption on the tank's target" },
				{ spell = "Bane of Agony", text = "Bane of Agony" },
				{ spell = "Siphon Life", text = "Siphon Life" },
			},
			loop = { { spell = "Shadow Bolt", text = "Shadow Bolt" } } },
		{ key = "pack", label = "4+", title = "Pack: switch demon",
			tip = "Packs need a tank: summon the Voidwalker.",
			opener = {
				{ spell = "Howl of Terror", text = "Howl of Terror" },
				{ spell = "Death Coil", text = "Death Coil the closest mob" },
			},
			loop = DRAIN_LOOP },
	},
	utility = {
		{ spell = "Fire Shield", petSpell = true, text = "Fire Shield on yourself or an ally" },
		{ spell = "Fear", text = "Fear the current target" },
		{ spell = "Death Coil", text = "Emergency fear and heal" },
		{ spell = "Health Funnel", text = "Heal your demon" },
		{ spell = "Life Tap", text = "Health to mana (out of danger)" },
		{ spell = "Drain Soul", text = "Finish with Drain Soul for a shard" },
	},
}

-- Without a demon out, the Imp plans (no tank) apply.
ns.PET_PLANS.none = ns.PET_PLANS.Imp
ns.PET_ALIASES = { Sayaad = "Succubus", Incubus = "Succubus", Succubus = "Succubus", Voidwalker = "Voidwalker",
	Felhunter = "Felhunter", Imp = "Imp" }

-- Which demon to bring, shown in the guide window.
ns.DEMON_ADVICE = {
	"Voidwalker: solo levelling and pulling several mobs (tanks, Suffering, Sacrifice).",
	"Succubus: faster single kills with drain-tanking; Seduction for humanoid adds.",
	"Felhunter: casters and healers (Spell Lock, Devour Magic).",
	"Imp: groups and dungeons (Blood Pact Stamina), or when you will not pull more than one mob.",
}

-- Compatibility: the first set is also exposed as ns.PLANS / ns.UTILITY.
ns.PLANS = ns.PET_PLANS.Voidwalker.plans
ns.UTILITY = ns.PET_PLANS.Voidwalker.utility

ns.TIPS = {
	"Your demon scales with your stats in Forever: Stamina makes the Voidwalker tougher too.",
	"Voidwalker at half health on two mobs is normal; Health Funnel it, keep Torment on autocast and let your DoTs kill rather than burst.",
	"Pull two mobs until Siphon Life (30); three with Fear; four or five once Howl of Terror (40) and Wrack arrive.",
	"Drain Life is your sustain: drain the mob hitting you, wand when healthy, Life Tap only when you can afford the health.",
	"Life Tap scales with Spirit in Forever, so Spirit is worth more than in Classic.",
	"Keep a Healthstone; Death Coil and Sacrifice are your panic buttons.",
	"Use Drain Soul on the last mob for Soul Shards (Fear, Healthstones, Voidwalker summons).",
	"Spellstone (Shadow damage and haste) suits Affliction; it stacks with Wizard Oil.",
}
