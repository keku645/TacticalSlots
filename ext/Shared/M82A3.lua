-- TacticalSlots -- shared: the M82A3, one more rifle in the recon's primary weapon list, with its accessories.
--
-- THE WEAPON. The game has the M82A3 whole -- its weapon, unlock, meshes, textures, variations, animation package, sound, bullet and
-- its own customization table (optics, bipod, laser sight / flashlight, each as an M82 unlock of its own) -- in the campaign only (the
-- SP_Villa level's main bundle). Our superbundle (tacticalslots/m82a3, loaded by ext/Shared/__init__.lua) holds only references to
-- those partitions, so on every multiplayer map they come in with the level, right after its main bundle; the accessories' meshes,
-- aiming and sights it uses are the multiplayer weapons' own (on every map's main bundle). Its sound plays 40 waves: most are on every
-- multiplayer map's main bundle (measured on the 29), the ones that are not ride in our bundle too -- its reloads, its close fire, and
-- the .50 casings falling on concrete and on wood (only the campaign has those; a casing on concrete with no wave there closes the
-- client at the first shot). Its ejected casing is a mesh particle of the campaign's (shells_large_mesh): a mesh is drawn with its
-- entry in a mesh variation database, and the casing's is in the campaign level's own; our bundle carries that one entry in a database
-- of its own (with no entry the client closes when the first casing is drawn). Before anything changes, the unlock, the accessories,
-- those sounds and the casing's entry must all be there (FIRING below).
-- Registered for the network here, in both realms, the same
-- order, as a multiplayer level registers its weapons (measured on MP_001's registry, the M98B: its unlock and every accessory unlock
-- of its customization in the asset registry, its weapon data, its blueprint; no bullet, no customization asset).
--
-- THE LIST. Every recon kit's primary weapon part lists the sniper rifles; the M82A3 is put at its END, in both realms. The game's own
-- screens show it -- its picker, its accessories screen (the weapon carries its customization) -- named by the game's UI descriptions
-- through the unlocks' identifiers (measured: the M82A3 and its accessories have none) -- our screen scripts name them. Picking it and
-- its accessories is the game's own, kept as any weapon's are. At the list's END so every rifle before it keeps its place.

-- ---- knobs ------------------------------------------------------------------------------------------------------------------
local M82A3_ENABLED = true            -- false: no M82A3 (the recon's primary weapon list as the game ships it)
local MESH3P_FIX_ENABLED = true       -- false: its third person mesh as the campaign ships it (the barrel floats on the customization screen)
-- -----------------------------------------------------------------------------------------------------------------------------

local IS_CLIENT = SharedUtils:IsClientModule()

local function LOG(p_Text)
	if _G.TACTICALSLOTS_LOG ~= nil then
		_G.TACTICALSLOTS_LOG("[m82a3] " .. tostring(p_Text))
	elseif _G.TACTICALSLOTS_PRINTS then
		print("[TacticalSlots][m82a3] " .. tostring(p_Text))
	end
end

-- the game's own (weapons/m82a3/u_m82a3, weapons/m82a3/m82a3)
local UNLOCK_PART = Guid("5B20A966-34C9-4B5F-AA20-6984AB4054F0")
local UNLOCK_INST = Guid("4B28E2E7-4F5D-455E-AC2E-C597763F5139")
local BP_PART = Guid("4155669B-F649-11DF-B195-DCFC5182825A")
local BP_INST = Guid("C5F55C5C-F05B-0E33-73BF-59D7D2AA1CFA")
local UNLOCK_NAME = "Weapons/M82A3/U_M82A3"

-- its accessories, the selectable unlocks of its customization table (weapons/m82a3/m82_customization), in the table's order
local ACCESSORIES = {
	{ "RifleScope", "5016C9D0-666F-11E0-BCBE-C9330074D87D", "36A31499-014D-3A99-4735-A05A63D01400" },
	{ "BallisticScope", "8B0676FC-666E-11E0-BCBE-C9330074D87D", "4D21E045-937E-6809-E089-9C33522DE26B" },
	{ "ACOG", "9FA4B85D-666E-11E0-BCBE-C9330074D87D", "E18247BD-CE11-5F8F-7860-02A2B5B88BBB" },
	{ "EOTech", "BE1264A7-666E-11E0-BCBE-C9330074D87D", "665058F5-90C0-586E-2DDC-529F100D8657" },
	{ "RX01", "59043F59-666F-11E0-BCBE-C9330074D87D", "C0894FEF-A924-5536-5640-AEB91977D83A" },
	{ "IRNV", "F439827C-666E-11E0-BCBE-C9330074D87D", "9DC27197-16D2-8500-3C53-801F3F612662" },
	{ "PKS-07", "3F1ACD0F-666F-11E0-BCBE-C9330074D87D", "A1000A0A-4C6E-DCD0-62DC-EFA4415272AD" },
	{ "M145", "213ADAB9-666F-11E0-BCBE-C9330074D87D", "73745BCE-2778-A789-1601-E0624936A2C3" },
	{ "PSO-1", "46A92850-666F-11E0-BCBE-C9330074D87D", "92A3D82C-6586-CB42-C754-9A20F269607B" },
	{ "PK-AS", "313DD155-666F-11E0-BCBE-C9330074D87D", "689B5DED-D243-78C7-ADB5-728E784B474D" },
	{ "Kobra", "186F6E4F-666F-11E0-BCBE-C9330074D87D", "0F4CFBC7-EE90-A434-2459-C5727E58A4F5" },
	{ "PKA", "29F558A5-666F-11E0-BCBE-C9330074D87D", "7FDAC12E-03E9-5C06-1070-3A89F9BEA456" },
	{ "Bipod", "756FE78F-666F-11E0-BCBE-C9330074D87D", "587F9CE8-00EE-C0A2-D96F-F28CCB2C2BEE" },
	{ "TargetPointer", "6DE958D5-666F-11E0-BCBE-C9330074D87D", "EA00424C-389A-3A52-B15B-593DDE766850" },
	{ "FlashLight", "D4768322-666E-11E0-BCBE-C9330074D87D", "183819CE-1547-390C-4510-BA35BDA150C5" },
}

-- what its first shot uses that only our bundle brings: its sound and the waves of it no multiplayer map has in its main bundle, and
-- the casing's mesh variation entry -- a wave or an entry asked for and not found is a null the game reads (the client closes), so
-- with any of them missing the M82A3 is not put in
local FIRING = {
	{ "Weapon_Sniper_M82A3", "07261A1C-A7D2-4F05-8AA4-E39EA2BA9BB7", "633EED42-02D0-4417-9625-312330503542" },
	{ "M82_Reload_Short_Wave", "07210E77-CF46-11E0-BE69-8B2063956F94", "173D6D32-ABA2-6741-E320-33DCF1E45CA2" },
	{ "M82_Reload_Long_Wave", "EFC6A9B7-CF45-11E0-BE69-8B2063956F94", "8B03C6DE-6BF3-2E50-B887-8CD9F6A5BB33" },
	{ "Bushmaster_Fire_Close_Wave", "90540CA6-FE5D-46A8-B305-75E5F330D7DA", "9407200B-8E8D-4DC1-A844-C98E5AD88696" },
	{ "Shell_Casing_50cal_concrete_Wave", "46134F64-9710-4E53-894E-5660EC417AFC", "46646BA5-14D3-44AD-A9AD-D0CF5346E232" },
	{ "Shell_Casing_50cal_wood_Wave", "8192D328-DE6A-4B7E-B811-BB3ED94ED628", "39021D42-B065-4C84-AB91-776486E04625" },
	{ "Shells_Large_MeshVariation", "6B4E1801-000E-4D18-8018-000000000001", "6B4E1801-000E-4D18-8018-000000000002" },
}

-- its customization table (weapons/m82a3/m82_customization) has the campaign's three parts -- optics, primary and secondary
-- accessory; every multiplayer weapon's has a fourth, last, holding only the game's "no camo" (weapons/common/nocamo, the row
-- "no camo" of the accessories screen), so a part of our own with that one is put at its end. Its bipod is taken out of its part
-- (that part keeps "no primary accessory"): the game picks a weapon's bipod animations (pose, zoomed pose, deploy, undeploy) in its
-- static animation bank, and for the M82A3 every one of those picks is empty (measured) -- deployed, the soldier's animations break
local TABLE_PART = Guid("B1374F55-666F-11E0-BCBE-C9330074D87D")
local TABLE_INST = Guid("CB794F00-B6CF-E032-F603-41153A1A3F61")
local NOCAMO_PART = Guid("1667D6AF-7996-11E1-9F39-9E1CE599C097")
local NOCAMO_INST = Guid("90DA90C5-2ED3-4CAC-A01E-8E5E75145945")

-- its third person mesh. The customization screen holds the rifle in a pose of the game's multiplayer animation bank that leaves the
-- barrel's bone (Wep_Extra1) where it rests, over the stock -- the barrel floats there. Our bundle carries the campaign's mesh with the
-- barrel's vertices moved to where the weapon's own data puts that bone and skinned to the weapon's root (weapons/m82a3/m82ts_3p_Mesh,
-- its own mesh variation entry): the barrel in place whatever the pose (it no longer recoils in third person)
local MESH3P_PART = Guid("6B4E1801-000E-4D18-8018-000000000020")
local MESH3P_INST = Guid("A5AC63F8-871E-CF6E-E9A1-9573668C591E")

-- the rifles a kit's primary weapon list holds (the recon's: any of the game's sniper rifles is what tells it)
local RIFLES = {
	["weapons/model98b/u_m98b"] = true, ["weapons/sv98/u_sv98"] = true, ["weapons/m40a5/u_m40a5"] = true, ["weapons/svd/u_svd"] = true,
	["weapons/mk11/u_mk11"] = true, ["weapons/m39ebr/u_m39ebr"] = true, ["weapons/xp1_l96/u_l96"] = true, ["weapons/xp2_jng90/u_jng90"] = true,
}

local TEAMS = { "US", "RU" }
local KIT_SUFFIXES = { "", "_GM", "_XP4", "_GM_XP4", "_XP4_SCV" }

local m_Built = false

local function NameOf(p_Unlock)
	local s_Name = "?"
	pcall(function() s_Name = tostring(UnlockAssetBase(p_Unlock).name) end)
	return s_Name
end

-- the recon kit's primary weapon part: the one listing a sniper rifle
local function RiflePartOf(p_Kit)
	local s_Table = p_Kit.weaponTable

	if s_Table == nil then
		return nil
	end

	for p = 1, #s_Table.unlockParts do
		local l_Part = s_Table.unlockParts[p]

		for u = 1, #l_Part.selectableUnlocks do
			if RIFLES[string.lower(NameOf(l_Part.selectableUnlocks[u]))] then
				return l_Part, p
			end
		end
	end

	return nil
end

-- its customization table as the multiplayer weapons': the bipod out of its part, the camo part at the end -- once each (a second
-- build of the same level finds them done)
local function FitTable()
	local s_Table = ResourceManager:FindInstanceByGuid(TABLE_PART, TABLE_INST)
	local s_NoCamo = ResourceManager:FindInstanceByGuid(NOCAMO_PART, NOCAMO_INST)

	if s_Table == nil or s_NoCamo == nil then
		return "⛔ its table not fitted (its table " .. tostring(s_Table ~= nil) .. ", the game's no camo " .. tostring(s_NoCamo ~= nil) .. ")"
	end

	s_Table = CustomizationTable(s_Table)
	local s_Said = {}

	for p = 1, #s_Table.unlockParts do
		local l_Part = s_Table.unlockParts[p]

		for u = #l_Part.selectableUnlocks, 1, -1 do
			if string.lower(NameOf(l_Part.selectableUnlocks[u])) == "weapons/m82a3/u_m82_bipod" then
				l_Part:MakeWritable()
				l_Part.selectableUnlocks:erase(u)
				s_Said[#s_Said + 1] = "its bipod taken out of part " .. tostring(p - 1) .. " (" .. tostring(#l_Part.selectableUnlocks) .. " left)"
			end
		end
	end

	if #s_Table.unlockParts < 4 then
		local s_Part = CustomizationUnlockParts()
		s_Part.uiCategorySid = ""
		s_Part.selectableUnlocks:add(UnlockAssetBase(s_NoCamo))
		s_Table:MakeWritable()
		s_Table.unlockParts:add(s_Part)
		s_Said[#s_Said + 1] = "a camo part put last in its table (no camo)"
	end

	return #s_Said > 0 and table.concat(s_Said, ", ") or "its table already fitted"
end

-- its third person mesh pointed at ours (the weapon state's own copy written back); left the game's when ours is not loaded
local function FitMesh3p(p_Weapon)
	if not MESH3P_FIX_ENABLED then
		return "its third person mesh the game's (knob off)"
	end

	local s_Mesh = ResourceManager:FindInstanceByGuid(MESH3P_PART, MESH3P_INST)

	if s_Mesh == nil then
		return "⛔ its third person mesh left the game's: ours is not loaded"
	end

	local s_Ok, s_Err = pcall(function()
		p_Weapon:MakeWritable()
		local s_State = p_Weapon.weaponStates[1]
		s_State.mesh3p = SkinnedMeshAsset(s_Mesh)
		p_Weapon.weaponStates[1] = s_State
	end)

	return s_Ok and "its third person mesh ours (the barrel in place)" or ("⛔ its third person mesh not set: " .. tostring(s_Err))
end

local function Build()
	local s_Unlock = ResourceManager:FindInstanceByGuid(UNLOCK_PART, UNLOCK_INST)
	local s_Blueprint = ResourceManager:FindInstanceByGuid(BP_PART, BP_INST)
	local s_Accessories = {}
	local s_Missing = {}

	for _, l_Accessory in ipairs(ACCESSORIES) do
		local l_Found = ResourceManager:FindInstanceByGuid(Guid(l_Accessory[2]), Guid(l_Accessory[3]))

		if l_Found ~= nil then
			s_Accessories[#s_Accessories + 1] = UnlockAssetBase(l_Found)
		else
			s_Missing[#s_Missing + 1] = l_Accessory[1]
		end
	end

	local s_Absent = {}

	for _, l_Piece in ipairs(FIRING) do
		if ResourceManager:FindInstanceByGuid(Guid(l_Piece[2]), Guid(l_Piece[3])) == nil then
			s_Absent[#s_Absent + 1] = l_Piece[1]
		end
	end

	if s_Unlock == nil or s_Blueprint == nil or #s_Missing > 0 or #s_Absent > 0 then
		LOG("⛔ the M82A3 is not loaded (unlock " .. tostring(s_Unlock ~= nil) .. ", blueprint " .. tostring(s_Blueprint ~= nil)
			.. ", accessories missing: " .. (#s_Missing > 0 and table.concat(s_Missing, ", ") or "none")
			.. ", firing pieces missing: " .. (#s_Absent > 0 and table.concat(s_Absent, ", ") or "none") .. "): our bundle did not come in -- nothing changed")
		return
	end

	s_Unlock = SoldierWeaponUnlockAsset(s_Unlock)
	s_Blueprint = SoldierWeaponBlueprint(s_Blueprint)
	local s_Weapon = SoldierWeaponData(s_Blueprint.object)

	-- in both realms, the same order (network ids): the unlock and its accessories, the blueprint, the weapon data
	local s_Registry = RegistryContainer()
	s_Registry.assetRegistry:add(s_Unlock)

	for _, l_Accessory in ipairs(s_Accessories) do
		s_Registry.assetRegistry:add(l_Accessory)
	end

	s_Registry.blueprintRegistry:add(s_Blueprint)
	s_Registry.entityRegistry:add(s_Weapon)
	ResourceManager:AddRegistry(s_Registry, ResourceCompartment.ResourceCompartment_Game)

	local s_Lists = 0
	local s_Said = { FitTable(), FitMesh3p(s_Weapon) }

	for _, l_Team in ipairs(TEAMS) do
		for _, l_Suffix in ipairs(KIT_SUFFIXES) do
			local l_Name = "Gameplay/Kits/" .. l_Team .. "Recon" .. l_Suffix
			local l_Found = ResourceManager:SearchForDataContainer(l_Name)

			if l_Found ~= nil then
				local l_Ok, l_Err = pcall(function()
					local l_Part, l_At = RiflePartOf(SoldierCustomizationAsset(l_Found))

					if l_Part == nil then
						s_Said[#s_Said + 1] = l_Name .. ": no rifle list"
						return
					end

					-- at its end, once (a second build of the same level finds it there)
					for u = 1, #l_Part.selectableUnlocks do
						if string.lower(NameOf(l_Part.selectableUnlocks[u])) == string.lower(UNLOCK_NAME) then
							return
						end
					end

					l_Part:MakeWritable()
					l_Part.selectableUnlocks:add(s_Unlock)
					s_Lists = s_Lists + 1

					if s_Lists == 1 then
						local l_Now = {}

						for u = 1, #l_Part.selectableUnlocks do
							l_Now[#l_Now + 1] = (NameOf(l_Part.selectableUnlocks[u]):match("[^/]+$"))
						end

						s_Said[#s_Said + 1] = l_Name .. " part " .. tostring(l_At - 1) .. " now [" .. table.concat(l_Now, ", ") .. "]"
					end
				end)

				if not l_Ok then
					s_Said[#s_Said + 1] = "⛔ " .. l_Name .. ": " .. tostring(l_Err)
				end
			end
		end
	end

	m_Built = true
	LOG(string.format("the M82A3 registered with %d accessories and its %d firing pieces found, identifier %s; put at the end of %d recon primary weapon list(s)%s; %s",
		#s_Accessories, #FIRING, tostring(s_Unlock.identifier), s_Lists, IS_CLIENT and "" or " (server)", table.concat(s_Said, " | ")))
end

if M82A3_ENABLED then
	Events:Subscribe("Level:RegisterEntityResources", function()
		if m_Built or not _G.TACTICALSLOTS_M82A3_MOUNTED then
			return
		end

		local s_Ok, s_Err = pcall(Build)

		if not s_Ok then
			LOG("⛔ build: " .. tostring(s_Err))
		end
	end)
end

Events:Subscribe("Level:Destroy", function()
	m_Built = false
end)
