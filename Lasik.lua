local ADDON = 'Lasik'
local ADDON_PATH = 'Interface\\AddOns\\' .. ADDON .. '\\'

BINDING_CATEGORY_LASIK = ADDON
BINDING_NAME_LASIK_TARGETMORE = "Toggle Targets +"
BINDING_NAME_LASIK_TARGETLESS = "Toggle Targets -"
BINDING_NAME_LASIK_TARGET1 = "Set Targets to 1"
BINDING_NAME_LASIK_TARGET2 = "Set Targets to 2"
BINDING_NAME_LASIK_TARGET3 = "Set Targets to 3"
BINDING_NAME_LASIK_TARGET4 = "Set Targets to 4"
BINDING_NAME_LASIK_TARGET5 = "Set Targets to 5+"

local function log(...)
	print(ADDON, '-', ...)
end

if select(2, UnitClass('player')) ~= 'DEMONHUNTER' then
	log('[|cFFFF0000Error|r]', 'Not loading because you are not the correct class! Consider disabling', ADDON, 'for this character.')
	return
end

-- reference heavily accessed global functions from local scope for performance
local min = math.min
local max = math.max
local floor = math.floor
local GetActionInfo = _G.GetActionInfo
local GetBindingKey = _G.GetBindingKey
local GetSpellCharges = C_Spell.GetSpellCharges
local GetSpellCooldown = C_Spell.GetSpellCooldown
local GetSpellInfo = C_Spell.GetSpellInfo
local GetItemCount = C_Item.GetItemCount
local GetItemCooldown = C_Item.GetItemCooldown
local GetInventoryItemCooldown = _G.GetInventoryItemCooldown
local GetItemInfo = C_Item.GetItemInfo
local GetTime = _G.GetTime
local GetUnitSpeed = _G.GetUnitSpeed
local IsSpellUsable = C_Spell.IsSpellUsable
local IsItemUsable = C_Item.IsUsableItem
local UnitAttackSpeed = _G.UnitAttackSpeed
local UnitAura = C_UnitAuras.GetAuraDataByIndex
local UnitCastingInfo = _G.UnitCastingInfo
local UnitChannelInfo = _G.UnitChannelInfo
local UnitDetailedThreatSituation = _G.UnitDetailedThreatSituation
local UnitHealth = _G.UnitHealth
local UnitHealthMax = _G.UnitHealthMax
local UnitPower = _G.UnitPower
local UnitPowerMax = _G.UnitPowerMax
local UnitSpellHaste = _G.UnitSpellHaste
-- end reference global functions

-- useful functions
local function between(n, min, max)
	return n >= min and n <= max
end

local function clamp(n, min, max)
	return (n < min and min) or (n > max and max) or n
end

local function startsWith(str, start) -- case insensitive check to see if a string matches the start of another string
	if type(str) ~= 'string' then
		return false
	end
	return string.lower(str:sub(1, start:len())) == start:lower()
end

local function ToUID(guid)
	local uid = guid:match('^%w+-%d+-%d+-%d+-%d+-(%d+)')
	return uid and tonumber(uid)
end
-- end useful functions

Lasik = {}
local Opt -- use this as a local table reference to Lasik

SLASH_Lasik1, SLASH_Lasik2, SLASH_Lasik3 = '/l', '/la', '/lasik'

local function InitOpts()
	local function SetDefaults(t, ref)
		for k, v in next, ref do
			if t[k] == nil then
				local pchar
				if type(v) == 'boolean' then
					pchar = v and 'true' or 'false'
				elseif type(v) == 'table' then
					pchar = 'table'
				else
					pchar = v
				end
				t[k] = v
			elseif type(t[k]) == 'table' then
				SetDefaults(t[k], v)
			end
		end
	end
	SetDefaults(Lasik, { -- defaults
		locked = false,
		snap = false,
		scale = {
			main = 1,
			previous = 0.7,
			cooldown = 0.7,
			interrupt = 0.4,
			extra = 0.4,
			glow = 1,
		},
		glow = {
			main = true,
			cooldown = true,
			interrupt = false,
			extra = true,
			blizzard = false,
			animation = false,
			color = { r = 1, g = 1, b = 1 },
		},
		hide = {
			havoc = false,
			vengeance = false,
		},
		alpha = 1,
		frequency = 0.2,
		previous = true,
		always_on = false,
		cooldown = true,
		spell_swipe = true,
		keybinds = true,
		dimmer = true,
		miss_effect = true,
		boss_only = false,
		interrupt = true,
		aoe = false,
		auto_aoe = false,
		auto_aoe_ttl = 10,
		cd_ttd = 8,
		pot = false,
		trinket = true,
	})
end

-- UI related functions container
local UI = {
	anchor = {},
	buttons = {},
	action_slots = {},
}

-- combat event related functions container
local CombatEvent = {}

-- automatically registered events container
local Events = {}

-- player ability template
local Ability = {}
Ability.__index = Ability

-- classified player abilities
local Abilities = {
	all = {},
	bySpellId = {},
	velocity = {},
	autoAoe = {},
	tracked = {},
}

-- methods for target tracking / aoe modes
local AutoAoe = {
	targets = {},
	blacklist = {},
	ignored_units = {},
}

-- methods for tracking ticking debuffs on targets
local TrackedAuras = {}

-- timers for updating combat/display/hp info
local Timer = {
	combat = 0,
	display = 0,
	health = 0,
}

-- specialization constants
local SPEC = {
	NONE = 0,
	HAVOC = 1,
	VENGEANCE = 2,
}

-- action priority list container
local APL = {
	[SPEC.NONE] = {},
	[SPEC.HAVOC] = {},
	[SPEC.VENGEANCE] = {},
}

-- current player information
local Player = {
	initialized = false,
	time = 0,
	time_diff = 0,
	ctime = 0,
	combat_start = 0,
	level = 1,
	spec = 0,
	group_size = 1,
	target_mode = 0,
	gcd = 1.5,
	gcd_remains = 0,
	execute_remains = 0,
	haste_factor = 1,
	moving = false,
	movement_speed = 100,
	health = {
		current = 0,
		max = 100,
		pct = 100,
	},
	fury = {
		current = 0,
		max = 100,
		deficit = 100,
	},
	cast = {
		start = 0,
		ends = 0,
		remains = 0,
	},
	channel = {
		chained = false,
		start = 0,
		ends = 0,
		remains = 0,
		tick_count = 0,
		tick_interval = 0,
		ticks = 0,
		ticks_remain = 0,
		ticks_extra = 0,
		interruptible = false,
		early_chainable = false,
	},
	threat = {
		status = 0,
		pct = 0,
		lead = 0,
	},
	swing = {
		mh = {
			last = 0,
			speed = 0,
			remains = 0,
		},
		oh = {
			last = 0,
			speed = 0,
			remains = 0,
		},
		last_taken = 0,
	},
	set_bonus = {
		t33 = 0, -- Husk of the Hypogeal Nemesis
	},
	previous_gcd = {},-- list of previous GCD abilities
	item_use_blacklist = { -- list of item IDs with on-use effects we should mark unusable
		[190958] = true, -- Soleah's Secret Technique
		[193757] = true, -- Ruby Whelp Shell
		[202612] = true, -- Screaming Black Dragonscale
		[203729] = true, -- Ominous Chromatic Essence
	},
	main_freecast = false,
}

-- current target information
local Target = {
	boss = false,
	dummy = false,
	health = {
		current = 0,
		loss_per_sec = 0,
		max = 100,
		pct = 100,
		history = {},
	},
	hostile = false,
	estimated_range = 30,
}

-- target dummy unit IDs (count these units as bosses)
Target.Dummies = {
	[189617] = true,
	[189632] = true,
	[194643] = true,
	[194644] = true,
	[194648] = true,
	[194649] = true,
	[197833] = true,
	[198594] = true,
	[219250] = true,
	[225983] = true,
	[225984] = true,
	[225985] = true,
	[225976] = true,
	[225977] = true,
	[225978] = true,
	[225982] = true,
}

-- Start AoE

Player.target_modes = {
	[SPEC.NONE] = {
		{1, ''}
	},
	[SPEC.HAVOC] = {
		{1, ''},
		{2, '2'},
		{3, '3'},
		{4, '4'},
		{5, '5+'},
	},
	[SPEC.VENGEANCE] = {
		{1, ''},
		{2, '2'},
		{3, '3'},
		{4, '4'},
		{5, '5'},
		{6, '6+'},
	},
}

function Player:SetTargetMode(mode)
	if mode == self.target_mode then
		return
	end
	self.target_mode = min(mode, #self.target_modes[self.spec])
	self.enemies = self.target_modes[self.spec][self.target_mode][1]
	lasikPanel.text.br:SetText(self.target_modes[self.spec][self.target_mode][2])
end

function Player:ToggleTargetMode()
	local mode = self.target_mode + 1
	self:SetTargetMode(mode > #self.target_modes[self.spec] and 1 or mode)
end

function Player:ToggleTargetModeReverse()
	local mode = self.target_mode - 1
	self:SetTargetMode(mode < 1 and #self.target_modes[self.spec] or mode)
end

-- Target Mode Keybinding Wrappers
function Lasik_SetTargetMode(mode)
	Player:SetTargetMode(mode)
end

function Lasik_ToggleTargetMode()
	Player:ToggleTargetMode()
end

function Lasik_ToggleTargetModeReverse()
	Player:ToggleTargetModeReverse()
end

-- End AoE

-- Start Auto AoE

function AutoAoe:Add(guid, update)
	if self.blacklist[guid] then
		return
	end
	local uid = ToUID(guid)
	if uid and self.ignored_units[uid] then
		self.blacklist[guid] = Player.time + 10
		return
	end
	local new = not self.targets[guid]
	self.targets[guid] = Player.time
	if update and new then
		self:Update()
	end
end

function AutoAoe:Remove(guid)
	-- blacklist enemies for 2 seconds when they die to prevent out of order events from re-adding them
	self.blacklist[guid] = Player.time + 2
	if self.targets[guid] then
		self.targets[guid] = nil
		self:Update()
	end
end

function AutoAoe:Clear()
	for _, ability in next, Abilities.autoAoe do
		ability.auto_aoe.start_time = nil
		for guid in next, ability.auto_aoe.targets do
			ability.auto_aoe.targets[guid] = nil
		end
	end
	for guid in next, self.targets do
		self.targets[guid] = nil
	end
	self:Update()
end

function AutoAoe:Update()
	local count = 0
	for i in next, self.targets do
		count = count + 1
	end
	if count <= 1 then
		Player:SetTargetMode(1)
		return
	end
	Player.enemies = count
	for i = #Player.target_modes[Player.spec], 1, -1 do
		if count >= Player.target_modes[Player.spec][i][1] then
			Player:SetTargetMode(i)
			Player.enemies = count
			return
		end
	end
end

function AutoAoe:Purge()
	local update
	for guid, t in next, self.targets do
		if Player.time - t > Opt.auto_aoe_ttl then
			self.targets[guid] = nil
			update = true
		end
	end
	-- remove expired blacklisted enemies
	for guid, t in next, self.blacklist do
		if Player.time > t then
			self.blacklist[guid] = nil
		end
	end
	if update then
		self:Update()
	end
end

-- End Auto AoE

-- Start Abilities

function Ability:Add(spellId, buff, player, spellId2)
	local ability = {
		spellIds = type(spellId) == 'table' and spellId or { spellId },
		spellId = 0,
		spellId2 = spellId2,
		name = false,
		icon = false,
		requires_charge = false,
		requires_react = false,
		triggers_gcd = true,
		hasted_duration = false,
		hasted_cooldown = false,
		hasted_ticks = false,
		known = false,
		rank = 0,
		fury_cost = 0,
		fury_gain = 0,
		cooldown_duration = 0,
		buff_duration = 0,
		tick_interval = 0,
		max_range = 40,
		velocity = 0,
		last_gained = 0,
		last_used = 0,
		aura_target = buff and 'player' or 'target',
		aura_filter = (buff and 'HELPFUL' or 'HARMFUL') .. (player and '|PLAYER' or ''),
		keybinds = {},
	}
	setmetatable(ability, self)
	Abilities.all[#Abilities.all + 1] = ability
	return ability
end

function Ability:Match(spell)
	if type(spell) == 'number' then
		return spell == self.spellId or (self.spellId2 and spell == self.spellId2)
	elseif type(spell) == 'string' then
		return spell:lower() == self.name:lower()
	elseif type(spell) == 'table' then
		return spell == self
	end
	return false
end

function Ability:Ready(seconds)
	return self:Cooldown() <= (seconds or 0) and (not self.requires_react or self:React() > (seconds or 0))
end

function Ability:Usable(seconds, pool)
	if not self.known then
		return false
	end
	if not self.pool and self:Cost() > Player.fury.current then
		return false
	end
	if self.requires_charge and self:Charges() == 0 then
		return false
	end
	return self:Ready(seconds)
end

function Ability:Remains()
	if self:Casting() or self:Traveling() > 0 then
		return self:Duration()
	end
	local aura
	for i = 1, 40 do
		aura = UnitAura(self.aura_target, i, self.aura_filter)
		if not aura then
			return 0
		elseif self:Match(aura.spellId) then
			if aura.expirationTime == 0 then
				return 600 -- infinite duration
			end
			return max(0, aura.expirationTime - Player.ctime - (self.off_gcd and 0 or Player.execute_remains))
		end
	end
	return 0
end

function Ability:React()
	return self:Remains()
end

function Ability:Expiring(seconds)
	local remains = self:Remains()
	return remains > 0 and remains < (seconds or Player.gcd)
end

function Ability:Refreshable()
	if self.buff_duration > 0 then
		return self:Remains() < self:Duration() * 0.3
	end
	return self:Down()
end

function Ability:Up(...)
	return self:Remains(...) > 0
end

function Ability:Down(...)
	return self:Remains(...) <= 0
end

function Ability:SetVelocity(velocity)
	if velocity > 0 then
		self.velocity = velocity
		self.traveling = {}
	else
		self.traveling = nil
		self.velocity = 0
	end
end

function Ability:Traveling(all)
	if not self.traveling then
		return 0
	end
	local count = 0
	for _, cast in next, self.traveling do
		if all or cast.dstGUID == Target.guid then
			if Player.time - cast.start < self.max_range / self.velocity + (self.travel_delay or 0) then
				count = count + 1
			end
		end
	end
	return count
end

function Ability:TravelTime()
	return Target.estimated_range / self.velocity + (self.travel_delay or 0)
end

function Ability:Ticking()
	local count, ticking = 0, {}
	if self.aura_targets then
		for guid, aura in next, self.aura_targets do
			if aura.expires - Player.time > (self.off_gcd and 0 or Player.execute_remains) then
				ticking[guid] = true
			end
		end
	end
	if self.traveling then
		for _, cast in next, self.traveling do
			if Player.time - cast.start < self.max_range / self.velocity + (self.travel_delay or 0) then
				ticking[cast.dstGUID] = true
			end
		end
	end
	for _ in next, ticking do
		count = count + 1
	end
	return count
end

function Ability:HighestRemains()
	local highest
	if self.traveling then
		for _, cast in next, self.traveling do
			if Player.time - cast.start < self.max_range / self.velocity then
				highest = self:Duration()
			end
		end
	end
	if self.aura_targets then
		local remains
		for _, aura in next, self.aura_targets do
			remains = max(0, aura.expires - Player.time - Player.execute_remains)
			if remains > 0 and (not highest or remains > highest) then
				highest = remains
			end
		end
	end
	return highest or 0
end

function Ability:LowestRemains()
	local lowest
	if self.traveling then
		for _, cast in next, self.traveling do
			if Player.time - cast.start < self.max_range / self.velocity then
				lowest = self:Duration()
			end
		end
	end
	if self.aura_targets then
		local remains
		for _, aura in next, self.aura_targets do
			remains = max(0, aura.expires - Player.time - Player.execute_remains)
			if remains > 0 and (not lowest or remains < lowest) then
				lowest = remains
			end
		end
	end
	return lowest or 0
end

function Ability:TickTime()
	return self.hasted_ticks and (Player.haste_factor * self.tick_interval) or self.tick_interval
end

function Ability:CooldownDuration()
	return self.hasted_cooldown and (Player.haste_factor * self.cooldown_duration) or self.cooldown_duration
end

function Ability:Cooldown()
	if self.cooldown_duration > 0 and self:Casting() then
		return self:CooldownDuration()
	end
	local cooldown = GetSpellCooldown(self.spellId)
	if cooldown.startTime == 0 then
		return 0
	end
	return max(0, cooldown.duration - (Player.ctime - cooldown.startTime) - (self.off_gcd and 0 or Player.execute_remains))
end

function Ability:CooldownExpected()
	if self.last_used == 0 then
		return self:Cooldown()
	end
	if self.cooldown_duration > 0 and self:Casting() then
		return self:CooldownDuration()
	end
	local cooldown = GetSpellCooldown(self.spellId)
	if cooldown.startTime == 0 then
		return 0
	end
	local remains = cooldown.duration - (Player.ctime - cooldown.startTime)
	local reduction = (Player.time - self.last_used) / (self:CooldownDuration() - remains)
	return max(0, (remains * reduction) - (self.off_gcd and 0 or Player.execute_remains))
end

function Ability:Stack()
	local aura
	for i = 1, 40 do
		aura = UnitAura(self.aura_target, i, self.aura_filter)
		if not aura then
			return 0
		elseif self:Match(aura.spellId) then
			return (aura.expirationTime == 0 or aura.expirationTime - Player.ctime > (self.off_gcd and 0 or Player.execute_remains)) and aura.applications or 0
		end
	end
	return 0
end

function Ability:MaxStack()
	return self.max_stack
end

function Ability:Capped(deficit)
	return self:Stack() >= (self:MaxStack() - (deficit or 0))
end

function Ability:Cost()
	return self.fury_cost
end

function Ability:Gain()
	return self.fury_gain
end

function Ability:Free()
	return (self.fury_cost > 0 and self:Cost() == 0)
end

function Ability:ChargesFractional()
	local info = GetSpellCharges(self.spellId)
	if not info then
		return 0
	end
	local charges = info.currentCharges
	if self:Casting() then
		if charges >= info.maxCharges then
			return charges - 1
		end
		charges = charges - 1
	end
	if charges >= info.maxCharges then
		return charges
	end
	return charges + ((max(0, Player.ctime - info.cooldownStartTime + (self.off_gcd and 0 or Player.execute_remains))) / info.cooldownDuration)
end

function Ability:Charges()
	return floor(self:ChargesFractional())
end

function Ability:MaxCharges()
	local info = GetSpellCharges(self.spellId)
	return info and info.maxCharges or 0
end

function Ability:FullRechargeTime()
	local info = GetSpellCharges(self.spellId)
	if not info then
		return 0
	end
	local charges = info.currentCharges
	if self:Casting() then
		if charges >= info.maxCharges then
			return info.cooldownDuration
		end
		charges = charges - 1
	end
	if charges >= info.maxCharges then
		return 0
	end
	return (info.maxCharges - charges - 1) * info.cooldownDuration + (info.cooldownDuration - (Player.ctime - info.cooldownStartTime) - (self.off_gcd and 0 or Player.execute_remains))
end

function Ability:Duration()
	return self.hasted_duration and (Player.haste_factor * self.buff_duration) or self.buff_duration
end

function Ability:Casting()
	return Player.cast.ability == self
end

function Ability:Channeling()
	return Player.channel.ability == self
end

function Ability:CastTime()
	local info = GetSpellInfo(self.spellId)
	return info and info.castTime / 1000 or 0
end

function Ability:WillCapFury(reduction)
	return (Player.fury.current + self:Gain()) >= (Player.fury.max - (reduction or 5))
end

function Ability:WontCapFury(...)
	return not self:WillCapFury(...)
end

function Ability:Previous(n)
	local i = n or 1
	if Player.cast.ability then
		if i == 1 then
			return Player.cast.ability == self
		end
		i = i - 1
	end
	return Player.previous_gcd[i] == self
end

function Ability:UsedWithin(seconds)
	return self.last_used >= (Player.time - seconds)
end

function Ability:AutoAoe(removeUnaffected, trigger)
	self.auto_aoe = {
		remove = removeUnaffected,
		targets = {},
		target_count = 0,
		trigger = 'SPELL_DAMAGE',
	}
	if trigger == 'periodic' then
		self.auto_aoe.trigger = 'SPELL_PERIODIC_DAMAGE'
	elseif trigger == 'apply' then
		self.auto_aoe.trigger = 'SPELL_AURA_APPLIED'
	elseif trigger == 'cast' then
		self.auto_aoe.trigger = 'SPELL_CAST_SUCCESS'
	end
end

function Ability:RecordTargetHit(guid)
	self.auto_aoe.targets[guid] = Player.time
	if not self.auto_aoe.start_time then
		self.auto_aoe.start_time = self.auto_aoe.targets[guid]
	end
end

function Ability:UpdateTargetsHit()
	if self.auto_aoe.start_time and Player.time - self.auto_aoe.start_time >= 0.3 then
		self.auto_aoe.start_time = nil
		self.auto_aoe.target_count = 0
		if self.auto_aoe.remove then
			for guid in next, AutoAoe.targets do
				AutoAoe.targets[guid] = nil
			end
		end
		for guid in next, self.auto_aoe.targets do
			AutoAoe:Add(guid)
			self.auto_aoe.targets[guid] = nil
			self.auto_aoe.target_count = self.auto_aoe.target_count + 1
		end
		AutoAoe:Update()
	end
end

function Ability:Targets()
	if self.auto_aoe and self:Up() then
		return self.auto_aoe.target_count
	end
	return 0
end

function Ability:CastSuccess(dstGUID)
	self.last_used = Player.time
	if self.ignore_cast then
		return
	end
	Player.last_ability = self
	if self.triggers_gcd then
		Player.previous_gcd[10] = nil
		table.insert(Player.previous_gcd, 1, self)
	end
	if Opt.auto_aoe and self.auto_aoe and self.auto_aoe.trigger == 'SPELL_CAST_SUCCESS' then
		AutoAoe:Add(dstGUID, true)
	end
	if self.traveling and self.next_castGUID then
		self.traveling[self.next_castGUID] = {
			guid = self.next_castGUID,
			start = self.last_used,
			dstGUID = dstGUID,
		}
		self.next_castGUID = nil
	end
	if Opt.previous then
		lasikPreviousPanel.ability = self
		lasikPreviousPanel.border:SetTexture(ADDON_PATH .. 'border.blp')
		lasikPreviousPanel.icon:SetTexture(self.icon)
		lasikPreviousPanel:SetShown(lasikPanel:IsVisible())
	end
end

function Ability:CastLanded(dstGUID, event, missType)
	if self.traveling then
		local oldest
		for guid, cast in next, self.traveling do
			if Player.time - cast.start >= self.max_range / self.velocity + (self.travel_delay or 0) + 0.2 then
				self.traveling[guid] = nil -- spell traveled 0.2s past max range, delete it, this should never happen
			elseif cast.dstGUID == dstGUID and (not oldest or cast.start < oldest.start) then
				oldest = cast
			end
		end
		if oldest then
			Target.estimated_range = floor(clamp(self.velocity * max(0, Player.time - oldest.start - (self.travel_delay or 0)), 0, self.max_range))
			self.traveling[oldest.guid] = nil
		end
	end
	if self.range_est_start then
		Target.estimated_range = floor(clamp(self.velocity * (Player.time - self.range_est_start - (self.travel_delay or 0)), 5, self.max_range))
		self.range_est_start = nil
	elseif self.max_range < Target.estimated_range then
		Target.estimated_range = self.max_range
	end
	if Opt.auto_aoe and self.auto_aoe then
		if event == 'SPELL_MISSED' and (missType == 'EVADE' or (missType == 'IMMUNE' and not self.ignore_immune)) then
			AutoAoe:Remove(dstGUID)
		elseif event == self.auto_aoe.trigger or (self.auto_aoe.trigger == 'SPELL_AURA_APPLIED' and event == 'SPELL_AURA_REFRESH') then
			self:RecordTargetHit(dstGUID)
		end
	end
	if Opt.previous and Opt.miss_effect and event == 'SPELL_MISSED' and lasikPreviousPanel.ability == self then
		lasikPreviousPanel.border:SetTexture(ADDON_PATH .. 'misseffect.blp')
	end
end

-- Start DoT tracking

function TrackedAuras:Purge()
	for _, ability in next, Abilities.tracked do
		for guid, aura in next, ability.aura_targets do
			if aura.expires <= Player.time then
				ability:RemoveAura(guid)
			end
		end
	end
end

function TrackedAuras:Remove(guid)
	for _, ability in next, Abilities.tracked do
		ability:RemoveAura(guid)
	end
end

function Ability:Track()
	self.aura_targets = {}
end

function Ability:ApplyAura(guid)
	if AutoAoe.blacklist[guid] then
		return
	end
	local aura = self.aura_targets[guid] or {}
	aura.expires = Player.time + self:Duration()
	self.aura_targets[guid] = aura
	return aura
end

function Ability:RefreshAura(guid, extend)
	if AutoAoe.blacklist[guid] then
		return
	end
	local aura = self.aura_targets[guid]
	if not aura then
		return self:ApplyAura(guid)
	end
	local duration = self:Duration()
	aura.expires = max(aura.expires, Player.time + min(duration * (self.no_pandemic and 1.0 or 1.3), (aura.expires - Player.time) + (extend or duration)))
	return aura
end

function Ability:RefreshAuraAll(extend)
	local duration = self:Duration()
	for guid, aura in next, self.aura_targets do
		aura.expires = max(aura.expires, Player.time + min(duration * (self.no_pandemic and 1.0 or 1.3), (aura.expires - Player.time) + (extend or duration)))
	end
end

function Ability:RemoveAura(guid)
	if self.aura_targets[guid] then
		self.aura_targets[guid] = nil
	end
end

-- End DoT tracking

--[[
Note: To get talent_node value for a talent, hover over talent and use macro:
/dump GetMouseFoci()[1]:GetNodeID()
]]

-- Demon Hunter Abilities
---- Class
------ Baseline
local Disrupt = Ability:Add(183752, false, true)
Disrupt.cooldown_duration = 15
Disrupt.triggers_gcd = false
Disrupt.off_gcd = true
local ImmolationAura = Ability:Add(258920, true, true)
ImmolationAura.buff_duration = 6
ImmolationAura.cooldown_duration = 30
ImmolationAura.tick_interval = 1
ImmolationAura.hasted_cooldown = true
ImmolationAura.damage = Ability:Add(258922, false, true)
ImmolationAura.damage:AutoAoe(true)
ImmolationAura.buff_spellIds = {
	[258920] = true,
	[427904] = true,
	[427905] = true,
	[427906] = true,
	[427907] = true,
	[427908] = true,
	[427910] = true,
	[427911] = true,
	[427912] = true,
	[427913] = true,
	[427914] = true,
	[427915] = true,
	[427916] = true,
	[427917] = true,
}
local MetamorphosisH = Ability:Add(191427, true, true, 162264)
MetamorphosisH.buff_duration = 30
MetamorphosisH.cooldown_duration = 240
MetamorphosisH.remains = 0
MetamorphosisH.active = false
MetamorphosisH.full = false
MetamorphosisH.stun = Ability:Add(200166, false, true)
MetamorphosisH.stun.buff_duration = 3
MetamorphosisH.stun:AutoAoe(false, 'apply')
local Torment = Ability:Add(185245, false, true)
Torment.cooldown_duration = 8
Torment.triggers_gcd = false
Torment.off_gcd = true
------ Talents
local BulkExtraction = Ability:Add(320341, false, true)
BulkExtraction.cooldown_duration = 60
local BurningBlood = Ability:Add(390213, false, true)
local ChainsOfAnger = Ability:Add(389715, false, true)
local ChaosFragments = Ability:Add(320412, true, true)
local ChaosNova = Ability:Add(179057, false, true)
ChaosNova.buff_duration = 2
ChaosNova.cooldown_duration = 60
ChaosNova.fury_cost = 30
local CollectiveAnguish = Ability:Add(390152, false, true)
local CycleOfBinding = Ability:Add(389718, false, true)
local Demonic = Ability:Add(213410, false, true)
local DownInFlames = Ability:Add(389732, false, true)
local SigilOfSpite = Ability:Add(390163, false, true)
SigilOfSpite.buff_duration = 2
SigilOfSpite.cooldown_duration = 60
local Felblade = Ability:Add(232893, false, true, 213243)
Felblade.cooldown_duration = 15
Felblade.hasted_cooldown = true
local FelEruption = Ability:Add(211881, false, true)
FelEruption.buff_duration = 4
FelEruption.cooldown_duration =  30
FelEruption.fury_cost = 10
local FocusedCleave = Ability:Add(343207, false, true)
local SigilOfChains = Ability:Add(202138, false, true)
SigilOfChains.cooldown_duration = 90
SigilOfChains.buff_duration = 2
SigilOfChains.dot = Ability:Add(204843, false, true)
SigilOfChains.dot.buff_duration = 6
local SigilOfFlame = Ability:Add(204596, false, true)
SigilOfFlame.cooldown_duration = 30
SigilOfFlame.buff_duration = 2
SigilOfFlame.dot = Ability:Add(204598, false, true)
SigilOfFlame.dot.buff_duration = 8
SigilOfFlame.dot.tick_interval = 1
SigilOfFlame.dot:AutoAoe(false, 'apply')
local SigilOfMisery = Ability:Add(207684, false, true)
SigilOfMisery.cooldown_duration = 90
SigilOfMisery.buff_duration = 2
SigilOfMisery.dot = Ability:Add(207685, false, true)
SigilOfMisery.dot.buff_duration = 20
local SigilOfSilence = Ability:Add(202137, false, true)
SigilOfSilence.cooldown_duration = 60
SigilOfSilence.buff_duration = 2
SigilOfSilence.dot = Ability:Add(204490, false, true)
SigilOfSilence.dot.buff_duration = 6
local StokeTheFlames = Ability:Add(393827, false, true)
local QuickenedSigils = Ability:Add(209281, true, true)
local TheHunt = Ability:Add(370965, true, true, 370969)
TheHunt.cooldown_duration = 90
TheHunt.buff_duration = 6
TheHunt.tick_interval = 2
TheHunt.hasted_ticks = true
local VengefulRetreat = Ability:Add(198793, false, true, 198813)
VengefulRetreat.cooldown_duration = 25
VengefulRetreat.triggers_gcd = false
VengefulRetreat.off_gcd = true
VengefulRetreat:AutoAoe()
------ Procs

---- Havoc
------ Talents
local AFireInside = Ability:Add(427775, true, true)
local AnyMeansNecessary = Ability:Add(388114, false, true, 394486)
local Annihilation = Ability:Add(201427, false, true, 201428)
Annihilation.fury_cost = 40
local BladeDance = Ability:Add(188499, false, true, 199552)
BladeDance.cooldown_duration = 9
BladeDance.fury_cost = 35
BladeDance.hasted_cooldown = true
BladeDance:AutoAoe(true)
local BlindFury = Ability:Add(203550, false, true)
local BurningWound = Ability:Add(391189, false, true, 391191)
BurningWound.buff_duration = 15
local ChaosStrike = Ability:Add(162794, false, true)
ChaosStrike.fury_cost = 40
local ChaosTheory = Ability:Add(389687, false, true, 337567)
ChaosTheory.buff_duration = 8
local ChaoticTransformation = Ability:Add(388112, false, true)
local CycleOfHatred = Ability:Add(258887, false, true)
local DeathSweep = Ability:Add(210152, false, true, 210153)
DeathSweep.cooldown_duration = 9
DeathSweep.fury_cost = 35
DeathSweep.hasted_cooldown = true
DeathSweep:AutoAoe(true)
local DemonBlades = Ability:Add(203555, false, true, 203796)
local DemonsBite = Ability:Add(162243, false, true)
local EssenceBreak = Ability:Add(258860, false, true, 320338)
EssenceBreak.cooldown_duration = 40
EssenceBreak.buff_duration = 4
local EyeBeam = Ability:Add(198013, false, true, 198030)
EyeBeam.buff_duration = 2
EyeBeam.cooldown_duration = 40
EyeBeam.fury_cost = 30
EyeBeam:AutoAoe(true)
local FelBarrage = Ability:Add(258925, true, true)
FelBarrage.cooldown_duration = 90
FelBarrage.buff_duration = 8
FelBarrage.fury_cost = 10
FelBarrage.damage = Ability:Add(258926, false, true)
FelBarrage.damage:AutoAoe(true)
local FelRush = Ability:Add(195072, false, true, 192611)
FelRush.cooldown_duration = 10
FelRush.requires_charge = true
FelRush:AutoAoe()
local FirstBlood = Ability:Add(206416, false, true)
local FuriousGaze = Ability:Add(343311, true, true, 343312)
FuriousGaze.buff_duration = 10
local FuriousThrows = Ability:Add(393029, false, true)
local GlaiveTempest = Ability:Add(342817, false, true, 342857)
GlaiveTempest.cooldown_duration = 25
GlaiveTempest.buff_duration = 3
GlaiveTempest.fury_cost = 30
GlaiveTempest.hasted_cooldown = true
GlaiveTempest:AutoAoe()
local Inertia = Ability:Add(427640, true, true, 427641)
Inertia.buff_duration = 5
local Initiative = Ability:Add(388108, true, true, 391215)
Initiative.buff_duration = 5
local InnerDemon = Ability:Add(389693, false, true, 390137)
InnerDemon:AutoAoe()
local Momentum = Ability:Add(206476, true, true, 208628)
Momentum.buff_duration = 6
local Ragefire = Ability:Add(388107, false, true, 390197)
Ragefire:AutoAoe()
local RestlessHunter = Ability:Add(390142, true, true, 390212)
RestlessHunter.buff_duration = 12
local ShatteredDestiny = Ability:Add(388116, false, true)
local Soulscar = Ability:Add(388106, false, true, 390181)
Soulscar.buff_duration = 6
Soulscar.tick_interval = 2
local TacticalRetreat = Ability:Add(389688, true, true, 389890)
TacticalRetreat.buff_duration = 10
local ThrowGlaive = Ability:Add(185123, false, true)
ThrowGlaive.cooldown_duration = 9
ThrowGlaive.hasted_cooldown = true
ThrowGlaive.damage = Ability:Add(337819, false, true)
ThrowGlaive.damage:AutoAoe()
local TrailOfRuin = Ability:Add(258881, false, true, 258883)
TrailOfRuin.buff_duration = 4
TrailOfRuin.tick_interval = 1
local UnboundChaos = Ability:Add(347461, true, true, 347462)
UnboundChaos.buff_duration = 12
---- Vengeance
------ Talents
local AscendingFlame = Ability:Add(428603, false, true)
local CalcifiedSpikes = Ability:Add(389720, true, true, 391171)
CalcifiedSpikes.buff_duration = 12
local CharredFlesh = Ability:Add(336639, false, true)
CharredFlesh.talent_node = 90962
local DarkglareBoon = Ability:Add(389708, false, true)
DarkglareBoon.talent_node = 90985
local DemonSpikes = Ability:Add(203720, true, true, 203819)
DemonSpikes.buff_duration = 6
DemonSpikes.cooldown_duration = 20
DemonSpikes.hasted_cooldown = true
DemonSpikes.requires_charge = true
DemonSpikes.triggers_gcd = false
DemonSpikes.off_gcd = true
local Fallout = Ability:Add(227174, false, true)
local FelDevastation = Ability:Add(212084, false, true)
FelDevastation.fury_cost = 50
FelDevastation.buff_duration = 2
FelDevastation.cooldown_duration = 40
FelDevastation:AutoAoe()
local FieryBrand = Ability:Add(204021, false, true, 207771)
FieryBrand.buff_duration = 10
FieryBrand.cooldown_duration = 60
FieryBrand.no_pandemic = true
FieryBrand:Track()
FieryBrand:AutoAoe(false, 'apply')
local FieryDemise = Ability:Add(389220, false, true)
FieryDemise.talent_node = 90958
local Fracture = Ability:Add(263642, false, true)
Fracture.cooldown_duration = 4.5
Fracture.fury_gain = 25
Fracture.hasted_cooldown = true
Fracture.requires_charge = true
local Frailty = Ability:Add(389958, false, true, 247456)
Frailty.buff_duration = 6
local InfernalStrike = Ability:Add(189110, false, true, 189112)
InfernalStrike.cooldown_duration = 20
InfernalStrike.requires_charge = true
InfernalStrike.triggers_gcd = false
InfernalStrike.off_gcd = true
InfernalStrike:AutoAoe()
local MetamorphosisV = Ability:Add(187827, true, true)
MetamorphosisV.buff_duration = 15
MetamorphosisV.cooldown_duration = 180
MetamorphosisV.remains = 0
MetamorphosisV.active = false
MetamorphosisV.full = false
local Shear = Ability:Add(203783, false, true)
Shear.fury_gain = 10
local ShearFury = Ability:Add(389997, false, true)
local SoulCarver = Ability:Add(207407, false, true)
SoulCarver.cooldown_duration = 60
SoulCarver.buff_duration = 3
SoulCarver.tick_interval = 1
local SoulCleave = Ability:Add(228477, false, true, 228478)
SoulCleave.fury_cost = 30
SoulCleave:AutoAoe(true)
local SoulCrush = Ability:Add(389985, false, true)
local SpiritBomb = Ability:Add(247454, false, true)
SpiritBomb.fury_cost = 40
SpiritBomb:AutoAoe(true)
local SoulSigils = Ability:Add(395446, false, true)
local ThrowGlaiveV = Ability:Add(204157, false, true)
ThrowGlaiveV.cooldown_duration = 3
ThrowGlaiveV.hasted_cooldown = true
ThrowGlaiveV:AutoAoe()
local Vulnerability = Ability:Add(389976, false, true)
Vulnerability.talent_node = 90981
------ Procs
local SoulFragments = Ability:Add(204254, false, true, 204255)
SoulFragments.buff = Ability:Add(203981, true, true)
-- Hero talents
---- Aldrachi Reaver

---- Fel-Scarred
local ConsumingFire = Ability:Add(452487, true, true)
ConsumingFire.cooldown_duration = 30
ConsumingFire.hasted_cooldown = true
local DemonicIntensity = Ability:Add(452415, false, true)
local Demonsurge = Ability:Add(452402, false, true, 452416)
Demonsurge:AutoAoe()
local FelDesolation = Ability:Add(452486, false, true)
FelDesolation.fury_cost = 50
FelDesolation.buff_duration = 2
FelDesolation.cooldown_duration = 40
FelDesolation:AutoAoe()
local SigilOfDoom = Ability:Add(452490, false, true)
SigilOfDoom.cooldown_duration = 30
SigilOfDoom.buff_duration = 2
SigilOfDoom.dot = Ability:Add(462030, false, true)
SigilOfDoom.dot.buff_duration = 8
SigilOfDoom.dot.tick_interval = 1
SigilOfDoom.dot:AutoAoe(false, 'apply')
local SoulSunder = Ability:Add(452436, false, true)
SoulSunder.fury_cost = 30
SoulSunder:AutoAoe(true)
local SpiritBurst = Ability:Add(452437, false, true)
SpiritBurst.fury_cost = 40
SpiritBurst:AutoAoe(true)
local ViolentTransformation = Ability:Add(452409, false, true)
-- Tier set bonuses

-- Racials

-- PvP talents

-- Trinket effects

-- Class cooldowns

-- Aliases
local Metamorphosis
-- End Abilities

-- Start Inventory Items

local InventoryItem, Trinket = {}, {}
InventoryItem.__index = InventoryItem

local InventoryItems = {
	all = {},
	byItemId = {},
}

function InventoryItem:Add(itemId)
	local name, _, _, _, _, _, _, _, _, icon = GetItemInfo(itemId)
	local item = {
		itemId = itemId,
		name = name,
		icon = icon,
		can_use = false,
		off_gcd = true,
		keybinds = {},
	}
	setmetatable(item, self)
	InventoryItems.all[#InventoryItems.all + 1] = item
	InventoryItems.byItemId[itemId] = item
	return item
end

function InventoryItem:Charges()
	local charges = GetItemCount(self.itemId, false, true) or 0
	if self.created_by and (self.created_by:Previous() or Player.previous_gcd[1] == self.created_by) then
		charges = max(self.max_charges, charges)
	end
	return charges
end

function InventoryItem:Count()
	local count = GetItemCount(self.itemId, false, false) or 0
	if self.created_by and (self.created_by:Previous() or Player.previous_gcd[1] == self.created_by) then
		count = max(1, count)
	end
	return count
end

function InventoryItem:Cooldown()
	local start, duration
	if self.equip_slot then
		start, duration = GetInventoryItemCooldown('player', self.equip_slot)
	else
		start, duration = GetItemCooldown(self.itemId)
	end
	if start == 0 then
		return 0
	end
	return max(0, duration - (Player.ctime - start) - (self.off_gcd and 0 or Player.execute_remains))
end

function InventoryItem:Ready(seconds)
	return self:Cooldown() <= (seconds or 0)
end

function InventoryItem:Equipped()
	return self.equip_slot and true
end

function InventoryItem:Usable(seconds)
	if not self.can_use then
		return false
	end
	if not self:Equipped() and self:Charges() == 0 then
		return false
	end
	return self:Ready(seconds)
end

-- Inventory Items

-- Equipment
local Trinket1 = InventoryItem:Add(0)
local Trinket2 = InventoryItem:Add(0)
-- End Inventory Items

-- Start Abilities Functions

function Abilities:Update()
	wipe(self.bySpellId)
	wipe(self.velocity)
	wipe(self.autoAoe)
	wipe(self.tracked)
	for _, ability in next, self.all do
		if ability.known then
			self.bySpellId[ability.spellId] = ability
			if ability.spellId2 then
				self.bySpellId[ability.spellId2] = ability
			end
			if ability.velocity > 0 then
				self.velocity[#self.velocity + 1] = ability
			end
			if ability.auto_aoe then
				self.autoAoe[#self.autoAoe + 1] = ability
			end
			if ability.aura_targets then
				self.tracked[#self.tracked + 1] = ability
			end
		end
	end
end

-- End Abilities Functions

-- Start Player Functions

function Player:ResetSwing(mainHand, offHand, missed)
	local mh, oh = UnitAttackSpeed('player')
	if mainHand then
		self.swing.mh.speed = (mh or 0)
		self.swing.mh.last = self.time
	end
	if offHand then
		self.swing.oh.speed = (oh or 0)
		self.swing.oh.last = self.time
	end
end

function Player:TimeInCombat()
	if self.combat_start > 0 then
		return self.time - self.combat_start
	end
	if self.cast.ability and self.cast.ability.triggers_combat then
		return 0.1
	end
	return 0
end

function Player:UnderMeleeAttack()
	return (self.time - self.swing.last_taken) < 3
end

function Player:UnderAttack()
	return self.threat.status >= 3 or self:UnderMeleeAttack()
end

function Player:BloodlustActive()
	local aura
	for i = 1, 40 do
		aura = UnitAura('player', i, 'HELPFUL')
		if not aura then
			return false
		elseif (
			aura.spellId == 2825 or   -- Bloodlust (Horde Shaman)
			aura.spellId == 32182 or  -- Heroism (Alliance Shaman)
			aura.spellId == 80353 or  -- Time Warp (Mage)
			aura.spellId == 90355 or  -- Ancient Hysteria (Hunter Pet - Core Hound)
			aura.spellId == 160452 or -- Netherwinds (Hunter Pet - Nether Ray)
			aura.spellId == 264667 or -- Primal Rage (Hunter Pet - Ferocity)
			aura.spellId == 381301 or -- Feral Hide Drums (Leatherworking)
			aura.spellId == 390386    -- Fury of the Aspects (Evoker)
		) then
			return true
		end
	end
end

function Player:Equipped(itemID, slot)
	for i = (slot or 1), (slot or 19) do
		if GetInventoryItemID('player', i) == itemID then
			return true, i
		end
	end
	return false
end

function Player:BonusIdEquipped(bonusId, slot)
	local link, item
	for i = (slot or 1), (slot or 19) do
		link = GetInventoryItemLink('player', i)
		if link then
			item = link:match('Hitem:%d+:([%d:]+)')
			if item then
				for id in item:gmatch('(%d+)') do
					if tonumber(id) == bonusId then
						return true
					end
				end
			end
		end
	end
	return false
end

function Player:InArenaOrBattleground()
	return self.instance == 'arena' or self.instance == 'pvp'
end

function Player:UpdateTime(timeStamp)
	self.ctime = GetTime()
	if timeStamp then
		self.time_diff = self.ctime - timeStamp
	end
	self.time = self.ctime - self.time_diff
end

function Player:UpdateKnown()
	local info, node
	local configId = C_ClassTalents.GetActiveConfigID()
	for _, ability in next, Abilities.all do
		ability.known = false
		ability.rank = 0
		for _, spellId in next, ability.spellIds do
			info = GetSpellInfo(spellId)
			if info then
				ability.spellId, ability.name, ability.icon = info.spellID, info.name, info.originalIconID
			end
			if IsPlayerSpell(spellId) or (ability.learn_spellId and IsPlayerSpell(ability.learn_spellId)) then
				ability.known = true
				break
			end
		end
		if ability.bonus_id then -- used for checking enchants and crafted effects
			ability.known = self:BonusIdEquipped(ability.bonus_id)
		end
		if ability.talent_node and configId then
			node = C_Traits.GetNodeInfo(configId, ability.talent_node)
			if node then
				ability.rank = node.activeRank
				ability.known = ability.rank > 0
			end
		end
		if C_LevelLink.IsSpellLocked(ability.spellId) or (ability.check_usable and not IsSpellUsable(ability.spellId)) then
			ability.known = false -- spell is locked, do not mark as known
		end
	end

	Metamorphosis = MetamorphosisH
	if MetamorphosisV.known then
		MetamorphosisH.known = false
		Metamorphosis = MetamorphosisV
	end
	if DemonBlades.known then
		DemonsBite.known = false
	end
	DeathSweep.known = BladeDance.known
	Annihilation.known = ChaosStrike.known
	ImmolationAura.damage.known = ImmolationAura.known
	FelBarrage.damage.known = FelBarrage.known
	SigilOfFlame.dot.known = SigilOfFlame.known
	ThrowGlaive.damage.known = ThrowGlaive.known
	if Fracture.known then
		Shear.known = false
	end
	if Demonsurge.known then
		SoulSunder.known = SoulCleave.known
		SpiritBurst.known = SpiritBomb.known
	end
	if DemonicIntensity.known then
		ConsumingFire.known = ImmolationAura.known
		FelDesolation.known = FelDevastation.known
		SigilOfDoom.known = SigilOfFlame.known
		SigilOfDoom.dot.known = SigilOfDoom.known
	end

	Abilities:Update()

	if APL[self.spec].precombat_variables then
		APL[self.spec]:precombat_variables()
	end
end

function Player:UpdateChannelInfo()
	local channel = self.channel
	local _, _, _, start, ends, _, _, spellId = UnitChannelInfo('player')
	if not spellId then
		channel.ability = nil
		channel.chained = false
		channel.start = 0
		channel.ends = 0
		channel.tick_count = 0
		channel.tick_interval = 0
		channel.ticks = 0
		channel.ticks_remain = 0
		channel.ticks_extra = 0
		channel.interrupt_if = nil
		channel.interruptible = false
		channel.early_chain_if = nil
		channel.early_chainable = false
		return
	end
	local ability = Abilities.bySpellId[spellId]
	if ability then
		if ability == channel.ability then
			channel.chained = true
		end
		channel.interrupt_if = ability.interrupt_if
	else
		channel.interrupt_if = nil
	end
	channel.ability = ability
	channel.ticks = 0
	channel.start = start / 1000
	channel.ends = ends / 1000
	if ability and ability.tick_interval then
		channel.tick_interval = ability:TickTime()
	else
		channel.tick_interval = channel.ends - channel.start
	end
	channel.tick_count = (channel.ends - channel.start) / channel.tick_interval
	if channel.chained then
		channel.ticks_extra = channel.tick_count - floor(channel.tick_count)
	else
		channel.ticks_extra = 0
	end
	channel.ticks_remain = channel.tick_count
end

function Player:UpdateThreat()
	local _, status, pct
	_, status, pct = UnitDetailedThreatSituation('player', 'target')
	self.threat.status = status or 0
	self.threat.pct = pct or 0
	self.threat.lead = 0
	if self.threat.status >= 3 and DETAILS_PLUGIN_TINY_THREAT then
		local threat_table = DETAILS_PLUGIN_TINY_THREAT.player_list_indexes
		if threat_table and threat_table[1] and threat_table[2] and threat_table[1][1] == self.name then
			self.threat.lead = max(0, threat_table[1][6] - threat_table[2][6])
		end
	end
end

function Player:Update()
	local _, cooldown, start, ends, spellId, speed, max_speed, speed_mh, speed_oh
	self.main = nil
	self.cd = nil
	self.interrupt = nil
	self.extra = nil
	self:UpdateTime()
	self.haste_factor = 1 / (1 + UnitSpellHaste('player') / 100)
	self.gcd = 1.5 * self.haste_factor
	cooldown = GetSpellCooldown(61304)
	self.gcd_remains = cooldown.startTime > 0 and cooldown.duration - (self.ctime - cooldown.startTime) or 0
	_, _, _, start, ends, _, _, _, spellId = UnitCastingInfo('player')
	if spellId then
		self.cast.ability = Abilities.bySpellId[spellId]
		self.cast.start = start / 1000
		self.cast.ends = ends / 1000
		self.cast.remains = self.cast.ends - self.ctime
	else
		self.cast.ability = nil
		self.cast.start = 0
		self.cast.ends = 0
		self.cast.remains = 0
	end
	self.execute_remains = max(self.cast.remains, self.gcd_remains)
	if self.channel.tick_count > 1 then
		self.channel.ticks = ((self.ctime - self.channel.start) / self.channel.tick_interval) - self.channel.ticks_extra
		self.channel.ticks_remain = (self.channel.ends - self.ctime) / self.channel.tick_interval
	end
	self.fury.current = UnitPower('player', 17)
	if self.cast.ability then
		self.fury.current = self.fury.current - self.cast.ability:Cost() + self.cast.ability:Gain()
	end
	self.fury.current = clamp(self.fury.current, 0, self.fury.max)
	self.fury.deficit = self.fury.max - self.fury.current
	speed, max_speed = GetUnitSpeed('player')
	self.moving = speed ~= 0
	self.movement_speed = max_speed / 7 * 100
	speed_mh, speed_oh = UnitAttackSpeed('player')
	self.swing.mh.speed = speed_mh or 0
	self.swing.oh.speed = speed_oh or 0
	self.swing.mh.remains = max(0, self.swing.mh.last + self.swing.mh.speed - self.time)
	self.swing.oh.remains = max(0, self.swing.oh.last + self.swing.oh.speed - self.time)
	self:UpdateThreat()
	Metamorphosis.remains = Metamorphosis:Remains()
	Metamorphosis.active = Metamorphosis.remains > 0
	if self.spec == SPEC.VENGEANCE then
		SoulFragments:Update()
	end

	TrackedAuras:Purge()
	if Opt.auto_aoe then
		for _, ability in next, Abilities.autoAoe do
			ability:UpdateTargetsHit()
		end
		AutoAoe:Purge()
	end

	self.main = APL[self.spec]:Main()

	if self.channel.interrupt_if then
		self.channel.interruptible = self.channel.ability ~= self.main and self.channel.interrupt_if()
	end
	if self.channel.early_chain_if then
		self.channel.early_chainable = self.channel.ability == self.main and self.channel.early_chain_if()
	end
end

function Player:Init()
	local _
	if not self.initialized then
		UI:ScanActionButtons()
		UI:ScanActionSlots()
		UI:DisableOverlayGlows()
		UI:CreateOverlayGlows()
		UI:HookResourceFrame()
		self.guid = UnitGUID('player')
		self.name = UnitName('player')
		self.initialized = true
	end
	lasikPreviousPanel.ability = nil
	_, self.instance = IsInInstance()
	Events:GROUP_ROSTER_UPDATE()
	Events:PLAYER_SPECIALIZATION_CHANGED('player')
end

function Player:OutOfRange()
	if self.swing.mh.last > VengefulRetreat.last_used then
		return false
	end
	if VengefulRetreat:Previous() then
		return true
	end
	return false
end

-- End Player Functions

-- Start Target Functions

function Target:UpdateHealth(reset)
	Timer.health = 0
	self.health.current = UnitHealth('target')
	self.health.max = UnitHealthMax('target')
	if self.health.current <= 0 then
		self.health.current = Player.health.max
		self.health.max = self.health.current
	end
	if reset then
		for i = 1, 25 do
			self.health.history[i] = self.health.current
		end
	else
		table.remove(self.health.history, 1)
		self.health.history[25] = self.health.current
	end
	self.timeToDieMax = self.health.current / Player.health.max * (
		15 + (Player.spec == SPEC.VENGEANCE and 5 or 0)
	)
	self.health.pct = self.health.max > 0 and (self.health.current / self.health.max * 100) or 100
	self.health.loss_per_sec = (self.health.history[1] - self.health.current) / 5
	self.timeToDie = (
		(self.dummy and 600) or
		(self.health.loss_per_sec > 0 and min(self.timeToDieMax, self.health.current / self.health.loss_per_sec)) or
		self.timeToDieMax
	)
end

function Target:Update()
	if UI:ShouldHide() then
		return UI:Disappear()
	end
	local guid = UnitGUID('target')
	if not guid then
		self.guid = nil
		self.uid = nil
		self.boss = false
		self.dummy = false
		self.stunnable = true
		self.classification = 'normal'
		self.player = false
		self.level = Player.level
		self.hostile = false
		self:UpdateHealth(true)
		if Opt.always_on then
			UI:UpdateCombat()
			lasikPanel:Show()
			return true
		end
		if Opt.previous and Player.combat_start == 0 then
			lasikPreviousPanel:Hide()
		end
		return UI:Disappear()
	end
	if guid ~= self.guid then
		self.guid = guid
		self.uid = ToUID(guid) or 0
		self:UpdateHealth(true)
	end
	self.boss = false
	self.dummy = false
	self.stunnable = true
	self.classification = UnitClassification('target')
	self.player = UnitIsPlayer('target')
	self.hostile = UnitCanAttack('player', 'target') and not UnitIsDead('target')
	self.level = UnitLevel('target')
	if self.level == -1 then
		self.level = Player.level + 3
	end
	if not self.player and self.classification ~= 'minus' and self.classification ~= 'normal' then
		self.boss = self.level >= (Player.level + 3)
		self.stunnable = self.level < (Player.level + 2)
	end
	if self.Dummies[self.uid] then
		self.boss = true
		self.dummy = true
	end
	if self.hostile or Opt.always_on then
		UI:UpdateCombat()
		lasikPanel:Show()
		return true
	end
	UI:Disappear()
end

function Target:TimeToPct(pct)
	if self.health.pct <= pct then
		return 0
	end
	if self.health.loss_per_sec <= 0 then
		return self.timeToDieMax
	end
	return min(self.timeToDieMax, (self.health.current - (self.health.max * (pct / 100))) / self.health.loss_per_sec)
end

function Target:Stunned()
	return FelEruption:Up() or ChaosNova:Up()
end

-- End Target Functions

-- Start Ability Modifications

function Annihilation:Usable()
	if not Metamorphosis.active then
		return false
	end
	return Ability.Usable(self)
end
DeathSweep.Usable = Annihilation.Usable

function ChaosStrike:Usable()
	if Metamorphosis.active then
		return false
	end
	return Ability.Usable(self)
end
BladeDance.Usable = ChaosStrike.Usable

function ThrowGlaive:Cost()
	local cost = Ability.Cost(self)
	if FuriousThrows.known then
		cost = cost + 25
	end
	return max(0, cost)
end

function ThrowGlaive.damage:CastSuccess()
	return -- ignored
end

function VengefulRetreat:Remains()
	return max(0, 1.1 - (Player.time - self.last_used) - Player.execute_remains)
end

function FelEruption:Usable()
	if not Target.stunnable then
		return false
	end
	return Ability.Usable(self)
end

function SigilOfFlame:Duration()
	local duration = Ability.Duration(self)
	if QuickenedSigils.known then
		duration = duration - 1
	end
	return duration
end
SigilOfChains.Duration = SigilOfFlame.Duration
SigilOfMisery.Duration = SigilOfFlame.Duration
SigilOfSilence.Duration = SigilOfFlame.Duration
SigilOfSpite.Duration = SigilOfFlame.Duration
SigilOfDoom.Duration = SigilOfFlame.Duration

function SigilOfFlame:Placed()
	return (Player.time - self.last_used) < (self:Duration() + 0.5)
end
SigilOfChains.Placed = SigilOfFlame.Placed
SigilOfMisery.Placed = SigilOfFlame.Placed
SigilOfSilence.Placed = SigilOfFlame.Placed
SigilOfSpite.Placed = SigilOfFlame.Placed
SigilOfDoom.Placed = SigilOfFlame.Placed

function ImmolationAura:Stack()
	local stack, aura = 0
	for i = 1, 40 do
		aura = UnitAura(self.aura_target, i, self.aura_filter)
		if not aura then
			break
		elseif ImmolationAura.buff_spellIds[id] and (aura.expirationTime - Player.ctime) > Player.execute_remains then
			stack = stack + 1
		end
	end
	return stack
end

function ImmolationAura:MaxStack()
	if AFireInside.known then
		return 5
	end
	return 1
end

function ImmolationAura.damage:CastLanded(dstGUID, event, missType)
	if FieryBrand.known and CharredFlesh.known then
		FieryBrand:CFExtend(dstGUID)
	end
end

function FieryBrand:CastSuccess(...)
	Ability.CastSuccess(self, ...)
	self.cast_trigger = true
end

function FieryBrand:ApplyAura(guid)
	local aura = Ability.ApplyAura(self, guid)
	if not aura then
		return
	end
	if self.cast_trigger then
		self.cast_trigger = false
		aura.main = true
		aura.cf_extend_time = 0
		aura.cf_extends = 0
	end
	return aura
end

function FieryBrand:RefreshAura(guid)
	local aura = self.aura_targets[guid]
	if not aura or self.cast_trigger then
		return self:ApplyAura(guid)
	end
	return aura
end

function FieryBrand:GetMainAura()
	for guid, aura in next, self.aura_targets do
		if aura.main and aura.expires - Player.time > 0 then
			return aura
		end
	end
end

function FieryBrand:CFExtend(guid)
	local aura = self.aura_targets[guid]
	if not aura then
		return
	end
	local main = self:GetMainAura()
	if not main then
		return
	end
	if Player.time > main.cf_extend_time then
		if main.cf_extends >= 8 then
			return -- after 8 Charred Flesh extensions, Fiery Brand can't be extended again
		end
		main.cf_extend_time = Player.time
		main.cf_extends = main.cf_extends + 1
	end
	aura.expires = aura.expires + (CharredFlesh.rank * 0.25)
end

function FieryBrand:AnyRemainsUnder(seconds)
	for guid, aura in next, self.aura_targets do
		if AutoAoe.targets[guid] and aura.expires < (Player.time + seconds) then
			return true
		end
	end
	return false
end

SoulFragments.spawning = {}
SoulFragments.current = 0
SoulFragments.incoming = 0
SoulFragments.total = 0

function SoulFragments:Update()
	local count = 0
	for i = #self.spawning, 1, -1 do
		if (Player.time - self.spawning[i]) >= 1 then -- fragment expired/never existed
			table.remove(self.spawning, i)
		elseif (self.spawning[i] + 0.8) < (Player.time + Player.execute_remains) then
			count = count + 1
		end
	end
	self.current = self.buff:Stack()
	self.incoming = count
	self.total = self.current + self.incoming
end

function SoulFragments:CastSuccess()
	if #self.spawning > 0 then
		table.remove(self.spawning, 1)
	end
end

function SoulFragments:Spawn(amount, delay)
	for i = 1, amount do
		self.spawning[#self.spawning + 1] = Player.time + (delay or 0)
	end
end

function Shear:Gain()
	local gain = Ability.Gain(self)
	if ShearFury.known then
		gain = gain + 10
	end
	return gain
end

function Fracture:CastSuccess(...)
	Ability.CastSuccess(self, ...)
	SoulFragments:Spawn(2)
end

function Shear:CastSuccess(...)
	Ability.CastSuccess(self, ...)
	SoulFragments:Spawn(1)
end

function ImmolationAura:CastSuccess(...)
	Ability.CastSuccess(self, ...)
	if SoulFragments.known and Fallout.known then
		local fragments = min(5, floor(Player.enemies * 0.5))
		if fragments > 0 then
			SoulFragments:Spawn(fragments)
		end
	end
end
ConsumingFire.CastSuccess = ImmolationAura.CastSuccess

function BulkExtraction:CastSuccess(...)
	Ability.CastSuccess(self, ...)
	SoulFragments:Spawn(min(5, Player.enemies))
end

function SigilOfSpite:CastSuccess(...)
	Ability.CastSuccess(self, ...)
	if SoulFragments.known then
		SoulFragments:Spawn(3 + (SoulSigils.known and 1 or 0), self:Duration())
	end
end

function SigilOfFlame:CastSuccess(...)
	Ability.CastSuccess(self, ...)
	if SoulFragments.known and SoulSigils.known then
		SoulFragments:Spawn(1, self:Duration())
	end
end
SigilOfChains.CastSuccess = SigilOfFlame.CastSuccess
SigilOfMisery.CastSuccess = SigilOfFlame.CastSuccess
SigilOfSilence.CastSuccess = SigilOfFlame.CastSuccess
SigilOfDoom.CastSuccess = SigilOfFlame.CastSuccess

Demonsurge.up = {
	[SoulSunder] = false,
	[SpiritBurst] = false,
}

function Demonsurge:Reset()
	for ability in next, self.up do
		self.up[ability] = true
	end
end

function MetamorphosisH:Full()
	return self.active and self.full
end
MetamorphosisV.Full = MetamorphosisH.Full

function MetamorphosisH:CastSuccess(...)
	self.full = true
	if Demonsurge.known then
		Demonsurge:Reset()
	end
	Ability.CastSuccess(self, ...)
end
MetamorphosisV.CastSuccess = MetamorphosisH.CastSuccess

function SoulCleave:Usable(...)
	if Demonsurge.known and Metamorphosis.active then
		return false
	end
	return Ability.Usable(self, ...)
end

function SoulSunder:Usable(...)
	return Metamorphosis.active and Ability.Usable(self, ...)
end

function SoulSunder:CastSuccess(...)
	Demonsurge.up[self] = false
	Ability.CastSuccess(self, ...)
end
SpiritBurst.CastSuccess = SoulSunder.CastSuccess

function SpiritBomb:Usable(...)
	if SoulFragments.total < 1 then
		return false
	end
	if Demonsurge.known and Metamorphosis.active then
		return false
	end
	return Ability.Usable(self, ...)
end

function SpiritBurst:Usable(...)
	if SoulFragments.total < 1 then
		return false
	end
	return Metamorphosis.active and Ability.Usable(self, ...)
end

function FelDevastation:Cooldown()
	if DemonicIntensity.known and Metamorphosis:Full() then
		return max(Metamorphosis.remains, Ability.Cooldown(self))
	end
	return Ability.Cooldown(self)
end

function FelDevastation:CastSuccess(...)
	if Demonic.known and Demonsurge.known then
		Demonsurge:Reset()
	end
	Ability.CastSuccess(self, ...)
end
EyeBeam.CastSuccess = FelDevastation.CastSuccess

function FelDesolation:Usable(...)
	return Metamorphosis:Full() and Ability.Usable(self, ...)
end

function ImmolationAura:Usable(...)
	if DemonicIntensity.known and Metamorphosis:Full() then
		return false
	end
	return Ability.Usable(self, ...)
end

function ConsumingFire:Usable(...)
	return Metamorphosis:Full() and Ability.Usable(self, ...)
end

function SigilOfFlame:Usable(...)
	if DemonicIntensity.known and Metamorphosis:Full() then
		return false
	end
	return Ability.Usable(self, ...)
end

function SigilOfDoom:Usable(...)
	return Metamorphosis:Full() and Ability.Usable(self, ...)
end

-- End Ability Modifications

local function UseCooldown(ability, overwrite)
	if Opt.cooldown and (not Opt.boss_only or Target.boss) and (not Player.cd or overwrite) then
		Player.cd = ability
	end
end

local function UseExtra(ability, overwrite)
	if not Player.extra or overwrite then
		Player.extra = ability
	end
end

-- Begin Action Priority Lists

APL[SPEC.NONE].Main = function(self)
end

APL[SPEC.HAVOC].Main = function(self)
	if Player:TimeInCombat() == 0 then
--[[
actions.precombat=flask
actions.precombat+=/augmentation
actions.precombat+=/food
actions.precombat+=/snapshot_stats
actions.precombat+=/variable,name=3min_trinket,value=trinket.1.cooldown.duration=180|trinket.2.cooldown.duration=180
actions.precombat+=/variable,name=trinket_sync_slot,value=1,if=trinket.1.has_stat.any_dps&(!trinket.2.has_stat.any_dps|trinket.1.cooldown.duration>=trinket.2.cooldown.duration)
actions.precombat+=/variable,name=trinket_sync_slot,value=2,if=trinket.2.has_stat.any_dps&(!trinket.1.has_stat.any_dps|trinket.2.cooldown.duration>trinket.1.cooldown.duration)
actions.precombat+=/arcane_torrent
actions.precombat+=/immolation_aura
actions.precombat+=/sigil_of_flame,if=!equipped.algethar_puzzle_box
]]
		if ImmolationAura:Usable() then
			return ImmolationAura
		end
		if SigilOfFlame:Usable() then
			return SigilOfFlame
		end
	else

	end
--[[
actions=auto_attack,if=!buff.out_of_range.up
actions+=/retarget_auto_attack,line_cd=1,target_if=min:debuff.burning_wound.remains,if=talent.burning_wound&talent.demon_blades&active_dot.burning_wound<(spell_targets>?3)
actions+=/retarget_auto_attack,line_cd=1,target_if=min:!target.is_boss,if=talent.burning_wound&talent.demon_blades&active_dot.burning_wound=(spell_targets>?3)
actions+=/variable,name=blade_dance,value=talent.first_blood|talent.trail_of_ruin|talent.chaos_theory&buff.chaos_theory.down|spell_targets.blade_dance1>1
actions+=/variable,name=pooling_for_blade_dance,value=variable.blade_dance&fury<(75-talent.demon_blades*20)&cooldown.blade_dance.remains<gcd.max
actions+=/variable,name=pooling_for_eye_beam,value=talent.demonic&!talent.blind_fury&cooldown.eye_beam.remains<(gcd.max*3)&fury.deficit>30
actions+=/variable,name=waiting_for_momentum,value=talent.momentum&!buff.momentum.up|talent.inertia&!buff.inertia.up
actions+=/variable,name=holding_meta,value=(talent.demonic&talent.essence_break)&variable.3min_trinket&fight_remains>cooldown.metamorphosis.remains+30+talent.shattered_destiny*60&cooldown.metamorphosis.remains<20&cooldown.metamorphosis.remains>action.eye_beam.execute_time+gcd.max*(talent.inner_demon+2)
actions+=/invoke_external_buff,name=power_infusion,if=buff.metamorphosis.up
actions+=/immolation_aura,if=talent.ragefire&active_enemies>=3&(cooldown.blade_dance.remains|debuff.essence_break.down)
actions+=/disrupt
actions+=/immolation_aura,if=talent.a_fire_inside&talent.inertia&buff.unbound_chaos.down&full_recharge_time<gcd.max*2&debuff.essence_break.down
actions+=/fel_rush,if=buff.unbound_chaos.up&(action.immolation_aura.charges=2&debuff.essence_break.down|prev_gcd.1.eye_beam&buff.inertia.up&buff.inertia.remains<3)
actions+=/the_hunt,if=time<10&buff.potion.up&(!talent.inertia|buff.metamorphosis.up&debuff.essence_break.down)
actions+=/immolation_aura,if=talent.inertia&(cooldown.eye_beam.remains<gcd.max*2|buff.metamorphosis.up)&cooldown.essence_break.remains<gcd.max*3&buff.unbound_chaos.down&buff.inertia.down&debuff.essence_break.down
actions+=/immolation_aura,if=talent.inertia&buff.unbound_chaos.down&(full_recharge_time<cooldown.essence_break.remains|!talent.essence_break)&debuff.essence_break.down&(buff.metamorphosis.down|buff.metamorphosis.remains>6)&cooldown.blade_dance.remains&(fury<75|cooldown.blade_dance.remains<gcd.max*2)
actions+=/fel_rush,if=buff.unbound_chaos.up&(buff.unbound_chaos.remains<gcd.max*2|target.time_to_die<gcd.max*2)
actions+=/fel_rush,if=talent.inertia&buff.inertia.down&buff.unbound_chaos.up&cooldown.eye_beam.remains+3>buff.unbound_chaos.remains&(cooldown.blade_dance.remains|cooldown.essence_break.up)
actions+=/fel_rush,if=buff.unbound_chaos.up&talent.inertia&buff.inertia.down&(buff.metamorphosis.up|cooldown.essence_break.remains>10)
actions+=/call_action_list,name=cooldown
actions+=/call_action_list,name=meta_end,if=buff.metamorphosis.up&buff.metamorphosis.remains<gcd.max&active_enemies<3
actions+=/pick_up_fragment,type=demon,if=demon_soul_fragments>0&(cooldown.eye_beam.remains<6|buff.metamorphosis.remains>5)&buff.empowered_demon_soul.remains<3|fight_remains<17
actions+=/pick_up_fragment,mode=nearest,type=lesser,if=fury.deficit>=45&(!cooldown.eye_beam.ready|fury<30)
actions+=/annihilation,if=buff.inner_demon.up&cooldown.metamorphosis.remains<=gcd*3
actions+=/vengeful_retreat,use_off_gcd=1,if=cooldown.eye_beam.remains<0.3&cooldown.essence_break.remains<gcd.max*2&time>5&fury>=30&gcd.remains<0.1&talent.inertia
actions+=/vengeful_retreat,use_off_gcd=1,if=talent.initiative&talent.essence_break&time>1&(cooldown.essence_break.remains>15|cooldown.essence_break.remains<gcd.max&(!talent.demonic|buff.metamorphosis.up|cooldown.eye_beam.remains>15+(10*talent.cycle_of_hatred)))&(time<30|gcd.remains-1<0)&(!talent.initiative|buff.initiative.remains<gcd.max|time>4)
actions+=/vengeful_retreat,use_off_gcd=1,if=talent.initiative&talent.essence_break&time>1&(cooldown.essence_break.remains>15|cooldown.essence_break.remains<gcd.max*2&(buff.initiative.remains<gcd.max&!variable.holding_meta&cooldown.eye_beam.remains<=gcd.remains&(raid_event.adds.in>(40-talent.cycle_of_hatred*15))&fury>30|!talent.demonic|buff.metamorphosis.up|cooldown.eye_beam.remains>15+(10*talent.cycle_of_hatred)))&(buff.unbound_chaos.down|buff.inertia.up)
actions+=/vengeful_retreat,use_off_gcd=1,if=talent.initiative&!talent.essence_break&time>1&((!buff.initiative.up|prev_gcd.1.death_sweep&cooldown.metamorphosis.up&talent.chaotic_transformation)&talent.initiative)
actions+=/fel_rush,if=talent.momentum.enabled&buff.momentum.remains<gcd.max*2&cooldown.eye_beam.remains<=gcd.max&debuff.essence_break.down&cooldown.blade_dance.remains
actions+=/fel_rush,if=talent.inertia.enabled&!buff.inertia.up&buff.unbound_chaos.up&(buff.metamorphosis.up|cooldown.eye_beam.remains>action.immolation_aura.recharge_time&cooldown.eye_beam.remains>4)&debuff.essence_break.down&cooldown.blade_dance.remains
actions+=/essence_break,if=(active_enemies>desired_targets|raid_event.adds.in>40)&(buff.metamorphosis.remains>gcd.max*3|cooldown.eye_beam.remains>10)&(!talent.tactical_retreat|buff.tactical_retreat.up|time<10)&(buff.vengeful_retreat_movement.remains<gcd.max*0.5|time>0)&cooldown.blade_dance.remains<=3.1*gcd.max|fight_remains<6
actions+=/death_sweep,if=variable.blade_dance&(!talent.essence_break|cooldown.essence_break.remains>gcd.max*2)&buff.fel_barrage.down
actions+=/the_hunt,if=debuff.essence_break.down&(time<10|cooldown.metamorphosis.remains>10|!equipped.algethar_puzzle_box)&(raid_event.adds.in>90|active_enemies>3|time_to_die<10)&time>10
actions+=/fel_barrage,if=active_enemies>desired_targets|raid_event.adds.in>30&fury.deficit<20&buff.metamorphosis.down
actions+=/glaive_tempest,if=(active_enemies>desired_targets|raid_event.adds.in>10)&(debuff.essence_break.down|active_enemies>1)&buff.fel_barrage.down
actions+=/annihilation,if=buff.inner_demon.up&cooldown.eye_beam.remains<=gcd&buff.fel_barrage.down
actions+=/fel_rush,if=talent.momentum.enabled&cooldown.eye_beam.remains<=gcd.max&buff.momentum.remains<5&buff.metamorphosis.down
actions+=/eye_beam,if=active_enemies>desired_targets|raid_event.adds.in>(40-talent.cycle_of_hatred*15)&!debuff.essence_break.up&(cooldown.metamorphosis.remains>30-talent.cycle_of_hatred*15|cooldown.metamorphosis.remains<gcd.max*2&(!talent.essence_break|cooldown.essence_break.remains<gcd.max*1.5))&(buff.metamorphosis.down|buff.metamorphosis.remains>gcd.max|!talent.restless_hunter)&(talent.cycle_of_hatred|!talent.initiative|cooldown.vengeful_retreat.remains>5|time<10)&buff.inner_demon.down|fight_remains<15
actions+=/blade_dance,if=variable.blade_dance&(cooldown.eye_beam.remains>5|equipped.algethar_puzzle_box&cooldown.metamorphosis.remains>(cooldown.blade_dance.duration)|!talent.demonic|(raid_event.adds.in>cooldown&raid_event.adds.in<25))&buff.fel_barrage.down
actions+=/sigil_of_flame,if=talent.any_means_necessary&debuff.essence_break.down&active_enemies>=4
actions+=/throw_glaive,if=talent.soulscar&(active_enemies>desired_targets|raid_event.adds.in>full_recharge_time+9)&spell_targets>=(2-talent.furious_throws)&!debuff.essence_break.up&(full_recharge_time<gcd.max*3|active_enemies>1)
actions+=/immolation_aura,if=active_enemies>=2&fury<70&debuff.essence_break.down
actions+=/annihilation,if=!variable.pooling_for_blade_dance&(cooldown.essence_break.remains|!talent.essence_break)&buff.fel_barrage.down
actions+=/felblade,if=fury.deficit>=40&talent.any_means_necessary&debuff.essence_break.down|talent.any_means_necessary&debuff.essence_break.down
actions+=/sigil_of_flame,if=fury.deficit>=40&talent.any_means_necessary
actions+=/throw_glaive,if=talent.soulscar&(active_enemies>desired_targets|raid_event.adds.in>full_recharge_time+9)&spell_targets>=(2-talent.furious_throws)&!debuff.essence_break.up
actions+=/immolation_aura,if=buff.immolation_aura.stack<buff.immolation_aura.max_stack&(!talent.ragefire|active_enemies>desired_targets|raid_event.adds.in>15)&buff.out_of_range.down&(!buff.unbound_chaos.up|!talent.unbound_chaos)&(recharge_time<cooldown.essence_break.remains|!talent.essence_break&cooldown.eye_beam.remains>recharge_time)
actions+=/chaos_strike,if=!variable.pooling_for_blade_dance&!variable.pooling_for_eye_beam&buff.fel_barrage.down
actions+=/sigil_of_flame,if=raid_event.adds.in>15&fury.deficit>=30&buff.out_of_range.down
actions+=/felblade,if=fury.deficit>=40
actions+=/fel_rush,if=!talent.momentum&talent.demon_blades&!cooldown.eye_beam.ready&(charges=2|(raid_event.movement.in>10&raid_event.adds.in>10))&(buff.unbound_chaos.down)&(recharge_time<cooldown.essence_break.remains|!talent.essence_break)
actions+=/demons_bite,target_if=min:debuff.burning_wound.remains,if=talent.burning_wound&debuff.burning_wound.remains<4&active_dot.burning_wound<(spell_targets>?3)
actions+=/fel_rush,if=!talent.momentum&!talent.demon_blades&spell_targets>1&(charges=2|(raid_event.movement.in>10&raid_event.adds.in>10))&(buff.unbound_chaos.down)
actions+=/sigil_of_flame,if=raid_event.adds.in>15&fury.deficit>=30&buff.out_of_range.down
actions+=/demons_bite
actions+=/fel_rush,if=talent.momentum&buff.momentum.remains<=20
actions+=/fel_rush,if=movement.distance>15|(buff.out_of_range.up&!talent.momentum)
actions+=/vengeful_retreat,if=!talent.initiative&movement.distance>15
actions+=/throw_glaive,if=(talent.demon_blades|buff.out_of_range.up)&!debuff.essence_break.up&buff.out_of_range.down
]]
	self.use_cds = Opt.cooldown and (Target.boss or Target.player or (not Opt.boss_only and Target.timeToDie > Opt.cd_ttd) or Metamorphosis.active)
	self.blade_dance = FirstBlood.known or TrailOfRuin.known or (ChaosTheory.known and ChaosTheory:Down()) or Player.enemies > 1
	self.pooling_for_blade_dance = self.blade_dance and Player.fury.current < (75 - (DemonBlades.known and 20 or 0)) and BladeDance:Ready(Player.gcd)
	self.pooling_for_eye_beam = Demonic.known and not BlindFury.known and EyeBeam:Ready(Player.gcd * 3) and Player.fury.deficit > 30
	self.waiting_for_momentum = (Momentum.known and Momentum:Down()) or (Inertia.known and Inertia:Down())
	self.in_fel_barrage = FelBarrage.known and FelBarrage:Up()
	self.in_essence_break = EssenceBreak.known and EssenceBreak:Up()
	self.holding_meta = (Demonic.known and EssenceBreak.known) and false
	if ImmolationAura:Usable() and Ragefire.known and Player.enemies >= 3 and (not BladeDance:Ready() or not self.in_essence_break) then
		return ImmolationAura
	end
	if ImmolationAura:Usable() and AFireInside.known and Inertia.known and UnboundChaos:Down() and ImmolationAura:FullRechargeTime() < (Player.gcd * 2) and not self.in_essence_break then
		return ImmolationAura
	end
	if FelRush:Usable() and UnboundChaos:Up() and (
		(ImmolationAura:Charges() >= 2 and not self.in_essence_break) or
		(Inertia.known and EyeBeam:Previous() and Inertia:Up() and Inertia:Remains() < 3)
	) then
		UseCooldown(FelRush)
	end
	if TheHunt:Usable() and Player:TimeInCombat() < 10 and (not Inertia.known or (Metamorphosis.active and not self.in_essence_break)) then
		UseCooldown(TheHunt)
	end
	if ImmolationAura:Usable() and Inertia.known and (
		((EyeBeam:Ready(Player.gcd * 2) or Metamorphosis.active) and (not EssenceBreak.known or EssenceBreak:Ready(Player.gcd * 3)) and UnboundChaos.known and Inertia:Down() and not self.in_essence_break) or
		(UnboundChaos:Down() and (not EssenceBreak.known or EssenceBreak:Ready(ImmolationAura:FullRechargeTime())) and not self.in_essence_break and (not Metamorphosis.active or Metamorphosis.remains > 6) and not BladeDance:Ready() and (Player.fury.current < 75 or BladeDance:Ready(Player.gcd * 2)))
	) then
		return ImmolationAura
	end
	if FelRush:Usable() and UnboundChaos:Up() and (
		(UnboundChaos:Remains() < (Player.gcd * 2) or Target.timeToDie < (Player.gcd * 2)) or
		(Inertia.known and Inertia:Down() and (
			((EyeBeam:Cooldown() + 3) > UnboundChaos:Remains() and (not BladeDance:Ready() or EssenceBreak:Ready())) or
			(Metamorphosis.active or not EssenceBreak:Ready(10))
		))
	) then
		UseCooldown(FelRush)
	end
	if self.use_cds then
		self:cooldown()
	end
	if Metamorphosis.active and Metamorphosis.remains < Player.gcd and Player.enemies < 3 then
		local apl = self:meta_end()
		if apl then return apl end
	end
--[[
actions+=/pick_up_fragment,type=demon,if=demon_soul_fragments>0&(cooldown.eye_beam.remains<6|buff.metamorphosis.remains>5)&buff.empowered_demon_soul.remains<3|fight_remains<17
actions+=/pick_up_fragment,mode=nearest,type=lesser,if=fury.deficit>=45&(!cooldown.eye_beam.ready|fury<30)
]]
	if Annihilation:Usable() and InnerDemon:Up() and Metamorphosis:Ready(Player.gcd * 3) then
		return Annihilation
	end
	if VengefulRetreat:Usable() and (
		(Inertia.known and EyeBeam:Ready(0.3) and EssenceBreak:Ready(Player.gcd * 2) and Player:TimeInCombat() > 5 and Player.fury.current >= 30) or
		(Initiative.known and EssenceBreak.known and Player:TimeInCombat() > 1 and (
				((not EssenceBreak:Ready(15) or (EssenceBreak:Ready(Player.gcd) and (not Demonic.known or Metamorphosis.active or not EyeBeam:Ready(15 + (CycleOfHatred.known and 10 or 0))))) and (not Initiative.known or Initiative:Remains() < Player.gcd or Player:TimeInCombat() > 4)) or
				((not EssenceBreak:Ready(15) or (EssenceBreak:Ready(Player.gcd * 2) and (Initiative:Remains() < Player.gcd and not self.holding_meta and EyeBeam:Ready(Player.gcd) and Player.fury.current > 30)) or not Demonic.known or Metamorphosis.active or not EyeBeam:Ready(15 + (CycleOfHatred.known and 10 or 0))) and (UnboundChaos:Down() or Inertia:Up()))
		)) or
		(Initiative.known and not EssenceBreak.known and Player:TimeInCombat() > 1 and Initiative:Down())
	) then
		UseCooldown(VengefulRetreat)
	end
	if FelRush:Usable() and not self.in_essence_break and not BladeDance:Ready() and (
		(Momentum.known and Momentum:Remains() < (Player.gcd * 2) and EyeBeam:Ready(Player.gcd)) or
		(Inertia.known and Inertia:Down() and UnboundChaos:Up() and (Metamorphosis.active or (not EyeBeam:Ready(ImmolationAura:Cooldown()) and not EyeBeam:Ready(4))))
	) then
		UseCooldown(FelRush)
	end
	if self.use_cds and EssenceBreak:Usable() and (
		(Target.boss and Target.timeToDie < 6) or
		((Metamorphosis.remains > (Player.gcd * 3) or not EyeBeam:Ready(10)) and (not TacticalRetreat.known or TacticalRetreat:Up() or Player:TimeInCombat() < 10) and BladeDance:Ready(Player.gcd * 3.1))
	) then
		UseCooldown(EssenceBreak)
	end
	if DeathSweep:Usable() and self.blade_dance and (not EssenceBreak.known or not EssenceBreak:Ready(Player.gcd * 2)) and not self.in_fel_barrage then
		return DeathSweep
	end
	if self.use_cds and TheHunt:Usable() and not self.in_essence_break then
		UseCooldown(TheHunt)
	end
	if self.use_cds and FelBarrage:Usable() and Player.fury.deficit < 20 and not Metamorphosis.active then
		UseCooldown(FelBarrage)
	end
	if GlaiveTempest:Usable() and (not self.in_essence_break or Player.enemies > 1) and not self.in_fel_barrage then
		UseCooldown(GlaiveTempest)
	end
	if Annihilation:Usable() and InnerDemon:Up() and EyeBeam:Ready(Player.gcd) and not self.in_fel_barrage then
		return Annihilation
	end
	if FelRush:Usable() and Momentum.known and EyeBeam:Ready(Player.gcd) and Momentum:Remains() < 5 and not Metamorphosis.active then
		UseCooldown(FelRush)
	end
	if self.use_cds and EyeBeam:Usable() and (
		Player.enemies > 1 or
		(Target.boss and Target.timeToDie < 15) or
		(not self.in_essence_break and InnerDemon:Down() and (not Metamorphosis:Ready(30 - (CycleOfHatred.known and 15 or 0)) or (Metamorphosis:Ready(Player.gcd * 2) and (not EssenceBreak.known or EssenceBreak:Ready(Player.gcd * 1.5)))) and (not Metamorphosis.active or Metamorphosis.remains > Player.gcd or not RestlessHunter.known) and (CycleOfHatred.known or not Initiative.known or not VengefulRetreat:Ready(5) or Player:TimeInCombat() < 10))
	) then
		UseCooldown(EyeBeam)
	end
	if BladeDance:Usable() and self.blade_dance and not self.in_fel_barrage then
		return BladeDance
	end
	if SigilOfFlame:Usable() and AnyMeansNecessary.known and not self.in_essence_break and Player.enemies >= 4 then
		return SigilOfFlame
	end
	if ThrowGlaive:Usable() and Soulscar.known and Player.enemies >= (2 - (FuriousThrows.known and 1 or 0)) and not self.in_essence_break and (ThrowGlaive:FullRechargeTime() < (Player.gcd * 3) or Player.enemies > 1) then
		return ThrowGlaive
	end
	if ImmolationAura:Usable() and Player.enemies >= 2 and Player.fury.current < 70 and not self.in_essence_break then
		return ImmolationAura
	end
	if Annihilation:Usable() and not self.pooling_for_blade_dance and (not EssenceBreak.known or not EssenceBreak:Ready()) and not self.in_fel_barrage then
		return Annihilation
	end
	if AnyMeansNecessary.known then
		if Felblade:Usable() and not self.in_essence_break then
			return Felblade
		end
		if SigilOfFlame:Usable() and Player.fury.deficit >= 40 then
			return SigilOfFlame
		end
	end
	if ThrowGlaive:Usable() and Soulscar.known and Player.enemies >= (2 - (FuriousThrows.known and 1 or 0)) and not self.in_essence_break then
		return ThrowGlaive
	end
	if ImmolationAura:Usable() and ImmolationAura:Stack() < ImmolationAura:MaxStack() and (not UnboundChaos.known or UnboundChaos:Down()) and not Player:OutOfRange() and (ImmolationAura:FullRechargeTime() < EssenceBreak:Cooldown() or (not EssenceBreak.known and not EyeBeam:Ready(ImmolationAura:FullRechargeTime()))) then
		return ImmolationAura
	end
	if ChaosStrike:Usable() and not self.pooling_for_blade_dance and not self.pooling_for_eye_beam and not self.in_fel_barrage then
		return ChaosStrike
	end
	if SigilOfFlame:Usable() and Player.fury.deficit >= 30 then
		return SigilOfFlame
	end
	if Felblade:Usable() and Player.fury.deficit >= 40 then
		return Felblade
	end
	if FelRush:Usable() and not Momentum.known and DemonBlades.known and not EyeBeam:Ready() and UnboundChaos:Down() and (not EssenceBreak.known or FelRush:FullRechargeTime() < EssenceBreak:Cooldown()) then
		UseCooldown(FelRush)
	end
	if DemonsBite:Usable() and BurningWound.known and BurningWound:Remains() < 4 and BurningWound:Ticking() < min(3, Player.enemies) then
		return DemonsBite
	end
	if FelRush:Usable() and not Momentum.known and not DemonBlades.known and Player.enemies > 1 and UnboundChaos:Down() then
		UseCooldown(FelRush)
	end
	if SigilOfFlame:Usable() and Player.fury.deficit >= 30 then
		return SigilOfFlame
	end
	if DemonsBite:Usable() then
		return DemonsBite
	end
	if FelRush:Usable() and Momentum.known and Momentum:Remains() <= 20 then
		UseCooldown(FelRush)
	end
	if ThrowGlaive:Usable() and (DemonBlades.known or Player:OutOfRange()) and not self.in_essence_break then
		return ThrowGlaive
	end
end

APL[SPEC.HAVOC].cooldown = function(self)
--[[
actions.cooldown=metamorphosis,if=!talent.demonic&((!talent.chaotic_transformation|cooldown.eye_beam.remains>20)&active_enemies>desired_targets|raid_event.adds.in>60|fight_remains<25)
actions.cooldown+=/metamorphosis,if=talent.demonic&(!talent.chaotic_transformation&cooldown.eye_beam.remains|cooldown.eye_beam.remains>20&(!variable.blade_dance|prev_gcd.1.death_sweep|prev_gcd.2.death_sweep)|fight_remains<25+talent.shattered_destiny*70&cooldown.eye_beam.remains&cooldown.blade_dance.remains)&buff.inner_demon.down
actions.cooldown+=/potion,if=buff.metamorphosis.remains>25|buff.metamorphosis.up&cooldown.metamorphosis.ready|fight_remains<60|time>0.1&time<10
actions.cooldown+=/sigil_of_spite,if=(active_enemies>desired_targets|raid_event.adds.in>30)&debuff.essence_break.down
actions.cooldown+=/use_items,slots=trinket1,if=(variable.trinket_sync_slot=1&(buff.metamorphosis.up|(!talent.demonic.enabled&cooldown.metamorphosis.remains>(fight_remains>?trinket.1.cooldown.duration%2))|fight_remains<=20)|(variable.trinket_sync_slot=2&!trinket.2.cooldown.ready)|!variable.trinket_sync_slot)&(!talent.initiative|buff.initiative.up)
actions.cooldown+=/use_items,slots=trinket2,if=(variable.trinket_sync_slot=2&(buff.metamorphosis.up|(!talent.demonic.enabled&cooldown.metamorphosis.remains>(fight_remains>?trinket.2.cooldown.duration%2))|fight_remains<=20)|(variable.trinket_sync_slot=1&!trinket.1.cooldown.ready)|!variable.trinket_sync_slot)&(!talent.initiative|buff.initiative.up)
]]
	if Metamorphosis:Usable() and (
		(not Demonic.known and (not ChaoticTransformation.known or not EyeBeam:Ready(20))) or
		(Demonic.known and (not InnerDemon.known or InnerDemon:Down()) and (
			(not ChaoticTransformation.known and not EyeBeam:Ready()) or
			(not EyeBeam:Ready(20) and (not self.blade_dance or DeathSweep:Previous(1) or DeathSweep:Previous(2))) or
			(Target.boss and Target.timeToDie < (25 + (ShatteredDestiny.known and 70 or 0)) and not EyeBeam:Ready() and not BladeDance:Ready())
		))
	) then
		return UseCooldown(Metamorphosis)
	end
	if SigilOfSpite:Usable() and (not EssenceBreak.known or not self.in_essence_break) then
		return UseCooldown(SigilOfSpite)
	end
	if Opt.trinket and (Metamorphosis.active or not Metamorphosis:Ready(20) or (Target.boss and Target.timeToDie < 20)) and (not Initiative.known or Initiative:Up()) then
		if Trinket1:Usable() then
			return UseCooldown(Trinket1)
		elseif Trinket2:Usable() then
			return UseCooldown(Trinket2)
		end
	end
end

APL[SPEC.HAVOC].meta_end = function(self)
--[[
actions.meta_end=death_sweep,if=buff.fel_barrage.down
actions.meta_end+=/annihilation,if=buff.fel_barrage.down
]]
	if DeathSweep:Usable() and not self.in_fel_barrage then
		return DeathSweep
	end
	if Annihilation:Usable() and not self.in_fel_barrage then
		return Annihilation
	end
end

APL[SPEC.VENGEANCE].precombat_variables = function(self)
--[[
actions.precombat+=/variable,name=spirit_bomb_soul_fragments_not_in_meta,op=setif,value=4,value_else=5,condition=talent.fracture
actions.precombat+=/variable,name=spirit_bomb_soul_fragments_in_meta,op=setif,value=3,value_else=4,condition=talent.fracture
actions.precombat+=/variable,name=vulnerability_frailty_stack,op=setif,value=1,value_else=0,condition=talent.vulnerability
actions.precombat+=/variable,name=cooldown_frailty_requirement_st,op=setif,value=6*variable.vulnerability_frailty_stack,value_else=variable.vulnerability_frailty_stack,condition=talent.soulcrush
actions.precombat+=/variable,name=cooldown_frailty_requirement_aoe,op=setif,value=5*variable.vulnerability_frailty_stack,value_else=variable.vulnerability_frailty_stack,condition=talent.soulcrush
]]
	self.spirit_bomb_soul_fragments_not_in_meta = Fracture.known and 4 or 5
	self.spirit_bomb_soul_fragments_in_meta = Fracture.known and 3 or 4
	self.cooldown_frailty_requirement_st = (Vulnerability.known and 1 or 0) * (SoulCrush.known and 6 or 1)
	self.cooldown_frailty_requirement_aoe = (Vulnerability.known and 1 or 0) * (SoulCrush.known and 5 or 1)
	self.filler_fury = (Fracture.known and Fracture:Gain()) or (Shear.known and Shear:Gain()) or 0
end

APL[SPEC.VENGEANCE].Main = function(self)
	if Player:TimeInCombat() == 0 then
--[[
actions.precombat=flask
actions.precombat+=/augmentation
actions.precombat+=/food
actions.precombat+=/snapshot_stats
actions.precombat+=/sigil_of_flame
actions.precombat+=/immolation_aura
]]
		if SigilOfDoom:Usable() and not SigilOfDoom:Placed() then
			return SigilOfDoom
		end
		if SigilOfFlame:Usable() and not SigilOfFlame:Placed() then
			return SigilOfFlame
		end
	end
--[[
actions=variable,name=trinket_1_buffs,value=trinket.1.has_use_buff|(trinket.1.has_buff.strength|trinket.1.has_buff.mastery|trinket.1.has_buff.versatility|trinket.1.has_buff.haste|trinket.1.has_buff.crit)
actions+=/variable,name=trinket_2_buffs,value=trinket.2.has_use_buff|(trinket.2.has_buff.strength|trinket.2.has_buff.mastery|trinket.2.has_buff.versatility|trinket.2.has_buff.haste|trinket.2.has_buff.crit)
actions+=/variable,name=trinket_1_exclude,value=0
actions+=/variable,name=dont_spend_fury,op=setif,condition=(cooldown.fel_devastation.remains<(action.soul_cleave.execute_time+gcd.remains))&fury<50,value=1,value_else=0
actions+=/auto_attack
actions+=/disrupt,if=target.debuff.casting.react
actions+=/infernal_strike,use_off_gcd=1
actions+=/demon_spikes,use_off_gcd=1,if=!buff.demon_spikes.up&!cooldown.pause_action.remains
actions+=/metamorphosis,use_off_gcd=1
actions+=/potion,use_off_gcd=1
actions+=/call_action_list,name=externals
actions+=/call_action_list,name=trinkets
actions+=/call_action_list,name=fiery_demise,if=talent.fiery_demise&active_dot.fiery_brand>0
actions+=/call_action_list,name=maintenance
actions+=/run_action_list,name=single_target,if=active_enemies<=1
actions+=/run_action_list,name=small_aoe,if=active_enemies>1&active_enemies<=5
actions+=/run_action_list,name=big_aoe,if=active_enemies>=6
]]
	self.dont_spend_fury = FelDevastation:Ready(Player.gcd * 2) and Player.fury.current < 50
	self.soul_cleave_condition = not SpiritBomb.known or not (SoulFragments.incoming > 1 or SigilOfSpite:Placed())
	self:defensives()
	self:trinkets()
	if ViolentTransformation.known and Metamorphosis:Usable() and not Metamorphosis.active and not FelDevastation:Ready(8) and SigilOfFlame:ChargesFractional() < 0.8 then
		UseCooldown(Metamorphosis)
	end
	local apl
	if Demonsurge.known and Metamorphosis.active then
		apl = self:demonsurge()
		if apl then return apl end
	end
	if FieryDemise.known and FieryBrand:Ticking() > 0 then
		apl = self:fiery_demise()
		if apl then return apl end
	end
	apl = self:maintenance()
	if apl then return apl end
	if Player.enemies >= 6 then
		return self:big_aoe()
	elseif Player.enemies > 1 then
		return self:small_aoe()
	end
	return self:single_target()
end

APL[SPEC.VENGEANCE].defensives = function(self)
	if DemonSpikes:Usable() and DemonSpikes:Down() and Player:UnderAttack() and (DemonSpikes:Charges() == DemonSpikes:MaxCharges() or (not Metamorphosis.active and (not CalcifiedSpikes.known or CalcifiedSpikes:Remains() < 8))) then
		return UseExtra(DemonSpikes)
	end
	if InfernalStrike:Usable() and InfernalStrike:ChargesFractional() >= 1.5 then
		return UseExtra(InfernalStrike)
	end
	if Metamorphosis:Usable() and not Metamorphosis.active and (not Demonic.known or not FelDevastation:Ready()) and (Player.health.pct <= 60 or (DemonSpikes:Down() and not DemonSpikes:Ready())) then
		return UseExtra(Metamorphosis)
	end
end

APL[SPEC.VENGEANCE].demonsurge = function(self)
--[[

]]
	if FelDesolation:Usable() and Metamorphosis.remains < (Player.gcd * 5) then
		UseCooldown(FelDesolation)
	end
	if SpiritBurst:Usable() and Demonsurge.up[SpiritBurst] and (
		SoulFragments.total >= 4 or
		Metamorphosis.remains < (Player.gcd * 2)
	) then
		return SpiritBurst
	end
	if SoulSunder:Usable() and Demonsurge.up[SoulSunder] and (
		Metamorphosis.remains < (Player.gcd * 2) or
		(Metamorphosis.remains < (Player.gcd * 5) and (not SpiritBurst.known or not Demonsurge.up[SpiritBurst] or SoulFragments.total <= 0))
	) then
		return SoulSunder
	end
	if Fracture:Usable() and Metamorphosis.remains < (Player.gcd * 5) and (
		(SpiritBurst.known and Demonsurge.up[SpiritBurst]) or
		(SoulSunder.known and Demonsurge.up[SoulSunder] and Player.fury.current < SoulSunder:Cost())
	) then
		return Fracture
	end
	if Shear:Usable() and Metamorphosis.remains < (Player.gcd * 5) and (
		(SpiritBurst.known and Demonsurge.up[SpiritBurst]) or
		(SoulSunder.known and Demonsurge.up[SoulSunder] and Player.fury.current < SoulSunder:Cost())
	) then
		return Shear
	end
end

APL[SPEC.VENGEANCE].big_aoe = function(self)
--[[
actions.big_aoe=fel_devastation,if=talent.collective_anguish.enabled|talent.stoke_the_flames.enabled
actions.big_aoe+=/the_hunt
actions.big_aoe+=/sigil_of_spite
actions.big_aoe+=/fel_devastation
actions.big_aoe+=/soul_carver
actions.big_aoe+=/spirit_bomb,if=soul_fragments>=4
actions.big_aoe+=/fracture
actions.big_aoe+=/shear
actions.big_aoe+=/soul_cleave,if=soul_fragments<1
actions.big_aoe+=/call_action_list,name=filler
]]
	if FelDesolation:Usable() and Metamorphosis.remains < 4 then
		UseCooldown(FelDesolation)
	end
	if FelDevastation:Usable() and Metamorphosis.remains < 8 and (CollectiveAnguish.known or (StokeTheFlames.known and BurningBlood.known)) then
		UseCooldown(FelDevastation)
	end
	if TheHunt:Usable() then
		UseCooldown(TheHunt)
	end
	if SigilOfSpite:Usable() and not SigilOfSpite:Placed() and SoulFragments.total <= 3 then
		UseCooldown(SigilOfSpite)
	end
	if FelDevastation:Usable() and Metamorphosis.remains < 8 then
		UseCooldown(FelDevastation)
	end
	if SoulCarver:Usable() then
		UseCooldown(SoulCarver)
	end
	if FelDesolation:Usable() then
		UseCooldown(FelDesolation)
	end
	if SoulFragments.total >= 4 then
		if SpiritBurst:Usable() then
			return SpiritBurst
		end
		if SpiritBomb:Usable() then
			return SpiritBomb
		end
	end
	if Fracture:Usable() then
		return Fracture
	end
	if Shear:Usable() then
		return Shear
	end
	if SoulSunder:Usable() and SoulFragments.total < 1 and self.soul_cleave_condition then
		return SoulSunder
	end
	if SoulCleave:Usable() and SoulFragments.total < 1 and self.soul_cleave_condition then
		return SoulCleave
	end
	return self:filler()
end

APL[SPEC.VENGEANCE].fiery_demise = function(self)
--[[
actions.fiery_demise=immolation_aura
actions.fiery_demise+=/sigil_of_flame
actions.fiery_demise+=/felblade,if=(cooldown.fel_devastation.remains<=(execute_time+gcd.remains))&fury<50
actions.fiery_demise+=/fel_devastation
actions.fiery_demise+=/soul_carver
actions.fiery_demise+=/spirit_bomb,if=spell_targets=1&soul_fragments>=5
actions.fiery_demise+=/spirit_bomb,if=spell_targets>1&spell_targets<=5&soul_fragments>=4
actions.fiery_demise+=/spirit_bomb,if=spell_targets>=6&soul_fragments>=3
actions.fiery_demise+=/the_hunt
actions.fiery_demise+=/sigil_of_spite
actions.fiery_demise+=/soul_cleave,if=fury.deficit<=30&!variable.dont_spend_fury
]]
	if Fallout.known and SpiritBurst:Usable() and SoulFragments.total >= 3 and Player.enemies >= 3 and ImmolationAura:Ready(Player.gcd) then
		return SpiritBurst
	end
	if Fallout.known and SpiritBomb:Usable() and SoulFragments.total >= 3 and Player.enemies >= 3 and ImmolationAura:Ready(Player.gcd) then
		return SpiritBomb
	end
	if ConsumingFire:Usable() then
		return ConsumingFire
	end
	if ImmolationAura:Usable() then
		return ImmolationAura
	end
	if SigilOfDoom:Usable() and not SigilOfDoom:Placed() and (
		SigilOfDoom:ChargesFractional() >= 1.8 or
		SigilOfDoom.dot:Refreshable() or
		(AscendingFlame.known and SigilOfDoom:ChargesFractional() >= 1.4 and Player.enemies >= 3)
	) then
		return SigilOfDoom
	end
	if SigilOfFlame:Usable() and not SigilOfFlame:Placed() and (
		SigilOfFlame:ChargesFractional() >= 1.8 or
		SigilOfFlame.dot:Refreshable() or
		(AscendingFlame.known and SigilOfFlame:ChargesFractional() >= 1.4 and Player.enemies >= 3)
	) then
		return SigilOfFlame
	end
	if Felblade:Usable() and Player.fury.current < 50 and FelDevastation:Ready(Player.gcd * 2) then
		return Felblade
	end
	if FelDesolation:Usable() then
		UseCooldown(FelDesolation)
	end
	if FelDevastation:Usable() and Metamorphosis.remains < 8 then
		UseCooldown(FelDevastation)
	end
	if SoulCarver:Usable() then
		UseCooldown(SoulCarver)
	end
	if SpiritBurst:Usable() and (
		(Player.enemies <= 1 and SoulFragments.total >= 5) or
		((between(Player.enemies, 2, 5) or (FieryDemise.known and FieryBrand:Ticking() > 0)) and SoulFragments.total >= 4) or
		(Player.enemies >= 6 and SoulFragments.total >= 3)
	) then
		return SpiritBurst
	end
	if SpiritBomb:Usable() and (
		(Player.enemies <= 1 and SoulFragments.total >= 5) or
		((between(Player.enemies, 2, 5) or (FieryDemise.known and FieryBrand:Ticking() > 0)) and SoulFragments.total >= 4) or
		(Player.enemies >= 6 and SoulFragments.total >= 3)
	) then
		return SpiritBomb
	end
	if TheHunt:Usable() then
		UseCooldown(TheHunt)
	end
	if SigilOfSpite:Usable() and not SigilOfSpite:Placed() and SoulFragments.total <= 3 then
		UseCooldown(SigilOfSpite)
	end
	if SoulSunder:Usable() and Player.fury.deficit <= 30 and not self.dont_spend_fury and self.soul_cleave_condition then
		return SoulSunder
	end
	if SoulCleave:Usable() and Player.fury.deficit <= 30 and not self.dont_spend_fury and self.soul_cleave_condition then
		return SoulCleave
	end
end

APL[SPEC.VENGEANCE].filler = function(self)
--[[
actions.filler=sigil_of_chains,if=talent.cycle_of_binding.enabled&talent.sigil_of_chains.enabled
actions.filler+=/sigil_of_misery,if=talent.cycle_of_binding.enabled&talent.sigil_of_misery.enabled
actions.filler+=/sigil_of_silence,if=talent.cycle_of_binding.enabled&talent.sigil_of_silence.enabled
actions.filler+=/throw_glaive
]]
	if CycleOfBinding.known then
		if SigilOfChains:Usable() and not SigilOfChains:Placed() and SigilOfChains.dot:Down() then
			UseCooldown(SigilOfChains)
		end
		if SigilOfMisery:Usable() and not SigilOfMisery:Placed() and SigilOfMisery.dot:Down()  then
			UseCooldown(SigilOfMisery)
		end
		if SigilOfSilence:Usable() and not SigilOfSilence:Placed() and SigilOfSilence.dot:Down()  then
			UseCooldown(SigilOfSilence)
		end
	end
	if ChaosFragments.known and ChaosNova:Usable() and Player.enemies >= 3 and self.soul_fragments <= 1 and Target.stunnable then
		UseCooldown(ChaosNova)
	end
	if ThrowGlaiveV:Usable() then
		return ThrowGlaiveV
	end
end

APL[SPEC.VENGEANCE].maintenance = function(self)
--[[
actions.maintenance=fiery_brand,if=(active_dot.fiery_brand=0&(cooldown.sigil_of_flame.remains<(execute_time+gcd.remains)|cooldown.soul_carver.remains<(execute_time+gcd.remains)|cooldown.fel_devastation.remains<(execute_time+gcd.remains)))|(talent.down_in_flames&full_recharge_time<(execute_time+gcd.remains))
actions.maintenance+=/sigil_of_flame
actions.maintenance+=/spirit_bomb,if=soul_fragments>=5
actions.maintenance+=/immolation_aura
actions.maintenance+=/bulk_extraction,if=prev_gcd.1.spirit_bomb
actions.maintenance+=/felblade,if=fury.deficit>=40
actions.maintenance+=/fracture,if=(cooldown.fel_devastation.remains<=(execute_time+gcd.remains))&fury<50
actions.maintenance+=/shear,if=(cooldown.fel_devastation.remains<=(execute_time+gcd.remains))&fury<50
actions.maintenance+=/spirit_bomb,if=fury.deficit<30&((spell_targets>=2&soul_fragments>=5)|(spell_targets>=6&soul_fragments>=4))&!variable.dont_spend_fury
actions.maintenance+=/soul_cleave,if=fury.deficit<30&soul_fragments<=3&!variable.dont_spend_fury
]]
	if FieryBrand:Usable() and (Target.boss or Target.timeToDie > 10) and (
		(FieryBrand:Ticking() == 0 and (SigilOfFlame:Ready(Player.gcd * 2) or SoulCarver:Ready(Player.gcd * 2) or FelDevastation:Ready(Player.gcd))) or
		(DownInFlames.known and FieryBrand:FullRechargeTime() < (Player.gcd * 2))
	) then
		UseCooldown(FieryBrand)
	end
	if SigilOfDoom:Usable() and not SigilOfDoom:Placed() and (
		SigilOfDoom:ChargesFractional() >= 1.8 or
		SigilOfDoom.dot:Remains() < 1 or
		(AscendingFlame.known and SigilOfDoom:ChargesFractional() >= 1.4 and Player.enemies >= 3 and (not FieryDemise.known or not FieryBrand:Ready(4)))
	) then
		return SigilOfDoom
	end
	if SigilOfFlame:Usable() and not SigilOfFlame:Placed() and (
		SigilOfFlame:ChargesFractional() >= 1.8 or
		SigilOfFlame.dot:Remains() < 1 or
		(AscendingFlame.known and SigilOfFlame:ChargesFractional() >= 1.4 and Player.enemies >= 3 and (not FieryDemise.known or not FieryBrand:Ready(4)))
	) then
		return SigilOfFlame
	end
	if SpiritBurst:Usable() and (
		SoulFragments.total >= 5 or
		(Fallout.known and SoulFragments.total >= 3 and Player.enemies >= 3 and ImmolationAura:Ready(Player.gcd))
	) then
		return SpiritBurst
	end
	if SpiritBomb:Usable() and (
		SoulFragments.total >= 5 or
		(Fallout.known and SoulFragments.total >= 3 and Player.enemies >= 3 and ImmolationAura:Ready(Player.gcd))
	) then
		return SpiritBomb
	end
	if ConsumingFire:Usable() and (not Fallout.known or SpiritBomb:Previous() or SpiritBurst:Previous() or Player.enemies <= 3 or SoulFragments.total <= 3) then
		return ConsumingFire
	end
	if ImmolationAura:Usable() and (not Fallout.known or SpiritBomb:Previous() or SpiritBurst:Previous() or Player.enemies <= 3 or SoulFragments.total <= 3) then
		return ImmolationAura
	end
	if BulkExtraction:Usable() and (SpiritBomb:Previous() or SpiritBurst:Previous()) then
		UseCooldown(BulkExtraction)
	end
	if Felblade:Usable() and Player.fury.deficit >= 40 then
		return Felblade
	end
	if Fracture:Usable() and Player.fury.current < 50 and FelDevastation:Ready(Player.gcd * 2) then
		return Fracture
	end
	if Shear:Usable() and Player.fury.current < 50 and FelDevastation:Ready(Player.gcd * 2) then
		return Shear
	end
	if SpiritBurst:Usable() and Player.fury.deficit < 30 and not self.dont_spend_fury and (
		(Player.enemies >= 2 and SoulFragments.total >= 5) or
		(Player.enemies >= 6 and SoulFragments.total >= 4)
	) then
		return SpiritBurst
	end
	if SpiritBomb:Usable() and Player.fury.deficit < 30 and not self.dont_spend_fury and (
		(Player.enemies >= 2 and SoulFragments.total >= 5) or
		(Player.enemies >= 6 and SoulFragments.total >= 4)
	) then
		return SpiritBomb
	end
	if SoulSunder:Usable() and Player.fury.deficit < 30 and SoulFragments.total <= 3 and not self.dont_spend_fury and self.soul_cleave_condition then
		return SoulSunder
	end
	if SoulCleave:Usable() and Player.fury.deficit < 30 and SoulFragments.total <= 3 and not self.dont_spend_fury and self.soul_cleave_condition then
		return SoulCleave
	end
end

APL[SPEC.VENGEANCE].single_target = function(self)
--[[
actions.single_target=the_hunt
actions.single_target+=/soul_carver
actions.single_target+=/fel_devastation,if=talent.collective_anguish.enabled|(talent.stoke_the_flames.enabled&talent.burning_blood.enabled)
actions.single_target+=/sigil_of_spite
actions.single_target+=/fel_devastation
actions.single_target+=/soul_cleave,if=talent.focused_cleave&!variable.dont_spend_fury
actions.single_target+=/fracture
actions.single_target+=/shear
actions.single_target+=/soul_cleave,if=!variable.dont_spend_fury
actions.single_target+=/call_action_list,name=filler
]]
	if FelDesolation:Usable() and Metamorphosis.remains < 4 then
		UseCooldown(FelDesolation)
	end
	if TheHunt:Usable() then
		UseCooldown(TheHunt)
	end
	if SoulCarver:Usable() then
		UseCooldown(SoulCarver)
	end
	if FelDevastation:Usable() and Metamorphosis.remains < 8 and (CollectiveAnguish.known or (StokeTheFlames.known and BurningBlood.known)) then
		UseCooldown(FelDevastation)
	end
	if SigilOfSpite:Usable() and not SigilOfSpite:Placed() and SoulFragments.total <= 3 then
		UseCooldown(SigilOfSpite)
	end
	if FelDesolation:Usable() then
		UseCooldown(FelDesolation)
	end
	if FelDevastation:Usable() and Metamorphosis.remains < 8 then
		UseCooldown(FelDevastation)
	end
	if FocusedCleave.known and not self.dont_spend_fury then
		if SoulSunder:Usable() then
			return SoulSunder
		end
		if SoulCleave:Usable() then
			return SoulCleave
		end
	end
	if Fracture:Usable() then
		return Fracture
	end
	if Shear:Usable() then
		return Shear
	end
	if not self.dont_spend_fury then
		if SoulSunder:Usable() then
			return SoulSunder
		end
		if SoulCleave:Usable() then
			return SoulCleave
		end
	end
	return self:filler()
end

APL[SPEC.VENGEANCE].small_aoe = function(self)
--[[
actions.small_aoe=the_hunt
actions.small_aoe+=/fel_devastation,if=talent.collective_anguish.enabled|(talent.stoke_the_flames.enabled&talent.burning_blood.enabled)
actions.small_aoe+=/sigil_of_spite
actions.small_aoe+=/fel_devastation
actions.small_aoe+=/soul_carver
actions.small_aoe+=/spirit_bomb,if=soul_fragments>=5
actions.small_aoe+=/soul_cleave,if=talent.focused_cleave&soul_fragments<=2
actions.small_aoe+=/fracture
actions.small_aoe+=/shear
actions.small_aoe+=/soul_cleave,if=soul_fragments<=2
actions.small_aoe+=/call_action_list,name=filler
]]
	if TheHunt:Usable() then
		UseCooldown(TheHunt)
	end
	if FelDesolation:Usable() and Metamorphosis.remains < 8 then
		UseCooldown(FelDesolation)
	end
	if FelDevastation:Usable() and Metamorphosis.remains < 8 and (CollectiveAnguish.known or (StokeTheFlames.known and BurningBlood.known)) then
		UseCooldown(FelDevastation)
	end
	if SigilOfSpite:Usable() and not SigilOfSpite:Placed() and SoulFragments.total <= 3 then
		UseCooldown(SigilOfSpite)
	end
	if FelDevastation:Usable() and Metamorphosis.remains < 8 then
		UseCooldown(FelDevastation)
	end
	if SoulCarver:Usable() then
		UseCooldown(SoulCarver)
	end
	if SpiritBurst:Usable() and (
		SoulFragments.total >= 5 or
		((FieryDemise.known and FieryBrand:Ticking() > 0) and SoulFragments.total >= 4)
	) then
		return SpiritBurst
	end
	if SpiritBomb:Usable() and (
		SoulFragments.total >= 5 or
		((FieryDemise.known and FieryBrand:Ticking() > 0) and SoulFragments.total >= 4)
	) then
		return SpiritBomb
	end
	if FocusedCleave.known and self.soul_cleave_condition and SoulFragments.total <= 2 then
		if SoulSunder:Usable() then
			return SoulSunder
		end
		if SoulCleave:Usable() then
			return SoulCleave
		end
	end
	if Fracture:Usable() then
		return Fracture
	end
	if Shear:Usable() then
		return Shear
	end
	if SoulFragments.total <= 2 then
		if SoulSunder:Usable() then
			return SoulSunder
		end
		if SoulCleave:Usable() then
			return SoulCleave
		end
	end
	return self:filler()
end

APL[SPEC.VENGEANCE].trinkets = function(self)
--[[
actions.trinkets=use_item,use_off_gcd=1,slot=trinket1,if=!variable.trinket_1_buffs
actions.trinkets+=/use_item,use_off_gcd=1,slot=trinket2,if=!variable.trinket_2_buffs
actions.trinkets+=/use_item,use_off_gcd=1,slot=main_hand,if=(variable.trinket_1_buffs|trinket.1.cooldown.remains)&(variable.trinket_2_buffs|trinket.2.cooldown.remains)
actions.trinkets+=/use_item,use_off_gcd=1,slot=trinket1,if=variable.trinket_1_buffs&(buff.metamorphosis.up|cooldown.metamorphosis.remains>20)&(variable.trinket_2_exclude|trinket.2.cooldown.remains|!trinket.2.has_cooldown|variable.trinket_2_buffs)
actions.trinkets+=/use_item,use_off_gcd=1,slot=trinket2,if=variable.trinket_2_buffs&(buff.metamorphosis.up|cooldown.metamorphosis.remains>20)&(variable.trinket_1_exclude|trinket.1.cooldown.remains|!trinket.1.has_cooldown|variable.trinket_1_buffs)
]]
	if Opt.trinket and (Metamorphosis.active or not Metamorphosis:Ready(20)) then
		if Trinket1:Usable() then
			return UseCooldown(Trinket1)
		elseif Trinket2:Usable() then
			return UseCooldown(Trinket2)
		end
	end
end

APL.Interrupt = function(self)
	if Disrupt:Usable() then
		return Disrupt
	end
	if SigilOfSilence:Usable() then
		return SigilOfSilence
	end
	if ChaosNova:Usable() and Target.stunnable then
		return ChaosNova
	end
	if FelEruption:Usable() and Target.stunnable then
		return FelEruption
	end
end

-- End Action Priority Lists

-- Start UI Functions

function UI.DenyOverlayGlow(actionButton)
	if Opt.glow.blizzard then
		return
	end
	local alert = actionButton.SpellActivationAlert
	if not alert then
		return
	end
	if alert.ProcStartAnim:IsPlaying() then
		alert.ProcStartAnim:Stop()
	end
	alert:Hide()
end
hooksecurefunc('ActionButton_ShowOverlayGlow', UI.DenyOverlayGlow) -- Disable Blizzard's built-in action button glowing

function UI:UpdateGlowColorAndScale()
	local w, h, glow
	local r, g, b = Opt.glow.color.r, Opt.glow.color.g, Opt.glow.color.b
	for i, button in next, self.buttons do
		glow = button['glow' .. ADDON]
		w, h = glow.button:GetSize()
		glow:SetSize(w * 1.4, h * 1.4)
		glow:SetPoint('TOPLEFT', glow.button, 'TOPLEFT', -w * 0.2 * Opt.scale.glow, h * 0.2 * Opt.scale.glow)
		glow:SetPoint('BOTTOMRIGHT', glow.button, 'BOTTOMRIGHT', w * 0.2 * Opt.scale.glow, -h * 0.2 * Opt.scale.glow)
		glow.ProcStartFlipbook:SetVertexColor(r, g, b)
		glow.ProcLoopFlipbook:SetVertexColor(r, g, b)
	end
end

function UI:DisableOverlayGlows()
	if Opt.glow.blizzard or not LibStub then
		return
	end
	local lib = LibStub:GetLibrary('LibButtonGlow-1.0', true)
	if lib then
		lib.ShowOverlayGlow = function(...)
			return lib.HideOverlayGlow(...)
		end
	end
end

function UI:ScanActionButtons()
	wipe(self.buttons)
	if Bartender4 then
		for i = 1, 120 do
			self.buttons[#self.buttons + 1] = _G['BT4Button' .. i]
		end
		for i = 1, 10 do
			self.buttons[#self.buttons + 1] = _G['BT4PetButton' .. i]
		end
		return
	end
	if ElvUI then
		for b = 1, 6 do
			for i = 1, 12 do
				self.buttons[#self.buttons + 1] = _G['ElvUI_Bar' .. b .. 'Button' .. i]
			end
		end
		return
	end
	if LUI then
		for b = 1, 6 do
			for i = 1, 12 do
				self.buttons[#self.buttons + 1] = _G['LUIBarBottom' .. b .. 'Button' .. i]
				self.buttons[#self.buttons + 1] = _G['LUIBarLeft' .. b .. 'Button' .. i]
				self.buttons[#self.buttons + 1] = _G['LUIBarRight' .. b .. 'Button' .. i]
			end
		end
		return
	end
	if Dominos then
		for i = 1, 60 do
			self.buttons[#self.buttons + 1] = _G['DominosActionButton' .. i]
		end
		-- fallthrough because Dominos re-uses Blizzard action buttons
	end
	for i = 1, 12 do
		self.buttons[#self.buttons + 1] = _G['ActionButton' .. i]
		self.buttons[#self.buttons + 1] = _G['MultiBarLeftButton' .. i]
		self.buttons[#self.buttons + 1] = _G['MultiBarRightButton' .. i]
		self.buttons[#self.buttons + 1] = _G['MultiBarBottomLeftButton' .. i]
		self.buttons[#self.buttons + 1] = _G['MultiBarBottomRightButton' .. i]
		self.buttons[#self.buttons + 1] = _G['MultiBar5Button' .. i]
		self.buttons[#self.buttons + 1] = _G['MultiBar6Button' .. i]
		self.buttons[#self.buttons + 1] = _G['MultiBar7Button' .. i]
	end
	for i = 1, 10 do
		self.buttons[#self.buttons + 1] = _G['PetActionButton' .. i]
	end
end

function UI:CreateOverlayGlows()
	local glow
	for i, button in next, self.buttons do
		glow = button['glow' .. ADDON] or CreateFrame('Frame', nil, button, 'ActionBarButtonSpellActivationAlert')
		glow:Hide()
		glow.ProcStartAnim:Play() -- will bug out if ProcLoop plays first
		glow.button = button
		button['glow' .. ADDON] = glow
	end
	self:UpdateGlowColorAndScale()
end

function UI:UpdateGlows()
	local glow, action
	for _, slot in next, self.action_slots do
		action = slot.action
		for _, button in next, slot.buttons do
			glow = button['glow' .. ADDON]
			if action and button:IsVisible() and (
				(Opt.glow.main and action == Player.main) or
				(Opt.glow.cooldown and action == Player.cd) or
				(Opt.glow.interrupt and action == Player.interrupt) or
				(Opt.glow.extra and action == Player.extra)
			) then
				if not glow:IsVisible() then
					glow:Show()
					if Opt.glow.animation then
						glow.ProcStartAnim:Play()
					else
						glow.ProcLoop:Play()
					end
				end
			elseif glow:IsVisible() then
				if glow.ProcStartAnim:IsPlaying() then
					glow.ProcStartAnim:Stop()
				end
				if glow.ProcLoop:IsPlaying() then
					glow.ProcLoop:Stop()
				end
				glow:Hide()
			end
		end
	end
end

UI.KeybindPatterns = {
	['ALT%-'] = 'a-',
	['CTRL%-'] = 'c-',
	['SHIFT%-'] = 's-',
	['META%-'] = 'm-',
	['NUMPAD'] = 'NP',
	['PLUS'] = '%+',
	['MINUS'] = '%-',
	['MULTIPLY'] = '%*',
	['DIVIDE'] = '%/',
	['BACKSPACE'] = 'BS',
	['BUTTON'] = 'MB',
	['CLEAR'] = 'Clr',
	['DELETE'] = 'Del',
	['END'] = 'End',
	['HOME'] = 'Home',
	['INSERT'] = 'Ins',
	['MOUSEWHEELDOWN'] = 'MwD',
	['MOUSEWHEELUP'] = 'MwU',
	['PAGEDOWN'] = 'PgDn',
	['PAGEUP'] = 'PgUp',
	['CAPSLOCK'] = 'Caps',
	['NUMLOCK'] = 'NumL',
	['SCROLLLOCK'] = 'ScrL',
	['SPACEBAR'] = 'Space',
	['SPACE'] = 'Space',
	['TAB'] = 'Tab',
	['DOWNARROW'] = 'Down',
	['LEFTARROW'] = 'Left',
	['RIGHTARROW'] = 'Right',
	['UPARROW'] = 'Up',
}

function UI:GetButtonKeybind(button)
	local bind = button.bindingAction or (button.config and button.config.keyBoundTarget)
	if bind then
		local key = GetBindingKey(bind)
		if key then
			key = key:gsub(' ', ''):upper()
			for pattern, short in next, self.KeybindPatterns do
				key = key:gsub(pattern, short)
			end
			return key
		end
	end
end

function UI:GetActionFromID(actionId)
	local actionType, id, subType = GetActionInfo(actionId)
	if id and type(id) == 'number' and id > 0 then
		if (actionType == 'item' or (actionType == 'macro' and subType == 'item')) then
			return InventoryItems.byItemId[id]
		elseif (actionType == 'spell' or (actionType == 'macro' and subType == 'spell')) then
			return Abilities.bySpellId[id]
		end
	end
end

function UI:UpdateActionSlot(actionId)
	local slot = self.action_slots[actionId]
	if not slot then
		return
	end
	local action = self:GetActionFromID(actionId)
	if action ~= slot.action then
		if slot.action then
			slot.action.keybinds[actionId] = nil
		end
		slot.action = action
	end
	if not action then
		return
	end
	for _, button in next, slot.buttons do
		action.keybinds[actionId] = self:GetButtonKeybind(button)
		if action.keybinds[actionId] then
			return
		end
	end
	action.keybinds[actionId] = nil
end

function UI:UpdateBindings()
	for _, item in next, InventoryItems.all do
		wipe(item.keybinds)
	end
	for _, ability in next, Abilities.all do
		wipe(ability.keybinds)
	end
	for actionId in next, self.action_slots do
		self:UpdateActionSlot(actionId)
	end
end

function UI:ScanActionSlots()
	wipe(self.action_slots)
	local actionId, buttons
	for _, button in next, self.buttons do
		actionId = (
			(button._state_type == 'action' and button._state_action) or
			(button.CalculateAction and button:CalculateAction()) or
			(button:GetAttribute('action'))
		) or 0
		if actionId > 0 then
			if not self.action_slots[actionId] then
				self.action_slots[actionId] = {
					buttons = {},
				}
			end
			buttons = self.action_slots[actionId].buttons
			buttons[#buttons + 1] = button
		end
	end
end

function UI:UpdateDraggable()
	local draggable = not (Opt.locked or Opt.snap or Opt.aoe)
	lasikPanel:SetMovable(not Opt.snap)
	lasikPreviousPanel:SetMovable(not Opt.snap)
	lasikCooldownPanel:SetMovable(not Opt.snap)
	lasikInterruptPanel:SetMovable(not Opt.snap)
	lasikExtraPanel:SetMovable(not Opt.snap)
	if not Opt.snap then
		lasikPanel:SetUserPlaced(true)
		lasikPreviousPanel:SetUserPlaced(true)
		lasikCooldownPanel:SetUserPlaced(true)
		lasikInterruptPanel:SetUserPlaced(true)
		lasikExtraPanel:SetUserPlaced(true)
	end
	lasikPanel:EnableMouse(draggable or Opt.aoe)
	lasikPanel.button:SetShown(Opt.aoe)
	lasikPreviousPanel:EnableMouse(draggable)
	lasikCooldownPanel:EnableMouse(draggable)
	lasikInterruptPanel:EnableMouse(draggable)
	lasikExtraPanel:EnableMouse(draggable)
end

function UI:UpdateAlpha()
	lasikPanel:SetAlpha(Opt.alpha)
	lasikPreviousPanel:SetAlpha(Opt.alpha)
	lasikCooldownPanel:SetAlpha(Opt.alpha)
	lasikInterruptPanel:SetAlpha(Opt.alpha)
	lasikExtraPanel:SetAlpha(Opt.alpha)
end

function UI:UpdateScale()
	lasikPanel:SetSize(64 * Opt.scale.main, 64 * Opt.scale.main)
	lasikPanel.text:SetScale(Opt.scale.main)
	lasikPreviousPanel:SetSize(64 * Opt.scale.previous, 64 * Opt.scale.previous)
	lasikCooldownPanel:SetSize(64 * Opt.scale.cooldown, 64 * Opt.scale.cooldown)
	lasikCooldownPanel.text:SetScale(Opt.scale.cooldown)
	lasikInterruptPanel:SetSize(64 * Opt.scale.interrupt, 64 * Opt.scale.interrupt)
	lasikExtraPanel:SetSize(64 * Opt.scale.extra, 64 * Opt.scale.extra)
end

function UI:SnapAllPanels()
	lasikPreviousPanel:ClearAllPoints()
	lasikPreviousPanel:SetPoint('TOPRIGHT', lasikPanel, 'BOTTOMLEFT', -3, 40)
	lasikCooldownPanel:ClearAllPoints()
	lasikCooldownPanel:SetPoint('TOPLEFT', lasikPanel, 'BOTTOMRIGHT', 3, 40)
	lasikInterruptPanel:ClearAllPoints()
	lasikInterruptPanel:SetPoint('BOTTOMLEFT', lasikPanel, 'TOPRIGHT', 3, -21)
	lasikExtraPanel:ClearAllPoints()
	lasikExtraPanel:SetPoint('BOTTOMRIGHT', lasikPanel, 'TOPLEFT', -3, -21)
end

UI.anchor_points = {
	blizzard = { -- Blizzard Personal Resource Display (Default)
		[SPEC.HAVOC] = {
			['above'] = { 'BOTTOM', 'TOP', 0, 36 },
			['below'] = { 'TOP', 'BOTTOM', 0, -9 },
		},
		[SPEC.VENGEANCE] = {
			['above'] = { 'BOTTOM', 'TOP', 0, 36 },
			['below'] = { 'TOP', 'BOTTOM', 0, -9 },
		},
	},
	kui = { -- Kui Nameplates
		[SPEC.HAVOC] = {
			['above'] = { 'BOTTOM', 'TOP', 0, 24 },
			['below'] = { 'TOP', 'BOTTOM', 0, 5 },
		},
		[SPEC.VENGEANCE] = {
			['above'] = { 'BOTTOM', 'TOP', 0, 24 },
			['below'] = { 'TOP', 'BOTTOM', 0, 5 },
		},
	},
}

function UI.OnResourceFrameHide()
	if Opt.snap then
		lasikPanel:ClearAllPoints()
	end
end

function UI.OnResourceFrameShow()
	if Opt.snap and UI.anchor.points then
		local p = UI.anchor.points[Player.spec][Opt.snap]
		lasikPanel:ClearAllPoints()
		lasikPanel:SetPoint(p[1], UI.anchor.frame, p[2], p[3], p[4])
		UI:SnapAllPanels()
	end
end

function UI:HookResourceFrame()
	if KuiNameplatesCoreSaved and KuiNameplatesCoreCharacterSaved and
		not KuiNameplatesCoreSaved.profiles[KuiNameplatesCoreCharacterSaved.profile].use_blizzard_personal
	then
		self.anchor.points = self.anchor_points.kui
		self.anchor.frame = KuiNameplatesPlayerAnchor
	else
		self.anchor.points = self.anchor_points.blizzard
		self.anchor.frame = NamePlateDriverFrame:GetClassNameplateBar()
	end
	if self.anchor.frame then
		self.anchor.frame:HookScript('OnHide', self.OnResourceFrameHide)
		self.anchor.frame:HookScript('OnShow', self.OnResourceFrameShow)
	end
end

function UI:ShouldHide()
	return (Player.spec == SPEC.NONE or
		   (Player.spec == SPEC.HAVOC and Opt.hide.havoc) or
		   (Player.spec == SPEC.VENGEANCE and Opt.hide.vengeance))
end

function UI:Disappear()
	lasikPanel:Hide()
	lasikPanel.icon:Hide()
	lasikPanel.border:Hide()
	lasikCooldownPanel:Hide()
	lasikInterruptPanel:Hide()
	lasikExtraPanel:Hide()
	Player.main = nil
	Player.cd = nil
	Player.interrupt = nil
	Player.extra = nil
	self:UpdateGlows()
end

function UI:Reset()
	lasikPanel:ClearAllPoints()
	lasikPanel:SetPoint('CENTER', 0, -169)
	self:SnapAllPanels()
end

function UI:UpdateDisplay()
	Timer.display = 0
	local border, dim, dim_cd, text_cd, text_center, text_tl, text_tr, text_bl, text_cd_center, text_cd_tr
	local channel = Player.channel

	if Opt.dimmer then
		dim = not ((not Player.main) or
		           (Player.main.spellId and IsSpellUsable(Player.main.spellId)) or
		           (Player.main.itemId and IsItemUsable(Player.main.itemId)))
		dim_cd = not ((not Player.cd) or
		           (Player.cd.spellId and IsSpellUsable(Player.cd.spellId)) or
		           (Player.cd.itemId and IsItemUsable(Player.cd.itemId)))
	end
	if Player.main then
		if Player.main.requires_react then
			local react = Player.main:React()
			if react > 0 then
				text_center = format('%.1f', react)
			end
		end
		if Player.main_freecast then
			border = 'freecast'
		end
		if Opt.keybinds then
			for _, bind in next, Player.main.keybinds do
				text_tr = bind
				break
			end
		end
	end
	if Player.cd then
		if Player.cd.requires_react then
			local react = Player.cd:React()
			if react > 0 then
				text_cd_center = format('%.1f', react)
			end
		end
		if Opt.keybinds then
			for _, bind in next, Player.cd.keybinds do
				text_cd_tr = bind
				break
			end
		end
	end
	if channel.ability and not channel.ability.ignore_channel and channel.tick_count > 0 then
		dim = Opt.dimmer
		if channel.tick_count > 1 then
			local ctime = GetTime()
			channel.ticks = ((ctime - channel.start) / channel.tick_interval) - channel.ticks_extra
			channel.ticks_remain = (channel.ends - ctime) / channel.tick_interval
			text_center = format('TICKS\n%.1f', max(0, channel.ticks))
			if channel.ability == Player.main then
				if channel.ticks_remain < 1 or channel.early_chainable then
					dim = false
					text_center = '|cFF00FF00CHAIN'
				end
			elseif channel.interruptible then
				dim = false
			end
		end
	end
	if Metamorphosis.active then
		text_bl = format('%.1fs', Metamorphosis.remains)
	end
	if SoulFragments.known and SoulFragments.current + SoulFragments.incoming > 0 then
		text_tl = SoulFragments.current
		if SoulFragments.incoming > 0 then
			text_tl = text_tl .. '+' .. SoulFragments.incoming
		end
	end
	if border ~= lasikPanel.border.overlay then
		lasikPanel.border.overlay = border
		lasikPanel.border:SetTexture(ADDON_PATH .. (border or 'border') .. '.blp')
	end

	lasikPanel.dimmer:SetShown(dim)
	lasikPanel.text.center:SetText(text_center)
	lasikPanel.text.tl:SetText(text_tl)
	lasikPanel.text.tr:SetText(text_tr)
	lasikPanel.text.bl:SetText(text_bl)
	lasikCooldownPanel.dimmer:SetShown(dim_cd)
	lasikCooldownPanel.text.center:SetText(text_cd_center)
	lasikCooldownPanel.text.tr:SetText(text_cd_tr)
end

function UI:UpdateCombat()
	Timer.combat = 0

	Player:Update()

	if Player.main then
		lasikPanel.icon:SetTexture(Player.main.icon)
		Player.main_freecast = Player.main:Free()
	end
	if Player.cd then
		lasikCooldownPanel.icon:SetTexture(Player.cd.icon)
		if Player.cd.spellId then
			local cooldown = GetSpellCooldown(Player.cd.spellId)
			lasikCooldownPanel.swipe:SetCooldown(cooldown.startTime, cooldown.duration)
		end
	end
	if Player.extra then
		lasikExtraPanel.icon:SetTexture(Player.extra.icon)
	end
	if Opt.interrupt then
		local _, _, _, start, ends, _, _, notInterruptible = UnitCastingInfo('target')
		if not start then
			_, _, _, start, ends, _, notInterruptible = UnitChannelInfo('target')
		end
		if start and not notInterruptible then
			Player.interrupt = APL.Interrupt()
			lasikInterruptPanel.swipe:SetCooldown(start / 1000, (ends - start) / 1000)
		end
		if Player.interrupt then
			lasikInterruptPanel.icon:SetTexture(Player.interrupt.icon)
		end
		lasikInterruptPanel.icon:SetShown(Player.interrupt)
		lasikInterruptPanel.border:SetShown(Player.interrupt)
		lasikInterruptPanel:SetShown(start and not notInterruptible)
	end
	if Opt.previous and lasikPreviousPanel.ability then
		if (Player.time - lasikPreviousPanel.ability.last_used) > 10 then
			lasikPreviousPanel.ability = nil
			lasikPreviousPanel:Hide()
		end
	end

	lasikPanel.icon:SetShown(Player.main)
	lasikPanel.border:SetShown(Player.main)
	lasikCooldownPanel:SetShown(Player.cd)
	lasikExtraPanel:SetShown(Player.extra)

	self:UpdateDisplay()
	self:UpdateGlows()
end

function UI:UpdateCombatWithin(seconds)
	if Opt.frequency - Timer.combat > seconds then
		Timer.combat = max(seconds, Opt.frequency - seconds)
	end
end

-- End UI Functions

-- Start Event Handling

function Events:ADDON_LOADED(name)
	if name == ADDON then
		Opt = Lasik
		local firstRun = not Opt.frequency
		InitOpts()
		UI:UpdateDraggable()
		UI:UpdateAlpha()
		UI:UpdateScale()
		if firstRun then
			log('It looks like this is your first time running ' .. ADDON .. ', why don\'t you take some time to familiarize yourself with the commands?')
			log('Type |cFFFFD000' .. SLASH_Lasik1 .. '|r for a list of commands.')
			UI:SnapAllPanels()
		end
		if UnitLevel('player') < 10 then
			log('[|cFFFFD000Warning|r]', ADDON, 'is not designed for players under level 10, and almost certainly will not operate properly!')
		end
	end
end

CombatEvent.TRIGGER = function(timeStamp, event, _, srcGUID, _, _, _, dstGUID, _, _, _, ...)
	Player:UpdateTime(timeStamp)
	local e = event
	if (
	   e == 'UNIT_DESTROYED' or
	   e == 'UNIT_DISSIPATES' or
	   e == 'SPELL_INSTAKILL' or
	   e == 'PARTY_KILL')
	then
		e = 'UNIT_DIED'
	elseif (
	   e == 'SPELL_CAST_START' or
	   e == 'SPELL_CAST_SUCCESS' or
	   e == 'SPELL_CAST_FAILED' or
	   e == 'SPELL_DAMAGE' or
	   e == 'SPELL_ABSORBED' or
	   e == 'SPELL_ENERGIZE' or
	   e == 'SPELL_PERIODIC_DAMAGE' or
	   e == 'SPELL_MISSED' or
	   e == 'SPELL_AURA_APPLIED' or
	   e == 'SPELL_AURA_REFRESH' or
	   e == 'SPELL_AURA_REMOVED')
	then
		e = 'SPELL'
	end
	if CombatEvent[e] then
		return CombatEvent[e](event, srcGUID, dstGUID, ...)
	end
end

CombatEvent.UNIT_DIED = function(event, srcGUID, dstGUID)
	local uid = ToUID(dstGUID)
	if not uid or Target.Dummies[uid] then
		return
	end
	TrackedAuras:Remove(dstGUID)
	if Opt.auto_aoe then
		AutoAoe:Remove(dstGUID)
	end
end

CombatEvent.SWING_DAMAGE = function(event, srcGUID, dstGUID, amount, overkill, spellSchool, resisted, blocked, absorbed, critical, glancing, crushing, offHand)
	if srcGUID == Player.guid then
		Player:ResetSwing(not offHand, offHand)
		if Opt.auto_aoe then
			AutoAoe:Add(dstGUID, true)
		end
	elseif dstGUID == Player.guid then
		Player.swing.last_taken = Player.time
		if Opt.auto_aoe then
			AutoAoe:Add(srcGUID, true)
		end
	end
end

CombatEvent.SWING_MISSED = function(event, srcGUID, dstGUID, missType, offHand, amountMissed)
	if srcGUID == Player.guid then
		Player:ResetSwing(not offHand, offHand, true)
		if Opt.auto_aoe and not (missType == 'EVADE' or missType == 'IMMUNE') then
			AutoAoe:Add(dstGUID, true)
		end
	elseif dstGUID == Player.guid then
		Player.swing.last_taken = Player.time
		if Opt.auto_aoe then
			AutoAoe:Add(srcGUID, true)
		end
	end
end

--local UnknownSpell = {}

CombatEvent.SPELL = function(event, srcGUID, dstGUID, spellId, spellName, spellSchool, missType, overCap, powerType)
	if srcGUID ~= Player.guid then
		return
	end

	local ability = spellId and Abilities.bySpellId[spellId]
	if not ability then
--[[
		if not UnknownSpell[event] then
			UnknownSpell[event] = {}
		end
		if not UnknownSpell[event][spellId] then
			UnknownSpell[event][spellId] = true
			log(format('%.3f EVENT %s TRACK CHECK FOR UNKNOWN %s ID %d FROM %s ON %s', Player.time, event, type(spellName) == 'string' and spellName or 'Unknown', spellId or 0, srcGUID, dstGUID))
		end
]]
		return
	end

	UI:UpdateCombatWithin(0.05)
	if event == 'SPELL_CAST_SUCCESS' then
		return ability:CastSuccess(dstGUID)
	elseif event == 'SPELL_CAST_START' then
		return ability.CastStart and ability:CastStart(dstGUID)
	elseif event == 'SPELL_CAST_FAILED'  then
		return ability.CastFailed and ability:CastFailed(dstGUID, missType)
	elseif event == 'SPELL_ENERGIZE' then
		return ability.Energize and ability:Energize(missType, overCap, powerType)
	end
	if ability.aura_targets then
		if event == 'SPELL_AURA_APPLIED' then
			ability:ApplyAura(dstGUID)
		elseif event == 'SPELL_AURA_REFRESH' then
			ability:RefreshAura(dstGUID)
		elseif event == 'SPELL_AURA_REMOVED' then
			ability:RemoveAura(dstGUID)
		end
	end
	if dstGUID == Player.guid then
		if event == 'SPELL_AURA_APPLIED' or event == 'SPELL_AURA_REFRESH' then
			ability.last_gained = Player.time
		end
		if ability == Metamorphosis and event == 'SPELL_AURA_REMOVED' then
			ability.full = false
		end
		return -- ignore buffs beyond here
	end
	if event == 'SPELL_DAMAGE' or event == 'SPELL_ABSORBED' or event == 'SPELL_MISSED' or event == 'SPELL_AURA_APPLIED' or event == 'SPELL_AURA_REFRESH' then
		ability:CastLanded(dstGUID, event, missType)
	end
end

function Events:COMBAT_LOG_EVENT_UNFILTERED()
	CombatEvent.TRIGGER(CombatLogGetCurrentEventInfo())
end

function Events:PLAYER_TARGET_CHANGED()
	Target:Update()
end

function Events:UNIT_FACTION(unitId)
	if unitId == 'target' then
		Target:Update()
	end
end

function Events:UNIT_FLAGS(unitId)
	if unitId == 'target' then
		Target:Update()
	end
end

function Events:UNIT_HEALTH(unitId)
	if unitId == 'player' then
		Player.health.current = UnitHealth(unitId)
		Player.health.max = UnitHealthMax(unitId)
		Player.health.pct = Player.health.current / Player.health.max * 100
	end
end

function Events:UNIT_MAXPOWER(unitId)
	if unitId == 'player' then
		Player.level = UnitLevel(unitId)
		Player.fury.max = UnitPowerMax(unitId, 17)
	end
end

function Events:UNIT_SPELLCAST_START(unitId, castGUID, spellId)
	if Opt.interrupt and unitId == 'target' then
		UI:UpdateCombatWithin(0.05)
	end
end

function Events:UNIT_SPELLCAST_STOP(unitId, castGUID, spellId)
	if Opt.interrupt and unitId == 'target' then
		UI:UpdateCombatWithin(0.05)
	end
end
Events.UNIT_SPELLCAST_FAILED = Events.UNIT_SPELLCAST_STOP
Events.UNIT_SPELLCAST_INTERRUPTED = Events.UNIT_SPELLCAST_STOP

function Events:UNIT_SPELLCAST_SUCCEEDED(unitId, castGUID, spellId)
	if unitId ~= 'player' or not spellId or castGUID:sub(6, 6) ~= '3' then
		return
	end
	local ability = Abilities.bySpellId[spellId]
	if not ability then
		return
	end
	if ability.traveling then
		ability.next_castGUID = castGUID
	end
end

function Events:UNIT_SPELLCAST_CHANNEL_UPDATE(unitId, castGUID, spellId)
	if unitId == 'player' then
		Player:UpdateChannelInfo()
	end
end
Events.UNIT_SPELLCAST_CHANNEL_START = Events.UNIT_SPELLCAST_CHANNEL_UPDATE
Events.UNIT_SPELLCAST_CHANNEL_STOP = Events.UNIT_SPELLCAST_CHANNEL_UPDATE

function Events:PLAYER_REGEN_DISABLED()
	Player:UpdateTime()
	Player.combat_start = Player.time
end

function Events:PLAYER_REGEN_ENABLED()
	Player:UpdateTime()
	Player.combat_start = 0
	Player.swing.last_taken = 0
	Target.estimated_range = 30
	wipe(Player.previous_gcd)
	if Player.last_ability then
		Player.last_ability = nil
		lasikPreviousPanel:Hide()
	end
	for _, ability in next, Abilities.velocity do
		for guid in next, ability.traveling do
			ability.traveling[guid] = nil
		end
	end
	if Opt.auto_aoe then
		AutoAoe:Clear()
	end
	if APL[Player.spec].precombat_variables then
		APL[Player.spec]:precombat_variables()
	end
end

function Events:PLAYER_EQUIPMENT_CHANGED()
	local _, equipType, hasCooldown
	Trinket1.itemId = GetInventoryItemID('player', 13) or 0
	Trinket2.itemId = GetInventoryItemID('player', 14) or 0
	for _, i in next, Trinket do -- use custom APL lines for these trinkets
		if Trinket1.itemId == i.itemId then
			Trinket1.itemId = 0
		end
		if Trinket2.itemId == i.itemId then
			Trinket2.itemId = 0
		end
	end
	for _, i in next, InventoryItems.all do
		i.name, _, _, _, _, _, _, _, equipType, i.icon = GetItemInfo(i.itemId or 0)
		i.can_use = i.name and true or false
		if equipType and equipType ~= '' then
			hasCooldown = 0
			_, i.equip_slot = Player:Equipped(i.itemId)
			if i.equip_slot then
				_, _, hasCooldown = GetInventoryItemCooldown('player', i.equip_slot)
			end
			i.can_use = hasCooldown == 1
		end
		if Player.item_use_blacklist[i.itemId] then
			i.can_use = false
		end
	end

	Player.set_bonus.t33 = (Player:Equipped(212063) and 1 or 0) + (Player:Equipped(212064) and 1 or 0) + (Player:Equipped(212065) and 1 or 0) + (Player:Equipped(212066) and 1 or 0) + (Player:Equipped(212068) and 1 or 0)

	Player:ResetSwing(true, true)
	Player:UpdateKnown()
end

function Events:PLAYER_SPECIALIZATION_CHANGED(unitId)
	if unitId ~= 'player' then
		return
	end
	Player.spec = GetSpecialization() or 0
	lasikPreviousPanel.ability = nil
	Player:SetTargetMode(1)
	Events:PLAYER_EQUIPMENT_CHANGED()
	Events:PLAYER_REGEN_ENABLED()
	Events:UNIT_HEALTH('player')
	Events:UNIT_MAXPOWER('player')
	Events:UPDATE_BINDINGS()
	UI.OnResourceFrameShow()
	Target:Update()
	Player:Update()
end

function Events:TRAIT_CONFIG_UPDATED()
	Events:PLAYER_SPECIALIZATION_CHANGED('player')
end

function Events:SPELL_UPDATE_COOLDOWN()
	if Opt.spell_swipe then
		local _, cooldown, castStart, castEnd
		_, _, _, castStart, castEnd = UnitCastingInfo('player')
		if castStart then
			cooldown = {
				startTime = castStart / 1000,
				duration = (castEnd - castStart) / 1000
			}
		else
			cooldown = GetSpellCooldown(61304)
		end
		lasikPanel.swipe:SetCooldown(cooldown.startTime, cooldown.duration)
	end
end

function Events:PLAYER_PVP_TALENT_UPDATE()
	Player:UpdateKnown()
end

function Events:ACTIONBAR_SLOT_CHANGED(slot)
	if not slot or slot < 1 then
		UI:ScanActionSlots()
		UI:UpdateBindings()
	else
		UI:UpdateActionSlot(slot)
	end
	UI:UpdateGlows()
end

function Events:ACTIONBAR_PAGE_CHANGED()
	C_Timer.After(0, function()
		Events:ACTIONBAR_SLOT_CHANGED(0)
	end)
end
Events.UPDATE_BONUS_ACTIONBAR = Events.ACTIONBAR_PAGE_CHANGED

function Events:UPDATE_BINDINGS()
	UI:UpdateBindings()
end
Events.GAME_PAD_ACTIVE_CHANGED = Events.UPDATE_BINDINGS

function Events:GROUP_ROSTER_UPDATE()
	Player.group_size = clamp(GetNumGroupMembers(), 1, 40)
end

function Events:PLAYER_ENTERING_WORLD()
	Player:Init()
	Target:Update()
	C_Timer.After(5, function() Events:PLAYER_EQUIPMENT_CHANGED() end)
end

lasikPanel.button:SetScript('OnClick', function(self, button, down)
	if down then
		if button == 'LeftButton' then
			Player:ToggleTargetMode()
		elseif button == 'RightButton' then
			Player:ToggleTargetModeReverse()
		elseif button == 'MiddleButton' then
			Player:SetTargetMode(1)
		end
	end
end)

lasikPanel:SetScript('OnUpdate', function(self, elapsed)
	Timer.combat = Timer.combat + elapsed
	Timer.display = Timer.display + elapsed
	Timer.health = Timer.health + elapsed
	if Timer.combat >= Opt.frequency then
		UI:UpdateCombat()
	end
	if Timer.display >= 0.05 then
		UI:UpdateDisplay()
	end
	if Timer.health >= 0.2 then
		Target:UpdateHealth()
	end
end)

lasikPanel:SetScript('OnEvent', function(self, event, ...) Events[event](self, ...) end)
for event in next, Events do
	lasikPanel:RegisterEvent(event)
end

-- End Event Handling

-- Start Slash Commands

-- this fancy hack allows you to click BattleTag links to add them as a friend!
local SetHyperlink = ItemRefTooltip.SetHyperlink
ItemRefTooltip.SetHyperlink = function(self, link)
	local linkType, linkData = link:match('(.-):(.*)')
	if linkType == 'BNadd' then
		BattleTagInviteFrame_Show(linkData)
		return
	end
	SetHyperlink(self, link)
end

local function Status(desc, opt, ...)
	local opt_view
	if type(opt) == 'string' then
		if opt:sub(1, 2) == '|c' then
			opt_view = opt
		else
			opt_view = '|cFFFFD000' .. opt .. '|r'
		end
	elseif type(opt) == 'number' then
		opt_view = '|cFFFFD000' .. opt .. '|r'
	else
		opt_view = opt and '|cFF00C000On|r' or '|cFFC00000Off|r'
	end
	log(desc .. ':', opt_view, ...)
end

SlashCmdList[ADDON] = function(msg, editbox)
	msg = { strsplit(' ', msg:lower()) }
	if startsWith(msg[1], 'lock') then
		if msg[2] then
			Opt.locked = msg[2] == 'on'
			UI:UpdateDraggable()
		end
		if Opt.aoe or Opt.snap then
			Status('Warning', 'Panels cannot be moved when aoe or snap are enabled!')
		end
		return Status('Locked', Opt.locked)
	end
	if startsWith(msg[1], 'snap') then
		if msg[2] then
			if msg[2] == 'above' or msg[2] == 'over' then
				Opt.snap = 'above'
				Opt.locked = true
			elseif msg[2] == 'below' or msg[2] == 'under' then
				Opt.snap = 'below'
				Opt.locked = true
			else
				Opt.snap = false
				Opt.locked = false
				UI:Reset()
			end
			UI:UpdateDraggable()
			UI.OnResourceFrameShow()
		end
		return Status('Snap to the Personal Resource Display frame', Opt.snap)
	end
	if msg[1] == 'scale' then
		if startsWith(msg[2], 'prev') then
			if msg[3] then
				Opt.scale.previous = tonumber(msg[3]) or 0.7
				UI:UpdateScale()
			end
			return Status('Previous ability icon scale', Opt.scale.previous, 'times')
		end
		if msg[2] == 'main' then
			if msg[3] then
				Opt.scale.main = tonumber(msg[3]) or 1
				UI:UpdateScale()
			end
			return Status('Main ability icon scale', Opt.scale.main, 'times')
		end
		if msg[2] == 'cd' then
			if msg[3] then
				Opt.scale.cooldown = tonumber(msg[3]) or 0.7
				UI:UpdateScale()
			end
			return Status('Cooldown ability icon scale', Opt.scale.cooldown, 'times')
		end
		if startsWith(msg[2], 'int') then
			if msg[3] then
				Opt.scale.interrupt = tonumber(msg[3]) or 0.4
				UI:UpdateScale()
			end
			return Status('Interrupt ability icon scale', Opt.scale.interrupt, 'times')
		end
		if startsWith(msg[2], 'ex') then
			if msg[3] then
				Opt.scale.extra = tonumber(msg[3]) or 0.4
				UI:UpdateScale()
			end
			return Status('Extra cooldown ability icon scale', Opt.scale.extra, 'times')
		end
		if msg[2] == 'glow' then
			if msg[3] then
				Opt.scale.glow = tonumber(msg[3]) or 1
				UI:UpdateGlowColorAndScale()
			end
			return Status('Action button glow scale', Opt.scale.glow, 'times')
		end
		return Status('Default icon scale options', '|cFFFFD000prev 0.7|r, |cFFFFD000main 1|r, |cFFFFD000cd 0.7|r, |cFFFFD000interrupt 0.4|r, |cFFFFD000extra 0.4|r, and |cFFFFD000glow 1|r')
	end
	if msg[1] == 'alpha' then
		if msg[2] then
			Opt.alpha = clamp(tonumber(msg[2]) or 100, 0, 100) / 100
			UI:UpdateAlpha()
		end
		return Status('Icon transparency', Opt.alpha * 100 .. '%')
	end
	if startsWith(msg[1], 'freq') then
		if msg[2] then
			Opt.frequency = tonumber(msg[2]) or 0.2
		end
		return Status('Calculation frequency (max time to wait between each update): Every', Opt.frequency, 'seconds')
	end
	if startsWith(msg[1], 'glow') then
		if msg[2] == 'main' then
			if msg[3] then
				Opt.glow.main = msg[3] == 'on'
				UI:UpdateGlows()
			end
			return Status('Glowing ability buttons (main icon)', Opt.glow.main)
		end
		if msg[2] == 'cd' then
			if msg[3] then
				Opt.glow.cooldown = msg[3] == 'on'
				UI:UpdateGlows()
			end
			return Status('Glowing ability buttons (cooldown icon)', Opt.glow.cooldown)
		end
		if startsWith(msg[2], 'int') then
			if msg[3] then
				Opt.glow.interrupt = msg[3] == 'on'
				UI:UpdateGlows()
			end
			return Status('Glowing ability buttons (interrupt icon)', Opt.glow.interrupt)
		end
		if startsWith(msg[2], 'ex') then
			if msg[3] then
				Opt.glow.extra = msg[3] == 'on'
				UI:UpdateGlows()
			end
			return Status('Glowing ability buttons (extra cooldown icon)', Opt.glow.extra)
		end
		if startsWith(msg[2], 'bliz') then
			if msg[3] then
				Opt.glow.blizzard = msg[3] == 'on'
				UI:UpdateGlows()
			end
			return Status('Blizzard default proc glow', Opt.glow.blizzard)
		end
		if startsWith(msg[2], 'anim') then
			if msg[3] then
				Opt.glow.animation = msg[3] == 'on'
				UI:UpdateGlows()
			end
			return Status('Use extended animation (shrinking circle)', Opt.glow.animation)
		end
		if msg[2] == 'color' then
			if msg[5] then
				Opt.glow.color.r = clamp(tonumber(msg[3]) or 0, 0, 1)
				Opt.glow.color.g = clamp(tonumber(msg[4]) or 0, 0, 1)
				Opt.glow.color.b = clamp(tonumber(msg[5]) or 0, 0, 1)
				UI:UpdateGlowColorAndScale()
			end
			return Status('Glow color', '|cFFFF0000' .. Opt.glow.color.r, '|cFF00FF00' .. Opt.glow.color.g, '|cFF0000FF' .. Opt.glow.color.b)
		end
		return Status('Possible glow options', '|cFFFFD000main|r, |cFFFFD000cd|r, |cFFFFD000interrupt|r, |cFFFFD000extra|r, |cFFFFD000blizzard|r, |cFFFFD000animation|r, and |cFFFFD000color')
	end
	if startsWith(msg[1], 'prev') then
		if msg[2] then
			Opt.previous = msg[2] == 'on'
			Target:Update()
		end
		return Status('Previous ability icon', Opt.previous)
	end
	if msg[1] == 'always' then
		if msg[2] then
			Opt.always_on = msg[2] == 'on'
			Target:Update()
		end
		return Status('Show the ' .. ADDON .. ' UI without a target', Opt.always_on)
	end
	if msg[1] == 'cd' then
		if msg[2] then
			Opt.cooldown = msg[2] == 'on'
		end
		return Status('Use ' .. ADDON .. ' for cooldown management', Opt.cooldown)
	end
	if msg[1] == 'swipe' then
		if msg[2] then
			Opt.spell_swipe = msg[2] == 'on'
		end
		return Status('Spell casting swipe animation', Opt.spell_swipe)
	end
	if startsWith(msg[1], 'key') or startsWith(msg[1], 'bind') then
		if msg[2] then
			Opt.keybinds = msg[2] == 'on'
		end
		return Status('Show keybinding text on main ability icon (topright)', Opt.keybinds)
	end
	if startsWith(msg[1], 'dim') then
		if msg[2] then
			Opt.dimmer = msg[2] == 'on'
		end
		return Status('Dim main ability icon when you don\'t have enough resources to use it', Opt.dimmer)
	end
	if msg[1] == 'miss' then
		if msg[2] then
			Opt.miss_effect = msg[2] == 'on'
		end
		return Status('Red border around previous ability when it fails to hit', Opt.miss_effect)
	end
	if msg[1] == 'aoe' then
		if msg[2] then
			Opt.aoe = msg[2] == 'on'
			Player:SetTargetMode(1)
			UI:UpdateDraggable()
		end
		return Status('Allow clicking main ability icon to toggle amount of targets (disables moving)', Opt.aoe)
	end
	if msg[1] == 'bossonly' then
		if msg[2] then
			Opt.boss_only = msg[2] == 'on'
		end
		return Status('Only use cooldowns on bosses', Opt.boss_only)
	end
	if startsWith(msg[1], 'hide') or startsWith(msg[1], 'spec') then
		if msg[2] then
			if startsWith(msg[2], 'h') then
				Opt.hide.havoc = not Opt.hide.havoc
				Events:PLAYER_SPECIALIZATION_CHANGED('player')
				return Status('Havoc specialization', not Opt.hide.havoc)
			end
			if startsWith(msg[2], 'v') then
				Opt.hide.vengeance = not Opt.hide.vengeance
				Events:PLAYER_SPECIALIZATION_CHANGED('player')
				return Status('Vengeance specialization', not Opt.hide.vengeance)
			end
		end
		return Status('Possible hidespec options', '|cFFFFD000havoc|r/|cFFFFD000vengeance|r')
	end
	if startsWith(msg[1], 'int') then
		if msg[2] then
			Opt.interrupt = msg[2] == 'on'
		end
		return Status('Show an icon for interruptable spells', Opt.interrupt)
	end
	if msg[1] == 'auto' then
		if msg[2] then
			Opt.auto_aoe = msg[2] == 'on'
		end
		return Status('Automatically change target mode on AoE spells', Opt.auto_aoe)
	end
	if msg[1] == 'ttl' then
		if msg[2] then
			Opt.auto_aoe_ttl = tonumber(msg[2]) or 10
		end
		return Status('Length of time target exists in auto AoE after being hit', Opt.auto_aoe_ttl, 'seconds')
	end
	if msg[1] == 'ttd' then
		if msg[2] then
			Opt.cd_ttd = tonumber(msg[2]) or 8
		end
		return Status('Minimum enemy lifetime to use cooldowns on (ignored on bosses)', Opt.cd_ttd, 'seconds')
	end
	if startsWith(msg[1], 'pot') then
		if msg[2] then
			Opt.pot = msg[2] == 'on'
		end
		return Status('Show flasks and battle potions in cooldown UI', Opt.pot)
	end
	if startsWith(msg[1], 'tri') then
		if msg[2] then
			Opt.trinket = msg[2] == 'on'
		end
		return Status('Show on-use trinkets in cooldown UI', Opt.trinket)
	end
	if msg[1] == 'reset' then
		UI:Reset()
		return Status('Position has been reset to', 'default')
	end
	print(ADDON, '(version: |cFFFFD000' .. C_AddOns.GetAddOnMetadata(ADDON, 'Version') .. '|r) - Commands:')
	for _, cmd in next, {
		'locked |cFF00C000on|r/|cFFC00000off|r - lock the ' .. ADDON .. ' UI so that it can\'t be moved',
		'snap |cFF00C000above|r/|cFF00C000below|r/|cFFC00000off|r - snap the ' .. ADDON .. ' UI to the Personal Resource Display',
		'scale |cFFFFD000prev|r/|cFFFFD000main|r/|cFFFFD000cd|r/|cFFFFD000interrupt|r/|cFFFFD000extra|r/|cFFFFD000glow|r - adjust the scale of the ' .. ADDON .. ' UI icons',
		'alpha |cFFFFD000[percent]|r - adjust the transparency of the ' .. ADDON .. ' UI icons',
		'frequency |cFFFFD000[number]|r - set the calculation frequency (default is every 0.2 seconds)',
		'glow |cFFFFD000main|r/|cFFFFD000cd|r/|cFFFFD000interrupt|r/|cFFFFD000extra|r/|cFFFFD000blizzard|r/|cFFFFD000animation|r |cFF00C000on|r/|cFFC00000off|r - glowing ability buttons on action bars',
		'glow color |cFFF000000.0-1.0|r |cFF00FF000.1-1.0|r |cFF0000FF0.0-1.0|r - adjust the color of the ability button glow',
		'previous |cFF00C000on|r/|cFFC00000off|r - previous ability icon',
		'always |cFF00C000on|r/|cFFC00000off|r - show the ' .. ADDON .. ' UI without a target',
		'cd |cFF00C000on|r/|cFFC00000off|r - use ' .. ADDON .. ' for cooldown management',
		'swipe |cFF00C000on|r/|cFFC00000off|r - show spell casting swipe animation on main ability icon',
		'keybind |cFF00C000on|r/|cFFC00000off|r - show keybinding text on main ability icon (topright)',
		'dim |cFF00C000on|r/|cFFC00000off|r - dim main ability icon when you don\'t have enough resources to use it',
		'miss |cFF00C000on|r/|cFFC00000off|r - red border around previous ability when it fails to hit',
		'aoe |cFF00C000on|r/|cFFC00000off|r - allow clicking main ability icon to toggle amount of targets (disables moving)',
		'bossonly |cFF00C000on|r/|cFFC00000off|r - only use cooldowns on bosses',
		'hidespec |cFFFFD000havoc|r/|cFFFFD000vengeance|r - toggle disabling ' .. ADDON .. ' for specializations',
		'interrupt |cFF00C000on|r/|cFFC00000off|r - show an icon for interruptable spells',
		'auto |cFF00C000on|r/|cFFC00000off|r  - automatically change target mode on AoE spells',
		'ttl |cFFFFD000[seconds]|r  - time target exists in auto AoE after being hit (default is 10 seconds)',
		'ttd |cFFFFD000[seconds]|r  - minimum enemy lifetime to use cooldowns on (default is 8 seconds, ignored on bosses)',
		'pot |cFF00C000on|r/|cFFC00000off|r - show flasks and battle potions in cooldown UI',
		'trinket |cFF00C000on|r/|cFFC00000off|r - show on-use trinkets in cooldown UI',
		'|cFFFFD000reset|r - reset the location of the ' .. ADDON .. ' UI to default',
	} do
		print('  ' .. SLASH_Lasik1 .. ' ' .. cmd)
	end
	print('Got ideas for improvement or found a bug? Talk to me on Battle.net:',
		'|c' .. BATTLENET_FONT_COLOR:GenerateHexColor() .. '|HBNadd:Spy#1955|h[Spy#1955]|h|r')
end

-- End Slash Commands
