-- TacticalSlots -- server: the mod's log, kept in its own database (Admin/Mods/TacticalSlots/mod.db, table notes), and the knife
-- each player's client sent when he deployed.
--
-- The client puts the chosen knife first in every kit's knife list and the game sends it on deploy; what the server then holds in
-- the knife slot (WeaponSlot_7) is the answer to "did the choice get through". Noted when he asks to spawn and when he spawns.

local m_Ready = false
local m_Seq = 0

local function Ensure()
	if m_Ready then
		return true
	end

	if not SQL:Open() then
		if _G.TACTICALSLOTS_PRINTS then
			print("[TacticalSlots][SRV] the mod database would not open -- lines go to the console only")
		end
		return false
	end

	SQL:Query("CREATE TABLE IF NOT EXISTS notes (seq INTEGER, ms INTEGER, who TEXT, line TEXT)")
	m_Ready = true
	return true
end

local function Note(p_Who, p_Line)
	m_Seq = m_Seq + 1

	if Ensure() then
		SQL:Query("INSERT INTO notes (seq, ms, who, line) VALUES (?, ?, ?, ?)", m_Seq, SharedUtils:GetTimeMS(), tostring(p_Who),
			tostring(p_Line))
	end
end

-- the shared script's lines (the server's own)
_G.TACTICALSLOTS_NOTE = Note

-- the client's lines, handed over by the shared script on his side
NetEvents:Subscribe("TacticalSlots:Log", function(p_Player, p_Line)
	if _G.TACTICALSLOTS_PRINTS then
		print("[TacticalSlots][CLI " .. tostring(p_Player and p_Player.name) .. "] " .. tostring(p_Line))
	end
	Note(p_Player and p_Player.name, p_Line)
end)

-- ---- each player's knife: picked in the deploy screen's knife slot (his client says TacticalSlots:Set), handed back to his client
-- when it loads a level (it asks: TacticalSlots:Ask -> TacticalSlots:Choice). Keyed by his account, as the camo framework keys its own.
local KNIVES = { machete = true, razor = true, knife = true }
local m_KnifeTable = false

local function PlayerKey(p_Player)
	local s_Key = nil
	pcall(function() s_Key = p_Player.accountGuid:ToString("D") end)

	if s_Key == nil or s_Key == "" or s_Key == "00000000-0000-0000-0000-000000000000" then
		s_Key = tostring(p_Player and p_Player.name)
	end

	return s_Key
end

local function KnifeTable()
	if m_KnifeTable then
		return true
	end

	if not Ensure() then
		return false
	end

	SQL:Query("CREATE TABLE IF NOT EXISTS knife (player TEXT PRIMARY KEY, knife TEXT)")
	m_KnifeTable = true
	return true
end

NetEvents:Subscribe("TacticalSlots:Set", function(p_Player, p_Key)
	local s_Key = tostring(p_Key)

	if p_Player == nil or not KNIVES[s_Key] or not KnifeTable() then
		Note(p_Player and p_Player.name, "knife '" .. s_Key .. "' NOT kept")
		return
	end

	SQL:Query("INSERT OR REPLACE INTO knife (player, knife) VALUES (?, ?)", PlayerKey(p_Player), s_Key)
	Note(p_Player.name, "knife '" .. s_Key .. "' kept")
end)

NetEvents:Subscribe("TacticalSlots:Ask", function(p_Player)
	if p_Player == nil or not KnifeTable() then
		return
	end

	local s_Rows = SQL:Query("SELECT knife FROM knife WHERE player = ?", PlayerKey(p_Player)) or {}
	local s_Key = s_Rows[1] ~= nil and tostring(s_Rows[1].knife) or nil

	if s_Key ~= nil and KNIVES[s_Key] then
		NetEvents:SendTo("TacticalSlots:Choice", p_Player, s_Key)
		Note(p_Player.name, "asked: his kept knife '" .. s_Key .. "' sent")
	else
		Note(p_Player.name, "asked: no knife kept (the game's own default)")
	end
end)

-- ---- each player's grenade: the same, for the grenade slot (TacticalSlots:GrenadeSet / GrenadeAsk -> GrenadeChoice, table grenade)
local GRENADES = { m67 = true, smoke = true }
local m_GrenadeTable = false

local function GrenadeTable()
	if m_GrenadeTable then
		return true
	end

	if not Ensure() then
		return false
	end

	SQL:Query("CREATE TABLE IF NOT EXISTS grenade (player TEXT PRIMARY KEY, grenade TEXT)")
	m_GrenadeTable = true
	return true
end

NetEvents:Subscribe("TacticalSlots:GrenadeSet", function(p_Player, p_Key)
	local s_Key = tostring(p_Key)

	if p_Player == nil or not GRENADES[s_Key] or not GrenadeTable() then
		Note(p_Player and p_Player.name, "grenade '" .. s_Key .. "' NOT kept")
		return
	end

	SQL:Query("INSERT OR REPLACE INTO grenade (player, grenade) VALUES (?, ?)", PlayerKey(p_Player), s_Key)
	Note(p_Player.name, "grenade '" .. s_Key .. "' kept")
end)

NetEvents:Subscribe("TacticalSlots:GrenadeAsk", function(p_Player)
	if p_Player == nil or not GrenadeTable() then
		return
	end

	local s_Rows = SQL:Query("SELECT grenade FROM grenade WHERE player = ?", PlayerKey(p_Player)) or {}
	local s_Key = s_Rows[1] ~= nil and tostring(s_Rows[1].grenade) or nil

	if s_Key ~= nil and GRENADES[s_Key] then
		NetEvents:SendTo("TacticalSlots:GrenadeChoice", p_Player, s_Key)
		Note(p_Player.name, "asked: his kept grenade '" .. s_Key .. "' sent")
	else
		Note(p_Player.name, "asked: no grenade kept (the game's own default)")
	end
end)

local function NameOf(p_Unlock)
	local s_Name = "nil"
	pcall(function() s_Name = tostring(UnlockAssetBase(p_Unlock).name) end)
	return s_Name
end

local KNIFE_SLOT = WeaponSlot.WeaponSlot_7
local GRENADE_SLOT = WeaponSlot.WeaponSlot_6

local function KnifeOf(p_Player)
	local s_Name = "nil"
	pcall(function() s_Name = NameOf(p_Player.weapons[KNIFE_SLOT + 1]) end)
	return s_Name
end

local function GrenadeOf(p_Player)
	local s_Name = "nil"
	pcall(function() s_Name = NameOf(p_Player.weapons[GRENADE_SLOT + 1]) end)
	return s_Name
end

for _, l_Event in ipairs({ "Player:SpawnOnSelectedSpawnPoint", "Player:SpawnOnPlayer", "Player:SpawnAtVehicle", "Player:Respawn" }) do
	Events:Subscribe(l_Event, function(p_Player)
		if p_Player == nil or p_Player.onlineId == 0 then
			return
		end

		local s_Line = l_Event .. ": knife slot holds " .. KnifeOf(p_Player) .. ", grenade slot holds " .. GrenadeOf(p_Player)
		if _G.TACTICALSLOTS_PRINTS then
			print("[TacticalSlots][SRV] " .. tostring(p_Player.name) .. " " .. s_Line)
		end
		Note(p_Player.name, s_Line)
	end)
end
