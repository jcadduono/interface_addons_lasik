if select(2, UnitClass('player')) ~= 'DEMONHUNTER' then
	DisableAddOn('Lasik')
	return
end

-- copy heavily accessed global functions into local scope for performance
local GetSpellCooldown = _G.GetSpellCooldown
local GetSpellCharges = _G.GetSpellCharges
local GetTime = _G.GetTime
local UnitCastingInfo = _G.UnitCastingInfo
local UnitAura = _G.UnitAura
-- end copy global functions

-- useful functions
local function between(n, min, max)
	return n >= min and n <= max
end

local function startsWith(str, start) -- case insensitive check to see if a string matches the start of another string
	if type(str) ~= 'string' then
		return false
	end
   return string.lower(str:sub(1, start:len())) == start:lower()
end
-- end useful functions

Lasik = {}
local Opt -- use this as a local table reference to Lasik

SLASH_Lasik1, SLASH_Lasik2 = '/lasik', '/l'
BINDING_HEADER_LASIK = 'Lasik'

local function InitOpts()
	local function SetDefaults(t, ref)
		local k, v
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
		dimmer = true,
		miss_effect = true,
		boss_only = false,
		interrupt = true,
		aoe = false,
		auto_aoe = false,
		auto_aoe_ttl = 10,
		pot = false,
		trinket = true,
		meta_ttd = 8,
	})
end

-- UI related functions container
local UI = {
	anchor = {},
	glows = {},
}

-- automatically registered events container
local events = {}

local timer = {
	combat = 0,
	display = 0,
	health = 0
}

-- specialization constants
local SPEC = {
	NONE = 0,
	HAVOC = 1,
	VENGEANCE = 2,
}

-- current player information
local Player = {
	time = 0,
	time_diff = 0,
	ctime = 0,
	combat_start = 0,
	spec = 0,
	target_mode = 0,
	gcd = 1.5,
	health = 0,
	health_max = 0,
	fury = 0,
	fury_max = 100,
	pain = 0,
	pain_max = 100,
	soul_fragments = 0,
	last_swing_taken = 0,
	previous_gcd = {},-- list of previous GCD abilities
	item_use_blacklist = { -- list of item IDs with on-use effects we should mark unusable
		[174044] = true, -- Humming Black Dragonscale (parachute)
	},
}

-- current target information
local Target = {
	boss = false,
	guid = 0,
	healthArray = {},
	hostile = false,
	estimated_range = 30,
}

-- Azerite trait API access
local Azerite = {}

local lasikPanel = CreateFrame('Frame', 'lasikPanel', UIParent)
lasikPanel:SetPoint('CENTER', 0, -169)
lasikPanel:SetFrameStrata('BACKGROUND')
lasikPanel:SetSize(64, 64)
lasikPanel:SetMovable(true)
lasikPanel:Hide()
lasikPanel.icon = lasikPanel:CreateTexture(nil, 'BACKGROUND')
lasikPanel.icon:SetAllPoints(lasikPanel)
lasikPanel.icon:SetTexCoord(0.05, 0.95, 0.05, 0.95)
lasikPanel.border = lasikPanel:CreateTexture(nil, 'ARTWORK')
lasikPanel.border:SetAllPoints(lasikPanel)
lasikPanel.border:SetTexture('Interface\\AddOns\\Lasik\\border.blp')
lasikPanel.border:Hide()
lasikPanel.dimmer = lasikPanel:CreateTexture(nil, 'BORDER')
lasikPanel.dimmer:SetAllPoints(lasikPanel)
lasikPanel.dimmer:SetColorTexture(0, 0, 0, 0.6)
lasikPanel.dimmer:Hide()
lasikPanel.swipe = CreateFrame('Cooldown', nil, lasikPanel, 'CooldownFrameTemplate')
lasikPanel.swipe:SetAllPoints(lasikPanel)
lasikPanel.swipe:SetDrawBling(false)
lasikPanel.text = CreateFrame('Frame', nil, lasikPanel)
lasikPanel.text:SetAllPoints(lasikPanel)
lasikPanel.text.tl = lasikPanel.text:CreateFontString(nil, 'OVERLAY')
lasikPanel.text.tl:SetFont('Fonts\\FRIZQT__.TTF', 12, 'OUTLINE')
lasikPanel.text.tl:SetPoint('TOPLEFT', lasikPanel, 'TOPLEFT', 2.5, -3)
lasikPanel.text.tl:SetJustifyH('LEFT')
lasikPanel.text.tl:SetJustifyV('TOP')
lasikPanel.text.tr = lasikPanel.text:CreateFontString(nil, 'OVERLAY')
lasikPanel.text.tr:SetFont('Fonts\\FRIZQT__.TTF', 12, 'OUTLINE')
lasikPanel.text.tr:SetPoint('TOPRIGHT', lasikPanel, 'TOPRIGHT', -2.5, -3)
lasikPanel.text.tr:SetJustifyH('RIGHT')
lasikPanel.text.tr:SetJustifyV('TOP')
lasikPanel.text.bl = lasikPanel.text:CreateFontString(nil, 'OVERLAY')
lasikPanel.text.bl:SetFont('Fonts\\FRIZQT__.TTF', 12, 'OUTLINE')
lasikPanel.text.bl:SetPoint('BOTTOMLEFT', lasikPanel, 'BOTTOMLEFT', 2.5, 3)
lasikPanel.text.bl:SetJustifyH('LEFT')
lasikPanel.text.bl:SetJustifyV('BOTTOM')
lasikPanel.text.br = lasikPanel.text:CreateFontString(nil, 'OVERLAY')
lasikPanel.text.br:SetFont('Fonts\\FRIZQT__.TTF', 12, 'OUTLINE')
lasikPanel.text.br:SetPoint('BOTTOMRIGHT', lasikPanel, 'BOTTOMRIGHT', -2.5, 3)
lasikPanel.text.br:SetJustifyH('RIGHT')
lasikPanel.text.br:SetJustifyV('BOTTOM')
lasikPanel.button = CreateFrame('Button', nil, lasikPanel)
lasikPanel.button:SetAllPoints(lasikPanel)
lasikPanel.button:RegisterForClicks('LeftButtonDown', 'RightButtonDown', 'MiddleButtonDown')
local lasikPreviousPanel = CreateFrame('Frame', 'lasikPreviousPanel', UIParent)
lasikPreviousPanel:SetFrameStrata('BACKGROUND')
lasikPreviousPanel:SetSize(64, 64)
lasikPreviousPanel:Hide()
lasikPreviousPanel:RegisterForDrag('LeftButton')
lasikPreviousPanel:SetScript('OnDragStart', lasikPreviousPanel.StartMoving)
lasikPreviousPanel:SetScript('OnDragStop', lasikPreviousPanel.StopMovingOrSizing)
lasikPreviousPanel:SetMovable(true)
lasikPreviousPanel.icon = lasikPreviousPanel:CreateTexture(nil, 'BACKGROUND')
lasikPreviousPanel.icon:SetAllPoints(lasikPreviousPanel)
lasikPreviousPanel.icon:SetTexCoord(0.05, 0.95, 0.05, 0.95)
lasikPreviousPanel.border = lasikPreviousPanel:CreateTexture(nil, 'ARTWORK')
lasikPreviousPanel.border:SetAllPoints(lasikPreviousPanel)
lasikPreviousPanel.border:SetTexture('Interface\\AddOns\\Lasik\\border.blp')
local lasikCooldownPanel = CreateFrame('Frame', 'lasikCooldownPanel', UIParent)
lasikCooldownPanel:SetSize(64, 64)
lasikCooldownPanel:SetFrameStrata('BACKGROUND')
lasikCooldownPanel:Hide()
lasikCooldownPanel:RegisterForDrag('LeftButton')
lasikCooldownPanel:SetScript('OnDragStart', lasikCooldownPanel.StartMoving)
lasikCooldownPanel:SetScript('OnDragStop', lasikCooldownPanel.StopMovingOrSizing)
lasikCooldownPanel:SetMovable(true)
lasikCooldownPanel.icon = lasikCooldownPanel:CreateTexture(nil, 'BACKGROUND')
lasikCooldownPanel.icon:SetAllPoints(lasikCooldownPanel)
lasikCooldownPanel.icon:SetTexCoord(0.05, 0.95, 0.05, 0.95)
lasikCooldownPanel.border = lasikCooldownPanel:CreateTexture(nil, 'ARTWORK')
lasikCooldownPanel.border:SetAllPoints(lasikCooldownPanel)
lasikCooldownPanel.border:SetTexture('Interface\\AddOns\\Lasik\\border.blp')
lasikCooldownPanel.cd = CreateFrame('Cooldown', nil, lasikCooldownPanel, 'CooldownFrameTemplate')
lasikCooldownPanel.cd:SetAllPoints(lasikCooldownPanel)
local lasikInterruptPanel = CreateFrame('Frame', 'lasikInterruptPanel', UIParent)
lasikInterruptPanel:SetFrameStrata('BACKGROUND')
lasikInterruptPanel:SetSize(64, 64)
lasikInterruptPanel:Hide()
lasikInterruptPanel:RegisterForDrag('LeftButton')
lasikInterruptPanel:SetScript('OnDragStart', lasikInterruptPanel.StartMoving)
lasikInterruptPanel:SetScript('OnDragStop', lasikInterruptPanel.StopMovingOrSizing)
lasikInterruptPanel:SetMovable(true)
lasikInterruptPanel.icon = lasikInterruptPanel:CreateTexture(nil, 'BACKGROUND')
lasikInterruptPanel.icon:SetAllPoints(lasikInterruptPanel)
lasikInterruptPanel.icon:SetTexCoord(0.05, 0.95, 0.05, 0.95)
lasikInterruptPanel.border = lasikInterruptPanel:CreateTexture(nil, 'ARTWORK')
lasikInterruptPanel.border:SetAllPoints(lasikInterruptPanel)
lasikInterruptPanel.border:SetTexture('Interface\\AddOns\\Lasik\\border.blp')
lasikInterruptPanel.cast = CreateFrame('Cooldown', nil, lasikInterruptPanel, 'CooldownFrameTemplate')
lasikInterruptPanel.cast:SetAllPoints(lasikInterruptPanel)
local lasikExtraPanel = CreateFrame('Frame', 'lasikExtraPanel', UIParent)
lasikExtraPanel:SetFrameStrata('BACKGROUND')
lasikExtraPanel:SetSize(64, 64)
lasikExtraPanel:Hide()
lasikExtraPanel:RegisterForDrag('LeftButton')
lasikExtraPanel:SetScript('OnDragStart', lasikExtraPanel.StartMoving)
lasikExtraPanel:SetScript('OnDragStop', lasikExtraPanel.StopMovingOrSizing)
lasikExtraPanel:SetMovable(true)
lasikExtraPanel.icon = lasikExtraPanel:CreateTexture(nil, 'BACKGROUND')
lasikExtraPanel.icon:SetAllPoints(lasikExtraPanel)
lasikExtraPanel.icon:SetTexCoord(0.05, 0.95, 0.05, 0.95)
lasikExtraPanel.border = lasikExtraPanel:CreateTexture(nil, 'ARTWORK')
lasikExtraPanel.border:SetAllPoints(lasikExtraPanel)
lasikExtraPanel.border:SetTexture('Interface\\AddOns\\Lasik\\border.blp')

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
		{5, '5+'},
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

local autoAoe = {
	targets = {},
	blacklist = {},
	ignored_units = {
		[120651] = true, -- Explosives (Mythic+ affix)
		[161895] = true, -- Thing From Beyond (40+ Corruption)
	},
}

function autoAoe:Add(guid, update)
	if self.blacklist[guid] then
		return
	end
	local unitId = guid:match('^%w+-%d+-%d+-%d+-%d+-(%d+)')
	if unitId and self.ignored_units[tonumber(unitId)] then
		self.blacklist[guid] = Player.time + 10
		return
	end
	local new = not self.targets[guid]
	self.targets[guid] = Player.time
	if update and new then
		self:Update()
	end
end

function autoAoe:Remove(guid)
	-- blacklist enemies for 2 seconds when they die to prevent out of order events from re-adding them
	self.blacklist[guid] = Player.time + 2
	if self.targets[guid] then
		self.targets[guid] = nil
		self:Update()
	end
end

function autoAoe:Clear()
	local guid
	for guid in next, self.targets do
		self.targets[guid] = nil
	end
end

function autoAoe:Update()
	local count, i = 0
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

function autoAoe:Purge()
	local update, guid, t
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

local Ability = {}
Ability.__index = Ability
local abilities = {
	all = {}
}

function Ability:Add(spellId, buff, player, spellId2)
	local ability = {
		spellIds = type(spellId) == 'table' and spellId or { spellId },
		spellId = 0,
		spellId2 = spellId2,
		name = false,
		icon = false,
		requires_charge = false,
		triggers_gcd = true,
		hasted_duration = false,
		hasted_cooldown = false,
		hasted_ticks = false,
		known = false,
		fury_cost = 0,
		pain_cost = 0,
		cooldown_duration = 0,
		buff_duration = 0,
		tick_interval = 0,
		max_range = 40,
		velocity = 0,
		last_used = 0,
		auraTarget = buff and 'player' or 'target',
		auraFilter = (buff and 'HELPFUL' or 'HARMFUL') .. (player and '|PLAYER' or '')
	}
	setmetatable(ability, self)
	abilities.all[#abilities.all + 1] = ability
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
	return self:Cooldown() <= (seconds or 0)
end

function Ability:Usable()
	if not self.known then
		return false
	end
	if Player.spec == SPEC.HAVOC then
		if self:FuryCost() > Player.fury then
			return false
		end
	elseif Player.spec == SPEC.VENGEANCE then
		if self:PainCost() > Player.pain then
			return false
		end
	end
	if self.requires_charge and self:Charges() == 0 then
		return false
	end
	return self:Ready()
end

function Ability:Remains()
	if self:Casting() or self:Traveling() then
		return self:Duration()
	end
	local _, i, id, expires
	for i = 1, 40 do
		_, _, _, _, _, expires, _, _, _, id = UnitAura(self.auraTarget, i, self.auraFilter)
		if not id then
			return 0
		end
		if self:Match(id) then
			if expires == 0 then
				return 600 -- infinite duration
			end
			return max(expires - Player.ctime - Player.execute_remains, 0)
		end
	end
	return 0
end

function Ability:Refreshable()
	if self.buff_duration > 0 then
		return self:Remains() < self:Duration() * 0.3
	end
	return self:Down()
end

function Ability:Up()
	return self:Remains() > 0
end

function Ability:Down()
	return not self:Up()
end

function Ability:SetVelocity(velocity)
	if velocity > 0 then
		self.velocity = velocity
		self.travel_start = {}
	else
		self.travel_start = nil
		self.velocity = 0
	end
end

function Ability:Traveling()
	if self.travel_start and self.travel_start[Target.guid] then
		if Player.time - self.travel_start[Target.guid] < self.max_range / self.velocity then
			return true
		end
		self.travel_start[Target.guid] = nil
	end
end

function Ability:TravelTime()
	return Target.estimated_range / self.velocity
end

function Ability:Ticking()
	if self.aura_targets then
		local count, guid, aura = 0
		for guid, aura in next, self.aura_targets do
			if aura.expires - Player.time > Player.execute_remains then
				count = count + 1
			end
		end
		return count
	end
	return self:Up() and 1 or 0
end

function Ability:TickTime()
	return self.hasted_ticks and (Player.haste_factor * self.tick_interval) or self.tick_interval
end

function Ability:CooldownDuration()
	return self.hasted_cooldown and (Player.haste_factor * self.cooldown_duration) or self.cooldown_duration
end

function Ability:Cooldown()
	if self.cooldown_duration > 0 and self:Casting() then
		return self.cooldown_duration
	end
	local start, duration = GetSpellCooldown(self.spellId)
	if start == 0 then
		return 0
	end
	return max(0, duration - (Player.ctime - start) - Player.execute_remains)
end

function Ability:Stack()
	local _, i, id, expires, count
	for i = 1, 40 do
		_, _, count, _, _, expires, _, _, _, id = UnitAura(self.auraTarget, i, self.auraFilter)
		if not id then
			return 0
		end
		if self:Match(id) then
			return (expires == 0 or expires - Player.ctime > Player.execute_remains) and count or 0
		end
	end
	return 0
end

function Ability:FuryCost()
	return self.fury_cost
end

function Ability:PainCost()
	return self.pain_cost
end

function Ability:Charges()
	return (GetSpellCharges(self.spellId)) or 0
end

function Ability:ChargesFractional()
	local charges, max_charges, recharge_start, recharge_time = GetSpellCharges(self.spellId)
	if charges >= max_charges then
		return charges
	end
	return charges + ((max(0, Player.ctime - recharge_start + Player.execute_remains)) / recharge_time)
end

function Ability:FullRechargeTime()
	local charges, max_charges, recharge_start, recharge_time = GetSpellCharges(self.spellId)
	if charges >= max_charges then
		return 0
	end
	return (max_charges - charges - 1) * recharge_time + (recharge_time - (Player.ctime - recharge_start) - Player.execute_remains)
end

function Ability:MaxCharges()
	local _, max_charges = GetSpellCharges(self.spellId)
	return max_charges or 0
end

function Ability:Duration()
	return self.hasted_duration and (Player.haste_factor * self.buff_duration) or self.buff_duration
end

function Ability:Casting()
	return Player.ability_casting == self
end

function Ability:Channeling()
	return UnitChannelInfo('player') == self.name
end

function Ability:CastTime()
	local _, _, _, castTime = GetSpellInfo(self.spellId)
	if castTime == 0 then
		return self.triggers_gcd and Player.gcd or 0
	end
	return castTime / 1000
end

function Ability:Previous(n)
	local i = n or 1
	if Player.ability_casting then
		if i == 1 then
			return Player.ability_casting == self
		end
		i = i - 1
	end
	return Player.previous_gcd[i] == self
end

function Ability:AzeriteRank()
	return Azerite.traits[self.spellId] or 0
end

function Ability:AutoAoe(removeUnaffected, trigger)
	self.auto_aoe = {
		remove = removeUnaffected,
		targets = {}
	}
	if trigger == 'periodic' then
		self.auto_aoe.trigger = 'SPELL_PERIODIC_DAMAGE'
	elseif trigger == 'apply' then
		self.auto_aoe.trigger = 'SPELL_AURA_APPLIED'
	else
		self.auto_aoe.trigger = 'SPELL_DAMAGE'
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
		if self.auto_aoe.remove then
			autoAoe:Clear()
		end
		local guid
		for guid in next, self.auto_aoe.targets do
			autoAoe:Add(guid)
			self.auto_aoe.targets[guid] = nil
		end
		autoAoe:Update()
	end
end

-- start DoT tracking

local trackAuras = {}

function trackAuras:Purge()
	local _, ability, guid, expires
	for _, ability in next, abilities.trackAuras do
		for guid, aura in next, ability.aura_targets do
			if aura.expires <= Player.time then
				ability:RemoveAura(guid)
			end
		end
	end
end

function trackAuras:Remove(guid)
	local _, ability
	for _, ability in next, abilities.trackAuras do
		ability:RemoveAura(guid)
	end
end

function Ability:TrackAuras()
	self.aura_targets = {}
end

function Ability:ApplyAura(guid)
	if autoAoe.blacklist[guid] then
		return
	end
	local aura = {
		expires = Player.time + self:Duration()
	}
	self.aura_targets[guid] = aura
end

function Ability:RefreshAura(guid)
	if autoAoe.blacklist[guid] then
		return
	end
	local aura = self.aura_targets[guid]
	if not aura then
		self:ApplyAura(guid)
		return
	end
	local duration = self:Duration()
	aura.expires = Player.time + min(duration * 1.3, (aura.expires - Player.time) + duration)
end

function Ability:RemoveAura(guid)
	if self.aura_targets[guid] then
		self.aura_targets[guid] = nil
	end
end

-- end DoT tracking

-- Demon Hunter Abilities
---- Multiple Specializations
local Disrupt = Ability:Add(183752, false, true)
Disrupt.cooldown_duration = 15
Disrupt.triggers_gcd = false
local Torment = Ability:Add(185245, false, true)
Torment.cooldown_duration = 8
Torment.triggers_gcd = false
------ Talents

------ Procs

---- Havoc
local Annihilation = Ability:Add(201427, false, true, 201428)
Annihilation.fury_cost = 40
local BladeDance = Ability:Add(188499, false, true, 199552)
BladeDance.cooldown_duration = 9
BladeDance.fury_cost = 35
BladeDance.hasted_cooldown = true
BladeDance:AutoAoe(true)
local ChaosNova = Ability:Add(179057, false, true)
ChaosNova.buff_duration = 2
ChaosNova.cooldown_duration = 60
ChaosNova.fury_cost = 30
local ChaosStrike = Ability:Add(162794, false, true)
ChaosStrike.fury_cost = 40
local DeathSweep = Ability:Add(210152, false, true, 210153)
DeathSweep.cooldown_duration = 9
DeathSweep.fury_cost = 35
DeathSweep.hasted_cooldown = true
DeathSweep:AutoAoe(true)
local DemonsBite = Ability:Add(162243, false, true)
local EyeBeam = Ability:Add(198013, false, true, 198030)
EyeBeam.buff_duration = 2
EyeBeam.cooldown_duration = 30
EyeBeam.fury_cost = 30
EyeBeam:AutoAoe(true)
local FelRush = Ability:Add(195072, false, true, 192611)
FelRush.cooldown_duration = 10
FelRush.requires_charge = true
FelRush:AutoAoe()
local Metamorphosis = Ability:Add(191427, true, true, 162264)
Metamorphosis.buff_duration = 30
Metamorphosis.cooldown_duration = 240
Metamorphosis.stun = Ability:Add(200166, false, true)
Metamorphosis.stun.buff_duration = 3
Metamorphosis.stun:AutoAoe(false, 'apply')
local ThrowGlaive = Ability:Add(185123, false, true)
ThrowGlaive.cooldown_duration = 9
ThrowGlaive.hasted_cooldown = true
ThrowGlaive:AutoAoe()
local VengefulRetreat = Ability:Add(198793, false, true, 198813)
VengefulRetreat.cooldown_duration = 25
VengefulRetreat:AutoAoe()
------ Talents
local BlindFury = Ability:Add(203550, false, true)
local DarkSlash = Ability:Add(258860, false, true)
DarkSlash.buff_duration = 8
DarkSlash.cooldown_duration = 20
local DemonBlades = Ability:Add(203555, false, true, 203796)
local Demonic = Ability:Add(213410, false, true)
local Felblade = Ability:Add(232893, false, true, 213243)
Felblade.cooldown_duration = 15
Felblade.hasted_cooldown = true
local FelBarrage = Ability:Add(258925, false, true, 258926)
FelBarrage.cooldown_duration = 60
FelBarrage:AutoAoe()
local FelEruption = Ability:Add(211881, false, true)
FelEruption.buff_duration = 4
FelEruption.cooldown_duration =  30
FelEruption.fury_cost = 10
FelEruption.pain_cost = 10
local FelMastery = Ability:Add(192939, false, true)
local FirstBlood = Ability:Add(206416, false, true)
local ImmolationAura = Ability:Add(258920, true, true)
ImmolationAura.buff_duration = 10
ImmolationAura.cooldown_duration = 30
ImmolationAura.tick_interval = 1
ImmolationAura.hasted_cooldown = true
ImmolationAura.damage = Ability:Add(258922, false, true)
ImmolationAura.damage:AutoAoe(true)
local Momentum = Ability:Add(206476, true, true, 208628)
Momentum.buff_duration = 6
local Nemesis = Ability:Add(206491, false, true)
Nemesis.buff_duration = 60
Nemesis.cooldown_duration = 120
local TrailOfRuin = Ability:Add(258881, false, true, 258883)
TrailOfRuin.buff_duration = 4
TrailOfRuin.tick_interval = 1
local UnleashedPower = Ability:Add(206477, false, true)
------ Procs

---- Vengeance
local DemonSpikes = Ability:Add(203720, true, true, 203819)
DemonSpikes.buff_duration = 6
DemonSpikes.cooldown_duration = 20
DemonSpikes.hasted_cooldown = true
DemonSpikes.requires_charge = true
local FieryBrand = Ability:Add(204021, false, true)
FieryBrand.buff_duration = 8
FieryBrand.cooldown_duration = 60
FieryBrand:TrackAuras()
local ImmolationAuraV = Ability:Add(178740, true, true)
ImmolationAuraV.buff_duration = 6
ImmolationAuraV.cooldown_duration = 15
ImmolationAuraV.tick_interval = 1
ImmolationAuraV.hasted_cooldown = true
ImmolationAuraV.damage = Ability:Add(178741, false, true)
ImmolationAuraV.damage:AutoAoe(true)
local InfernalStrike = Ability:Add(189110, false, true, 189112)
InfernalStrike.cooldown_duration = 20
InfernalStrike.requires_charge = true
InfernalStrike.triggers_gcd = false
InfernalStrike:AutoAoe()
local MetamorphosisV = Ability:Add(187827, true, true)
MetamorphosisV.buff_duration = 15
MetamorphosisV.cooldown_duration = 180
local Shear = Ability:Add(203783, false, true)
local SigilOfChains = Ability:Add(202138, false, true)
SigilOfChains.cooldown_duration = 90
SigilOfChains.buff_duration = 2
local SigilOfFlame = Ability:Add(204596, false, true)
SigilOfFlame.cooldown_duration = 30
SigilOfFlame.buff_duration = 2
SigilOfFlame.dot = Ability:Add(204598, false, true)
SigilOfFlame.dot.buff_duration = 6
SigilOfFlame.dot.tick_interval = 1
SigilOfFlame.dot:AutoAoe(false, 'apply')
local SigilOfMisery = Ability:Add(207684, false, true)
SigilOfMisery.cooldown_duration = 90
SigilOfMisery.buff_duration = 2
local SigilOfSilence = Ability:Add(202137, false, true)
SigilOfSilence.cooldown_duration = 60
SigilOfSilence.buff_duration = 2
local SoulCleave = Ability:Add(228477, false, true, 228478)
SoulCleave.pain_cost = 30
SoulCleave:AutoAoe(true)
local SoulFragments = Ability:Add(204254, true, true, 203981)
local ThrowGlaiveV = Ability:Add(204157, false, true)
ThrowGlaiveV.cooldown_duration = 3
ThrowGlaiveV.hasted_cooldown = true
ThrowGlaiveV:AutoAoe()
------ Talents
local CharredFlesh = Ability:Add(264002, true, true)
local FelDevastation = Ability:Add(212084, false, true)
FelDevastation.buff_duration = 2
FelDevastation.cooldown_duration = 60
FelDevastation:AutoAoe()
local FlameCrash = Ability:Add(227322, true, true)
local Fracture = Ability:Add(263642, false, true)
Fracture.cooldown_duration = 4.5
Fracture.hasted_cooldown = true
Fracture.requires_charge = true
local SpiritBomb = Ability:Add(247454, false, true)
SpiritBomb.pain_cost = 30
SpiritBomb:AutoAoe(true)
local QuickenedSigils = Ability:Add(209281, true, true)
------ Procs

-- Heart of Azeroth
---- Azerite Traits
local ChaoticTransformation = Ability:Add(288754, false, true)
local EyesOfRage = Ability:Add(278500, false, true)
local FuriousGaze = Ability:Add(273231, true, true, 273232)
FuriousGaze.buff_duration = 12
local RevolvingBlades = Ability:Add(279581, false, true, 279584)
RevolvingBlades.buff_duration = 12
---- Major Essences
local BloodOfTheEnemy = Ability:Add({297108, 298273, 298277} , false, true)
BloodOfTheEnemy.buff_duration = 10
BloodOfTheEnemy.cooldown_duration = 120
BloodOfTheEnemy.essence_id = 23
BloodOfTheEnemy.essence_major = true
local ConcentratedFlame = Ability:Add({295373, 299349, 299353}, true, true, 295378)
ConcentratedFlame.buff_duration = 180
ConcentratedFlame.cooldown_duration = 30
ConcentratedFlame.requires_charge = true
ConcentratedFlame.essence_id = 12
ConcentratedFlame.essence_major = true
ConcentratedFlame:SetVelocity(40)
ConcentratedFlame.dot = Ability:Add(295368, false, true)
ConcentratedFlame.dot.buff_duration = 6
ConcentratedFlame.dot.tick_interval = 2
ConcentratedFlame.dot.essence_id = 12
ConcentratedFlame.dot.essence_major = true
local GuardianOfAzeroth = Ability:Add({295840, 299355, 299358}, false, true)
GuardianOfAzeroth.cooldown_duration = 180
GuardianOfAzeroth.essence_id = 14
GuardianOfAzeroth.essence_major = true
local FocusedAzeriteBeam = Ability:Add({295258, 299336, 299338}, false, true)
FocusedAzeriteBeam.cooldown_duration = 90
FocusedAzeriteBeam.essence_id = 5
FocusedAzeriteBeam.essence_major = true
local MemoryOfLucidDreams = Ability:Add({298357, 299372, 299374}, true, true)
MemoryOfLucidDreams.buff_duration = 15
MemoryOfLucidDreams.cooldown_duration = 120
MemoryOfLucidDreams.essence_id = 27
MemoryOfLucidDreams.essence_major = true
local PurifyingBlast = Ability:Add({295337, 299345, 299347}, false, true, 295338)
PurifyingBlast.cooldown_duration = 60
PurifyingBlast.essence_id = 6
PurifyingBlast.essence_major = true
PurifyingBlast:AutoAoe(true)
local ReapingFlames = Ability:Add({310690, 311194, 311195}, false, true)
ReapingFlames.cooldown_duration = 45
ReapingFlames.essence_id = 35
ReapingFlames.essence_major = true
local RippleInSpace = Ability:Add({302731, 302982, 302983}, true, true)
RippleInSpace.buff_duration = 2
RippleInSpace.cooldown_duration = 60
RippleInSpace.essence_id = 15
RippleInSpace.essence_major = true
local TheUnboundForce = Ability:Add({298452, 299376,299378}, false, true)
TheUnboundForce.cooldown_duration = 45
TheUnboundForce.essence_id = 28
TheUnboundForce.essence_major = true
local VisionOfPerfection = Ability:Add({296325, 299368, 299370}, true, true, 303345)
VisionOfPerfection.buff_duration = 10
VisionOfPerfection.essence_id = 22
VisionOfPerfection.essence_major = true
local WorldveinResonance = Ability:Add({295186, 298628, 299334}, true, true)
WorldveinResonance.cooldown_duration = 60
WorldveinResonance.essence_id = 4
WorldveinResonance.essence_major = true
---- Minor Essences
local AncientFlame = Ability:Add(295367, false, true)
AncientFlame.buff_duration = 10
AncientFlame.essence_id = 12
local CondensedLifeForce = Ability:Add(295367, false, true)
CondensedLifeForce.essence_id = 14
local FocusedEnergy = Ability:Add(295248, true, true)
FocusedEnergy.buff_duration = 4
FocusedEnergy.essence_id = 5
local Lifeblood = Ability:Add(295137, true, true)
Lifeblood.essence_id = 4
local LucidDreams = Ability:Add(298343, true, true)
LucidDreams.buff_duration = 8
LucidDreams.essence_id = 27
local PurificationProtocol = Ability:Add(295305, false, true)
PurificationProtocol.essence_id = 6
PurificationProtocol:AutoAoe()
local RealityShift = Ability:Add(302952, true, true)
RealityShift.buff_duration = 20
RealityShift.cooldown_duration = 30
RealityShift.essence_id = 15
local RecklessForce = Ability:Add(302932, true, true)
RecklessForce.buff_duration = 3
RecklessForce.essence_id = 28
local StriveForPerfection = Ability:Add(299369, true, true)
StriveForPerfection.essence_id = 22
-- Racials
local ArcaneTorrent = Ability:Add(25046, true, false) -- Blood Elf
local Shadowmeld = Ability:Add(58984, true, true) -- Night Elf

-- PvP talents

-- Trinket Effects

-- End Abilities

-- Start Inventory Items

local InventoryItem, inventoryItems, Trinket = {}, {}, {}
InventoryItem.__index = InventoryItem

function InventoryItem:Add(itemId)
	local name, _, _, _, _, _, _, _, _, icon = GetItemInfo(itemId)
	local item = {
		itemId = itemId,
		name = name,
		icon = icon,
		can_use = false,
	}
	setmetatable(item, self)
	inventoryItems[#inventoryItems + 1] = item
	return item
end

function InventoryItem:Charges()
	local charges = GetItemCount(self.itemId, false, true) or 0
	if self.created_by and (self.created_by:Previous() or Player.previous_gcd[1] == self.created_by) then
		charges = max(charges, self.max_charges)
	end
	return charges
end

function InventoryItem:Count()
	local count = GetItemCount(self.itemId, false, false) or 0
	if self.created_by and (self.created_by:Previous() or Player.previous_gcd[1] == self.created_by) then
		count = max(count, 1)
	end
	return count
end

function InventoryItem:Cooldown()
	local startTime, duration
	if self.equip_slot then
		startTime, duration = GetInventoryItemCooldown('player', self.equip_slot)
	else
		startTime, duration = GetItemCooldown(self.itemId)
	end
	return startTime == 0 and 0 or duration - (Player.ctime - startTime)
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
local GreaterFlaskOfTheCurrents = InventoryItem:Add(168651)
GreaterFlaskOfTheCurrents.buff = Ability:Add(298836, true, true)
local SuperiorBattlePotionOfAgility = InventoryItem:Add(168489)
SuperiorBattlePotionOfAgility.buff = Ability:Add(298146, true, true)
SuperiorBattlePotionOfAgility.buff.triggers_gcd = false
local PotionOfUnbridledFury = InventoryItem:Add(169299)
PotionOfUnbridledFury.buff = Ability:Add(300714, true, true)
PotionOfUnbridledFury.buff.triggers_gcd = false
-- Equipment
local Trinket1 = InventoryItem:Add(0)
local Trinket2 = InventoryItem:Add(0)
-- End Inventory Items

-- Start Azerite Trait API

Azerite.equip_slots = { 1, 3, 5 } -- Head, Shoulder, Chest

function Azerite:Init()
	self.locations = {}
	self.traits = {}
	self.essences = {}
	local i
	for i = 1, #self.equip_slots do
		self.locations[i] = ItemLocation:CreateFromEquipmentSlot(self.equip_slots[i])
	end
end

function Azerite:Update()
	local _, loc, slot, pid, pinfo
	for pid in next, self.traits do
		self.traits[pid] = nil
	end
	for pid in next, self.essences do
		self.essences[pid] = nil
	end
	if UnitEffectiveLevel('player') < 110 then
		return -- disable all Azerite/Essences for players scaled under 110
	end
	for _, loc in next, self.locations do
		if GetInventoryItemID('player', loc:GetEquipmentSlot()) and C_AzeriteEmpoweredItem.IsAzeriteEmpoweredItem(loc) then
			for _, slot in next, C_AzeriteEmpoweredItem.GetAllTierInfo(loc) do
				if slot.azeritePowerIDs then
					for _, pid in next, slot.azeritePowerIDs do
						if C_AzeriteEmpoweredItem.IsPowerSelected(loc, pid) then
							self.traits[pid] = 1 + (self.traits[pid] or 0)
							pinfo = C_AzeriteEmpoweredItem.GetPowerInfo(pid)
							if pinfo and pinfo.spellID then
								--print('Azerite found:', pinfo.azeritePowerID, GetSpellInfo(pinfo.spellID))
								self.traits[pinfo.spellID] = self.traits[pid]
							end
						end
					end
				end
			end
		end
	end
	for _, loc in next, C_AzeriteEssence.GetMilestones() or {} do
		if loc.slot then
			pid = C_AzeriteEssence.GetMilestoneEssence(loc.ID)
			if pid then
				pinfo = C_AzeriteEssence.GetEssenceInfo(pid)
				self.essences[pid] = {
					id = pid,
					rank = pinfo.rank,
					major = loc.slot == 0,
				}
			end
		end
	end
end

-- End Azerite Trait API

-- Start Player API

function Player:Health()
	return self.health
end

function Player:HealthMax()
	return self.health_max
end

function Player:HealthPct()
	return self.health / self.health_max * 100
end

function Player:Fury()
	return self.fury
end

function Player:FuryDeficit()
	return self.fury_max - self.fury
end

function Player:Pain()
	return self.pain
end

function Player:PainDeficit()
	return self.pain_max - self.pain
end

function Player:UnderAttack()
	return (Player.time - self.last_swing_taken) < 3
end

function Player:TimeInCombat()
	if self.combat_start > 0 then
		return self.time - self.combat_start
	end
	return 0
end

function Player:BloodlustActive()
	local _, i, id
	for i = 1, 40 do
		_, _, _, _, _, _, _, _, _, id = UnitAura('player', i, 'HELPFUL')
		if (
			id == 2825 or   -- Bloodlust (Horde Shaman)
			id == 32182 or  -- Heroism (Alliance Shaman)
			id == 80353 or  -- Time Warp (Mage)
			id == 90355 or  -- Ancient Hysteria (Hunter Pet - Core Hound)
			id == 160452 or -- Netherwinds (Hunter Pet - Nether Ray)
			id == 264667 or -- Primal Rage (Hunter Pet - Ferocity)
			id == 178207 or -- Drums of Fury (Leatherworking)
			id == 146555 or -- Drums of Rage (Leatherworking)
			id == 230935 or -- Drums of the Mountain (Leatherworking)
			id == 256740    -- Drums of the Maelstrom (Leatherworking)
		) then
			return true
		end
	end
end

function Player:Equipped(itemID, slot)
	if slot then
		return GetInventoryItemID('player', slot) == itemID, slot
	end
	local i
	for i = 1, 19 do
		if GetInventoryItemID('player', i) == itemID then
			return true, i
		end
	end
	return false
end

function Player:InArenaOrBattleground()
	return self.instance == 'arena' or self.instance == 'pvp'
end

function Player:UpdateAbilities()
	self.fury_max = UnitPowerMax('player', 17)
	self.pain_max = UnitPowerMax('player', 18)

	local _, ability, spellId

	for _, ability in next, abilities.all do
		ability.known = false
		for _, spellId in next, ability.spellIds do
			ability.spellId, ability.name, _, ability.icon = spellId, GetSpellInfo(spellId)
			if IsPlayerSpell(spellId) or Azerite.traits[spellId] then
				ability.known = true
				break
			end
		end
		if C_LevelLink.IsSpellLocked(ability.spellId) then
			ability.known = false -- spell is locked, do not mark as known
		elseif ability.essence_id and Azerite.essences[ability.essence_id] then
			if ability.essence_major then
				ability.known = Azerite.essences[ability.essence_id].major
			else
				ability.known = true
			end
		end
	end

	ImmolationAura.damage.known = ImmolationAura.known
	ImmolationAuraV.damage.known = ImmolationAuraV.known
	SigilOfFlame.dot.known = SigilOfFlame.known
	if DemonBlades.known then
		DemonsBite.known = false
	end
	if Fracture.known then
		Shear.known = false
	end
	if Metamorphosis.known then
		Metamorphosis.stun.known = true
		Annihilation.known = ChaosStrike.known
		DeathSweep.known = BladeDance.known
	end

	abilities.bySpellId = {}
	abilities.velocity = {}
	abilities.autoAoe = {}
	abilities.trackAuras = {}
	for _, ability in next, abilities.all do
		if ability.known then
			abilities.bySpellId[ability.spellId] = ability
			if ability.spellId2 then
				abilities.bySpellId[ability.spellId2] = ability
			end
			if ability.velocity > 0 then
				abilities.velocity[#abilities.velocity + 1] = ability
			end
			if ability.auto_aoe then
				abilities.autoAoe[#abilities.autoAoe + 1] = ability
			end
			if ability.aura_targets then
				abilities.trackAuras[#abilities.trackAuras + 1] = ability
			end
		end
	end
end

-- End Player API

-- Start Target API

function Target:UpdateHealth()
	timer.health = 0
	self.health = UnitHealth('target')
	self.health_max = UnitHealthMax('target')
	table.remove(self.healthArray, 1)
	self.healthArray[25] = self.health
	self.timeToDieMax = self.health / Player.health_max * 15
	self.healthPercentage = self.health_max > 0 and (self.health / self.health_max * 100) or 100
	self.healthLostPerSec = (self.healthArray[1] - self.health) / 5
	self.timeToDie = self.healthLostPerSec > 0 and min(self.timeToDieMax, self.health / self.healthLostPerSec) or self.timeToDieMax
end

function Target:Update()
	UI:Disappear()
	if UI:ShouldHide() then
		return
	end
	local guid = UnitGUID('target')
	if not guid then
		self.guid = nil
		self.boss = false
		self.stunnable = true
		self.classification = 'normal'
		self.player = false
		self.level = UnitLevel('player')
		self.hostile = true
		local i
		for i = 1, 25 do
			self.healthArray[i] = 0
		end
		self:UpdateHealth()
		if Opt.always_on then
			UI:UpdateCombat()
			lasikPanel:Show()
			return true
		end
		if Opt.previous and Player.combat_start == 0 then
			lasikPreviousPanel:Hide()
		end
		return
	end
	if guid ~= self.guid then
		self.guid = guid
		local i
		for i = 1, 25 do
			self.healthArray[i] = UnitHealth('target')
		end
	end
	self.boss = false
	self.stunnable = true
	self.classification = UnitClassification('target')
	self.player = UnitIsPlayer('target')
	self.level = UnitLevel('target')
	self.hostile = UnitCanAttack('player', 'target') and not UnitIsDead('target')
	self:UpdateHealth()
	if not self.player and self.classification ~= 'minus' and self.classification ~= 'normal' then
		if self.level == -1 or (Player.instance == 'party' and self.level >= UnitLevel('player') + 2) then
			self.boss = true
			self.stunnable = false
		elseif Player.instance == 'raid' or (self.health_max > Player.health_max * 10) then
			self.stunnable = false
		end
	end
	if self.hostile or Opt.always_on then
		UI:UpdateCombat()
		lasikPanel:Show()
		return true
	end
end

-- End Target API

-- Start Ability Modifications

function ConcentratedFlame.dot:Remains()
	if ConcentratedFlame:Traveling() then
		return self:Duration()
	end
	return Ability.Remains(self)
end

function ChaosNova:FuryCost()
	if UnleashedPower.known then
		return 0
	end
	return Ability.FuryCost(self)
end

function BladeDance:FuryCost()
	local cost = Ability.FuryCost(self)
	if FirstBlood.known then
		cost = cost - 20
	end
	if RevolvingBlades.known then
		cost = cost - (3 * RevolvingBlades:Stack())
	end
	return max(0, cost)
end
DeathSweep.FuryCost = BladeDance.FuryCost

function Annihilation:Usable()
	if not Player.meta_active then
		return false
	end
	return Ability.Usable(self)
end
DeathSweep.Usable = Annihilation.Usable

function ChaosStrike:Usable()
	if Player.meta_active then
		return false
	end
	return Ability.Usable(self)
end
BladeDance.Usable = ChaosStrike.Usable

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

function SigilOfFlame:Placed()
	return (Player.time - self.last_used) < (self:Duration() + 0.5)
end
SigilOfChains.Placed = SigilOfFlame.Placed
SigilOfMisery.Placed = SigilOfFlame.Placed
SigilOfSilence.Placed = SigilOfFlame.Placed

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

local APL = {
	[SPEC.NONE] = {
		main = function() end
	},
	[SPEC.HAVOC] = {},
	[SPEC.VENGEANCE] = {},
}

APL[SPEC.HAVOC].main = function(self)
	Player.use_meta = Opt.cooldown and (Target.boss or (not Opt.boss_only and Target.timeToDie > Opt.meta_ttd))

	if Player:TimeInCombat() == 0 then
--[[
actions.precombat=flask
actions.precombat+=/augmentation
actions.precombat+=/food
# Snapshot raid buffed stats before combat begins and pre-potting is done.
actions.precombat+=/snapshot_stats
actions.precombat+=/potion
actions.precombat+=/metamorphosis,if=!azerite.chaotic_transformation.enabled
actions.precombat+=/use_item,name=azsharas_font_of_power
]]
		if Opt.pot and not Player:InArenaOrBattleground() then
			if GreaterFlaskOfEndlessFathoms:Usable() and GreaterFlaskOfEndlessFathoms.buff:Remains() < 300 then
				UseCooldown(GreaterFlaskOfTheCurrents)
			end
			if Target.boss and PotionOfUnbridledFury:Usable() then
				UseCooldown(PotionOfUnbridledFury)
			end
		end
		if Player.use_meta and not ChaoticTransformation.known and Metamorphosis:Usable() then
			UseCooldown(Metamorphosis)
		end
	end
--[[
actions=auto_attack
actions+=/variable,name=blade_dance,value=talent.first_blood.enabled|spell_targets.blade_dance1>=(3-talent.trail_of_ruin.enabled)
actions+=/variable,name=waiting_for_nemesis,value=!(!talent.nemesis.enabled|cooldown.nemesis.ready|cooldown.nemesis.remains>target.time_to_die|cooldown.nemesis.remains>60)
actions+=/variable,name=pooling_for_meta,value=!talent.demonic.enabled&cooldown.metamorphosis.remains<6&fury.deficit>30&(!variable.waiting_for_nemesis|cooldown.nemesis.remains<10)
actions+=/variable,name=pooling_for_blade_dance,value=variable.blade_dance&(fury<75-talent.first_blood.enabled*20)
actions+=/variable,name=pooling_for_eye_beam,value=talent.demonic.enabled&!talent.blind_fury.enabled&cooldown.eye_beam.remains<(gcd.max*2)&fury.deficit>20
actions+=/variable,name=waiting_for_dark_slash,value=talent.dark_slash.enabled&!variable.pooling_for_blade_dance&!variable.pooling_for_meta&cooldown.dark_slash.up
actions+=/variable,name=waiting_for_momentum,value=talent.momentum.enabled&!buff.momentum.up
actions+=/disrupt
actions+=/call_action_list,name=cooldown,if=gcd.remains=0
actions+=/pick_up_fragment,if=fury.deficit>=35&(!azerite.eyes_of_rage.enabled|cooldown.eye_beam.remains>1.4)
actions+=/call_action_list,name=dark_slash,if=talent.dark_slash.enabled&(variable.waiting_for_dark_slash|debuff.dark_slash.up)
actions+=/run_action_list,name=demonic,if=talent.demonic.enabled
actions+=/run_action_list,name=normal
]]
	Player.blade_dance = FirstBlood.known or Player.enemies >= (3 - (TrailOfRuin.known and 1 or 0))
	Player.waiting_for_nemesis = not (not Nemesis.known or Nemesis:Ready() or Nemesis:Cooldown() > Target.timeToDie or Nemesis:Cooldown() > 60)
	Player.pooling_for_meta = Player.use_meta and not Demonic.known and Metamorphosis:Ready(6) and Player:FuryDeficit() > 30 and (not Player.waiting_for_nemesis or Nemesis:Ready(10))
	Player.pooling_for_blade_dance = Player.blade_dance and Player:Fury() < (75 - (FirstBlood.known and 20 or 0))
	Player.pooling_for_eye_beam = Demonic.known and not BlindFury.known and EyeBeam:Ready(Player.gcd * 2) and Player:FuryDeficit() > 20
	Player.waiting_for_dark_slash = DarkSlash.known and not Player.pooling_for_blade_dance and not Player.pooling_for_meta and not DarkSlash:Ready()
	Player.waiting_for_momentum = Momentum.known and Momentum:Down()
	local apl
	apl = self:cooldown()
	if apl then return apl end
	-- Player.pick_up_fragment = Player:FuryDeficit() >= 35 and (not EyesOfRage.known or EyeBeam:Cooldown() > 1.4)
	if DarkSlash.known and (Player.waiting_for_dark_slash or DarkSlash:Up()) then
		apl = self:dark_slash()
		if apl then return apl end
	end
	if Demonic.known then
		return self:demonic()
	end
	return self:normal()
end

APL[SPEC.HAVOC].cooldown = function(self)
--[[
actions.cooldown=metamorphosis,if=!(talent.demonic.enabled|variable.pooling_for_meta|variable.waiting_for_nemesis)|target.time_to_die<25
actions.cooldown+=/metamorphosis,if=talent.demonic.enabled&(!azerite.chaotic_transformation.enabled|(cooldown.eye_beam.remains>20&(!variable.blade_dance|cooldown.blade_dance.remains>gcd.max)))
actions.cooldown+=/nemesis,target_if=min:target.time_to_die,if=raid_event.adds.exists&debuff.nemesis.down&(active_enemies>desired_targets|raid_event.adds.in>60)
actions.cooldown+=/nemesis,if=!raid_event.adds.exists
actions.cooldown+=/potion,if=buff.metamorphosis.remains>25|target.time_to_die<60
actions.cooldown+=/use_item,name=galecallers_boon,if=!talent.fel_barrage.enabled|cooldown.fel_barrage.ready
actions.cooldown+=/use_item,effect_name=cyclotronic_blast,if=buff.metamorphosis.up&buff.memory_of_lucid_dreams.down&(!variable.blade_dance|!cooldown.blade_dance.ready)
actions.cooldown+=/use_item,name=ashvanes_razor_coral,if=debuff.razor_coral_debuff.down|(debuff.conductive_ink_debuff.up|buff.metamorphosis.remains>20)&target.health.pct<31|target.time_to_die<20
actions.cooldown+=/use_item,name=azsharas_font_of_power,if=cooldown.metamorphosis.remains<10|cooldown.metamorphosis.remains>60
# Default fallback for usable items.
actions.cooldown+=/use_items,if=(azerite.furious_gaze.enabled&(cooldown.eye_beam.ready|buff.furious_gaze.remains>6))|(!azerite.furious_gaze.enabled&buff.metamorphosis.up)|target.time_to_die<25
actions.cooldown+=/call_action_list,name=essences
]]
	if Player.use_meta and Metamorphosis:Usable() then
		if (Target.boss or Player.enemies > 1 or Target.timeToDie > (Metamorphosis:Remains() + 6)) and (not ChaoticTransformation.known or not EyeBeam:Ready(6)) and (
			(Target.boss and Target.timeToDie < 25) or
			(not (Demonic.known or Player.pooling_for_meta or Player.waiting_for_nemesis)) or
			(Demonic.known and (not ChaoticTransformation.known or (not EyeBeam:Ready(20) and (not Player.blade_dance or BladeDance:Cooldown() > Player.gcd))))
		) then
			return UseCooldown(Metamorphosis)
		end
	end
	if Nemesis:Usable() then
		return UseCooldown(Nemesis)
	end
	if Opt.pot and Target.boss and PotionOfUnbridledFury:Usable() and (Player.meta_remains > 25 or Target.timeToDie < 60) then
		return UseCooldown(PotionOfUnbridledFury)
	end
	if Opt.trinket and ((FuriousGaze.known and (EyeBeam:Ready() or FuriousGaze:Remains() > 6)) or (not FuriousGaze.known and Player.meta_active) or (Target.boss and Target.timeToDie < 25)) then
		if Trinket1:Usable() then
			return UseCooldown(Trinket1)
		elseif Trinket2:Usable() then
			return UseCooldown(Trinket2)
		end
	end
	return self:essences()
end


APL[SPEC.HAVOC].dark_slash = function(self)
--[[
actions.dark_slash=dark_slash,if=fury>=80&(!variable.blade_dance|!cooldown.blade_dance.ready)
actions.dark_slash+=/annihilation,if=debuff.dark_slash.up
actions.dark_slash+=/chaos_strike,if=debuff.dark_slash.up
]]
	if DarkSlash:Usable() and Player:Fury() >= 80 and (not Player.blade_dance or not BladeDance:Ready()) then
		return DarkSlash
	end
	if Annihilation:Usable() and DarkSlash:Up() then
		return Annihilation
	end
	if ChaosStrike:Usable() and DarkSlash:Up() then
		return ChaosStrike
	end
end

APL[SPEC.HAVOC].demonic = function(self)
--[[
actions.demonic=death_sweep,if=variable.blade_dance
actions.demonic+=/eye_beam,if=raid_event.adds.up|raid_event.adds.in>25
actions.demonic+=/fel_barrage,if=((!cooldown.eye_beam.up|buff.metamorphosis.up)&raid_event.adds.in>30)|active_enemies>desired_targets
actions.demonic+=/blade_dance,if=variable.blade_dance&(!cooldown.metamorphosis.ready|azerite.chaotic_transformation.enabled)&(cooldown.eye_beam.remains>(5-azerite.revolving_blades.rank*3)|(raid_event.adds.in>cooldown&raid_event.adds.in<25))
actions.demonic+=/immolation_aura
actions.demonic+=/focused_azerite_beam,if=buff.furious_gaze.up
actions.demonic+=/annihilation,if=!variable.pooling_for_blade_dance
actions.demonic+=/felblade,if=fury.deficit>=40
actions.demonic+=/chaos_strike,if=!variable.pooling_for_blade_dance&!variable.pooling_for_eye_beam
actions.demonic+=/fel_rush,if=talent.demon_blades.enabled&!cooldown.eye_beam.ready&(charges=2|(raid_event.movement.in>10&raid_event.adds.in>10))
actions.demonic+=/demons_bite
actions.demonic+=/throw_glaive,if=buff.out_of_range.up
actions.demonic+=/fel_rush,if=movement.distance>15|buff.out_of_range.up
actions.demonic+=/vengeful_retreat,if=movement.distance>15
actions.demonic+=/throw_glaive,if=talent.demon_blades.enabled
]]
	if DeathSweep:Usable() and Player.blade_dance then
		return DeathSweep
	end
	if EyeBeam:Usable() then
		return EyeBeam
	end
	if FelBarrage:Usable() and (EyeBeam:Ready() or Player.meta_active) then
		return FelBarrage
	end
	if BladeDance:Usable() and Player.blade_dance and (not Player.use_meta or not Metamorphosis:Ready() or ChaoticTransformation.known) and EyeBeam:Cooldown() > (5 - RevolvingBlades:AzeriteRank() * 3) then
		return BladeDance
	end
	if ImmolationAura:Usable() and (Player.enemies > 1 or Target.timeToDie > 4) then
		return ImmolationAura
	end
	if FuriousGaze.known and FocusedAzeriteBeam:Usable() and FuriousGaze:Up() then
		UseCooldown(FocusedAzeriteBeam, true)
	end
	if Annihilation:Usable() and not Player.pooling_for_blade_dance then
		return Annihilation
	end
	if Felblade:Usable() and Player:FuryDeficit() >= 40 then
		return Felblade
	end
	if ChaosStrike:Usable() and not Player.pooling_for_blade_dance and not Player.pooling_for_eye_beam then
		return ChaosStrike
	end
	if FelRush:Usable() and DemonBlades.known and not EyeBeam:Ready() then
		UseExtra(FelRush)
	end
	if DemonsBite:Usable() then
		return DemonsBite
	end
	if DemonBlades.known then
		return ThrowGlaive
	end
end

APL[SPEC.HAVOC].essences = function(self)
--[[
actions.essences=concentrated_flame,if=(!dot.concentrated_flame_burn.ticking&!action.concentrated_flame.in_flight|full_recharge_time<gcd.max)
actions.essences+=/blood_of_the_enemy,if=buff.metamorphosis.up|target.time_to_die<=10
actions.essences+=/guardian_of_azeroth,if=(buff.metamorphosis.up&cooldown.metamorphosis.ready)|buff.metamorphosis.remains>25|target.time_to_die<=30
actions.essences+=/focused_azerite_beam,if=!azerite.furious_gaze.enabled&(spell_targets.blade_dance1>=2|raid_event.adds.in>60)
actions.essences+=/purifying_blast,if=spell_targets.blade_dance1>=2|raid_event.adds.in>60
actions.essences+=/the_unbound_force,if=buff.reckless_force.up|buff.reckless_force_counter.stack<10
actions.essences+=/ripple_in_space
actions.essences+=/worldvein_resonance,if=buff.metamorphosis.up
actions.essences+=/memory_of_lucid_dreams,if=fury<40&buff.metamorphosis.up
actions.essences+=/reaping_flames,if=target.health.pct>80|target.health.pct<=20|target.time_to_pct_20>30
]]
	if ConcentratedFlame:Usable() and (ConcentratedFlame.dot:Down() or ConcentratedFlame:Charges() > 1.8) then
		return ConcentratedFlame
	end
	if BloodOfTheEnemy:Usable() and (Player.meta_active or Target.timeToDie <= 10) then
		return UseCooldown(BloodOfTheEnemy)
	end
	if GuardianOfAzeroth:Usable() and ((Player.meta_active and Metamorphosis:Ready()) or Player.meta_remains > 25 or Target.timeToDie <= 30) then
		return UseCooldown(GuardianOfAzeroth)
	end
	if not FuriousGaze.known and FocusedAzeriteBeam:Usable() then
		return UseCooldown(FocusedAzeriteBeam, true)
	end
	if PurifyingBlast:Usable() then
		return UseCooldown(PurifyingBlast)
	end
	if TheUnboundForce:Usable() and (RecklessForce:Up() or RecklessForce.counter:Stack() < 10) then
		return UseCooldown(TheUnboundForce)
	end
	if RippleInSpace:Usable() then
		return UseCooldown(RippleInSpace)
	end
	if WorldveinResonance:Usable() and Player.meta_active then
		return UseCooldown(WorldveinResonance)
	end
	if MemoryOfLucidDreams:Usable() and Player:Fury() < 40 and Player.meta_active then
		return UseCooldown(MemoryOfLucidDreams)
	end
	if ReapingFlames:Usable() then
		return UseCooldown(ReapingFlames)
	end
end

APL[SPEC.HAVOC].normal = function(self)
--[[
actions.normal=vengeful_retreat,if=talent.momentum.enabled&buff.prepared.down&time>1
actions.normal+=/fel_rush,if=(variable.waiting_for_momentum|talent.fel_mastery.enabled)&(charges=2|(raid_event.movement.in>10&raid_event.adds.in>10))
actions.normal+=/fel_barrage,if=!variable.waiting_for_momentum&(active_enemies>desired_targets|raid_event.adds.in>30)
actions.normal+=/death_sweep,if=variable.blade_dance
actions.normal+=/immolation_aura
actions.normal+=/focused_azerite_beam,if=buff.furious_gaze.up
actions.normal+=/eye_beam,if=active_enemies>1&(!raid_event.adds.exists|raid_event.adds.up)&!variable.waiting_for_momentum
actions.normal+=/blade_dance,if=variable.blade_dance
actions.normal+=/felblade,if=fury.deficit>=40
actions.normal+=/eye_beam,if=!talent.blind_fury.enabled&!variable.waiting_for_dark_slash&raid_event.adds.in>cooldown
actions.normal+=/annihilation,if=(talent.demon_blades.enabled|!variable.waiting_for_momentum|fury.deficit<30|buff.metamorphosis.remains<5)&!variable.pooling_for_blade_dance&!variable.waiting_for_dark_slash
actions.normal+=/chaos_strike,if=(talent.demon_blades.enabled|!variable.waiting_for_momentum|fury.deficit<30)&!variable.pooling_for_meta&!variable.pooling_for_blade_dance&!variable.waiting_for_dark_slash
actions.normal+=/eye_beam,if=talent.blind_fury.enabled&raid_event.adds.in>cooldown
actions.normal+=/demons_bite
actions.normal+=/fel_rush,if=!talent.momentum.enabled&raid_event.movement.in>charges*10&talent.demon_blades.enabled
actions.normal+=/felblade,if=movement.distance>15|buff.out_of_range.up
actions.normal+=/fel_rush,if=movement.distance>15|(buff.out_of_range.up&!talent.momentum.enabled)
actions.normal+=/vengeful_retreat,if=movement.distance>15
actions.normal+=/throw_glaive,if=talent.demon_blades.enabled
]]
	if VengefulRetreat:Usable() and Momentum.known and Prepared:Down() and Player:TimeInCombat() > 1 then
		UseExtra(VengefulRetreat)
	end
	if FelRush:Usable() and (Player.waiting_for_momentum or FelMastery.known) then
		UseExtra(FelRush)
	end
	if FelBarrage:Usable() and not Player.waiting_for_momentum then
		return FelBarrage
	end
	if DeathSweep:Usable() and Player.blade_dance then
		return DeathSweep
	end
	if ImmolationAura:Usable() and (Player.enemies > 1 or Target.timeToDie > 4) then
		return ImmolationAura
	end
	if FuriousGaze.known and FocusedAzeriteBeam:Usable() and FuriousGaze:Up() then
		UseCooldown(FocusedAzeriteBeam, true)
	end
	if EyeBeam:Usable() and Player.enemies > 1 and not Player.waiting_for_momentum then
		return EyeBeam
	end
	if BladeDance:Usable() and Player.blade_dance then
		return BladeDance
	end
	if Felblade:Usable() and Player:FuryDeficit() >= 40 then
		return Felblade
	end
	if EyeBeam:Usable() and not BlindFury.known and not Player.waiting_for_dark_slash then
		return EyeBeam
	end
	if Annihilation:Usable() and (DemonBlades.known or not Player.waiting_for_momentum or Player:FuryDeficit() < 30 or Player.meta_remains < 5) and not Player.pooling_for_blade_dance and not Player.waiting_for_dark_slash then
		return Annihilation
	end
	if ChaosStrike:Usable() and (DemonBlades.known or not Player.waiting_for_momentum or Player:FuryDeficit() < 30) and not Player.pooling_for_blade_dance and not Player.waiting_for_dark_slash then
		return ChaosStrike
	end
	if EyeBeam:Usable() and BlindFury.known then
		return EyeBeam
	end
	if DemonsBite:Usable() then
		return DemonsBite
	end
	if DemonBlades.known then
		return ThrowGlaive
	end
end

APL[SPEC.VENGEANCE].main = function(self)
	if Player:TimeInCombat() == 0 then
--[[
actions.precombat=flask
actions.precombat+=/augmentation
actions.precombat+=/food
# Snapshot raid buffed stats before combat begins and pre-potting is done.
actions.precombat+=/snapshot_stats
actions.precombat+=/potion
actions.precombat+=/use_item,name=azsharas_font_of_power
]]
		if Opt.pot and not Player:InArenaOrBattleground() then
			if GreaterFlaskOfEndlessFathoms:Usable() and GreaterFlaskOfEndlessFathoms.buff:Remains() < 300 then
				UseCooldown(GreaterFlaskOfTheCurrents)
			end
			if Target.boss and PotionOfUnbridledFury:Usable() then
				UseCooldown(PotionOfUnbridledFury)
			end
		end
	end
--[[
actions=auto_attack
actions+=/consume_magic
actions+=/call_action_list,name=brand,if=talent.charred_flesh.enabled
actions+=/call_action_list,name=defensives
actions+=/call_action_list,name=cooldowns
actions+=/call_action_list,name=normal
]]
	local apl
	if CharredFlesh.known then
		apl = self:brand()
		if apl then return apl end
	end
	apl = self:defensives()
	if apl then return apl end
	apl = self:cooldowns()
	if apl then return apl end
	return self:normal()
end

APL[SPEC.VENGEANCE].brand = function(self)
--[[
actions.brand=sigil_of_flame,if=cooldown.fiery_brand.remains<2
actions.brand+=/infernal_strike,if=cooldown.fiery_brand.remains=0
actions.brand+=/fiery_brand
actions.brand+=/immolation_aura,if=dot.fiery_brand.ticking
actions.brand+=/fel_devastation,if=dot.fiery_brand.ticking
actions.brand+=/infernal_strike,if=dot.fiery_brand.ticking
actions.brand+=/sigil_of_flame,if=dot.fiery_brand.ticking
]]
	if SigilOfFlame:Usable() and not SigilOfFlame:Placed() and FieryBrand:Ready(2) then
		return SigilOfFlame
	end
	if InfernalStrike:Usable() and FieryBrand:Ready() then
		UseCooldown(InfernalStrike)
	end
	if FieryBrand:Usable() then
		UseCooldown(FieryBrand)
	end
	if FieryBrand:Ticking() then
		if ImmolationAuraV:Usable() then
			return ImmolationAuraV
		end
		if FelDevastation:Usable() then
			UseCooldown(FelDevastation)
		end
		if InfernalStrike:Usable() then
			UseCooldown(InfernalStrike)
		end
		if SigilOfFlame:Usable() and not SigilOfFlame:Placed() and SigilOfFlame.dot:Remains() < (SigilOfFlame:Duration() + 1) then
			return SigilOfFlame
		end
	end
end

APL[SPEC.VENGEANCE].cooldowns = function(self)
--[[
actions.cooldowns=potion
actions.cooldowns+=/concentrated_flame,if=(!dot.concentrated_flame_burn.ticking&!action.concentrated_flame.in_flight|full_recharge_time<gcd.max)
actions.cooldowns+=/worldvein_resonance,if=buff.lifeblood.stack<3
actions.cooldowns+=/memory_of_lucid_dreams
# Default fallback for usable essences.
actions.cooldowns+=/heart_essence
actions.cooldowns+=/use_item,effect_name=cyclotronic_blast,if=buff.memory_of_lucid_dreams.down
actions.cooldowns+=/use_item,name=ashvanes_razor_coral,if=debuff.razor_coral_debuff.down|debuff.conductive_ink_debuff.up&target.health.pct<31|target.time_to_die<20
# Default fallback for usable items.
actions.cooldowns+=/use_items
]]
	if Opt.pot and Target.boss and PotionOfUnbridledFury:Usable() then
		return UseCooldown(PotionOfUnbridledFury)
	end
	if ConcentratedFlame:Usable() and (ConcentratedFlame.dot:Down() or ConcentratedFlame:Charges() > 1.8) then
		return ConcentratedFlame
	end
	if WorldveinResonance:Usable() and Lifeblood:Stack() < 3 then
		return UseCooldown(WorldveinResonance)
	end
	if MemoryOfLucidDreams:Usable() then
		return UseCooldown(MemoryOfLucidDreams)
	end
	if BloodOfTheEnemy:Usable() then
		return UseCooldown(BloodOfTheEnemy)
	end
	if GuardianOfAzeroth:Usable() then
		return UseCooldown(GuardianOfAzeroth)
	end
	if FocusedAzeriteBeam:Usable() then
		return UseCooldown(FocusedAzeriteBeam, true)
	end
	if PurifyingBlast:Usable() then
		return UseCooldown(PurifyingBlast)
	end
	if TheUnboundForce:Usable() and (RecklessForce:Up() or RecklessForce.counter:Stack() < 10) then
		return UseCooldown(TheUnboundForce)
	end
	if RippleInSpace:Usable() then
		return UseCooldown(RippleInSpace)
	end
	if ReapingFlames:Usable() then
		return UseCooldown(ReapingFlames)
	end
	if Opt.trinket then
		if Trinket1:Usable() then
			return UseCooldown(Trinket1)
		elseif Trinket2:Usable() then
			return UseCooldown(Trinket2)
		end
	end
end

APL[SPEC.VENGEANCE].defensives = function(self)
--[[
actions.defensives=demon_spikes
actions.defensives+=/metamorphosis
actions.defensives+=/fiery_brand
]]
	if DemonSpikes:Usable() then
		UseExtra(DemonSpikes)
	end
	if MetamorphosisV:Usable() then
		UseExtra(MetamorphosisV)
	end
	if FieryBrand:Usable() then
		UseCooldown(FieryBrand)
	end
end

APL[SPEC.VENGEANCE].normal = function(self)
--[[
actions.normal=infernal_strike,if=(!talent.flame_crash.enabled|(dot.sigil_of_flame.remains<3&!action.infernal_strike.sigil_placed))
actions.normal+=/spirit_bomb,if=((buff.metamorphosis.up&soul_fragments>=3)|soul_fragments>=4)
actions.normal+=/soul_cleave,if=(!talent.spirit_bomb.enabled&((buff.metamorphosis.up&soul_fragments>=3)|soul_fragments>=4))
actions.normal+=/soul_cleave,if=talent.spirit_bomb.enabled&soul_fragments=0
actions.normal+=/immolation_aura,if=pain<=90
actions.normal+=/felblade,if=pain<=70
actions.normal+=/fracture,if=soul_fragments<=3
actions.normal+=/fel_devastation
actions.normal+=/sigil_of_flame
actions.normal+=/shear
actions.normal+=/throw_glaive
]]
	if InfernalStrike:Usable() and (not FlameCrash.known or (SigilOfFlame.dot:Remains() < (SigilOfFlame:Duration() + 1) and not SigilOfFlame:Placed())) then
		UseCooldown(InfernalStrike)
	end
	if SpiritBomb:Usable() and Player.soul_fragments >= (Player.meta_active and 3 or 4) then
		return SpiritBomb
	end
	if SoulCleave:Usable() and (
		(not SpiritBomb.known and Player.soul_fragments >= (Player.meta_active and 3 or 4)) or
		(SpiritBomb.known and Player.soul_fragments == 0)
	) then
		return SoulCleave
	end
	if ImmolationAuraV:Usable() and Player:Pain() <= 90 then
		return ImmolationAuraV
	end
	if Felblade:Usable() and Player:Pain() <= 70 then
		return Felblade
	end
	if Fracture:Usable() and Player.soul_fragments <= 3 then
		return Fracture
	end
	if FelDevastation:Usable() then
		UseCooldown(FelDevastation)
	end
	if SigilOfFlame:Usable() and not SigilOfFlame:Placed() and SigilOfFlame.dot:Remains() < (SigilOfFlame:Duration() + 1) then
		return SigilOfFlame
	end
	if Shear:Usable() then
		return Shear
	end
	if ThrowGlaiveV:Usable() then
		return ThrowGlaiveV
	end
end

APL.Interrupt = function(self)
	if Disrupt:Usable() then
		return Disrupt
	end
	if EyesOfRage.known and ChaosNova:Usable() and Player.enemies >= (UnleashedPower.known and 3 or 5) and not EyeBeam:Ready(4) then
		return ChaosNova
	end
	if FelEruption:Usable() then
		return FelEruption
	end
end

-- End Action Priority Lists

-- Start UI API

function UI.DenyOverlayGlow(actionButton)
	if not Opt.glow.blizzard then
		actionButton.overlay:Hide()
	end
end
hooksecurefunc('ActionButton_ShowOverlayGlow', UI.DenyOverlayGlow) -- Disable Blizzard's built-in action button glowing

function UI:UpdateGlowColorAndScale()
	local w, h, glow, i
	local r = Opt.glow.color.r
	local g = Opt.glow.color.g
	local b = Opt.glow.color.b
	for i = 1, #self.glows do
		glow = self.glows[i]
		w, h = glow.button:GetSize()
		glow:SetSize(w * 1.4, h * 1.4)
		glow:SetPoint('TOPLEFT', glow.button, 'TOPLEFT', -w * 0.2 * Opt.scale.glow, h * 0.2 * Opt.scale.glow)
		glow:SetPoint('BOTTOMRIGHT', glow.button, 'BOTTOMRIGHT', w * 0.2 * Opt.scale.glow, -h * 0.2 * Opt.scale.glow)
		glow.spark:SetVertexColor(r, g, b)
		glow.innerGlow:SetVertexColor(r, g, b)
		glow.innerGlowOver:SetVertexColor(r, g, b)
		glow.outerGlow:SetVertexColor(r, g, b)
		glow.outerGlowOver:SetVertexColor(r, g, b)
		glow.ants:SetVertexColor(r, g, b)
	end
end

function UI:CreateOverlayGlows()
	local b, i
	local GenerateGlow = function(button)
		if button then
			local glow = CreateFrame('Frame', nil, button, 'ActionBarButtonSpellActivationAlert')
			glow:Hide()
			glow.button = button
			self.glows[#self.glows + 1] = glow
		end
	end
	for i = 1, 12 do
		GenerateGlow(_G['ActionButton' .. i])
		GenerateGlow(_G['MultiBarLeftButton' .. i])
		GenerateGlow(_G['MultiBarRightButton' .. i])
		GenerateGlow(_G['MultiBarBottomLeftButton' .. i])
		GenerateGlow(_G['MultiBarBottomRightButton' .. i])
	end
	for i = 1, 10 do
		GenerateGlow(_G['PetActionButton' .. i])
	end
	if Bartender4 then
		for i = 1, 120 do
			GenerateGlow(_G['BT4Button' .. i])
		end
	end
	if Dominos then
		for i = 1, 60 do
			GenerateGlow(_G['DominosActionButton' .. i])
		end
	end
	if ElvUI then
		for b = 1, 6 do
			for i = 1, 12 do
				GenerateGlow(_G['ElvUI_Bar' .. b .. 'Button' .. i])
			end
		end
	end
	if LUI then
		for b = 1, 6 do
			for i = 1, 12 do
				GenerateGlow(_G['LUIBarBottom' .. b .. 'Button' .. i])
				GenerateGlow(_G['LUIBarLeft' .. b .. 'Button' .. i])
				GenerateGlow(_G['LUIBarRight' .. b .. 'Button' .. i])
			end
		end
	end
	UI:UpdateGlowColorAndScale()
end

function UI:UpdateGlows()
	local glow, icon, i
	for i = 1, #self.glows do
		glow = self.glows[i]
		icon = glow.button.icon:GetTexture()
		if icon and glow.button.icon:IsVisible() and (
			(Opt.glow.main and Player.main and icon == Player.main.icon) or
			(Opt.glow.cooldown and Player.cd and icon == Player.cd.icon) or
			(Opt.glow.interrupt and Player.interrupt and icon == Player.interrupt.icon) or
			(Opt.glow.extra and Player.extra and icon == Player.extra.icon)
			) then
			if not glow:IsVisible() then
				glow.animIn:Play()
			end
		elseif glow:IsVisible() then
			glow.animIn:Stop()
			glow:Hide()
		end
	end
end

function UI:UpdateDraggable()
	lasikPanel:EnableMouse(Opt.aoe or not Opt.locked)
	lasikPanel.button:SetShown(Opt.aoe)
	if Opt.locked then
		lasikPanel:SetScript('OnDragStart', nil)
		lasikPanel:SetScript('OnDragStop', nil)
		lasikPanel:RegisterForDrag(nil)
		lasikPreviousPanel:EnableMouse(false)
		lasikCooldownPanel:EnableMouse(false)
		lasikInterruptPanel:EnableMouse(false)
		lasikExtraPanel:EnableMouse(false)
	else
		if not Opt.aoe then
			lasikPanel:SetScript('OnDragStart', lasikPanel.StartMoving)
			lasikPanel:SetScript('OnDragStop', lasikPanel.StopMovingOrSizing)
			lasikPanel:RegisterForDrag('LeftButton')
		end
		lasikPreviousPanel:EnableMouse(true)
		lasikCooldownPanel:EnableMouse(true)
		lasikInterruptPanel:EnableMouse(true)
		lasikExtraPanel:EnableMouse(true)
	end
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
	lasikPreviousPanel:SetSize(64 * Opt.scale.previous, 64 * Opt.scale.previous)
	lasikCooldownPanel:SetSize(64 * Opt.scale.cooldown, 64 * Opt.scale.cooldown)
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
			['below'] = { 'TOP', 'BOTTOM', 0, -9 }
		},
		[SPEC.VENGEANCE] = {
			['above'] = { 'BOTTOM', 'TOP', 0, 36 },
			['below'] = { 'TOP', 'BOTTOM', 0, -9 }
		},
	},
	kui = { -- Kui Nameplates
		[SPEC.HAVOC] = {
			['above'] = { 'BOTTOM', 'TOP', 0, 28 },
			['below'] = { 'TOP', 'BOTTOM', 0, 4 }
		},
		[SPEC.VENGEANCE] = {
			['above'] = { 'BOTTOM', 'TOP', 0, 28 },
			['below'] = { 'TOP', 'BOTTOM', 0, 4 }
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
		self.anchor.frame = NamePlateDriverFrame:GetClassNameplateManaBar()
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
	UI:UpdateGlows()
end

function UI:UpdateDisplay()
	timer.display = 0
	local dim, text_tr, text_tl
	if Opt.dimmer then
		dim = not ((not Player.main) or
		           (Player.main.spellId and IsUsableSpell(Player.main.spellId)) or
		           (Player.main.itemId and IsUsableItem(Player.main.itemId)))
	end
	if Player.meta_active then
		text_tr = format('%.1fs', Player.meta_remains)
	end
	if Player.soul_fragments > 0 then
		text_tl = Player.soul_fragments
	end
	lasikPanel.dimmer:SetShown(dim)
	lasikPanel.text.tr:SetText(text_tr)
	lasikPanel.text.tl:SetText(text_tl)
	--lasikPanel.text.bl:SetText(format('%.1fs', Target.timeToDie))
end

function UI:UpdateCombat()
	timer.combat = 0
	local _, start, duration, remains, spellId
	Player.ctime = GetTime()
	Player.time = Player.ctime - Player.time_diff
	Player.main =  nil
	Player.cd = nil
	Player.interrupt = nil
	Player.extra = nil
	start, duration = GetSpellCooldown(61304)
	Player.gcd_remains = start > 0 and duration - (Player.ctime - start) or 0
	_, _, _, _, remains, _, _, _, spellId = UnitCastingInfo('player')
	Player.ability_casting = abilities.bySpellId[spellId]
	Player.execute_remains = max(remains and (remains / 1000 - Player.ctime) or 0, Player.gcd_remains)
	Player.haste_factor = 1 / (1 + UnitSpellHaste('player') / 100)
	Player.gcd = 1.5 * Player.haste_factor
	Player.fury = UnitPower('player', 17)
	Player.pain = UnitPower('player', 18)
	Player.health = UnitHealth('player')
	Player.health_max = UnitHealthMax('player')
	if Player.spec == SPEC.HAVOC then
		Player.meta_remains = Metamorphosis:Remains()
		Player.soul_fragments = 0
	elseif Player.spec == SPEC.VENGEANCE then
		Player.meta_remains = MetamorphosisV:Remains()
		Player.soul_fragments = SoulFragments:Stack()
	end
	Player.meta_active = Player.meta_remains > 0

	trackAuras:Purge()
	if Opt.auto_aoe then
		local ability
		for _, ability in next, abilities.autoAoe do
			ability:UpdateTargetsHit()
		end
		autoAoe:Purge()
	end

	Player.main = APL[Player.spec]:main()
	if Player.main then
		lasikPanel.icon:SetTexture(Player.main.icon)
	end
	if Player.cd then
		lasikCooldownPanel.icon:SetTexture(Player.cd.icon)
	end
	if Player.extra then
		lasikExtraPanel.icon:SetTexture(Player.extra.icon)
	end
	if Opt.interrupt then
		local ends, notInterruptible
		_, _, _, start, ends, _, _, notInterruptible = UnitCastingInfo('target')
		if not start then
			_, _, _, start, ends, _, notInterruptible = UnitChannelInfo('target')
		end
		if start and not notInterruptible then
			Player.interrupt = APL.Interrupt()
			lasikInterruptPanel.cast:SetCooldown(start / 1000, (ends - start) / 1000)
		end
		if Player.interrupt then
			lasikInterruptPanel.icon:SetTexture(Player.interrupt.icon)
		end
		lasikInterruptPanel.icon:SetShown(Player.interrupt)
		lasikInterruptPanel.border:SetShown(Player.interrupt)
		lasikInterruptPanel:SetShown(start and not notInterruptible)
	end
	lasikPanel.icon:SetShown(Player.main)
	lasikPanel.border:SetShown(Player.main)
	lasikCooldownPanel:SetShown(Player.cd)
	lasikExtraPanel:SetShown(Player.extra)

	self:UpdateDisplay()
	self:UpdateGlows()
end

function UI:UpdateCombatWithin(seconds)
	if Opt.frequency - timer.combat > seconds then
		timer.combat = max(seconds, Opt.frequency - seconds)
	end
end

-- End UI API

-- Start Event Handling

function events:ADDON_LOADED(name)
	if name == 'Lasik' then
		Opt = Lasik
		if not Opt.frequency then
			print('It looks like this is your first time running ' .. name .. ', why don\'t you take some time to familiarize yourself with the commands?')
			print('Type |cFFFFD000' .. SLASH_Lasik1 .. '|r for a list of commands.')
		end
		if UnitLevel('player') < 110 then
			print('[|cFFFFD000Warning|r] ' .. name .. ' is not designed for players under level 110, and almost certainly will not operate properly!')
		end
		InitOpts()
		Azerite:Init()
		UI:UpdateDraggable()
		UI:UpdateAlpha()
		UI:UpdateScale()
		UI:SnapAllPanels()
	end
end

local function CombatEvent(timeStamp, eventType, srcGUID, dstGUID, spellId, spellName, missType)
	Player.time = timeStamp
	Player.ctime = GetTime()
	Player.time_diff = Player.ctime - Player.time

	if eventType == 'UNIT_DIED' or eventType == 'UNIT_DESTROYED' or eventType == 'UNIT_DISSIPATES' or eventType == 'SPELL_INSTAKILL' or eventType == 'PARTY_KILL' then
		trackAuras:Remove(dstGUID)
		if Opt.auto_aoe then
			autoAoe:Remove(dstGUID)
		end
	end
	if eventType == 'SWING_DAMAGE' or eventType == 'SWING_MISSED' then
		if dstGUID == Player.guid then
			Player.last_swing_taken = Player.time
		end
		if Opt.auto_aoe then
			if dstGUID == Player.guid then
				autoAoe:Add(srcGUID, true)
			elseif srcGUID == Player.guid and not (missType == 'EVADE' or missType == 'IMMUNE') then
				autoAoe:Add(dstGUID, true)
			end
		end
	end

	if srcGUID ~= Player.guid then
		return
	end

	local ability = spellId and abilities.bySpellId[spellId]
	if not ability then
--[[
		if spellId and type(spellName) == 'string' then
			print(format('EVENT %s TRACK CHECK FOR UNKNOWN %s ID %d', eventType, spellName, spellId))
		end
]]
		return
	end

	if not (
	   eventType == 'SPELL_CAST_START' or
	   eventType == 'SPELL_CAST_SUCCESS' or
	   eventType == 'SPELL_CAST_FAILED' or
	   eventType == 'SPELL_AURA_REMOVED' or
	   eventType == 'SPELL_DAMAGE' or
	   eventType == 'SPELL_ABSORBED' or
	   eventType == 'SPELL_PERIODIC_DAMAGE' or
	   eventType == 'SPELL_MISSED' or
	   eventType == 'SPELL_AURA_APPLIED' or
	   eventType == 'SPELL_AURA_REFRESH' or
	   eventType == 'SPELL_AURA_REMOVED')
	then
		return
	end

	UI:UpdateCombatWithin(0.05)
	if eventType == 'SPELL_CAST_SUCCESS' then
		if srcGUID == Player.guid or ability.player_triggered then
			Player.last_ability = ability
			ability.last_used = Player.time
			if ability.triggers_gcd then
				Player.previous_gcd[10] = nil
				table.insert(Player.previous_gcd, 1, ability)
			end
			if ability.travel_start then
				ability.travel_start[dstGUID] = Player.time
			end
			if Opt.previous and lasikPanel:IsVisible() then
				lasikPreviousPanel.ability = ability
				lasikPreviousPanel.border:SetTexture('Interface\\AddOns\\Lasik\\border.blp')
				lasikPreviousPanel.icon:SetTexture(ability.icon)
				lasikPreviousPanel:Show()
			end
			if ability == InfernalStrike and FlameCrash.known then
				SigilOfFlame.last_used = Player.time + 1
			end
		end
		return
	end

	if dstGUID == Player.guid then
		return -- ignore buffs beyond here
	end
	if ability.aura_targets then
		if eventType == 'SPELL_AURA_APPLIED' then
			ability:ApplyAura(dstGUID)
		elseif eventType == 'SPELL_AURA_REFRESH' then
			ability:RefreshAura(dstGUID)
		elseif eventType == 'SPELL_AURA_REMOVED' then
			ability:RemoveAura(dstGUID)
		end
	end
	if Opt.auto_aoe then
		if eventType == 'SPELL_MISSED' and (missType == 'EVADE' or missType == 'IMMUNE') then
			autoAoe:Remove(dstGUID)
		elseif ability.auto_aoe and (eventType == ability.auto_aoe.trigger or ability.auto_aoe.trigger == 'SPELL_AURA_APPLIED' and eventType == 'SPELL_AURA_REFRESH') then
			ability:RecordTargetHit(dstGUID)
		end
	end
	if eventType == 'SPELL_ABSORBED' or eventType == 'SPELL_MISSED' or eventType == 'SPELL_DAMAGE' or eventType == 'SPELL_AURA_APPLIED' or eventType == 'SPELL_AURA_REFRESH' then
		if ability.travel_start and ability.travel_start[dstGUID] then
			ability.travel_start[dstGUID] = nil
		end
		if Opt.previous and Opt.miss_effect and eventType == 'SPELL_MISSED' and lasikPanel:IsVisible() and ability == lasikPreviousPanel.ability then
			lasikPreviousPanel.border:SetTexture('Interface\\AddOns\\Lasik\\misseffect.blp')
		end
		if ability == InfernalStrike and FlameCrash.known then
			SigilOfFlame.last_used = Player.time
		end
	end
end

function events:UNIT_SPELLCAST_SUCCEEDED(srcName, castId, spellId)
	-- workaround for Infernal Strike not triggering a combat event
	if srcName == 'player' and spellId == InfernalStrike.spellId then
		CombatEvent(GetTime() - Player.time_diff, 'SPELL_CAST_SUCCESS', Player.guid, nil, InfernalStrike.spellId, InfernalStrike.spellName)
	end
end

function events:COMBAT_LOG_EVENT_UNFILTERED()
	local timeStamp, eventType, _, srcGUID, _, _, _, dstGUID, _, _, _, spellId, spellName, _, missType = CombatLogGetCurrentEventInfo()
	CombatEvent(timeStamp, eventType, srcGUID, dstGUID, spellId, spellName, missType)
end

function events:PLAYER_TARGET_CHANGED()
	Target:Update()
end

function events:UNIT_FACTION(unitID)
	if unitID == 'target' then
		Target:Update()
	end
end

function events:UNIT_FLAGS(unitID)
	if unitID == 'target' then
		Target:Update()
	end
end

function events:PLAYER_REGEN_DISABLED()
	Player.combat_start = GetTime() - Player.time_diff
end

function events:PLAYER_REGEN_ENABLED()
	Player.combat_start = 0
	Player.last_swing_taken = 0
	Target.estimated_range = 30
	Player.previous_gcd = {}
	if Player.last_ability then
		Player.last_ability = nil
		lasikPreviousPanel:Hide()
	end
	local _, ability, guid
	for _, ability in next, abilities.velocity do
		for guid in next, ability.travel_start do
			ability.travel_start[guid] = nil
		end
	end
	if Opt.auto_aoe then
		for _, ability in next, abilities.autoAoe do
			ability.auto_aoe.start_time = nil
			for guid in next, ability.auto_aoe.targets do
				ability.auto_aoe.targets[guid] = nil
			end
		end
		autoAoe:Clear()
		autoAoe:Update()
	end
end

function events:PLAYER_EQUIPMENT_CHANGED()
	local _, i, equipType, hasCooldown
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
	for i = 1, #inventoryItems do
		inventoryItems[i].name, _, _, _, _, _, _, _, equipType, inventoryItems[i].icon = GetItemInfo(inventoryItems[i].itemId or 0)
		inventoryItems[i].can_use = inventoryItems[i].name and true or false
		if equipType and equipType ~= '' then
			hasCooldown = 0
			_, inventoryItems[i].equip_slot = Player:Equipped(inventoryItems[i].itemId)
			if inventoryItems[i].equip_slot then
				_, _, hasCooldown = GetInventoryItemCooldown('player', inventoryItems[i].equip_slot)
			end
			inventoryItems[i].can_use = hasCooldown == 1
		end
		if Player.item_use_blacklist[inventoryItems[i].itemId] then
			inventoryItems[i].can_use = false
		end
	end
	Azerite:Update()
	Player:UpdateAbilities()
end

function events:PLAYER_SPECIALIZATION_CHANGED(unitName)
	if unitName ~= 'player' then
		return
	end
	Player.spec = GetSpecialization() or 0
	lasikPreviousPanel.ability = nil
	Player:SetTargetMode(1)
	Target:Update()
	events:PLAYER_EQUIPMENT_CHANGED()
	events:PLAYER_REGEN_ENABLED()
end

function events:SPELL_UPDATE_COOLDOWN()
	if Opt.spell_swipe then
		local _, start, duration, castStart, castEnd
		_, _, _, castStart, castEnd = UnitCastingInfo('player')
		if castStart then
			start = castStart / 1000
			duration = (castEnd - castStart) / 1000
		else
			start, duration = GetSpellCooldown(61304)
		end
		lasikPanel.swipe:SetCooldown(start, duration)
	end
end

function events:UNIT_POWER_UPDATE(srcName, powerType)
	if srcName == 'player' and (powerType == 'FURY' or powerType == 'PAIN') then
		UI:UpdateCombatWithin(0.05)
	end
end

function events:UNIT_SPELLCAST_START(srcName)
	if Opt.interrupt and srcName == 'target' then
		UI:UpdateCombatWithin(0.05)
	end
end

function events:UNIT_SPELLCAST_STOP(srcName)
	if Opt.interrupt and srcName == 'target' then
		UI:UpdateCombatWithin(0.05)
	end
end

function events:PLAYER_PVP_TALENT_UPDATE()
	Player:UpdateAbilities()
end

function events:AZERITE_ESSENCE_UPDATE()
	Azerite:Update()
	Player:UpdateAbilities()
end

function events:ACTIONBAR_SLOT_CHANGED()
	UI:UpdateGlows()
end

function events:PLAYER_ENTERING_WORLD()
	if #UI.glows == 0 then
		UI:CreateOverlayGlows()
		UI:HookResourceFrame()
	end
	local _
	_, Player.instance = IsInInstance()
	Player.guid = UnitGUID('player')
	events:PLAYER_SPECIALIZATION_CHANGED('player')
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
	timer.combat = timer.combat + elapsed
	timer.display = timer.display + elapsed
	timer.health = timer.health + elapsed
	if timer.combat >= Opt.frequency then
		UI:UpdateCombat()
	end
	if timer.display >= 0.05 then
		UI:UpdateDisplay()
	end
	if timer.health >= 0.2 then
		Target:UpdateHealth()
	end
end)

lasikPanel:SetScript('OnEvent', function(self, event, ...) events[event](self, ...) end)
local event
for event in next, events do
	lasikPanel:RegisterEvent(event)
end

-- End Event Handling

-- Start Slash Commands

-- this fancy hack allows you to click BattleTag links to add them as a friend!
local ChatFrame_OnHyperlinkShow_Original = ChatFrame_OnHyperlinkShow
function ChatFrame_OnHyperlinkShow(chatFrame, link, ...)
	local linkType, linkData = link:match('(.-):(.*)')
	if linkType == 'BNadd' then
		return BattleTagInviteFrame_Show(linkData)
	end
	return ChatFrame_OnHyperlinkShow_Original(chatFrame, link, ...)
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
	print('Lasik -', desc .. ':', opt_view, ...)
end

function SlashCmdList.Lasik(msg, editbox)
	msg = { strsplit(' ', msg:lower()) }
	if startsWith(msg[1], 'lock') then
		if msg[2] then
			Opt.locked = msg[2] == 'on'
			UI:UpdateDraggable()
		end
		return Status('Locked', Opt.locked)
	end
	if startsWith(msg[1], 'snap') then
		if msg[2] then
			if msg[2] == 'above' or msg[2] == 'over' then
				Opt.snap = 'above'
			elseif msg[2] == 'below' or msg[2] == 'under' then
				Opt.snap = 'below'
			else
				Opt.snap = false
				lasikPanel:ClearAllPoints()
			end
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
			Opt.alpha = max(min((tonumber(msg[2]) or 100), 100), 0) / 100
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
		if msg[2] == 'color' then
			if msg[5] then
				Opt.glow.color.r = max(min(tonumber(msg[3]) or 0, 1), 0)
				Opt.glow.color.g = max(min(tonumber(msg[4]) or 0, 1), 0)
				Opt.glow.color.b = max(min(tonumber(msg[5]) or 0, 1), 0)
				UI:UpdateGlowColorAndScale()
			end
			return Status('Glow color', '|cFFFF0000' .. Opt.glow.color.r, '|cFF00FF00' .. Opt.glow.color.g, '|cFF0000FF' .. Opt.glow.color.b)
		end
		return Status('Possible glow options', '|cFFFFD000main|r, |cFFFFD000cd|r, |cFFFFD000interrupt|r, |cFFFFD000extra|r, |cFFFFD000blizzard|r, and |cFFFFD000color')
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
		return Status('Show the Lasik UI without a target', Opt.always_on)
	end
	if msg[1] == 'cd' then
		if msg[2] then
			Opt.cooldown = msg[2] == 'on'
		end
		return Status('Use Lasik for cooldown management', Opt.cooldown)
	end
	if msg[1] == 'swipe' then
		if msg[2] then
			Opt.spell_swipe = msg[2] == 'on'
		end
		return Status('Spell casting swipe animation', Opt.spell_swipe)
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
	if msg[1] == 'hidespec' or startsWith(msg[1], 'spec') then
		if msg[2] then
			if startsWith(msg[2], 'h') then
				Opt.hide.havoc = not Opt.hide.havoc
				events:PLAYER_SPECIALIZATION_CHANGED('player')
				return Status('Havoc specialization', not Opt.hide.havoc)
			end
			if startsWith(msg[2], 'v') then
				Opt.hide.vengeance = not Opt.hide.vengeance
				events:PLAYER_SPECIALIZATION_CHANGED('player')
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
	if msg[1] == 'meta' then
		if msg[2] then
			Opt.meta_ttd = tonumber(msg[2]) or 8
		end
		return Status('Minimum enemy lifetime to use Metamorphosis on (ignored on bosses)', Opt.meta_ttd, 'seconds')
	end
	if msg[1] == 'reset' then
		lasikPanel:ClearAllPoints()
		lasikPanel:SetPoint('CENTER', 0, -169)
		UI:SnapAllPanels()
		return Status('Position has been reset to', 'default')
	end
	print('Lasik (version: |cFFFFD000' .. GetAddOnMetadata('Lasik', 'Version') .. '|r) - Commands:')
	local _, cmd
	for _, cmd in next, {
		'locked |cFF00C000on|r/|cFFC00000off|r - lock the Lasik UI so that it can\'t be moved',
		'snap |cFF00C000above|r/|cFF00C000below|r/|cFFC00000off|r - snap the Lasik UI to the Personal Resource Display',
		'scale |cFFFFD000prev|r/|cFFFFD000main|r/|cFFFFD000cd|r/|cFFFFD000interrupt|r/|cFFFFD000extra|r/|cFFFFD000glow|r - adjust the scale of the Lasik UI icons',
		'alpha |cFFFFD000[percent]|r - adjust the transparency of the Lasik UI icons',
		'frequency |cFFFFD000[number]|r - set the calculation frequency (default is every 0.2 seconds)',
		'glow |cFFFFD000main|r/|cFFFFD000cd|r/|cFFFFD000interrupt|r/|cFFFFD000extra|r/|cFFFFD000blizzard|r |cFF00C000on|r/|cFFC00000off|r - glowing ability buttons on action bars',
		'glow color |cFFF000000.0-1.0|r |cFF00FF000.1-1.0|r |cFF0000FF0.0-1.0|r - adjust the color of the ability button glow',
		'previous |cFF00C000on|r/|cFFC00000off|r - previous ability icon',
		'always |cFF00C000on|r/|cFFC00000off|r - show the Lasik UI without a target',
		'cd |cFF00C000on|r/|cFFC00000off|r - use Lasik for cooldown management',
		'swipe |cFF00C000on|r/|cFFC00000off|r - show spell casting swipe animation on main ability icon',
		'dim |cFF00C000on|r/|cFFC00000off|r - dim main ability icon when you don\'t have enough resources to use it',
		'miss |cFF00C000on|r/|cFFC00000off|r - red border around previous ability when it fails to hit',
		'aoe |cFF00C000on|r/|cFFC00000off|r - allow clicking main ability icon to toggle amount of targets (disables moving)',
		'bossonly |cFF00C000on|r/|cFFC00000off|r - only use cooldowns on bosses',
		'hidespec |cFFFFD000havoc|r/|cFFFFD000vengeance|r - toggle disabling Lasik for specializations',
		'interrupt |cFF00C000on|r/|cFFC00000off|r - show an icon for interruptable spells',
		'auto |cFF00C000on|r/|cFFC00000off|r  - automatically change target mode on AoE spells',
		'ttl |cFFFFD000[seconds]|r  - time target exists in auto AoE after being hit (default is 10 seconds)',
		'pot |cFF00C000on|r/|cFFC00000off|r - show flasks and battle potions in cooldown UI',
		'trinket |cFF00C000on|r/|cFFC00000off|r - show on-use trinkets in cooldown UI',
		'meta |cFFFFD000[seconds]|r  - minimum enemy lifetime to use Metamorphosis on (default is 8 seconds, ignored on bosses)',
		'|cFFFFD000reset|r - reset the location of the Lasik UI to default',
	} do
		print('  ' .. SLASH_Lasik1 .. ' ' .. cmd)
	end
	print('Got ideas for improvement or found a bug? Talk to me on Battle.net:',
		'|c' .. BATTLENET_FONT_COLOR:GenerateHexColor() .. '|HBNadd:Spy#1955|h[Spy#1955]|h|r')
end

-- End Slash Commands
