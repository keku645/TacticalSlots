-- TacticalSlots -- shared: the M18 smoke grenade, the grenade slot that offers it, and the player's choice.
--
-- THE WEAPON. The game has no M18 to throw (no unlock, blueprint or hand mesh), so ours is the M67 copied in memory with guids of its
-- own: the M67's animation, aiming, sounds and HUD, with
--   - in the hand (1st and 3rd person) an M18 mesh shipped in our superbundle, on the M67's own two bones (body and pin ring, so the
--     M67's pin pull moves its ring), drawn with the game's own M18 textures;
--   - thrown, the canister the game already has (fx/meshparticles/weapons/m18_smokegrenade), on a collision of its own: one capsule
--     the size of the canister, so it rolls like a can (the M67's is its own ball-shaped hull);
--   - on detonation, no damage, the area unspotted, and the game's red signal smoke turned grey (the 40 mm smoke's colours).
-- The meshes, the projectile and its collision come in our superbundle (tacticalslots/smoke, loaded with the machete's); the copies
-- are made here, with the same guids in both realms, and registered for the network.
-- ⛔ The weapon blueprint's NAME stays the M67's (renamed, the grenade is invisible, and after a kit change every weapon is).
--
-- THE GRENADE SLOT. Every kit's weapon table has a grenade part listing [M67]. The client sends the FIRST grenade of that list when the
-- player deploys (as with the knife), so the choice is the order of that list on the player's own client; the smoke is added to the
-- list in both realms.
--
-- THE CHOICE. The deploy screen's grenade slot (KnifeTab.lua hears "GRF<key>") calls TACTICALSLOTS_GRENADE_CHOOSE: the choice is put first
-- in every kit's list, written into the screen's mailbox (GrenadeSelSet) and kept by the server (mod.db, table grenade).

-- ---- knobs ------------------------------------------------------------------------------------------------------------------
local SMOKE_ENABLED = true            -- false: no smoke at all (the grenade slot offers the M67 only, as before)
local DEFAULT_GRENADE = "m67"         -- what the game sends when the player has not chosen: "m67" | "smoke"

local FUSE_SECONDS = 1.5              -- from the throw to the smoke (the M67's fuse is 3.6)
local MIN_BOUNCE_SPEED = 0.5          -- below this the canister stops bouncing (the M67's: 0.5)
local COLLISION_SPEED_MULTIPLIER = 0.3 -- speed kept at each bounce (the M67's: 0.3)
local UNSPOTTABLE_SECONDS = 10.0      -- players in the smoke cannot be spotted for this long (the 40 mm smoke's: 10)

local SMOKE_COLOR_START = 0.9         -- grey of the plume as it leaves the canister (the 40 mm smoke's: 0.9)
local SMOKE_COLOR_END = 0.8           -- grey as it ages (the 40 mm smoke's: 0.8)
local SMOKE_COLOR_CURVE = Vec4(0.0, 0.0, -1.31976759, 1.00892854) -- the 40 mm smoke's colour curve
local PLUME_SIZE_SCALE = 1.0          -- size of the main plume's particles (1 = the signal smoke's)
local PUFF_EMISSIVE = false           -- the first puff glowing (the red signal's does; a grey smoke should not)
local PUFF_TIME_SCALE = 0.3           -- the first puff's pace (the signal's: 1)

-- The smoke comes out PARALLEL TO THE GROUND. The jet leaves along the emitter's local Z (each particle's direction
-- is drawn from x -0.1..0.1, y LIFT_MIN..LIFT_MAX, z 1: the signal's y is 0.05..0.2), turned horizontal and out of the canister's top
-- (the canister lies along -Z, see GreySmoke); the signal smoke's "gravity" (-0.5) is what makes it climb.
local JET_LIFT_MIN = 0.0              -- vertical spread of the jet, lowest (the signal's: 0.05)
local JET_LIFT_MAX = 0.03             -- vertical spread of the jet, highest (the signal's: 0.2)
local PLUME_RISE = 0.0                -- the particles' gravity: 0 = the smoke stays level; -0.5 = it climbs like the signal's
local JET_HEIGHT = 0.03               -- height of the jet's mouth over the ground (m)
local JET_AHEAD = 0.0                 -- the mouth's distance ahead of the canister's top, along the jet (m)

-- The smoke must END. The signal smoke is an ambient effect that never stops (its emitters repeat, its hiss loops
-- until something stops it, and nothing stops a detonation's effect); ours emit once:
local SMOKE_SECONDS = 10.0            -- how long the plume pours out (the signal's own cycle: 5 / 0.5 = 10); then it thins out (6 s)
local PUFF_SECONDS = 10.0             -- how long the dense puff at the mouth lasts
local CANISTER_SECONDS = 16.0         -- how long the canister lies on the ground after it goes off (the smoke + its thinning out)
local SMOKE_SOUND = "hiss"            -- "hiss" = the signal smoke's own hiss, played on its own and stopped when the smoke stops
                                      -- pouring (SMOKE_SECONDS: it loops until stopped); "pop" = the game's smoke grenade sound (the
                                      -- 40 mm smoke's); "none"

-- The effect's own canister (a particle mesh) is never drawn in multiplayer, while the very same mesh flies fine as the thrown
-- grenade. So the canister and the smoke are put down HERE, on every client, when a smoke grenade goes away
-- (it detonates): the canister as a plain mesh where and as the grenade came to rest (laid on the ground if it went off in the air or
-- standing), the smoke out of its top, level, along it. false: the detonation plays the smoke itself (fixed direction, no canister).
local SMOKE_BY_LUA = true

local CANISTER_CLEARANCE = 0.005      -- gap left between the lying canister and the ground (m): never in it
local CANISTER_MAX_SLOPE = 0.7        -- steeper than this between its two ends (a step, a ledge): it lies level on the highest contact
local CANISTER_STEP = 0.02            -- a lift above this (m) means a step under it: it lies level on its footprint's highest point
-- -----------------------------------------------------------------------------------------------------------------------------

local IS_CLIENT = SharedUtils:IsClientModule()

local function LOG(p_Text)
	if _G.TACTICALSLOTS_LOG ~= nil then
		_G.TACTICALSLOTS_LOG("[smoke] " .. tostring(p_Text))
	elseif _G.TACTICALSLOTS_PRINTS then
		print("[TacticalSlots][smoke] " .. tostring(p_Text))
	end
end

-- ---- the game's pieces --------------------------------------------------------------------------------------------------------
local M67_UNLOCK_PART = Guid("31EBAC8C-F32E-11DF-8153-F8368A2EF9E0")
local M67_UNLOCK_INST = Guid("9F789F05-CE7B-DADC-87D7-16E847DBDD09")

local SIGNAL_PART = Guid("905AE573-09EB-4A66-8AF7-8CFB7B50E3BB")
local SIGNAL_BP_INST = Guid("C8BB7647-878A-4465-A8F2-1F4C2119B2C3")

local CANISTER_PART = Guid("4B3767C6-6031-4ECB-6B36-55C730861F96")
local CANISTER_INST = Guid("823F3022-8F9B-1318-6669-E0330A20E8CB")
-- the canister mesh's bounds (measured): x -0.0362..0.0300, y -0.0736..0.0519 (its axis; the top at +y), z -0.0346..0.0312
local CANISTER_CENTRE_X = 0.0031      -- centres it on the jet
local CANISTER_REST_HEIGHT = 0.0346   -- lifts its lowest side onto the ground

local SMOKE_POP_SOUND = "Sound/Explosions/ModularModel/Explosion_Smokegrenade"

-- the 40 mm smoke's explosion material (physics material 0): the M67's (56, the frag's) plays the frag's impact effects and sound
local MATERIALS_PART = Guid("B50615C2-4743-4919-9A40-A738150DEBE9")
local SMOKE_EXPLOSION_MATERIAL = Guid("F8B64F95-63CE-40D8-BEFE-1CA74C404176")

-- ---- ours (in the superbundle; instance guids of the meshes are the M67's, kept by the mesh clone) --------------------------
local MESH_1P_PART = Guid("6B4E1801-0001-4D18-8018-000000000001")
local MESH_1P_INST = Guid("ECB55FAC-CA19-1433-75D7-D0CA50C48798")
local MESH_3P_PART = Guid("6B4E1801-0001-4D18-8018-000000000003")
local MESH_3P_INST = Guid("388539AF-C6EA-C4B3-5577-3CC232B89519")

local PROJ_PART = Guid("6B4E1801-0004-4D18-8018-000000000001")
local PROJ_BP_INST = Guid("6B4E1801-0004-4D18-8018-000000000002")
local PROJ_DATA_INST = Guid("6B4E1801-0004-4D18-8018-000000000003")
local PROJ_EXPLOSION_INST = Guid("6B4E1801-0004-4D18-8018-000000000005")

-- ---- the copies made here (fixed: the same in both realms) ----------------------------------------------------------------------
local SMOKE_UNLOCK_INST = Guid("6B4E1801-0005-4D18-8018-000000000001")
local SMOKE_BP_INST = Guid("6B4E1801-0005-4D18-8018-000000000002")
local SMOKE_WEAPON_INST = Guid("6B4E1801-0005-4D18-8018-000000000003")
local SMOKE_FIRING_INST = Guid("6B4E1801-0005-4D18-8018-000000000004")
local SMOKE_FIRE_INST = Guid("6B4E1801-0005-4D18-8018-000000000005")
local SMOKE_UNLOCK_NAME = "Weapons/M18/U_M18_Smoke"
local SMOKE_IDENTIFIER = 3105181818   -- a number of our own: the unlock's identity on the network (the M67's is 1049314494)

local FX_GUID_PREFIX = "6B4E1801-0006-4D18-8018-0000000000"   -- + two hex digits, in the order the copies are made

local GRENADES = {
	m67 = "Weapons/M67/U_M67",
	smoke = SMOKE_UNLOCK_NAME,
}

local TEAMS = { "US", "RU" }
local CLASSES = { "Assault", "Engineer", "Support", "Recon" }
local KIT_SUFFIXES = { "", "_GM", "_XP4", "_GM_XP4", "_XP4_SCV" }

local m_Built = false
local m_Chosen = DEFAULT_GRENADE
local m_GrenadeParts = {}   -- this level's kits' grenade lists: { part, kit, kept }
local m_ByKey = {}          -- this level's grenade unlocks by key
local m_FxGuid = 0

-- the canister and the smoke put down by the script (client)
local m_SmokeEffect = nil   -- our grey smoke (EffectBlueprint)
local m_HissEffect = nil    -- the signal's hiss on its own (EffectBlueprint), stopped when the smoke stops pouring
local m_CanisterData = nil  -- a StaticModelEntityData drawing the canister mesh
local m_Grenades = {}       -- smoke grenades in the world: uniqueId -> { entity, transform }
local m_Gone = {}           -- grenades that went away this frame: their last transform (handled in the PreSim pass: raycasts)
local m_Down = {}           -- canisters on the ground: { entity, effect, age }
local m_Logged = 0          -- smokes logged this level (the first few, to the mod's database)

local function NextFxGuid()
	m_FxGuid = m_FxGuid + 1
	return Guid(FX_GUID_PREFIX .. string.format("%02X", m_FxGuid))
end

local function Cast(p_Instance)
	if p_Instance == nil then
		return nil
	end

	return _G[p_Instance.typeInfo.name](p_Instance)
end

local function Writable(p_Instance)
	local s_Instance = Cast(p_Instance)

	if s_Instance ~= nil and s_Instance.isReadOnly then
		s_Instance:MakeWritable()
	end

	return s_Instance
end

local function Copy(p_Instance, p_Guid)
	return Cast(p_Instance:Clone(p_Guid))
end

local function NameOf(p_Unlock)
	local s_Name = "?"
	pcall(function() s_Name = tostring(UnlockAssetBase(p_Unlock).name) end)
	return s_Name
end

local function KeyOf(p_Name)
	for l_Key, l_Name in pairs(GRENADES) do
		if string.lower(l_Name) == string.lower(p_Name) then
			return l_Key
		end
	end

	return nil
end

-- ---- the grey smoke: the signal smoke's effect copied, its two smoke emitters copied and turned grey -------------------------
-- Only the copies are touched (the red signal smoke a level places stays red): an emitter's processors are a chain, so the WHOLE
-- chain is copied (and the evaluators we change), and only the copies are edited.
local function GreyEmitter(p_Document, p_Role)
	local s_Document = Copy(p_Document, NextFxGuid())
	local s_Template = Copy(s_Document.templateData, NextFxGuid())
	s_Document.templateData = s_Template

	local s_Head, s_Previous, s_Node, s_Colours = nil, nil, s_Document.rootProcessor, 0
	local s_Steps = 0
	local s_Level = {}

	while s_Node ~= nil and s_Steps < 64 do
		s_Steps = s_Steps + 1
		local l_Copy = Copy(s_Node, NextFxGuid())

		if s_Previous == nil then
			s_Head = l_Copy
		else
			s_Previous.nextProcessor = l_Copy
		end

		if p_Role == "canister" then
			-- the canister only lives as long as the smoke (the particle's own age is what removes it)
			if l_Copy.typeInfo.name == "UpdateAgeData" then
				l_Copy.lifetime = CANISTER_SECONDS
				s_Level[#s_Level + 1] = "lies " .. tostring(CANISTER_SECONDS) .. " s"
			end
		elseif l_Copy.typeInfo.name == "SpawnDirectionData" then
			if l_Copy.pre ~= nil and l_Copy.pre.typeInfo.name == "RandomXYZEvaluatorData" then
				local l_Spread = Copy(l_Copy.pre, NextFxGuid())
				l_Spread.minY = JET_LIFT_MIN
				l_Spread.maxY = JET_LIFT_MAX
				l_Copy.pre = l_Spread
				s_Level[#s_Level + 1] = "jet level"
			end
		elseif l_Copy.typeInfo.name == "GravityData" then
			l_Copy.gravity = PLUME_RISE
			s_Level[#s_Level + 1] = "rise " .. tostring(PLUME_RISE)
		elseif l_Copy.typeInfo.name == "UpdateColorData" then
			l_Copy.color = Vec3(1.0, 1.0, 1.0)
			l_Copy.defaultValues = Vec4(1.0, 1.0, 1.0, 1.0)

			if l_Copy.pre ~= nil and l_Copy.pre.typeInfo.name == "PolynomialColorInterpData" then
				local l_Curve = Copy(l_Copy.pre, NextFxGuid())
				l_Curve.color0 = Vec3(SMOKE_COLOR_START, SMOKE_COLOR_START, SMOKE_COLOR_START)
				l_Curve.color1 = Vec3(SMOKE_COLOR_END, SMOKE_COLOR_END, SMOKE_COLOR_END)
				l_Curve.coefficients = SMOKE_COLOR_CURVE
				l_Copy.pre = l_Curve
			end

			s_Colours = s_Colours + 1
		elseif l_Copy.typeInfo.name == "SpawnSizeData" and p_Role == "plume" and PLUME_SIZE_SCALE ~= 1.0 then
			l_Copy.size = l_Copy.size * PLUME_SIZE_SCALE
		end

		s_Previous = l_Copy
		s_Node = l_Copy.nextProcessor
	end

	s_Document.rootProcessor = s_Head
	s_Template.rootProcessor = s_Head

	if p_Role == "puff" then
		s_Template.emissive = PUFF_EMISSIVE
		s_Template.timeScale = PUFF_TIME_SCALE
	end

	-- once, not forever: an emitter's Lifetime runs in its own time (TimeScale), so the seconds are scaled into it
	local s_Seconds = (p_Role == "plume" and SMOKE_SECONDS) or (p_Role == "puff" and PUFF_SECONDS) or CANISTER_SECONDS
	s_Template.repeatParticleSpawning = false
	s_Template.lifetime = s_Seconds * s_Template.timeScale
	s_Level[#s_Level + 1] = string.format("once, %g s", s_Seconds)

	return s_Document, s_Colours, s_Steps, table.concat(s_Level, ", ")
end

local function GreySmoke()
	local s_Original = ResourceManager:FindInstanceByGuid(SIGNAL_PART, SIGNAL_BP_INST)

	if s_Original == nil then
		return nil, "the signal smoke is not loaded"
	end

	m_FxGuid = 0
	local s_Blueprint = Copy(s_Original, NextFxGuid())
	local s_Effect = Copy(s_Blueprint.object, NextFxGuid())
	s_Blueprint.object = s_Effect
	s_Blueprint.name = "FX/TacticalSlots/FX_M18_Smoke_Grey"

	local s_Said = {}
	local s_Drop = {}
	local s_Hiss = nil

	for i = 1, #s_Effect.components do
		local l_Component = s_Effect.components[i]

		if l_Component ~= nil and l_Component.typeInfo.name == "SoundEffectEntityData" then
			-- the signal's hiss loops until stopped, so it rides an effect of its own that the script stops when the smoke stops
			-- pouring (stopping the smoke's effect would cut the smoke); or the game's smoke grenade sound; or none
			local l_Pop = ResourceManager:SearchForDataContainer(SMOKE_POP_SOUND)

			if SMOKE_SOUND == "hiss" and SMOKE_BY_LUA then
				s_Hiss = Copy(s_Original, NextFxGuid())
				local l_HissEffect = Copy(s_Hiss.object, NextFxGuid())
				l_HissEffect.components:clear()
				l_HissEffect.components:add(l_Component)
				s_Hiss.object = l_HissEffect
				s_Hiss.name = "FX/TacticalSlots/FX_M18_Smoke_Hiss"
				s_Drop[#s_Drop + 1] = i
				s_Said[#s_Said + 1] = "sound: the signal's hiss (its own effect)"
			elseif SMOKE_SOUND == "pop" and l_Pop ~= nil then
				local l_Sound = Copy(l_Component, NextFxGuid())
				l_Sound.sound = SoundAsset(l_Pop)
				s_Effect.components[i] = l_Sound
				s_Said[#s_Said + 1] = "sound: the smoke grenade's"
			else
				s_Drop[#s_Drop + 1] = i
				s_Said[#s_Said + 1] = SMOKE_SOUND == "pop" and "sound: none (the smoke grenade's is not loaded)" or "sound: none"
			end
		elseif l_Component ~= nil and l_Component.typeInfo.name == "EmitterEntityData" then
			local l_Emitter = Copy(l_Component, NextFxGuid())
			local l_Name = string.lower(tostring(EmitterDocument(l_Emitter.emitter).name))

			-- the canister: put down by this script (SMOKE_BY_LUA), so the effect's own goes; otherwise lying flat on the ground
			-- (its axis, the mesh's Y, along -Z; its side on the ground), its top where the jets come out. The jets: their local Z
			-- (the jet) along -Z, level, their local Y up.
			if l_Name:find("grenademesh") and SMOKE_BY_LUA then
				s_Drop[#s_Drop + 1] = i
				s_Said[#s_Said + 1] = "canister: put down by the script"
			elseif l_Name:find("grenademesh") then
				l_Emitter.transform = LinearTransform(Vec3(1.0, 0.0, 0.0), Vec3(0.0, 0.0, -1.0), Vec3(0.0, 1.0, 0.0),
					Vec3(CANISTER_CENTRE_X, CANISTER_REST_HEIGHT, 0.0))
				local l_Document, _, l_Steps, l_Level = GreyEmitter(l_Emitter.emitter, "canister")
				l_Emitter.emitter = l_Document
				s_Said[#s_Said + 1] = string.format("canister (%s; %d processor(s) copied)", l_Level, l_Steps)
			else
				-- the mouth: the effect's origin is the canister's top when the script plays it; the canister's centre (top at
				-- -0.052 along -Z) when the detonation does
				l_Emitter.transform = LinearTransform(Vec3(-1.0, 0.0, 0.0), Vec3(0.0, 1.0, 0.0), Vec3(0.0, 0.0, -1.0),
					Vec3(0.0, JET_HEIGHT, (SMOKE_BY_LUA and 0.0 or -0.052) - JET_AHEAD))
				local l_Role = l_Name:find("initsmoke") and "puff" or "plume"
				local l_Document, l_Colours, l_Steps, l_Level = GreyEmitter(l_Emitter.emitter, l_Role)
				l_Emitter.emitter = l_Document
				s_Said[#s_Said + 1] = string.format("%s grey (%d colour; %s; %d processor(s) copied)", l_Role, l_Colours, l_Level, l_Steps)
			end

			s_Effect.components[i] = l_Emitter
		end
	end

	for d = #s_Drop, 1, -1 do
		s_Effect.components:erase(s_Drop[d])
	end

	local s_Partition = ResourceManager:FindDatabasePartition(SIGNAL_PART)

	if s_Partition ~= nil then
		s_Partition:AddInstance(s_Blueprint)

		if s_Hiss ~= nil then
			s_Partition:AddInstance(s_Hiss)
		end
	end

	return s_Blueprint, table.concat(s_Said, ", "), s_Hiss
end

-- ---- the weapon -----------------------------------------------------------------------------------------------------------------
local function MakeWeapon(p_Effect)
	local s_M67 = ResourceManager:FindInstanceByGuid(M67_UNLOCK_PART, M67_UNLOCK_INST)
	local s_Mesh1p = ResourceManager:FindInstanceByGuid(MESH_1P_PART, MESH_1P_INST)
	local s_Mesh3p = ResourceManager:FindInstanceByGuid(MESH_3P_PART, MESH_3P_INST)
	local s_ProjectileBp = ResourceManager:FindInstanceByGuid(PROJ_PART, PROJ_BP_INST)
	local s_Projectile = ResourceManager:FindInstanceByGuid(PROJ_PART, PROJ_DATA_INST)
	local s_Explosion = ResourceManager:FindInstanceByGuid(PROJ_PART, PROJ_EXPLOSION_INST)
	local s_Canister = ResourceManager:FindInstanceByGuid(CANISTER_PART, CANISTER_INST)

	local s_Missing = {}
	for l_Name, l_Instance in pairs({ m67 = s_M67, mesh1p = s_Mesh1p, mesh3p = s_Mesh3p, projectileBlueprint = s_ProjectileBp,
		projectile = s_Projectile, explosion = s_Explosion, canister = s_Canister }) do
		if l_Instance == nil then
			s_Missing[#s_Missing + 1] = l_Name
		end
	end

	if #s_Missing > 0 then
		return nil, "not loaded: " .. table.concat(s_Missing, ", ")
	end

	-- the thrown canister: the game's own mesh on our collision, our fuse, a smoke grenade (no frag warning on the HUD)
	s_Projectile = Writable(s_Projectile)
	s_Projectile.mesh = RigidMeshAsset(s_Canister)
	s_Projectile.timeToLive = FUSE_SECONDS
	s_Projectile.detonateOnTimeout = true
	s_Projectile.minBounceSpeed = MIN_BOUNCE_SPEED
	s_Projectile.collisionSpeedMultiplier = COLLISION_SPEED_MULTIPLIER
	s_Projectile.grenadeType = GrenadeType.GrenadeType_Smoke

	-- the detonation: no damage, no blast, the area unspotted, the grey smoke
	s_Explosion = Writable(s_Explosion)
	s_Explosion.blastDamage = 0.0
	s_Explosion.blastRadius = 0.0
	s_Explosion.innerBlastRadius = 0.0
	s_Explosion.blastImpulse = 0.0
	s_Explosion.shockwaveDamage = 0.0
	s_Explosion.shockwaveRadius = 0.0
	s_Explosion.shockwaveImpulse = 0.0
	s_Explosion.shockwaveTime = 0.0
	s_Explosion.cameraShockwaveRadius = 0.0
	s_Explosion.hasStunEffect = false
	s_Explosion.triggerImpairedHearing = false
	s_Explosion.isCausingSuppression = false
	s_Explosion.unspotsOnExplode = true
	s_Explosion.unspottableTime = UNSPOTTABLE_SECONDS

	-- the 40 mm smoke's explosion material, not the frag's: the M67's material is what still played the frag's explosion sound
	local s_Material = ResourceManager:FindInstanceByGuid(MATERIALS_PART, SMOKE_EXPLOSION_MATERIAL)
	local s_MaterialSaid = "material: the frag's (the smoke's not loaded)"

	if s_Material ~= nil then
		s_Explosion.materialPair = MaterialContainerPair(s_Material)
		s_MaterialSaid = "material: the 40 mm smoke's"
	end
	-- the smoke: played by this script where the canister lies (SMOKE_BY_LUA), or by the detonation itself
	s_Explosion.detonationEffect = (not SMOKE_BY_LUA) and p_Effect or nil

	-- the weapon: the M67 copied unlock -> blueprint -> weapon data -> firing -> primary fire, each with our guid
	local s_Unlock = Copy(s_M67, SMOKE_UNLOCK_INST)
	s_Unlock.name = SMOKE_UNLOCK_NAME
	s_Unlock.debugUnlockId = "U_M18_Smoke"
	s_Unlock.identifier = SMOKE_IDENTIFIER

	local s_Blueprint = Copy(s_Unlock.weapon, SMOKE_BP_INST)   -- its name stays the M67's (see the header)
	s_Unlock.weapon = s_Blueprint

	local s_Weapon = Copy(s_Blueprint.object, SMOKE_WEAPON_INST)
	s_Blueprint.object = s_Weapon
	s_Weapon.soldierWeaponBlueprint = s_Blueprint
	s_Weapon.damageGiverName = "M18"

	local s_Firing = Copy(s_Weapon.weaponFiring, SMOKE_FIRING_INST)
	s_Weapon.weaponFiring = s_Firing

	local s_Fire = Copy(s_Firing.primaryFire, SMOKE_FIRE_INST)
	s_Firing.primaryFire = s_Fire
	s_Fire.shot.projectile = ProjectileBlueprint(s_ProjectileBp)
	s_Fire.shot.projectileData = GrenadeEntityData(s_Projectile)

	for i = 1, #s_Weapon.weaponStates do
		s_Weapon.weaponStates[i].mesh1p = SkinnedMeshAsset(s_Mesh1p)
		s_Weapon.weaponStates[i].meshZoom1p = SkinnedMeshAsset(s_Mesh1p)
		s_Weapon.weaponStates[i].mesh3p = SkinnedMeshAsset(s_Mesh3p)
	end

	local s_Partition = ResourceManager:FindDatabasePartition(M67_UNLOCK_PART)

	if s_Partition ~= nil then
		s_Partition:AddInstance(s_Unlock)
	end

	-- the same, in the same order, in both realms (network ids)
	local s_Registry = RegistryContainer()
	s_Registry.assetRegistry:add(s_Unlock)
	s_Registry.blueprintRegistry:add(s_Blueprint)
	s_Registry.blueprintRegistry:add(ProjectileBlueprint(s_ProjectileBp))
	s_Registry.entityRegistry:add(s_Weapon)
	s_Registry.entityRegistry:add(GrenadeEntityData(s_Projectile))
	ResourceManager:AddRegistry(s_Registry, ResourceCompartment.ResourceCompartment_Game)

	return s_Unlock, string.format("%d weapon state(s) with the M18 meshes; explosion %s", #s_Weapon.weaponStates, s_MaterialSaid)
end

-- ---- the order of the grenade lists ---------------------------------------------------------------------------------------------
local function OrderFor(p_Kept)
	local s_Order = {}

	for _, l_Key in ipairs(p_Kept) do
		if l_Key ~= "smoke" and m_ByKey[l_Key] ~= nil then
			s_Order[#s_Order + 1] = l_Key
		end
	end

	if m_ByKey.smoke ~= nil then
		s_Order[#s_Order + 1] = "smoke"
	end

	if IS_CLIENT and m_ByKey[m_Chosen] ~= nil then
		for i = #s_Order, 1, -1 do
			if s_Order[i] == m_Chosen then
				table.remove(s_Order, i)
			end
		end

		table.insert(s_Order, 1, m_Chosen)
	end

	return s_Order
end

local function WriteList(p_Part, p_Order)
	p_Part:MakeWritable()
	p_Part.selectableUnlocks:clear()

	for _, l_Key in ipairs(p_Order) do
		p_Part.selectableUnlocks:add(m_ByKey[l_Key])
	end
end

local function ListText(p_Part)
	local s_Now = {}

	for u = 1, #p_Part.selectableUnlocks do
		s_Now[#s_Now + 1] = KeyOf(NameOf(p_Part.selectableUnlocks[u])) or NameOf(p_Part.selectableUnlocks[u])
	end

	return "[" .. table.concat(s_Now, ", ") .. "]"
end

local function GrenadePartOf(p_Kit)
	local s_Table = p_Kit.weaponTable

	if s_Table == nil then
		return nil
	end

	for p = 1, #s_Table.unlockParts do
		local l_Part = s_Table.unlockParts[p]

		for u = 1, #l_Part.selectableUnlocks do
			if KeyOf(NameOf(l_Part.selectableUnlocks[u])) == "m67" then
				return l_Part, p
			end
		end
	end

	return nil
end

-- The deploy screen's grenade mailbox: every loaded copy of its GrenadeSelSet (collected by the screen's load handler in __init__).
local function WriteMailbox(p_Why)
	local s_Nodes = _G.TACTICALSLOTS_GRENADE_NODES or {}
	local s_Written = 0

	for _, l_Node in ipairs(s_Nodes) do
		local s_Ok, s_Err = pcall(function()
			l_Node:MakeWritable()
			l_Node.param = m_Chosen
		end)

		if s_Ok then
			s_Written = s_Written + 1
		else
			LOG("⛔ grenade mailbox (" .. tostring(p_Why) .. "): " .. tostring(s_Err))
		end
	end

	return s_Written, #s_Nodes
end

local function Build()
	local s_Effect, s_EffectSaid, s_Hiss = GreySmoke()

	if s_Effect == nil then
		LOG("⛔ " .. tostring(s_EffectSaid) .. ": our bundle did not come in -- no smoke this level")
		return
	end

	local s_Unlock, s_WeaponSaid = MakeWeapon(s_Effect)

	if s_Unlock == nil then
		LOG("⛔ the smoke grenade could not be made (" .. tostring(s_WeaponSaid) .. ") -- no smoke this level")
		return
	end

	m_ByKey = { smoke = s_Unlock }
	m_GrenadeParts = {}

	if IS_CLIENT and SMOKE_BY_LUA then
		m_SmokeEffect = s_Effect
		m_HissEffect = s_Hiss
		m_CanisterData = StaticModelEntityData()
		m_CanisterData.mesh = RigidMeshAsset(ResourceManager:FindInstanceByGuid(CANISTER_PART, CANISTER_INST))
		m_CanisterData.visible = true
	end

	local s_M67 = ResourceManager:SearchForDataContainer(GRENADES.m67)

	if s_M67 ~= nil then
		m_ByKey.m67 = SoldierWeaponUnlockAsset(s_M67)
	end

	local s_Said = {}

	for _, l_Team in ipairs(TEAMS) do
		for _, l_Class in ipairs(CLASSES) do
			for _, l_Suffix in ipairs(KIT_SUFFIXES) do
				local l_Name = "Gameplay/Kits/" .. l_Team .. l_Class .. l_Suffix
				local l_Found = ResourceManager:SearchForDataContainer(l_Name)

				if l_Found ~= nil then
					local l_Ok, l_Err = pcall(function()
						local l_Part, l_At = GrenadePartOf(SoldierCustomizationAsset(l_Found))

						if l_Part == nil then
							s_Said[#s_Said + 1] = l_Name .. ": no grenade list"
							return
						end

						local l_Kept = {}

						for u = 1, #l_Part.selectableUnlocks do
							local l_Key = KeyOf(NameOf(l_Part.selectableUnlocks[u]))

							if l_Key ~= nil then
								l_Kept[#l_Kept + 1] = l_Key
							end
						end

						WriteList(l_Part, OrderFor(l_Kept))
						m_GrenadeParts[#m_GrenadeParts + 1] = { part = l_Part, kit = l_Name, kept = l_Kept }

						if #m_GrenadeParts == 1 then
							s_Said[#s_Said + 1] = l_Name .. " part " .. tostring(l_At - 1) .. " now " .. ListText(l_Part)
						end
					end)

					if not l_Ok then
						s_Said[#s_Said + 1] = "⛔ " .. l_Name .. ": " .. tostring(l_Err)
					end
				end
			end
		end
	end

	m_Built = true
	LOG(string.format("smoke grenade made (%s; effect: %s); grenade list set in %d kit(s)%s; %s", s_WeaponSaid, s_EffectSaid,
		#m_GrenadeParts, IS_CLIENT and (", '" .. m_Chosen .. "' first") or " (server: the smoke added at the end)",
		table.concat(s_Said, " | ")))
end

if SMOKE_ENABLED then
	Events:Subscribe("Level:RegisterEntityResources", function()
		if m_Built or not _G.TACTICALSLOTS_SMOKE_MOUNTED then
			return
		end

		local s_Ok, s_Err = pcall(Build)

		if not s_Ok then
			LOG("⛔ build: " .. tostring(s_Err))
		end
	end)
end

-- ---- the choice (client) ------------------------------------------------------------------------------------------------------
local function Choose(p_Key, p_Why, p_Tell)
	local s_Key = tostring(p_Key)

	if GRENADES[s_Key] == nil then
		LOG("⛔ choose: '" .. s_Key .. "' is not a grenade of ours (" .. tostring(p_Why) .. ")")
		return
	end

	m_Chosen = s_Key
	local s_Lists = 0

	for _, l_Entry in ipairs(m_GrenadeParts) do
		if pcall(function() WriteList(l_Entry.part, OrderFor(l_Entry.kept)) end) then
			s_Lists = s_Lists + 1
		end
	end

	local s_Mail, s_Copies = WriteMailbox(p_Why)

	if p_Tell then
		pcall(function() NetEvents:Send("TacticalSlots:GrenadeSet", s_Key) end)
	end

	LOG(string.format("grenade '%s' (%s): first in %d kit list(s)%s; mailbox %s", s_Key, tostring(p_Why), s_Lists,
		#m_GrenadeParts > 0 and (" -- " .. m_GrenadeParts[1].kit .. " " .. ListText(m_GrenadeParts[1].part)) or "",
		s_Copies > 0 and string.format("written in %d of %d copies", s_Mail, s_Copies) or "not loaded yet"))
end

if IS_CLIENT then
	_G.TACTICALSLOTS_GRENADE_CHOOSE = Choose

	_G.TACTICALSLOTS_GRENADE_SCREEN_LOADED = function()
		local s_Written, s_Copies = WriteMailbox("screen loaded")
		LOG(string.format("deploy screen loaded: grenade mailbox '%s' written in %d of %d copies", m_Chosen, s_Written, s_Copies))
	end

	NetEvents:Subscribe("TacticalSlots:GrenadeChoice", function(p_Key)
		Choose(p_Key, "kept by the server", false)
	end)

	Events:Subscribe("Level:LoadResources", function()
		pcall(function() NetEvents:Send("TacticalSlots:GrenadeAsk") end)
	end)
end

-- ---- the canister and the smoke, put down where a smoke grenade went off (client, SMOKE_BY_LUA) ---------------------------------
-- Every smoke grenade the client creates (the thrower's own and everybody else's) is followed; when it goes away (it went off) the
-- canister is put down as a plain mesh where it lay and the smoke is played out of its top, level, along it.
local CANISTER_TOP = 0.0519           -- the canister mesh's top along its axis (its local Y)
local CANISTER_BOTTOM = 0.0736        -- and its bottom (local Y -0.0736)
local RAY_FLAGS = RayCastFlags.CheckDetailMesh | RayCastFlags.DontCheckWater | RayCastFlags.DontCheckCharacter |
	RayCastFlags.DontCheckRagdoll | RayCastFlags.DontCheckPhantoms

local function Horizontal(p_V)
	local s_Length = math.sqrt(p_V.x * p_V.x + p_V.z * p_V.z)

	if s_Length < 0.2 then
		return nil
	end

	return Vec3(p_V.x / s_Length, 0.0, p_V.z / s_Length)
end

local function Unit(p_V)
	local s_Length = math.sqrt(p_V.x * p_V.x + p_V.y * p_V.y + p_V.z * p_V.z)

	if s_Length < 1e-6 then
		return nil
	end

	return Vec3(p_V.x / s_Length, p_V.y / s_Length, p_V.z / s_Length)
end

local function Dot(p_A, p_B)
	return p_A.x * p_B.x + p_A.y * p_B.y + p_A.z * p_B.z
end

local function Cross(p_A, p_B)
	return Vec3(p_A.y * p_B.z - p_A.z * p_B.y, p_A.z * p_B.x - p_A.x * p_B.z, p_A.x * p_B.y - p_A.y * p_B.x)
end

local function GroundUnder(p_X, p_Z, p_Y)
	return RaycastManager:Raycast(Vec3(p_X, p_Y + 0.6, p_Z), Vec3(p_X, p_Y - 3.0, p_Z), RAY_FLAGS)
end

-- The canister never clips into the ground: it always LIES ON the ground, never as the grenade's own pose
-- (its physics and the drawn can differ: it sank). Keeping the way it pointed, the ground is sampled over its whole footprint (7 points
-- along it x 5 across it): its axis runs along the ground between its two ends (slopes), it turns onto its side on the ground (the
-- ground's normal), and it is lifted as much as the highest sample needs (a bump, a kerb's edge — the can's roundness counted) plus
-- CANISTER_CLEARANCE. When that lift would be more than CANISTER_STEP (a step or a ledge under it), it lies level on the highest point
-- of its footprint instead: a little in the air rather than in the ground.
local FOOT_ALONG = 7
local FOOT_ACROSS = { -1.0, -0.5, 0.0, 0.5, 1.0 }   -- times the canister's radius

local function RestPose(p_T)
	local s_Axis = Horizontal(p_T.up) or Horizontal(p_T.forward) or Vec3(0.0, 0.0, 1.0)
	local s_Side = Vec3(-s_Axis.z, 0.0, s_Axis.x)
	local s_O = p_T.trans
	local s_R = CANISTER_REST_HEIGHT
	local s_Length = CANISTER_TOP + CANISTER_BOTTOM

	-- the footprint: t along (0 = the bottom end, 1 = the top end), l across (m)
	local s_Samples = {}
	local s_Highest = nil

	for a = 0, FOOT_ALONG - 1 do
		local l_T = a / (FOOT_ALONG - 1)

		for _, l_Across in ipairs(FOOT_ACROSS) do
			local l_L = l_Across * s_R
			local l_At = s_O + s_Axis * (l_T * s_Length - CANISTER_BOTTOM) + s_Side * l_L
			local l_Hit = GroundUnder(l_At.x, l_At.z, s_O.y)

			if l_Hit ~= nil then
				s_Samples[#s_Samples + 1] = { t = l_T, l = l_L, hit = l_Hit }

				if s_Highest == nil or l_Hit.position.y > s_Highest then
					s_Highest = l_Hit.position.y
				end
			end
		end
	end

	if s_Highest == nil then
		return LinearTransform(s_Side, s_Axis, Vec3(0.0, 1.0, 0.0), s_O), "where it went off (no ground under it)"
	end

	local function Level(p_Why)
		local s_Origin = Vec3(s_O.x, s_Highest, s_O.z) + Vec3(0.0, s_R + CANISTER_CLEARANCE, 0.0) + s_Side * CANISTER_CENTRE_X
		return LinearTransform(s_Side, s_Axis, Vec3(0.0, 1.0, 0.0), s_Origin), "level on the highest point (" .. p_Why .. ")"
	end

	-- the two ends' contacts (on the axis)
	local s_PB, s_PT = nil, nil

	for _, l_S in ipairs(s_Samples) do
		if l_S.l == 0.0 and l_S.t == 0.0 then
			s_PB = l_S.hit.position
		elseif l_S.l == 0.0 and l_S.t == 1.0 then
			s_PT = l_S.hit.position
		end
	end

	if s_PB == nil or s_PT == nil then
		return Level("an end over nothing")
	end

	local s_Along = s_PT - s_PB
	local s_A = Unit(s_Along)

	if s_A == nil or math.abs(s_A.y) > CANISTER_MAX_SLOPE then
		return Level("too steep between its ends")
	end

	-- the ground's normal (a wall's is no floor: ignored), made square to the axis
	local s_Sum = Vec3(0.0, 0.0, 0.0)

	for _, l_S in ipairs(s_Samples) do
		if l_S.hit.normal.y > 0.3 then
			s_Sum = s_Sum + l_S.hit.normal
		end
	end

	local s_Up = Unit(s_Sum) or Vec3(0.0, 1.0, 0.0)
	local s_N = Unit(s_Up - s_A * Dot(s_Up, s_A)) or Vec3(0.0, 1.0, 0.0)

	-- the lift every sample needs: its height over the line between the ends, minus how far the round can is off that line there
	local s_Lift = 0.0

	for _, l_S in ipairs(s_Samples) do
		local l_Line = s_PB + s_Along * l_S.t
		local l_Round = s_R - math.sqrt(math.max(0.0, s_R * s_R - l_S.l * l_S.l))
		local l_Need = Dot(l_S.hit.position - l_Line, s_N) - l_Round

		if l_Need > s_Lift then
			s_Lift = l_Need
		end
	end

	if s_Lift > CANISTER_STEP then
		return Level(string.format("a step under it: %.3f", s_Lift))
	end

	-- the mesh's origin: CANISTER_BOTTOM up the axis from the bottom contact, its lowest side (mesh -Z) on the ground
	local s_X = Cross(s_A, s_N)
	local s_Origin = s_PB + s_A * CANISTER_BOTTOM + s_N * (s_R + CANISTER_CLEARANCE + s_Lift) + s_X * CANISTER_CENTRE_X
	return LinearTransform(s_X, s_A, s_N, s_Origin),
		"on the ground" .. (s_Lift > 0.0005 and string.format(", lifted %.3f", s_Lift) or "")
end

local function PutDown(p_T)
	-- one canister per grenade: a client can hold the thrower's own copy and the server's (same place, same moment)
	for _, l_Down in ipairs(m_Down) do
		if l_Down.age < 1.0 and l_Down.pose.trans:Distance(p_T.trans) < 1.5 then
			return
		end
	end

	local s_Pose, s_How = RestPose(p_T)
	local s_Axis = Horizontal(s_Pose.up) or Vec3(0.0, 0.0, 1.0)
	local s_Top = s_Pose.trans + s_Pose.up * CANISTER_TOP
	local s_GroundY = (s_Top - s_Pose.forward * (CANISTER_REST_HEIGHT + CANISTER_CLEARANCE)).y

	local s_Entity = EntityManager:CreateEntity(m_CanisterData, s_Pose)

	if s_Entity ~= nil then
		s_Entity:Init(Realm.Realm_Client, true)
	end

	-- the smoke's frame: level, its -Z along the canister (the jets leave along -Z), its origin on the ground under the top
	local s_F = Vec3(-s_Axis.x, 0.0, -s_Axis.z)
	local s_Frame = LinearTransform(Vec3(s_F.z, 0.0, -s_F.x), Vec3(0.0, 1.0, 0.0), s_F, Vec3(s_Top.x, s_GroundY, s_Top.z))
	local s_Effect = EffectManager:PlayEffect(m_SmokeEffect, s_Frame, EffectParams(), false)
	local s_Hiss = m_HissEffect ~= nil and EffectManager:PlayEffect(m_HissEffect, s_Frame, EffectParams(), false) or nil

	m_Down[#m_Down + 1] = { entity = s_Entity, effect = s_Effect, hiss = s_Hiss, pose = s_Pose, age = 0.0, stopped = false }

	if m_Logged < 3 then
		m_Logged = m_Logged + 1
		LOG(string.format("smoke %d went off: canister %s (%s) at %.2f %.2f %.2f, smoke %s along %.2f %.2f, hiss %s", m_Logged,
			s_Entity ~= nil and "put down" or "NOT created", s_How, s_Pose.trans.x, s_Pose.trans.y, s_Pose.trans.z,
			tostring(s_Effect), s_Axis.x, s_Axis.z, tostring(s_Hiss)))
	end
end

local function Track(p_Entity)
	if p_Entity == nil then
		return
	end

	local s_Id = p_Entity.uniqueId

	if m_Grenades[s_Id] ~= nil then
		return
	end

	local s_Spatial = SpatialEntity(p_Entity)
	m_Grenades[s_Id] = { entity = s_Spatial, transform = s_Spatial.transform }

	p_Entity:RegisterDeinitCallback(function()
		local s_Grenade = m_Grenades[s_Id]
		m_Grenades[s_Id] = nil

		if s_Grenade ~= nil and m_SmokeEffect ~= nil then
			m_Gone[#m_Gone + 1] = s_Grenade.transform
		end
	end)
end

if IS_CLIENT and SMOKE_ENABLED and SMOKE_BY_LUA then
	Hooks:Install("EntityFactory:Create", 100, function(p_Hook, p_Data, p_Transform)
		if p_Data ~= nil and p_Data.instanceGuid == PROJ_DATA_INST then
			local s_Entity = p_Hook:Call()
			local s_Ok, s_Err = pcall(Track, s_Entity)

			if not s_Ok then
				LOG("⛔ following a smoke grenade: " .. tostring(s_Err))
			end
		end
	end)

	Hooks:Install("EntityFactory:CreateFromBlueprint", 100, function(p_Hook, p_Blueprint, p_Transform, p_Variation, p_Parent)
		if p_Blueprint ~= nil and p_Blueprint.instanceGuid == PROJ_BP_INST then
			local s_Bus = p_Hook:Call()

			if s_Bus ~= nil then
				for _, l_Entity in ipairs(s_Bus.entities) do
					if l_Entity.data ~= nil and l_Entity.data.instanceGuid == PROJ_DATA_INST then
						pcall(Track, l_Entity)
					end
				end
			end
		end
	end)

	Events:Subscribe("UpdateManager:Update", function(p_Delta, p_Pass)
		if p_Pass ~= UpdatePass.UpdatePass_PreSim then
			return
		end

		for _, l_Grenade in pairs(m_Grenades) do
			pcall(function() l_Grenade.transform = l_Grenade.entity.transform end)
		end

		if #m_Gone > 0 then
			local s_Gone = m_Gone
			m_Gone = {}

			for _, l_T in ipairs(s_Gone) do
				local s_Ok, s_Err = pcall(PutDown, l_T)

				if not s_Ok then
					LOG("⛔ putting the canister and the smoke down: " .. tostring(s_Err))
				end
			end
		end

		for i = #m_Down, 1, -1 do
			local l_Down = m_Down[i]
			l_Down.age = l_Down.age + p_Delta

			-- the signal's hiss loops until stopped: stopped when the smoke stops pouring (its own effect: the smoke thins out)
			if not l_Down.stopped and l_Down.age >= SMOKE_SECONDS and l_Down.hiss ~= nil then
				pcall(function() EffectManager:StopEffect(l_Down.hiss) end)
				l_Down.stopped = true
			end

			if l_Down.age >= CANISTER_SECONDS then
				if l_Down.entity ~= nil then
					pcall(function() l_Down.entity:Destroy() end)
				end

				table.remove(m_Down, i)
			end
		end
	end)
end

Events:Subscribe("Level:Destroy", function()
	m_Built = false
	m_GrenadeParts = {}
	m_ByKey = {}

	for _, l_Down in ipairs(m_Down) do
		if l_Down.entity ~= nil then
			pcall(function() l_Down.entity:Destroy() end)
		end
	end

	m_Down = {}
	m_Grenades = {}
	m_Gone = {}
	m_Logged = 0
	m_SmokeEffect = nil
	m_HissEffect = nil
	m_CanisterData = nil
end)
