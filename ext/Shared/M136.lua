-- TacticalSlots -- shared: the M136 AT4, one more launcher in the engineer's gadget 1 list.
--
-- THE WEAPON. The game has the M136 whole -- its weapon, unlock, meshes, textures, variation, animation package and sound -- in the
-- campaign and on one multiplayer map (MP_012, in its main bundle). Our superbundle (tacticalslots/m136, loaded by ext/Shared/__init__.lua)
-- holds only references to those partitions, so on every other map they come in with the level, right after its main bundle; on MP_012
-- the level brings them itself. Its rocket is the RPG-7's (on every multiplayer map). The unlock, blueprint and weapon data are
-- registered for the network here, in both realms, the same order (as the machete is).
--
-- THE LIST. Every engineer kit's gadget 1 part lists the launchers and the crossbows; the M136 is put at its END, in both realms. The
-- game's own picker shows a cell per unlock of that list, named by the game's UI descriptions through the unlock's identifier (measured:
-- the M136 has none, so its name and picture come out empty) -- the deploy screen's script names that cell, and the bar's slot when it
-- holds it, "M136 AT4" with its picture. Picking it is the game's own: the slot keeps the picked unlock's identifier and the deploy sends
-- the unlock of the list with that identifier (measured in the client's deploy code), so the choice is kept as any gadget's is. At the
-- list's END so every cell before it keeps its place (a gadget a player kept stays his).

-- ---- knobs ------------------------------------------------------------------------------------------------------------------
local M136_ENABLED = true             -- false: no M136 (the engineer's gadget 1 list as the game ships it)
-- -----------------------------------------------------------------------------------------------------------------------------

local IS_CLIENT = SharedUtils:IsClientModule()

local function LOG(p_Text)
	if _G.TACTICALSLOTS_LOG ~= nil then
		_G.TACTICALSLOTS_LOG("[m136] " .. tostring(p_Text))
	elseif _G.TACTICALSLOTS_PRINTS then
		print("[TacticalSlots][m136] " .. tostring(p_Text))
	end
end

-- the game's own (weapons/m136/u_m136, weapons/m136/m136)
local UNLOCK_PART = Guid("648AD83F-C199-4DA9-B40A-64F0D19DBEF6")
local UNLOCK_INST = Guid("08513814-B7DC-4BB9-8A00-6462938D0AEA")
local BP_PART = Guid("D487DEBD-EB3C-11DF-B5BF-9988EEC5C3D3")
local BP_INST = Guid("CB1AD75B-5CC3-FE67-1F62-8B1D314F53A1")
local UNLOCK_NAME = "Weapons/M136/U_M136"

-- the launchers a kit's gadget 1 list holds (the engineer's: the SMAW or the RPG-7 is what tells it)
local LAUNCHERS = { ["weapons/smaw/u_smaw"] = true, ["weapons/rpg7/u_rpg7"] = true }

-- maps whose own bundle registers the M136 (its partitions come with the level: no second registration)
local LEVEL_REGISTERS = { mp_012 = true }

local TEAMS = { "US", "RU" }
local KIT_SUFFIXES = { "", "_GM", "_XP4", "_GM_XP4", "_XP4_SCV" }

local m_Built = false

local function NameOf(p_Unlock)
	local s_Name = "?"
	pcall(function() s_Name = tostring(UnlockAssetBase(p_Unlock).name) end)
	return s_Name
end

-- the engineer kit's gadget 1 part: the one listing the SMAW or the RPG-7
local function LauncherPartOf(p_Kit)
	local s_Table = p_Kit.weaponTable

	if s_Table == nil then
		return nil
	end

	for p = 1, #s_Table.unlockParts do
		local l_Part = s_Table.unlockParts[p]

		for u = 1, #l_Part.selectableUnlocks do
			if LAUNCHERS[string.lower(NameOf(l_Part.selectableUnlocks[u]))] then
				return l_Part, p
			end
		end
	end

	return nil
end

local function Build()
	local s_Unlock = ResourceManager:FindInstanceByGuid(UNLOCK_PART, UNLOCK_INST)
	local s_Blueprint = ResourceManager:FindInstanceByGuid(BP_PART, BP_INST)

	if s_Unlock == nil or s_Blueprint == nil then
		LOG("⛔ the M136 is not loaded (unlock " .. tostring(s_Unlock ~= nil) .. ", blueprint " .. tostring(s_Blueprint ~= nil)
			.. "): our bundle did not come in -- nothing changed")
		return
	end

	s_Unlock = SoldierWeaponUnlockAsset(s_Unlock)
	s_Blueprint = SoldierWeaponBlueprint(s_Blueprint)
	local s_Weapon = SoldierWeaponData(s_Blueprint.object)
	local s_Level = string.lower(tostring(SharedUtils:GetLevelName()):match("[^/]+$") or "")
	local s_Registered = "registered"

	-- the same three, in the same order, in both realms (network ids); a map that carries the M136 registers it itself
	if LEVEL_REGISTERS[s_Level] then
		s_Registered = "the level's own (not registered again)"
	else
		local s_Registry = RegistryContainer()
		s_Registry.assetRegistry:add(s_Unlock)
		s_Registry.blueprintRegistry:add(s_Blueprint)
		s_Registry.entityRegistry:add(s_Weapon)
		ResourceManager:AddRegistry(s_Registry, ResourceCompartment.ResourceCompartment_Game)
	end

	local s_Lists = 0
	local s_Said = {}

	for _, l_Team in ipairs(TEAMS) do
		for _, l_Suffix in ipairs(KIT_SUFFIXES) do
			local l_Name = "Gameplay/Kits/" .. l_Team .. "Engineer" .. l_Suffix
			local l_Found = ResourceManager:SearchForDataContainer(l_Name)

			if l_Found ~= nil then
				local l_Ok, l_Err = pcall(function()
					local l_Part, l_At = LauncherPartOf(SoldierCustomizationAsset(l_Found))

					if l_Part == nil then
						s_Said[#s_Said + 1] = l_Name .. ": no launcher list"
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
	LOG(string.format("the M136 %s, identifier %s; put at the end of %d engineer gadget 1 list(s)%s; %s", s_Registered,
		tostring(s_Unlock.identifier), s_Lists, IS_CLIENT and "" or " (server)", table.concat(s_Said, " | ")))
end

if M136_ENABLED then
	Events:Subscribe("Level:RegisterEntityResources", function()
		local s_Level = string.lower(tostring(SharedUtils:GetLevelName()):match("[^/]+$") or "")

		if m_Built or not (_G.TACTICALSLOTS_M136_MOUNTED or LEVEL_REGISTERS[s_Level]) then
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
