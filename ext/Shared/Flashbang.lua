-- TacticalSlots -- shared: the M84 flashbang, offered in the grenade slot (ext/Shared/SmokeGrenade.lua keeps the slot's list and the
-- player's choice; this file makes the grenade and its flash).
--
-- THE WEAPON. The game has an M84 only in its campaign (its projectile mesh, its collision, its textures, its sparks and its bang; no
-- unlock, no blueprint, no hand mesh), so ours is the M67 copied in memory with guids of its own, as the M18 smoke is:
--   - in the hand (1st and 3rd person) an M84 mesh shipped in our superbundle (tacticalslots/flash), on the M67's own two bones (body
--     and pin ring, so the M67's pin pull moves its ring), drawn with the game's own flashbang textures;
--   - thrown, the game's flashbang projectile mesh on the game's flashbang collision (a copy of the M67's projectile carrying both);
--   - its numbers (fuse, bounce, blast and shockwave, stun, hearing loss, suppression, one more grenade than the M67) a multiplayer
--     flashbang's, each a knob below (the campaign's own in brackets).
-- Note: the weapon blueprint's NAME stays the M67's (renamed, the grenade is invisible, and after a kit change every weapon is).
--
-- THE FLASH. The detonation plays the campaign flashbang's sparks and smoke and its bang, for everybody (the explosion's effect). The
-- white-out is each client's own: the server says where a flashbang went off and whose it was (TacticalSlots:Flash, with the server's
-- friendly fire setting), and the client weighs a visual environment of its own every frame (brighter, flatter, less colour, blurred):
-- as strong as how squarely the camera faces the point and how near it is when it goes off, held full a while, then fading; none when
-- the camera does not see the point, its player is dead or sits in a vehicle. A flashbang of the player's own team (his own included)
-- gives the short, weak flash instead, unless friendly fire is on.

-- ---- knobs ------------------------------------------------------------------------------------------------------------------
local FLASH_ENABLED = true            -- false: no flashbang (the grenade slot offers the M67 and the smoke)

-- the grenade (the campaign's projectile's own values in brackets)
local FUSE_SECONDS = 1.5              -- from the throw to the bang (2.0)
local MIN_BOUNCE_SPEED = 0.5          -- below this it stops bouncing (1.0)
local COLLISION_SPEED_MULTIPLIER = 0.45 -- speed kept at each bounce (0.17)
local GRAVITY = -9.8
local SPARE_GRENADES = 2              -- grenades carried besides the one in hand (the M67's: 1)
local RELOAD_SECONDS = 0.8            -- from one throw to the next grenade in hand (the M67's: 1.0)
local AMMO_BAG_DELAY = 7.0            -- an ammo bag's refill time, as a multiple (the M67's: 5)

-- the detonation (the campaign's in brackets)
local BLAST_DAMAGE = 5.0              -- (20)
local BLAST_RADIUS = 7.0              -- (6)
local INNER_BLAST_RADIUS = 3.0        -- (2)
local BLAST_IMPULSE = 100.0           -- (2000)
local SHOCKWAVE_DAMAGE = 1.0          -- (1)
local SHOCKWAVE_RADIUS = 12.0         -- (8)
local SHOCKWAVE_IMPULSE = 50.0        -- (500)
local SHOCKWAVE_SECONDS = 0.25        -- (0.25)
local CAMERA_SHOCKWAVE_RADIUS = 3.0   -- the camera shaken within this (0)
local STUN = true                     -- the game's stun of the soldiers it hits
local HEARING_LOSS = true             -- the game's ringing ears
local SUPPRESSION = true              -- it suppresses like gunfire
local UNSPOTTABLE_SECONDS = 1.0

-- what the detonation shows and sounds like
local PARTICLES = true                -- the campaign flashbang's sparks and smoke
local BANG = "campaign"               -- "campaign": the campaign's flashbang bang | "grenade": the hand grenade's explosion | "none"
local BANG_FALLOFF = true             -- the campaign's bang fades with distance (as the hand grenade's does); false: as the campaign
                                      -- plays it (the same loudness at any distance)

-- the white-out
local WHITEOUT = "own"                -- "own": a visual environment of our own, weighed here every frame by the curves below |
                                      -- "effect": the game's visual environment effect, which weighs itself (measured: faint and short)
local FLASH_SECONDS = 10.0            -- how long the flash of an enemy's grenade lasts
local FLASH_HOLD = 0.4                -- the part of it at full strength before it starts fading (0..1)
local FRIEND_SECONDS = 0.6            -- and of the player's own team's (his own included): short and weak
local REACH = 10.0                    -- no flash from farther (m); the strength falls with distance up to it
local STRENGTH_POWER = 0.5            -- how much distance and angle take off it: the curves' strength to this power (1: the curves as
                                      -- they are, 0.56 at 5 m facing it; 0.5: 0.75 there; none behind or out of reach either way)
-- its look at full strength: the campaign flashbang's own visual environment (FX/VisualEnviroments/Explosion/VE_Flashbang_01)
local WHITE_BRIGHTNESS = 4.0          -- how bright the view goes (1: as it is; the campaign's: 4)
local WHITE_CONTRAST = 0.5            -- its contrast (1: as it is; the campaign's: 0.5)
local WHITE_SATURATION = 0.5          -- its colour (1: as it is; 0: grey; the campaign's: 0.5)
local WHITE_HUE = 10.0                -- its hue turned (0: as it is; the campaign's: 10)
local BLUR = 10.0                     -- how blurred the view goes (0: not; the campaign's: 10)
local BLUR_SPREAD = 10.0              -- the blur's width (the campaign's: 10)
local WHITE_PRIORITY = 30000          -- over the level's visual environments and the smoke's (20000, 20001)
-- (WHITEOUT "effect" only:) its look and its film's fade
local LOOK = "film"                   -- "film": darker, then a white film over the screen | "campaign": the campaign's own (brighter,
                                      -- flat, less colour)
local FADE_SECONDS = 6.2              -- the white film's fade back to none
local OCCLUSION = true                -- no flash when the camera does not see the point
local IGNORE_DEAD = true              -- no flash for the dead
local VEHICLES_SHIELD = true          -- no flash inside a vehicle
local TEAMS = true                    -- false: everybody gets the enemy's flash (the control)
local THROWER_REACH = 3.0             -- the thrower: the soldier nearest where the grenade came out, at most this far (m)
-- -----------------------------------------------------------------------------------------------------------------------------

-- the white-out's curves (time, angle, distance: weight = x t^3 + y t^2 + z t + w, each over its own 0..1)
local CURVE_ENEMY = Vec4(-2.765321731567383, 4.269258975982666, -2.477012872695923, 0.9975078701972961)
local CURVE_FRIEND = Vec4(0.5189564228057861, -0.6660080552101135, -0.44016626477241516, 0.5872175097465515)
local CURVE_ANGLE = Vec4(0.0, 0.0, -1.639344573020935, 1.3278690576553345)
local CURVE_DISTANCE = Vec4(0.0, 0.0, -1.1235953569412231, 1.1235953569412231)
local CURVE_FLAT = Vec4(0.0, 0.0, 0.0, 1.0)
local PRIORITY = 10000                -- the flash's visual environment
local FADE_PRIORITY = 9999            -- the film's fade, just under it

local IS_CLIENT = SharedUtils:IsClientModule()

local function LOG(p_Text)
	if _G.TACTICALSLOTS_LOG ~= nil then
		_G.TACTICALSLOTS_LOG("[flash] " .. tostring(p_Text))
	elseif _G.TACTICALSLOTS_PRINTS then
		print("[TacticalSlots][flash] " .. tostring(p_Text))
	end
end

-- ---- the game's pieces --------------------------------------------------------------------------------------------------------
local M67_UNLOCK_PART = Guid("31EBAC8C-F32E-11DF-8153-F8368A2EF9E0")
local M67_UNLOCK_INST = Guid("9F789F05-CE7B-DADC-87D7-16E847DBDD09")

-- the campaign flashbang's (in our superbundle, as references into the player's game data)
local THROWN_MESH_PART = Guid("EA83624F-4323-48A6-BA88-DD552C2CD2D3")
local THROWN_MESH_INST = Guid("5CC70435-A658-3B70-A936-546A16F5160A")
local SMOKE_EMITTER_PART = Guid("CC4182AF-9B90-4D41-AC49-0E85803AD18D")
local SMOKE_EMITTER_INST = Guid("FA81B9D0-D4B3-458E-9C23-54B44A3DB7A6")
local SPARKS_EMITTER_PART = Guid("6E134F3B-6577-432C-8EED-6CC6C2C8C830")
local SPARKS_EMITTER_INST = Guid("A1903900-21AD-4F3F-919F-1F3DDD83FB57")
local BANG_PART = Guid("E8205F37-DBD4-4873-AD49-3AFBA54B73B4")
local BANG_INST = Guid("B67187D2-25F4-416A-BBE0-04D4A7ED7F82")
local GRENADE_BANG = "Sound/Explosions/ModularModel/Explosion_Handgrenade"

-- the materials the campaign gives its flashbang (the projectile's) and its detonation (the smoke grenades', physics material 0)
local MATERIALS_PART = Guid("B50615C2-4743-4919-9A40-A738150DEBE9")
local PROJECTILE_MATERIAL = Guid("4665C768-857A-4BA9-B28F-A942D28F554A")
local EXPLOSION_MATERIAL = Guid("F8B64F95-63CE-40D8-BEFE-1CA74C404176")

-- the 40 mm smoke's effect, on every multiplayer map: its pieces are the copies' templates (an effect, an emitter, a sound)
local FX40_PART = Guid("6A2C27D9-D455-458D-A542-C212C6F8F69C")
local FX40_BP = Guid("00C3D2F9-1346-47B8-956D-10CC23AD8B4D")

-- the hand grenade explosion's fall-off (its flat output): distance (m), level (dB), slope
local FALLOFF = { { 0.0, 0.0, -1.37142 }, { 6.66667, -8.23909, -0.96476 }, { 17.35789, -13.83579, -0.29309 },
	{ 54.11579, -22.82105, -0.21424 }, { 100.06316, -32.21474, -0.19955 } }
local FALLOFF_NEAR = 5.0

-- ---- ours (in the superbundle; the meshes keep the M67's instance guids) ---------------------------------------------------------
local MESH_1P_PART = Guid("6B4E1801-000A-4D18-8018-000000000001")
local MESH_1P_INST = Guid("ECB55FAC-CA19-1433-75D7-D0CA50C48798")
local MESH_3P_PART = Guid("6B4E1801-000A-4D18-8018-000000000003")
local MESH_3P_INST = Guid("388539AF-C6EA-C4B3-5577-3CC232B89519")

local PROJ_PART = Guid("6B4E1801-000A-4D18-8018-000000000011")
local PROJ_BP_INST = Guid("6B4E1801-000A-4D18-8018-000000000012")
local PROJ_DATA_INST = Guid("6B4E1801-000A-4D18-8018-000000000013")
local PROJ_EXPLOSION_INST = Guid("6B4E1801-000A-4D18-8018-000000000015")

-- ---- the copies made here (fixed: the same in both realms) ----------------------------------------------------------------------
local UNLOCK_INST = Guid("6B4E1801-000B-4D18-8018-000000000001")
local BP_INST = Guid("6B4E1801-000B-4D18-8018-000000000002")
local WEAPON_INST = Guid("6B4E1801-000B-4D18-8018-000000000003")
local FIRING_INST = Guid("6B4E1801-000B-4D18-8018-000000000004")
local FIRE_INST = Guid("6B4E1801-000B-4D18-8018-000000000005")
local UNLOCK_NAME = "Weapons/M84/U_M84_Flashbang"
local IDENTIFIER = 3105184884         -- a number of our own: the unlock's identity on the network (the M67's is 1049314494)
local FX_GUIDS = "6B4E1801-000C-4D18-8018-0000000000"   -- + two hex digits, in the order the copies are made
local LOOK_GUIDS = "6B4E1801-000D-4D18-8018-0000000000" -- the white-out's visual environments

_G.TACTICALSLOTS_FLASH_NAME = UNLOCK_NAME

local Flash = {
	fx = 0,
	enemy = nil,          -- the white-out of an enemy's flashbang (client): an effect of two visual environments
	friend = nil,         -- of the player's team's
	looks = {},           -- the colour corrections and films the white-outs are made of (to follow the level's switches)
	friendlyFire = false, -- the server's setting, as it last said
	followed = {},        -- (server) flashbangs in the world: uniqueId -> { entity, at, start, thrower }
	gone = {},            -- (server) flashbangs gone this frame
	logged = 0,
	watch = nil,          -- (client) the last flash played, its weight looked at a few seconds (said once it is over)
	white = nil,          -- (client, WHITEOUT "own") our white-out's visual environment: { entity, set, the data it is made of }
	active = {},          -- (client) the flashes being weighed: { kind, start (0..1), seconds, age, far, angle, most }
}

local function NextFxGuid()
	Flash.fx = Flash.fx + 1

	if Flash.fx > 255 then
		error("out of fx guids (two hex digits)")
	end

	return Guid(FX_GUIDS .. string.format("%02X", Flash.fx))
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

-- ---- the detonation's effect: the campaign flashbang's sparks and smoke and its bang -------------------------------------------
-- The campaign's bang plays at the same loudness at any distance (its output has no fall-off: it was played next to the player); with
-- BANG_FALLOFF it gets the hand grenade's. What was done, said.
function Flash.Falloff(p_Patch)
	local s_Said = "no output found"

	for i = 1, #p_Patch.outputNodes do
		local l_Node = p_Patch.outputNodes[i]

		if l_Node ~= nil and l_Node.typeInfo.name == "FlatOutputNodeData" then
			local l_Output = Writable(l_Node)
			l_Output.attenuationCurve.points:clear()

			for _, l_P in ipairs(FALLOFF) do
				local l_Point = AudioCurvePoint()
				l_Point.x, l_Point.y, l_Point.k = l_P[1], l_P[2], l_P[3]
				l_Output.attenuationCurve.points:add(l_Point)
			end

			l_Output.minDistance = FALLOFF_NEAR
			s_Said = string.format("fades with distance (%d points)", #l_Output.attenuationCurve.points)
		end
	end

	return s_Said
end

function Flash.Detonation()
	local s_Template = ResourceManager:FindInstanceByGuid(FX40_PART, FX40_BP)

	if s_Template == nil then
		return nil, "the 40 mm smoke's effect (the template) is not loaded"
	end

	local s_Blueprint = Copy(s_Template, NextFxGuid())
	local s_Effect = Copy(s_Blueprint.object, NextFxGuid())
	s_Blueprint.object = s_Effect
	s_Blueprint.name = "FX/TacticalSlots/FX_M84_Flashbang"
	s_Effect.maxInstanceCount = 10

	local s_Emitter, s_Sound = nil, nil

	for i = 1, #s_Effect.components do
		local l_Component = s_Effect.components[i]

		if l_Component ~= nil and l_Component.typeInfo.name == "EmitterEntityData" and s_Emitter == nil then
			s_Emitter = l_Component
		elseif l_Component ~= nil and l_Component.typeInfo.name == "SoundEffectEntityData" and s_Sound == nil then
			s_Sound = l_Component
		end
	end

	s_Effect.components:clear()
	local s_Said = {}

	if PARTICLES and s_Emitter ~= nil then
		for _, l_Which in ipairs({ { SPARKS_EMITTER_PART, SPARKS_EMITTER_INST, "sparks" }, { SMOKE_EMITTER_PART, SMOKE_EMITTER_INST, "smoke" } }) do
			local l_Document = ResourceManager:FindInstanceByGuid(l_Which[1], l_Which[2])

			if l_Document ~= nil then
				local l_Emitter = Copy(s_Emitter, NextFxGuid())
				l_Emitter.emitter = EmitterDocument(l_Document)
				l_Emitter.transform = LinearTransform()
				l_Emitter.maxInstanceCount = 10
				s_Effect.components:add(l_Emitter)
				s_Said[#s_Said + 1] = l_Which[3]
			else
				s_Said[#s_Said + 1] = "no " .. l_Which[3] .. " (not loaded)"
			end
		end
	end

	local s_Bang = nil
	local s_BangSaid = "no bang"

	if BANG == "campaign" then
		s_Bang = ResourceManager:FindInstanceByGuid(BANG_PART, BANG_INST)
		s_BangSaid = s_Bang ~= nil and "the campaign's bang" or "no bang (the campaign's is not loaded)"

		if s_Bang ~= nil and BANG_FALLOFF then
			local s_Ok, s_How = pcall(Flash.Falloff, SoundPatchAsset(s_Bang))
			s_BangSaid = s_BangSaid .. ", " .. (s_Ok and tostring(s_How) or ("its fall-off FAILED: " .. tostring(s_How)))
		end
	elseif BANG == "grenade" then
		s_Bang = ResourceManager:SearchForDataContainer(GRENADE_BANG)
		s_BangSaid = s_Bang ~= nil and "the hand grenade's explosion" or "no bang (the hand grenade's is not on this map)"
	end

	if s_Bang ~= nil and s_Sound ~= nil then
		local l_Sound = Copy(s_Sound, NextFxGuid())
		l_Sound.sound = SoundAsset(s_Bang)
		l_Sound.transform = LinearTransform()
		s_Effect.components:add(l_Sound)
	end

	s_Said[#s_Said + 1] = s_BangSaid

	local s_Partition = ResourceManager:FindDatabasePartition(PROJ_PART)

	if s_Partition ~= nil then
		s_Partition:AddInstance(s_Blueprint)
	end

	return s_Blueprint, table.concat(s_Said, ", ")
end

-- ---- the white-out (client) -------------------------------------------------------------------------------------------------------
-- A visual environment as the game's effects carry one (a blueprint and its entity, here a colour correction and a film grain), and an
-- effect entity that plays it with its curves. The game weighs it: by its time (lifetime curve over its seconds), by distance (over
-- REACH) and by the angle between where the camera looks and the point, sampled when it starts.
local function Component(p_Data, p_Index)
	p_Data.excluded = false
	p_Data.isEventConnectionTarget = 3
	p_Data.isPropertyConnectionTarget = 3
	p_Data.indexInBlueprint = p_Index
	p_Data.transform = LinearTransform()
	p_Data.realm = Realm.Realm_Client
	return p_Data
end

-- p_Kind: "flash" (the white-out) or "fade" (the film going back to none under it)
function Flash.Look(p_Kind, p_Base)
	local s_Blueprint = VisualEnvironmentBlueprint(Guid(LOOK_GUIDS .. string.format("%02X", p_Base)))
	local s_Environment = VisualEnvironmentEntityData(Guid(LOOK_GUIDS .. string.format("%02X", p_Base + 1)))
	s_Blueprint.name = p_Kind == "flash" and "FX/TacticalSlots/VE_M84_Flashbang" or "FX/TacticalSlots/VE_M84_Flashbang_Fade"
	s_Blueprint.object = s_Environment
	s_Environment.enabled = true
	s_Environment.visibility = 1.0
	s_Environment.priority = p_Kind == "flash" and PRIORITY or FADE_PRIORITY

	local s_Grain = Component(FilmGrainComponentData(Guid(LOOK_GUIDS .. string.format("%02X", p_Base + 2))), 0)
	s_Grain.textureScale = Vec2(0.0001, 0.0001)
	s_Grain.linearFilteringEnable = false
	s_Grain.randomEnable = false
	s_Grain.texture = nil

	if p_Kind == "fade" then
		s_Grain.colorScale = Vec3(0.01, 0.01, 0.01)
		s_Grain.enable = false
		s_Environment.components:add(s_Grain)
		s_Environment.runtimeComponentCount = 1
		return s_Blueprint, { grain = s_Grain }
	end

	local s_Correction = Component(ColorCorrectionComponentData(Guid(LOOK_GUIDS .. string.format("%02X", p_Base + 3))), 1)
	s_Correction.enable = true
	s_Correction.colorGradingEnable = false
	s_Correction.hue = 0.0
	s_Correction.contrast = Vec3(1.0, 1.0, 1.0)
	s_Correction.saturation = Vec3(1.0, 1.0, 1.0)

	if LOOK == "campaign" then
		-- the campaign's own flash: brighter, flatter, less colour; no film
		s_Correction.brightness = Vec3(4.0, 4.0, 4.0)
		s_Correction.contrast = Vec3(0.5, 0.5, 0.5)
		s_Correction.saturation = Vec3(0.5, 0.5, 0.5)
		s_Correction.hue = 10.0
		s_Environment.components:add(s_Correction)
		s_Environment.runtimeComponentCount = 1
		return s_Blueprint, { correction = s_Correction, own = true }
	end

	-- the film: darker, and a film of one texel over the whole screen, 20 times bright (white, a little warm)
	s_Correction.brightness = Vec3(0.25, 0.25, 0.25)
	s_Grain.colorScale = Vec3(20.0, 20.0, 18.0)
	s_Grain.enable = true
	s_Environment.components:add(s_Grain)
	s_Environment.components:add(s_Correction)
	s_Environment.runtimeComponentCount = 2
	return s_Blueprint, { correction = s_Correction, grain = s_Grain }
end

local function VisualEffect(p_Look, p_Seconds, p_Curve, p_Angle, p_Distance)
	local s_Effect = VisualEnvironmentEffectEntityData(NextFxGuid())
	s_Effect.transform = LinearTransform(Vec3(1.0, 0.0, 0.0), Vec3(0.0, 1.0, 0.0), Vec3(0.0, 0.0, 1.0), Vec3(0.0, 0.1, 0.0))
	s_Effect.isEventConnectionTarget = 3
	s_Effect.isPropertyConnectionTarget = 3
	s_Effect.indexInBlueprint = 65535
	s_Effect.maxInstanceCount = 30
	s_Effect.cullDistance = REACH
	s_Effect.startDelay = 0.0
	s_Effect.highEndPc = true
	s_Effect.mediumPc = true
	s_Effect.lowEndPc = true
	s_Effect.resetInstanceWhenStarted = true
	s_Effect.lifetimeCurve = p_Curve
	s_Effect.cullAngleCurve = p_Angle
	s_Effect.cullDistanceCurve = p_Distance
	s_Effect.lifetime = p_Seconds
	s_Effect.visualEnvironment = p_Look
	s_Effect.sampleOnStartOnly = true
	return s_Effect
end

-- the enemy's white-out or the friend's: the flash and its fade, as one effect
function Flash.WhiteOut(p_Friend, p_Flash, p_Fade)
	local s_Template = ResourceManager:FindInstanceByGuid(FX40_PART, FX40_BP)

	if s_Template == nil then
		return nil
	end

	local s_Blueprint = Copy(s_Template, NextFxGuid())
	local s_Effect = Copy(s_Blueprint.object, NextFxGuid())
	s_Blueprint.object = s_Effect
	s_Blueprint.name = p_Friend and "FX/TacticalSlots/FX_M84_Flash_Friend" or "FX/TacticalSlots/FX_M84_Flash"
	s_Effect.maxInstanceCount = 30
	s_Effect.components:clear()
	s_Effect.components:add(VisualEffect(p_Flash, p_Friend and FRIEND_SECONDS or FLASH_SECONDS,
		p_Friend and CURVE_FRIEND or CURVE_ENEMY, CURVE_ANGLE, CURVE_DISTANCE))
	s_Effect.components:add(VisualEffect(p_Fade, FADE_SECONDS, CURVE_FLAT, CURVE_FLAT, CURVE_FLAT))

	local s_Partition = ResourceManager:FindDatabasePartition(PROJ_PART)

	if s_Partition ~= nil then
		s_Partition:AddInstance(s_Blueprint)
	end

	return s_Blueprint
end

-- ---- the weapon -----------------------------------------------------------------------------------------------------------------
-- Made at the level's entity registration, in both realms (the same guids, the same order: network ids). Returns its unlock and what
-- was made, or nil and why not.
function Flash.Make()
	Flash.fx = 0
	local s_M67 = ResourceManager:FindInstanceByGuid(M67_UNLOCK_PART, M67_UNLOCK_INST)
	local s_Mesh1p = ResourceManager:FindInstanceByGuid(MESH_1P_PART, MESH_1P_INST)
	local s_Mesh3p = ResourceManager:FindInstanceByGuid(MESH_3P_PART, MESH_3P_INST)
	local s_ProjectileBp = ResourceManager:FindInstanceByGuid(PROJ_PART, PROJ_BP_INST)
	local s_Projectile = ResourceManager:FindInstanceByGuid(PROJ_PART, PROJ_DATA_INST)
	local s_Explosion = ResourceManager:FindInstanceByGuid(PROJ_PART, PROJ_EXPLOSION_INST)
	local s_Thrown = ResourceManager:FindInstanceByGuid(THROWN_MESH_PART, THROWN_MESH_INST)

	local s_Missing = {}
	for _, l_Pair in ipairs({ { "m67", s_M67 }, { "mesh1p", s_Mesh1p }, { "mesh3p", s_Mesh3p }, { "projectileBlueprint", s_ProjectileBp },
		{ "projectile", s_Projectile }, { "explosion", s_Explosion }, { "thrownMesh", s_Thrown } }) do
		if l_Pair[2] == nil then
			s_Missing[#s_Missing + 1] = l_Pair[1]
		end
	end

	if #s_Missing > 0 then
		return nil, "not loaded: " .. table.concat(s_Missing, ", ")
	end

	-- the thrown grenade: the campaign's mesh (its collision rides our copy of the projectile), the knobs' fuse and bounce
	s_Projectile = Writable(s_Projectile)
	s_Projectile.mesh = RigidMeshAsset(s_Thrown)
	s_Projectile.timeToLive = FUSE_SECONDS
	s_Projectile.detonateOnTimeout = true
	s_Projectile.gravity = GRAVITY
	s_Projectile.minBounceSpeed = MIN_BOUNCE_SPEED
	s_Projectile.collisionSpeedMultiplier = COLLISION_SPEED_MULTIPLIER
	s_Projectile.grenadeType = GrenadeType.GrenadeType_Flash
	s_Projectile.hitReactionWeaponType = AntHitReactionWeaponType.AntHitReactionWeaponType_Flashbang
	s_Projectile.ammunitionType = "Flashbang"

	local s_Said = {}
	local s_Material = ResourceManager:FindInstanceByGuid(MATERIALS_PART, PROJECTILE_MATERIAL)

	if s_Material ~= nil then
		s_Projectile.materialPair = MaterialContainerPair(s_Material)
	else
		s_Said[#s_Said + 1] = "the flashbang's material not loaded (the frag's kept)"
	end

	-- the detonation: the knobs' numbers, the campaign's sparks, smoke and bang
	s_Explosion = Writable(s_Explosion)
	s_Explosion.blastDamage = BLAST_DAMAGE
	s_Explosion.blastRadius = BLAST_RADIUS
	s_Explosion.innerBlastRadius = INNER_BLAST_RADIUS
	s_Explosion.blastImpulse = BLAST_IMPULSE
	s_Explosion.shockwaveDamage = SHOCKWAVE_DAMAGE
	s_Explosion.shockwaveRadius = SHOCKWAVE_RADIUS
	s_Explosion.shockwaveImpulse = SHOCKWAVE_IMPULSE
	s_Explosion.shockwaveTime = SHOCKWAVE_SECONDS
	s_Explosion.cameraShockwaveRadius = CAMERA_SHOCKWAVE_RADIUS
	s_Explosion.maxOcclusionRaycastRadius = 0.5
	s_Explosion.disableOcclusion = false
	s_Explosion.disableStaticEntityOcclusion = true
	s_Explosion.hasStunEffect = STUN
	s_Explosion.triggerImpairedHearing = HEARING_LOSS
	s_Explosion.isCausingSuppression = SUPPRESSION
	s_Explosion.unspotsOnExplode = false
	s_Explosion.spotsOnExplode = false
	s_Explosion.unspottableTime = UNSPOTTABLE_SECONDS
	s_Explosion.empTime = 0.0

	local s_ExplosionMaterial = ResourceManager:FindInstanceByGuid(MATERIALS_PART, EXPLOSION_MATERIAL)

	if s_ExplosionMaterial ~= nil then
		s_Explosion.materialPair = MaterialContainerPair(s_ExplosionMaterial)
	end

	local s_Detonation, s_DetonationSaid = Flash.Detonation()
	s_Explosion.detonationEffect = s_Detonation
	s_Said[#s_Said + 1] = "detonation: " .. tostring(s_DetonationSaid)

	-- the weapon: the M67 copied unlock -> blueprint -> weapon data -> firing -> primary fire, each with our guid
	local s_Unlock = Copy(s_M67, UNLOCK_INST)
	s_Unlock.name = UNLOCK_NAME
	s_Unlock.debugUnlockId = "U_M84_Flashbang"
	s_Unlock.identifier = IDENTIFIER

	local s_Blueprint = Copy(s_Unlock.weapon, BP_INST)   -- its name stays the M67's (see the header)
	s_Unlock.weapon = s_Blueprint

	local s_Weapon = Copy(s_Blueprint.object, WEAPON_INST)
	s_Blueprint.object = s_Weapon
	s_Weapon.soldierWeaponBlueprint = s_Blueprint
	s_Weapon.damageGiverName = "M84"

	local s_Firing = Copy(s_Weapon.weaponFiring, FIRING_INST)
	s_Weapon.weaponFiring = s_Firing

	local s_Fire = Copy(s_Firing.primaryFire, FIRE_INST)
	s_Firing.primaryFire = s_Fire
	s_Fire.shot.projectile = ProjectileBlueprint(s_ProjectileBp)
	s_Fire.shot.projectileData = GrenadeEntityData(s_Projectile)
	s_Fire.ammo.numberOfMagazines = SPARE_GRENADES
	s_Fire.ammo.ammoBagPickupDelayMultiplier = AMMO_BAG_DELAY
	s_Fire.fireLogic.reloadTime = RELOAD_SECONDS

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

	-- the white-outs (client)
	if IS_CLIENT then
		Flash.looks = {}
		local s_Flash, s_FlashParts = Flash.Look("flash", 0x01)
		local s_Fade, s_FadeParts = Flash.Look("fade", 0x11)
		Flash.looks = { s_FlashParts, s_FadeParts }
		Flash.enemy = Flash.WhiteOut(false, s_Flash, s_Fade)
		Flash.friend = Flash.WhiteOut(true, s_Flash, s_Fade)
		s_Said[#s_Said + 1] = string.format("white-out (%s look): %s", LOOK,
			(Flash.enemy ~= nil and Flash.friend ~= nil) and "made" or "NOT made (the template is not loaded)")
	end

	return s_Unlock, string.format("%d weapon state(s) with the M84 meshes, %d spare grenade(s); %s", #s_Weapon.weaponStates,
		SPARE_GRENADES, table.concat(s_Said, "; "))
end

_G.TACTICALSLOTS_FLASH_MAKE = FLASH_ENABLED and Flash.Make or nil

-- ---- whose it was (server) ------------------------------------------------------------------------------------------------------
-- The soldier nearest where the grenade came out (his eyes are somewhere up his height: the distance to the segment from his feet up
-- 1.8 m), at most THROWER_REACH (or p_Reach) away. p_Soldiers: { { id, team, at } }. Returns that entry and how far, or nil.
function Flash.Thrower(p_At, p_Soldiers, p_Reach)
	local s_Best, s_Gap = nil, p_Reach or THROWER_REACH

	for _, l_Soldier in ipairs(p_Soldiers) do
		local l_Up = math.max(0.0, math.min(1.8, p_At.y - l_Soldier.at.y))
		local l_Dx, l_Dy, l_Dz = p_At.x - l_Soldier.at.x, p_At.y - (l_Soldier.at.y + l_Up), p_At.z - l_Soldier.at.z
		local l_Gap = math.sqrt(l_Dx * l_Dx + l_Dy * l_Dy + l_Dz * l_Dz)

		if l_Gap <= s_Gap then
			s_Best, s_Gap = l_Soldier, l_Gap
		end
	end

	return s_Best, s_Best ~= nil and s_Gap or nil
end

-- ---- the white-out or not (client) --------------------------------------------------------------------------------------------
-- p_Me: { id, team, alive, inVehicle } (the local player), the thrower's id and team (-1 / 0: not known), friendly fire on.
-- Returns "enemy" (the full flash), "friend" (the short, weak one) or nil, and why.
function Flash.Decide(p_Me, p_ThrowerId, p_ThrowerTeam, p_FriendlyFire)
	if p_Me == nil then
		return nil, "no local player"
	elseif IGNORE_DEAD and not p_Me.alive then
		return nil, "dead"
	elseif VEHICLES_SHIELD and p_Me.inVehicle then
		return nil, "in a vehicle"
	elseif not TEAMS then
		return "enemy", "teams not looked at"
	end

	local s_Own = p_ThrowerId ~= nil and p_ThrowerId >= 0 and p_ThrowerId == p_Me.id
	local s_Team = p_ThrowerTeam ~= nil and p_ThrowerTeam > 0 and p_ThrowerTeam == p_Me.team

	if s_Own or s_Team then
		if p_FriendlyFire then
			return "enemy", (s_Own and "his own" or "his team's") .. ", friendly fire on"
		end

		return "friend", s_Own and "his own" or "his team's"
	end

	if p_ThrowerTeam == nil or p_ThrowerTeam <= 0 then
		return "enemy", "whose it was is not known"
	end

	return "enemy", "an enemy's"
end

-- does something stand between the camera and the point (the game's own test looks at the detailed meshes)
local OCCLUSION_FLAGS = RayCastFlags.CheckDetailMesh | RayCastFlags.DontCheckWater | RayCastFlags.DontCheckCharacter |
	RayCastFlags.DontCheckRagdoll | RayCastFlags.DontCheckPhantoms

function Flash.Occluded(p_From, p_To)
	local s_Hit = RaycastManager:Raycast(p_From, p_To, OCCLUSION_FLAGS)

	if s_Hit == nil then
		return false
	end

	local s_Left = s_Hit.position - p_To
	return math.sqrt(s_Left.x * s_Left.x + s_Left.y * s_Left.y + s_Left.z * s_Left.z) > 0.25
end

-- the level's look under the flash: the switches of the highest state weighing anything that is not an effect's (the flash's own, and
-- any other passing one) copied into the flash's colour correction and film, so the flash changes its brightness and film only (a
-- switch of the highest state would otherwise turn the level's grading off under it)
function Flash.FollowLevel()
	local s_Grade, s_GradeP, s_Grain, s_GrainP = nil, -1, nil, -1

	for _, l_State in pairs(VisualEnvironmentManager:GetStates()) do
		if l_State.entityName ~= "EffectEntity" and (l_State.visibility or 0.0) > 0.0 then
			if l_State.colorCorrection ~= nil and l_State.priority > s_GradeP then
				s_Grade, s_GradeP = l_State.colorCorrection, l_State.priority
			end

			if l_State.filmGrain ~= nil and l_State.priority > s_GrainP then
				s_Grain, s_GrainP = l_State.filmGrain, l_State.priority
			end
		end
	end

	for _, l_Parts in ipairs(Flash.looks) do
		if l_Parts.correction ~= nil and s_Grade ~= nil then
			l_Parts.correction.colorGradingEnable = s_Grade.colorGradingEnable
			l_Parts.correction.colorGradingTexture = s_Grade.colorGradingTexture

			if not l_Parts.own then
				l_Parts.correction.contrast = s_Grade.contrast
				l_Parts.correction.saturation = s_Grade.saturation
				l_Parts.correction.hue = s_Grade.hue
			end
		end

		if l_Parts.grain ~= nil and s_Grain ~= nil then
			l_Parts.grain.texture = s_Grain.texture
		end
	end

	return string.format("grading %s (priority %d), film texture %s", s_Grade ~= nil and tostring(s_Grade.colorGradingEnable) or "none",
		s_GradeP, s_Grain ~= nil and (s_Grain.texture ~= nil and "the level's" or "none") or "no film state")
end

-- ---- our white-out (client, WHITEOUT "own") -------------------------------------------------------------------------------------
-- A visual environment of our own (as the smoke's fog: a logic entity -> its blueprint -> the environment: a colour correction and a
-- depth of field blur), enabled once a level is up and weighed every frame through its state's visibility: the strongest of the
-- flashes going on, each its strength when it went off (angle, distance) times its time curve.
local function Poly(p_C, p_X)
	return ((p_C.x * p_X + p_C.y) * p_X + p_C.z) * p_X + p_C.w
end

local function Clamp01(p_V)
	return math.max(0.0, math.min(1.0, p_V))
end

-- the angle (degrees) between where the camera looks and the point
function Flash.Angle(p_Look, p_To)
	local s_A = math.sqrt(p_Look.x * p_Look.x + p_Look.y * p_Look.y + p_Look.z * p_Look.z)
	local s_B = math.sqrt(p_To.x * p_To.x + p_To.y * p_To.y + p_To.z * p_To.z)

	if s_A < 1e-6 or s_B < 1e-6 then
		return 0.0
	end

	local s_Cos = (p_Look.x * p_To.x + p_Look.y * p_To.y + p_Look.z * p_To.z) / (s_A * s_B)
	return math.deg(math.acos(math.max(-1.0, math.min(1.0, s_Cos))))
end

-- how strong a flash starts: the angle curve over 0..180 degrees times the distance curve over 0..REACH, to STRENGTH_POWER; and each
-- of them
function Flash.Strength(p_Angle, p_Far)
	local s_ByAngle = Clamp01(Poly(CURVE_ANGLE, p_Angle / 180.0))
	local s_ByFar = Clamp01(Poly(CURVE_DISTANCE, math.max(0.0, p_Far) / REACH))
	return (s_ByAngle * s_ByFar) ^ STRENGTH_POWER, s_ByAngle, s_ByFar
end

-- its strength over its time (p_T: 0..1 of its seconds): an enemy's held full FLASH_HOLD of it, then the fading curve over the rest;
-- a friend's, the short one from the start
function Flash.Curve(p_Kind, p_T)
	if p_T >= 1.0 then
		return 0.0
	elseif p_Kind == "friend" then
		return Clamp01(Poly(CURVE_FRIEND, p_T))
	elseif p_T <= FLASH_HOLD then
		return 1.0
	end

	return Clamp01(Poly(CURVE_ENEMY, (p_T - FLASH_HOLD) / math.max(0.001, 1.0 - FLASH_HOLD)))
end

function Flash.MakeWhite()
	local s_Logic = LogicVisualEnvironmentEntityData(Guid(LOOK_GUIDS .. "21"))
	local s_Blueprint = VisualEnvironmentBlueprint(Guid(LOOK_GUIDS .. "22"))
	local s_Environment = VisualEnvironmentEntityData(Guid(LOOK_GUIDS .. "23"))
	s_Blueprint.name = "FX/TacticalSlots/VE_M84_WhiteOut"
	s_Blueprint.object = s_Environment
	s_Logic.visualEnvironment = s_Blueprint
	s_Logic.visibility = 1.0
	s_Environment.enabled = true
	s_Environment.priority = WHITE_PRIORITY
	s_Environment.visibility = 1.0

	local s_Correction = Component(ColorCorrectionComponentData(Guid(LOOK_GUIDS .. "24")), 0)
	s_Correction.enable = true
	s_Correction.brightness = Vec3(WHITE_BRIGHTNESS, WHITE_BRIGHTNESS, WHITE_BRIGHTNESS)
	s_Correction.contrast = Vec3(WHITE_CONTRAST, WHITE_CONTRAST, WHITE_CONTRAST)
	s_Correction.saturation = Vec3(WHITE_SATURATION, WHITE_SATURATION, WHITE_SATURATION)
	s_Correction.hue = WHITE_HUE
	s_Correction.colorGradingEnable = false
	s_Environment.components:add(s_Correction)

	-- the blur: the campaign flash's depth of field (all of the view out of focus, BLUR more)
	local s_Blur = nil

	if BLUR > 0.0 then
		s_Blur = Component(DofComponentData(Guid(LOOK_GUIDS .. "25")), 1)
		s_Blur.enable = true
		s_Blur.focusDistance = 1.0
		s_Blur.nearDistanceScale = 0.1
		s_Blur.farDistanceScale = 2.0
		s_Blur.blurAdd = BLUR
		s_Blur.blurFilter = BlurFilter.BfGaussian9Pixels
		s_Blur.blurFilterDeviation = BLUR_SPREAD
		s_Blur.scale = 1.0
		s_Blur.diffusionDofEnable = false
		s_Blur.diffusionDofFocalLength = 0.2
		s_Blur.diffusionDofAperture = 5.0
		s_Environment.components:add(s_Blur)
	end

	s_Environment.runtimeComponentCount = #s_Environment.components

	local s_Entity = EntityManager:CreateEntity(s_Logic, LinearTransform())

	if s_Entity == nil then
		return nil
	end

	s_Entity:Init(Realm.Realm_Client, true)
	s_Entity:FireEvent("Enable")
	VisualEnvironmentManager:SetDirty(true)

	return { entity = s_Entity, set = -1.0, logic = s_Logic, blueprint = s_Blueprint, environment = s_Environment,
		correction = s_Correction, blur = s_Blur }
end

local function OurWhite(p_State)
	return p_State.priority == WHITE_PRIORITY or p_State.priority == 10000000 + WHITE_PRIORITY
end

-- the level's switches under the white-out (as the smoke's fog does): of the states weighing anything -- not ours, not an effect's
-- passing one -- the highest's colour grading copied into ours, so the flash changes the numbers only
function Flash.MirrorWhite(p_Ours)
	local s_Grade, s_GradeP = nil, -1

	for _, l_State in pairs(VisualEnvironmentManager:GetStates()) do
		if not OurWhite(l_State) and l_State.entityName ~= "EffectEntity" and (l_State.visibility or 0.0) > 0.0 and
			l_State.colorCorrection ~= nil and l_State.priority > s_GradeP then
			s_Grade, s_GradeP = l_State.colorCorrection, l_State.priority
		end
	end

	if s_Grade ~= nil and p_Ours.colorCorrection ~= nil then
		p_Ours.colorCorrection.colorGradingEnable = s_Grade.colorGradingEnable
		p_Ours.colorCorrection.colorGradingTexture = s_Grade.colorGradingTexture
	end

	return s_Grade ~= nil and string.format("grading %s (priority %d)", tostring(s_Grade.colorGradingEnable), s_GradeP) or "no grading found"
end

-- the white-out's weight now (its state: ours by priority); as it comes on, its switches the level's
function Flash.SetWhite(p_Visibility)
	local s_White = Flash.white

	if math.abs(s_White.set - p_Visibility) < 0.002 then
		return
	end

	for _, l_State in pairs(VisualEnvironmentManager:GetStates()) do
		if OurWhite(l_State) then
			if p_Visibility > 0.0 and s_White.set <= 0.0 then
				local s_Ok, s_Said = pcall(Flash.MirrorWhite, l_State)
				s_White.mirror = s_Ok and s_Said or ("FAILED " .. tostring(s_Said))
			end

			l_State.visibility = p_Visibility
			VisualEnvironmentManager:SetDirty(true)
			s_White.priority = l_State.priority
			s_White.set = p_Visibility
			return
		end
	end

	-- not there: looked for a while (it may take a frame or two to come up), then given up, said once
	s_White.missing = (s_White.missing or 0) + 1

	if s_White.missing == 300 then
		LOG(string.format("⛔ the white-out: no visual environment state with priority %d came up -- no white-out this level", WHITE_PRIORITY))
		s_White.set = 0.0
	end
end

-- whether this frame weighs the white-out: while a flash goes on, and until its state has been put at what it should be -- also the
-- first time: it is made at full weight (left so, the view is white from the spawn on, with no flashbang thrown)
function Flash.NeedsFrame()
	return #Flash.active > 0 or (Flash.white ~= nil and Flash.white.set ~= 0.0)
end

-- every frame: the flashes aged, the strongest one now the white-out's weight; each said once it is over
function Flash.Frame(p_Delta)
	local s_Now = 0.0

	for i = #Flash.active, 1, -1 do
		local l_Flash = Flash.active[i]
		l_Flash.age = l_Flash.age + p_Delta
		local l_Weight = l_Flash.start * Flash.Curve(l_Flash.kind, l_Flash.age / l_Flash.seconds)
		l_Flash.most = math.max(l_Flash.most, l_Weight)
		s_Now = math.max(s_Now, l_Weight)

		if l_Flash.age >= l_Flash.seconds then
			table.remove(Flash.active, i)
			LOG(string.format("the %s's flash from %.1f m, facing it %.0f deg, weighed %.2f at most over %.1f s (the white-out's state %s%s)",
				l_Flash.kind, l_Flash.far, l_Flash.angle, l_Flash.most, l_Flash.seconds,
				Flash.white ~= nil and Flash.white.priority ~= nil and ("found, priority " .. tostring(Flash.white.priority)) or "NOT found",
				Flash.white ~= nil and Flash.white.mirror ~= nil and ("; " .. Flash.white.mirror) or ""))
		end
	end

	if Flash.white ~= nil then
		-- (its last hundredth let go at once: no switch of ours weighs on past the flash)
		Flash.SetWhite(s_Now < 0.01 and 0.0 or s_Now)
	end
end

function Flash.Seen(p_X, p_Y, p_Z, p_ThrowerId, p_ThrowerTeam, p_FriendlyFire)
	local s_At = Vec3(p_X, p_Y, p_Z)
	local s_Player = PlayerManager:GetLocalPlayer()
	local s_Me = nil

	if s_Player ~= nil then
		s_Me = { id = s_Player.id, team = s_Player.teamId, alive = s_Player.soldier ~= nil and s_Player.alive,
			inVehicle = s_Player.inVehicle }
	end

	local s_Kind, s_Why = Flash.Decide(s_Me, p_ThrowerId, p_ThrowerTeam, p_FriendlyFire)
	local s_Camera = ClientUtils:GetCameraTransform()
	local s_Far = -1.0

	if s_Kind ~= nil and s_Camera ~= nil then
		local s_Gap = s_At - s_Camera.trans
		s_Far = math.sqrt(s_Gap.x * s_Gap.x + s_Gap.y * s_Gap.y + s_Gap.z * s_Gap.z)

		if s_Far > REACH then
			s_Kind, s_Why = nil, string.format("%.1f m away (beyond %.0f)", s_Far, REACH)
		elseif OCCLUSION and Flash.Occluded(s_Camera.trans, s_At + Vec3(0.0, 0.1, 0.0)) then
			s_Kind, s_Why = nil, string.format("not seen from %.1f m (something in between)", s_Far)
		end
	end

	local s_Effect = s_Kind == "enemy" and Flash.enemy or (s_Kind == "friend" and Flash.friend or nil)
	local s_Played = false
	local s_Level = ""

	if s_Kind ~= nil and WHITEOUT == "own" and s_Camera ~= nil then
		-- how strong: by how squarely the camera faces the point (the view is -forward) and how near it is, sampled now
		local s_Look = Vec3(-s_Camera.forward.x, -s_Camera.forward.y, -s_Camera.forward.z)
		local s_To = s_At + Vec3(0.0, 0.1, 0.0) - s_Camera.trans
		local s_Angle = Flash.Angle(s_Look, s_To)
		local s_Start, s_ByAngle, s_ByFar = Flash.Strength(s_Angle, s_Far)
		Flash.active[#Flash.active + 1] = { kind = s_Kind, start = s_Start, seconds = s_Kind == "friend" and FRIEND_SECONDS or FLASH_SECONDS,
			age = 0.0, far = s_Far, angle = s_Angle, byAngle = s_ByAngle, byFar = s_ByFar, most = 0.0 }
		s_Played = Flash.white ~= nil
		s_Level = string.format("strength %.2f (facing it %.0f deg: %.2f, %.1f m: %.2f)", s_Start, s_Angle, s_ByAngle, s_Far, s_ByFar)
	elseif s_Effect ~= nil then
		local s_Ok, s_Said = pcall(Flash.FollowLevel)
		s_Level = s_Ok and tostring(s_Said) or ("following the level FAILED: " .. tostring(s_Said))
		local s_Handle = EffectManager:PlayEffect(s_Effect, LinearTransform(Vec3(1.0, 0.0, 0.0), Vec3(0.0, 1.0, 0.0), Vec3(0.0, 0.0, 1.0), s_At),
			EffectParams(), false)
		s_Played = s_Handle ~= nil
		Flash.watch = { age = 0.0, most = 0.0, kind = s_Kind, far = s_Far }
	end

	-- the first few a level, said
	if Flash.logged < 12 then
		Flash.logged = Flash.logged + 1
		LOG(string.format("flashbang %d went off at %.1f %.1f %.1f (thrower %s, team %s, friendly fire %s): %s -- %s%s", Flash.logged,
			p_X, p_Y, p_Z, tostring(p_ThrowerId), tostring(p_ThrowerTeam), tostring(p_FriendlyFire),
			s_Kind ~= nil and (s_Kind .. "'s flash" .. (s_Played and " played" or " NOT played")) or "no flash", tostring(s_Why),
			s_Level ~= "" and ("; " .. s_Level) or ""))
	end
end

-- how much the white-out weighed (any state of an effect with the flash's film or brightness), the first seconds of the last one: said
-- once it is over, so the log tells the game weighed it at all, and how much
function Flash.Watch(p_Delta)
	local s_Watch = Flash.watch
	s_Watch.age = s_Watch.age + p_Delta

	for _, l_State in pairs(VisualEnvironmentManager:GetStates()) do
		if l_State.entityName == "EffectEntity" and l_State.priority ~= nil then
			local l_Ours = (l_State.filmGrain ~= nil and l_State.filmGrain.colorScale.x > 10.0) or
				(l_State.colorCorrection ~= nil and (l_State.colorCorrection.brightness.x == 0.25 or l_State.colorCorrection.brightness.x == 4.0))

			if l_Ours then
				s_Watch.most = math.max(s_Watch.most, l_State.visibility or 0.0)
				s_Watch.priority = l_State.priority
			end
		end
	end

	if s_Watch.age >= (s_Watch.kind == "friend" and FRIEND_SECONDS or FLASH_SECONDS) + 0.5 then
		LOG(string.format("the %s's flash from %.1f m weighed at most %.2f (its state's priority %s)", s_Watch.kind, s_Watch.far,
			s_Watch.most, tostring(s_Watch.priority)))
		Flash.watch = nil
	end
end

if IS_CLIENT and FLASH_ENABLED then
	NetEvents:Subscribe("TacticalSlots:Flash", function(p_X, p_Y, p_Z, p_ThrowerId, p_ThrowerTeam, p_FriendlyFire)
		local s_Ok, s_Err = pcall(Flash.Seen, tonumber(p_X), tonumber(p_Y), tonumber(p_Z), tonumber(p_ThrowerId), tonumber(p_ThrowerTeam),
			p_FriendlyFire == true or p_FriendlyFire == "true")

		if not s_Ok then
			LOG("⛔ a flashbang's flash: " .. tostring(s_Err))
		end
	end)

	Events:Subscribe("UpdateManager:Update", function(p_Delta, p_Pass)
		if p_Pass ~= UpdatePass.UpdatePass_PreSim then
			return
		end

		if Flash.NeedsFrame() then
			local s_Ok, s_Err = pcall(Flash.Frame, p_Delta)

			if not s_Ok then
				LOG("⛔ the white-out: " .. tostring(s_Err))
				Flash.active = {}
			end
		end

		if Flash.watch ~= nil then
			local s_Ok, s_Err = pcall(Flash.Watch, p_Delta)

			if not s_Ok then
				LOG("⛔ looking at a flash's weight: " .. tostring(s_Err))
				Flash.watch = nil
			end
		end
	end)

	-- our white-out's visual environment, made once a level is up
	if WHITEOUT == "own" then
		Events:Subscribe("Level:Loaded", function()
			local s_Ok, s_White = pcall(Flash.MakeWhite)
			Flash.white = s_Ok and s_White or nil
			LOG(Flash.white ~= nil and string.format("the white-out made (visual environment, priority %d; brightness %.1f, blur %.1f, %.0f s)",
				WHITE_PRIORITY, WHITE_BRIGHTNESS, BLUR, FLASH_SECONDS) or
				("⛔ the white-out could not be made: " .. tostring(s_Ok and "no entity" or s_White)))
		end)
	end
end

-- ---- where it went off and whose it was (server) -----------------------------------------------------------------------------------
-- The server follows every flashbang from where it came out (whose: Flash.Thrower) to where it is gone (it went off), and tells every
-- client: TacticalSlots:Flash x, y, z, the thrower's id and team (-1 / 0: none found) and its friendly fire setting.
function Flash.FriendlyFireOn()
	local s_Ok, s_Answer = pcall(function() return RCON:SendCommand("vu.FriendlyFire") end)

	if s_Ok and type(s_Answer) == "table" then
		return tostring(s_Answer[2]) == "true" or tostring(s_Answer[2]) == "1"
	end

	return false
end

function Flash.AtOrigin(p_At)
	return math.abs(p_At.x) + math.abs(p_At.y) + math.abs(p_At.z) < 0.01
end

-- the alive soldiers, where they stand
function Flash.Soldiers()
	local s_Soldiers = {}

	for _, l_Player in pairs(PlayerManager:GetPlayers()) do
		if l_Player.soldier ~= nil and l_Player.alive then
			local l_At = l_Player.soldier.worldTransform.trans
			s_Soldiers[#s_Soldiers + 1] = { id = l_Player.id, team = l_Player.teamId, name = l_Player.name, at = Vec3(l_At.x, l_At.y, l_At.z) }
		end
	end

	return s_Soldiers
end

-- whose a flashbang is, from where it is first seen (p_At); the nearest soldier at all kept as well, for the log
function Flash.Pick(p_Flash, p_At)
	local s_Soldiers = Flash.Soldiers()
	p_Flash.thrower, p_Flash.gap = Flash.Thrower(p_At, s_Soldiers)
	p_Flash.from = Vec3(p_At.x, p_At.y, p_At.z)
	p_Flash.soldiers = #s_Soldiers
	local s_Near, s_NearGap = Flash.Thrower(p_At, s_Soldiers, 1.0e9)
	p_Flash.nearest = s_Near ~= nil and string.format("%s at %.1f m", tostring(s_Near.name), s_NearGap) or "none"
	p_Flash.picked = true
end

function Flash.Follow(p_Entity, p_From)
	if p_Entity == nil then
		return
	end

	local s_Id = p_Entity.uniqueId

	if Flash.followed[s_Id] ~= nil then
		return
	end

	local s_Spatial = SpatialEntity(p_Entity)
	local s_Start = s_Spatial.transform.trans
	local s_Flash = { entity = s_Spatial, at = Vec3(s_Start.x, s_Start.y, s_Start.z), start = SharedUtils:GetTimeMS(), picked = false,
		hookAt = p_From ~= nil and Vec3(p_From.trans.x, p_From.trans.y, p_From.trans.z) or nil }
	Flash.followed[s_Id] = s_Flash

	-- whose: from where the grenade itself is (once it has a place: as it is made it may still stand at the origin, and the hook's
	-- transform is not where it came out -- measured, every flashbang found nobody near the hook's)
	if not Flash.AtOrigin(s_Flash.at) then
		Flash.Pick(s_Flash, s_Flash.at)
	end

	p_Entity:RegisterDeinitCallback(function()
		local s_Flash = Flash.followed[s_Id]
		Flash.followed[s_Id] = nil

		if s_Flash ~= nil and not Flash.ending then
			Flash.gone[#Flash.gone + 1] = s_Flash
		end
	end)
end

function Flash.Tell(p_Flash)
	local s_Thrower = p_Flash.thrower
	local s_FriendlyFire = Flash.FriendlyFireOn()
	local s_Seconds = (SharedUtils:GetTimeMS() - p_Flash.start) / 1000.0
	NetEvents:Broadcast("TacticalSlots:Flash", p_Flash.at.x, p_Flash.at.y, p_Flash.at.z, s_Thrower ~= nil and s_Thrower.id or -1,
		s_Thrower ~= nil and s_Thrower.team or 0, s_FriendlyFire)

	if Flash.logged < 12 then
		Flash.logged = Flash.logged + 1
		local s_From = p_Flash.from ~= nil and string.format("came out at %.1f %.1f %.1f", p_Flash.from.x, p_Flash.from.y, p_Flash.from.z)
			or "never seen off the origin"
		local s_Hook = p_Flash.hookAt ~= nil and string.format("%.1f %.1f %.1f", p_Flash.hookAt.x, p_Flash.hookAt.y, p_Flash.hookAt.z) or "none"
		LOG(string.format("flashbang %d went off after %.2f s at %.1f %.1f %.1f, thrown by %s; friendly fire %s (%s, %s soldier(s) alive, the "
			.. "nearest %s; the hook's transform %s)", Flash.logged, s_Seconds, p_Flash.at.x, p_Flash.at.y, p_Flash.at.z,
			s_Thrower ~= nil and string.format("%s (team %s, %.2f m from where it came out)", tostring(s_Thrower.name),
			tostring(s_Thrower.team), p_Flash.gap or -1) or "NOBODY found near where it came out", tostring(s_FriendlyFire), s_From,
			tostring(p_Flash.soldiers), tostring(p_Flash.nearest), s_Hook))
	end
end

if not IS_CLIENT and FLASH_ENABLED then
	Hooks:Install("EntityFactory:CreateFromBlueprint", 100, function(p_Hook, p_Blueprint, p_Transform, p_Variation, p_Parent)
		if p_Blueprint == nil or p_Blueprint.instanceGuid ~= PROJ_BP_INST then
			return
		end

		local s_Bus = p_Hook:Call()

		if s_Bus ~= nil then
			for _, l_Entity in ipairs(s_Bus.entities) do
				if l_Entity.data ~= nil and l_Entity.data.instanceGuid == PROJ_DATA_INST then
					local l_Ok, l_Err = pcall(Flash.Follow, l_Entity, p_Transform)

					if not l_Ok then
						LOG("⛔ following a flashbang: " .. tostring(l_Err))
					end
				end
			end
		end
	end)

	Hooks:Install("EntityFactory:Create", 100, function(p_Hook, p_Data, p_Transform)
		if p_Data == nil or p_Data.instanceGuid ~= PROJ_DATA_INST then
			return
		end

		local s_Entity = p_Hook:Call()
		local s_Ok, s_Err = pcall(Flash.Follow, s_Entity, p_Transform)

		if not s_Ok then
			LOG("⛔ following a flashbang: " .. tostring(s_Err))
		end
	end)

	-- each flashbang's last place (where it is when it goes; whose, from its first place off the origin); the gone ones told
	Events:Subscribe("Engine:Update", function(p_Delta)
		for _, l_Flash in pairs(Flash.followed) do
			local l_Ok, l_Err = pcall(function()
				local l_Now = l_Flash.entity.transform.trans
				l_Flash.at = Vec3(l_Now.x, l_Now.y, l_Now.z)

				if not l_Flash.picked and not Flash.AtOrigin(l_Flash.at) then
					Flash.Pick(l_Flash, l_Flash.at)
				end
			end)

			if not l_Ok and not Flash.pickFailed then
				Flash.pickFailed = true
				LOG("⛔ following a flashbang's place: " .. tostring(l_Err))
			end
		end

		if #Flash.gone > 0 then
			local s_Gone = Flash.gone
			Flash.gone = {}

			for _, l_Flash in ipairs(s_Gone) do
				local s_Ok, s_Err = pcall(Flash.Tell, l_Flash)

				if not s_Ok then
					LOG("⛔ telling a flashbang's flash: " .. tostring(s_Err))
				end
			end
		end
	end)
end

Events:Subscribe("Level:Destroy", function()
	Flash.ending = true
	Flash.followed = {}
	Flash.gone = {}
	Flash.watch = nil
	Flash.enemy, Flash.friend, Flash.looks = nil, nil, {}
	Flash.logged = 0
	Flash.active = {}

	if Flash.white ~= nil then
		pcall(function() Flash.white.entity:Destroy() end)
		Flash.white = nil
	end
end)

Events:Subscribe("Level:LoadResources", function()
	Flash.ending = false
end)

_G.TACTICALSLOTS_FLASH = Flash
