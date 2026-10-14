-- KnifeTab (client) -- the deploy screen's knife slot talks to Lua over the ActionScript channel (the document carries its receiver:
-- every frame is the event AS2:Frame): "KNF<key>" = the player picked a knife in the slot's picker; "KNM<text>|<before>" = the screen
-- read the mailbox (the knife the slot shows when it comes up, and what the slot held before it); "KNB<line>|<corners>|<moved>" = the
-- row was laid out (the bar's slots moved left, its grey line and corner brackets stretched over our slots); "GRF<key>" = the player
-- picked a grenade in the grenade slot's picker (the M67 or the M18 smoke); "GRM<text>|<before>" = the screen read the grenade
-- mailbox. The choices themselves are the shared code's (TACTICALSLOTS_KNIFE_CHOOSE in ext/Shared/__init__.lua, TACTICALSLOTS_GRENADE_CHOOSE in
-- ext/Shared/SmokeGrenade.lua): each puts its pick first in every kit's list (what the game sends when the player deploys), keeps the
-- mailbox the screen reads, and has the server keep it for the next session.

Events:Subscribe("AS2:Frame", function(p_Text)
	local s_Text = tostring(p_Text)
	local s_Tag = s_Text:sub(1, 3)

	if s_Tag == "KNF" then
		if _G.TACTICALSLOTS_KNIFE_CHOOSE ~= nil then
			_G.TACTICALSLOTS_KNIFE_CHOOSE(s_Text:sub(4), "picked in the deploy screen", true)
		end
	elseif s_Tag == "KNM" then
		if _G.TACTICALSLOTS_LOG ~= nil then
			local s_Read, s_Before = s_Text:sub(4):match("^([^|]*)|?(.*)$")
			_G.TACTICALSLOTS_LOG("the deploy screen read the mailbox: '" .. tostring(s_Read) .. "' (the slot held '" .. tostring(s_Before) .. "' before)")
		end
	elseif s_Tag == "KNB" then
		if _G.TACTICALSLOTS_LOG ~= nil then
			_G.TACTICALSLOTS_LOG("the deploy screen laid out the row: grey line x+width " .. s_Text:sub(4))
		end
	elseif s_Tag == "GRF" then
		if _G.TACTICALSLOTS_GRENADE_CHOOSE ~= nil then
			_G.TACTICALSLOTS_GRENADE_CHOOSE(s_Text:sub(4), "picked in the deploy screen", true)
		elseif _G.TACTICALSLOTS_LOG ~= nil then
			_G.TACTICALSLOTS_LOG("grenade '" .. s_Text:sub(4) .. "' picked in the deploy screen, but the smoke code is not loaded")
		end
	elseif s_Tag == "GRM" then
		if _G.TACTICALSLOTS_LOG ~= nil then
			local s_Read, s_Before = s_Text:sub(4):match("^([^|]*)|?(.*)$")
			_G.TACTICALSLOTS_LOG("the deploy screen read the grenade mailbox: '" .. tostring(s_Read) .. "' (the slot held '" .. tostring(s_Before) .. "' before)")
		end
	end
end)
