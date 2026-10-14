-- TacticalSlots -- shared: the machete on every multiplayer map, the knife slot that offers it, and the player's choice.
--
-- THE MACHETE. The game has it, but only the campaign levels Paris and Villa carry it. Our superbundle holds only its own seven
-- partitions (the weapon, its unlock, both meshes, both textures and its variation database), as references into the player's
-- own game data. Everything else it points at (the knife's sounds, aiming and camera data, the weapon shader, the dust texture)
-- sits in the level's MAIN bundle on every multiplayer map, so our bundle loads right AFTER that bundle, in the same call, and
-- its imports resolve against it. Its first-person mesh data comes in the weapon's own bundle, which the game loads by itself
-- when a soldier is given the machete.
--
-- THE KNIFE SLOT. Every kit's weapon table has a knife part listing [ACB-90, knife]. When a player deploys, his client sends the
-- FIRST eligible knife of that list (measured: the deploy code asks for index 0, no profile, no menu). So the choice is the
-- order of that list on the player's own client. The machete is added to the list in both realms: the server checks what the
-- client sends against its own copy (measured 2026-10-14: it takes the machete).
--
-- THE CHOICE. The deploy screen's knife slot (the UI build merged into this mod: ext/Shared/TacticalSlotsShared.lua mounts its
-- bundle, ext/Client/KnifeTab.lua hears its picks) calls TACTICALSLOTS_KNIFE_CHOOSE. The choice is put first in every kit's list, written
-- into the screen's mailbox (the KnifeSelSet DataSetNode's Param, which the screen pulls to show the slot), and kept by the server
-- (Admin/Mods/TacticalSlots/mod.db, table knife), which hands it back when the player's client loads a level.

-- ---- knobs ------------------------------------------------------------------------------------------------------------------
-- The knife the game sends when the player has not chosen one: the first of the game's own list. "machete" | "razor" | "knife"
local DEFAULT_KNIFE = "razor"

-- Levels that already carry the machete in their own bundle: ours would load a second copy of the same partitions.
local SKIP_LEVELS = { sp_paris = true, sp_villa = true, frontend = true }

-- The mod's lines in the client's and the server's console (the server keeps them in mod.db either way). false = silent.
local PRINTS = false
-- -----------------------------------------------------------------------------------------------------------------------------

local SUPERBUNDLE = "tacticalslots/machete"
local BUNDLE = "tacticalslots/machetebundle"

-- The M18 smoke grenade's superbundle (ext/Shared/SmokeGrenade.lua): its hand meshes, its projectile and collision, the signal smoke
-- it turns grey. Loaded right after the machete's, the same way; every multiplayer map (the menu has no use for it).
local SMOKE_SUPERBUNDLE = "tacticalslots/smoke"
local SMOKE_BUNDLE = "tacticalslots/smokebundle"
local SMOKE_SKIP_LEVELS = { frontend = true }

local KNIVES = {
	machete = "Weapons/Machete/U_Machete",
	razor = "Weapons/XP2_Knife_RazorBlade/U_Knife_Razor",
	knife = "Weapons/Knife/U_Knife",
}

-- the machete's unlock and blueprint, as the game ships them
local MACHETE_UNLOCK_PART = Guid("55B4E2D8-C772-425D-A6D0-8910EBE8C4C1")
local MACHETE_UNLOCK_INST = Guid("40A84898-626F-4976-9D6A-CF8158C68C68")
local MACHETE_BP_PART = Guid("14C4CC08-7012-11E0-8382-CF9D6AEDA2D0")
local MACHETE_BP_INST = Guid("1D83D193-C17A-3906-8A26-81037E0AE6C7")

-- the deploy screen (our copy of it rides in the UI bundle under the game's own guid) and its mailbox node
local SPAWN_SCREEN_PART = Guid("68C43870-078E-11E0-B752-B997645AD52D")
local MAIL_NODE = "KnifeSelSet"
local GRENADE_MAIL_NODE = "GrenadeSelSet"

local TEAMS = { "US", "RU" }
local CLASSES = { "Assault", "Engineer", "Support", "Recon" }
local KIT_SUFFIXES = { "", "_GM", "_XP4", "_GM_XP4", "_XP4_SCV" }

local IS_CLIENT = SharedUtils:IsClientModule()

local m_Active = false
local m_SmokeActive = false
local m_Built = false
local m_Chosen = DEFAULT_KNIFE      -- the client's choice (the server's copy of the lists only ever appends the machete)
local m_KnifeParts = {}             -- this level's kits' knife lists: { part, kit name }
local m_ByKey = {}                  -- this level's knife unlocks by key
local m_MailNodes = {}              -- every loaded copy of the deploy screen's KnifeSelSet (the screen loads more than once)

_G.TACTICALSLOTS_PRINTS = PRINTS

local function LOG(p_Text)
	local s_Line = tostring(p_Text)
	if PRINTS then
		print("[TacticalSlots][" .. (IS_CLIENT and "CLI" or "SRV") .. "] " .. s_Line)
	end

	-- the server keeps its lines in the mod's database; the client hands its own to the server
	if IS_CLIENT then
		pcall(function() NetEvents:Send("TacticalSlots:Log", s_Line) end)
	elseif _G.TACTICALSLOTS_NOTE ~= nil then
		pcall(_G.TACTICALSLOTS_NOTE, "server", s_Line)
	end
end

_G.TACTICALSLOTS_LOG = LOG

local function NameOf(p_Unlock)
	local s_Name = "?"
	pcall(function() s_Name = tostring(UnlockAssetBase(p_Unlock).name) end)
	return s_Name
end

local function KeyOf(p_Name)
	for l_Key, l_Name in pairs(KNIVES) do
		if string.lower(l_Name) == string.lower(p_Name) then
			return l_Key
		end
	end

	return nil
end

-- ---- delivery -----------------------------------------------------------------------------------------------------------------
Events:Subscribe("Level:LoadResources", function(p_LevelName)
	m_Active, m_SmokeActive, m_Built = false, false, false
	_G.TACTICALSLOTS_SMOKE_MOUNTED = false

	local s_Leaf = string.lower(tostring(p_LevelName):match("[^/]+$") or "")

	if not SMOKE_SKIP_LEVELS[s_Leaf] then
		local s_SmokeOk, s_SmokeErr = pcall(function() ResourceManager:MountSuperBundle(SMOKE_SUPERBUNDLE) end)
		LOG("mount '" .. SMOKE_SUPERBUNDLE .. "': " .. (s_SmokeOk and "OK" or ("FAILED " .. tostring(s_SmokeErr))))
		m_SmokeActive = s_SmokeOk
		_G.TACTICALSLOTS_SMOKE_MOUNTED = s_SmokeOk
	end

	if SKIP_LEVELS[s_Leaf] then
		LOG("level " .. tostring(p_LevelName) .. " carries the machete itself (or is the menu): our bundle stays out")
		return
	end

	local s_Ok, s_Err = pcall(function() ResourceManager:MountSuperBundle(SUPERBUNDLE) end)
	LOG("mount '" .. SUPERBUNDLE .. "': " .. (s_Ok and "OK" or ("FAILED " .. tostring(s_Err))))
	m_Active = s_Ok

	-- the client asks the server for the knife it keeps for this player (the answer is TacticalSlots:Choice)
	if IS_CLIENT then
		pcall(function() NetEvents:Send("TacticalSlots:Ask") end)
	end
end)

-- Our bundle goes right AFTER the level's main bundle, in the call that loads it. Keyed on the level's bundle being in the
-- list, never on the list's length or position, so another mod adding its own first cannot stop this from firing.
Hooks:Install("ResourceManager:LoadBundles", 100, function(p_Hook, p_Bundles, p_Compartment)
	local s_Ours = {}

	if m_Active then
		s_Ours[#s_Ours + 1] = BUNDLE
	end

	if m_SmokeActive then
		s_Ours[#s_Ours + 1] = SMOKE_BUNDLE
	end

	if #s_Ours == 0 then
		return
	end

	local s_Level = string.lower(tostring(SharedUtils:GetLevelName()))

	if s_Level == "" or s_Level == "nil" then
		return
	end

	local s_At = nil

	for i, l_Bundle in ipairs(p_Bundles) do
		if l_Bundle == BUNDLE or l_Bundle == SMOKE_BUNDLE then
			return
		end

		if s_At == nil and string.lower(l_Bundle) == s_Level then
			s_At = i
		end
	end

	if s_At == nil then
		return
	end

	local s_New = {}

	for i, l_Bundle in ipairs(p_Bundles) do
		s_New[#s_New + 1] = l_Bundle

		if i == s_At then
			for _, l_Ours in ipairs(s_Ours) do
				s_New[#s_New + 1] = l_Ours
			end
		end
	end

	LOG("bundle(s) '" .. table.concat(s_Ours, "', '") .. "' load right after " .. p_Bundles[s_At] .. " (" .. #p_Bundles
		.. " bundle(s) in the call, compartment " .. tostring(p_Compartment) .. ")")
	p_Hook:Pass(s_New, p_Compartment)
end)

-- ---- the order of the knife lists -----------------------------------------------------------------------------------------------
-- A kit's list rebuilt from this level's knives: the kit's own in its order, the machete at the end; on the client the choice first.
local function OrderFor(p_Kept)
	local s_Order = {}

	for _, l_Key in ipairs(p_Kept) do
		if l_Key ~= "machete" and m_ByKey[l_Key] ~= nil then
			s_Order[#s_Order + 1] = l_Key
		end
	end

	s_Order[#s_Order + 1] = "machete"

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

-- The deploy screen's mailbox: the Param its KnifeSelSet writes when the screen pulls it (the slot shows that knife).
-- The screen's partition loads more than once per level and the screen may run any of the copies, so every copy is written
-- (measured 2026-10-14: writing only the last copy left the screen showing the knife of the level's start). Returns how many.
local function WriteMailbox(p_Why)
	local s_Written = 0

	for _, l_Node in ipairs(m_MailNodes) do
		local s_Ok, s_Err = pcall(function()
			l_Node:MakeWritable()
			l_Node.param = m_Chosen
		end)

		if s_Ok then
			s_Written = s_Written + 1
		else
			LOG("⛔ mailbox (" .. tostring(p_Why) .. "): " .. tostring(s_Err))
		end
	end

	return s_Written
end

-- The knife part of a kit's weapon table: the part that lists the game's own knives.
local function KnifePartOf(p_Kit)
	local s_Table = p_Kit.weaponTable

	if s_Table == nil then
		return nil
	end

	for p = 1, #s_Table.unlockParts do
		local l_Part = s_Table.unlockParts[p]

		for u = 1, #l_Part.selectableUnlocks do
			local l_Key = KeyOf(NameOf(l_Part.selectableUnlocks[u]))

			if l_Key == "razor" or l_Key == "knife" then
				return l_Part, p
			end
		end
	end

	return nil
end

local function Build()
	local s_Unlock = ResourceManager:FindInstanceByGuid(MACHETE_UNLOCK_PART, MACHETE_UNLOCK_INST)
	local s_Blueprint = ResourceManager:FindInstanceByGuid(MACHETE_BP_PART, MACHETE_BP_INST)

	if s_Unlock == nil or s_Blueprint == nil then
		LOG("⛔ the machete is not loaded (unlock " .. tostring(s_Unlock ~= nil) .. ", blueprint " .. tostring(s_Blueprint ~= nil)
			.. "): our bundle did not come in -- nothing changed")
		return
	end

	s_Unlock = SoldierWeaponUnlockAsset(s_Unlock)
	s_Blueprint = SoldierWeaponBlueprint(s_Blueprint)
	local s_Weapon = SoldierWeaponData(s_Blueprint.object)

	-- the same three, in the same order, in both realms (network ids)
	local s_Registry = RegistryContainer()
	s_Registry.assetRegistry:add(s_Unlock)
	s_Registry.blueprintRegistry:add(s_Blueprint)
	s_Registry.entityRegistry:add(s_Weapon)
	ResourceManager:AddRegistry(s_Registry, ResourceCompartment.ResourceCompartment_Game)

	-- the knives as this level has them, by name (the lists are rebuilt from these, never from what a kit held before)
	m_ByKey = { machete = s_Unlock }
	m_KnifeParts = {}

	for l_Key, l_Name in pairs(KNIVES) do
		if m_ByKey[l_Key] == nil then
			local l_Found = ResourceManager:SearchForDataContainer(l_Name)

			if l_Found ~= nil then
				m_ByKey[l_Key] = SoldierWeaponUnlockAsset(l_Found)
			end
		end
	end

	local s_Said = {}

	for _, l_Team in ipairs(TEAMS) do
		for _, l_Class in ipairs(CLASSES) do
			for _, l_Suffix in ipairs(KIT_SUFFIXES) do
				local l_Name = "Gameplay/Kits/" .. l_Team .. l_Class .. l_Suffix
				local l_Found = ResourceManager:SearchForDataContainer(l_Name)

				if l_Found ~= nil then
					local l_Ok, l_Err = pcall(function()
						local l_Part, l_At = KnifePartOf(SoldierCustomizationAsset(l_Found))

						if l_Part == nil then
							s_Said[#s_Said + 1] = l_Name .. ": no knife list"
							return
						end

						-- the kit's own knives, in its order
						local l_Kept = {}

						for u = 1, #l_Part.selectableUnlocks do
							local l_Key = KeyOf(NameOf(l_Part.selectableUnlocks[u]))

							if l_Key ~= nil then
								l_Kept[#l_Kept + 1] = l_Key
							end
						end

						WriteList(l_Part, OrderFor(l_Kept))
						m_KnifeParts[#m_KnifeParts + 1] = { part = l_Part, kit = l_Name, kept = l_Kept, at = l_At }

						if #m_KnifeParts == 1 then
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
	LOG(string.format("machete registered; knife list set in %d kit(s)%s; %s", #m_KnifeParts,
		IS_CLIENT and (", '" .. m_Chosen .. "' first") or " (server: the machete added at the end)",
		table.concat(s_Said, " | ")))
end

Events:Subscribe("Level:RegisterEntityResources", function()
	if not m_Active or m_Built then
		return
	end

	local s_Ok, s_Err = pcall(Build)

	if not s_Ok then
		LOG("⛔ build: " .. tostring(s_Err))
	end
end)

-- ---- the choice (client) ------------------------------------------------------------------------------------------------------
-- p_Tell = true: the server keeps it (a pick); false: it came from the server.
local function Choose(p_Key, p_Why, p_Tell)
	local s_Key = tostring(p_Key)

	if KNIVES[s_Key] == nil then
		LOG("⛔ choose: '" .. s_Key .. "' is not a knife of ours (" .. tostring(p_Why) .. ")")
		return
	end

	m_Chosen = s_Key
	local s_Lists = 0

	for _, l_Entry in ipairs(m_KnifeParts) do
		local l_Ok = pcall(function() WriteList(l_Entry.part, OrderFor(l_Entry.kept)) end)

		if l_Ok then
			s_Lists = s_Lists + 1
		end
	end

	local s_Mail = WriteMailbox(p_Why)

	if p_Tell then
		pcall(function() NetEvents:Send("TacticalSlots:Set", s_Key) end)
	end

	LOG(string.format("knife '%s' (%s): first in %d kit list(s)%s; mailbox %s", s_Key, tostring(p_Why), s_Lists,
		#m_KnifeParts > 0 and (" -- " .. m_KnifeParts[1].kit .. " " .. ListText(m_KnifeParts[1].part)) or "",
		#m_MailNodes > 0 and string.format("written in %d of %d copies", s_Mail, #m_MailNodes) or "not loaded yet"))
end

if IS_CLIENT then
	_G.TACTICALSLOTS_KNIFE_CHOOSE = Choose

	NetEvents:Subscribe("TacticalSlots:Choice", function(p_Key)
		Choose(p_Key, "kept by the server", false)
	end)

	-- the deploy screen loads: its mailbox node takes the choice before the screen pulls it (the grenade slot's mailbox,
	-- GrenadeSelSet, is collected here too and written by ext/Shared/SmokeGrenade.lua)
	_G.TACTICALSLOTS_GRENADE_NODES = {}

	ResourceManager:RegisterPartitionLoadHandler(SPAWN_SCREEN_PART, function(p_Partition)
		local s_Found = false
		local s_FoundGrenade = false

		local s_Ok, s_Err = pcall(function()
			local s_Screen = UIScreenAsset(p_Partition.primaryInstance)

			for n = 1, #s_Screen.nodes do
				local l_Node = s_Screen.nodes[n]

				if l_Node ~= nil and l_Node.typeInfo.name == "DataSetNode" then
					local l_Set = DataSetNode(l_Node)

					if l_Set.name == MAIL_NODE then
						m_MailNodes[#m_MailNodes + 1] = l_Set
						s_Found = true
					elseif l_Set.name == GRENADE_MAIL_NODE then
						_G.TACTICALSLOTS_GRENADE_NODES[#_G.TACTICALSLOTS_GRENADE_NODES + 1] = l_Set
						s_FoundGrenade = true
					end
				end
			end
		end)

		if s_FoundGrenade and _G.TACTICALSLOTS_GRENADE_SCREEN_LOADED ~= nil then
			pcall(_G.TACTICALSLOTS_GRENADE_SCREEN_LOADED)
		end

		if not s_Ok then
			LOG("⛔ deploy screen: " .. tostring(s_Err))
			return
		end

		if s_Found then
			local s_Written = WriteMailbox("screen loaded")
			LOG(string.format("deploy screen loaded (copy %d this level): mailbox found, '%s' written in %d of %d copies",
				#m_MailNodes, m_Chosen, s_Written, #m_MailNodes))
		else
			LOG("deploy screen loaded: mailbox NOT found (no " .. MAIL_NODE .. " node: the screen is the game's own, not ours)")
		end
	end)
end

-- a screen's data is released with the level (a reference kept past it crashes the client in a finalizer)
Events:Subscribe("Level:Destroy", function()
	m_Built = false
	m_KnifeParts = {}
	m_ByKey = {}
	m_MailNodes = {}
	_G.TACTICALSLOTS_GRENADE_NODES = {}
end)

-- the M18 smoke grenade and the grenade slot's choice
require('__shared/SmokeGrenade')

-- the deploy screen's knife slot (the UI build merged into this mod)
require('__shared/TacticalSlotsShared')
