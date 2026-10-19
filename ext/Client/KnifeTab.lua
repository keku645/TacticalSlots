-- KnifeTab (client) -- the deploy screen's slots talk to Lua over the ActionScript channel (the document carries its receiver: every
-- frame is the event AS2:Frame): "KNF<key>" = the player picked a knife in the knife slot's picker; "GRF<key>" = the player picked a
-- grenade in the grenade slot's picker (the M67, the M18 smoke or the M84 flashbang). The choices themselves are the shared code's
-- (TACTICALSLOTS_KNIFE_CHOOSE in ext/Shared/__init__.lua, TACTICALSLOTS_GRENADE_CHOOSE in ext/Shared/SmokeGrenade.lua): each puts its
-- pick first in every kit's list (what the game sends when the player deploys), keeps the mailbox the screen reads, and has the
-- server keep it for the next session. Any other frame is the screens' own and is ignored here.

Events:Subscribe("AS2:Frame", function(p_Text)
	local s_Text = tostring(p_Text)
	local s_Tag = s_Text:sub(1, 3)

	if s_Tag == "KNF" then
		if _G.TACTICALSLOTS_KNIFE_CHOOSE ~= nil then
			_G.TACTICALSLOTS_KNIFE_CHOOSE(s_Text:sub(4), "picked in the deploy screen", true)
		end
	elseif s_Tag == "GRF" then
		if _G.TACTICALSLOTS_GRENADE_CHOOSE ~= nil then
			_G.TACTICALSLOTS_GRENADE_CHOOSE(s_Text:sub(4), "picked in the deploy screen", true)
		end
	end
end)
