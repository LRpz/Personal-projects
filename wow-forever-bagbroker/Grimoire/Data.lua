-- Grimoire: guide data for a warlock levelling in WoW Forever (talent plan for Affliction, rotation
-- rules for all three specializations).
-- Talent nodes and ranks come from the Forever game files (build 1.60.1.70959, read through
-- Everloot's talent_tree tool). The order follows the consensus of current Forever guides:
--   * Wowhead (updated 2026-11-11): instant Corruption first, then Suppression; Affliction-heavy at 40.
--   * Icy Veins (updated November 2026): Corruption, Pandemic, Nightfall, Siphon Life; 40 / 11 at 60.
--   * Conquest Capped, Foreverspec, Talents Forever: Improved Drains and Pandemic in the 20s,
--     Siphon Life at 30, Wrack at 40.
-- Edit TALENT_PLAN to follow another build; the tests check that every step respects the tree.
local _, ns = ...

-- [nodeID] = { name, tree, row, maxRanks, pointsRequiredInTree }; all three trees (the spec is the
-- tree with the most points).
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
	[105901] = { "Improved Sayaad", "Demonology", 3, 3, 10 },
	[105900] = { "Demonic Sacrifice", "Demonology", 3, 1, 10 },
	[105898] = { "Master Summoner", "Demonology", 3, 2, 10 },
	[105897] = { "Decimation", "Demonology", 4, 2, 15 },
	[105895] = { "Fel Domination", "Demonology", 4, 1, 15 },
	[105896] = { "Demonic Brand", "Demonology", 4, 3, 15 },
	[105894] = { "Improved Felhunter", "Demonology", 5, 3, 20 },
	[105892] = { "Soul Link", "Demonology", 5, 1, 20 },
	[105893] = { "Demonic Knowledge", "Demonology", 5, 3, 20 },
	[105891] = { "Master Demonologist", "Demonology", 6, 5, 25 },
	[105890] = { "Demonic Pact", "Demonology", 7, 1, 30 },
	[105881] = { "Destructive Reach", "Destruction", 1, 2, 0 },
	[105889] = { "Improved Shadow Bolt", "Destruction", 1, 5, 0 },
	[105888] = { "Bane", "Destruction", 1, 5, 0 },
	[105885] = { "Molten Skin", "Destruction", 2, 5, 5 },
	[105887] = { "Cataclysm", "Destruction", 2, 3, 5 },
	[105886] = { "Aftermath", "Destruction", 2, 5, 5 },
	[105883] = { "Ruin", "Destruction", 3, 5, 10 },
	[105884] = { "Shadowburn", "Destruction", 3, 1, 10 },
	[105882] = { "Intensity", "Destruction", 4, 3, 15 },
	[105879] = { "Agonizing Flames", "Destruction", 4, 3, 15 },
	[105880] = { "Conflagrate", "Destruction", 4, 1, 15 },
	[105878] = { "Pyroclasm", "Destruction", 5, 2, 20 },
	[105876] = { "Bane of Havoc", "Destruction", 5, 1, 20 },
	[105877] = { "Fire and Brimstone", "Destruction", 5, 3, 20 },
	[105875] = { "Shadow and Flame", "Destruction", 6, 5, 25 },
	[105874] = { "Incinerate", "Destruction", 7, 1, 30 },
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

-- DoTs in the order the assistant applies them. Damage and duration are read from each spell's
-- tooltip at your rank (these values are only fallbacks); ticks: Agony ramps up (weights per tick).
-- minHealthShare: skip the DoT when the enemy has less health left than this share of its damage.
ns.DOTS = {
	{ spell = "Corruption", school = 32, duration = 18, damage = 0, minHealthShare = 0.35 },
	{ spell = "Bane of Agony", school = 32, duration = 24, damage = 0, minHealthShare = 0.5, ramp = true },
	{ spell = "Curse of Agony", school = 32, duration = 24, damage = 0, minHealthShare = 0.5, ramp = true },
	{ spell = "Siphon Life", school = 32, duration = 30, damage = 0, minHealthShare = 0.5 },
	{ spell = "Immolate", school = 4, duration = 15, damage = 0, minHealthShare = 0.35, maxLevel = 29 },
}
-- Rotation per specialization, from the current Forever levelling guides:
--   Affliction: Wowhead (Affliction levelling tips, November 2026) and Mobalytics (Kargoz 1-60):
--     Bane of Agony first on enemies that live long enough to ramp up (with Amplify Curse when
--     talented), Corruption on every enemy, Siphon Life once talented, Immolate only on high-health
--     enemies; wand or Drain Life as filler (Drain Life when hurt, always with Soul Siphon);
--     Shadow Trance (Nightfall) procs: instant Shadow Bolt; Fear the extra enemy, re-Fear it.
--   Demonology: Wowhead (Demonology levelling tips), Warcraft Tavern, Mobalytics: with Demonic
--     Brand, Searing Pain on the demon's target whenever the brand has fallen off (never before
--     the talent: it pulls threat); Corruption, Bane of Agony or Immolate depending on how long the
--     enemy lives; wand before 30, Drain Life (rank 3+) from 30.
--   Destruction: Wowhead (Destruction levelling tips), Icy Veins: Immolate and DoTs, Conflagrate
--     near the end of Immolate (25+), Shadowburn to finish (20+), Shadow Bolt filler, Incinerate
--     on burning enemies from 40; wand or Drain Life when low.
-- lives: cast the DoT only when the enemy's health left after your running DoTs is at least this
-- share of the DoT's damage (1 = it must survive the whole DoT). with: cast first when ready.
ns.ROTATIONS = {
	Affliction = {
		dots = {
			{ spell = "Bane of Agony", lives = 0.5, with = "Amplify Curse" },
			{ spell = "Curse of Agony", lives = 0.5, with = "Amplify Curse" },
			{ spell = "Corruption", lives = 0.3 },
			{ spell = "Siphon Life", lives = 0.5 },
			{ spell = "Immolate", lives = 1.0 },
		},
	},
	Demonology = {
		brand = true,
		dots = {
			{ spell = "Corruption", lives = 0.3 },
			{ spell = "Bane of Agony", lives = 0.6 },
			{ spell = "Curse of Agony", lives = 0.6 },
			{ spell = "Immolate", lives = 1.0 },
		},
	},
	Destruction = {
		dots = {
			{ spell = "Immolate", lives = 0.4 },
			{ spell = "Corruption", lives = 0.4 },
			{ spell = "Bane of Agony", lives = 0.8 },
			{ spell = "Curse of Agony", lives = 0.8 },
		},
	},
}

-- Situation thresholds used by the rules (shares of maximum health).
ns.THRESHOLDS = {
	sacrifice = 0.25,     -- your health: Voidwalker Sacrifice
	deathCoil = 0.35,     -- your health: Death Coil the enemy hitting you
	funnelPet = 0.5,      -- demon health: Health Funnel (Wowhead: below half)
	funnelSelf = 0.5,     -- ... only while you stay above this
	drainBelow = 0.7,     -- your health: Drain Life rather than the wand (Affliction)
	drainBelowDemo = 0.6, -- Demonology before 30
	drainBelowDestro = 0.5,
	howlOnYou = 3,        -- enemies hitting you: Howl of Terror
	brand = 10,           -- seconds Demonic Brand lasts
	conflagrate = 3,      -- seconds of Immolate left: Conflagrate
	shardReserve = 1,     -- Soul Shards kept before Shadowburn
}

ns.DOT_BY_NAME = {}
for _, dot in ipairs(ns.DOTS) do ns.DOT_BY_NAME[dot.spell] = dot end

-- Agony deals half damage for the first third, full for the second, one and a half for the last.
ns.AGONY_WEIGHTS = { 0.5, 0.5, 0.5, 0.5, 1, 1, 1, 1, 1.5, 1.5, 1.5, 1.5 }

-- Control spells: take an extra enemy out of the fight (broken by damage, so never on a DoTed enemy).
ns.CONTROL = {
	["Fear"] = { duration = 15, school = 32 },
	["Seduction"] = { duration = 15, school = 32, pet = true, humanoid = true },
}

-- Direct spells (their hits are not DoT ticks when confirming DoTs or learning DoT damage).
ns.DIRECT = { ["Shadow Bolt"] = true, ["Death Coil"] = true, ["Shadowburn"] = true, ["Drain Life"] = true,
	["Drain Soul"] = true, ["Searing Pain"] = true, ["Conflagrate"] = true, ["Incinerate"] = true, ["Soul Fire"] = true }

ns.SOUL_SHARD = 6265

-- Per demon: how many enemies you fight at once (capacity, plus one with Siphon Life for the
-- Voidwalker), which control spells take the next ones out, what to do per pull size, and the
-- utility row. Spell names are English, as on the Forever client.
ns.PET_SETS = {}

ns.PET_SETS.Voidwalker = {
	advice = "Voidwalker: the solo tank. Best for pulling several mobs.",
	capacity = 2, siphonBonus = 1,
	control = { "Fear" },
	playbook = {
		"One enemy: the Voidwalker tanks, DoTs tick, Drain Life keeps you topped up.",
		"Two enemies: both on the Voidwalker; DoT both, drain the one hitting you. Funnel the Voidwalker below half health.",
		"Three: Fear the extra one, kill the others on the Voidwalker, Fear it again when it comes back.",
		"Pack: spread Corruption, Howl of Terror when they reach you, Suffering pulls them back to the Voidwalker.",
	},
	utility = {
		{ spell = "Health Funnel", text = "Heal the Voidwalker (use below half health)" },
		{ spell = "Sacrifice", petSpell = true, text = "Voidwalker shield when overwhelmed" },
		{ spell = "Suffering", petSpell = true, text = "Voidwalker taunts everything nearby" },
		{ spell = "Death Coil", text = "Emergency fear and heal" },
		{ spell = "Life Tap", text = "Health to mana (out of danger)" },
		{ spell = "Howl of Terror", text = "Fear every enemy around you" },
	},
}

ns.PET_SETS.Succubus = {
	advice = "Succubus: more damage, no tank. Seduction locks a humanoid out; switch to the Voidwalker for packs.",
	capacity = 1,
	control = { "Seduction", "Fear" },
	playbook = {
		"One enemy: the Succubus adds damage while you drain-tank with Drain Life.",
		"Two: Seduce the humanoid (or Fear the other one), kill the rest. Never DoT the controlled enemy.",
		"Three: Seduce one, Fear one, kill the third. Tight: keep Death Coil ready.",
		"Pack: summon the Voidwalker. In an emergency: Howl of Terror, Death Coil, run.",
	},
	utility = {
		{ spell = "Seduction", petSpell = true, text = "Seduce the current target (humanoids)" },
		{ spell = "Fear", text = "Fear the current target" },
		{ spell = "Death Coil", text = "Emergency fear and heal" },
		{ spell = "Health Funnel", text = "Heal your demon" },
		{ spell = "Life Tap", text = "Health to mana (out of danger)" },
		{ spell = "Howl of Terror", text = "Fear every enemy around you" },
	},
}

ns.PET_SETS.Felhunter = {
	advice = "Felhunter: answers casters. Spell Lock interrupts heals and big spells, Devour Magic strips buffs.",
	capacity = 1,
	control = { "Fear" },
	playbook = {
		"One enemy: the Felhunter fights while you DoT and drain; Spell Lock its heals.",
		"Two: Fear one, kill the other with the Felhunter.",
		"Three: Fear one and expect to drain-tank; Death Coil if it gets close.",
		"Pack: summon the Voidwalker.",
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

ns.PET_SETS.Imp = {
	advice = "Imp: no tank. Fine for groups (Blood Pact Stamina); solo, one mob at a time or switch to the Voidwalker.",
	capacity = 1,
	control = { "Fear" },
	playbook = {
		"One enemy: DoT, drain, and Fear it if it reaches you while you are low.",
		"Two: Fear one, kill the other.",
		"Three: too many without a tank: Fear, Death Coil, and summon the Voidwalker next time.",
		"Pack: summon the Voidwalker.",
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

-- Without a demon out, the Imp set (no tank) applies.
ns.PET_SETS.none = ns.PET_SETS.Imp
ns.PET_ALIASES = { Sayaad = "Succubus", Incubus = "Succubus", Succubus = "Succubus", Voidwalker = "Voidwalker",
	Felhunter = "Felhunter", Imp = "Imp" }

-- Which demon to bring, shown in the guide window.
ns.DEMON_ADVICE = {
	"Voidwalker: solo levelling and pulling several mobs (tanks, Suffering, Sacrifice).",
	"Succubus: faster single kills with drain-tanking; Seduction for humanoid adds.",
	"Felhunter: casters and healers (Spell Lock, Devour Magic).",
	"Imp: groups and dungeons (Blood Pact Stamina), or when you will not pull more than one mob.",
}

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
