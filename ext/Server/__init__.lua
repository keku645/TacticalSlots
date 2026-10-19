-- TacticalSlots -- server: each player's knife and grenade, kept in the mod's own database (mod.db, tables knife and grenade) and
-- handed back to his client when it loads a level.

local m_Ready = false

local function Ensure()
	if m_Ready then
		return true
	end

	if not SQL:Open() then
		if _G.TACTICALSLOTS_PRINTS then
			print("[TacticalSlots][SRV] the mod database would not open -- choices are not kept")
		end
		return false
	end

	m_Ready = true
	return true
end

-- ---- each player's knife: picked in the deploy screen's knife slot (his client says TacticalSlots:Set), handed back to his client
-- when it loads a level (it asks: TacticalSlots:Ask -> TacticalSlots:Choice). Keyed by his account.
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
		return
	end

	SQL:Query("INSERT OR REPLACE INTO knife (player, knife) VALUES (?, ?)", PlayerKey(p_Player), s_Key)
end)

NetEvents:Subscribe("TacticalSlots:Ask", function(p_Player)
	if p_Player == nil or not KnifeTable() then
		return
	end

	local s_Rows = SQL:Query("SELECT knife FROM knife WHERE player = ?", PlayerKey(p_Player)) or {}
	local s_Key = s_Rows[1] ~= nil and tostring(s_Rows[1].knife) or nil

	if s_Key ~= nil and KNIVES[s_Key] then
		NetEvents:SendTo("TacticalSlots:Choice", p_Player, s_Key)
	end
end)

-- ---- each player's grenade: the same, for the grenade slot (TacticalSlots:GrenadeSet / GrenadeAsk -> GrenadeChoice, table grenade)
local GRENADES = { m67 = true, smoke = true, flash = true }
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
		return
	end

	SQL:Query("INSERT OR REPLACE INTO grenade (player, grenade) VALUES (?, ?)", PlayerKey(p_Player), s_Key)
end)

NetEvents:Subscribe("TacticalSlots:GrenadeAsk", function(p_Player)
	if p_Player == nil or not GrenadeTable() then
		return
	end

	local s_Rows = SQL:Query("SELECT grenade FROM grenade WHERE player = ?", PlayerKey(p_Player)) or {}
	local s_Key = s_Rows[1] ~= nil and tostring(s_Rows[1].grenade) or nil

	if s_Key ~= nil and GRENADES[s_Key] then
		NetEvents:SendTo("TacticalSlots:GrenadeChoice", p_Player, s_Key)
	end
end)
