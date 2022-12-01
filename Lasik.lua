local ADDON = 'Lasik'
if select(2, UnitClass('player')) ~= 'DEMONHUNTER' then
	DisableAddOn(ADDON)
	return
end
local ADDON_PATH = 'Interface\\AddOns\\' .. ADDON .. '\\'

-- reference heavily accessed global functions from local scope for performance
local min = math.min
local max = math.max
local floor = math.floor
local GetPowerRegenForPowerType = _G.GetPowerRegenForPowerType
local GetSpellCharges = _G.GetSpellCharges
local GetSpellCooldown = _G.GetSpellCooldown
local GetSpellInfo = _G.GetSpellInfo
local GetTime = _G.GetTime
local GetUnitSpeed = _G.GetUnitSpeed
local UnitAttackSpeed = _G.UnitAttackSpeed
local UnitAura = _G.UnitAura
local UnitCastingInfo = _G.UnitCastingInfo
local UnitChannelInfo = _G.UnitChannelInfo
local UnitDetailedThreatSituation = _G.UnitDetailedThreatSituation
local UnitHealth = _G.UnitHealth
local UnitHealthMax = _G.UnitHealthMax
local UnitPower = _G.UnitPower
local UnitPowerMax = _G.UnitPowerMax
-- end reference global functions

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
BINDING_HEADER_CLAW = ADDON

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
		cd_ttd = 8,
		pot = false,
		trinket = true,
	})
end

-- UI related functions container
local UI = {
	anchor = {},
	glows = {},
}

-- combat event related functions container
local CombatEvent = {}

-- automatically registered events container
local events = {}

local timer = {
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

-- current player information
local Player = {
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
	cast_remains = 0,
	execute_remains = 0,
	haste_factor = 1,
	moving = false,
	health = {
		current = 0,
		max = 100,
		pct = 0,
	},
	fury = {
		current = 0,
		deficit = 0,
		max = 100,
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
	previous_gcd = {},-- list of previous GCD abilities
	item_use_blacklist = { -- list of item IDs with on-use effects we should mark unusable
	},
	main_freecast = false,
	meta_remains = 0,
	meta_active = false,
	soul_fragments = 0,
}

-- current target information
local Target = {
	boss = false,
	guid = 0,
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
lasikPanel.border:SetTexture(ADDON_PATH .. 'border.blp')
lasikPanel.border:Hide()
lasikPanel.dimmer = lasikPanel:CreateTexture(nil, 'BORDER')
lasikPanel.dimmer:SetAllPoints(lasikPanel)
lasikPanel.dimmer:SetColorTexture(0, 0, 0, 0.6)
lasikPanel.dimmer:Hide()
lasikPanel.swipe = CreateFrame('Cooldown', nil, lasikPanel, 'CooldownFrameTemplate')
lasikPanel.swipe:SetAllPoints(lasikPanel)
lasikPanel.swipe:SetDrawBling(false)
lasikPanel.swipe:SetDrawEdge(false)
lasikPanel.text = CreateFrame('Frame', nil, lasikPanel)
lasikPanel.text:SetAllPoints(lasikPanel)
lasikPanel.text.tl = lasikPanel.text:CreateFontString(nil, 'OVERLAY')
lasikPanel.text.tl:SetFont('Fonts\\FRIZQT__.TTF', 12, 'OUTLINE')
lasikPanel.text.tl:SetPoint('TOPLEFT', lasikPanel, 'TOPLEFT', 2.5, -3)
lasikPanel.text.tl:SetJustifyH('LEFT')
lasikPanel.text.tr = lasikPanel.text:CreateFontString(nil, 'OVERLAY')
lasikPanel.text.tr:SetFont('Fonts\\FRIZQT__.TTF', 12, 'OUTLINE')
lasikPanel.text.tr:SetPoint('TOPRIGHT', lasikPanel, 'TOPRIGHT', -2.5, -3)
lasikPanel.text.tr:SetJustifyH('RIGHT')
lasikPanel.text.bl = lasikPanel.text:CreateFontString(nil, 'OVERLAY')
lasikPanel.text.bl:SetFont('Fonts\\FRIZQT__.TTF', 12, 'OUTLINE')
lasikPanel.text.bl:SetPoint('BOTTOMLEFT', lasikPanel, 'BOTTOMLEFT', 2.5, 3)
lasikPanel.text.bl:SetJustifyH('LEFT')
lasikPanel.text.br = lasikPanel.text:CreateFontString(nil, 'OVERLAY')
lasikPanel.text.br:SetFont('Fonts\\FRIZQT__.TTF', 12, 'OUTLINE')
lasikPanel.text.br:SetPoint('BOTTOMRIGHT', lasikPanel, 'BOTTOMRIGHT', -2.5, 3)
lasikPanel.text.br:SetJustifyH('RIGHT')
lasikPanel.text.center = lasikPanel.text:CreateFontString(nil, 'OVERLAY')
lasikPanel.text.center:SetFont('Fonts\\FRIZQT__.TTF', 12, 'OUTLINE')
lasikPanel.text.center:SetAllPoints(lasikPanel.text)
lasikPanel.text.center:SetJustifyH('CENTER')
lasikPanel.text.center:SetJustifyV('CENTER')
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
lasikPreviousPanel.border:SetTexture(ADDON_PATH .. 'border.blp')
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
lasikCooldownPanel.border:SetTexture(ADDON_PATH .. 'border.blp')
lasikCooldownPanel.dimmer = lasikCooldownPanel:CreateTexture(nil, 'BORDER')
lasikCooldownPanel.dimmer:SetAllPoints(lasikCooldownPanel)
lasikCooldownPanel.dimmer:SetColorTexture(0, 0, 0, 0.6)
lasikCooldownPanel.dimmer:Hide()
lasikCooldownPanel.swipe = CreateFrame('Cooldown', nil, lasikCooldownPanel, 'CooldownFrameTemplate')
lasikCooldownPanel.swipe:SetAllPoints(lasikCooldownPanel)
lasikCooldownPanel.swipe:SetDrawBling(false)
lasikCooldownPanel.swipe:SetDrawEdge(false)
lasikCooldownPanel.text = lasikCooldownPanel:CreateFontString(nil, 'OVERLAY')
lasikCooldownPanel.text:SetFont('Fonts\\FRIZQT__.TTF', 12, 'OUTLINE')
lasikCooldownPanel.text:SetAllPoints(lasikCooldownPanel)
lasikCooldownPanel.text:SetJustifyH('CENTER')
lasikCooldownPanel.text:SetJustifyV('CENTER')
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
lasikInterruptPanel.border:SetTexture(ADDON_PATH .. 'border.blp')
lasikInterruptPanel.swipe = CreateFrame('Cooldown', nil, lasikInterruptPanel, 'CooldownFrameTemplate')
lasikInterruptPanel.swipe:SetAllPoints(lasikInterruptPanel)
lasikInterruptPanel.swipe:SetDrawBling(false)
lasikInterruptPanel.swipe:SetDrawEdge(false)
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
lasikExtraPanel.border:SetTexture(ADDON_PATH .. 'border.blp')

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
	for guid in next, self.targets do
		self.targets[guid] = nil
	end
end

function autoAoe:Update()
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

function autoAoe:Purge()
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

local Ability = {}
Ability.__index = Ability
local abilities = {
	all = {},
	bySpellId = {},
	velocity = {},
	autoAoe = {},
	trackAuras = {},
}

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
		fury_cost = 0,
		cooldown_duration = 0,
		buff_duration = 0,
		tick_interval = 0,
		max_range = 40,
		velocity = 0,
		last_used = 0,
		aura_target = buff and 'player' or 'target',
		aura_filter = (buff and 'HELPFUL' or 'HARMFUL') .. (player and '|PLAYER' or '')
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
	return self:Cooldown() <= (seconds or 0) and (not self.requires_react or self:React() > (seconds or 0))
end

function Ability:Usable(seconds, pool)
	if not self.known then
		return false
	end
	if self:FuryCost() > Player.fury.current then
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
	local _, id, expires
	for i = 1, 40 do
		_, _, _, _, _, expires, _, _, _, id = UnitAura(self.aura_target, i, self.aura_filter)
		if not id then
			return 0
		elseif self:Match(id) then
			if expires == 0 then
				return 600 -- infinite duration
			end
			return max(0, expires - Player.ctime - Player.execute_remains)
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
			if Player.time - cast.start < self.max_range / self.velocity then
				count = count + 1
			end
		end
	end
	return count
end

function Ability:TravelTime()
	return Target.estimated_range / self.velocity
end

function Ability:Ticking()
	local count, ticking = 0, {}
	if self.aura_targets then
		for guid, aura in next, self.aura_targets do
			if aura.expires - Player.time > Player.execute_remains then
				ticking[guid] = true
			end
		end
	end
	if self.traveling then
		for _, cast in next, self.traveling do
			if Player.time - cast.start < self.max_range / self.velocity then
				ticking[cast.dstGUID] = true
			end
		end
	end
	for _ in next, ticking do
		count = count + 1
	end
	return count
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
	local _, id, expires, count
	for i = 1, 40 do
		_, _, count, _, _, expires, _, _, _, id = UnitAura(self.aura_target, i, self.aura_filter)
		if not id then
			return 0
		elseif self:Match(id) then
			return (expires == 0 or expires - Player.ctime > Player.execute_remains) and count or 0
		end
	end
	return 0
end

function Ability:FuryCost()
	return self.fury_cost
end

function Ability:ChargesFractional()
	local charges, max_charges, recharge_start, recharge_time = GetSpellCharges(self.spellId)
	if self:Casting() then
		if charges >= max_charges then
			return charges - 1
		end
		charges = charges - 1
	end
	if charges >= max_charges then
		return charges
	end
	return charges + ((max(0, Player.ctime - recharge_start + Player.execute_remains)) / recharge_time)
end

function Ability:Charges()
	return floor(self:ChargesFractional())
end

function Ability:MaxCharges()
	local _, max_charges = GetSpellCharges(self.spellId)
	return max_charges or 0
end

function Ability:FullRechargeTime()
	local charges, max_charges, recharge_start, recharge_time = GetSpellCharges(self.spellId)
	if self:Casting() then
		if charges >= max_charges then
			return recharge_time
		end
		charges = charges - 1
	end
	if charges >= max_charges then
		return 0
	end
	return (max_charges - charges - 1) * recharge_time + (recharge_time - (Player.ctime - recharge_start) - Player.execute_remains)
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
		return 0
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
		if self.auto_aoe.remove then
			autoAoe:Clear()
		end
		self.auto_aoe.target_count = 0
		for guid in next, self.auto_aoe.targets do
			autoAoe:Add(guid)
			self.auto_aoe.targets[guid] = nil
			self.auto_aoe.target_count = self.auto_aoe.target_count + 1
		end
		autoAoe:Update()
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
	Player.last_ability = self
	if self.triggers_gcd then
		Player.previous_gcd[10] = nil
		table.insert(Player.previous_gcd, 1, self)
	end
	if self.aura_targets and self.requires_react then
		self:RemoveAura(self.aura_target == 'player' and Player.guid or dstGUID)
	end
	if Opt.auto_aoe and self.auto_aoe and self.auto_aoe.trigger == 'SPELL_CAST_SUCCESS' then
		autoAoe:Add(dstGUID, true)
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
			if Player.time - cast.start >= self.max_range / self.velocity + 0.2 then
				self.traveling[guid] = nil -- spell traveled 0.2s past max range, delete it, this should never happen
			elseif cast.dstGUID == dstGUID and (not oldest or cast.start < oldest.start) then
				oldest = cast
			end
		end
		if oldest then
			Target.estimated_range = min(self.max_range, floor(self.velocity * max(0, Player.time - oldest.start)))
			self.traveling[oldest.guid] = nil
		end
	end
	if self.range_est_start then
		Target.estimated_range = floor(max(5, min(self.max_range, self.velocity * (Player.time - self.range_est_start))))
		self.range_est_start = nil
	elseif self.max_range < Target.estimated_range then
		Target.estimated_range = self.max_range
	end
	if Opt.previous and Opt.miss_effect and event == 'SPELL_MISSED' and lasikPreviousPanel.ability == self then
		lasikPreviousPanel.border:SetTexture(ADDON_PATH .. 'misseffect.blp')
	end
end

-- Start DoT tracking

local trackAuras = {}

function trackAuras:Purge()
	for _, ability in next, abilities.trackAuras do
		for guid, aura in next, ability.aura_targets do
			if aura.expires <= Player.time then
				ability:RemoveAura(guid)
			end
		end
	end
end

function trackAuras:Remove(guid)
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
	local aura = {}
	aura.expires = Player.time + self:Duration()
	self.aura_targets[guid] = aura
	return aura
end

function Ability:RefreshAura(guid)
	if autoAoe.blacklist[guid] then
		return
	end
	local aura = self.aura_targets[guid]
	if not aura then
		return self:ApplyAura(guid)
	end
	local duration = self:Duration()
	aura.expires = max(aura.expires, Player.time + min(duration * 1.3, (aura.expires - Player.time) + duration))
	return aura
end

function Ability:RefreshAuraAll()
	local duration = self:Duration()
	for guid, aura in next, self.aura_targets do
		aura.expires = max(aura.expires, Player.time + min(duration * 1.3, (aura.expires - Player.time) + duration))
	end
end

function Ability:RemoveAura(guid)
	if self.aura_targets[guid] then
		self.aura_targets[guid] = nil
	end
end

-- End DoT tracking

-- Demon Hunter Abilities
---- Baseline
local Disrupt = Ability:Add(183752, false, true)
Disrupt.cooldown_duration = 15
Disrupt.triggers_gcd = false
local ImmolationAura = Ability:Add(258920, true, true)
ImmolationAura.buff_duration = 6
ImmolationAura.cooldown_duration = 15
ImmolationAura.tick_interval = 1
ImmolationAura.hasted_cooldown = true
ImmolationAura.damage = Ability:Add(258922, false, true)
ImmolationAura.damage:AutoAoe(true)
local Torment = Ability:Add(185245, false, true)
Torment.cooldown_duration = 8
Torment.triggers_gcd = false
local Annihilation = Ability:Add(201427, false, true, 201428)
Annihilation.fury_cost = 40
local BladeDance = Ability:Add(188499, false, true, 199552)
BladeDance.cooldown_duration = 9
BladeDance.fury_cost = 35
BladeDance.hasted_cooldown = true
BladeDance:AutoAoe(true)
local ChaosFragments = Ability:Add(320412, true, true)
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
local FelMastery = Ability:Add(192939, false, true)
local FirstBlood = Ability:Add(206416, false, true)
local Momentum = Ability:Add(206476, true, true, 208628)
Momentum.buff_duration = 6
local Nemesis = Ability:Add(206491, false, true)
Nemesis.buff_duration = 60
Nemesis.cooldown_duration = 120
local TrailOfRuin = Ability:Add(258881, false, true, 258883)
TrailOfRuin.buff_duration = 4
TrailOfRuin.tick_interval = 1
local UnleashedPower = Ability:Add(206477, false, true)
local DemonSpikes = Ability:Add(203720, true, true, 203819)
DemonSpikes.buff_duration = 6
DemonSpikes.cooldown_duration = 20
DemonSpikes.hasted_cooldown = true
DemonSpikes.requires_charge = true
local FelDevastation = Ability:Add(212084, false, true)
FelDevastation.fury_cost = 50
FelDevastation.buff_duration = 2
FelDevastation.cooldown_duration = 60
FelDevastation:AutoAoe()
local FieryBrand = Ability:Add(204021, false, true)
FieryBrand.buff_duration = 12
FieryBrand.cooldown_duration = 60
FieryBrand:TrackAuras()
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
SoulCleave.fury_cost = 30
SoulCleave:AutoAoe(true)
local SoulFragments = Ability:Add(204254, true, true, 203981)
local ThrowGlaiveV = Ability:Add(204157, false, true)
ThrowGlaiveV.cooldown_duration = 3
ThrowGlaiveV.hasted_cooldown = true
ThrowGlaiveV:AutoAoe()
local Fracture = Ability:Add(263642, false, true)
Fracture.cooldown_duration = 4.5
Fracture.hasted_cooldown = true
Fracture.requires_charge = true
local SpiritBomb = Ability:Add(247454, false, true)
SpiritBomb.fury_cost = 40
SpiritBomb:AutoAoe(true)
local QuickenedSigils = Ability:Add(209281, true, true)
local TheHunt = Ability:Add(370965, true, true)
TheHunt.cooldown_duration = 90
TheHunt.buff_duration = 30
local ElysianDecree = Ability:Add(306830, false, true)
ElysianDecree.cooldown_duration = 60
ElysianDecree.check_usable = true
-- Racials

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
local EternalAugmentRune = InventoryItem:Add(190384)
EternalAugmentRune.buff = Ability:Add(367405, true, true)
local EternalFlask = InventoryItem:Add(171280)
EternalFlask.buff = Ability:Add(307166, true, true)
local PotionOfPhantomFire = InventoryItem:Add(171349)
PotionOfPhantomFire.buff = Ability:Add(307495, true, true)
local PotionOfSpectralAgility = InventoryItem:Add(171270)
PotionOfSpectralAgility.buff = Ability:Add(307159, true, true)
local SpectralFlaskOfPower = InventoryItem:Add(171276)
SpectralFlaskOfPower.buff = Ability:Add(307185, true, true)
-- Equipment
local Trinket1 = InventoryItem:Add(0)
local Trinket2 = InventoryItem:Add(0)
-- End Inventory Items

-- Start Player API

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
	return 0
end

function Player:UnderMeleeAttack()
	return (self.time - self.swing.last_taken) < 3
end

function Player:UnderAttack()
	return self.threat.status >= 3 or self:UnderMeleeAttack()
end

function Player:BloodlustActive()
	local _, id
	for i = 1, 40 do
		_, _, _, _, _, _, _, _, _, id = UnitAura('player', i, 'HELPFUL')
		if not id then
			return false
		elseif (
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

function Player:UpdateAbilities()
	self.fury.max = UnitPowerMax('player', 17)

	local node
	for _, ability in next, abilities.all do
		ability.known = false
		for _, spellId in next, ability.spellIds do
			ability.spellId, ability.name, _, ability.icon = spellId, GetSpellInfo(spellId)
			if IsPlayerSpell(spellId) or (ability.learn_spellId and IsPlayerSpell(ability.learn_spellId)) then
				ability.known = true
				break
			end
		end
		if ability.bonus_id then -- used for checking enchants and crafted effects
			ability.known = self:BonusIdEquipped(ability.bonus_id)
		end
		if C_LevelLink.IsSpellLocked(ability.spellId) or (ability.check_usable and not IsUsableSpell(ability.spellId)) then
			ability.known = false -- spell is locked, do not mark as known
		end
	end

	ImmolationAura.damage.known = ImmolationAura.known
	SigilOfFlame.dot.known = SigilOfFlame.known
	if Fracture.known then
		Shear.known = false
	end

	wipe(abilities.bySpellId)
	wipe(abilities.velocity)
	wipe(abilities.autoAoe)
	wipe(abilities.trackAuras)
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

function Player:UpdateThreat()
	local _, status, pct
	_, status, pct = UnitDetailedThreatSituation('player', 'target')
	self.threat.status = status or 0
	self.threat.pct = pct or 0
	self.threat.lead = 0
	if self.threat.status >= 3 and DETAILS_PLUGIN_TINY_THREAT then
		local threat_table = DETAILS_PLUGIN_TINY_THREAT.player_list_indexes
		if threat_table and threat_table[1] and threat_table[2] and threat_table[1][1] == Player.name then
			self.threat.lead = max(0, threat_table[1][6] - threat_table[2][6])
		end
	end
end

function Player:Update()
	local _, start, duration, remains, spellId, speed_mh, speed_oh
	self.main =  nil
	self.cd = nil
	self.interrupt = nil
	self.extra = nil
	self:UpdateTime()
	start, duration = GetSpellCooldown(61304)
	self.gcd_remains = start > 0 and duration - (self.ctime - start) or 0
	_, _, _, _, remains, _, _, _, spellId = UnitCastingInfo('player')
	self.ability_casting = abilities.bySpellId[spellId]
	self.cast_remains = remains and (remains / 1000 - self.ctime) or 0
	self.execute_remains = max(self.cast_remains, self.gcd_remains)
	self.haste_factor = 1 / (1 + UnitSpellHaste('player') / 100)
	speed_mh, speed_oh = UnitAttackSpeed('player')
	self.swing.mh.speed = speed_mh or 0
	self.swing.oh.speed = speed_oh or 0
	self.swing.mh.remains = max(0, self.swing.mh.last + self.swing.mh.speed - self.time)
	self.swing.oh.remains = max(0, self.swing.oh.last + self.swing.oh.speed - self.time)
	self.moving = GetUnitSpeed('player') ~= 0
	self:UpdateThreat()
	self.gcd = 1.5 * self.haste_factor
	self.fury.current = UnitPower('player', 17)
	self.fury.deficit = self.fury.max - self.fury.current
	if self.spec == SPEC.HAVOC then
		self.meta_remains = Metamorphosis:Remains()
		self.soul_fragments = 0
	elseif self.spec == SPEC.VENGEANCE then
		self.meta_remains = MetamorphosisV:Remains()
		self.soul_fragments = SoulFragments:Stack()
	end
	self.meta_active = self.meta_remains > 0

	trackAuras:Purge()
	if Opt.auto_aoe then
		for _, ability in next, abilities.autoAoe do
			ability:UpdateTargetsHit()
		end
		autoAoe:Purge()
	end
end

function Player:Init()
	local _
	if #UI.glows == 0 then
		UI:DisableOverlayGlows()
		UI:CreateOverlayGlows()
		UI:HookResourceFrame()
	end
	lasikPreviousPanel.ability = nil
	self.guid = UnitGUID('player')
	self.name = UnitName('player')
	self.level = UnitLevel('player')
	_, self.instance = IsInInstance()
	events:GROUP_ROSTER_UPDATE()
	events:PLAYER_SPECIALIZATION_CHANGED('player')
end

-- End Player API

-- Start Target API

function Target:UpdateHealth(reset)
	timer.health = 0
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
	self.timeToDieMax = self.health.current / Player.health.max * 10
	self.health.pct = self.health.max > 0 and (self.health.current / self.health.max * 100) or 100
	self.health.loss_per_sec = (self.health.history[1] - self.health.current) / 5
	self.timeToDie = self.health.loss_per_sec > 0 and min(self.timeToDieMax, self.health.current / self.health.loss_per_sec) or self.timeToDieMax
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
		return
	end
	if guid ~= self.guid then
		self.guid = guid
		self:UpdateHealth(true)
	end
	self.boss = false
	self.stunnable = true
	self.classification = UnitClassification('target')
	self.player = UnitIsPlayer('target')
	self.level = UnitLevel('target')
	self.hostile = UnitCanAttack('player', 'target') and not UnitIsDead('target')
	if not self.player and self.classification ~= 'minus' and self.classification ~= 'normal' then
		if self.level == -1 or (Player.instance == 'party' and self.level >= Player.level + 2) then
			self.boss = true
			self.stunnable = false
		elseif Player.instance == 'raid' or (self.health.max > Player.health.max * 10) then
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
ElysianDecree.Duration = SigilOfFlame.Duration

function SigilOfFlame:Placed()
	return (Player.time - self.last_used) < (self:Duration() + 0.5)
end
SigilOfChains.Placed = SigilOfFlame.Placed
SigilOfMisery.Placed = SigilOfFlame.Placed
SigilOfSilence.Placed = SigilOfFlame.Placed
ElysianDecree.Placed = SigilOfFlame.Placed

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

APL[SPEC.HAVOC].Main = function(self)
	if Player:TimeInCombat() == 0 then
		if not Player:InArenaOrBattleground() then
			if EternalAugmentRune:Usable() and EternalAugmentRune.buff:Remains() < 300 then
				UseCooldown(EternalAugmentRune)
			end
			if EternalFlask:Usable() and EternalFlask.buff:Remains() < 300 and SpectralFlaskOfPower.buff:Remains() < 300 then
				UseCooldown(EternalFlask)
			end
			if Opt.pot and SpectralFlaskOfPower:Usable() and SpectralFlaskOfPower.buff:Remains() < 300 and EternalFlask.buff:Remains() < 300 then
				UseCooldown(SpectralFlaskOfPower)
			end
		end
	else

	end
end

APL[SPEC.VENGEANCE].Main = function(self)
	if Player:TimeInCombat() == 0 then
		if not Player:InArenaOrBattleground() then
			if EternalAugmentRune:Usable() and EternalAugmentRune.buff:Remains() < 300 then
				UseCooldown(EternalAugmentRune)
			end
			if EternalFlask:Usable() and EternalFlask.buff:Remains() < 300 and SpectralFlaskOfPower.buff:Remains() < 300 then
				UseCooldown(EternalFlask)
			end
			if Opt.pot and SpectralFlaskOfPower:Usable() and SpectralFlaskOfPower.buff:Remains() < 300 and EternalFlask.buff:Remains() < 300 then
				UseCooldown(SpectralFlaskOfPower)
			end
		end
	else

	end
	self:defensives()
	self:cooldowns()
	return self:normal()
end

APL[SPEC.VENGEANCE].cooldowns = function(self)
--[[
actions.cooldowns=potion
# Default fallback for usable items.
actions.cooldowns+=/use_items
actions.cooldowns+=/sinful_brand,if=!dot.sinful_brand.ticking
actions.cooldowns+=/the_hunt
actions.cooldowns+=/elysian_decree
]]
	if Opt.pot and Target.boss and PotionOfSpectralAgility:Usable() then
		return UseCooldown(PotionOfSpectralAgility)
	end
	if Opt.trinket then
		if Trinket1:Usable() then
			return UseCooldown(Trinket1)
		elseif Trinket2:Usable() then
			return UseCooldown(Trinket2)
		end
	end
	if ElysianDecree:Usable() and Player.enemies >= 3 then
		return UseCooldown(ElysianDecree)
	end
	if TheHunt:Usable() then
		return UseCooldown(TheHunt)
	end
	if ElysianDecree:Usable() then
		return UseCooldown(ElysianDecree)
	end
end

APL[SPEC.VENGEANCE].defensives = function(self)
--[[
actions.defensives=demon_spikes
actions.defensives+=/metamorphosis,if=!buff.metamorphosis.up&(!covenant.venthyr.enabled|!dot.sinful_brand.ticking)|target.time_to_die<15
actions.defensives+=/fiery_brand
]]
	if DemonSpikes:Usable() and Target.timeToDie > DemonSpikes:Remains() then
		UseExtra(DemonSpikes)
	end
	if MetamorphosisV:Usable() and not Player.meta_active and (not Demonic.known or not FelDevastation:Ready()) then
		UseExtra(MetamorphosisV)
	end
	if FelDevastation:Usable() and not Player.meta_active then
		return UseCooldown(FelDevastation)
	end
end

APL[SPEC.VENGEANCE].normal = function(self)
--[[
actions.normal=infernal_strike
actions.normal+=/bulk_extraction
actions.normal+=/spirit_bomb,if=((buff.metamorphosis.up&talent.fracture.enabled&soul_fragments>=3)|soul_fragments>=4)
actions.normal+=/soul_cleave,if=((talent.spirit_bomb.enabled&soul_fragments=0)|!talent.spirit_bomb.enabled)&((talent.fracture.enabled&fury>=55)|(!talent.fracture.enabled&fury>=70)|cooldown.fel_devastation.remains>target.time_to_die|(buff.metamorphosis.up&((talent.fracture.enabled&fury>=35)|(!talent.fracture.enabled&fury>=50))))
actions.normal+=/immolation_aura,if=((variable.brand_build&cooldown.fiery_brand.remains>10)|!variable.brand_build)&fury<=90
actions.normal+=/fel_devastation,if=fury<=60
actions.normal+=/fracture,if=((talent.spirit_bomb.enabled&soul_fragments<=3)|(!talent.spirit_bomb.enabled&((buff.metamorphosis.up&fury<=55)|(buff.metamorphosis.down&fury<=70))))
actions.normal+=/sigil_of_flame,if=!(covenant.kyrian.enabled&runeforge.razelikhs_defilement)
actions.normal+=/shear
actions.normal+=/throw_glaive
]]
	self.spirit_bomb_condition = SpiritBomb.known and Player.soul_fragments >= (4 - (Player.meta_active and Fracture.known and 1 or 0))
	if FieryBrand:Usable() then
		UseCooldown(FieryBrand)
	end
	if InfernalStrike:Usable() and InfernalStrike:ChargesFractional() >= 1.5 then
		UseExtra(InfernalStrike)
	end
	if SigilOfFlame:Usable() and self.spirit_bomb_condition and Player.health.pct >= 50 then
		return SigilOfFlame
	end
	if SpiritBomb:Usable() and self.spirit_bomb_condition then
		return SpiritBomb
	end
	if SoulCleave:Usable() and (not SpiritBomb.known or (Player.soul_fragments == 0 and not (Fracture:Previous() or SigilOfFlame:Placed() or ElysianDecree:Placed()))) and (
		Player.fury.current >= (Fracture.known and 55 or 70) or
		not FelDevastation:Ready(Target.timeToDie) or
		(Player.meta_active and Player.fury.current >= (Fracture.known and 35 or 50))
	) then
		return SoulCleave
	end
	if ImmolationAura:Usable() and ImmolationAura:Down() then
		return ImmolationAura
	end
	if Fracture:Usable() and (
		(SpiritBomb.known and Player.soul_fragments <= 3) or
		(not SpiritBomb.known and Player.fury.current <= (Player.meta_active and 55 or 70))
	) then
		return Fracture
	end
	if SigilOfFlame:Usable() then
		return SigilOfFlame
	end
	if ChaosFragments.known and ChaosNova:Usable() and Player.enemies >= 3 and Player.soul_fragments <= 1 and Target.stunnable then
		UseCooldown(ChaosNova)
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

-- Start UI API

function UI.DenyOverlayGlow(actionButton)
	if not Opt.glow.blizzard then
		actionButton.overlay:Hide()
	end
end
hooksecurefunc('ActionButton_ShowOverlayGlow', UI.DenyOverlayGlow) -- Disable Blizzard's built-in action button glowing

function UI:UpdateGlowColorAndScale()
	local w, h, glow
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

function UI:DisableOverlayGlows()
	if LibStub and LibStub.GetLibrary and not Opt.glow.blizzard then
		local lib = LibStub:GetLibrary('LibButtonGlow-1.0', true)
		if lib then
			lib.ShowOverlayGlow = function(self)
				return
			end
		end
	end
end

function UI:CreateOverlayGlows()
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
	local glow, icon
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
		lasikPanel:RegisterForDrag('')
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
	local dim, dim_cd, text_center, text_cd, text_tl, text_tr

	if Opt.dimmer then
		dim = not ((not Player.main) or
		           (Player.main.spellId and IsUsableSpell(Player.main.spellId)) or
		           (Player.main.itemId and IsUsableItem(Player.main.itemId)))
		dim_cd = not ((not Player.cd) or
		           (Player.cd.spellId and IsUsableSpell(Player.cd.spellId)) or
		           (Player.cd.itemId and IsUsableItem(Player.cd.itemId)))
	end
	if Player.main and Player.main.requires_react then
		local react = Player.main:React()
		if react > 0 then
			text_center = format('%.1f', react)
		end
	end
	if Player.cd and Player.cd.requires_react then
		local react = Player.cd:React()
		if react > 0 then
			text_cd = format('%.1f', react)
		end
	end
	if Player.meta_active then
		text_tr = format('%.1fs', Player.meta_remains)
	end
	if Player.soul_fragments > 0 then
		text_tl = Player.soul_fragments
	end
	if Player.main and Player.main_freecast then
		if not lasikPanel.freeCastOverlayOn then
			lasikPanel.freeCastOverlayOn = true
			lasikPanel.border:SetTexture(ADDON_PATH .. 'freecast.blp')
		end
	elseif lasikPanel.freeCastOverlayOn then
		lasikPanel.freeCastOverlayOn = false
		lasikPanel.border:SetTexture(ADDON_PATH .. 'border.blp')
	end

	lasikPanel.dimmer:SetShown(dim)
	lasikPanel.text.center:SetText(text_center)
	lasikPanel.text.tl:SetText(text_tl)
	lasikPanel.text.tr:SetText(text_tr)
	--lasikPanel.text.bl:SetText(format('%.1fs', Target.timeToDie))
	lasikCooldownPanel.text:SetText(text_cd)
	lasikCooldownPanel.dimmer:SetShown(dim_cd)
end

function UI:UpdateCombat()
	timer.combat = 0

	Player:Update()

	Player.main = APL[Player.spec]:Main()
	if Player.main then
		lasikPanel.icon:SetTexture(Player.main.icon)
		Player.main_freecast = (Player.main.fury_cost > 0 and Player.main:FuryCost() == 0)
	end
	if Player.cd then
		lasikCooldownPanel.icon:SetTexture(Player.cd.icon)
		if Player.cd.spellId then
			local start, duration = GetSpellCooldown(Player.cd.spellId)
			lasikCooldownPanel.swipe:SetCooldown(start, duration)
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
	if Opt.frequency - timer.combat > seconds then
		timer.combat = max(seconds, Opt.frequency - seconds)
	end
end

-- End UI API

-- Start Event Handling

function events:ADDON_LOADED(name)
	if name == ADDON then
		Opt = Lasik
		if not Opt.frequency then
			print('It looks like this is your first time running ' .. ADDON .. ', why don\'t you take some time to familiarize yourself with the commands?')
			print('Type |cFFFFD000' .. SLASH_Lasik1 .. '|r for a list of commands.')
		end
		if UnitLevel('player') < 10 then
			print('[|cFFFFD000Warning|r] ' .. ADDON .. ' is not designed for players under level 10, and almost certainly will not operate properly!')
		end
		InitOpts()
		UI:UpdateDraggable()
		UI:UpdateAlpha()
		UI:UpdateScale()
		UI:SnapAllPanels()
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
	trackAuras:Remove(dstGUID)
	if Opt.auto_aoe then
		autoAoe:Remove(dstGUID)
	end
end

CombatEvent.SWING_DAMAGE = function(event, srcGUID, dstGUID, amount, overkill, spellSchool, resisted, blocked, absorbed, critical, glancing, crushing, offHand)
	if srcGUID == Player.guid then
		Player:ResetSwing(not offHand, offHand)
		if Opt.auto_aoe then
			autoAoe:Add(dstGUID, true)
		end
	elseif dstGUID == Player.guid then
		Player.swing.last_taken = Player.time
		if Opt.auto_aoe then
			autoAoe:Add(srcGUID, true)
		end
	end
end

CombatEvent.SWING_MISSED = function(event, srcGUID, dstGUID, missType, offHand, amountMissed)
	if srcGUID == Player.guid then
		Player:ResetSwing(not offHand, offHand, true)
		if Opt.auto_aoe and not (missType == 'EVADE' or missType == 'IMMUNE') then
			autoAoe:Add(dstGUID, true)
		end
	elseif dstGUID == Player.guid then
		Player.swing.last_taken = Player.time
		if Opt.auto_aoe then
			autoAoe:Add(srcGUID, true)
		end
	end
end

CombatEvent.SPELL = function(event, srcGUID, dstGUID, spellId, spellName, spellSchool, missType, overCap, powerType)
	if srcGUID ~= Player.guid then
		return
	end
	local ability = spellId and abilities.bySpellId[spellId]
	if not ability then
		--print(format('EVENT %s TRACK CHECK FOR UNKNOWN %s ID %d', event, type(spellName) == 'string' and spellName or 'Unknown', spellId or 0))
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
		return -- ignore buffs beyond here
	end
	if Opt.auto_aoe then
		if event == 'SPELL_MISSED' and (missType == 'EVADE' or missType == 'IMMUNE') then
			autoAoe:Remove(dstGUID)
		elseif ability.auto_aoe and (event == ability.auto_aoe.trigger or ability.auto_aoe.trigger == 'SPELL_AURA_APPLIED' and event == 'SPELL_AURA_REFRESH') then
			ability:RecordTargetHit(dstGUID)
		end
	end
	if event == 'SPELL_DAMAGE' or event == 'SPELL_ABSORBED' or event == 'SPELL_MISSED' or event == 'SPELL_AURA_APPLIED' or event == 'SPELL_AURA_REFRESH' then
		ability:CastLanded(dstGUID, event, missType)
	end
end

function events:COMBAT_LOG_EVENT_UNFILTERED()
	CombatEvent.TRIGGER(CombatLogGetCurrentEventInfo())
end

function events:PLAYER_TARGET_CHANGED()
	Target:Update()
end

function events:UNIT_FACTION(unitId)
	if unitId == 'target' then
		Target:Update()
	end
end

function events:UNIT_FLAGS(unitId)
	if unitId == 'target' then
		Target:Update()
	end
end

function events:UNIT_HEALTH(unitId)
	if unitId == 'player' then
		Player.health.current = UnitHealth('player')
		Player.health.max = UnitHealthMax('player')
		Player.health.pct = Player.health.current / Player.health.max * 100
	end
end

function events:UNIT_SPELLCAST_START(unitId, castGUID, spellId)
	if Opt.interrupt and unitId == 'target' then
		UI:UpdateCombatWithin(0.05)
	end
end

function events:UNIT_SPELLCAST_STOP(unitId, castGUID, spellId)
	if Opt.interrupt and unitId == 'target' then
		UI:UpdateCombatWithin(0.05)
	end
end
events.UNIT_SPELLCAST_FAILED = events.UNIT_SPELLCAST_STOP
events.UNIT_SPELLCAST_INTERRUPTED = events.UNIT_SPELLCAST_STOP

--[[
function events:UNIT_SPELLCAST_SENT(unitId, destName, castGUID, spellId)
	if unitId ~= 'player' or not spellId or castGUID:sub(6, 6) ~= '3' then
		return
	end
	local ability = abilities.bySpellId[spellId]
	if not ability then
		return
	end
end
]]

function events:UNIT_SPELLCAST_SUCCEEDED(unitId, castGUID, spellId)
	if unitId ~= 'player' or not spellId or castGUID:sub(6, 6) ~= '3' then
		return
	end
	local ability = abilities.bySpellId[spellId]
	if not ability then
		return
	end
	if ability.traveling then
		ability.next_castGUID = castGUID
	end
end

function events:PLAYER_REGEN_DISABLED()
	Player.combat_start = GetTime() - Player.time_diff
end

function events:PLAYER_REGEN_ENABLED()
	Player.combat_start = 0
	Player.swing.last_taken = 0
	Target.estimated_range = 30
	wipe(Player.previous_gcd)
	if Player.last_ability then
		Player.last_ability = nil
		lasikPreviousPanel:Hide()
	end
	for _, ability in next, abilities.velocity do
		for guid in next, ability.traveling do
			ability.traveling[guid] = nil
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

	Player:ResetSwing(true, true)
	Player:UpdateAbilities()
end

function events:PLAYER_SPECIALIZATION_CHANGED(unitId)
	if unitId ~= 'player' then
		return
	end
	Player.spec = GetSpecialization() or 0
	lasikPreviousPanel.ability = nil
	Player:SetTargetMode(1)
	events:PLAYER_EQUIPMENT_CHANGED()
	events:PLAYER_REGEN_ENABLED()
	UI.OnResourceFrameShow()
	Player:Update()
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

function events:PLAYER_PVP_TALENT_UPDATE()
	Player:UpdateAbilities()
end

function events:SOULBIND_ACTIVATED()
	Player:UpdateAbilities()
end

function events:SOULBIND_NODE_UPDATED()
	Player:UpdateAbilities()
end

function events:SOULBIND_PATH_CHANGED()
	Player:UpdateAbilities()
end

function events:ACTIONBAR_SLOT_CHANGED()
	UI:UpdateGlows()
end

function events:GROUP_ROSTER_UPDATE()
	Player.group_size = max(1, min(40, GetNumGroupMembers()))
end

function events:PLAYER_ENTERING_WORLD()
	Player:Init()
	Target:Update()
	C_Timer.After(5, function() events:PLAYER_EQUIPMENT_CHANGED() end)
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
for event in next, events do
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
	print(ADDON, '-', desc .. ':', opt_view, ...)
end

SlashCmdList[ADDON] = function(msg, editbox)
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
			Opt.alpha = max(0, min(100, tonumber(msg[2]) or 100)) / 100
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
				Opt.glow.color.r = max(0, min(1, tonumber(msg[3]) or 0))
				Opt.glow.color.g = max(0, min(1, tonumber(msg[4]) or 0))
				Opt.glow.color.b = max(0, min(1, tonumber(msg[5]) or 0))
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
		lasikPanel:ClearAllPoints()
		lasikPanel:SetPoint('CENTER', 0, -169)
		UI:SnapAllPanels()
		return Status('Position has been reset to', 'default')
	end
	print(ADDON, '(version: |cFFFFD000' .. GetAddOnMetadata(ADDON, 'Version') .. '|r) - Commands:')
	for _, cmd in next, {
		'locked |cFF00C000on|r/|cFFC00000off|r - lock the ' .. ADDON .. ' UI so that it can\'t be moved',
		'snap |cFF00C000above|r/|cFF00C000below|r/|cFFC00000off|r - snap the ' .. ADDON .. ' UI to the Personal Resource Display',
		'scale |cFFFFD000prev|r/|cFFFFD000main|r/|cFFFFD000cd|r/|cFFFFD000interrupt|r/|cFFFFD000extra|r/|cFFFFD000glow|r - adjust the scale of the ' .. ADDON .. ' UI icons',
		'alpha |cFFFFD000[percent]|r - adjust the transparency of the ' .. ADDON .. ' UI icons',
		'frequency |cFFFFD000[number]|r - set the calculation frequency (default is every 0.2 seconds)',
		'glow |cFFFFD000main|r/|cFFFFD000cd|r/|cFFFFD000interrupt|r/|cFFFFD000extra|r/|cFFFFD000blizzard|r |cFF00C000on|r/|cFFC00000off|r - glowing ability buttons on action bars',
		'glow color |cFFF000000.0-1.0|r |cFF00FF000.1-1.0|r |cFF0000FF0.0-1.0|r - adjust the color of the ability button glow',
		'previous |cFF00C000on|r/|cFFC00000off|r - previous ability icon',
		'always |cFF00C000on|r/|cFFC00000off|r - show the ' .. ADDON .. ' UI without a target',
		'cd |cFF00C000on|r/|cFFC00000off|r - use ' .. ADDON .. ' for cooldown management',
		'swipe |cFF00C000on|r/|cFFC00000off|r - show spell casting swipe animation on main ability icon',
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
