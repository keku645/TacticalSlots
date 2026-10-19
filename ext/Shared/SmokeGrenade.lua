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
-- Note: the weapon blueprint's NAME stays the M67's (renamed, the grenade is invisible, and after a kit change every weapon is).
--
-- THE GRENADE SLOT. Every kit's weapon table has a grenade part listing [M67]. The client sends the FIRST grenade of that list when the
-- player deploys (as with the knife), so the choice is the order of that list on the player's own client; the smoke and the M84
-- flashbang (ext/Shared/Flashbang.lua makes it) are added to the list in both realms.
--
-- THE CHOICE. The deploy screen's grenade slot (KnifeTab.lua hears "GRF<key>") calls TACTICALSLOTS_GRENADE_CHOOSE: the choice is put first
-- in every kit's list, written into the screen's mailbox (GrenadeSelSet) and kept by the server (mod.db, table grenade).

-- ---- knobs ------------------------------------------------------------------------------------------------------------------
local SMOKE_ENABLED = true            -- false: no smoke at all (the grenade slot offers the M67 and the M84 flashbang)
local DEFAULT_GRENADE = "m67"         -- what the game sends when the player has not chosen: "m67" | "smoke" | "flash"

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
-- (it detonates): the canister as a plain mesh, laid on the ground where the grenade went off (if that was in the air, after it
-- falls the rest of the way), the smoke out of its top, level, along it. false: the detonation plays the smoke itself (fixed
-- direction, no canister).
local SMOKE_BY_LUA = true

local CANISTER_CLEARANCE = 0.005      -- gap left between the lying canister and the ground (m): never in it
local CANISTER_MAX_SLOPE = 0.7        -- steeper than this between its two ends (a step, a ledge): it lies level on the highest contact
local CANISTER_STEP = 0.02            -- a lift above this (m) means a step under it: it lies level on its footprint's highest point
local CANISTER_FALLS = true           -- went off in the AIR: the canister falls on from there (its speed, the grenade's gravity) to the
                                      -- ground, down a cliff too, pouring smoke all the way; false = laid at once on the ground under it
local FALL_GROUND_GAP = 0.15          -- ground closer than this under the grenade when it goes off (m): it is on the ground already
local FALL_BOUNCE = 0.3               -- the falling canister bounces off the ground keeping this much of the speed it hit it with (the
                                      -- thrown grenade's COLLISION_SPEED_MULTIPLIER is 0.3); 0 = no bounce. A bounce under MIN_BOUNCE_SPEED
                                      -- is no bounce: it slides on
local FALL_BOUNCE_MAX = 3.0           -- the fastest it leaves the ground after a bounce (m/s): 3 = at most ~0.45 m high, however far it fell
local FALL_BOUNCE_GRIP = 0.75         -- of its speed ALONG the ground, what each bounce keeps (1 = none lost, 0 = it stops across)
local SLIDE_FRICTION = 0.45           -- how hard the ground brakes the canister sliding on it (its friction): from 3 m/s it slides ~1 m,
                                      -- from 1 m/s ~11 cm; 0 = it never stops on level ground
local SLIDE_HOLD = 0.6                -- the steepest ground it can stop on (rise over run: 0.6 = 31 degrees); steeper, it slides on down
local SLIDE_STOP = 0.05               -- slower than this (m/s), on ground it can stop on, it stops

-- INDOORS. The game's smoke particles go through walls (they have no collision of any kind), and the plume's drift carries them metres
-- away. So under a ceiling the canister pours the same jet, short (JET_INDOORS) and without the drift, turned to the room's most open
-- side if a wall is right in front of it; and from its mouth the smoke FLOWS into the room in streams: the room is measured with rays
-- (a grid of points ROOM_CELL apart, each reached from the one before by a clear ray: a wall stops it, an open door lets it through),
-- and each stream runs from the mouth along those clear rays to a place in the room, fast as it leaves the jet, slower and slower,
-- laying its smoke where it passes, which stays there. Nearer places first: the room fills from the canister out. Outdoors the streams
-- are never used (the volume draws a cloud there, VOLUME.OUTDOORS, or the canister pours the plume as it is).
local ROOM_SMOKE = true               -- false: indoors as outdoors (the plume, through the walls)
local ROOM_CEILING = 6.0              -- a ceiling within this over the canister (m): it is indoors
local ROOM_TALL = 12.0                -- and one farther, within this: a tall room (an atrium, a stairwell's shaft over a step the canister
                                      -- lies on, a hall), indoors as well (in the open with a roof that high over it: VOLUME.OPEN_SHARE)
local ROOM_MIN_HEIGHT = 1.9           -- lower than this over the floor is furniture or a vehicle (a table, a bench), not a ceiling: the
                                      -- ceiling is looked for over it
local ROOM_CELL = 1.2                 -- the room is measured every this (m)
local ROOM_REACH = 8.0                -- the farthest the smoke flows from the canister (m, along the floor)
local ROOM_MAX_POINTS = 40            -- the most points of the room measured (the nearest)
local ROOM_RAYS = 40                  -- rays a frame spends measuring a room (10 a point: the measuring takes ~20 frames)
-- A particle is drawn as a flat card the size of its smoke, facing the camera at the depth of its centre: a wall hides the card only
-- where the wall is in front of it, so a card wider than its distance to a wall shows past the wall's edge, over whatever lies beyond
-- (seen from aside, the next corridor). Indoors the smoke is therefore SMALL cards (JET_INDOORS_SIZE, ROOM_SMOKE_SIZE: about a metre,
-- growing little) let out ROOM_CLEARANCE or more off the walls.
local JET_INDOORS = 0.5               -- the jet's push indoors, against outdoors (1)
local JET_INDOORS_SIZE = 0.3          -- its smoke's size indoors, against outdoors (the signal's are 4 m and grow)
local JET_INDOORS_DRAG = 2.5          -- how hard the air brakes the jet indoors, from the moment it leaves (the signal's builds up only
                                      -- halfway through its smoke's life, so outdoors it carries metres): it pours out and stops within ~1 m
local JET_ROOM = 1.5                  -- clear space the jet needs in front of it (m); less (a wall), the canister turns to the most open side
local ROOM_STREAMS = 12               -- how many streams the smoke flows out in
local ROOM_STREAM_EVERY = 0.6         -- a stream more every this (s): 12 x 0.6 = the jet's own pouring time
local ROOM_STREAM_SPEED = 1.2         -- how fast a stream leaves the mouth (m/s)
local ROOM_STREAM_SLOW = 0.25         -- the slowest it gets (m/s)
local ROOM_STREAM_EASE = 2.0          -- how soon it slows (s): its speed halves every ~1.4 s
local ROOM_STREAM_SECONDS = 9.0       -- how long a stream lets smoke out: on its way, then where it ends (the room thickening there)
local ROOM_SMOKE_RATE = 12.0          -- smoke a stream lets out per second (small cards: many of them)
local ROOM_SMOKE_COUNT = 100          -- at most this much of a stream's smoke at once
local ROOM_PATH_CLEAR = 0.4           -- a stream takes a straight way only with this much room on both its sides (m): off corners and door
                                      -- frames, where its smoke would show past the edge
local ROOM_SMOKE_LIFE = 10.0          -- how long its smoke hangs in the air
local ROOM_SMOKE_SIZE = 1.2           -- its smoke's size when grown (m): let out at 60 % of it, it grows to it over its life
local ROOM_CLEARANCE = 0.6            -- every point of the room the smoke goes to is kept this far off the walls and the ceiling (m),
                                      -- or in the middle where there is less room (a door, a narrow passage)
local ROOM_SMOKE_DENSITY = 0.8        -- how thick a stream's smoke gets. It is let out CLEAR and thickens over the first third of its life
                                      -- (so a stream's head, where its newest smoke is, shows no smoke of its own: what shows is the smoke it
                                      -- leaves, growing from the canister out), then thins out to nothing
local ROOM_SMOKE_SPEED = 0.0          -- how fast its smoke leaves the stream (m/s): 0 = it stays where it is let out (anything more, and
                                      -- smoke let out by a wall drifts through it)
-- How the smoke indoors LOOKS, set as the game's own thick smoke volumes are: lit with the smoke's relief, each card turned its own way
-- and turning slowly, of varied sizes, soft-edged all its life. The signal's cards are lit flat, all turned the same way, still, of
-- nearly one size, and their edges sharpen as they age: a room full of them reads as cotton balls.
local ROOM_SMOKE_NORMALMAP = "FX/Textures/Smoke/Anim_TurbulentThickSmoke01_8x32_NRM" -- the smoke texture's own relief, so the
                                      -- level's light shapes it (the streams and the jet indoors); nil = lit flat, as the signal's. A
                                      -- level packs the particle textures it uses into an atlas and draws none outside it: the relief
                                      -- is used only where this level's atlas has it
local ROOM_SMOKE_TURN = 1.0           -- how far each card is turned at random when let out (0 = all turned the same way)
local ROOM_SMOKE_SPIN = 0.02          -- how fast each card turns, either way, at random up to this (0 = still; the game's own smoke
                                      -- grenade turns its smoke this fast)
local ROOM_SMOKE_SIZE_MIN = 0.5       -- the smallest card, against ROOM_SMOKE_SIZE (the largest): each one in between at random
local ROOM_SMOKE_SOFT = true          -- soft edges all its life; false = the signal's, edges sharpening as the smoke ages

-- IN the smoke: a fog over the whole view (a visual environment, the game's own way of filling the screen with dust after a blast or
-- of whiting it out after a flashbang), weighed every frame by how deep the camera is in a room the smoke has filled: nothing outside
-- it (a wall in between is outside), up to ROOM_FOG in thick smoke.
local ROOM_FOG = 0.85                 -- the fog at its thickest (0 = no fog)
local ROOM_FOG_END = 5.0              -- in thick smoke nothing farther than this is seen (m)
local ROOM_FOG_COLOR = Vec3(0.25, 0.25, 0.25) -- its colour (the light it scatters: the game's own fogs run from 0.001 at night up)
local ROOM_FOG_RISE = 5.0             -- how long the smoke takes to thicken where it gets to (s)
local ROOM_FOG_PRIORITY = 20000       -- over the level's own visual environments (a smoke grenade's own whiteout is weighed at this)
local ROOM_FOG_MIRROR = true          -- its switches (a fog colour of its own, the sky's gradient, height fog, colour grading and its
                                      -- texture) copied from the level's own look: a blend weighs numbers, not switches -- while the fog
                                      -- weighs anything ITS switches stand, so with them unlike the level's, the level's own unused fog
                                      -- colour (sand, sky blue, black...) showed at its distances and its colour grading went off until the
                                      -- fog had faded out whole; false: not copied
-- and the WHITEOUT: in thick smoke the picture flattens to grey (a colour correction with no contrast: the way a smoke grenade's own
-- whiteout is made, weighed the same way). Neutral is 1 for the three, 0 for the hue.
local ROOM_WHITEOUT_BRIGHTNESS = 0.5
local ROOM_WHITEOUT_CONTRAST = 0.0
local ROOM_WHITEOUT_SATURATION = 0.75
local ROOM_WHITEOUT_HUE = 10.0

-- THE VOLUME. Indoors the smoke is drawn as what it is, a volume, instead of the streams' particles: the room is measured floor to
-- ceiling, each measured point becomes a box reaching out to the walls round it where the room goes no farther (and no farther: no
-- smoke shows past a wall), the boxes side by side joined into big ones, and a shader of our own marches each view once -- by the box
-- the camera is in, else the first one the view goes into -- through the smoke's density: the measured points smoothed, grown from the
-- canister along its way there (round through a door, not through the wall), billowing, eroded at its open edges, lit by the light of
-- the place from where it is brightest, darker where the smoke is thick between it and that light; it stops where the view meets
-- anything solid. One room at a time holds the volume's grid; a second canister near enough pours into it (VOLUME.MERGE), else a
-- second smoke, while the first lasts, is a volume of its own in the main space of its room (VOLUME.OTHERS). The volume alone draws
-- its room's smoke (VOLUME.JET), and the fog and whiteout above still come
-- over the view inside it. In the open it is a cloud measured the same way under a ceiling of its own, open at the top (VOLUME.OUTDOORS);
-- and a room's smoke that gets to a window or a door to the open pours out of it (VOLUME.EXITS).
local VOLUME = {
	ON = true,                        -- false: the streams' particles
	GROW = 1.4,                       -- how fast the smoke spreads from the canister (m/s)
	RADIUS = 6.0,                     -- how far from the canister it spreads at most (m): a room smaller than this fills whole, a big hall
	                                  -- gets a round cloud this big (its grid holds 12 x 14 m: more shows cut off by it)
	DENSITY = 5.0,                    -- how thick it gets: a metre of it hides 1 - e^-5 = 99 % of what is behind (its billows' creases a
	                                  -- little less); thicker is also cheaper to draw from inside it (the view stops sooner)
	ALBEDO = 0.75,                    -- how light it is: the share of the light it scatters back
	NOISE = 0.9,                      -- its billows' frequency (1/m): smaller, bigger billows
	EROSION = 0.7,                    -- how deep the billows eat into it: 0 = an even fill; at the open edges they break it into wisps
	EDGE = 0.4,                       -- how far in from its open edges it gets full, in shares of a cell (0.5 = at the farthest point's
	                                  -- own place); it is nothing right at the edge whatever this is
	SHADOW = 0.6,                     -- how dark it gets where thick smoke stands between it and the light (0 = evenly lit)
	CLEAR = 5.0,                      -- how long it takes to clear at the end (s)
	POINTS = 360,                     -- the most points of the room measured for it (the nearest; the streams measure ROOM_MAX_POINTS)
	RAYS = 120,                       -- rays a frame spent measuring it (12 a point: ~360 points in ~36 frames)
	EVERY_FRAME = false,              -- true: its numbers written every frame (each write makes the game blend all its visual environments
	                                  -- again); false: only when they change enough to show (growing, clearing), ~100 writes a smoke
	ONE_WRITER = true,                -- true: of its boxes (cut to the walls, side by side) ONE draws each view -- the one the camera is
	                                  -- in, else the first one the view goes into -- marching it all the way through, the others drawing
	                                  -- nothing there; false: each box draws its own stretch (translucent boxes over one another: the game
	                                  -- draws them in an order of its own, the far one sometimes over the near one -- they flicker and
	                                  -- show as blocks -- and every box costs the whole shader where it covers the view)
	THIN_WALLS = true,                -- true: a box's side that only part of something stands in (a counter's edge, a hood) is left
	                                  -- whole only if what its other corners met is solid as far as the box reaches; a wall with room
	                                  -- behind it there (beside a door, round a hatch or a window) is cut at, so no box reaches past it;
	                                  -- false: one corner getting past leaves the side whole
	CAMERA_RAY = true,                -- true: the camera is in the smoke (the fog over the view; the box it is in draws every view) only
	                                  -- with nothing between it and that box's point; false: being in the box is enough
	ONE_PASS = true,                  -- true: ONE box round all the points' boxes (its sides on the room's walls round it) draws every
	                                  -- view through it, one march from where the view enters it: no seams where one box would give
	                                  -- way to another, no view drawn twice; false: the points' boxes, one of them drawing each view
	REAL_FLOOR = true,                -- true: a canister lying on a table, a counter, a shelf (up to 2.5 m over the floor round it) fills
	                                  -- the room from its floor (under the table too); false: from where the canister lies
	JET = false,                      -- true: the canister's own jet of particles pours indoors as well while the volume draws the room;
	                                  -- false: the volume alone (the hiss stays; a room the volume does not draw still gets the jet)
	UNDER_ROOF = true,                -- true: the smoke's room is where a roof is over it: out through a door to the open sky it stops at
	                                  -- the door; false: on outside as well, under the room's own layers (a flat-topped slab out there)
	FOG_DRAWN = true,                 -- true: the fog over the view only where the smoke drawn is; false: in any of the room's boxes once
	                                  -- its time to get there has passed (round a wall as well, where the smoke drawn never gets)
	TALL = 0.5,                       -- how much the growing smoke's height counts against its spread along the floor: 1 = it grows as a
	                                  -- ball from the canister (in a corridor its front is a dome, short of the ceiling and the walls);
	                                  -- 0.5 = it reaches the ceiling of a 3 m room once it has spread 1.5 m, and fills a corridor's height
	                                  -- as far along as its floor (more than 0, 1 at most)
	MAIN_FILL = true,                 -- true: the room's main space (the block of its points round the canister, its sides on the walls)
	                                  -- drawn full up to its walls, its floor and its ceiling, and the grid's first and last layers read
	                                  -- on to the floor and the ceiling; false: the grid alone, thinning out towards them
	CUT_THROUGH = true,               -- true: a point's box ends at a wall or a floor across it within its place even where the room
	                                  -- has a point on the other side (got to round it: a hall under a floor that opens onto the stairs);
	                                  -- false: it reaches its whole place there, through that wall or floor
	OTHERS = true,                    -- true: a smoke going off while another one's room is drawn as the volume (and not poured into it,
	                                  -- VOLUME.MERGE) is a volume of its own:
	                                  -- the smoke grows from its canister in the main box of its room (the room's points round it, its
	                                  -- sides on the walls), thinning out towards a side where the room goes on (it does not flow out
	                                  -- through a door); false: that smoke flows in particle streams, with the canister's jet
	OUTDOORS = true,                  -- true: a canister lying in the open (no ceiling over it) is drawn as a volume as well: a cloud over
	                                  -- the ground round it, OUT_HEIGHT high, measured as a room is (its sides cut at the walls round it,
	                                  -- into a building only through its door), open at the top: thinning out upwards; false: the game's
	                                  -- smoke particles there
	OPEN_SHARE = 0.5,                 -- a canister under a ceiling in a place mostly open to the sky (a porch, an eave, a bridge, a tree:
	                                  -- this share or more of the places round it have the sky over them) is in the open as well: its
	                                  -- cloud drawn there, under that ceiling where it stands; less, a room (its smoke pouring out of the
	                                  -- room's openings, VOLUME.EXITS); 1: by the ceiling over the canister alone
	OUT_HEIGHT = 5.0,                 -- how high the cloud stands over the ground round the canister in the open (m)
	OUT_TOP = 2.0,                    -- over how much of its height, from its top down, smoke open to the sky thins out to nothing (m; 6.3
	                                  -- at most): the cloud in the open, and the smoke let out of a room through a window or a door
	OUT_ROUND = true,                 -- true: the cloud in the open is a heap, its top OUT_HEIGHT up over the canister, coming down to the
	                                  -- ground at the edge of its spread; false: as high all over (a drum, its sides straight up)
	EXITS = 4,                        -- a room's openings to the open (a window, a door: where VOLUME.UNDER_ROOF stops the room) its smoke
	                                  -- pours out of once it gets there, a cell out at the opening's height, thinning out over and past
	                                  -- that (drawn with the room's own smoke, by its one box): the nearest this many (0: none, the
	                                  -- smoke stops at them)
	JOIN = true,                      -- true: a smoke going off inside another one's smoke drawn as the volume (in one of its points'
	                                  -- boxes) joins it -- that smoke lasts on from then, as long as a new one -- instead of being a
	                                  -- volume of its own over the same place (two boxes of ours over one another flicker); false: a
	                                  -- volume of its own there too (VOLUME.OTHERS)
	MERGE = true,                     -- true: a canister going off while another smoke's room fills over time (VOLUME.SIM), near enough
	                                  -- for that one's grid to take in both (its 12 x 12 places across moved over), pours into that room
	                                  -- as a second canister: the room measured on from where it lies, its smoke filling it as the
	                                  -- first's does -- one smoke the shape of the rooms round both, lasting as long as a new one; false
	                                  -- (or too far off): a volume of its own in the main space of its room (VOLUME.OTHERS)
	HOLD = true,                      -- true: smoke that had settled in the room when another canister pours in (or an M320 round's smoke
	                                  -- joins it) stays where it is -- the new smoke spreads round it and over it --, so what is drawn of
	                                  -- the first changes only where the new smoke gets to; false: it all spreads out again together
	                                  -- (the first's smoke drawn sinking and moving over to the new places)
	RECEDE = 1.4,                     -- a canister too far off for that grid to take in both smokes as they are drawn: the first gives way
	                                  -- -- its box's sides past the grid that takes in both drawing in at this pace (m/s), its smoke there
	                                  -- thinning out as they pass, at the front's pace (SIM_FRONT_CANISTER) --, and the canister pours into
	                                  -- its room once they are in; 0: a volume of its own there
	FLOW = true,                     -- true: the smoke goes where a fixed amount of it flows (AMOUNT): from the canister, always into the
	                                  -- cheapest place next to those it fills already -- the farther the dearer (SHAPE, ROUNDNESS), up dearer
	                                  -- and down cheaper (GRAVITY), a wall stops it -- so it settles to the floor, fills a room from the floor
	                                  -- up, and pours out of a door or a window and down outside once that is cheaper than climbing: one rule
	                                  -- for a room, a stairwell, a porch, the open and the openings between them (VOLUME.RADIUS, UNDER_ROOF,
	                                  -- OPEN_SHARE and EXITS then play no part); false: the room measured place by place round the canister
	                                  -- out to VOLUME.RADIUS
	AMOUNT = 250,                     -- how much smoke there is (m3): a closed room smaller than this fills whole and the rest stays in it; a
	                                  -- room with a door or a window lets the rest out; in the open, a heap about 6 m across each way
	SHAPE_X = 0.7,                    -- how far it would rather spread along x, up, and along z (their ratios: wider than it is tall, and a
	SHAPE_Y = 1.0,                    -- little longer along x than along z)
	SHAPE_Z = 0.6,
	ROUNDNESS = 2,                    -- the shape the cost of the distance grows in: 2 = an ellipsoid; more, squarer
	GRAVITY = 18,                     -- how much dearer each place is the higher it is (per 7 m up): 18 = going down is cheaper than staying
	                                  -- level (it drops out of a window); 0 = up and down alike; under 0 it rises
	FLOW_BY_WAY = true,               -- true: how far a place is counts along the smoke's way there (straight while nothing is in the way,
	                                  -- round through a door): through a door into the next room it spreads on from the door; false: straight
	                                  -- from the canister, through the walls (the next room then fills first along the wall it shares with
	                                  -- the canister's room, as if the smoke had come through it)
	FLOW_OVER = true,                 -- true: a place whose middle is in something low (a bed, a sofa, a table) is filled from higher up in
	                                  -- it, the smoke round that thing down to the floor; false: such a place is left out (the smoke ends
	                                  -- over it in a flat face, a cell's height up)
	FLOW_FLOORS = true,               -- true: a place standing on a floor inside its own place (a stairwell's upper part over a hall's
	                                  -- ceiling) over air the smoke has not got to is not filled -- its smoke would be drawn down through
	                                  -- that floor into the hall under it --, the smoke going elsewhere; false: filled (it shows under it)
	SMOOTH = true,                    -- true: its growing and its clearing written as they go (a centimetre at a time: every frame or so);
	                                  -- false: a tenth of a metre at a time (it grows in small jumps)
	HOLES = true,                     -- true: a bullet through the smoke drawn leaves a hole along its way (half a metre round it, its edge
	                                  -- wavering: the shader's HOLE_RADIUS), shutting over HOLE_SECONDS; two at once -- a burst along the
	                                  -- same way keeps one open --; false: none
	HOLE_SECONDS = 2.0,               -- how long a bullet's hole takes to shut (it eases shut)
	WAKE = true,                      -- true: a soldier moving through the room's smoke (VOLUME.SIM) leaves a wake in it: a way through it
	                                  -- from about a metre behind them to where they are, from the knees to the head (the shader's
	                                  -- WAKE_RADIUS), opening towards them and closing up behind them as they go; one at a time, the
	                                  -- nearest the camera (another player before the camera's own); the bullets' holes one at a time
	                                  -- then; false: none (two bullets' holes at once)
	NEAR_QUALITY = 2.0,               -- with the camera in the smoke drawn or within this of it (m) -- where it fills the view and costs the
	                                  -- most -- the shader marches it the cheaper way (the shader's NEAR_SEEN, NEAR_FINE, NEAR_DEEP: about a
	                                  -- third less work there, a slightly finer grain deep in the smoke); farther off, at its best; 0:
	                                  -- always at its best
	M320 = true,                      -- true: the M320's smoke round (and the rifles' underslung ones) is drawn as this smoke too -- the
	                                  -- room or the open round where it hits measured and filled, through doors, with the bullets'
	                                  -- holes -- as the round's own smoke: no canister, its own sound (its detonation plays the sound
	                                  -- alone), spreading at once, thinning out from the start; false: the game's own particles
	M320_GROW = 15.0,                 -- how fast its smoke spreads (m/s): the round's 51 puffs come out at once over 5 m round it
	M320_AMOUNT = 400,                -- how much smoke the round lets out (m3): its puffs fill a ball of 5 m and more round it
	M320_SECONDS = 20.0,              -- how long its smoke lasts (the round's puffs' life); it thins out from the start as theirs do:
	                                  -- two thirds left at a quarter of it, a third at half, a seventh at three quarters (Vol.Strength)
	M320_EARLY = true,                -- true: its smoke drawn from the moment it hits, growing as the place round it is measured (drawn
	                                  -- again each time twice as much of it is measured, and once all of it is); false: drawn once the
	                                  -- place is measured whole (half a second or more after it hits)
	M320_RAYS = 240,                  -- rays a frame spent measuring the place round where it hit (a canister's: RAYS)
	M320_BELOW = 4.0,                 -- a floor up to this far (m) straight under where it hits (high on a wall, a building's front) is its
	                                  -- smoke's floor: the smoke round where it hit and down to that floor; with no floor so near, it
	                                  -- hangs round where it hit, from M320_HANG under it (its bottom thinning out where the volume's
	                                  -- grid draws it)
	M320_HANG = 2.5,
	M320_OVER = 2.0,                  -- in the open, its cloud's top at least this far (m) over where it hit (else OUT_HEIGHT over its floor)
	M320_SHAPE_X = 1.0,               -- the shape its smoke would rather spread in, and how much it settles (as SHAPE_X/Y/Z and GRAVITY
	M320_SHAPE_Y = 1.0,               -- are a canister's): a ball round where it hit, sinking a little, as the round's puffs do
	M320_SHAPE_Z = 1.0,
	M320_GRAVITY = 3,
	MORTAR = true,                    -- true: the mortar's smoke round (the deployed M224's second round) is drawn as this smoke too, as
	                                  -- the M320's is -- its explosion plays the very effect the M320 round's does (the same puffs, the
	                                  -- same sound), so it is put down the same way and with the same numbers (where it hits measured
	                                  -- and filled, M320_EARLY, M320_RAYS, M320_BELOW, M320_HANG, M320_OVER, M320_SHAPE_*, M320_GRAVITY);
	                                  -- false: the game's own particles
	MORTAR_GROW = 15.0,               -- how fast its smoke spreads (m/s): its puffs are the M320 round's (M320_GROW)
	MORTAR_AMOUNT = 400,              -- how much smoke it lets out (m3): the M320 round's (M320_AMOUNT)
	MORTAR_SECONDS = 20.0,            -- how long its smoke lasts, thinning out from the start as the M320 round's does (M320_SECONDS)
	ROUND_FOG = 1.0,                  -- in a round's smoke (the M320's, the mortar's), the view greys over as much as this many metres of
	                                  -- its smoke as drawn hide (DENSITY times how thick it still is): grey as long as the smoke drawn
	                                  -- hides all round you -- 0.84 at half its time, 0.53 at three quarters --, clearing as it does;
	                                  -- 0: as thick as it still is (0.36 at half its time: the screen cleared well before the smoke did)
	SIM = true,                       -- true: the smoke FILLS its place over time: poured out of the canister (or let out round where an
	                                  -- M320 round hit, sinking), going from place to place as its levels even out -- down first, out of a
	                                  -- door or over a counter as far as it stands over the sill, never through a wall --, its grid holding
	                                  -- how full each place is (empty, half or full); drawn from its first places measured on, as they are
	                                  -- measured. false: grown from the canister (the grid holds where it has got to)
	SIM_ROOM = 1.6,                   -- the place measured round it: this much more than its smoke fills (room for it to spread)
	SIM_SPREAD = 3.0,                 -- how fast its levels even out between places side by side (1/s)
	SIM_SLOPE = 0.35,                 -- the steepest its top stands, in layers from one place to the next (a heap in the open)
	SIM_POUR = 0.5,                   -- of a canister's smoke, the share poured out over its first SIM_BURST s; the rest over SMOKE_SECONDS
	SIM_BURST = 1.5,
	SIM_SINK = 0.4,                   -- how fast an M320 round's smoke, out in a ball round where it hit, sinks (m/s); and smoke with no
	                                  -- floor under it (past a roof's edge), falling away
	SIM_FRONT = 3.0,                  -- the smoke is drawn within a front grown from where an M320 round hit as it spreads, at most this
	                                  -- fast (m/s): what fills a place comes in smoothly as the front gets there, not at once
	SIM_FRONT_CANISTER = 1.4,         -- and a canister's, from its mouth: as fast as a volume of its own grows (VOLUME.GROW) -- the smoke
	                                  -- seen pouring out of it as smoothly, a ball growing round it; 3.0: as fast as the round's
	SIM_AHEAD = true,                 -- true: once a canister's place is measured, its smoke is simulated on ahead of its time to where it
	                                  -- ends up (all poured out and settled, a second or two in), and that is what is drawn from then on, its
	                                  -- front showing it spread at an even pace -- nothing drawn creeps on a column at a time; an M320 round's
	                                  -- ball, once measured, is drawn as it is then, sinking evenly (VOLUME.SIM_SINK) until it rests on the
	                                  -- floor; false: the smoke drawn as it fills, step by step
	SIM_PACE = false,                  -- how a canister's smoke comes out (either way it comes in through doors, never walls: SIM_WAY):
	                                  -- true: at the simulated smoke's own pace -- nothing for the second or two its smoke takes to be
	                                  -- simulated on to where it ends up (SIM_AHEAD: shown sooner, it would change a column at a time),
	                                  -- then out as fast as it spread, slowing down as it spreads on, waiting while it fills a room before a
	                                  -- door, easing in and out, at most SIM_PACE_MOST m/s (an M320 round's: SIM_FRONT, at once);
	                                  -- false: at once, at an even pace (SIM_FRONT_CANISTER m/s; an M320 round's SIM_FRONT)
	SIM_PACE_MOST = 4.0,
	SIM_WAY = true,                   -- true: the smoke is shown no sooner than it gets there along its way (round through a door, never
	                                  -- through a wall): a column whose way from the canister is longer than straight -- behind a wall --
	                                  -- waits, empty, until the front grown along the way gets there, and fades in whole then; false:
	                                  -- shown as the front grows straight out from the canister (with SIM_AHEAD: through a wall)
	SIDE = false,                      -- true: seen from outside the smoke, its smoothing between the grid's columns never draws it through
	                                  -- a wall, a floor or a ceiling: a column counts only where no surface the screen shows stands
	                                  -- between it and the point drawn (no thin wavy smoke on the near side of a wall with smoke behind
	                                  -- it, none on a ceiling from the floor over it); false: within 1 m of such a surface
	                                  -- nothing, unless the smoke's churn pulled the view in
	SIM_COLUMNS = true,               -- true: the grid holds, for each column of places, where its smoke starts and how high it stands (a
	                                  -- third of a layer at a time): the smoke spreads and rises in thin steps; false: how full each place
	                                  -- is (empty, half, full: a layer-high place at a time)
	MEASURE_MS = 2.0,                 -- the most of a frame (ms) measuring the smokes' places takes, all of them together: a frame that
	                                  -- reaches it measures on in the next one (0: no cap, RAYS rays a frame each)
	CLEANUP = 10,                    -- every this many frames, a small clean-up of the memory the mod's Lua no longer uses (the client's;
	                                  -- generational: the young leftovers only, about half a millisecond), so no big one ever stops a frame
	                                  -- for 10-15 ms; 0: Lua's own clean-up as it sees fit
	ORDER = true,                    -- true: with several smokes drawn at once (their boxes one behind another along the view), they are
	                                  -- drawn far to near, each over the ones behind it, however many there are (Vol.Order); false: in the
	                                  -- game's own order for boxes of one mesh, near to far -- a box farther off drawn over the smoke in
	                                  -- front of it (its side shows as a square, and flickers as the camera moves)
}
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
	flash = "Weapons/M84/U_M84_Flashbang",   -- ext/Shared/Flashbang.lua's
}

local TEAMS = { "US", "RU" }
local CLASSES = { "Assault", "Engineer", "Support", "Recon" }
local KIT_SUFFIXES = { "", "_GM", "_XP4", "_GM_XP4", "_XP4_SCV" }

local m_Built = false
local m_Chosen = DEFAULT_GRENADE
local m_GrenadeParts = {}   -- this level's kits' grenade lists: { part, kit, kept }
local m_ByKey = {}          -- this level's grenade unlocks by key
local m_FxGuid = 0
local m_SmokeRelief = nil   -- ROOM_SMOKE_NORMALMAP when this level's particle atlas has it, else nil (lit flat)

-- the canister and the smoke put down by the script (client)
local m_SmokeEffect = nil   -- our grey smoke (EffectBlueprint)
local m_SmokeFallEffect = nil -- the same, its smoke left in the world: played by a canister that falls (a trail behind it)
local m_SmokeRoomEffect = nil -- one stream of the smoke flowing into a room (indoors)
local m_SmokeIndoorEffect = nil -- the jet indoors (pushed less, no drift)
local m_HissEffect = nil    -- the signal's hiss on its own (EffectBlueprint), stopped when the smoke stops pouring
local m_CanisterData = nil  -- a StaticModelEntityData drawing the canister mesh

-- the volume (client): its box's data (our mesh, our shader) when our bundle brought them, the visual environment carrying its numbers,
-- and the room drawn as a volume now ({ down, boxes, values }); its functions below
local Vol = { data = nil, env = nil, now = nil, others = {} }
Vol.MESH = "TacticalSlots/Smoke/Volume/tssmokevolume_box1_Mesh"   -- the box: a unit cube of ours, in the volume superbundle
-- and the same box as meshes of their own, one a box drawn at once (Vol.Slot): the game draws the boxes of one composite mesh together,
-- in an order of its own (not by where they are), and each mesh on its own draw, near to far by where it takes the box to be -- which
-- the box's steer sets (Vol.Order)
Vol.BOXES = "123456789ABC"
local m_Grenades = {}       -- smoke grenades in the world: uniqueId -> { entity, transform, velocity }
local m_Gone = {}           -- grenades that went away this frame: their last transform and velocity (handled in the PreSim pass: raycasts)
local m_Down = {}           -- canisters put down (falling, then on the ground): { entity, effect, hiss, pose, start, age, ... }
local m_Gravity = -9.81     -- the grenade's own gravity (read from its data when the grenade is made)
local m_Logged = 0          -- smokes logged this level (the first few)
local SMOKES_LOGGED = 24    -- how many of a level's smokes are logged (a few lines each)

local function NextFxGuid()
	m_FxGuid = m_FxGuid + 1

	if m_FxGuid > 255 then
		error("out of fx guids (two hex digits)")
	end

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
local function GreyEmitter(p_Document, p_Role, p_Variant)
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

				if p_Role == "room" then
					l_Spread.minX, l_Spread.maxX = -1.0, 1.0
					l_Spread.minY, l_Spread.maxY = -0.3, 0.6
					l_Spread.minZ, l_Spread.maxZ = -1.0, 1.0
					s_Level[#s_Level + 1] = "every way"
				else
					l_Spread.minY = JET_LIFT_MIN
					l_Spread.maxY = JET_LIFT_MAX
					s_Level[#s_Level + 1] = "jet level"
				end

				l_Copy.pre = l_Spread
			end
		elseif p_Role == "room" and l_Copy.typeInfo.name == "SpawnSpeedData" then
			l_Copy.speed = ROOM_SMOKE_SPEED
		elseif (p_Role == "room" or p_Variant == "indoor") and l_Copy.typeInfo.name == "LocalForceData" then
			-- the signal's drift (a wind along the emitter) would carry the smoke out through the wall: none indoors
			l_Copy.localForce = Vec3(0.0, 0.0, 0.0)
			s_Level[#s_Level + 1] = "no drift"
		elseif p_Variant == "indoor" and l_Copy.typeInfo.name == "SpawnSpeedData" then
			-- the jet indoors: the same, pushed less, so it pours out and slows into the room near the canister
			l_Copy.speed = l_Copy.speed * JET_INDOORS
			s_Level[#s_Level + 1] = string.format("push x%g", JET_INDOORS)
		elseif p_Variant == "indoor" and l_Copy.typeInfo.name == "AirResistanceData" then
			-- and braked hard from the moment it leaves (the signal's drag curve is 0 at birth, full only halfway through the life)
			l_Copy.dragFactor = JET_INDOORS_DRAG

			if l_Copy.pre ~= nil and l_Copy.pre.typeInfo.name == "PolynomialData" then
				local l_Curve = Copy(l_Copy.pre, NextFxGuid())
				l_Curve.coefficients = Vec4(0.0, 0.0, 0.0, 1.0)
				l_Curve.scaleValue = 1.0
				l_Copy.pre = l_Curve
			end

			s_Level[#s_Level + 1] = string.format("drag %g from the start", JET_INDOORS_DRAG)
		elseif p_Role == "room" and l_Copy.typeInfo.name == "TurbulanceData" then
			-- still air: a stream's smoke stays where it is let out
			l_Copy.intensity = 0.0
		elseif p_Role == "room" and l_Copy.typeInfo.name == "UpdateTransparencyData" then
			-- let out clear, thickest a third into its life, then thinning to nothing: f(t) = 6.75 t (1 - t)^2 (peak 1 at t = 1/3), the
			-- curve's terms (t^3, t^2, t, 1), times ROOM_SMOKE_DENSITY
			if l_Copy.pre ~= nil and l_Copy.pre.typeInfo.name == "PolynomialData" then
				local l_Curve = Copy(l_Copy.pre, NextFxGuid())
				l_Curve.coefficients = Vec4(6.75, -13.5, 6.75, 0.0)
				l_Curve.scaleValue = ROOM_SMOKE_DENSITY
				l_Curve.minClamp = 0.0
				l_Curve.maxClamp = 1.0
				l_Copy.pre = l_Curve
				s_Level[#s_Level + 1] = "let out clear, thickening"
			end
		elseif p_Role == "room" and l_Copy.typeInfo.name == "SpawnRateData" then
			l_Copy.spawnRate = ROOM_SMOKE_RATE
		elseif p_Role == "room" and l_Copy.typeInfo.name == "UpdateAgeData" then
			l_Copy.lifetime = ROOM_SMOKE_LIFE
			s_Level[#s_Level + 1] = string.format("hangs %g s", ROOM_SMOKE_LIFE)
		elseif p_Role == "room" and l_Copy.typeInfo.name == "SpawnSizeData" then
			l_Copy.size = ROOM_SMOKE_SIZE

			if l_Copy.pre ~= nil and l_Copy.pre.typeInfo.name == "RandomEvaluatorData" then
				local l_Random = Copy(l_Copy.pre, NextFxGuid())
				l_Random.min = ROOM_SMOKE_SIZE_MIN
				l_Random.max = 1.0
				l_Copy.pre = l_Random
				s_Level[#s_Level + 1] = string.format("sizes x%g-1", ROOM_SMOKE_SIZE_MIN)
			end
		elseif p_Role == "room" and l_Copy.typeInfo.name == "SpawnRotationData" then
			-- each card turned its own way (the signal's: all the same way)
			l_Copy.rotation = ROOM_SMOKE_TURN

			if l_Copy.pre ~= nil and l_Copy.pre.typeInfo.name == "RandomEvaluatorData" then
				local l_Random = Copy(l_Copy.pre, NextFxGuid())
				l_Random.min = -1.0
				l_Random.max = 1.0
				l_Copy.pre = l_Random
				s_Level[#s_Level + 1] = string.format("turned at random x%g", ROOM_SMOKE_TURN)
			end
		elseif p_Role == "room" and l_Copy.typeInfo.name == "SpawnRotationSpeedData" then
			-- and turning slowly, either way (the signal's: still)
			l_Copy.rotationSpeed = ROOM_SMOKE_SPIN

			if l_Copy.pre ~= nil and l_Copy.pre.typeInfo.name == "RandomEvaluatorData" then
				local l_Random = Copy(l_Copy.pre, NextFxGuid())
				l_Random.min = -1.0
				l_Random.max = 1.0
				l_Copy.pre = l_Random
				s_Level[#s_Level + 1] = string.format("turning up to %g", ROOM_SMOKE_SPIN)
			end
		elseif p_Role == "room" and l_Copy.typeInfo.name == "UpdateRotationData" then
			-- at that speed all its life (the signal's curve stops the turning a third into it)
			local l_Curve = PolynomialData(NextFxGuid())
			l_Curve.emitterParameter = 0
			l_Curve.coefficients = Vec4(0.0, 0.0, 0.0, 1.0)
			l_Curve.scaleValue = 1.0
			l_Curve.minClamp = 0.0
			l_Curve.maxClamp = 1.0
			l_Copy.pre = l_Curve
		elseif p_Role == "room" and ROOM_SMOKE_SOFT and l_Copy.typeInfo.name == "UpdateAlphaLevelScaleData" then
			-- soft-edged all its life, as the game's thick smoke volumes are: their alpha level stays low (0.05 -> 0.24) where the
			-- signal's climbs to 1 and its edges harden as the smoke ages
			l_Copy.exponent = 3.856

			if l_Copy.pre ~= nil and l_Copy.pre.typeInfo.name == "PolynomialData" then
				local l_Curve = Copy(l_Copy.pre, NextFxGuid())
				l_Curve.coefficients = Vec4(0.0, 0.0, 0.264706, -0.0285293)
				l_Curve.scaleValue = 1.0
				l_Curve.minClamp = 0.05
				l_Curve.maxClamp = 0.99
				l_Copy.pre = l_Curve
				s_Level[#s_Level + 1] = "soft"
			end
		elseif (p_Role == "room" or (p_Variant == "indoor" and p_Role == "plume")) and m_SmokeRelief ~= nil
			and l_Copy.typeInfo.name == "UpdateTextureCoordsData" then
			-- the smoke texture with its own relief (normal map), so the level's light shapes it; the rest as it was
			local l_Old = l_Copy.textureInfo1
			local l_Info = EmitterTextureInfo()
			l_Info.textureName = l_Old.textureName
			l_Info.normalmapName = m_SmokeRelief
			l_Info.animationFrameCount = l_Old.animationFrameCount
			l_Info.animationFrameColumnCount = l_Old.animationFrameColumnCount
			l_Info.enableAnimation = l_Old.enableAnimation
			l_Copy.textureInfo1 = l_Info
			s_Level[#s_Level + 1] = "lit with relief"
		elseif p_Variant == "indoor" and l_Copy.typeInfo.name == "SpawnSizeData" then
			l_Copy.size = l_Copy.size * JET_INDOORS_SIZE
			s_Level[#s_Level + 1] = string.format("size x%g", JET_INDOORS_SIZE)
		elseif (p_Role == "room" or p_Variant == "indoor") and l_Copy.typeInfo.name == "UpdateSizeData" then
			-- grows little (the signal's curve makes its cards several times bigger): from 60 % to its full size over its life,
			-- f(t) = 0.6 + 0.4 t (terms t^3, t^2, t, 1)
			local l_Curve = PolynomialData(NextFxGuid())
			l_Curve.emitterParameter = 0
			l_Curve.coefficients = Vec4(0.0, 0.0, 0.4, 0.6)
			l_Curve.scaleValue = 1.0
			l_Curve.minClamp = 0.0
			l_Curve.maxClamp = 1.0
			l_Copy.pre = l_Curve
			s_Level[#s_Level + 1] = "grows to x1"
		elseif p_Role == "room" and l_Copy.typeInfo.name == "SpawnAnimationData" then
			-- the stream runs in real time (below), the plume at half: its smoke's texture animates as fast as the plume's
			l_Copy.animationSpeed = l_Copy.animationSpeed * s_Template.timeScale
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
	elseif p_Role == "room" then
		-- real time, so its seconds, rate and speed are the knobs' own
		s_Template.timeScale = 1.0
		s_Template.maxCount = ROOM_SMOKE_COUNT
	end

	-- once, not forever: an emitter's Lifetime runs in its own time (TimeScale), so the seconds are scaled into it
	local s_Seconds = (p_Role == "plume" and SMOKE_SECONDS) or (p_Role == "puff" and PUFF_SECONDS) or
		(p_Role == "room" and ROOM_STREAM_SECONDS) or CANISTER_SECONDS
	s_Template.repeatParticleSpawning = false
	s_Template.lifetime = s_Seconds * s_Template.timeScale
	s_Level[#s_Level + 1] = string.format("once, %g s", s_Seconds)

	-- the signal's particles live in the emitter's own space (LocalSpace): moved, the effect carries its whole plume along. For a
	-- canister that falls, and for a stream, they stay where they were let out (as the game's own smoke trails, all LocalSpace off)
	if p_Variant == "falling" or p_Role == "room" then
		s_Template.localSpace = false
		s_Level[#s_Level + 1] = "left in the world"
	end

	return s_Document, s_Colours, s_Steps, table.concat(s_Level, ", ")
end

-- p_Variant: "ground" = the smoke a canister lying outdoors pours (and the hiss, an effect of its own); "falling" = the same, its smoke
-- left in the world as a trail (a canister that went off in the air and falls; the hiss is the ground copy's, moved along); "indoor" =
-- the same jet indoors, pushed less and without the drift; "room" = one STREAM of the smoke flowing into a room: the plume alone, its
-- smoke let out slowly every way round the stream and left where it passes, no sound
local SMOKE_NAMES = { ground = "FX/TacticalSlots/FX_M18_Smoke_Grey", falling = "FX/TacticalSlots/FX_M18_Smoke_Grey_Falling",
	indoor = "FX/TacticalSlots/FX_M18_Smoke_Grey_Indoor", room = "FX/TacticalSlots/FX_M18_Smoke_Grey_Stream" }

local function GreySmoke(p_Variant)
	local s_Original = ResourceManager:FindInstanceByGuid(SIGNAL_PART, SIGNAL_BP_INST)

	if s_Original == nil then
		return nil, "the signal smoke is not loaded"
	end

	local s_Blueprint = Copy(s_Original, NextFxGuid())
	local s_Effect = Copy(s_Blueprint.object, NextFxGuid())
	s_Blueprint.object = s_Effect
	s_Blueprint.name = SMOKE_NAMES[p_Variant]

	local s_Said = {}

	-- the signal allows 10 of itself at a time (MaxInstanceCount); a room flows in ROOM_STREAMS streams, and several rooms may be at once
	if p_Variant == "room" then
		s_Effect.maxInstanceCount = ROOM_STREAMS * 6
		s_Said[#s_Said + 1] = string.format("up to %d at a time", ROOM_STREAMS * 6)
	end
	local s_Drop = {}
	local s_Hiss = nil

	for i = 1, #s_Effect.components do
		local l_Component = s_Effect.components[i]

		if l_Component ~= nil and l_Component.typeInfo.name == "SoundEffectEntityData" then
			-- the signal's hiss loops until stopped, so it rides an effect of its own that the script stops when the smoke stops
			-- pouring (stopping the smoke's effect would cut the smoke); or the game's smoke grenade sound; or none
			local l_Pop = ResourceManager:SearchForDataContainer(SMOKE_POP_SOUND)

			if p_Variant == "room" then
				s_Drop[#s_Drop + 1] = i
				s_Said[#s_Said + 1] = "sound: none (the canister's own)"
			elseif SMOKE_SOUND == "hiss" and SMOKE_BY_LUA then
				if p_Variant == "ground" then
					s_Hiss = Copy(s_Original, NextFxGuid())
					local l_HissEffect = Copy(s_Hiss.object, NextFxGuid())
					l_HissEffect.components:clear()
					l_HissEffect.components:add(l_Component)
					s_Hiss.object = l_HissEffect
					s_Hiss.name = "FX/TacticalSlots/FX_M18_Smoke_Hiss"
				end

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
			elseif p_Variant == "room" and l_Name:find("initsmoke") then
				s_Drop[#s_Drop + 1] = i
				s_Said[#s_Said + 1] = "no first puff"
			elseif p_Variant == "room" then
				-- a stream: its smoke let out every way, slowly, round where the stream is, and left there
				l_Emitter.transform = LinearTransform(Vec3(1.0, 0.0, 0.0), Vec3(0.0, 1.0, 0.0), Vec3(0.0, 0.0, 1.0), Vec3(0.0, 0.0, 0.0))
				local l_Document, l_Colours, l_Steps, l_Level = GreyEmitter(l_Emitter.emitter, "room", p_Variant)
				l_Emitter.emitter = l_Document
				s_Said[#s_Said + 1] = string.format("stream grey (%d colour; %s; %d processor(s) copied)", l_Colours, l_Level, l_Steps)
			else
				-- the mouth: the effect's origin is the canister's top when the script plays it; the canister's centre (top at
				-- -0.052 along -Z) when the detonation does
				l_Emitter.transform = LinearTransform(Vec3(-1.0, 0.0, 0.0), Vec3(0.0, 1.0, 0.0), Vec3(0.0, 0.0, -1.0),
					Vec3(0.0, JET_HEIGHT, (SMOKE_BY_LUA and 0.0 or -0.052) - JET_AHEAD))
				local l_Role = l_Name:find("initsmoke") and "puff" or "plume"
				local l_Document, l_Colours, l_Steps, l_Level = GreyEmitter(l_Emitter.emitter, l_Role, p_Variant)
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

-- ---- the M320's smoke round (VOLUME.M320) ---------------------------------------------------------------------------------------
-- Every M320 smoke round (the launcher's and the rifles' underslung ones: one firing, 40mm_SMK_Firing) is the projectile
-- Weapons/Gadgets/M320/40mmSmoke; its explosion plays FX_40mm_Smoke, 51 puffs and the smoke grenade's sound. Its explosion here plays a
-- copy of that effect with the sound alone; the smoke is the volume, put down where the round hit (Vol.M320Off).
Vol.M320_PART = Guid("A3E3C07B-2E9C-42D2-B540-7E70594293EC")
Vol.M320_DATA = Guid("30AD5145-04AD-4C97-8D1B-B4FE0E1AD6F5")       -- its BulletEntityData
Vol.M320_BP = Guid("7460744A-FB96-4D6F-9CA9-72BF50883581")         -- its ProjectileBlueprint
Vol.M320_EXPLOSION = Guid("48BBE181-231E-4E7F-A959-10ECA1BCAF57")
Vol.FX40_PART = Guid("6A2C27D9-D455-458D-A542-C212C6F8F69C")         -- FX/Vehicles/Misc/FX_40mm_Smoke
Vol.FX40_BP = Guid("00C3D2F9-1346-47B8-956D-10CC23AD8B4D")
-- The mortar's smoke round (VOLUME.MORTAR): the deployed M224's second weapon fires Weapons/Gadgets/M224/M224_Projectile_Smoke, a
-- missile whose explosion plays that same FX_40mm_Smoke; it gets the same copy with the sound alone (Vol.RoundDetonations)
Vol.MORTAR_PART = Guid("7C592ADA-6915-4969-BFF2-A875027A9962")
Vol.MORTAR_DATA = Guid("A420BDD8-F89F-49E3-B6DB-E8327253A589")     -- its MissileEntityData
Vol.MORTAR_BP = Guid("DC240C29-1B26-4142-9095-EE385E6A1374")       -- its ProjectileBlueprint
Vol.MORTAR_EXPLOSION = Guid("A7E5A920-FA8C-4511-AA6C-CAF00C967C3E")

-- the rounds whose smoke is drawn as the volume (VOLUME.M320, VOLUME.MORTAR): their explosions play a copy of FX_40mm_Smoke with its
-- sound alone; Vol.m320 / Vol.mortar say which took it. What happened, said
function Vol.RoundDetonations()
	Vol.m320, Vol.mortar = false, false
	local s_Original = ResourceManager:FindInstanceByGuid(Vol.FX40_PART, Vol.FX40_BP)
	local s_M320 = VOLUME.M320 and ResourceManager:FindInstanceByGuid(Vol.M320_PART, Vol.M320_EXPLOSION) or nil
	local s_Mortar = VOLUME.MORTAR and ResourceManager:FindInstanceByGuid(Vol.MORTAR_PART, Vol.MORTAR_EXPLOSION) or nil

	if s_Original == nil then
		return "their effect is not loaded (their own particles, as ever)"
	end

	local s_Said = {}
	local s_Blueprint = nil

	for _, l_Round in ipairs({ { explosion = s_M320, on = VOLUME.M320, name = "the M320's", flag = "m320" },
			{ explosion = s_Mortar, on = VOLUME.MORTAR, name = "the mortar's", flag = "mortar" } }) do
		if l_Round.on and l_Round.explosion == nil then
			s_Said[#s_Said + 1] = l_Round.name .. " round is not loaded (its own particles)"
		elseif l_Round.on then
			if s_Blueprint == nil then
				local s_Done, s_Made = Vol.SoundAlone(s_Original)

				if not s_Done then
					return s_Made .. " (their own particles, as ever)"
				end

				s_Blueprint = s_Made
			end

			-- (the rounds' own particles, where there is no place for the volume: the game's effect itself -- not what an explosion
			-- plays, our copy once built before)
			Vol.m320Particles = EffectBlueprint(s_Original)
			local l_Explosion = Writable(l_Round.explosion)
			l_Explosion.detonationEffect = s_Blueprint
			Vol[l_Round.flag] = true
			s_Said[#s_Said + 1] = l_Round.name .. " round's detonation plays its sound alone, its smoke drawn as the volume"
		end
	end

	return table.concat(s_Said, "; ")
end

-- a copy of FX_40mm_Smoke (p_Original) with its sound alone, put in its partition: true and it, or false and why not
function Vol.SoundAlone(p_Original)
	local s_Blueprint = Copy(p_Original, NextFxGuid())
	local s_Effect = Copy(s_Blueprint.object, NextFxGuid())
	local s_Sound = nil

	for i = 1, #s_Effect.components do
		local l_Component = s_Effect.components[i]

		if l_Component ~= nil and l_Component.typeInfo.name == "SoundEffectEntityData" then
			s_Sound = l_Component
		end
	end

	if s_Sound == nil then
		return false, "their effect has no sound"
	end

	s_Effect.components:clear()
	s_Effect.components:add(s_Sound)
	s_Blueprint.object = s_Effect
	s_Blueprint.name = "FX/TacticalSlots/FX_M320_Smoke_Sound"

	local s_Partition = ResourceManager:FindDatabasePartition(Vol.FX40_PART)

	if s_Partition ~= nil then
		s_Partition:AddInstance(s_Blueprint)
	end

	return true, s_Blueprint
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

	-- the canister that falls on after going off in the air falls like the thrown grenade
	if s_Projectile.gravity ~= nil and s_Projectile.gravity ~= 0.0 then
		m_Gravity = -math.abs(s_Projectile.gravity)
	end

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

	return s_Unlock, string.format("%d weapon state(s) with the M18 meshes; explosion %s; gravity %.2f", #s_Weapon.weaponStates,
		s_MaterialSaid, m_Gravity)
end

-- ---- the order of the grenade lists ---------------------------------------------------------------------------------------------
local function OrderFor(p_Kept)
	local s_Order = {}

	for _, l_Key in ipairs(p_Kept) do
		if l_Key ~= "smoke" and l_Key ~= "flash" and m_ByKey[l_Key] ~= nil then
			s_Order[#s_Order + 1] = l_Key
		end
	end

	-- ours, after the kit's own, in this order
	for _, l_Key in ipairs({ "smoke", "flash" }) do
		if m_ByKey[l_Key] ~= nil then
			s_Order[#s_Order + 1] = l_Key
		end
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

-- A level packs the particle textures its effects use into one atlas (its emitter system) and draws no particle texture outside it:
-- is this one in this level's?
local function InLevelAtlas(p_Name)
	local s_Level = tostring(SharedUtils:GetLevelName() or "")
	local s_Found = ResourceManager:SearchForDataContainer(s_Level .. "/EmitterSystem_Win32")

	if s_Found == nil then
		return false, "the level's particle atlas was not found"
	end

	local s_Infos = EmitterSystemAsset(s_Found).textureInfos
	local s_Wanted = string.lower(p_Name)

	for i = 1, #s_Infos do
		if string.lower(tostring(s_Infos[i].textureName)) == s_Wanted then
			return true, string.format("in the level's particle atlas (%d textures)", #s_Infos)
		end
	end

	return false, string.format("not in the level's particle atlas (%d textures)", #s_Infos)
end

local function Build()
	m_FxGuid = 0
	local s_Unlock, s_WeaponSaid, s_Effect, s_EffectSaid, s_Hiss = nil, nil, nil, nil, nil

	if SMOKE_ENABLED and _G.TACTICALSLOTS_SMOKE_MOUNTED then
		s_Effect, s_EffectSaid, s_Hiss = GreySmoke("ground")

		if s_Effect == nil then
			LOG("⛔ " .. tostring(s_EffectSaid) .. ": our bundle did not come in -- no smoke this level")
		else
			s_Unlock, s_WeaponSaid = MakeWeapon(s_Effect)

			if s_Unlock == nil then
				LOG("⛔ the smoke grenade could not be made (" .. tostring(s_WeaponSaid) .. ") -- no smoke this level")
			end
		end
	end

	-- the M84 flashbang (ext/Shared/Flashbang.lua), when its superbundle came in; made after the smoke, in both realms alike
	local s_Flash, s_FlashSaid = nil, "not loaded"

	if _G.TACTICALSLOTS_FLASH_MOUNTED and _G.TACTICALSLOTS_FLASH_MAKE ~= nil then
		local s_Ok, s_Made, s_Said = pcall(_G.TACTICALSLOTS_FLASH_MAKE)
		s_Flash = s_Ok and s_Made or nil
		s_FlashSaid = s_Ok and tostring(s_Said) or ("FAILED " .. tostring(s_Made))

		if s_Flash == nil then
			LOG("⛔ the M84 flashbang could not be made (" .. s_FlashSaid .. ") -- no flashbang this level")
		end
	end

	if s_Unlock == nil and s_Flash == nil then
		return
	end

	m_ByKey = { smoke = s_Unlock, flash = s_Flash }
	m_GrenadeParts = {}

	if IS_CLIENT and SMOKE_BY_LUA and s_Unlock ~= nil then
		m_SmokeEffect = s_Effect
		m_HissEffect = s_Hiss

		-- the falling copy is extra: if it cannot be made, a falling canister plays the smoke above (carried along)
		if CANISTER_FALLS then
			local s_Ok, s_Fall, s_FallSaid = pcall(GreySmoke, "falling")
			m_SmokeFallEffect = s_Ok and s_Fall or nil
			s_EffectSaid = s_EffectSaid .. string.format("; falling copy: %s (%d fx copies)",
				s_Ok and tostring(s_FallSaid) or ("FAILED " .. tostring(s_Fall)), m_FxGuid)
		end

		-- the room's stream and the indoor jet, extra as well: without both, a canister indoors pours the plume above (through the walls)
		if ROOM_SMOKE then
			m_SmokeRelief = nil

			if ROOM_SMOKE_NORMALMAP ~= nil then
				local s_AtlasOk, s_Has, s_Where = pcall(InLevelAtlas, ROOM_SMOKE_NORMALMAP)
				m_SmokeRelief = (s_AtlasOk and s_Has) and ROOM_SMOKE_NORMALMAP or nil
				s_EffectSaid = s_EffectSaid .. string.format("; smoke relief: %s", s_AtlasOk and
					(tostring(s_Where) .. (s_Has and "" or ", lit flat")) or ("FAILED " .. tostring(s_Has) .. ", lit flat"))
			end

			local s_Ok, s_Room, s_RoomSaid = pcall(GreySmoke, "room")
			local s_JetOk, s_Jet, s_JetSaid = pcall(GreySmoke, "indoor")
			m_SmokeRoomEffect = (s_Ok and s_JetOk) and s_Room or nil
			m_SmokeIndoorEffect = (s_Ok and s_JetOk) and s_Jet or nil
			s_EffectSaid = s_EffectSaid .. string.format("; room stream: %s; indoor jet: %s (%d fx copies)",
				s_Ok and tostring(s_RoomSaid) or ("FAILED " .. tostring(s_Room)),
				s_JetOk and tostring(s_JetSaid) or ("FAILED " .. tostring(s_Jet)), m_FxGuid)
		end

		m_CanisterData = StaticModelEntityData()
		m_CanisterData.mesh = RigidMeshAsset(ResourceManager:FindInstanceByGuid(CANISTER_PART, CANISTER_INST))
		m_CanisterData.visible = true

		-- the volume's box, if its superbundle came in (else a room fills with the streams' particles)
		Vol.data = nil
		Vol.datas = {}

		if ROOM_SMOKE and VOLUME.ON then
			for l_K = 1, #Vol.BOXES do
				local l_Box = ResourceManager:SearchForDataContainer((Vol.MESH:gsub("box1", "box" .. Vol.BOXES:sub(l_K, l_K))))

				if l_Box ~= nil then
					local l_Data = StaticModelEntityData()
					l_Data.mesh = MeshAsset(l_Box)
					l_Data.visible = true
					Vol.datas[#Vol.datas + 1] = l_Data
				end
			end

			Vol.data = Vol.datas[1]
			s_EffectSaid = s_EffectSaid .. (Vol.data ~= nil and string.format("; the volume's box is in (%d mesh(es) of it)", #Vol.datas)
				or "; no volume box (its bundle did not come in)")

			-- the M320's smoke round and the mortar's drawn as the volume too (VOLUME.M320, VOLUME.MORTAR)
			Vol.m320, Vol.mortar, Vol.mortarSeen = false, false, nil

			if IS_CLIENT and (VOLUME.M320 or VOLUME.MORTAR) and Vol.data ~= nil then
				local s_Ok, s_Said = pcall(Vol.RoundDetonations)

				if not s_Ok then
					Vol.m320, Vol.mortar = false, false
				end

				s_EffectSaid = s_EffectSaid .. "; the smoke rounds: " .. (s_Ok and tostring(s_Said) or ("FAILED " .. tostring(s_Said)))
			end
		end
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
	LOG(string.format("smoke grenade %s; M84 flashbang %s; grenade list set in %d kit(s)%s; %s",
		s_Unlock ~= nil and string.format("made (%s; effect: %s)", tostring(s_WeaponSaid), tostring(s_EffectSaid)) or "not made",
		s_Flash ~= nil and ("made (" .. s_FlashSaid .. ")") or "not made", #m_GrenadeParts,
		IS_CLIENT and (", '" .. m_Chosen .. "' first") or " (server: ours added at the end)", table.concat(s_Said, " | ")))
end

Events:Subscribe("Level:RegisterEntityResources", function()
	if m_Built or not (_G.TACTICALSLOTS_SMOKE_MOUNTED or _G.TACTICALSLOTS_FLASH_MOUNTED) then
		return
	end

	local s_Ok, s_Err = pcall(Build)

	if not s_Ok then
		LOG("⛔ build: " .. tostring(s_Err))
	end
end)

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
-- canister is put down as a plain mesh where it lay and the smoke is played out of its top, level, along it. If it went off in the
-- AIR, the canister is not left there: it falls on to the ground (CANISTER_FALLS), the smoke and the hiss following it.
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

-- The smoke's frame: level, its -Z along the canister (the jets leave along -Z, out of its top). On the ground its origin is the ground
-- under the top (the jets' mouth sits JET_HEIGHT over it); in the air, the mouth is the top itself.
local function SmokeFrame(p_Pose, p_OnGround)
	local s_Axis = Horizontal(p_Pose.up) or Vec3(0.0, 0.0, 1.0)
	local s_Top = p_Pose.trans + p_Pose.up * CANISTER_TOP
	local s_Y = s_Top.y - JET_HEIGHT

	if p_OnGround then
		s_Y = (s_Top - p_Pose.forward * (CANISTER_REST_HEIGHT + CANISTER_CLEARANCE)).y
	end

	local s_F = Vec3(-s_Axis.x, 0.0, -s_Axis.z)
	return LinearTransform(Vec3(s_F.z, 0.0, -s_F.x), Vec3(0.0, 1.0, 0.0), s_F, Vec3(s_Top.x, s_Y, s_Top.z)), s_Axis
end

-- One frame of a canister that went off in the air: it moves on under gravity along the ground's ray; a wall or a ceiling in the way
-- stops it across (it drops down along it); the ground bounces it back up (FALL_BOUNCE of its speed into the ground, as the thrown
-- grenade bounces, no faster than FALL_BOUNCE_MAX; FALL_BOUNCE_GRIP of its speed along the ground) until a bounce would be slower than
-- MIN_BOUNCE_SPEED: then it SLIDES on with the speed it has along the ground (p_Fall.sliding, SlideStep).
local FALL_WALL = 0.3                 -- a hit whose normal points up less than this is a wall, not ground
local FALL_BOUNCE_LIFT = 0.01         -- a bounce starts this far off the ground (m), not on it

local function FallStep(p_Fall, p_Delta)
	local s_V = p_Fall.velocity + Vec3(0.0, m_Gravity * p_Delta, 0.0)
	local s_To = p_Fall.position + s_V * p_Delta
	local s_Hit = RaycastManager:Raycast(p_Fall.position, s_To, RAY_FLAGS)

	if s_Hit == nil then
		p_Fall.position = s_To
		p_Fall.velocity = s_V
		return false
	end

	if s_Hit.normal.y < FALL_WALL then
		-- off the wall by the canister's longest reach from its origin, so that lying at the wall's foot it is not in it
		p_Fall.position = s_Hit.position + s_Hit.normal * (CANISTER_BOTTOM + CANISTER_CLEARANCE)
		p_Fall.velocity = Vec3(0.0, math.min(s_V.y, 0.0), 0.0)
		return false
	end

	-- off the ground: its speed into the ground turned back out (FALL_BOUNCE of it, capped at FALL_BOUNCE_MAX), its speed along the
	-- ground kept (FALL_BOUNCE_GRIP of it)
	local s_N = s_Hit.normal
	local s_Into = -Dot(s_V, s_N)
	local s_Along = (s_V + s_N * s_Into) * FALL_BOUNCE_GRIP
	local s_Up = math.min(s_Into * FALL_BOUNCE, FALL_BOUNCE_MAX)

	if s_Up >= MIN_BOUNCE_SPEED then
		p_Fall.position = s_Hit.position + s_N * FALL_BOUNCE_LIFT
		p_Fall.velocity = s_Along + s_N * s_Up
		p_Fall.bounces = (p_Fall.bounces or 0) + 1
		return false
	end

	-- too slow to bounce: it stays on the ground and slides on along it
	p_Fall.position = s_Hit.position
	p_Fall.velocity = s_Along
	p_Fall.normal = s_N
	p_Fall.sliding = true
	return false
end

-- One frame of a canister sliding on the ground (p_Fall.normal): the ground's friction brakes it (SLIDE_FRICTION), the slope pulls it
-- down; it follows the ground under it, bounces back off a wall, and leaves the ground over an edge (it falls again: p_Fall.sliding
-- false). Slower than SLIDE_STOP on ground it can stop on (SLIDE_HOLD): it stops, true.
local SLIDE_FEEL = 0.05               -- how far over the ground its walls check runs (m)
local SLIDE_DROP = 0.1                -- ground further down than this from one frame to the next is an edge: it falls off (m)

local function SlideStep(p_Fall, p_Delta)
	local s_N = p_Fall.normal
	local s_V = p_Fall.velocity
	local s_Speed = math.sqrt(Dot(s_V, s_V))
	local s_Press = -m_Gravity * s_N.y                     -- gravity into the ground
	local s_Pull = Vec3(0.0, m_Gravity, 0.0) + s_N * s_Press -- gravity along it (down the slope)
	local s_PullSize = math.sqrt(Dot(s_Pull, s_Pull))

	if s_Speed < SLIDE_STOP and s_PullSize <= SLIDE_HOLD * s_Press then
		p_Fall.velocity = Vec3(0.0, 0.0, 0.0)
		return true
	end

	local s_NewV = s_V + s_Pull * p_Delta

	if s_Speed > 1e-4 then
		-- friction: against the way it slides, never turning it back
		local s_Brake = math.min(SLIDE_FRICTION * s_Press * p_Delta, s_Speed)
		s_NewV = s_NewV - s_V * (s_Brake / s_Speed)
	end

	local s_From = p_Fall.position
	local s_To = s_From + s_NewV * p_Delta

	-- something in the way, just over the ground: a wall bounces it back (as the ground does), kept clear of it; ground rising
	-- ahead (a ramp, a low kerb) it goes on over
	local s_Ahead = RaycastManager:Raycast(s_From + s_N * SLIDE_FEEL, s_To + s_N * SLIDE_FEEL, RAY_FLAGS)

	if s_Ahead ~= nil and s_Ahead.normal.y < FALL_WALL then
		local s_W = s_Ahead.normal
		p_Fall.velocity = (s_NewV - s_W * (2.0 * Dot(s_NewV, s_W))) * FALL_BOUNCE
		p_Fall.position = s_Ahead.position - s_N * SLIDE_FEEL + s_W * (CANISTER_BOTTOM + CANISTER_CLEARANCE)
		return false
	elseif s_Ahead ~= nil then
		s_To = s_Ahead.position
	end

	-- the ground under where it moves to (looked for from over the height its check above ran at, never from inside it): it follows
	-- it, up a slope or down one; none close below = an edge, it falls
	local s_Rise = math.max(SLIDE_FEEL + 0.02, 0.02 + math.sqrt(s_NewV.x * s_NewV.x + s_NewV.z * s_NewV.z) * p_Delta)
	local s_Ground = RaycastManager:Raycast(Vec3(s_To.x, s_To.y + s_Rise, s_To.z), Vec3(s_To.x, s_To.y - SLIDE_DROP, s_To.z), RAY_FLAGS)

	if s_Ground == nil or s_Ground.normal.y < FALL_WALL then
		p_Fall.position = s_To
		p_Fall.velocity = s_NewV
		p_Fall.sliding = false
		return false
	end

	-- on to the new ground, its speed turned along it (as fast: where the ground bends, it follows the bend, it is not braked by it)
	local s_G = s_Ground.normal
	local s_Laid = s_NewV - s_G * Dot(s_NewV, s_G)
	local s_LaidSize = math.sqrt(Dot(s_Laid, s_Laid))

	if s_LaidSize > 1e-4 then
		s_Laid = s_Laid * (math.sqrt(Dot(s_NewV, s_NewV)) / s_LaidSize)
	end

	p_Fall.slid = (p_Fall.slid or 0.0) + math.sqrt(Dot(s_To - s_From, s_To - s_From))
	p_Fall.position = s_Ground.position
	p_Fall.normal = s_G
	p_Fall.velocity = s_Laid
	return false
end

-- Indoors: a ceiling within ROOM_CEILING over p_At (a surface facing down, ROOM_MIN_HEIGHT or more over the floor; a wall is no
-- ceiling). Something lower (the top of a table the canister lies under) is looked past: the ray goes on from just over it. Its
-- height, or nil.
local function CeilingOver(p_At)
	local s_From = p_At + Vec3(0.0, 0.1, 0.0)
	local s_To = p_At + Vec3(0.0, math.max(ROOM_CEILING, ROOM_TALL or 0.0), 0.0)

	for _ = 1, 4 do
		local s_Hit = RaycastManager:Raycast(s_From, s_To, RAY_FLAGS)

		if s_Hit == nil then
			return nil
		end

		if s_Hit.position.y - p_At.y >= ROOM_MIN_HEIGHT then
			return s_Hit.normal.y < -0.3 and s_Hit.position.y or nil
		end

		-- lower: furniture, whichever face the ray met
		s_From = s_Hit.position + Vec3(0.0, 0.05, 0.0)
	end

	return nil
end

-- The room round a canister lying indoors: points ROOM_CELL apart in layers over its floor (the first ROOM_CELL / 2 up) up to under the
-- ceiling, each reached from a neighbour by a clear ray (a wall stops it, an open door lets it through), as far as ROOM_REACH along
-- the floor and no more than ROOM_MAX_POINTS of them. Each point keeps the one it was reached from: a way back to the canister along
-- clear rays. Measured over frames (RoomMeasure, ROOM_RAYS a frame), nearest first.
local ROOM_STEPS = { { 1, 0, 0 }, { -1, 0, 0 }, { 0, 0, 1 }, { 0, 0, -1 }, { 0, 1, 0 }, { 0, -1, 0 } }

-- along one axis, the shift that keeps a point ROOM_CLEARANCE off the walls on its two sides (p_Plus, p_Minus: how far they are, up to
-- ROOM_CLEARANCE): off the near one, or to the middle if both are near; and how wide the place is there (huge if not both near)
local function Shift(p_Plus, p_Minus)
	if p_Plus < ROOM_CLEARANCE and p_Minus < ROOM_CLEARANCE then
		return (p_Plus - p_Minus) * 0.5, p_Plus + p_Minus
	elseif p_Plus < ROOM_CLEARANCE then
		return p_Plus - ROOM_CLEARANCE, 1e9
	elseif p_Minus < ROOM_CLEARANCE then
		return ROOM_CLEARANCE - p_Minus, 1e9
	end

	return 0.0, 1e9
end

-- a point of the room moved ROOM_CLEARANCE off the walls round it: along the floor's two axes (4 rays), then, from there, along its
-- two diagonals (4 rays more: a corner, a crate's edge, is off every axis)
local DIAGONAL = math.sqrt(0.5)

local function KeepClear(p_At, p_Far)
	local function Gap(p_From, p_Way, p_Length)
		local s_Hit = RaycastManager:Raycast(p_From, p_From + p_Way * (p_Length or ROOM_CLEARANCE), RAY_FLAGS)

		if s_Hit == nil then
			return p_Length or ROOM_CLEARANCE
		end

		local s_To = s_Hit.position - p_From
		return math.sqrt(Dot(s_To, s_To))
	end

	-- the room round p_At along the floor's axes, up to ROOM_CLEARANCE each way, or p_Far if farther (a room measured for the volume:
	-- its boxes reach a wall up to a cell off)
	local s_Far = math.max(ROOM_CLEARANCE, p_Far or 0.0)
	local s_Gaps = { px = Gap(p_At, Vec3(1.0, 0.0, 0.0), s_Far), nx = Gap(p_At, Vec3(-1.0, 0.0, 0.0), s_Far),
		pz = Gap(p_At, Vec3(0.0, 0.0, 1.0), s_Far), nz = Gap(p_At, Vec3(0.0, 0.0, -1.0), s_Far) }
	local s_X, s_WideX = Shift(math.min(s_Gaps.px, ROOM_CLEARANCE), math.min(s_Gaps.nx, ROOM_CLEARANCE))
	local s_Z, s_WideZ = Shift(math.min(s_Gaps.pz, ROOM_CLEARANCE), math.min(s_Gaps.nz, ROOM_CLEARANCE))
	local s_At = p_At + Vec3(s_X, 0.0, s_Z)

	local s_U, s_V = Vec3(DIAGONAL, 0.0, DIAGONAL), Vec3(DIAGONAL, 0.0, -DIAGONAL)
	local s_AlongU, s_WideU = Shift(Gap(s_At, s_U), Gap(s_At, s_U * -1.0))
	local s_AlongV, s_WideV = Shift(Gap(s_At, s_V), Gap(s_At, s_V * -1.0))
	return s_At + s_U * s_AlongU + s_V * s_AlongV, math.min(s_WideX, s_WideZ, s_WideU, s_WideV), s_Gaps
end

-- a place narrower than this (m) is only a way through (a gap between a crate and the wall): streams pass it, smoke does not gather
-- there (its smoke would show over what is round it)
local ROOM_NARROW = 0.7

local ROOM_RAYS_A_POINT = 10          -- a point's rays: the one that reaches it, its 8 to the walls, the one that checks the move

-- p_Volume: the room is to be drawn as the volume -- measured up to its ceiling (no ROOM_CLEARANCE under it: no card to show past it),
-- in layers that fit floor to ceiling (Vol.Layer), up to VOLUME.POINTS points the volume's grid holds, each also measured up and down.
-- p_Outside: a canister in the open (VOLUME.OUTDOORS): its ceiling is VOLUME.OUT_HEIGHT over the floor found under it, and nothing it
-- gets to is left out for having the sky over it. p_From: where an M320 round hit, over that floor (its smoke's first point in the
-- layer that is in; in the open, its cloud's top VOLUME.M320_OVER over it at least)
local function RoomStart(p_Floor, p_Ceiling, p_Volume, p_Outside, p_From)
	-- the room's floor: where the canister lies, or the floor round the table, counter or shelf it lies on (Vol.FloorUnder); its
	-- first point in the layer it lies in, over what it lies on (the source of the smoke's way, Vol.Path)
	local s_Base, s_FloorSaid = Vol.FloorUnder(p_Floor)

	if p_Outside then
		p_Ceiling = s_Base.y + VOLUME.OUT_HEIGHT

		if p_From ~= nil then
			p_Ceiling = math.max(p_Ceiling, p_From.y + VOLUME.M320_OVER)
		end
	end

	local s_Layer = p_Volume and Vol.Layer(p_Ceiling - s_Base.y) or ROOM_CELL
	local s_J = math.max(0, math.floor((p_Floor.y + 0.15 - s_Base.y) / s_Layer))

	if p_From ~= nil then
		s_J = math.max(0, math.min(p_Volume and Vol.NY - 1 or 1e9, math.floor((p_From.y - s_Base.y) / s_Layer)))
	end

	local s_Source = Vec3(p_Floor.x, math.max(s_Base.y + s_Layer * (0.5 + s_J), p_Floor.y + 0.15), p_Floor.z)
	local s_First = { i = 0, j = s_J, k = 0, at = s_Source, reach = 0.0 }
	local s_Clear, _, s_Gaps = KeepClear(s_First.at, p_Volume and ROOM_CELL or nil)
	s_First.gaps = s_Gaps

	if p_Volume then
		Vol.Gaps(s_First.gaps, s_First.at, s_Layer)
		s_First.path = 0.0
	end

	if RaycastManager:Raycast(s_First.at, s_Clear, RAY_FLAGS) == nil then
		s_First.at = s_Clear
	end

	-- as far along the floor as the volume's smoke spreads (and the half cell its last points' boxes reach past it)
	local s_Reach = p_Volume and math.min(ROOM_REACH, VOLUME.RADIUS + ROOM_CELL * 0.5) or ROOM_REACH

	return { floor = s_Base, top = p_Ceiling - ROOM_CLEARANCE, ceiling = p_Ceiling, cells = { s_First }, queue = { s_First },
		seen = { ["0," .. s_J .. ",0"] = true },
		head = 1, rays = 0, frames = 0, done = false, layer = s_Layer, forVolume = p_Volume == true, reach = s_Reach,
		spread = { minI = 0, maxI = 0, minK = 0, maxK = 0 }, source = s_Source, drop = p_Floor.y - s_Base.y, floorSaid = s_FloorSaid,
		outside = p_Outside == true, open = s_First, hit = p_From }
end

-- one frame's measuring, up to p_Rays rays: true once the room is measured (for the volume as its smoke flows, VOLUME.FLOW)
local function RoomMeasure(p_Room, p_Rays)
	if p_Room.forVolume and VOLUME.FLOW then
		return Vol.Flow(p_Room, p_Rays)
	end

	local s_Rays = 0
	local s_Most = p_Room.forVolume and VOLUME.POINTS or ROOM_MAX_POINTS
	local s_APoint = ROOM_RAYS_A_POINT + (p_Room.forVolume and Vol.RAYS_A_POINT + (VOLUME.UNDER_ROOF and 1 or 0) or 0)
	p_Room.frames = p_Room.frames + 1

	while p_Room.head <= #p_Room.queue do
		local s_Cell = p_Room.queue[p_Room.head]
		local s_Next = s_Cell.next or 1

		while s_Next <= #ROOM_STEPS do
			if #p_Room.cells >= s_Most then
				p_Room.done = true
				return true
			end

			if s_Rays + s_APoint > p_Rays then
				s_Cell.next = s_Next
				return false
			end

			local l_Step = ROOM_STEPS[s_Next]
			s_Next = s_Next + 1
			local l_I, l_J, l_K = s_Cell.i + l_Step[1], s_Cell.j + l_Step[2], s_Cell.k + l_Step[3]
			local l_Key = l_I .. "," .. l_J .. "," .. l_K
			local l_At = Vec3(p_Room.floor.x + l_I * ROOM_CELL, p_Room.floor.y + p_Room.layer * (0.5 + l_J), p_Room.floor.z + l_K * ROOM_CELL)
			local l_Reach = math.sqrt(l_I * l_I + l_K * l_K) * ROOM_CELL
			-- under the ceiling: kept ROOM_CLEARANCE under it for the streams' cards; for the volume, wherever a clear ray gets, within
			-- its grid
			local l_Under = l_At.y <= p_Room.top

			if p_Room.forVolume then
				l_Under = l_J < Vol.NY and Vol.Fits(p_Room.spread, l_I, l_K)
			end

			if not p_Room.seen[l_Key] and l_J >= 0 and l_Under and l_Reach <= p_Room.reach then
				s_Rays = s_Rays + 1
				p_Room.rays = p_Room.rays + 1

				-- a point is reached once, from the first neighbour with a clear ray to it (a blocked one leaves it to the others); then
				-- kept off the walls, if the way to where it moves is clear as well (else it stays where it was reached)
				if RaycastManager:Raycast(s_Cell.at, l_At, RAY_FLAGS) == nil then
					p_Room.seen[l_Key] = true

					-- for the volume, a point with open sky over it (out through a door) is outdoors, not the room's (VOLUME.UNDER_ROOF):
					-- the smoke stops at the door. Looked up to ROOM_CEILING over the room's own ceiling: a point low down in a tall
					-- room (down its stairs, under an atrium's roof) is under that roof however far up it is. (A cloud in the open
					-- leaves nothing out.)
					local l_Sky = Vec3(l_At.x, math.max(l_At.y, p_Room.ceiling or l_At.y) + ROOM_CEILING, l_At.z)

					if p_Room.forVolume and VOLUME.UNDER_ROOF and not p_Room.outside
						and RaycastManager:Raycast(l_At, l_Sky, RAY_FLAGS) == nil then
						p_Room.outdoors = (p_Room.outdoors or 0) + 1
						-- and the side of the point it was reached from closed at the wall beside that door
						local l_Side = (l_Step[1] == 1 and "px") or (l_Step[1] == -1 and "nx") or (l_Step[3] == 1 and "pz")
							or (l_Step[3] == -1 and "nz") or nil
						local l_More = 1 + Vol.CloseSide(s_Cell, l_Side, p_Room.layer)
						s_Rays = s_Rays + l_More
						p_Room.rays = p_Room.rays + l_More

						-- an opening to the open the room's smoke may pour out of (VOLUME.EXITS): where, and from which of its points
						if l_Side ~= nil then
							p_Room.openings = p_Room.openings or {}
							p_Room.openings[#p_Room.openings + 1] = { cell = s_Cell, side = l_Side, at = l_At, i = l_I, j = l_J, k = l_K }
						end
					else
						local l_Clear, l_Wide, l_Gaps = KeepClear(l_At, p_Room.forVolume and ROOM_CELL or nil)
						s_Rays = s_Rays + s_APoint - 1
						p_Room.rays = p_Room.rays + s_APoint - 1

						local l_Path = nil

						if p_Room.forVolume then
							-- (its rays up and down counted in s_APoint; those that tell a wall from part of something on top)
							local l_More = Vol.Gaps(l_Gaps, l_At, p_Room.layer) - 2
							s_Rays = s_Rays + l_More
							p_Room.rays = p_Room.rays + l_More
							Vol.Spread(p_Room.spread, l_I, l_K)
							l_Path = Vol.Path(p_Room, s_Cell, l_At, l_Step)
						end

						if RaycastManager:Raycast(s_Cell.at, l_Clear, RAY_FLAGS) == nil then
							l_At = l_Clear
						end

						local l_Cell = { i = l_I, j = l_J, k = l_K, at = l_At, reach = l_Reach, from = s_Cell,
							narrow = l_Wide < ROOM_NARROW, gaps = l_Gaps, path = l_Path }
						p_Room.cells[#p_Room.cells + 1] = l_Cell
						p_Room.queue[#p_Room.queue + 1] = l_Cell
					end
				end
			end
		end

		s_Cell.next = s_Next
		p_Room.head = p_Room.head + 1
	end

	p_Room.done = true
	return true
end

-- The places the streams run to: up to ROOM_STREAMS points spread over the measured room, nearest first (every n-th in the measuring's
-- own nearest-first order, the canister's own point left out). A small room has fewer places than streams: they take turns.
local function StreamTargets(p_Room)
	-- the places smoke may gather: not the canister's own point, not a narrow way through (unless there is nothing else), never
	-- closer to the ceiling than ROOM_CLEARANCE (a room measured for the volume reaches it)
	local s_Open = {}

	for l_Index = 2, #p_Room.cells do
		if not p_Room.cells[l_Index].narrow and p_Room.cells[l_Index].at.y <= p_Room.top then
			s_Open[#s_Open + 1] = p_Room.cells[l_Index]
		end
	end

	if #s_Open == 0 then
		for l_Index = 2, #p_Room.cells do
			if p_Room.cells[l_Index].at.y <= p_Room.top then
				s_Open[#s_Open + 1] = p_Room.cells[l_Index]
			end
		end
	end

	if #s_Open == 0 then
		return { p_Room.cells[1] }
	end

	local s_Places = math.min(ROOM_STREAMS, #s_Open)
	local s_Targets = {}

	for l_N = 1, s_Places do
		s_Targets[l_N] = s_Open[math.max(1, math.floor(l_N * #s_Open / s_Places + 0.5))]
	end

	return s_Targets
end

-- a straight way a stream may take: clear, and clear ROOM_PATH_CLEAR to either side of it as well (3 rays)
local function WideClear(p_From, p_To)
	if RaycastManager:Raycast(p_From, p_To, RAY_FLAGS) ~= nil then
		return false
	end

	local s_Way = p_To - p_From
	local s_Flat = math.sqrt(s_Way.x * s_Way.x + s_Way.z * s_Way.z)

	if s_Flat < 0.01 then
		return true
	end

	local s_Side = Vec3(-s_Way.z / s_Flat, 0.0, s_Way.x / s_Flat) * ROOM_PATH_CLEAR
	return RaycastManager:Raycast(p_From + s_Side, p_To + s_Side, RAY_FLAGS) == nil and
		RaycastManager:Raycast(p_From - s_Side, p_To - s_Side, RAY_FLAGS) == nil
end

-- The way a stream runs from the canister's mouth to its place: back along the points each was reached from, straightened wherever a
-- straight way is clear with room on both sides (WideClear), so it bends only round what is in the way and keeps off corners.
local function StreamPath(p_Mouth, p_Target)
	local s_Chain = {}
	local s_Cell = p_Target

	while s_Cell ~= nil do
		table.insert(s_Chain, 1, s_Cell.at)
		s_Cell = s_Cell.from
	end

	table.insert(s_Chain, 1, p_Mouth)

	local s_Path = { s_Chain[1] }
	local s_At = 1

	while s_At < #s_Chain do
		local s_To = s_At + 1

		for l_Try = #s_Chain, s_At + 2, -1 do
			if WideClear(s_Chain[s_At], s_Chain[l_Try]) then
				s_To = l_Try
				break
			end
		end

		s_Path[#s_Path + 1] = s_Chain[s_To]
		s_At = s_To
	end

	return s_Path
end

-- One frame of a stream along its way: as fast as it leaves the jet (ROOM_STREAM_SPEED), slower and slower (ROOM_STREAM_EASE), never
-- slower than ROOM_STREAM_SLOW. True once it is at its place.
local function StreamMove(p_Stream, p_Delta)
	p_Stream.t = p_Stream.t + p_Delta
	local s_Left = math.max(ROOM_STREAM_SLOW, ROOM_STREAM_SPEED * math.exp(-p_Stream.t / ROOM_STREAM_EASE)) * p_Delta

	while s_Left > 0.0 and p_Stream.leg < #p_Stream.path do
		local s_Next = p_Stream.path[p_Stream.leg + 1]
		local s_Way = s_Next - p_Stream.at
		local s_Length = math.sqrt(Dot(s_Way, s_Way))

		if s_Length <= s_Left then
			p_Stream.at = s_Next
			p_Stream.leg = p_Stream.leg + 1
			s_Left = s_Left - s_Length
		else
			p_Stream.at = p_Stream.at + s_Way * (s_Left / s_Length)
			s_Left = 0.0
		end
	end

	return p_Stream.leg >= #p_Stream.path
end

-- Indoors the jet needs JET_ROOM of clear space in front of it: with a wall right there, the canister turns (where it lies) to the most
-- open of 8 sides. The side to turn to, or nil.
local function OpenSide(p_Pose)
	local s_From = p_Pose.trans + Vec3(0.0, 0.1, 0.0)

	local function Clear(p_Way)
		local s_Hit = RaycastManager:Raycast(s_From, s_From + p_Way * 6.0, RAY_FLAGS)

		if s_Hit == nil then
			return 6.0
		end

		local s_To = s_Hit.position - s_From
		return math.sqrt(Dot(s_To, s_To))
	end

	if Clear(Horizontal(p_Pose.up) or Vec3(0.0, 0.0, 1.0)) >= JET_ROOM then
		return nil
	end

	local s_Best, s_BestClear = nil, -1.0

	for l_N = 0, 7 do
		local l_Angle = l_N * math.pi / 4.0
		local l_Way = Vec3(math.cos(l_Angle), 0.0, math.sin(l_Angle))
		local l_Clear = Clear(l_Way)

		if l_Clear > s_BestClear then
			s_Best, s_BestClear = l_Way, l_Clear
		end
	end

	return s_Best
end

-- a canister lying at p_Pose indoors (and the indoor smoke made): the floor under it and the ceiling's height; outdoors nil
local function Indoors(p_Pose)
	if not ROOM_SMOKE or m_SmokeRoomEffect == nil or m_SmokeIndoorEffect == nil then
		return nil
	end

	local s_Ceiling = CeilingOver(p_Pose.trans)

	if s_Ceiling == nil then
		return nil
	end

	return Vec3(p_Pose.trans.x, p_Pose.trans.y - CANISTER_REST_HEIGHT - CANISTER_CLEARANCE, p_Pose.trans.z), s_Ceiling
end

-- a canister lying at p_Pose in the open (no ceiling over it) whose cloud the volume is to draw (VOLUME.OUTDOORS): the ground under it
-- (its ceiling is VOLUME.OUT_HEIGHT over the floor the room finds round it, RoomStart); else nil
local function Outdoors(p_Pose)
	if not VOLUME.OUTDOORS or not Vol.WillDraw() then
		return nil
	end

	return Vec3(p_Pose.trans.x, p_Pose.trans.y - CANISTER_REST_HEIGHT - CANISTER_CLEARANCE, p_Pose.trans.z)
end

-- where a canister lying at p_Pose pours its smoke: indoors (the floor under it, the ceiling's height), in the open as a cloud (the
-- floor, nil, true), or nil (the plume as it is); and, under a ceiling, how much of the place round it has the sky over it (for the log).
-- Under a ceiling with VOLUME.OPEN_SHARE or more of it open to the sky (Vol.OpenShare), it is in the open -- unless its smoke flows
-- (VOLUME.FLOW): then out from under that ceiling it goes as it flows, the ceiling only where its layers end
local function SmokePlace(p_Pose)
	local s_Floor, s_Ceiling = Indoors(p_Pose)

	if s_Floor == nil then
		local s_Open = Outdoors(p_Pose)
		return s_Open, nil, s_Open ~= nil, nil
	end

	if not VOLUME.OUTDOORS or not Vol.WillDraw() or (VOLUME.OPEN_SHARE or 1.0) >= 1.0 or VOLUME.FLOW then
		return s_Floor, s_Ceiling, false, nil
	end

	local s_Share, s_Reached, s_Sky = Vol.OpenShare(p_Pose.trans, s_Ceiling)
	local s_Said = string.format("%d of the %d place(s) round it got to have the sky over them", s_Sky, s_Reached)

	if s_Reached >= Vol.SHARE_FEWEST and s_Share >= VOLUME.OPEN_SHARE then
		return Outdoors(p_Pose), nil, true, s_Said .. ": in the open, under a ceiling where it lies"
	end

	return s_Floor, s_Ceiling, false, s_Said
end

-- the canister lying indoors at p_Pose, turned to the room's open side if a wall is right in front of its jet (from where p_At is)
local function IndoorPose(p_Pose, p_At, p_How)
	local s_Side = OpenSide(p_Pose)

	if s_Side == nil then
		return p_Pose, p_How
	end

	local s_Pose, s_How = RestPose(LinearTransform(Vec3(-s_Side.z, 0.0, s_Side.x), s_Side, Vec3(0.0, 1.0, 0.0), p_At))
	return s_Pose, s_How .. ", turned to the room's open side"
end

-- the room is filled from p_Down's mouth (p_Frame: its smoke's frame): measured first, then the streams (p_Outside: a cloud in the open,
-- Outdoors: the volume or the plume, never the streams)
local function StartRoom(p_Down, p_Floor, p_Ceiling, p_Frame, p_Outside)
	p_Down.room = RoomStart(p_Floor, p_Ceiling, Vol.WillDraw(), p_Outside, p_Down.hit)
	p_Down.room.notVolume = not p_Down.room.forVolume and Vol.WhyNot() or nil
	p_Down.room.jetFrame = p_Frame
	p_Down.room.start = p_Down.age
	p_Down.room.height = p_Down.room.ceiling - p_Down.room.floor.y
	p_Down.room.mouth = p_Frame.trans + Vec3(0.0, JET_HEIGHT, 0.0)
	p_Down.room.streams = {}
	p_Down.room.launched = 0
end

local function At(p_Position)
	return LinearTransform(Vec3(1.0, 0.0, 0.0), Vec3(0.0, 1.0, 0.0), Vec3(0.0, 0.0, 1.0), p_Position)
end

-- ---- the volume (client) ----------------------------------------------------------------------------------------------------------
-- Its numbers reach its shader by name from a visual environment of our own, weighed 1 all the time (blended with nothing, so the
-- grid's bits arrive whole): TsSmokeA the canister and how far the smoke has grown, TsSmokeB the grid's low corner and its layer,
-- TsSmokeC density, its look (Vol.Look) and the mode word (Vol.ModeWord: the mode, the front's height, how open the bullets' holes
-- are), TsSmokeD the two bullets' holes' ends (Vol.HoleFrame), TsSmokeBits0-4 the grid's 468 cells. Nine names: a level blends sixteen
-- at most, and the game's own use up to seven at once (a rim light, a thermal sight, the tracers).
Vol.GUIDS = "6B4E1801-0008-4D18-8018-0000000001"
Vol.PRIORITY = 20001
-- the grid: 12 x 13 cells across (14.4 x 15.6 m: VOLUME.RADIUS's round cloud fits in it whole), 3 layers floor to ceiling
Vol.NX, Vol.NY, Vol.NZ = 12, 3, 13
-- (VOLUME.SIM: 12 x 3 x 12 places, how full each is in 3 steps -- 19 to a number of 31 bits, 23 numbers)
if VOLUME.SIM then
	Vol.NZ = 12
end
Vol.PARAMS = { "TsSmokeA", "TsSmokeB", "TsSmokeC", "TsSmokeD", "TsSmokeBits0", "TsSmokeBits1", "TsSmokeBits2", "TsSmokeBits3",
	"TsSmokeBits4" }
-- a point's rays for the volume, on top of the streams' own (whose four along the floor then reach a cell off): up and down, and the
-- two from the canister (Vol.Path: from it, and from over it)
Vol.RAYS_A_POINT = 4

-- how far the smoke goes to get to a point (p_At, reached from the point p_From by the grid step p_Step): straight from the canister's
-- own point if nothing is in the way, else round the way it was reached (out through a door): the smoke shows past a wall only once
-- it has gone round it
-- (straight: from the canister's point, or from Vol.LIFT over it -- under the ceiling -- as the smoke rises and pours over an edge:
-- a landing's down a flight of stairs, a counter's, a low wall's)
Vol.LIFT = 1.0

function Vol.Path(p_Room, p_From, p_At, p_Step)
	local s_Round = (p_From.path or 0.0) + (p_Step[2] ~= 0 and p_Room.layer or ROOM_CELL)
	local s_Way = p_At - p_Room.source
	local s_Straight = math.sqrt(Dot(s_Way, s_Way))

	if s_Straight >= s_Round - 0.01 then
		return s_Round
	end

	local s_From = p_Room.cells[1].at

	if RaycastManager:Raycast(s_From, p_At, RAY_FLAGS) == nil then
		return s_Straight
	end

	local s_Lift = math.max(0.0, math.min(Vol.LIFT, (p_Room.ceiling or s_From.y) - 0.3 - s_From.y))

	if s_Lift > 0.05 and RaycastManager:Raycast(s_From + Vec3(0.0, s_Lift, 0.0), p_At, RAY_FLAGS) == nil then
		return s_Straight
	end

	return s_Round
end

-- ---- the smoke as it flows (VOLUME.FLOW) --------------------------------------------------------------------------------------------
-- The room measured for the volume as a fixed amount of smoke flows: from the canister's own place, the cheapest place next to those it
-- fills already is filled next (Vol.FlowCost), reached by a clear ray from one of them -- a wall stops it; a place a blocked ray met is
-- left to its other neighbours (round through a door) -- until VOLUME.AMOUNT is filled, the grid holds no more, or there is nowhere
-- left to flow. Each place filled is measured as the room's points are: kept off the walls, its gaps, its way from the canister.

-- what it costs the smoke to fill a place p_Way from its source: the farther the dearer, along VOLUME.SHAPE's ellipsoid (its halves
-- across, up and along) rounded to VOLUME.ROUNDNESS, and VOLUME.GRAVITY dearer for every Vol.FLOW_SPAN up (cheaper down) -- or the
-- room's own shape and gravity (p_Room.shape, p_Room.gravity: an M320 round's)
Vol.FLOW_SPAN = 7.0

function Vol.ShapeDistance(p_Way, p_Room)
	local s_Shape = (p_Room ~= nil and p_Room.shape) or { VOLUME.SHAPE_X, VOLUME.SHAPE_Y, VOLUME.SHAPE_Z }
	local s_R = VOLUME.ROUNDNESS or 2.0
	local s_Sum = (math.abs(p_Way.x) / (s_Shape[1] * 0.5)) ^ s_R + (math.abs(p_Way.y) / (s_Shape[2] * 0.5)) ^ s_R
		+ (math.abs(p_Way.z) / (s_Shape[3] * 0.5)) ^ s_R
	return s_Sum ^ (1.0 / s_R)
end

function Vol.Gravity(p_Room)
	return (p_Room ~= nil and p_Room.gravity) or VOLUME.GRAVITY or 0.0
end

function Vol.FlowCost(p_Way, p_Room)
	return Vol.ShapeDistance(p_Way, p_Room) + Vol.Gravity(p_Room) * p_Way.y / Vol.FLOW_SPAN
end

-- (VOLUME.FLOW_BY_WAY) a place's way from the source: on from the place where its last straight stretch starts -- the one the place it
-- was found from got its own way from, if that one sees it; else from the place it was found from (round a corner, through a door).
-- How far that is (as Vol.ShapeDistance counts it, and in metres), and from where
function Vol.FlowWay(p_Room, p_From, p_Place, p_Spend)
	local s_Start = p_From.start or p_From

	if s_Start ~= p_From then
		p_Spend(1)

		if RaycastManager:Raycast(s_Start.at, p_Place, RAY_FLAGS) ~= nil then
			s_Start = p_From
		end
	end

	local s_Way = p_Place - (s_Start.place or p_Room.source)
	return (s_Start.along or 0.0) + Vol.ShapeDistance(s_Way, p_Room), (s_Start.path or 0.0) + math.sqrt(Dot(s_Way, s_Way)), s_Start
end

-- (VOLUME.FLOW_OVER) a place whose middle a ray from its neighbour cannot get to is tried this much of a layer higher up in it
Vol.FLOW_LIFT = 0.4

-- the places the smoke may flow to next, the cheapest on top (of two as dear, the one found first)
function Vol.FlowBefore(p_A, p_B)
	return p_A.cost < p_B.cost or (p_A.cost == p_B.cost and p_A.order < p_B.order)
end

function Vol.HeapPush(p_Heap, p_Item)
	p_Heap[#p_Heap + 1] = p_Item
	local s_N = #p_Heap

	while s_N > 1 do
		local l_Up = math.floor(s_N / 2)

		if not Vol.FlowBefore(p_Heap[s_N], p_Heap[l_Up]) then
			break
		end

		p_Heap[s_N], p_Heap[l_Up] = p_Heap[l_Up], p_Heap[s_N]
		s_N = l_Up
	end
end

function Vol.HeapPop(p_Heap)
	local s_Top = p_Heap[1]
	local s_Last = table.remove(p_Heap)

	if #p_Heap > 0 then
		p_Heap[1] = s_Last
		local s_N = 1

		while true do
			local l_Best = s_N

			for _, l_Child in ipairs({ s_N * 2, s_N * 2 + 1 }) do
				if l_Child <= #p_Heap and Vol.FlowBefore(p_Heap[l_Child], p_Heap[l_Best]) then
					l_Best = l_Child
				end
			end

			if l_Best == s_N then
				break
			end

			p_Heap[s_N], p_Heap[l_Best] = p_Heap[l_Best], p_Heap[s_N]
			s_N = l_Best
		end
	end

	return s_Top
end

-- one frame of it, up to p_Rays rays (a place filled costs a point's rays, a neighbour looked at one): true once done
function Vol.Flow(p_Room, p_Rays)
	local s_Rays = 0
	local s_APoint = ROOM_RAYS_A_POINT + Vol.RAYS_A_POINT
	local s_Place = ROOM_CELL * ROOM_CELL * p_Room.layer
	p_Room.frames = p_Room.frames + 1
	p_Room.heap = p_Room.heap or {}
	p_Room.amount = p_Room.amount or s_Place
	p_Room.order = p_Room.order or 0

	local function Spend(p_N)
		s_Rays = s_Rays + p_N
		p_Room.rays = p_Room.rays + p_N
	end

	-- (VOLUME.SIM: the places measured hold more than the smoke fills, SIM_ROOM -- room for it to spread as it fills over time --, and
	-- each one keeps which of its neighbours a clear ray joins it to: Vol.Link)
	-- (and the smoke of canisters poured into it, VOLUME.MERGE)
	local s_Fills = ((p_Room.amountMax or VOLUME.AMOUNT) + (p_Room.pouredIn or 0.0)) * (VOLUME.SIM and VOLUME.SIM_ROOM or 1.0)

	if VOLUME.SIM and p_Room.cellAt == nil then
		p_Room.cellAt = { [Vol.Key(p_Room.cells[1].i, p_Room.cells[1].j, p_Room.cells[1].k)] = p_Room.cells[1] }
	end

	while true do
		local s_Cell = p_Room.open

		if s_Cell == nil then
			-- the next place to fill: the cheapest found, while there is smoke left and the grid holds it
			if #p_Room.heap == 0 or p_Room.amount >= s_Fills or #p_Room.cells >= VOLUME.POINTS then
				-- (the places standing on a floor across their own place over air the smoke has not got to: left out, the smoke on
				-- elsewhere -- Vol.FlowOverFloors)
				if Vol.FlowOverFloors(p_Room) == 0 or #p_Room.heap == 0 then
					p_Room.flowEnd = (p_Room.amount >= s_Fills and "all of it") or (#p_Room.heap == 0 and "nowhere left to flow")
						or "as much as the grid holds"
					return Vol.FlowDone(p_Room)
				end
			end

			if s_Rays + s_APoint > p_Rays then
				return false
			end

			-- (this frame's measuring time spent, VOLUME.MEASURE_MS: on in the next one)
			if p_Room.measureUntil ~= nil and s_Rays > 0 then
				local l_Now = Vol.Clock()

				if l_Now ~= nil and l_Now >= p_Room.measureUntil then
					p_Room.capped = (p_Room.capped or 0) + 1
					return false
				end
			end

			local l_Next = Vol.HeapPop(p_Room.heap)
			-- (the grid's top layer only under something over it -- a ceiling, a roof -- within half a layer over its top: out under
			-- the open sky, a room's smoke would end there in a flat face at the room's ceiling height; it stays in the layers under
			-- that, its top soft. A cloud in the open thins out under its own top instead.)
			local l_Capped = true

			if l_Next.j == Vol.NY - 1 and not p_Room.outside then
				Spend(1)
				l_Capped = RaycastManager:Raycast(l_Next.place, l_Next.place + Vec3(0.0, p_Room.layer, 0.0), RAY_FLAGS) ~= nil
			end

			if l_Capped and Vol.FitsRoom(p_Room, l_Next.i, l_Next.k) then
				local l_At = l_Next.at
				local l_Clear, l_Wide, l_Gaps = KeepClear(l_At, ROOM_CELL)
				Spend(s_APoint - 1 + Vol.Gaps(l_Gaps, l_At, p_Room.layer) - 2)
				-- (measured from higher up in its place, VOLUME.FLOW_OVER: its gaps up and down as from its place's middle, where its
				-- box is put -- down to the top of what it stands over, not through it)
				local l_Lift = l_At.y - l_Next.place.y
				l_Gaps.up = l_Gaps.up + l_Lift
				l_Gaps.down = l_Gaps.down - l_Lift
				Vol.Spread(p_Room.spread, l_Next.i, l_Next.k)
				-- (its way there: along it, as found -- VOLUME.FLOW_BY_WAY --; else straight from the canister or round, Vol.Path)
				local l_Path = l_Next.path or Vol.Path(p_Room, l_Next.from, l_At, l_Next.step)

				if RaycastManager:Raycast(l_Next.from.at, l_Clear, RAY_FLAGS) == nil then
					l_At = l_Clear
				end

				-- (whose canister its way is from: a second one's poured in, VOLUME.MERGE, its places' ways from its own place --
				-- Vol.SimWayHeld)
				s_Cell = { i = l_Next.i, j = l_Next.j, k = l_Next.k, at = l_At, reach = math.sqrt(l_Next.i * l_Next.i + l_Next.k * l_Next.k)
					* ROOM_CELL, from = l_Next.from, narrow = l_Wide < ROOM_NARROW, gaps = l_Gaps, path = l_Path, cost = l_Next.cost,
					place = l_Next.place, along = l_Next.along, start = l_Next.start, over = l_Next.over,
					wayOf = l_Next.start ~= nil and l_Next.start.wayOf or nil }
				p_Room.cells[#p_Room.cells + 1] = s_Cell
				p_Room.amount = p_Room.amount + s_Place
				p_Room.open = s_Cell

				if VOLUME.SIM then
					p_Room.cellAt[Vol.Key(s_Cell.i, s_Cell.j, s_Cell.k)] = s_Cell
					Vol.Link(p_Room, l_Next.from, s_Cell)
					p_Room.version = (p_Room.version or 0) + 1
				end
			end
		else
			-- the places next to it the smoke can flow on to: a clear ray from it to theirs
			local s_Next = s_Cell.next or 1

			while s_Next <= #ROOM_STEPS do
				if s_Rays + 1 > p_Rays then
					s_Cell.next = s_Next
					return false
				end

				-- (this frame's measuring time spent, VOLUME.MEASURE_MS: on in the next one)
				if p_Room.measureUntil ~= nil and s_Rays > 0 and (Vol.Clock() or 0.0) >= p_Room.measureUntil then
					p_Room.capped = (p_Room.capped or 0) + 1
					s_Cell.next = s_Next
					return false
				end

				local l_Step = ROOM_STEPS[s_Next]
				s_Next = s_Next + 1
				local l_I, l_J, l_K = s_Cell.i + l_Step[1], s_Cell.j + l_Step[2], s_Cell.k + l_Step[3]
				local l_Key = l_I .. "," .. l_J .. "," .. l_K
				local l_Other = VOLUME.SIM and p_Room.cellAt[Vol.Key(l_I, l_J, l_K)] or nil

				-- (VOLUME.SIM: a neighbour that is one of the room's places already, found from elsewhere: whether a clear ray joins the two)
				if l_Other ~= nil and l_Other ~= s_Cell.from and not Vol.Linked(p_Room, s_Cell, l_Other) then
					Spend(1)

					if RaycastManager:Raycast(s_Cell.at, l_Other.at, RAY_FLAGS) == nil then
						Vol.Link(p_Room, s_Cell, l_Other)
					end
				elseif not p_Room.seen[l_Key] and l_J >= 0 and l_J < Vol.NY and Vol.FitsRoom(p_Room, l_I, l_K) then
					local l_Place = Vec3(p_Room.floor.x + l_I * ROOM_CELL, p_Room.floor.y + p_Room.layer * (0.5 + l_J),
						p_Room.floor.z + l_K * ROOM_CELL)
					local l_At = l_Place
					Spend(1)
					local l_Blocked = RaycastManager:Raycast(s_Cell.at, l_At, RAY_FLAGS) ~= nil

					-- (VOLUME.FLOW_OVER: its middle in something low -- a bed, a sofa, a table --, tried higher up in it)
					if l_Blocked and VOLUME.FLOW_OVER then
						l_At = l_Place + Vec3(0.0, p_Room.layer * Vol.FLOW_LIFT, 0.0)
						Spend(1)
						l_Blocked = RaycastManager:Raycast(s_Cell.at, l_At, RAY_FLAGS) ~= nil
					end

					if not l_Blocked then
						p_Room.seen[l_Key] = true
						p_Room.order = p_Room.order + 1
						local l_Item = { i = l_I, j = l_J, k = l_K, at = l_At, place = l_Place, from = s_Cell, step = l_Step,
							order = p_Room.order, over = l_At ~= l_Place }

						if VOLUME.FLOW_BY_WAY then
							l_Item.along, l_Item.path, l_Item.start = Vol.FlowWay(p_Room, s_Cell, l_Place, Spend)
							l_Item.cost = l_Item.along + Vol.Gravity(p_Room) * (l_Place.y - p_Room.source.y) / Vol.FLOW_SPAN
						else
							l_Item.cost = Vol.FlowCost(l_Place - p_Room.source, p_Room)
						end

						Vol.HeapPush(p_Room.heap, l_Item)
					end
				end
			end

			s_Cell.next = s_Next
			-- (a second canister's place waiting to have its neighbours found, VOLUME.MERGE: next)
			p_Room.open, p_Room.openNext = p_Room.openNext, nil
		end
	end
end

-- (VOLUME.FLOW_FLOORS) a place filled whose smoke stands on a floor across its own place -- the floor less than 0.45 of a layer under
-- its middle: a slab inside it -- over air the smoke has not got to (the place under it found, not filled: a hall under the floor of
-- a stairwell's upper part, open to it) would be drawn down through that floor into that air (the grid smooths a place's smoke over its
-- whole height). Such places are left out, their smoke flowing on elsewhere. How many were left out now.
function Vol.FlowOverFloors(p_Room)
	if not VOLUME.FLOW_FLOORS then
		return 0
	end

	local s_Filled = {}

	for _, l_Cell in ipairs(p_Room.cells) do
		s_Filled[l_Cell.i .. "," .. l_Cell.j .. "," .. l_Cell.k] = true
	end

	local s_Kept, s_Out = {}, 0

	for l_Index, l_Cell in ipairs(p_Room.cells) do
		local l_Below = l_Cell.i .. "," .. (l_Cell.j - 1) .. "," .. l_Cell.k
		local l_Gap = l_Cell.gaps ~= nil and l_Cell.gaps.down or nil

		if l_Index > 1 and not l_Cell.poured and l_Cell.j > 0 and l_Gap ~= nil and l_Gap < p_Room.layer * 0.45 and p_Room.seen[l_Below]
			and not s_Filled[l_Below] then
			s_Out = s_Out + 1

			-- (VOLUME.SIM: the smoke it held already goes back to the canister's place, to flow on from there)
			if p_Room.cellAt ~= nil then
				p_Room.cellAt[Vol.Key(l_Cell.i, l_Cell.j, l_Cell.k)] = nil
				p_Room.cells[1].f = (p_Room.cells[1].f or 0.0) + (l_Cell.f or 0.0)
				p_Room.cells[1].h = (p_Room.cells[1].h or 0.0) + (l_Cell.h or 0.0)
				p_Room.gaveBack = (p_Room.gaveBack or 0.0) + (l_Cell.f or 0.0) + (l_Cell.h or 0.0)
				l_Cell.f, l_Cell.h = 0.0, 0.0
				p_Room.version = (p_Room.version or 0) + 1
				p_Room.simForce = true
			end
		else
			s_Kept[#s_Kept + 1] = l_Cell
		end
	end

	if s_Out > 0 then
		p_Room.cells = s_Kept
		p_Room.amount = p_Room.amount - s_Out * ROOM_CELL * ROOM_CELL * p_Room.layer
		p_Room.overFloors = (p_Room.overFloors or 0) + s_Out
	end

	return s_Out
end

-- the flow done: how far along its way the farthest place it filled is (the smoke grows that far, Vol.Spreads)
function Vol.FlowDone(p_Room)
	Vol.Farthest(p_Room)
	p_Room.done = true
	return true
end

-- how far along its way the farthest place filled so far is (kept as how far the smoke grows: Vol.Spreads)
function Vol.Farthest(p_Room)
	local s_Far = 0.0

	for _, l_Cell in ipairs(p_Room.cells) do
		s_Far = math.max(s_Far, l_Cell.path or 0.0)
	end

	p_Room.farthest = s_Far
	return s_Far
end

-- ---- the smoke filling its place over time (VOLUME.SIM) -----------------------------------------------------------------------------
-- Each place measured holds a share of smoke: stacked from the floor of its column (the places one over another that clear rays join,
-- from the lowest up) -- or, an M320 round's, hanging where it went off and sinking (Vol.SimHang). Each step moves smoke between columns
-- side by side as their levels (how high the smoke stands in each) even out: through the layers a clear ray joins the two at, as much
-- of it as stands over the higher of their floors (a door's sill, a counter's top), never steeper than SIM_SLOPE (a heap in the open);
-- down a step or off a ledge it pours. A place full with more coming presses it on. The grid gets how full each place is, in 3 steps.
Vol.SIM_DT = 0.05                    -- a step (s)
Vol.SIM_PRESS = 4.0                  -- how much a full column with more in it presses its smoke on (layers of level a layer of more)
Vol.SIM_CHECK = 710564442            -- the number the shader checks the 31 bits a number arrive whole by (0x2A5A5A5A)

Vol.SIM_SIDE = { { 1, 0 }, { 0, 1 } }   -- (the neighbours across a place joins its column to: +x, +z)

-- a place's key: a whole number (no string made each time it is looked up)
function Vol.Key(p_I, p_J, p_K)
	return ((p_K + 256) * 512 + (p_J + 256)) * 512 + (p_I + 256)
end

-- a clear ray between two of the room's places, both ways; and whether there is one
function Vol.Link(p_Room, p_A, p_B)
	local s_A, s_B = Vol.Key(p_A.i, p_A.j, p_A.k), Vol.Key(p_B.i, p_B.j, p_B.k)
	p_Room.links = p_Room.links or {}
	p_Room.links[s_A * 134217728 + s_B] = true
	p_Room.links[s_B * 134217728 + s_A] = true
end

function Vol.Linked(p_Room, p_A, p_B)
	return p_Room.links ~= nil and p_Room.links[Vol.Key(p_A.i, p_A.j, p_A.k) * 134217728 + Vol.Key(p_B.i, p_B.j, p_B.k)] == true
end

-- the room's columns (places one over another joined by clear rays, from the lowest up) and the layers clear rays join side by side
-- columns at; made again whenever the room's places changed (p_Room.version: one measured, one left out -- Vol.SimSync); each place
-- keeps its smoke: p_Cell.f stacked, p_Cell.h hanging
function Vol.SimTopo(p_Room)
	local s_Cols, s_Order = {}, {}

	for _, l_Cell in ipairs(p_Room.cells) do
		local l_Key = Vol.Key(l_Cell.i, 0, l_Cell.k)

		if s_Cols[l_Key] == nil then
			s_Cols[l_Key] = {}
			s_Order[#s_Order + 1] = l_Key
		end

		table.insert(s_Cols[l_Key], l_Cell)
		l_Cell.f = l_Cell.f or 0.0
		l_Cell.h = l_Cell.h or 0.0
	end

	local s_Segs = {}

	for _, l_Key in ipairs(s_Order) do
		local l_Cells = s_Cols[l_Key]
		table.sort(l_Cells, function(p_A, p_B) return p_A.j < p_B.j end)
		local l_Seg = nil

		for _, l_Cell in ipairs(l_Cells) do
			local l_Last = l_Seg ~= nil and l_Seg.cells[#l_Seg.cells] or nil

			if l_Last == nil or l_Cell.j ~= l_Last.j + 1 or not Vol.Linked(p_Room, l_Last, l_Cell) then
				l_Seg = { cells = {}, jbot = l_Cell.j, id = #s_Segs + 1, joins = 0 }
				s_Segs[#s_Segs + 1] = l_Seg
			end

			l_Seg.cells[#l_Seg.cells + 1] = l_Cell
			l_Cell.seg = l_Seg
		end
	end

	-- (a column with nothing under its lowest place within a layer -- past a roof's edge, out of a window high up, round where an M320
	-- round hit a wall high up --: no floor for the smoke to stack on; it hangs there (Vol.SimStep), and from the grid's lowest layer
	-- sinks out of its bottom, falling away; higher up, over air not measured, it stays hanging)
	-- (and how much each holds stacked, as a step works it out: what the columns are drawn from, Vol.SimColumnSpans -- before the next
	-- step, and with none to come once the smoke has been simulated on to where it ends up, VOLUME.SIM_AHEAD)
	for _, l_Seg in ipairs(s_Segs) do
		local l_Gaps = l_Seg.cells[1].gaps
		l_Seg.floorless = l_Gaps ~= nil and l_Gaps.down ~= nil and l_Gaps.down >= p_Room.layer - 0.01
		l_Seg.drops = l_Seg.floorless and l_Seg.jbot == 0
		l_Seg.v = 0.0

		for _, l_Cell in ipairs(l_Seg.cells) do
			l_Seg.v = l_Seg.v + l_Cell.f
		end
	end

	local s_Edges, s_EdgeOf = {}, {}

	for _, l_Cell in ipairs(p_Room.cells) do
		for _, l_Step in ipairs(Vol.SIM_SIDE) do
			local l_Other = p_Room.cellAt[Vol.Key(l_Cell.i + l_Step[1], l_Cell.j, l_Cell.k + l_Step[2])]

			if l_Other ~= nil and l_Other.seg ~= l_Cell.seg and Vol.Linked(p_Room, l_Cell, l_Other) then
				local l_Key = l_Cell.seg.id * 65536 + l_Other.seg.id
				local l_Edge = s_EdgeOf[l_Key]

				if l_Edge == nil then
					l_Edge = { a = l_Cell.seg, b = l_Other.seg, open = {} }
					s_EdgeOf[l_Key] = l_Edge
					s_Edges[#s_Edges + 1] = l_Edge
					l_Cell.seg.joins = l_Cell.seg.joins + 1
					l_Other.seg.joins = l_Other.seg.joins + 1
				end

				l_Edge.open[#l_Edge.open + 1] = l_Cell.j
			end
		end
	end

	-- (each column's way from its canister -- the shortest of its places' -- and how much longer than straight that is: Vol.SimWayHeld)
	local s_Way = {}

	for _, l_Cell in ipairs(p_Room.cells) do
		if l_Cell.path ~= nil then
			local l_Key = Vol.Key(l_Cell.i, 0, l_Cell.k)
			local l_W = s_Way[l_Key]

			if l_W == nil or l_Cell.path < l_W.path then
				local l_Of = l_Cell.wayOf or 1
				local l_D = (l_Cell.place or l_Cell.at) - ((l_Of == 2 and p_Room.source2) or p_Room.source)
				s_Way[l_Key] = { path = l_Cell.path, over = l_Cell.path - math.sqrt(Dot(l_D, l_D)), of = l_Of }
			end
		end
	end

	p_Room.sim = p_Room.sim or { t = 0.0, poured = 0.0, steps = 0 }
	p_Room.sim.segs, p_Room.sim.edges, p_Room.sim.cells = s_Segs, s_Edges, #p_Room.cells
	p_Room.sim.version = p_Room.version
	p_Room.colWay = s_Way
	return p_Room.sim
end

-- ---- the smoke shown along its way (VOLUME.SIM_WAY) -------------------------------------------------------------------------------
-- The front the smoke is drawn within grows straight out from the canister: a place behind a wall, a few metres off straight and many
-- round through the door, would be shown as the front gets to it -- the smoke seen coming through the wall (with VOLUME.SIM_AHEAD its
-- smoke is there long before; without, a little before). Each place's way from its canister is measured with it (round through a door,
-- p_Cell.path); a column whose way is longer than straight by more than Vol.WAY_SLACK -- behind a wall -- waits, empty, until a front
-- grown along the way at the front's own pace (p_Room.wayFront; a second canister's from when it poured in, wayFront2) gets as far, and
-- then is shown whole, fading in over the time the front takes to cross a place (the shader's emptying fade run backwards: Vol.
-- SimColumnSteps): the smoke seen coming in through the door at the front's pace, the columns along the way one after another. Columns
-- whose way is straight are shown as the front gets to them, as ever.
Vol.WAY_SLACK = 1.0

-- whether column p_Key waits, its way not got along yet
function Vol.SimWayHeld(p_Room, p_Key)
	if not VOLUME.SIM_WAY or p_Room.colWay == nil then
		return false
	end

	local s_W = p_Room.colWay[p_Key]

	if s_W == nil or s_W.over <= Vol.WAY_SLACK then
		return false
	end

	return s_W.path > (s_W.of == 2 and (p_Room.wayFront2 or -1.0) or (p_Room.wayFront or 0.0))
end

-- how fast the room's fronts grow (m/s): a canister's (VOLUME.SIM_FRONT_CANISTER), an M320 round's (SIM_FRONT)
function Vol.FrontSpeed(p_Room)
	return math.max(p_Room.hit ~= nil and VOLUME.SIM_FRONT or VOLUME.SIM_FRONT_CANISTER or VOLUME.SIM_FRONT or 3.0, 0.05)
end

-- the columns made again if the room's places changed since (and an M320 round's ball given to the places measured since): while
-- places are being measured (every frame), at most every Vol.SIM_TOPO_EVERY s of the smoke's time -- the newest places get smoke a
-- little later --; at once when places were left out (p_Room.simForce: their smoke went back to the canister's place) and once all are
-- measured
Vol.SIM_TOPO_EVERY = 0.1

function Vol.SimSync(p_Room)
	local s_Sim = p_Room.sim

	if s_Sim == nil or (s_Sim.version ~= p_Room.version and (p_Room.simForce or p_Room.done
		or s_Sim.t - (s_Sim.topoAt or -1.0) >= Vol.SIM_TOPO_EVERY - 1e-6)) then
		Vol.SimTopo(p_Room)
		p_Room.sim.topoAt = p_Room.sim.t
		p_Room.sim.topos = (p_Room.sim.topos or 0) + 1
		p_Room.simForce = nil

		if p_Room.hit ~= nil then
			Vol.SimHang(p_Room)
		end
	end

	return p_Room.sim
end

-- how much of a canister's smoke (a share of all of it) has poured out by p_T s
function Vol.SimPoured(p_T)
	local s_Burst = math.max(VOLUME.SIM_BURST, 0.01)
	local s_Rest = math.max(SMOKE_SECONDS - s_Burst, 0.01)
	return VOLUME.SIM_POUR * math.min(1.0, p_T / s_Burst) + (1.0 - VOLUME.SIM_POUR) * math.max(0.0, math.min(1.0, (p_T - s_Burst) / s_Rest))
end

-- one step of p_Dt s
function Vol.SimStep(p_Room, p_Dt)
	local s_Sim = p_Room.sim
	local s_Source = p_Room.cells[1]
	s_Sim.t = s_Sim.t + p_Dt
	s_Sim.steps = s_Sim.steps + 1

	-- a canister pours (in places' worth: its AMOUNT over a place's size); an M320 round's smoke is out already, hanging (Vol.SimHang)
	if p_Room.hit == nil then
		local l_All = (p_Room.amountMax or VOLUME.AMOUNT) / (ROOM_CELL * ROOM_CELL * p_Room.layer)
		local l_Now = l_All * Vol.SimPoured(s_Sim.t)
		s_Source.f = s_Source.f + (l_Now - s_Sim.poured)
		s_Sim.poured = l_Now
	end

	-- and the smokes that went off in this one's and joined it (Vol.SimJoin), each into its place as a canister pours
	for _, l_Pour in ipairs(s_Sim.pours or {}) do
		local l_Now = l_Pour.all * Vol.SimPoured(s_Sim.t - l_Pour.from)
		l_Pour.cell.f = (l_Pour.cell.f or 0.0) + (l_Now - l_Pour.poured)
		l_Pour.poured = l_Now
	end

	-- hanging smoke sinks: into the place under it while that has room, else it lands on what is there (stacked); in a column with
	-- no floor under it, the smoke stacked in it hangs instead, and what sinks out of its lowest place falls away (out of the grid) --
	-- a canister's poured over an edge; an M320 round's ball stays hanging in its lowest places (M320_HANG under where it hit), as the
	-- round's puffs hang on for their life
	local s_Sink = math.min(1.0, VOLUME.SIM_SINK * p_Dt / p_Room.layer)

	for _, l_Seg in ipairs(s_Sim.segs) do
		for l_Index, l_Cell in ipairs(l_Seg.cells) do
			if l_Seg.floorless and l_Cell.f > 0.0 then
				l_Cell.h = l_Cell.h + l_Cell.f
				l_Cell.f = 0.0
			end

			if l_Cell.h > 0.0005 then
				local l_Move = l_Cell.h * s_Sink
				local l_Under = l_Seg.cells[l_Index - 1]

				if l_Under == nil and l_Seg.drops and p_Room.hit == nil then
					l_Cell.h = l_Cell.h - l_Move
					s_Sim.fell = (s_Sim.fell or 0.0) + l_Move
				elseif l_Under == nil and l_Seg.floorless then
					-- (over air not measured: it stays hanging)
					l_Move = 0.0
				elseif l_Under == nil or l_Under.f >= 0.999 then
					l_Cell.h = l_Cell.h - l_Move
					l_Cell.f = l_Cell.f + l_Move
				else
					l_Move = math.min(l_Move, math.max(0.0, 1.0 - l_Under.f - l_Under.h))
					l_Cell.h = l_Cell.h - l_Move
					l_Under.h = l_Under.h + l_Move
				end
			end
		end
	end

	-- each column's level (in layers from the grid's floor) and where its smoke stands; and how much of it stays where it is (smoke
	-- that had settled when another came in, VOLUME.HOLD: Vol.SimHold)
	for _, l_Seg in ipairs(s_Sim.segs) do
		local l_V, l_Fixed = 0.0, 0.0

		for _, l_Cell in ipairs(l_Seg.cells) do
			l_V = l_V + l_Cell.f
			l_Fixed = l_Fixed + (l_Cell.fixed or 0.0)
		end

		l_Seg.fixed = l_Fixed

		local l_Cap = #l_Seg.cells
		l_Seg.v = l_V
		l_Seg.top = l_Seg.jbot + math.min(l_V, l_Cap)
		l_Seg.level = l_Seg.top + math.max(0.0, l_V - l_Cap) * Vol.SIM_PRESS
		-- (how much its level moves for a place's worth of smoke in or out: a full one presses, SIM_PRESS)
		l_Seg.stiff = l_V > l_Cap and Vol.SIM_PRESS or 1.0
		l_Seg.dv = 0.0
	end

	-- between columns side by side: from the higher level to the lower, through the joined layers the smoke stands in over the higher
	-- floor of the two, never steeper than SIM_SLOPE. No join moves more than its share of what would even the two out (over the more
	-- joins either has): a column never ends up past its neighbours, so the levels settle instead of swinging back and forth. The smoke
	-- that stays where it is (l_Seg.fixed) counts in its column's level, and none of it moves
	for _, l_Edge in ipairs(s_Sim.edges) do
		local l_Up, l_Down = l_Edge.a, l_Edge.b

		if l_Down.level > l_Up.level then
			l_Up, l_Down = l_Down, l_Up
		end

		local l_D = l_Up.level - l_Down.level - VOLUME.SIM_SLOPE
		local l_Free = l_Up.v - l_Up.fixed

		if l_D > 0.0 and l_Free > 0.0 then
			local l_Lo, l_Hi = math.max(l_Up.jbot, l_Down.jbot), l_Up.top
			local l_Wet = 0.0

			for _, l_J in ipairs(l_Edge.open) do
				l_Wet = l_Wet + math.max(0.0, math.min(l_Hi, l_J + 1) - math.max(l_Lo, l_J))
			end

			if l_Wet > 0.0 then
				local l_Most = 1.0 / ((l_Up.stiff + l_Down.stiff) * math.max(l_Up.joins, l_Down.joins, 1))
				local l_Q = math.min(math.min(VOLUME.SIM_SPREAD * l_Wet * p_Dt, l_Most) * l_D, l_Free / math.max(l_Up.joins, 1))
				l_Up.dv = l_Up.dv - l_Q
				l_Down.dv = l_Down.dv + l_Q
			end
		end
	end

	-- stacked again from each column's floor (more than it holds stays pressing in its top place)
	for _, l_Seg in ipairs(s_Sim.segs) do
		local l_V = math.max(0.0, l_Seg.v + l_Seg.dv)
		local l_N = #l_Seg.cells

		for l_Index, l_Cell in ipairs(l_Seg.cells) do
			l_Cell.f = math.max(0.0, math.min(1.0, l_V - (l_Index - 1)))
		end

		if l_V > l_N then
			l_Seg.cells[l_N].f = 1.0 + (l_V - l_N)
		end
	end

	-- (how far along its way its smoke has got by now: the fronts' pace, VOLUME.SIM_PACE)
	if VOLUME.SIM_PACE then
		Vol.SimPaceNote(p_Room)
	end
end

-- ---- the fronts at the smoke's own pace (VOLUME.SIM_PACE) -----------------------------------------------------------------------
-- After each step of the simulation, how far along its way (its places' paths from the canister: Vol.SimWayHeld's) its smoke has got
-- -- the farthest place holding Vol.PACE_SMOKE of a place's smoke or more -- is noted each time it gets further: the time and how far
-- (s_Sim.pace[1]; a second canister's poured in, its own places', pace[2], from when it poured in). The fronts follow it as the smoke's
-- age gets to each time (Vol.SimPaceAt: from one such point straight on to the next, never a step and a wait), at most
-- VOLUME.SIM_PACE_MOST m/s, their speed changing by Vol.PACE_EASE m/s a second at most -- slowing down in time to stop where it is
-- (Vol.PaceChase). Simulated on ahead (VOLUME.SIM_AHEAD), the points are there before the fronts need them.
Vol.PACE_SMOKE = 0.2
Vol.PACE_EASE = 6.0

function Vol.SimPaceNote(p_Room)
	local s_Sim = p_Room.sim
	local s_R = { 0.0, 0.0 }

	for _, l_Cell in ipairs(p_Room.cells) do
		if l_Cell.path ~= nil and (l_Cell.f or 0.0) + (l_Cell.h or 0.0) >= Vol.PACE_SMOKE then
			local l_Of = l_Cell.wayOf == 2 and 2 or 1

			if l_Cell.path > s_R[l_Of] then
				s_R[l_Of] = l_Cell.path
			end
		end
	end

	s_Sim.pace = s_Sim.pace or { {}, {} }

	for l_Of = 1, 2 do
		local l_List = s_Sim.pace[l_Of]
		local l_Last = l_List[#l_List]

		if s_R[l_Of] > (l_Last ~= nil and l_Last.r or 0.0) + 1e-3 then
			l_List[#l_List + 1] = { t = s_Sim.t, r = s_R[l_Of] }
		end
	end
end

-- how far along its way the smoke had got by the simulation's time p_T (noted from p_From on, p_List): straight on from each point
-- noted to the next; past the last, the last
function Vol.SimPaceAt(p_List, p_From, p_T)
	local s_T0, s_R0 = p_From, 0.0

	for _, l_P in ipairs(p_List) do
		if p_T <= l_P.t then
			if l_P.t - s_T0 < 1e-6 then
				return l_P.r
			end

			return s_R0 + (l_P.r - s_R0) * math.max(0.0, p_T - s_T0) / (l_P.t - s_T0)
		end

		s_T0, s_R0 = l_P.t, l_P.r
	end

	return s_R0
end

-- a front at p_At moving at p_V on towards p_Target over p_Dt s: no faster than it can slow down from to stop there (at
-- Vol.PACE_EASE m/s a second) nor than p_Most m/s, its speed changing by Vol.PACE_EASE m/s a second at most -- a target moving on, it
-- keeps a little behind it at its speed (never stopped dead by it); never back. Where it is and its speed
function Vol.PaceChase(p_At, p_V, p_Target, p_Most, p_Dt)
	local s_Want = math.max(0.0, math.min(p_Most, math.sqrt(2.0 * Vol.PACE_EASE * math.max(0.0, p_Target - p_At))))
	local s_Ease = Vol.PACE_EASE * p_Dt
	local s_V = math.max(0.0, (p_V or 0.0) + math.max(-s_Ease, math.min(s_Ease, s_Want - (p_V or 0.0))))
	return p_At + s_V * p_Dt, s_V
end

-- an M320 round's smoke out round where it hit (p_Room.hit): a ball of its M320_AMOUNT, each place measured within it filled (hanging)
-- by how much of it the ball takes; places measured later get theirs as they come (while p_Room.ballOpen)
function Vol.SimHang(p_Room)
	local s_R = (3.0 * (p_Room.amountMax or VOLUME.M320_AMOUNT) / (4.0 * math.pi)) ^ (1.0 / 3.0)
	local s_Floor = p_Room.floor

	for _, l_Cell in ipairs(p_Room.cells) do
		if not l_Cell.balled then
			l_Cell.balled = true
			local l_At = Vec3(s_Floor.x + l_Cell.i * ROOM_CELL, s_Floor.y + p_Room.layer * (0.5 + l_Cell.j), s_Floor.z + l_Cell.k * ROOM_CELL)
			local l_Way = l_At - p_Room.hit
			local l_D = math.sqrt(Dot(l_Way, l_Way))
			l_Cell.h = math.max(0.0, math.min(1.0, (s_R - l_D) / ROOM_CELL + 0.5))
		end
	end
end

-- how full a place is as drawn, in 3 steps (0 empty, 1 half, 2 full), a little held either way so it does not flip between them: the
-- step its smoke calls for now, and how far past the step's edge it is (how pressing the change is; 0: none)
function Vol.SimTarget(p_Cell)
	local s_V = math.min(1.0, (p_Cell.f or 0.0) + (p_Cell.h or 0.0))
	local s_Q = p_Cell.q or 0

	if s_Q == 0 and s_V > 0.3 then
		return s_V > 0.8 and 2 or 1, s_V - 0.3
	elseif s_Q == 1 and s_V > 0.8 then
		return 2, s_V - 0.8
	elseif s_Q == 1 and s_V < 0.2 then
		return 0, 0.2 - s_V
	elseif s_Q == 2 and s_V < 0.7 then
		return s_V < 0.2 and 0 or 1, 0.7 - s_V
	end

	return s_Q, 0.0
end

-- a whole number under 2^31 as a float whose bits carry all of it -- its sign, an exponent from 64 up (7 bits) and 23 of mantissa:
-- never a denormal, an infinity or a NaN, so it arrives whole (the visual environment copies a name's value as it is)
function Vol.Bits31(p_N)
	local s_Neg = p_N >= 1073741824
	local s_R = s_Neg and p_N - 1073741824 or p_N
	local s_E = math.floor(s_R / 8388608)
	local s_M = s_R - s_E * 8388608
	local s_V = (1.0 + s_M / 8388608) * 2.0 ^ (s_E + 64 - 127)
	return s_Neg and -s_V or s_V
end

-- the grid's 23 numbers (19 places a number, 3 steps each) from the room's places, round its spread (as Vol.Grid centres it): the low
-- corner and the numbers. Each time, at most Vol.SIM_FLIPS places change step, one step each, the most pressing first (the rest the
-- next times: p_Room.simBacklog of them), so the smoke fills in a place or two a frame instead of a dozen at once (0: all at once)
Vol.SIM_FLIPS = 2
Vol.POW3 = { [0] = 1 }

for l_D = 1, 18 do
	Vol.POW3[l_D] = Vol.POW3[l_D - 1] * 3
end

function Vol.SimWords(p_Room)
	if VOLUME.SIM_COLUMNS then
		return Vol.SimColumnWords(p_Room)
	end

	local s_I0, s_K0 = Vol.SimCorner(p_Room)
	local s_NX, s_NY, s_NZ = Vol.NX, Vol.NY, Vol.NZ
	local s_Due = {}

	for _, l_Cell in ipairs(p_Room.cells) do
		local l_X, l_Z = l_Cell.i - s_I0, l_Cell.k - s_K0

		-- (each place's index in the grid, nil off it)
		if l_X >= 0 and l_X < s_NX and l_Z >= 0 and l_Z < s_NZ and l_Cell.j >= 0 and l_Cell.j < s_NY then
			l_Cell.simAt = (l_Cell.j * s_NZ + l_Z) * s_NX + l_X
			local l_Q, l_Push = Vol.SimTarget(l_Cell)

			if l_Q ~= (l_Cell.q or 0) then
				s_Due[#s_Due + 1] = { cell = l_Cell, q = l_Q, push = l_Push }
			end
		else
			l_Cell.simAt = nil
		end
	end

	if Vol.SIM_FLIPS > 0 and #s_Due > Vol.SIM_FLIPS then
		table.sort(s_Due, function(p_A, p_B) return p_A.push > p_B.push end)
	end

	local s_Changed = 0

	for _, l_Due in ipairs(s_Due) do
		if Vol.SIM_FLIPS > 0 and s_Changed >= Vol.SIM_FLIPS then
			break
		end

		local l_Q = l_Due.cell.q or 0
		l_Due.cell.q = Vol.SIM_FLIPS > 0 and l_Q + (l_Due.q > l_Q and 1 or -1) or l_Due.q
		s_Changed = s_Changed + 1
	end

	p_Room.simBacklog = #s_Due - s_Changed

	-- (each place's step as a digit of its number: place index n is digit n % 19 of number n // 19)
	local s_Words = {}

	for l_W = 1, 23 do
		s_Words[l_W] = 0
	end

	for _, l_Cell in ipairs(p_Room.cells) do
		local l_At = l_Cell.simAt

		if l_At ~= nil and (l_Cell.q or 0) > 0 then
			local l_W = l_At // 19
			s_Words[l_W + 1] = s_Words[l_W + 1] + l_Cell.q * Vol.POW3[l_At - l_W * 19]
		end
	end

	return Vec3(p_Room.floor.x + (s_I0 - 0.5) * ROOM_CELL, p_Room.floor.y, p_Room.floor.z + (s_K0 - 0.5) * ROOM_CELL), s_Words
end

-- (VOLUME.SIM_COLUMNS) the grid as columns instead: each of its Vol.NX x Vol.NZ columns holds where its smoke starts (a whole layer)
-- and how high it stands (in Vol.SIM_TOPS steps a layer) as one digit of Vol.SimColumnCombos(), Vol.SimColumnDigits() of them a number
-- -- the smoke drawn spreads and rises a thin step at a time instead of a place (a layer high) at once. Each step fades in: up to
-- Vol.SIM_COLUMN_SLOTS columns at once have a slot -- the column, how it changes and how far on it is (14 bits: two in each of the
-- grid's last two numbers, two in the check number's low 28 bits) -- and the shader draws each that far on between its steps. A step
-- fades in over the time its column's smoke takes to rise or sink a step (Vol.SIM_COLUMN_FADE .. Vol.SIM_COLUMN_FADE_MOST s): a column
-- filling slowly creeps up all along instead of a step at a time. A column starting to hold smoke or emptying -- the smoke's edge,
-- what shows as it spreads -- takes that time, Vol.SIM_COLUMN_EDGES of them at once; any other step no longer than lets the slots take
-- every column wanting a step within Vol.SIM_COLUMN_SERVE s, many at once taking short turns one after another; with more steps
-- waiting than Vol.SIM_COLUMN_BEHIND (the smoke pouring out) the fading ones are hurried to finish within Vol.SIM_COLUMN_HURRY s. The most
-- pressing first, each held Vol.SIM_COLUMN_HOLD of a step past its half either way
Vol.SIM_TOPS = 3
Vol.SIM_COLUMN_SLOTS = 6
Vol.SIM_COLUMN_FADE = 0.05
Vol.SIM_COLUMN_FADE_MOST = 1.5
Vol.SIM_COLUMN_SERVE = 0.5
Vol.SIM_COLUMN_STAGGER = 2          -- columns starting to fade at most at a time, so the slots start and end apart (no beat of six)
Vol.SIM_COLUMN_EDGES = 3
Vol.SIM_COLUMN_HURRY = 0.25
Vol.SIM_COLUMN_BEHIND = 24          -- steps waiting past which the fading ones are hurried (the smoke pouring out, far ahead)
Vol.SIM_COLUMN_HOLD = 0.15
Vol.SIM_COLUMN_CHECK = 6          -- the check number's top 3 bits with the grid as columns, its first steps on the floor in parts
Vol.SIM_COLUMN_CHECK_WHOLE = 5    -- and with them whole (Vol.SIM_COLUMN_PARTS 1); any other: the shader draws it magenta
-- A column on the grid's floor starting to hold smoke shows its first step (a third of a layer high) a part at a time, in this many: a
-- part more each time its smoke gets a part further on towards that step (half a step and Vol.SIM_COLUMN_HOLD), so the smoke's edge
-- creeps on over the floor as its smoke gets there instead of a column's width at once, once its smoke is past a threshold; emptying,
-- a part at a time back. 3 (the shader's COL_PARTS) or 1: whole, at once
Vol.SIM_COLUMN_PARTS = 3

-- the check number's top 3 bits: the grid as columns, its first steps on the floor in parts or whole
function Vol.SimColumnCheck()
	return Vol.SIM_COLUMN_PARTS > 1 and Vol.SIM_COLUMN_CHECK or Vol.SIM_COLUMN_CHECK_WHOLE
end

-- how many a column's digit can be: empty, or a start (a whole layer, 0 .. Vol.NY - 1) and a top over it (in steps); and on the floor, a
-- first step shown in part (Vol.SIM_COLUMN_PARTS - 1 more)
function Vol.SimColumnCombos()
	return 1 + Vol.SIM_TOPS * Vol.NY * (Vol.NY + 1) // 2 + (Vol.SIM_COLUMN_PARTS - 1)
end

-- a column's digit as it is shown (p_Shown: b its start, t its top in steps, p how many parts of a first step on the floor show)
function Vol.SimColumnDigit(p_Shown)
	if p_Shown.t <= 0 then
		return 0
	end

	if p_Shown.b == 0 and p_Shown.t == 1 and (p_Shown.p or Vol.SIM_COLUMN_PARTS) < Vol.SIM_COLUMN_PARTS then
		return 1 + Vol.SIM_TOPS * Vol.NY * (Vol.NY + 1) // 2 + p_Shown.p - 1
	end

	return Vol.SimColumnCombo(p_Shown.b, p_Shown.t)
end

-- how many digits a number holds (under 2^31)
function Vol.SimColumnDigits()
	local s_C, s_D, s_P = Vol.SimColumnCombos(), 0, 1

	while s_P * s_C < 2147483648 do
		s_P, s_D = s_P * s_C, s_D + 1
	end

	return s_D
end

-- a column's digit: 0 empty; else its start p_B (layers) and top p_T (steps, over p_B's), counted start by start from the lowest
function Vol.SimColumnCombo(p_B, p_T)
	if p_T <= 0 then
		return 0
	end

	local s_S = Vol.SIM_TOPS
	local s_Before = 0

	for l_B = 0, p_B - 1 do
		s_Before = s_Before + (Vol.NY - l_B) * s_S
	end

	return 1 + s_Before + (p_T - p_B * s_S - 1)
end

-- where each column's smoke stands (layers from the grid's floor). Its pieces: each segment's stacked smoke from the segment's floor up
-- as far as it reaches; its hanging smoke from its lowest place's top (as full as it is) to its highest's bottom (one place alone:
-- round its middle). Pieces of a segment closer than Vol.SIM_COLUMN_GAP are one, and so are two across a floor between segments when
-- the lower reaches that floor and the upper stands on it (the floor hides the join); of what is left -- smoke on two floors, a ball
-- hanging high over smoke on the floor -- the column holds the piece on the floor nearest the camera's height (p_Room.simCamera; the
-- lowest without one), kept while it is no more than Vol.SIM_COLUMN_KEEP further than the nearest: through a floor the other piece is
-- out of sight
Vol.SIM_COLUMN_GAP = 0.67
Vol.SIM_COLUMN_KEEP = 0.5

function Vol.SimColumnSpans(p_Room)
	local s_Pieces = {}

	local function Take(p_Key, p_Lo, p_Hi, p_Seg, p_Stacked)
		local l_List = s_Pieces[p_Key] or {}
		s_Pieces[p_Key] = l_List
		l_List[#l_List + 1] = { lo = p_Lo, hi = p_Hi, seg = p_Seg, stacked = p_Stacked, bot = p_Seg.jbot, roof = p_Seg.jbot + #p_Seg.cells }
	end

	local s_Hung = {}

	for _, l_Cell in ipairs(p_Room.cells) do
		local l_Seg = l_Cell.seg

		if l_Seg ~= nil and l_Seg.cells[1] == l_Cell and (l_Seg.v or 0.0) > 0.02 then
			Take(Vol.Key(l_Cell.i, 0, l_Cell.k), l_Seg.jbot, l_Seg.jbot + math.min(l_Seg.v, #l_Seg.cells), l_Seg, true)
		end

		if l_Seg ~= nil and math.min(1.0, l_Cell.h or 0.0) > 0.02 then
			local l_Hung = s_Hung[l_Seg]

			if l_Hung == nil then
				s_Hung[l_Seg] = { lo = l_Cell, hi = l_Cell }
			else
				l_Hung.lo = l_Cell.j < l_Hung.lo.j and l_Cell or l_Hung.lo
				l_Hung.hi = l_Cell.j > l_Hung.hi.j and l_Cell or l_Hung.hi
			end
		end
	end

	for l_Seg, l_Hung in pairs(s_Hung) do
		local l_Lo, l_Hi = math.min(1.0, l_Hung.lo.h), math.min(1.0, l_Hung.hi.h)
		local l_Key = Vol.Key(l_Hung.lo.i, 0, l_Hung.lo.k)

		if l_Hung.lo == l_Hung.hi then
			Take(l_Key, l_Hung.lo.j + 0.5 - l_Lo * 0.5, l_Hung.lo.j + 0.5 + l_Lo * 0.5, l_Seg, false)
		else
			Take(l_Key, l_Hung.lo.j + 1.0 - l_Lo, l_Hung.hi.j + l_Hi, l_Seg, false)
		end
	end

	-- (a segment with no smoke at all in a column with smoke elsewhere: an empty piece on its floor, so that from its own floor -- a
	-- hall under the floor over it -- the column holds nothing rather than the smoke over that floor, whose bottom layer reaches down
	-- past it)
	for _, l_Cell in ipairs(p_Room.cells) do
		local l_Seg = l_Cell.seg
		local l_Key = Vol.Key(l_Cell.i, 0, l_Cell.k)

		if l_Seg ~= nil and l_Seg.cells[1] == l_Cell and s_Pieces[l_Key] ~= nil and (l_Seg.v or 0.0) <= 0.02 and s_Hung[l_Seg] == nil then
			Take(l_Key, l_Seg.jbot, l_Seg.jbot, l_Seg, true)
			s_Pieces[l_Key][#s_Pieces[l_Key]].empty = true
		end
	end

	local s_Camera = p_Room.simCamera ~= nil and (p_Room.simCamera.y - p_Room.floor.y) / p_Room.layer or nil
	local s_Kept = p_Room.colKept or {}
	p_Room.colKept = s_Kept
	local s_Spans = {}

	for l_Key, l_List in pairs(s_Pieces) do
		table.sort(l_List, function(p_A, p_B) return p_A.lo < p_B.lo end)
		local l_Merged = { l_List[1] }

		for l_I = 2, #l_List do
			local l_Last, l_Next = l_Merged[#l_Merged], l_List[l_I]
			local l_Floor = l_Last.seg ~= l_Next.seg and l_Last.hi >= l_Last.seg.jbot + #l_Last.seg.cells - 0.01
				and l_Next.stacked and l_Next.lo <= l_Next.seg.jbot + 0.01 and not l_Last.empty and not l_Next.empty

			if (l_Last.seg ~= l_Next.seg or l_Next.lo - l_Last.hi >= Vol.SIM_COLUMN_GAP) and not l_Floor then
				l_Merged[#l_Merged + 1] = l_Next
			elseif l_Last.empty then
				l_Merged[#l_Merged] = l_Next
			elseif not l_Next.empty then
				l_Merged[#l_Merged] = { lo = l_Last.lo, hi = math.max(l_Last.hi, l_Next.hi), seg = l_Next.seg, stacked = l_Next.stacked,
					bot = math.min(l_Last.bot, l_Next.bot), roof = math.max(l_Last.roof, l_Next.roof) }
			end
		end

		local l_Pick = l_Merged[1]

		if #l_Merged > 1 and s_Camera ~= nil then
			-- (how far the camera is from the floor (the segments) a piece is on)
			local function Far(p_Piece)
				return math.max(0.0, p_Piece.bot - s_Camera, s_Camera - p_Piece.roof)
			end

			local l_Was = nil

			for _, l_Piece in ipairs(l_Merged) do
				l_Pick = Far(l_Piece) < Far(l_Pick) and l_Piece or l_Pick

				if s_Kept[l_Key] ~= nil and s_Kept[l_Key] >= l_Piece.lo - 0.5 and s_Kept[l_Key] <= l_Piece.hi + 0.5 then
					l_Was = l_Piece
				end
			end

			if l_Was ~= nil and Far(l_Was) <= Far(l_Pick) + Vol.SIM_COLUMN_KEEP then
				l_Pick = l_Was
			end
		end

		s_Kept[l_Key] = (l_Pick.lo + l_Pick.hi) * 0.5

		if not l_Pick.empty then
			s_Spans[l_Key] = { lo = l_Pick.lo, hi = l_Pick.hi }
		end
	end

	return s_Spans
end

Vol.POWC = nil

function Vol.SimColumnWords(p_Room)
	local s_I0, s_K0 = Vol.SimCorner(p_Room)
	local s_S = Vol.SIM_TOPS
	local s_Shown = p_Room.colShown or {}
	p_Room.colShown = s_Shown
	local s_Slots = p_Room.colSlots or { list = {} }
	p_Room.colSlots = s_Slots

	-- (the smoke's time: its age as the frame gives it (p_Room.simNow), else a 60th of a second a time)
	local s_Now = p_Room.simNow or ((s_Slots.clock or 0.0) + 1.0 / 60.0)
	local s_Dt = math.max(0.0, s_Now - (s_Slots.clock or s_Now))
	s_Slots.clock = s_Now
	local s_Changed = s_Slots.words == nil or s_Slots.i0 ~= s_I0 or s_Slots.k0 ~= s_K0

	-- (the fading columns on by the time gone: one finished frees its slot, a column emptying emptied)
	local s_Live, s_Busy, s_Edges = {}, {}, 0

	for _, l_Slot in ipairs(s_Slots.list) do
		l_Slot.prog = l_Slot.prog + s_Dt / l_Slot.dur

		if l_Slot.prog >= 1.0 then
			-- (an emptying one emptied; one shown whole along the way, VOLUME.SIM_WAY, stays)
			if l_Slot.kind == 3 and not l_Slot.appear then
				l_Slot.shown.t, l_Slot.shown.p = 0, nil
				s_Changed = true
			end
		else
			s_Live[#s_Live + 1] = l_Slot
			s_Busy[l_Slot.key] = true
			s_Edges = s_Edges + (l_Slot.edge and 1 or 0)
		end
	end

	-- (everything shown as its smoke stands, at once, its fading slots let go: an M320 round's ball drawn sinking taken up by the
	-- simulation again, Vol.SimUnfreeze)
	if p_Room.colSyncAll then
		p_Room.colSyncAll, p_Room.colDue = nil, nil
		s_Live, s_Busy, s_Edges = {}, {}, 0
		Vol.SimColumnDue(p_Room, s_I0, s_K0, s_Busy, s_Now, true)
		p_Room.colSynced = 0
		s_Changed = true
	end

	-- (steps for the free slots: as often as the smoke's levels change -- a step of the simulation -- or while steps wait; none for an
	-- M320 round's ball drawn as it was, sinking: Vol.SimSink)
	if not p_Room.colFrozen and #s_Live < Vol.SIM_COLUMN_SLOTS
		and (s_Now - (s_Slots.due or -1.0) >= Vol.SIM_DT - 1e-6 or (p_Room.simBacklog or 0) > 0) then
		s_Slots.due = s_Now

		local l_Free = math.min(Vol.SIM_COLUMN_SLOTS - #s_Live, Vol.SIM_COLUMN_STAGGER)

		for _, l_Slot in ipairs(Vol.SimColumnSteps(p_Room, s_I0, s_K0, l_Free, s_Busy, s_Now, s_Edges)) do
			s_Live[#s_Live + 1] = l_Slot
		end

		-- (and the columns out of every front shown as their smoke stands, Vol.SimHidden)
		s_Changed = s_Changed or (p_Room.simTaken or 0) > 0 or (p_Room.colSynced or 0) > 0
		p_Room.colSynced = 0
	end

	-- (more steps waiting than Vol.SIM_COLUMN_BEHIND: the fading ones hurried to finish within Vol.SIM_COLUMN_HURRY s)
	if (p_Room.simBacklog or 0) > Vol.SIM_COLUMN_BEHIND then
		for _, l_Slot in ipairs(s_Live) do
			if (1.0 - l_Slot.prog) * l_Slot.dur > Vol.SIM_COLUMN_HURRY then
				l_Slot.dur = Vol.SIM_COLUMN_HURRY / (1.0 - l_Slot.prog)
			end
		end
	end

	s_Slots.list = s_Live
	s_Slots.busy = #s_Live > 0
	local s_Origin = Vec3(p_Room.floor.x + (s_I0 - 0.5) * ROOM_CELL, p_Room.floor.y, p_Room.floor.z + (s_K0 - 0.5) * ROOM_CELL)

	-- (the columns' numbers made again only when a column's step or the grid's corner changed)
	if s_Changed then
		-- (each place as drawn, for the box round the smoke, the front, the camera in it: 2 all of it in its column's smoke, 1 some, 0
		-- none)
		for _, l_Cell in ipairs(p_Room.cells) do
			local l_Shown = s_Shown[Vol.Key(l_Cell.i, 0, l_Cell.k)]
			local l_X, l_Z = l_Cell.i - s_I0, l_Cell.k - s_K0
			local l_Q = 0

			if l_Shown ~= nil and l_Shown.t > 0 and l_X >= 0 and l_X < Vol.NX and l_Z >= 0 and l_Z < Vol.NZ then
				local l_In = math.min(l_Cell.j + 1.0, l_Shown.t / s_S) - math.max(l_Cell.j, l_Shown.b)
				l_Q = l_In >= 0.99 and 2 or (l_In > 0.01 and 1 or 0)
			end

			l_Cell.q = l_Q
		end

		-- (each column's digit: column n = z * Vol.NX + x is digit n % D of number n // D)
		local s_C, s_D = Vol.SimColumnCombos(), Vol.SimColumnDigits()

		if Vol.POWC == nil or Vol.POWC.c ~= s_C then
			Vol.POWC = { c = s_C, [0] = 1 }

			for l_P = 1, s_D - 1 do
				Vol.POWC[l_P] = Vol.POWC[l_P - 1] * s_C
			end
		end

		local s_Cols = {}

		for l_W = 1, Vol.SIM_COLUMN_WORDS do
			s_Cols[l_W] = 0
		end

		for l_X = 0, Vol.NX - 1 do
			for l_Z = 0, Vol.NZ - 1 do
				local l_Shown = s_Shown[Vol.Key(s_I0 + l_X, 0, s_K0 + l_Z)]
				local l_N = l_Z * Vol.NX + l_X
				local l_W = l_N // s_D

				if l_Shown ~= nil and l_Shown.t > 0 and l_W < Vol.SIM_COLUMN_WORDS then
					s_Cols[l_W + 1] = s_Cols[l_W + 1] + Vol.SimColumnDigit(l_Shown) * Vol.POWC[l_N - l_W * s_D]
				end
			end
		end

		s_Slots.words, s_Slots.i0, s_Slots.k0 = s_Cols, s_I0, s_K0
	end

	-- (the slots: 14 bits each -- the column times 4 and how it changes (1 up a step, 2 down one, 3 emptying), times 16 and how far on
	-- it is in 15ths --, the first two in the 22nd number, the next two in the 23rd, the last two in the check number under its top 3
	-- bits, Vol.SimColumnCheck(); how it changes: 1 up a step or a part of a first step on the floor, 2 down one, 3 emptying)
	local s_Words = {}

	for l_W = 1, Vol.SIM_COLUMN_WORDS do
		s_Words[l_W] = s_Slots.words[l_W]
	end

	s_Words[Vol.SIM_COLUMN_WORDS + 1], s_Words[Vol.SIM_COLUMN_WORDS + 2] = 0, 0
	local s_Check, s_Slot = 0, 0

	for _, l_Slot in ipairs(s_Live) do
		local l_X, l_Z = l_Slot.i - s_I0, l_Slot.k - s_K0

		if l_X >= 0 and l_X < Vol.NX and l_Z >= 0 and l_Z < Vol.NZ and s_Slot < Vol.SIM_COLUMN_SLOTS then
			-- (shown whole along the way: the emptying fade from its end back, VOLUME.SIM_WAY)
			local l_Prog = l_Slot.appear and 1.0 - l_Slot.prog or l_Slot.prog
			local l_Bits = ((l_Z * Vol.NX + l_X) * 4 + l_Slot.kind) * 16 + math.max(0, math.min(15, math.floor(l_Prog * 15.0 + 0.5)))
			local l_Shift = s_Slot % 2 == 0 and 1 or 16384

			if s_Slot < 4 then
				local l_W = Vol.SIM_COLUMN_WORDS + 1 + s_Slot // 2
				s_Words[l_W] = s_Words[l_W] + l_Bits * l_Shift
			else
				s_Check = s_Check + l_Bits * l_Shift
			end

			s_Slot = s_Slot + 1
		end
	end

	p_Room.colCheck = Vol.SimColumnCheck() * 268435456 + s_Check
	return s_Origin, s_Words
end

-- the columns' numbers: the first 21 (Vol.NX * Vol.NZ over Vol.SimColumnDigits()); the slots in the 22nd and 23rd (and the check)
Vol.SIM_COLUMN_WORDS = 21

-- steps for up to p_Free columns not fading (p_Busy) (the grid's corner column p_I0, p_K0): each column's step as its smoke calls for
-- it, the most pressing first; a column's start moved at once (its top kept over it), else up one step, down one, or emptying (kept
-- until it has faded out); on the floor a part of its first step more or less (Vol.SIM_COLUMN_PARTS; its last part emptying). Each
-- one's slot, fading in over the time its column's smoke has been taking to move a step (or a part of one) (p_Room.colPace:
-- how fast its top has been moving, in steps a second) -- no longer than the slots can take all the columns wanting a step within
-- Vol.SIM_COLUMN_SERVE s --, at once (Vol.SIM_COLUMN_FADE) when it is more than a step behind. The columns' steps worked out again
-- only once the simulation has stepped (Vol.SIM_DT) or the grid's corner moved; in between the ones left are handed out as slots free
function Vol.SimColumnSteps(p_Room, p_I0, p_K0, p_Free, p_Busy, p_Now, p_Edges)
	local s_S = Vol.SIM_TOPS
	local s_Pace = p_Room.colPace or {}
	p_Room.colPace = s_Pace
	local s_Was = p_Room.colDue

	if s_Was == nil or p_Now - s_Was.t >= Vol.SIM_DT - 1e-6 or s_Was.i0 ~= p_I0 or s_Was.k0 ~= p_K0 then
		s_Was = { t = p_Now, i0 = p_I0, k0 = p_K0, list = Vol.SimColumnDue(p_Room, p_I0, p_K0, p_Busy, p_Now) }
		s_Was.turn = Vol.SIM_COLUMN_SLOTS * Vol.SIM_COLUMN_SERVE / math.max(#s_Was.list, 1)
		p_Room.colDue = s_Was
	end

	local s_Due = s_Was.list
	local s_Turn = s_Was.turn

	-- (a step a column: its start moved at once, its top kept over it; else up one, down one, started, emptying -- a slot each, fading
	-- no longer than lets the slots take all those wanting one within Vol.SIM_COLUMN_SERVE s)
	local s_List, s_Changed, s_Left = {}, 0, {}
	local s_Edges = p_Edges or 0

	for _, l_Due in ipairs(s_Due) do
		if #s_List >= p_Free or p_Busy[l_Due.key] then
			s_Left[#s_Left + 1] = l_Due
		else
			local l_Shown = l_Due.shown
			local l_Kind = 0
			local l_Appear = false

			if l_Due.step == 4 then
				-- (behind a wall, the front along its way there now: shown whole as its smoke stands, fading in -- its smoke weighed from
				-- none, the shader's emptying fade run backwards -- VOLUME.SIM_WAY)
				Vol.SimColumnSync(l_Shown, l_Due.start, l_Due.want)

				if l_Shown.t > 0 then
					l_Kind, l_Appear = 3, true
					p_Room.colHeld[l_Due.key] = nil
				end
			elseif l_Due.step == 2 then
				l_Shown.b = l_Due.b
				l_Shown.t = math.max(l_Shown.t, l_Shown.b * s_S + 1)
				l_Shown.p = nil
			elseif l_Due.step == 3 then
				-- (a part more of a first step on the floor: the first from none)
				if l_Shown.t == 0 then
					l_Shown.b, l_Shown.t, l_Shown.p = 0, 1, 1
				else
					l_Shown.p = math.min(Vol.SIM_COLUMN_PARTS, (l_Shown.p or Vol.SIM_COLUMN_PARTS) + 1)
				end

				l_Kind = 1
			elseif l_Due.step == -3 then
				-- (a part less; the last one emptying, kept until it has faded out)
				if (l_Shown.p or Vol.SIM_COLUMN_PARTS) <= 1 then
					l_Kind = 3
				else
					l_Shown.p, l_Kind = (l_Shown.p or Vol.SIM_COLUMN_PARTS) - 1, 2
				end
			elseif l_Shown.t == 0 then
				l_Shown.b, l_Shown.t, l_Kind = l_Due.b, l_Due.b * s_S + 1, 1
			elseif l_Due.step < 0 and l_Shown.t <= l_Shown.b * s_S + 1 then
				l_Kind = 3
			else
				l_Shown.t, l_Kind = l_Shown.t + l_Due.step, l_Due.step > 0 and 1 or 2
			end

			if l_Kind > 0 then
				-- (the smoke's edge -- a column starting to hold smoke, emptying -- at its own pace, Vol.SIM_COLUMN_EDGES at once; any other
				-- step taking its turn)
				local l_Edge = (l_Kind == 1 and l_Shown.t == l_Shown.b * s_S + 1 or l_Kind == 3 or l_Due.step == -3) and s_Edges < Vol.SIM_COLUMN_EDGES
				-- (over the time its smoke takes to get that far: a step, or a part of one)
				local l_Far = (l_Due.step == 3 or l_Due.step == -3) and (0.5 + Vol.SIM_COLUMN_HOLD) / Vol.SIM_COLUMN_PARTS or 1.0
				local l_Dur = math.min(Vol.SIM_COLUMN_FADE_MOST, 0.9 * l_Far / math.max(s_Pace[l_Due.key].v, 1e-3))
				l_Dur = l_Due.push > 1.0 and Vol.SIM_COLUMN_FADE or math.max(Vol.SIM_COLUMN_FADE, l_Edge and l_Dur or math.min(l_Dur, s_Turn))

				-- (shown whole along the way: over the time the front takes to cross a place)
				if l_Appear then
					l_Edge, l_Dur = false, ROOM_CELL / Vol.FrontSpeed(p_Room)
				end

				s_Edges = s_Edges + (l_Edge and 1 or 0)
				s_List[#s_List + 1] = { shown = l_Shown, kind = l_Kind, i = l_Due.i, k = l_Due.k, key = l_Due.key, prog = 0.0, dur = l_Dur,
					edge = l_Edge, appear = l_Appear }
			end

			s_Changed = s_Changed + 1
		end
	end

	s_Was.list = s_Left
	p_Room.simBacklog = #s_Left
	p_Room.simTaken = s_Changed
	return s_List
end

-- whether nothing of column p_I, p_K shows yet: its nearest point along the floor further from every front's middle than the front
-- has grown (the front counts height too: further still)
function Vol.SimHidden(p_Room, p_I, p_K)
	local s_X, s_Z = p_Room.floor.x + p_I * ROOM_CELL, p_Room.floor.z + p_K * ROOM_CELL
	local s_Half = ROOM_CELL * 0.5

	local function Out(p_M, p_R)
		local l_DX = math.max(0.0, math.abs(s_X - p_M.x) - s_Half)
		local l_DZ = math.max(0.0, math.abs(s_Z - p_M.z) - s_Half)
		return l_DX * l_DX + l_DZ * l_DZ > p_R * p_R
	end

	-- (split from the second's, Vol.SimFrontSplit: the first front not counted for a column wholly on the second's side)
	local s_M = Vol.FrontAt(p_Room)
	local s_Side = Vol.FrontSide(p_Room, Vec3(s_X, 0.0, s_Z))
	local s_Out1 = Out(s_M, p_Room.simFront or 0.0) or (p_Room.frontSplit and s_Side <= 0.0
		and Vol.FrontSide(p_Room, Vec3(s_X + s_Half, 0.0, s_Z + s_Half)) <= 0.0 and Vol.FrontSide(p_Room, Vec3(s_X - s_Half, 0.0, s_Z - s_Half)) <= 0.0
		and Vol.FrontSide(p_Room, Vec3(s_X + s_Half, 0.0, s_Z - s_Half)) <= 0.0 and Vol.FrontSide(p_Room, Vec3(s_X - s_Half, 0.0, s_Z + s_Half)) <= 0.0)
	return s_Out1 and (p_Room.mouth2 == nil or Out(p_Room.mouth2, p_Room.simFront2 or 0.0))
end

-- a column shown as its smoke stands, at once (p_B its start, p_WantT its top in steps): its start, its top the nearest step (on the
-- floor, its first step's parts as far as its smoke has got; none under the first). True if that changed it
function Vol.SimColumnSync(p_Shown, p_B, p_WantT)
	local s_S, s_Parts = Vol.SIM_TOPS, Vol.SIM_COLUMN_PARTS
	local s_U = (0.5 + Vol.SIM_COLUMN_HOLD) / s_Parts
	local s_B, s_T, s_P = p_B, 0, nil

	if p_B == 0 and s_Parts > 1 and p_WantT < 0.5 + Vol.SIM_COLUMN_HOLD then
		local l_P = math.max(0, math.min(s_Parts, math.floor(p_WantT / s_U)))
		s_T, s_P = l_P > 0 and 1 or 0, l_P > 0 and l_P or nil
	elseif p_WantT - p_B * s_S > 0.5 then
		s_T = math.max(p_B * s_S + 1, math.min(Vol.NY * s_S, math.floor(p_WantT + 0.5)))
	end

	if s_P == s_Parts then
		s_P = nil
	end

	if s_T == p_Shown.t and (s_T == 0 or (s_B == p_Shown.b and s_P == p_Shown.p)) then
		return false
	end

	p_Shown.b, p_Shown.t, p_Shown.p = s_T > 0 and s_B or p_Shown.b, s_T, s_P
	return true
end

-- every column of the grid (its corner column p_I0, p_K0) that calls for a step, not fading (p_Busy), the most pressing first: the
-- step and how pressing it is; and how fast each column's top has been moving (p_Room.colPace). A column out of every front is
-- shown as its smoke stands at once (Vol.SimHidden): none of it shows
function Vol.SimColumnDue(p_Room, p_I0, p_K0, p_Busy, p_Now, p_All)
	local s_S, s_NY = Vol.SIM_TOPS, Vol.NY
	local s_Hold = Vol.SIM_COLUMN_HOLD
	local s_Parts = Vol.SIM_COLUMN_PARTS
	local s_U = (0.5 + s_Hold) / s_Parts
	local s_Spans = Vol.SimColumnSpans(p_Room)
	local s_Shown = p_Room.colShown
	local s_Pace = p_Room.colPace
	local s_Held = p_Room.colHeld or {}
	p_Room.colHeld = s_Held
	local s_Due = {}

	-- (each column of the grid: the step it calls for and how pressing that is; how fast its top has been moving)
	for l_X = 0, Vol.NX - 1 do
		for l_Z = 0, Vol.NZ - 1 do
			local l_Key = Vol.Key(p_I0 + l_X, 0, p_K0 + l_Z)
			local l_Span = s_Spans[l_Key]
			local l_Shown = s_Shown[l_Key] or { b = 0, t = 0 }
			s_Shown[l_Key] = l_Shown
			local l_B, l_T = l_Shown.b, l_Shown.t
			local l_WantB, l_WantT = l_B, 0.0

			if l_Span ~= nil then
				local l_Lo = math.max(0.0, math.min(s_NY - 1.0 / s_S, l_Span.lo))
				local l_Hi = math.max(l_Lo, math.min(s_NY, l_Span.hi))

				-- (its start: the nearest whole layer, held)
				if l_T == 0 or math.abs(l_Lo - l_B) > 0.5 + s_Hold / s_S then
					l_WantB = math.max(0, math.min(s_NY - 1, math.floor(l_Lo + 0.5)))
				end

				l_WantT = l_Hi * s_S
			end

			-- (behind a wall, the front along its way not there yet: kept empty -- never one shown --; once it is, shown whole, fading in:
			-- VOLUME.SIM_WAY, Vol.SimWayHeld)
			local l_Start = l_Span ~= nil and math.max(0, math.min(s_NY - 1, math.floor(l_Span.lo + 0.5))) or 0
			local l_Held = l_Span ~= nil and (l_T == 0 or s_Held[l_Key]) and Vol.SimWayHeld(p_Room, l_Key)
			local l_Appear = false

			if l_Held then
				s_Held[l_Key], l_WantT = true, 0.0
			elseif s_Held[l_Key] then
				l_Appear = l_T == 0 and l_WantT > 0.0

				if l_T > 0 or l_Span == nil then
					s_Held[l_Key] = nil
				end
			end

			local l_Pace = s_Pace[l_Key]

			if l_Pace == nil then
				s_Pace[l_Key] = { t = p_Now, w = l_WantT, v = 0.0 }
			elseif p_Now - l_Pace.t > 1e-6 then
				l_Pace.v = 0.6 * l_Pace.v + 0.4 * math.abs(l_WantT - l_Pace.w) / (p_Now - l_Pace.t)
				l_Pace.t, l_Pace.w = p_Now, l_WantT
			end

			local l_Push = 0.0
			local l_Step = 0
			-- (on the grid's floor, empty or showing its first step: a part of it at a time, Vol.SIM_COLUMN_PARTS -- its parts a part of
			-- the way to the step each, back down 0.6 of a part under it)
			local l_P = l_T == 0 and 0 or ((l_B == 0 and l_T == 1) and (l_Shown.p or s_Parts) or s_Parts)
			local l_Floor = s_Parts > 1 and l_WantB == 0 and (l_T == 0 or (l_B == 0 and l_T == 1))
				and (l_P < s_Parts or l_WantT < l_T + 0.5 + s_Hold)

			if not p_Busy[l_Key] and (p_All or Vol.SimHidden(p_Room, p_I0 + l_X, p_K0 + l_Z)) then
				-- (out of every front: nothing of it shows yet -- shown as its smoke stands at once, no slot: when a front gets to it, it
				-- is there already, the front alone moving)
				if Vol.SimColumnSync(l_Shown, l_Start, l_WantT) then
					p_Room.colSynced = (p_Room.colSynced or 0) + 1
				end

				if not l_Held and l_Shown.t > 0 then
					s_Held[l_Key] = nil
				end
			elseif p_Busy[l_Key] then
				l_Step = 0
			elseif l_Appear then
				-- (the nearer along the way the sooner)
				l_Push, l_Step = 100.0 + math.max(0.0, 100.0 - p_Room.colWay[l_Key].path), 4
			elseif l_WantB ~= l_B and l_T > 0 then
				l_Push, l_Step = 1.0 + math.abs(l_WantB - l_B), 2
			elseif l_Floor and l_P < s_Parts and l_WantT > (l_P + 1) * s_U then
				l_Push, l_Step = l_WantT - (l_P + 1) * s_U, 3
			elseif l_Floor and l_P > 0 and l_WantT < (l_P - 0.6) * s_U then
				l_Push, l_Step = (l_P - 0.6) * s_U - l_WantT, -3
			elseif l_Floor then
				l_Step = 0
			elseif l_T == 0 then
				if l_WantT - l_WantB * s_S > 0.5 + s_Hold then
					l_Push, l_Step = l_WantT - l_WantB * s_S - 0.5, 1
				end
			elseif l_WantT > l_T + 0.5 + s_Hold and l_T < s_NY * s_S then
				l_Push, l_Step = l_WantT - l_T - 0.5, 1
			elseif l_WantT < l_T - 0.5 - s_Hold then
				l_Push, l_Step = l_T - 0.5 - l_WantT, -1
			end

			if l_Step ~= 0 then
				s_Due[#s_Due + 1] = { shown = l_Shown, b = l_WantB, step = l_Step, push = l_Push, i = p_I0 + l_X, k = p_K0 + l_Z, key = l_Key,
					start = l_Start, want = l_WantT }
			end
		end
	end

	table.sort(s_Due, function(p_A, p_B) return p_A.push > p_B.push end)
	return s_Due
end

-- The room drawn filling over time (VOLUME.SIM): one plain box round its places (each cut to the walls, Vol.Box), half a place
-- further out on a side nothing cut (the smoke's soft edge past its last places), never under its floor nor over its ceiling -- no
-- plan of boxes, no main box --, the grid's numbers written by Vol.SimFrame from the simulation each frame something changed.
Vol.SIM_STEPS = 2   -- at most this many steps of the simulation a frame (a long frame catches up over the next ones)
-- (VOLUME.SIM_AHEAD) a canister's room measured: simulated on ahead, this many steps a frame within this many milliseconds of it,
-- until all its smoke has poured out and Vol.SIM_SETTLE s more (an M320 round's ball joined to it: Vol.SIM_SETTLE_BALL s from then)
Vol.SIM_AHEAD_STEPS = 3
Vol.SIM_AHEAD_MS = 1.5
Vol.SIM_SETTLE = 2.0
Vol.SIM_SETTLE_BALL = 8.0

-- (VOLUME.SIM_AHEAD) how far on (the simulation's own time) a canister's room has to be simulated for its smoke to have ended up
-- where it stays: its own pouring done, every canister's poured into it (VOLUME.MERGE), and settled
function Vol.SimEnd(p_Room)
	local s_Sim = p_Room.sim
	local s_End = SMOKE_SECONDS

	for _, l_Pour in ipairs(s_Sim.pours or {}) do
		s_End = math.max(s_End, l_Pour.from + SMOKE_SECONDS)
	end

	return math.max(s_End + Vol.SIM_SETTLE, s_Sim.settleTo or 0.0)
end

-- (VOLUME.SIM_AHEAD) how far an M320 round's ball drawn as it was once its place was measured may sink: until its lowest smoke drawn
-- rests on the grid's floor (the floor under it, or with none, M320_HANG under where it hit) -- its columns' lowest start (m)
function Vol.SimSinkMost(p_Room)
	local s_Low = nil

	for _, l_Shown in pairs(p_Room.colShown or {}) do
		if l_Shown.t > 0 then
			s_Low = math.min(s_Low or l_Shown.b, l_Shown.b)
		end
	end

	return (s_Low or 0) * p_Room.layer
end

-- a frame of an M320 round's room (VOLUME.SIM_AHEAD): once its place is measured, its ball drawn as it is then -- its columns no
-- longer stepped, p_Room.colFrozen -- sinking evenly until its lowest smoke rests on the grid's floor (not once a canister has poured
-- into it, nor while it is being shown again as it stands). How far down it is drawn now (m)
function Vol.SimSinkFrame(p_Room, p_Age)
	if VOLUME.SIM_AHEAD and p_Room.hit ~= nil and not p_Room.merged and p_Room.done and p_Room.sinkFrom == nil
		and not p_Room.colSyncAll then
		p_Room.sinkFrom, p_Room.sinkMost, p_Room.colFrozen = p_Age, Vol.SimSinkMost(p_Room), true
	end

	return Vol.SimSink(p_Room, p_Age)
end

-- how far down the ball is drawn p_Age s into its life: evenly at VOLUME.SIM_SINK, to where it rests (0: not sinking)
function Vol.SimSink(p_Room, p_Age)
	if p_Room.sinkFrom == nil then
		return 0.0
	end

	return math.max(0.0, math.min(p_Room.sinkMost or 0.0, VOLUME.SIM_SINK * (p_Age - p_Room.sinkFrom)))
end

-- a frame's steps of the room's simulation, its smoke p_Age s old (p_Clock: the wall clock when the frame began, ms; nil: none): on
-- to its age, Vol.SIM_STEPS at most; a canister's measured (VOLUME.SIM_AHEAD) on ahead to Vol.SimEnd, Vol.SIM_AHEAD_STEPS at most
-- within Vol.SIM_AHEAD_MS, and no further -- from then on what is drawn stays, its front showing it (p_Room.settledAt: when). How many
function Vol.SimAdvance(p_Room, p_Age, p_Clock)
	local s_Sim = p_Room.sim
	local s_Want = p_Age - (p_Room.simFrom or 0.0)
	local s_Most, s_Until = Vol.SIM_STEPS, nil
	local s_Steps = 0

	if VOLUME.SIM_AHEAD and (p_Room.hit == nil or p_Room.merged ~= nil) and (p_Room.done or p_Room.aheadFrom ~= nil) then
		p_Room.aheadFrom = p_Room.aheadFrom or p_Age

		if p_Room.done then
			s_Want, s_Most = Vol.SimEnd(p_Room), Vol.SIM_AHEAD_STEPS
			s_Until = p_Clock ~= nil and p_Clock + Vol.SIM_AHEAD_MS or nil
		else
			-- (measured on for a smoke poured into it, Vol.SimMergeInto: on at the smoke's own pace from then -- ahead before the places
			-- it spreads to are measured, it would pile up short of them -- and ahead once they are)
			local l_From = p_Room.stepFrom
			s_Want = l_From ~= nil and l_From.t + math.max(0.0, p_Age - l_From.age) or s_Sim.t
		end
	end

	while s_Sim.t + Vol.SIM_DT <= s_Want + 1e-6 and s_Steps < s_Most
		and (s_Until == nil or s_Steps < Vol.SIM_STEPS or (Vol.Clock() or 0.0) < s_Until) do
		Vol.SimStep(p_Room, Vol.SIM_DT)
		s_Steps = s_Steps + 1
	end

	if p_Room.aheadFrom ~= nil and p_Room.done and s_Sim.t + Vol.SIM_DT > s_Want + 1e-6 then
		p_Room.settledAt = p_Room.settledAt or p_Age
	else
		p_Room.settledAt = nil
	end

	return s_Steps
end

-- the room's places' boxes and the box round them
function Vol.SimPlaces(p_Room)
	local function Has(p_I, p_J, p_K)
		return p_Room.cellAt ~= nil and p_Room.cellAt[Vol.Key(p_I, p_J, p_K)] ~= nil
	end

	local s_Boxes = {}
	local s_Bound = { x0 = math.huge, y0 = math.huge, z0 = math.huge, x1 = -math.huge, y1 = -math.huge, z1 = -math.huge }

	for _, l_Cell in ipairs(p_Room.cells) do
		local l_Box = Vol.Box(p_Room, l_Cell, Has)
		s_Boxes[#s_Boxes + 1] = l_Box
		s_Bound.x0, s_Bound.y0, s_Bound.z0 = math.min(s_Bound.x0, l_Box.x0), math.min(s_Bound.y0, l_Box.y0), math.min(s_Bound.z0, l_Box.z0)
		s_Bound.x1, s_Bound.y1, s_Bound.z1 = math.max(s_Bound.x1, l_Box.x1), math.max(s_Bound.y1, l_Box.y1), math.max(s_Bound.z1, l_Box.z1)
	end

	-- (across only: under the floor and over the ceiling it never goes)
	for _, l_Side in ipairs(Vol.BOUND_SIDES) do
		if l_Side[1]:sub(1, 1) ~= "y" then
			for _, l_Box in ipairs(s_Boxes) do
				if math.abs(l_Box[l_Side[1]] - s_Bound[l_Side[1]]) < 0.001 and not l_Box.cut[l_Side[2]] then
					s_Bound[l_Side[1]] = s_Bound[l_Side[1]] + l_Side[3] * ROOM_CELL * 0.5
					break
				end
			end
		end
	end

	return s_Boxes, s_Bound
end

-- the box drawn: round the places whose smoke is drawn (their step not empty), half a place out on every side and half a layer up and
-- down (its soft edge, the churn), never past the box round all the places (p_All, on the room's walls): the view is marched only where
-- smoke may be, the box growing as the smoke spreads (nil: none drawn yet)
function Vol.SimBound(p_Boxes, p_All, p_Layer)
	local s_B = nil

	-- (and the first place's, where the front grows from; a second canister's poured in, where its own does, VOLUME.MERGE)
	for l_Index, l_Box in ipairs(p_Boxes) do
		if (l_Box.cell.q or 0) > 0 or l_Index == 1 or l_Box.cell.poured then
			if s_B == nil then
				s_B = { x0 = l_Box.x0, y0 = l_Box.y0, z0 = l_Box.z0, x1 = l_Box.x1, y1 = l_Box.y1, z1 = l_Box.z1 }
			else
				s_B.x0, s_B.y0, s_B.z0 = math.min(s_B.x0, l_Box.x0), math.min(s_B.y0, l_Box.y0), math.min(s_B.z0, l_Box.z0)
				s_B.x1, s_B.y1, s_B.z1 = math.max(s_B.x1, l_Box.x1), math.max(s_B.y1, l_Box.y1), math.max(s_B.z1, l_Box.z1)
			end
		end
	end

	if s_B == nil then
		return nil
	end

	local s_H, s_V = ROOM_CELL * 0.5, p_Layer * 0.5
	return { x0 = math.max(p_All.x0, s_B.x0 - s_H), y0 = math.max(p_All.y0, s_B.y0 - s_V), z0 = math.max(p_All.z0, s_B.z0 - s_H),
		x1 = math.min(p_All.x1, s_B.x1 + s_H), y1 = math.min(p_All.y1, s_B.y1 + s_V), z1 = math.min(p_All.z1, s_B.z1 + s_H) }
end

-- the front the room's smoke is drawn within (the shader thins it out over its last Vol.FRONT): grown from its middle (the canister's
-- mouth, where the round hit) towards as far as its places with smoke reach (as the front counts how far: Vol.FrontDistance), a cell
-- further, at VOLUME.SIM_FRONT_CANISTER a second at most (an M320 round's: SIM_FRONT), never back: a place the simulation fills is
-- seen as the front gets to it, the smoke coming in smoothly instead of a place at a time. A second canister poured in (VOLUME.MERGE)
-- has a front of its own, round its mouth, grown as the first's from when it went off: its smoke seen spreading out of it as the
-- first's is, the first's going on as it was. How far each has grown (m; the second's 0 with none)
function Vol.SimFront(p_Room, p_Dt)
	local s_M, s_M2 = Vol.FrontAt(p_Room), p_Room.mouth2
	local s_Tall = Vol.Tall()
	local s_Far, s_Far2 = 0.0, 0.0

	for _, l_Cell in ipairs(p_Room.cells) do
		if (l_Cell.q or 0) > 0 then
			local l_X = p_Room.floor.x + l_Cell.i * ROOM_CELL
			local l_Y = p_Room.floor.y + p_Room.layer * (0.5 + l_Cell.j)
			local l_Z = p_Room.floor.z + l_Cell.k * ROOM_CELL
			s_Far = math.max(s_Far, (l_X - s_M.x) ^ 2 + ((l_Y - s_M.y) * s_Tall) ^ 2 + (l_Z - s_M.z) ^ 2)

			if s_M2 ~= nil then
				s_Far2 = math.max(s_Far2, (l_X - s_M2.x) ^ 2 + ((l_Y - s_M2.y) * s_Tall) ^ 2 + (l_Z - s_M2.z) ^ 2)
			end
		end
	end

	local s_Ahead = Vol.SIM_FRONT_AHEAD or (ROOM_CELL + Vol.FRONT)
	local s_Speed = (p_Room.hit ~= nil and VOLUME.SIM_FRONT or VOLUME.SIM_FRONT_CANISTER or VOLUME.SIM_FRONT or 3.0) * p_Dt
	local s_Sim = p_Room.sim
	-- (VOLUME.SIM_PACE: at the simulated smoke's own pace, as far along its way as it had got by the smoke's age, Vol.SimPaceAt)
	local s_Pace = VOLUME.SIM_PACE and s_Sim ~= nil
	local s_T = (p_Room.simNow or 0.0) - (p_Room.simFrom or 0.0)
	local s_Most = p_Room.hit ~= nil and (VOLUME.SIM_FRONT or 3.0) or (VOLUME.SIM_PACE_MOST or 4.0)

	-- (a canister's simulated on ahead, VOLUME.SIM_AHEAD: nothing shown until its smoke has been simulated on to where it ends up --
	-- a column shown before would go on changing, a column at a time --, its fronts from then at the pace it spread at, from its
	-- start: p_Room.paceFrom)
	if s_Pace and VOLUME.SIM_AHEAD and p_Room.hit == nil and p_Room.paceFrom == nil then
		if p_Room.settledAt == nil then
			return p_Room.simFront or 0.0, p_Room.simFront2 or 0.0
		end

		p_Room.paceFrom = s_T
	end

	-- (held to p_Room.front1Cap once another smoke has come into the room with a front of its own, Vol.SimSecondFront; at the
	-- simulated smoke's pace, nowhere before its first step)
	if s_Pace then
		local l_R = s_Sim.pace ~= nil and Vol.SimPaceAt(s_Sim.pace[1], 0.0, s_T - (p_Room.paceFrom or 0.0)) or 0.0
		p_Room.simFront, p_Room.paceV = Vol.PaceChase(p_Room.simFront or 0.0, p_Room.paceV, math.min(math.sqrt(s_Far) + s_Ahead,
			l_R + s_Ahead, p_Room.front1Cap or math.huge), s_Most, p_Dt)
		-- (and along the smoke's way, as fast: the columns behind a wall shown as it gets to them, VOLUME.SIM_WAY)
		p_Room.wayFront, p_Room.paceW = Vol.PaceChase(p_Room.wayFront or 0.0, p_Room.paceW, l_R, s_Most, p_Dt)
	else
		p_Room.simFront = math.max(p_Room.simFront or 0.0, math.min(math.sqrt(s_Far) + s_Ahead, (p_Room.simFront or 0.0) + s_Speed,
			p_Room.front1Cap or math.huge))
		p_Room.wayFront = (p_Room.wayFront or 0.0) + s_Speed
	end

	-- (a second canister's poured in, its own places' pace from when it poured in -- simulated on ahead, from once the room's smoke
	-- has been simulated on to where it ends up again --; an M320 round's joining it, as before)
	if s_M2 ~= nil and s_Pace and s_Sim.pace ~= nil and #s_Sim.pace[2] > 0 and VOLUME.SIM_AHEAD and p_Room.pace2Go == nil then
		p_Room.pace2Go = p_Room.settledAt ~= nil and s_T or nil
	end

	if s_M2 ~= nil and s_Pace and s_Sim.pace ~= nil and #s_Sim.pace[2] > 0 and VOLUME.SIM_AHEAD and p_Room.pace2Go == nil then
		-- (waiting)
		p_Room.simFront2 = p_Room.simFront2 or 0.0
	elseif s_M2 ~= nil and s_Pace and s_Sim.pace ~= nil and #s_Sim.pace[2] > 0 then
		local l_R2 = Vol.SimPaceAt(s_Sim.pace[2], s_Sim.pace2From or 0.0, (s_Sim.pace2From or 0.0) + s_T - (p_Room.pace2Go or s_T))
		p_Room.simFront2, p_Room.paceV2 = Vol.PaceChase(p_Room.simFront2 or 0.0, p_Room.paceV2,
			math.min(math.sqrt(s_Far2) + s_Ahead, l_R2 + s_Ahead), s_Most, p_Dt)
		p_Room.wayFront2, p_Room.paceW2 = Vol.PaceChase(p_Room.wayFront2 or 0.0, p_Room.paceW2, l_R2, s_Most, p_Dt)
	elseif s_M2 ~= nil then
		p_Room.simFront2 = math.max(p_Room.simFront2 or 0.0, math.min(math.sqrt(s_Far2) + s_Ahead, (p_Room.simFront2 or 0.0) + s_Speed))
		p_Room.wayFront2 = (p_Room.wayFront2 or 0.0) + s_Speed
	end

	return p_Room.simFront, p_Room.simFront2 or 0.0
end

-- the box's matrix for the room filling over time (kind 3; Vol.Raw): the front's middle (8 bits an axis across the box), a ceiling
-- over the grid (bit 18: its top layer reads on up), a floor under it (bit 19: its first layer reads on down -- not under an M320
-- round's smoke hanging) and the grid's numbers as columns (bit 20, VOLUME.SIM_COLUMNS); how far the front has grown (centimetres).
-- A second canister's front (VOLUME.MERGE) in the bits left: its middle 7 bits across the box along x (bits 8-14 of the second number)
-- and z (15-21), as high as the first's; how far it has grown in Vol.FRONT2_STEP, 12 bits (its lowest in bit 22 of the second number,
-- the next 9 over the first front's 14 in the third, the top 2 in bits 21-22 of the first); 0: none. With none, the sides drawing in
-- while the smoke gives way (p_Faces, VOLUME.RECEDE) in the x field's low 4 bits: 1 the box's low x side, 2 its high one, 4 low z, 8
-- high z (the shader thins the columns out over a place in from each)
Vol.FRONT2_STEP = 0.025
Vol.FACE_BITS = { x0 = 1, x1 = 2, z0 = 4, z1 = 8 }
Vol.FACE_SIDES = { "x0", "x1", "z0", "z1" }

function Vol.SimTransform(p_Box, p_Room, p_Sink, p_Faces)
	local s_Size = Vol.Size(p_Box)
	-- (the fronts' middles as low as the M320 round's ball is drawn sinking, Vol.SimSink)
	local s_Down = Vec3(0.0, p_Sink or 0.0, 0.0)
	local s_M, s_M2 = Vol.FrontAt(p_Room) - s_Down, p_Room.mouth2 ~= nil and p_Room.mouth2 - s_Down or nil

	local function Across(p_V, p_Lo, p_Span, p_Most)
		return math.max(0, math.min(p_Most or 255, math.floor((p_V - p_Lo) / math.max(p_Span, 0.001) * (p_Most or 255) + 0.5)))
	end

	local s_Flags = (p_Room.outside and 0 or 1) + (p_Room.hangs and 0 or 2) + (VOLUME.SIM_COLUMNS and 4 or 0)
	local s_X2, s_Z2, s_R2 = 0, 0, 0

	-- (split from the first, Vol.SimFrontSplit: a step at least from the first frame -- the shader takes the split's plane from its middle)
	if s_M2 ~= nil then
		s_R2 = math.max(p_Room.frontSplit and 1 or 0, math.min(4095, math.floor((p_Room.simFront2 or 0.0) / Vol.FRONT2_STEP + 0.5)))
	end

	-- (its middle only while it has grown: with none grown the field is the sides' drawing in, none)
	if s_R2 > 0 then
		s_X2, s_Z2 = Across(s_M2.x, p_Box.x0, s_Size.x, 127), Across(s_M2.z, p_Box.z0, s_Size.z, 127)
	elseif p_Faces ~= nil then
		for l_Side, l_Bit in pairs(Vol.FACE_BITS) do
			s_X2 = s_X2 + (p_Faces[l_Side] ~= nil and l_Bit or 0)
		end
	end

	return Vol.Raw(s_Size, Vol.Middle(p_Box),
		Vol.Pack(3 + 4 * Across(s_M.x, p_Box.x0, s_Size.x) + 1024 * Across(s_M.y, p_Box.y0, s_Size.y) + 262144 * s_Flags
			+ 2097152 * (s_R2 // 1024)),
		Vol.Pack(Across(s_M.z, p_Box.z0, s_Size.z) + 256 * s_X2 + 32768 * s_Z2 + 4194304 * (s_R2 % 2)),
		-- (split from the second's, Vol.SimFrontSplit: 81.92 m more -- no front grows that far)
		Vol.Pack(Vol.FrontField(p_Room) + 16384 * ((s_R2 // 2) % 512)))
end

-- how far the room's front has grown as the box's matrix holds it (centimetres, 14 bits): split from the second's (Vol.SimFrontSplit)
-- 8192 more, under it no more than 81.91 m
function Vol.FrontField(p_Room)
	local s_Cm = math.max(0, math.floor((p_Room.simFront or 0.0) * 100.0 + 0.5))
	return (p_Room.frontSplit and p_Room.mouth2 ~= nil) and 8192 + math.min(8191, s_Cm) or math.min(16383, s_Cm)
end

-- whether p_At (the camera) is in one of the places' boxes whose smoke is drawn (its step not empty) and sees its place (p_Any: any of
-- its places, smoke or not)
function Vol.SimInside(p_Boxes, p_At, p_Any)
	for _, l_Box in ipairs(p_Boxes) do
		if p_At.x > l_Box.x0 + 0.01 and p_At.x < l_Box.x1 - 0.01 and p_At.y > l_Box.y0 + 0.01 and p_At.y < l_Box.y1 - 0.01
			and p_At.z > l_Box.z0 + 0.01 and p_At.z < l_Box.z1 - 0.01 then
			return (p_Any or (l_Box.cell.q or 0) > 0) and Vol.Sees(l_Box.cell, p_At)
		end
	end

	return false
end

-- whether p_At is in box p_B
function Vol.InBox(p_B, p_At)
	return p_B ~= nil and p_At.x >= p_B.x0 and p_At.x <= p_B.x1 and p_At.y >= p_B.y0 and p_At.y <= p_B.y1 and p_At.z >= p_B.z0
		and p_At.z <= p_B.z1
end

-- whether the sides drawing in (Vol.RecedeFrame's) moved a centimetre or more, or began or ended
function Vol.FacesMoved(p_A, p_B)
	if (p_A == nil) ~= (p_B == nil) then
		return true
	end

	for _, l_Side in ipairs(Vol.FACE_SIDES) do
		local l_A, l_B = p_A ~= nil and p_A[l_Side] or nil, p_B ~= nil and p_B[l_Side] or nil

		if (l_A == nil) ~= (l_B == nil) or (l_A ~= nil and math.abs(l_A - l_B) >= 0.01) then
			return true
		end
	end

	return false
end

-- how much of the smoke at p_At the sides drawing in leave (as the shader thins the columns out from a place in from each to two),
-- 0 to 1
function Vol.FacesLeave(p_Faces, p_At)
	if p_Faces == nil then
		return 1.0
	end

	local function In(p_D)
		return math.max(0.0, math.min(1.0, p_D / ROOM_CELL - 1.0))
	end

	local s_Left = 1.0
	local s_X0, s_X1, s_Z0, s_Z1 = p_Faces.x0, p_Faces.x1, p_Faces.z0, p_Faces.z1

	if s_X0 ~= nil then s_Left = s_Left * In(p_At.x - s_X0) end
	if s_X1 ~= nil then s_Left = s_Left * In(s_X1 - p_At.x) end
	if s_Z0 ~= nil then s_Left = s_Left * In(p_At.z - s_Z0) end
	if s_Z1 ~= nil then s_Left = s_Left * In(s_Z1 - p_At.z) end

	return s_Left
end

-- p_Down's room drawn as the volume filling over time: its box made, the simulation started from when its room did
function Vol.SimStart(p_Down)
	local s_Room = p_Down.room
	s_Room.simFrom = s_Room.simFrom or s_Room.start or p_Down.age
	local s_Sim = Vol.SimSync(s_Room)
	local s_Boxes, s_Bound = Vol.SimPlaces(s_Room)

	if #s_Boxes == 0 then
		return false
	end

	-- (drawn round its smoke as it spreads, Vol.SimBound; its front from nothing, Vol.SimFront)
	local s_Drawn = Vol.SimBound(s_Boxes, s_Bound, s_Room.layer) or s_Boxes[1]
	s_Room.simFront = s_Room.simFront or 0.0
	local s_Transform = Vol.SimTransform(s_Drawn, s_Room)
	local s_Slot, s_Data = Vol.Slot({})
	local s_Entity = EntityManager:CreateEntity(s_Data, s_Transform)

	if s_Entity == nil then
		return false
	end

	s_Entity:Init(Realm.Realm_Client, true)
	Vol.now = { down = p_Down, boxes = { s_Entity }, drawn = { { entity = s_Entity, raw = s_Transform, slot = s_Slot } }, values = {},
		cells = s_Boxes, single = true, sim = true, all = s_Bound, bound = s_Drawn, top = s_Bound.y1, placesAt = s_Sim.topos,
		holesBefore = Vol.holeCount or 0 }

	if p_Down.logged ~= nil then
		LOG(string.format("smoke %d is drawn as a volume filling over time (VOLUME.SIM): its box %.1f x %.1f x %.1f m round %d place(s)"
			.. " measured so far, layers of %.2f m, %s, %s", p_Down.logged, s_Bound.x1 - s_Bound.x0, s_Bound.y1 - s_Bound.y0,
			s_Bound.z1 - s_Bound.z0, #s_Room.cells, s_Room.layer, s_Room.outside and "in the open" or "a ceiling over it",
			s_Room.hangs and "hanging (nothing under it)" or "a floor under it"))
	end

	return true
end

-- one frame of the room filling over time: the simulation stepped on to the smoke's age (Vol.SIM_STEPS at most), the places' boxes
-- and the box round them made again once the columns were, and its numbers written when anything drawn changed: the grid (a place
-- or two changing step a frame, Vol.SIM_FLIPS), how thick it is (thinning to nothing over VOLUME.CLEAR before p_End), the camera
-- into or out of its smoke, the bullets' holes
function Vol.SimFrame(p_End)
	local s_Now = Vol.now
	local s_Down = s_Now.down
	local s_Room = s_Down.room
	local s_Clock = Vol.Clock()
	-- (what each part takes, for the log at its end: ms in all and the most in a frame, Vol.SIM_PARTS)
	local s_Parts = s_Room.simParts or { ms = {}, most = {} }
	s_Room.simParts = s_Parts
	local s_Lap = s_Clock

	local function Lap(p_Name)
		local l_Now = s_Lap ~= nil and Vol.Clock() or nil

		if l_Now ~= nil then
			s_Parts.ms[p_Name] = (s_Parts.ms[p_Name] or 0.0) + (l_Now - s_Lap)
			s_Parts.most[p_Name] = math.max(s_Parts.most[p_Name] or 0.0, l_Now - s_Lap)
			s_Lap = l_Now
		end
	end

	-- (the smoke giving way to a canister too far for one grid, VOLUME.RECEDE: the box's sides drawing in, the canister poured in
	-- once they are in -- before the columns are made again)
	local s_Faces = Vol.RecedeFrame(s_Down)

	if Vol.FacesMoved(s_Now.faces, s_Faces) then
		s_Now.faces, s_Now.matrixFront = s_Faces, nil
	end

	local s_Sim = Vol.SimSync(s_Room)
	Lap("columns")
	local s_Steps = Vol.SimAdvance(s_Room, s_Down.age, s_Clock)

	local s_Sink = Vol.SimSinkFrame(s_Room, s_Down.age)
	Lap("steps")
	local s_Reshape = false

	if s_Now.placesAt ~= s_Sim.topos then
		s_Now.placesAt = s_Sim.topos
		s_Now.cells, s_Now.all = Vol.SimPlaces(s_Room)
		s_Now.top = s_Now.all.y1
		s_Reshape = true
	end

	Lap("places")

	-- the grid's numbers: after a step, while places wait to change step or columns fade in (VOLUME.SIM_COLUMNS: which of a
	-- column's pieces it holds, by the camera's height), the first time, and once the places changed (the grid's corner with them: a
	-- canister poured in, VOLUME.MERGE -- its numbers and its corner written together)
	local s_Eye = ClientUtils:GetCameraTransform()
	s_Room.simCamera = s_Eye ~= nil and s_Eye.trans or nil
	s_Room.simNow = s_Down.age

	if s_Steps > 0 or (s_Room.simBacklog or 0) > 0 or s_Now.words == nil or (s_Room.colSlots ~= nil and s_Room.colSlots.busy)
		or s_Room.colSyncAll or s_Reshape then
		local l_Origin, l_Words = Vol.SimWords(s_Room)
		local l_Same = s_Now.words ~= nil and s_Now.origin ~= nil and l_Origin.x == s_Now.origin.x and l_Origin.y == s_Now.origin.y
			and l_Origin.z == s_Now.origin.z and s_Room.colCheck == s_Now.colCheck
		s_Now.colCheck = s_Room.colCheck

		for l_I = 1, #l_Words do
			l_Same = l_Same and l_Words[l_I] == s_Now.words[l_I]
		end

		if not l_Same then
			s_Now.words, s_Now.origin, s_Now.unwritten = l_Words, l_Origin, true
			s_Reshape = true
		end
	end

	Lap("grid")

	-- the box round the smoke drawn (Vol.SimBound) and its front (Vol.SimFront), set again when either changed (a centimetre of
	-- front: every frame while it grows)
	local s_Front, s_Front2 = Vol.SimFront(s_Room, math.max(0.0, s_Down.age - (s_Now.frontAge or s_Down.age)))
	s_Now.frontAge = s_Down.age

	if s_Reshape then
		local l_New = Vol.SimBound(s_Now.cells, s_Now.all, s_Room.layer) or s_Now.cells[1]
		local l_Old = s_Now.bound

		if math.abs(l_New.x0 - l_Old.x0) + math.abs(l_New.y0 - l_Old.y0) + math.abs(l_New.z0 - l_Old.z0)
			+ math.abs(l_New.x1 - l_Old.x1) + math.abs(l_New.y1 - l_Old.y1) + math.abs(l_New.z1 - l_Old.z1) > 0.001 then
			s_Now.bound = l_New
			s_Now.matrixFront = nil
		end
	end

	-- (and as far down as the M320 round's ball has sunk, Vol.SimSink: the box, its fronts, the grid's corner and the bullets' holes
	-- counted from it, all drawn that much lower, a centimetre at a time)
	if math.abs(s_Sink - (s_Now.sinkDrawn or 0.0)) >= 0.01 then
		s_Now.sinkDrawn, s_Now.matrixFront, s_Now.unwritten = s_Sink, nil, true
	end

	if s_Now.matrixFront == nil or math.abs(s_Front - s_Now.matrixFront) >= 0.01
		or math.abs(s_Front2 - (s_Now.matrixFront2 or 0.0)) >= Vol.FRONT2_STEP then
		local l_Down = s_Now.sinkDrawn or 0.0
		local l_B = s_Now.bound
		-- (its sides drawing in while the smoke gives way where they are, VOLUME.RECEDE: a place out of the box round the smoke at first,
		-- the shader thinning the columns out from a place in from them)
		local l_F = s_Now.faces or {}
		local l_X0, l_Z0 = l_F.x0 or l_B.x0, l_F.z0 or l_B.z0
		s_Now.matrixFront, s_Now.matrixFront2 = s_Front, s_Front2
		s_Now.drawBound = { x0 = l_X0, y0 = l_B.y0 - l_Down, z0 = l_Z0, x1 = math.max(l_X0 + 0.01, l_F.x1 or l_B.x1),
			y1 = l_B.y1 - l_Down, z1 = math.max(l_Z0 + 0.01, l_F.z1 or l_B.z1) }
		s_Now.drawn[1].raw = Vol.SimTransform(s_Now.drawBound, s_Room, l_Down, s_Now.faces)
		s_Now.drawn[1].dirty = true
	end

	if s_Now.origin ~= nil then
		s_Now.drawOrigin = Vec3(s_Now.origin.x, s_Now.origin.y - (s_Now.sinkDrawn or 0.0), s_Now.origin.z)
	end

	Lap("front")
	local s_Strength = Vol.Strength(s_Down, p_End)
	local s_Camera = ClientUtils:GetCameraTransform()
	-- (the camera against the places as they are drawn: as high over them as the ball has sunk; within the sides drawing in while the
	-- smoke gives way)
	local s_Mode = (s_Camera ~= nil and Vol.SimInside(s_Now.cells, s_Camera.trans + Vec3(0.0, s_Now.sinkDrawn or 0.0, 0.0))
		and (s_Now.faces == nil or Vol.InBox(s_Now.drawBound, s_Camera.trans))) and 6 or 5
	Vol.nearBit = (s_Camera ~= nil and Vol.Near(s_Camera.trans)) and Vol.NEAR_BIT or 0
	s_Now.strength = s_Strength
	Lap("camera")

	local s_Due = VOLUME.EVERY_FRAME or s_Now.unwritten or s_Now.written == nil or math.abs(s_Strength - s_Now.written) >= Vol.ClearStep()
		or (s_Strength <= 0.0 and s_Now.written > 0.0) or s_Mode ~= s_Now.mode or (Vol.holeBits or 0) ~= (s_Now.holeBits or 0)
		or Vol.holeStamp ~= s_Now.holeStamp or (Vol.nearBit or 0) ~= (s_Now.nearBit or 0)

	if s_Due then
		local s_W = s_Now.words
		local s_Values = s_Now.values

		local function F(p_I)
			return Vol.Bits31(s_W[p_I])
		end

		-- (the check number; with the grid as columns its top 3 bits Vol.SimColumnCheck(), under them two of the fading columns)
		local s_Check = VOLUME.SIM_COLUMNS and (s_Now.colCheck or Vol.SimColumnCheck() * 268435456) or Vol.SIM_CHECK
		s_Values.TsSmokeA = Vec4(F(21), F(22), F(23), Vol.Bits31(s_Check))
		s_Values.TsSmokeB = Vec4(s_Now.drawOrigin.x, s_Now.drawOrigin.y, s_Now.drawOrigin.z, s_Room.layer)

		for l_I = 0, 4 do
			s_Values["TsSmokeBits" .. l_I] = Vec4(F(l_I * 4 + 1), F(l_I * 4 + 2), F(l_I * 4 + 3), F(l_I * 4 + 4))
		end

		local s_LookA, s_LookB = Vol.Look()
		-- (the mode word as ever: the front's height counted as VOLUME.TALL, which the volumes of their own read too)
		s_Values.TsSmokeC = Vec4(VOLUME.DENSITY * s_Strength, s_LookA, s_LookB, Vol.ModeWord(s_Mode))
		-- (the bullets' holes, Vol.HoleFrame: their ends, relative to this grid's corner)
		s_Values.TsSmokeD = Vol.HoleEnds()

		if Vol.SetParams(s_Values) then
			s_Now.written, s_Now.mode, s_Now.unwritten = s_Strength, s_Mode, false
			s_Now.holeBits, s_Now.holeStamp, s_Now.nearBit = Vol.holeBits or 0, Vol.holeStamp, Vol.nearBit or 0
			s_Now.writes = (s_Now.writes or 0) + 1
		end
	end

	Lap("write")
	Vol.Spent(s_Room, s_Clock, "simMs")
end

-- the parts of a frame of the room filling over time, as the log says them
Vol.SIM_PARTS = { "columns", "steps", "places", "grid", "front", "camera", "write" }

function Vol.SimPartsSaid(p_Room)
	local s_Parts, s_Said = p_Room.simParts, {}

	if s_Parts == nil then
		return "not timed"
	end

	for _, l_Name in ipairs(Vol.SIM_PARTS) do
		s_Said[#s_Said + 1] = string.format("%s %.1f (%.2f)", l_Name, s_Parts.ms[l_Name] or 0.0, s_Parts.most[l_Name] or 0.0)
	end

	return table.concat(s_Said, ", ")
end

-- the smoke the room's places hold (m3)
function Vol.SimHeld(p_Room)
	local s_Held = 0.0

	for _, l_Cell in ipairs(p_Room.cells) do
		s_Held = s_Held + (l_Cell.f or 0.0) + (l_Cell.h or 0.0)
	end

	return s_Held * ROOM_CELL * ROOM_CELL * p_Room.layer
end

-- how deep the camera (p_At) is in the room's smoke filling over time, 0 to 1: in one of its places' boxes that sees its place, as
-- full as that place is (from a sixth of it up), as thick as the smoke still is -- the smoke as drawn: within a front, and an M320
-- round's ball sinking (Vol.SimSink) as its places are drawn (none, some, full) that much lower
function Vol.SimFog(p_At)
	local s_Room = Vol.now.down.room
	local s_At = p_At + Vec3(0.0, Vol.now.sinkDrawn or 0.0, 0.0)
	local s_M = Vol.FrontAt(s_Room)

	if (Vol.FrontDistance(s_At, s_M) > (s_Room.simFront or 0.0) or Vol.FrontSide(s_Room, s_At) <= 0.0) and (s_Room.mouth2 == nil
		or Vol.FrontDistance(s_At, s_Room.mouth2) > (s_Room.simFront2 or 0.0)) then
		return 0.0
	end

	for _, l_Box in ipairs(Vol.now.cells) do
		if s_At.x >= l_Box.x0 and s_At.x <= l_Box.x1 and s_At.y >= l_Box.y0 and s_At.y <= l_Box.y1 and s_At.z >= l_Box.z0
			and s_At.z <= l_Box.z1 then
			-- (none in a column behind a wall the front along the way has not got to, nothing of it shown: VOLUME.SIM_WAY)
			if not Vol.Sees(l_Box.cell, s_At) or (s_Room.colHeld ~= nil and s_Room.colHeld[Vol.Key(l_Box.cell.i, 0, l_Box.cell.k)]) then
				return 0.0
			end

			local l_V = math.min(1.0, (l_Box.cell.f or 0.0) + (l_Box.cell.h or 0.0))

			if s_Room.colFrozen then
				l_V = (l_Box.cell.q or 0) * 0.5
			end

			-- (and as much as the sides drawing in leave, VOLUME.RECEDE)
			return math.max(0.0, math.min(1.0, (l_V - 0.15) / 0.6)) * Vol.FogStrength(Vol.now.down, Vol.now.strength)
				* Vol.FacesLeave(Vol.now.faces, s_At)
		end
	end

	return 0.0
end

-- a smoke going off among the places of the room filling over time joins it (p_From: the joining smoke's room, its amount): a
-- canister's poured into the room's place nearest its own first place, as a canister pours; an M320 round's let out at once round
-- where it hit, a ball hanging there (as Vol.SimHang shares it out, all of its amount) and sinking
function Vol.SimJoin(p_Room, p_From)
	local s_Sim = p_Room.sim
	local s_All = (p_From.amountMax or VOLUME.AMOUNT) / (ROOM_CELL * ROOM_CELL * p_Room.layer)

	if s_Sim == nil then
		return false
	end

	if p_From.hit ~= nil then
		local s_R = (3.0 * (p_From.amountMax or VOLUME.M320_AMOUNT) / (4.0 * math.pi)) ^ (1.0 / 3.0)
		local s_Share, s_Sum = {}, 0.0

		for _, l_Cell in ipairs(p_Room.cells) do
			if l_Cell.seg ~= nil then
				local l_At = Vec3(p_Room.floor.x + l_Cell.i * ROOM_CELL, p_Room.floor.y + p_Room.layer * (0.5 + l_Cell.j),
					p_Room.floor.z + l_Cell.k * ROOM_CELL)
				local l_Way = l_At - p_From.hit
				local l_W = math.max(0.0, math.min(1.0, (s_R - math.sqrt(Dot(l_Way, l_Way))) / ROOM_CELL + 0.5))

				if l_W > 0.0 then
					s_Share[#s_Share + 1] = { cell = l_Cell, w = l_W }
					s_Sum = s_Sum + l_W
				end
			end
		end

		if s_Sum > 0.0 then
			-- (the smoke settled there staying where it is, VOLUME.HOLD)
			Vol.SimHold(p_Room)

			for _, l_Share in ipairs(s_Share) do
				l_Share.cell.h = (l_Share.cell.h or 0.0) + s_All * l_Share.w / s_Sum
			end

			s_Sim.joinedAll = (s_Sim.joinedAll or 0.0) + s_All
			-- (VOLUME.SIM_AHEAD: the room simulated on until the ball has sunk and settled as well; the ball seen within a front of its
			-- own round where it hit; a ball drawn sinking taken up by the simulation again)
			s_Sim.settleTo = math.max(s_Sim.settleTo or 0.0, s_Sim.t + Vol.SIM_SETTLE_BALL)
			Vol.SimSecondFront(p_Room, p_From.hit)
			Vol.SimUnfreeze(p_Room)
			return true
		end
	end

	local s_Best, s_Far = nil, math.huge

	for _, l_Cell in ipairs(p_Room.cells) do
		local l_Way = l_Cell.at - p_From.source
		local l_D = Dot(l_Way, l_Way)

		if l_Cell.seg ~= nil and l_D < s_Far then
			s_Best, s_Far = l_Cell, l_D
		end
	end

	if s_Best == nil then
		return false
	end

	s_Sim.pours = s_Sim.pours or {}
	s_Sim.pours[#s_Sim.pours + 1] = { cell = s_Best, from = s_Sim.t, poured = 0.0, all = s_All }
	return true
end

-- ---- a second canister into the room filling over time (VOLUME.MERGE) ---------------------------------------------------------------
-- A canister going off while another smoke's room fills over time pours into that room as a second canister. Its place there: of the
-- room's places round where it lies (on the room's grid of places, the first canister's), the nearest it sees -- one of the room's
-- already, or measured now as the room's first one was. The room is measured on from it (the places waiting to be measured costed
-- from the nearer canister) as far as both smokes' amount fills, and its smoke poured out there as a canister pours (Vol.SimPoured)
-- from now. The grid (Vol.NX x Vol.NZ places across) moves over to take in both: every place whose smoke is drawn, and the new
-- canister's with as many places round it as it can up to Vol.MERGE_ROOM, centred on them; the places measured that it no longer takes
-- in are left out (their smoke, a trace not drawn yet, back to the first canister's place). A canister too far for one grid with the
-- smoke drawn there, out of the room's layers, or in the open while the room is under a ceiling (or the other way round), is a volume
-- of its own as before.
Vol.MERGE_ROOM = 4

-- a smoke poured or let out into the room (a canister, VOLUME.MERGE; an M320 round joining it): a front of its own round p_Mouth,
-- grown from nothing as the first's was; the first's held to as far as the smoke drawn reaches now (its edge drawn whole), so what the
-- new one brings shows within its own front alone. A third one takes the second's front over: the smoke the second's had not got to
-- yet is shown at once (one front each is all the box's matrix holds)
function Vol.SimSecondFront(p_Room, p_Mouth)
	-- (a third: the first front round its mouth again, unsplit, Vol.SimFrontSplit)
	if p_Room.mouth2 ~= nil then
		p_Room.frontAt, p_Room.frontSplit = nil, nil
	end

	local s_M = Vol.FrontAt(p_Room)

	if p_Room.mouth2 ~= nil then
		p_Room.simFront = math.max(p_Room.simFront or 0.0, Vol.SimReach(p_Room, s_M))
		p_Room.front1Cap = p_Room.simFront
	else
		p_Room.front1Cap = math.max(0.0, Vol.SimReach(p_Room, s_M) - ROOM_CELL * 0.5)
	end

	-- (its front along the way from now: a third's keeps on the second's -- what it showed stays shown, Vol.SimWayHeld)
	p_Room.mouth2, p_Room.simFront2, p_Room.wayFront2 = p_Mouth, 0.0, p_Room.wayFront2 or 0.0
	p_Room.paceV2, p_Room.paceW2, p_Room.pace2Go = 0.0, 0.0, nil
end

-- another smoke coming into the room (VOLUME.HOLD): the smoke stacked there once it had settled (all poured and simulated on to where it
-- ends up: VOLUME.SIM_AHEAD) stays where it is -- each place's share of it kept there (p_Cell.fixed), counting in its column's level,
-- none of it moving (Vol.SimStep) --: the new smoke spreads round it and over it, and what is drawn of the first changes only where the
-- new smoke gets to. True if it did
function Vol.SimHold(p_Room)
	if not VOLUME.HOLD or p_Room.settledAt == nil then
		return false
	end

	for _, l_Cell in ipairs(p_Room.cells) do
		l_Cell.fixed = l_Cell.f or 0.0
	end

	return true
end

-- an M320 round's ball drawn sinking (Vol.SimSink) taken up by the simulation again: drawn as the simulation stands, at once
-- (p_Room.colSyncAll), no longer lower
function Vol.SimUnfreeze(p_Room)
	if p_Room.sinkFrom ~= nil then
		p_Room.sinkFrom, p_Room.colFrozen, p_Room.colSyncAll = nil, nil, true
	end
end

-- the middle of the room's front (Vol.SimFront): the canister's mouth (where the round hit), or where Vol.SimFrontRound put it
function Vol.FrontAt(p_Room)
	return p_Room.frontAt or p_Room.mouth or p_Room.source
end

-- the room's front round its places drawn alone (the smoke kept once it gave way, VOLUME.RECEDE): its middle the middle of them along
-- the floor (as high as it was), as far as they reach and a cell further -- every one within it as before, nothing else drawn yet
function Vol.SimFrontRound(p_Room)
	local s_I0, s_I1, s_K0, s_K1 = math.huge, -math.huge, math.huge, -math.huge

	for _, l_Cell in ipairs(p_Room.cells) do
		if (l_Cell.q or 0) > 0 then
			s_I0, s_I1 = math.min(s_I0, l_Cell.i), math.max(s_I1, l_Cell.i)
			s_K0, s_K1 = math.min(s_K0, l_Cell.k), math.max(s_K1, l_Cell.k)
		end
	end

	if s_I0 > s_I1 then
		return
	end

	local s_F = p_Room.floor
	p_Room.frontAt = Vec3(s_F.x + (s_I0 + s_I1) * 0.5 * ROOM_CELL, Vol.FrontAt(p_Room).y, s_F.z + (s_K0 + s_K1) * 0.5 * ROOM_CELL)
	p_Room.simFront = Vol.SimReach(p_Room, p_Room.frontAt)
end

-- the room's front once its smoke gave way (VOLUME.RECEDE) to a canister at p_Mouth2: split from the new one's front along a plane
-- (upright) between the smoke kept and the new canister -- every place kept, its soft edge a cell further, Vol.FRONT_SPLIT / 2 and
-- Vol.SPLIT_SLACK past it on the front's side: the shader's split weighs the front from none to whole over FRONT_SPLIT across it --,
-- its middle the new canister's mirrored over that plane (the shader takes the plane half way between the two middles), as far as the
-- places kept reach from there and a cell further. Every place kept is within it and on its side as before; the new canister's side,
-- with nothing drawn yet, is the second front's alone -- the smoke spreading out there seen as it gets there, not a column at a time.
-- With no room for the plane (the smoke kept reaching nearer the canister than that and Vol.SPLIT_ROOM, or the middle out of the box
-- drawn): round the smoke kept (Vol.SimFrontRound)
Vol.FRONT_SPLIT = 1.0
Vol.SPLIT_SLACK = 0.2
Vol.SPLIT_ROOM = 1.0

function Vol.SimFrontSplit(p_Room, p_Mouth2, p_Bound)
	local s_From = Vol.FrontAt(p_Room)
	local s_X, s_Z = s_From.x - p_Mouth2.x, s_From.z - p_Mouth2.z
	local s_Len = math.sqrt(s_X * s_X + s_Z * s_Z)

	if s_Len < 0.01 then
		Vol.SimFrontRound(p_Room)
		return
	end

	-- (along the floor from the new canister towards the smoke kept; the nearest place drawn that way)
	local s_NX, s_NZ = s_X / s_Len, s_Z / s_Len
	local s_Near = math.huge

	for _, l_Cell in ipairs(p_Room.cells) do
		if (l_Cell.q or 0) > 0 then
			s_Near = math.min(s_Near, (p_Room.floor.x + l_Cell.i * ROOM_CELL - p_Mouth2.x) * s_NX
				+ (p_Room.floor.z + l_Cell.k * ROOM_CELL - p_Mouth2.z) * s_NZ)
		end
	end

	local s_At = s_Near - ROOM_CELL - Vol.FRONT_SPLIT * 0.5 - Vol.SPLIT_SLACK
	local s_Middle = Vec3(p_Mouth2.x + s_NX * 2.0 * s_At, s_From.y, p_Mouth2.z + s_NZ * 2.0 * s_At)

	if s_At < Vol.SPLIT_ROOM or (p_Bound ~= nil and not (s_Middle.x > p_Bound.x0 and s_Middle.x < p_Bound.x1 and s_Middle.z > p_Bound.z0
		and s_Middle.z < p_Bound.z1)) then
		Vol.SimFrontRound(p_Room)
		return
	end

	p_Room.frontAt, p_Room.frontSplit = s_Middle, true
	p_Room.simFront = Vol.SimReach(p_Room, s_Middle)
end

-- how much of the room's front counts at p_At once split from the second's (Vol.SimFrontSplit), as the shader weighs it: none on the
-- second's side of the plane half way between their middles, whole on its own, over Vol.FRONT_SPLIT across it (1 unsplit)
function Vol.FrontSide(p_Room, p_At)
	if not p_Room.frontSplit or p_Room.mouth2 == nil then
		return 1.0
	end

	local s_M, s_M2 = Vol.FrontAt(p_Room), p_Room.mouth2
	local s_X, s_Z = s_M.x - s_M2.x, s_M.z - s_M2.z
	local s_Len = math.max(math.sqrt(s_X * s_X + s_Z * s_Z), 1e-6)
	local s_D = ((p_At.x - (s_M.x + s_M2.x) * 0.5) * s_X + (p_At.z - (s_M.z + s_M2.z) * 0.5) * s_Z) / s_Len
	return math.max(0.0, math.min(1.0, s_D / Vol.FRONT_SPLIT + 0.5))
end

-- how far from p_M (as the front counts it) the room's places drawn reach, and a cell further (Vol.SimFront's)
function Vol.SimReach(p_Room, p_M)
	local s_Tall = Vol.Tall()
	local s_Far = 0.0

	for _, l_Cell in ipairs(p_Room.cells) do
		if (l_Cell.q or 0) > 0 then
			s_Far = math.max(s_Far, (p_Room.floor.x + l_Cell.i * ROOM_CELL - p_M.x) ^ 2
				+ ((p_Room.floor.y + p_Room.layer * (0.5 + l_Cell.j) - p_M.y) * s_Tall) ^ 2 + (p_Room.floor.z + l_Cell.k * ROOM_CELL - p_M.z) ^ 2)
		end
	end

	return math.sqrt(s_Far) + (Vol.SIM_FRONT_AHEAD or (ROOM_CELL + Vol.FRONT))
end

-- where p_From (the new smoke's room as measured so far; its canister's place p_From.source) pours into p_Room: its place's i, j, k,
-- the point it is measured from, the grid's new corner and how many places of room round it the grid gives it -- or nil and why not
function Vol.SimMergeWhere(p_Room, p_From)
	if p_From.hit ~= nil then
		return nil, "an M320 round's"
	end

	if (p_From.outside == true) ~= (p_Room.outside == true) then
		return nil, p_Room.outside and "under a ceiling, the room in the open" or "in the open, the room under a ceiling"
	end

	local s_F, s_L, s_S = p_Room.floor, p_Room.layer, p_From.source
	local s_J = math.floor((s_S.y - s_F.y) / s_L)

	if s_J < 0 or s_J >= Vol.NY then
		return nil, string.format("out of the room's layers (%.1f m over its floor)", s_S.y - s_F.y)
	end

	-- (the room's places round it, the nearest first: the first one a ray from where it lies gets to -- over what it lies by,
	-- Vol.FLOW_LIFT of a layer up, if not straight)
	local s_FI, s_FK = (s_S.x - s_F.x) / ROOM_CELL, (s_S.z - s_F.z) / ROOM_CELL
	local s_Round = {}

	for _, l_I in ipairs({ math.floor(s_FI), math.floor(s_FI) + 1 }) do
		for _, l_K in ipairs({ math.floor(s_FK), math.floor(s_FK) + 1 }) do
			s_Round[#s_Round + 1] = { i = l_I, k = l_K, d = (l_I - s_FI) ^ 2 + (l_K - s_FK) ^ 2 }
		end
	end

	table.sort(s_Round, function(p_A, p_B) return p_A.d < p_B.d end)
	local s_Pick = nil

	for _, l_Round in ipairs(s_Round) do
		local l_Place = Vec3(s_F.x + l_Round.i * ROOM_CELL, s_F.y + s_L * (0.5 + s_J), s_F.z + l_Round.k * ROOM_CELL)
		local l_At = l_Place
		local l_Blocked = RaycastManager:Raycast(s_S, l_At, RAY_FLAGS) ~= nil

		if l_Blocked then
			l_At = l_Place + Vec3(0.0, s_L * Vol.FLOW_LIFT, 0.0)
			l_Blocked = RaycastManager:Raycast(s_S, l_At, RAY_FLAGS) ~= nil
		end

		if not l_Blocked then
			s_Pick = { i = l_Round.i, j = s_J, k = l_Round.k, place = l_Place, at = l_At }
			break
		end
	end

	if s_Pick == nil then
		return nil, "none of the room's places round it in sight"
	end

	-- (what the grid must take in: the first canister's place, every place whose smoke is drawn, the new canister's -- a trace of smoke
	-- not drawn yet, under a column's first step, may be left out)
	local s_I0, s_I1, s_K0, s_K1 = s_Pick.i, s_Pick.i, s_Pick.k, s_Pick.k

	for l_Index, l_Cell in ipairs(p_Room.cells) do
		if l_Index == 1 or (l_Cell.q or 0) > 0 then
			s_I0, s_I1 = math.min(s_I0, l_Cell.i), math.max(s_I1, l_Cell.i)
			s_K0, s_K1 = math.min(s_K0, l_Cell.k), math.max(s_K1, l_Cell.k)
		end
	end

	-- (along one way: the grid's first place taking in p_Lo .. p_Hi and p_At with as many places round it as it can, up to
	-- Vol.MERGE_ROOM, centred on them; and how many)
	local function Corner(p_Lo, p_Hi, p_At, p_N)
		for l_M = Vol.MERGE_ROOM, 0, -1 do
			local l_From = math.max(p_Hi - p_N + 1, p_At + l_M - p_N + 1)
			local l_To = math.min(p_Lo, p_At - l_M)

			if l_From <= l_To then
				local l_Mid = math.floor((math.min(p_Lo, p_At - l_M) + math.max(p_Hi, p_At + l_M) - (p_N - 1)) / 2)
				return math.max(l_From, math.min(l_To, l_Mid)), l_M
			end
		end

		return nil, 0
	end

	local s_CI, s_MI = Corner(s_I0, s_I1, s_Pick.i, Vol.NX)
	local s_CK, s_MK = Corner(s_K0, s_K1, s_Pick.k, Vol.NZ)

	-- (and where it would pour, for the smoke there to give way to it: Vol.SimRecedeWhere)
	if s_CI == nil or s_CK == nil then
		return nil, string.format("too far for one grid with the smoke there (%d x %d places across, the grid %d x %d)", s_I1 - s_I0 + 1,
			s_K1 - s_K0 + 1, Vol.NX, Vol.NZ), s_Pick
	end

	s_Pick.i0, s_Pick.k0, s_Pick.room = s_CI, s_CK, math.min(s_MI, s_MK)
	-- (for the log: the places it takes in across, each way)
	s_Pick.across = string.format("%d x %d", s_I1 - s_I0 + 1, s_K1 - s_K0 + 1)
	return s_Pick
end

-- ---- the smoke there giving way to a canister too far for one grid (VOLUME.RECEDE) ----------------------------------------------------
-- A canister too far from the room filling over time for its grid to take in both smokes as they are drawn: the grid's window moves
-- over to take in the first canister's place and the new one's (p_Pick, Vol.SimMergeWhere's) with as many places of room round it as
-- it can (Vol.MERGE_ROOM down to none) and, of the windows that do, the one keeping the most of the first's places drawn (the nearest
-- the middle of them when more keep as many). The smoke past it gives way: the room's box's sides past it draw in to it at
-- VOLUME.RECEDE a second, the columns of smoke they pass thinning out over a place as they go (the shader's: a side drawing in
-- weighs each column a place in from it by how far in it is, none past it); once all are in, the canister pours in as one that fits
-- (Vol.SimMergeInto), the smoke past the window dropped -- by then nothing of it is drawn, and the columns kept are drawn as they
-- were: the grid's own edge there is where the sides stopped, nothing seen changing. Nil and why when no window takes in both places
-- (they are more than a grid apart), another smoke came into the room before (one front more is all the box's matrix holds) or the
-- room is giving way already
function Vol.SimRecedeWhere(p_Room, p_Pick)
	if p_Room.recede ~= nil then
		return nil, "the smoke there is giving way to another canister already"
	end

	if p_Room.mouth2 ~= nil then
		return nil, "another smoke came into that room before it"
	end

	local s_First = p_Room.cells[1]
	local s_Drawn = {}

	for _, l_Cell in ipairs(p_Room.cells) do
		if (l_Cell.q or 0) > 0 then
			s_Drawn[#s_Drawn + 1] = l_Cell
		end
	end

	for l_M = Vol.MERGE_ROOM, 0, -1 do
		-- (the grid's first place along either way: the first canister's place in it, the new one's with l_M places round it)
		local l_ILo, l_IHi = math.max(s_First.i, p_Pick.i + l_M) - (Vol.NX - 1), math.min(s_First.i, p_Pick.i - l_M)
		local l_KLo, l_KHi = math.max(s_First.k, p_Pick.k + l_M) - (Vol.NZ - 1), math.min(s_First.k, p_Pick.k - l_M)

		if l_ILo <= l_IHi and l_KLo <= l_KHi then
			local l_Best = nil

			for l_I0 = l_ILo, l_IHi do
				for l_K0 = l_KLo, l_KHi do
					local l_Kept = 0

					for _, l_Cell in ipairs(s_Drawn) do
						if l_Cell.i >= l_I0 and l_Cell.i < l_I0 + Vol.NX and l_Cell.k >= l_K0 and l_Cell.k < l_K0 + Vol.NZ then
							l_Kept = l_Kept + 1
						end
					end

					local l_Off = math.abs(2 * l_I0 - l_ILo - l_IHi) + math.abs(2 * l_K0 - l_KLo - l_KHi)

					if l_Best == nil or l_Kept > l_Best.kept or (l_Kept == l_Best.kept and l_Off < l_Best.off) then
						l_Best = { i0 = l_I0, k0 = l_K0, kept = l_Kept, off = l_Off }
					end
				end
			end

			p_Pick.i0, p_Pick.k0, p_Pick.room, p_Pick.recede = l_Best.i0, l_Best.k0, l_M, true
			p_Pick.kept, p_Pick.cut = l_Best.kept, #s_Drawn - l_Best.kept
			p_Pick.across = string.format("%d x %d", math.abs(p_Pick.i - s_First.i) + 1, math.abs(p_Pick.k - s_First.k) + 1)
			return p_Pick
		end
	end

	return nil, string.format("too far for one grid even with the smoke there giving way (the canisters' places %d x %d apart, the grid"
		.. " %d x %d)", math.abs(p_Pick.i - s_First.i) + 1, math.abs(p_Pick.k - s_First.k) + 1, Vol.NX, Vol.NZ)
end

-- the sides of the room's box drawing in to the window p_Where takes in (Vol.SimRecedeWhere), from where the box is drawn now
-- (p_Bound): for each side with smoke drawn past the window, where it is -- a place further out than the box round the smoke
-- (Vol.SimBound): the shader thins the columns out from a place in from a side, so the smoke drawn stays as it was -- and where it
-- stops -- two places out of the window: the columns past it weigh nothing, the first one in it its whole --, and how far it has to go
function Vol.RecedeSides(p_Room, p_Where, p_Bound)
	local s_F = p_Room.floor
	local s_Lo = { x = s_F.x + (p_Where.i0 - 2) * ROOM_CELL, z = s_F.z + (p_Where.k0 - 2) * ROOM_CELL }
	local s_Hi = { x = s_F.x + (p_Where.i0 + Vol.NX + 1) * ROOM_CELL, z = s_F.z + (p_Where.k0 + Vol.NZ + 1) * ROOM_CELL }
	local s_Sides, s_Most = {}, 0.0

	for _, l_Axis in ipairs({ "x", "z" }) do
		local l_From0, l_From1 = p_Bound[l_Axis .. "0"] - ROOM_CELL, p_Bound[l_Axis .. "1"] + ROOM_CELL

		if s_Lo[l_Axis] > l_From0 + 0.01 then
			s_Sides[l_Axis .. "0"] = { from = l_From0, to = s_Lo[l_Axis], way = 1.0 }
			s_Most = math.max(s_Most, s_Lo[l_Axis] - l_From0)
		end

		if s_Hi[l_Axis] < l_From1 - 0.01 then
			s_Sides[l_Axis .. "1"] = { from = l_From1, to = s_Hi[l_Axis], way = -1.0 }
			s_Most = math.max(s_Most, l_From1 - s_Hi[l_Axis])
		end
	end

	return s_Sides, s_Most
end

-- how fast the sides draw in (m/s): VOLUME.RECEDE, or faster for a long way -- in no more than Vol.RECEDE_MOST s (the canister pours
-- once they are in) --, the same all the way
Vol.RECEDE_MOST = 2.0

function Vol.RecedePace(p_Most)
	return math.max(VOLUME.RECEDE or 0.0, 0.05, p_Most / Vol.RECEDE_MOST)
end

-- the side faces the room's box is drawn within while its smoke gives way (p_Room.recede): each side drawing in at its pace
-- (Vol.RecedePace) from when it began (p_Age, the smoke's), no further than where it stops; once all are in, the new canister poured
-- in (Vol.RecedeEnd) and nil
function Vol.RecedeFrame(p_Down)
	local s_R = p_Down.room.recede

	if s_R == nil then
		return nil
	end

	local s_Gone = math.max(0.0, p_Down.age - s_R.at) * Vol.RecedePace(s_R.most)

	if s_Gone >= s_R.most then
		Vol.RecedeEnd(p_Down)
		return nil
	end

	local s_Faces = {}

	for l_Side, l_S in pairs(s_R.sides) do
		s_Faces[l_Side] = l_S.from + l_S.way * math.min(s_Gone, math.abs(l_S.to - l_S.from))
	end

	return s_Faces
end

-- p_Down's smoke (a canister too far for the room filling over time, Vol.SimRecedeWhere at p_Where) poured into it once the smoke
-- there has given way: that smoke lasting on from now, as long as a new one; this one's room drawn by it from now on, measured no
-- further (nothing of it drawn while that one gives way)
function Vol.RecedeStart(p_Down, p_Where)
	local s_Room = p_Down.room
	local s_Into = Vol.now.down
	local s_Bound = Vol.now.drawBound or Vol.now.bound
	local s_Sides, s_Most = Vol.RecedeSides(s_Into.room, p_Where, s_Bound)
	s_Into.room.recede = { where = p_Where, from = s_Room, down = p_Down, at = s_Into.age, sides = s_Sides, most = s_Most }
	s_Into.room.recedeMost = s_Most
	s_Into.room.start = s_Into.age
	s_Room.joined = s_Into
	s_Room.volume = true

	if p_Down.logged ~= nil then
		local l_Way = s_Room.source - s_Into.room.source
		local l_Said = {}

		for l_Side, l_S in pairs(s_Sides) do
			l_Said[#l_Said + 1] = string.format("%s %.1f m", l_Side, math.abs(l_S.to - l_S.from))
		end

		table.sort(l_Said)
		LOG(string.format("smoke %d is too far from smoke %s's room filling over time for one grid with the smoke there (%.1f m from its"
			.. " canister, the canisters' places %s across): that smoke gives way (VOLUME.RECEDE, %.1f m/s, %.1f s: its sides %s), %d of"
			.. " its %d place(s) drawn kept, with %d place(s) of room round this one; it pours in then", p_Down.logged,
			tostring(s_Into.logged or "(not logged)"), math.sqrt(Dot(l_Way, l_Way)), p_Where.across, Vol.RecedePace(s_Most), s_Most
			/ Vol.RecedePace(s_Most), table.concat(l_Said, ", "), p_Where.kept, p_Where.kept + p_Where.cut, p_Where.room))
	end
end

-- the smoke there has given way (p_Down: the room filling over time's smoke): the new canister poured in at its window, the smoke past
-- it dropped (Vol.SimMergeInto)
function Vol.RecedeEnd(p_Down)
	local s_Room = p_Down.room
	local s_R = s_Room.recede
	s_Room.recede = nil
	s_R.where.cut = true
	local s_Done = Vol.SimMergeInto(s_Room, s_R.from, s_R.where)
	-- (lasting on from now, as long as a new one: the canister pours from now)
	s_Room.start = p_Down.age

	if s_R.down.logged ~= nil then
		LOG(string.format("smoke %s's room filling over time has given way: smoke %d poured in at its place %d, %d, %d (%s), the grid"
			.. " moved over %d, %d place(s); %d measured place(s) past it dropped with %.1f m3 of smoke not drawn any more; the room"
			.. " measured on for %.0f m3 in all", tostring(p_Down.logged or "(not logged)"), s_R.down.logged, s_R.where.i, s_R.where.j,
			s_R.where.k, s_Done.new and "measured now" or "one of its places already", s_Done.movedI, s_Done.movedK, s_Done.left,
			s_Done.back, (s_Room.amountMax or VOLUME.AMOUNT) + (s_Room.pouredIn or 0.0)))
	end
end

-- p_From's smoke poured into p_Room at p_Where (Vol.SimMergeWhere): the grid moved over, the places it no longer takes in left out,
-- the new canister's place one of the room's, the room measured on from it for both smokes' amount, its smoke poured out there from
-- now; what was done, for the log
function Vol.SimMergeInto(p_Room, p_From, p_Where)
	local s_Sim = p_Room.sim
	local s_Place = ROOM_CELL * ROOM_CELL * p_Room.layer
	local s_WasI, s_WasK = Vol.SimCorner(p_Room)
	p_Room.window = { i0 = p_Where.i0, k0 = p_Where.k0 }

	-- (the places the grid no longer takes in: left out, their smoke back to the first canister's place -- a trace not drawn yet; past
	-- the window of smoke that gave way, p_Where.cut, dropped: Vol.RecedeFrame drew it out of sight first -- counted in s_Sim.cut)
	local s_First = p_Room.cells[1]
	local s_Kept, s_Out, s_Back = { s_First }, {}, 0.0

	for l_Index = 2, #p_Room.cells do
		local l_Cell = p_Room.cells[l_Index]

		if Vol.FitsRoom(p_Room, l_Cell.i, l_Cell.k) then
			s_Kept[#s_Kept + 1] = l_Cell
		else
			s_Out[l_Cell] = true
			s_Back = s_Back + (l_Cell.f or 0.0) + (l_Cell.h or 0.0)

			if p_Where.cut then
				s_Sim.cut = (s_Sim.cut or 0.0) + (l_Cell.f or 0.0) + (l_Cell.h or 0.0)
			else
				s_First.f = (s_First.f or 0.0) + (l_Cell.f or 0.0)
				s_First.h = (s_First.h or 0.0) + (l_Cell.h or 0.0)
			end

			l_Cell.f, l_Cell.h = 0.0, 0.0
			p_Room.cellAt[Vol.Key(l_Cell.i, l_Cell.j, l_Cell.k)] = nil

			if p_Room.colShown ~= nil then
				p_Room.colShown[Vol.Key(l_Cell.i, 0, l_Cell.k)] = nil
			end
		end
	end

	local s_Left = #p_Room.cells - #s_Kept
	p_Room.cells = s_Kept
	p_Room.amount = (p_Room.amount or 0.0) - s_Left * s_Place
	p_Room.spread = { minI = s_First.i, maxI = s_First.i, minK = s_First.k, maxK = s_First.k }

	for _, l_Cell in ipairs(s_Kept) do
		Vol.Spread(p_Room.spread, l_Cell.i, l_Cell.k)
	end

	if p_Room.open ~= nil and s_Out[p_Room.open] then
		p_Room.open = nil
	end

	-- (the smoke settled there staying where it is, VOLUME.HOLD)
	local s_Held = Vol.SimHold(p_Room)

	-- (the new canister's place: one of the room's already, or measured now as the room's first one was -- kept off the walls round
	-- it, its gaps -- its neighbours found from it next)
	local s_Key = Vol.Key(p_Where.i, p_Where.j, p_Where.k)
	local s_Seed = p_Room.cellAt[s_Key]
	local s_New = s_Seed == nil

	if s_New then
		local l_At = p_Where.at
		local l_Over = l_At ~= p_Where.place
		local l_Clear, l_Wide, l_Gaps = KeepClear(l_At, ROOM_CELL)
		Vol.Gaps(l_Gaps, l_At, p_Room.layer)
		local l_Lift = l_At.y - p_Where.place.y
		l_Gaps.up = l_Gaps.up + l_Lift
		l_Gaps.down = l_Gaps.down - l_Lift

		if RaycastManager:Raycast(p_From.source, l_Clear, RAY_FLAGS) == nil then
			l_At = l_Clear
		end

		s_Seed = { i = p_Where.i, j = p_Where.j, k = p_Where.k, at = l_At, reach = math.sqrt(p_Where.i * p_Where.i + p_Where.k
			* p_Where.k) * ROOM_CELL, narrow = l_Wide < ROOM_NARROW, gaps = l_Gaps, path = 0.0, along = 0.0, cost = 0.0,
			place = p_Where.place, over = l_Over }
		p_Room.cells[#p_Room.cells + 1] = s_Seed
		p_Room.cellAt[s_Key] = s_Seed
		p_Room.seen[p_Where.i .. "," .. p_Where.j .. "," .. p_Where.k] = true
		p_Room.amount = p_Room.amount + s_Place
		Vol.Spread(p_Room.spread, p_Where.i, p_Where.k)

		if p_Room.open == nil then
			p_Room.open = s_Seed
		else
			p_Room.openNext = s_Seed
		end
	end

	-- (its smoke poured there: never left out for standing on a floor over air, Vol.FlowOverFloors; the ways of the places measured on
	-- from it counted from it, shown as the second front gets along them, Vol.SimWayHeld)
	s_Seed.poured = true
	s_Seed.path, s_Seed.wayOf, s_Seed.along = 0.0, 2, 0.0
	p_Room.source2 = s_Seed.place or s_Seed.at

	-- (the places waiting to be measured: costed from the nearer canister, straight from the new one's place; those the grid no longer
	-- takes in, or found from a place left out, dropped)
	local s_Heap = p_Room.heap or {}
	p_Room.heap = {}

	for _, l_Item in ipairs(s_Heap) do
		if Vol.FitsRoom(p_Room, l_Item.i, l_Item.k) and not s_Out[l_Item.from] then
			l_Item.cost = math.min(l_Item.cost, Vol.ShapeDistance(l_Item.place - s_Seed.place, p_Room)
				+ Vol.Gravity(p_Room) * (l_Item.place.y - p_Room.source.y) / Vol.FLOW_SPAN)
			Vol.HeapPush(p_Room.heap, l_Item)
		end
	end

	-- measured on for both smokes' amount (the first canister's own, amountMax, as it was: it pours that), its columns made again at
	-- once, its smoke poured out from now
	p_Room.pouredIn = (p_Room.pouredIn or 0.0) + (p_From.amountMax or VOLUME.AMOUNT)
	p_Room.done = false
	p_Room.flowEnd = nil
	-- (simulated on at the smoke's own pace from now while it is measured on, VOLUME.SIM_AHEAD: Vol.SimAdvance; its front's pace noted
	-- from now, VOLUME.SIM_PACE)
	p_Room.stepFrom = { t = s_Sim.t, age = p_Room.simNow or 0.0 }
	s_Sim.pace2From = s_Sim.t
	p_Room.version = (p_Room.version or 0) + 1
	p_Room.simForce = true
	s_Sim.pours = s_Sim.pours or {}
	s_Sim.pours[#s_Sim.pours + 1] = { cell = s_Seed, from = s_Sim.t, poured = 0.0, all = (p_From.amountMax or VOLUME.AMOUNT) / s_Place }
	-- (its smoke seen within a front of its own, round its mouth, grown from now as the first's was: Vol.SimSecondFront -- the first's,
	-- past the window of smoke that gave way, round the smoke kept alone: from the middle of its places drawn, as far as they reach and
	-- a cell further (Vol.SimReach) -- nothing past them is drawn any more, they are within it whole; else the new smoke near them would
	-- show within the first's front, a column at a time)
	if p_Where.cut then
		Vol.SimFrontSplit(p_Room, p_From.mouth or p_From.source, Vol.now ~= nil and Vol.now.bound or nil)
	end

	Vol.SimSecondFront(p_Room, p_From.mouth or p_From.source)
	p_Room.merged = (p_Room.merged or 0) + 1
	-- (an M320 round's ball drawn sinking taken up by the simulation again, shown as it stands: the room fills as a canister's now)
	Vol.SimUnfreeze(p_Room)
	return { movedI = p_Where.i0 - s_WasI, movedK = p_Where.k0 - s_WasK, left = s_Left, back = s_Back * s_Place, new = s_New,
		room = p_Where.room, held = s_Held }
end

-- how much the smoke grows (m) and thins out (of its thickness) before it is written again: a centimetre and half a percent with
-- VOLUME.SMOOTH (every frame or so: no jumps), a tenth of a metre and two percent without
function Vol.GrowStep()
	return VOLUME.SMOOTH and 0.01 or 0.1
end

function Vol.ClearStep()
	return VOLUME.SMOOTH and 0.005 or 0.02
end

-- how far along its way the smoke of p_Room grows: as far as the farthest place it flowed to (VOLUME.FLOW), else VOLUME.RADIUS
function Vol.Spreads(p_Room)
	if VOLUME.FLOW and p_Room ~= nil and p_Room.farthest ~= nil then
		return p_Room.farthest
	end

	return VOLUME.RADIUS
end

-- the layers a room drawn as the volume is measured in: as many as fit floor to ceiling where the canister lies, ROOM_CELL high or a
-- little less (a 3.5 m room: 3 of 1.17 m, the top one ending at the ceiling), Vol.NY at most (a higher room: higher layers)
function Vol.Layer(p_Height)
	return p_Height / math.max(1, math.min(Vol.NY, math.ceil(p_Height / ROOM_CELL - 0.01)))
end

-- the floor under a canister lying at p_At (VOLUME.REAL_FLOOR): where it lies, or -- lying on a table, a counter, a shelf, a bed, a
-- landing, a ramp -- the floor round or below that, up to Vol.DROP lower. Rays straight down from round it (8 ways, Vol.DROP_RINGS
-- out), each from a place a clear ray from just over the canister gets to (no floor of the next room). The floor is the lower of:
--   - the lowest level, facing up, that 3 or more of them meet (a table's or a counter's floor round it);
--   - down a way whose rays met lower ground (stairs, a ramp): followed on from the last of them, Vol.WALK_STEP at a time over it, for
--     as long as the ground goes on down (Vol.WALK_MOST steps at most), the lowest it gets to, once 3 or more of them along that way
--     met lower ground (one or two are a hole, a step).
-- Where it lies if neither. And what the rays met, for the log.
Vol.DROP = 2.5
Vol.DROP_RINGS = { 0.6, 1.2, 1.8, 2.4, 3.0 }
Vol.WALK_STEP = 0.6
Vol.WALK_MOST = 10

function Vol.FloorUnder(p_At)
	if not VOLUME.REAL_FLOOR then
		return p_At, "where it lies"
	end

	local s_Over = p_At + Vec3(0.0, 0.3, 0.0)
	local s_Lower, s_Same, s_Blocked, s_Nothing = {}, 0, 0, 0
	-- each way's lower ground: how many rays met it, the lowest, and where the farthest of them met it
	local s_Ways = {}

	for l_Way = 0, 7 do
		s_Ways[l_Way] = { count = 0 }
	end

	for _, l_Ring in ipairs(Vol.DROP_RINGS) do
		for l_Way = 0, 7 do
			local l_Angle = l_Way * math.pi * 0.25
			local l_From = s_Over + Vec3(math.cos(l_Angle) * l_Ring, 0.0, math.sin(l_Angle) * l_Ring)

			if RaycastManager:Raycast(s_Over, l_From, RAY_FLAGS) == nil then
				local l_Hit = RaycastManager:Raycast(l_From, l_From - Vec3(0.0, Vol.DROP + 0.3, 0.0), RAY_FLAGS)

				if l_Hit == nil or l_Hit.normal.y <= 0.5 then
					s_Nothing = s_Nothing + 1
				elseif l_Hit.position.y < p_At.y - 0.2 then
					s_Lower[#s_Lower + 1] = l_Hit.position.y
					local l_Chain = s_Ways[l_Way]
					l_Chain.count = l_Chain.count + 1
					l_Chain.lowest = math.min(l_Chain.lowest or l_Hit.position.y, l_Hit.position.y)
					l_Chain.last = l_Hit.position
				else
					s_Same = s_Same + 1
				end
			else
				s_Blocked = s_Blocked + 1
			end
		end
	end

	-- the ways down (stairs, a ramp), followed on: a step over the ground (a clear ray half a metre over it), a ray down there; on while
	-- the ground is there, facing up, lower than the canister and no higher than the last (a step up ends it), until it has stayed level
	-- twice (the foot of the stairs)
	local s_Down, s_Walked = nil, 0

	for l_Way = 0, 7 do
		local l_Chain = s_Ways[l_Way]

		if l_Chain.last ~= nil then
			local l_Angle = l_Way * math.pi * 0.25
			local l_Step = Vec3(math.cos(l_Angle) * Vol.WALK_STEP, 0.0, math.sin(l_Angle) * Vol.WALK_STEP)
			local l_At, l_Level = l_Chain.last, 0

			for _ = 1, Vol.WALK_MOST do
				local l_From = l_At + Vec3(0.0, 0.5, 0.0)
				local l_To = l_From + l_Step
				s_Walked = s_Walked + 1

				if RaycastManager:Raycast(l_From, l_To, RAY_FLAGS) ~= nil then
					break
				end

				local l_Hit = RaycastManager:Raycast(l_To, Vec3(l_To.x, p_At.y - Vol.DROP, l_To.z), RAY_FLAGS)

				if l_Hit == nil or l_Hit.normal.y <= 0.5 or l_Hit.position.y >= p_At.y - 0.2 or l_Hit.position.y > l_At.y + 0.05 then
					break
				end

				l_Chain.count = l_Chain.count + 1
				l_Level = l_Hit.position.y < l_Chain.lowest - 0.05 and 0 or l_Level + 1
				l_Chain.lowest = math.min(l_Chain.lowest, l_Hit.position.y)
				l_At = l_Hit.position

				if l_Level >= 2 then
					break
				end
			end

			if l_Chain.count >= 3 and (s_Down == nil or l_Chain.lowest < s_Down) then
				s_Down = l_Chain.lowest
			end
		end
	end

	table.sort(s_Lower)
	local s_Said = string.format("rays down: %d lower, %d at its level, %d nothing under, %d blocked; %d step(s) followed down"
		.. " (lowest %s)", #s_Lower, s_Same, s_Nothing, s_Blocked, s_Walked,
		s_Down ~= nil and string.format("%.2f m under it", p_At.y - s_Down) or "none")
	local s_Base = nil

	for l_Index, l_Level in ipairs(s_Lower) do
		local l_Count = 0

		for l_Other = l_Index, #s_Lower do
			if s_Lower[l_Other] <= l_Level + 0.15 then
				l_Count = l_Count + 1
			end
		end

		if l_Count >= 3 then
			s_Base = l_Level
			break
		end
	end

	if s_Down ~= nil and (s_Base == nil or s_Down < s_Base) then
		s_Base = s_Down
	end

	if s_Base ~= nil then
		return Vec3(p_At.x, s_Base, p_At.z), s_Said
	end

	return p_At, s_Said
end

-- how much of the place round a canister lying at p_At under a ceiling (at p_Ceiling) has the sky over it: places on rings round it
-- (Vol.SHARE_RINGS out, 8 ways), Vol.SHARE_UP over it (under that ceiling), each got to by a clear ray from there and looked up from as
-- the room's points are (VOLUME.UNDER_ROOF: up to ROOM_CEILING over the ceiling): the share of those got to with the sky over them, how
-- many were got to, and how many of them have it
Vol.SHARE_RINGS = { 1.5, 3.0, 4.5 }
Vol.SHARE_UP = 1.2                    -- (through a window at the height of most: a sill under it)
Vol.SHARE_FEWEST = 4                  -- fewer places got to than this (a cupboard, a duct): it stays where its ceiling says

function Vol.OpenShare(p_At, p_Ceiling)
	local s_Over = p_At + Vec3(0.0, math.max(0.1, math.min(Vol.SHARE_UP, p_Ceiling - p_At.y - 0.3)), 0.0)
	local s_Reached, s_Sky = 0, 0

	for _, l_Ring in ipairs(Vol.SHARE_RINGS) do
		for l_Way = 0, 7 do
			local l_Angle = l_Way * math.pi * 0.25
			local l_To = s_Over + Vec3(math.cos(l_Angle) * l_Ring, 0.0, math.sin(l_Angle) * l_Ring)

			if RaycastManager:Raycast(s_Over, l_To, RAY_FLAGS) == nil then
				s_Reached = s_Reached + 1

				if RaycastManager:Raycast(l_To, Vec3(l_To.x, math.max(l_To.y, p_Ceiling) + ROOM_CEILING, l_To.z), RAY_FLAGS) == nil then
					s_Sky = s_Sky + 1
				end
			end
		end
	end

	return s_Reached > 0 and s_Sky / s_Reached or 0.0, s_Reached, s_Sky
end

-- whether a room measured now would be drawn as the volume (on, its bundle and environment in, none drawn yet)
function Vol.Free()
	return VOLUME.ON and Vol.data ~= nil and Vol.env ~= nil and Vol.now == nil
end

-- whether the volume can be drawn at all (on, its bundle and environment in)
function Vol.Ready()
	return VOLUME.ON and Vol.data ~= nil and Vol.env ~= nil
end

-- whether a room measured now would be drawn as a volume: the volume (free), or one of its own (VOLUME.OTHERS)
function Vol.WillDraw()
	return Vol.Free() or (VOLUME.OTHERS and Vol.Ready())
end

-- why not, for the log
function Vol.WhyNot()
	if not VOLUME.ON then
		return "the volume is turned off"
	elseif Vol.data == nil then
		return "its bundle is not in"
	elseif Vol.env == nil then
		return "its environment was not made"
	elseif Vol.now ~= nil then
		local s_Down = type(Vol.now.down) == "table" and Vol.now.down or {}
		return string.format("it draws smoke %s's room, %s s into its life", tostring(s_Down.logged or "(not logged)"),
			type(s_Down.age) == "number" and string.format("%.0f", s_Down.age) or "?")
	end

	return "it is free"
end

-- how far the nearest surface is from p_From along p_Way, up to p_Length
function Vol.Gap(p_From, p_Way, p_Length)
	local s_Hit = RaycastManager:Raycast(p_From, p_From + p_Way * p_Length, RAY_FLAGS)

	if s_Hit == nil then
		return p_Length
	end

	local s_To = s_Hit.position - p_From
	return math.sqrt(Dot(s_To, s_To))
end

-- a point's room up and down (to the ceiling, to the floor: a layer each way), added to its gaps along the floor (a cell each way); and,
-- on each side but the floor where something was met, whether it fills the side -- a wall, the ceiling: four more rays, from near the
-- side's corners, all meet something as near -- or is only part of something -- a counter's edge, a hood, a pillar: the smoke goes on
-- past it, whatever stands in it the depth hides -- (p_Gaps.part). The corners' rays start 0.35 of the cell in from the side's middle
-- each way, or short of a wall found nearer that way (in the room: one started past a wall meets nothing and would call a wall part
-- of something). With VOLUME.THIN_WALLS, what the other corners met must also be solid as far as the box reaches (a ray back from
-- there meets nothing short of it): a wall with room behind it within that -- beside a door, round a hatch or a window, whatever the
-- corner got through -- is no part of something, the side is cut at it (else the box would reach into the room behind). How many rays
-- it took.
Vol.WAYS = { px = { 1, 0, 0 }, nx = { -1, 0, 0 }, pz = { 0, 0, 1 }, nz = { 0, 0, -1 }, up = { 0, 1, 0 } }
-- a side's two ways across it: the axis (as a unit vector), the gaps that bound it either way, the cell's size along it (true: a layer)
Vol.ACROSS = {
	px = { { Vec3(0.0, 1.0, 0.0), "up", "down", true }, { Vec3(0.0, 0.0, 1.0), "pz", "nz", false } },
	nx = { { Vec3(0.0, 1.0, 0.0), "up", "down", true }, { Vec3(0.0, 0.0, 1.0), "pz", "nz", false } },
	pz = { { Vec3(1.0, 0.0, 0.0), "px", "nx", false }, { Vec3(0.0, 1.0, 0.0), "up", "down", true } },
	nz = { { Vec3(1.0, 0.0, 0.0), "px", "nx", false }, { Vec3(0.0, 1.0, 0.0), "up", "down", true } },
	up = { { Vec3(1.0, 0.0, 0.0), "px", "nx", false }, { Vec3(0.0, 0.0, 1.0), "pz", "nz", false } },
}

-- how far across from a side's middle a corner's ray may start, along one way across it (p_Across, of Vol.ACROSS) and sign
function Vol.CornerOff(p_Gaps, p_Across, p_Sign, p_Layer)
	local s_Gap = p_Gaps[p_Sign > 0 and p_Across[2] or p_Across[3]] or 0.0
	return p_Across[1] * (p_Sign * math.max(0.0, math.min((p_Across[4] and p_Layer or ROOM_CELL) * 0.35, s_Gap - 0.05)))
end

function Vol.Gaps(p_Gaps, p_At, p_Layer)
	p_Gaps.up = Vol.Gap(p_At, Vec3(0.0, 1.0, 0.0), p_Layer)
	p_Gaps.down = Vol.Gap(p_At, Vec3(0.0, -1.0, 0.0), p_Layer)
	p_Gaps.part = {}
	local s_Rays = 2

	local function Off(p_Across, p_Sign)
		return Vol.CornerOff(p_Gaps, p_Across, p_Sign, p_Layer)
	end

	for l_Name, l_Way in pairs(Vol.WAYS) do
		local l_Far = l_Name == "up" and p_Layer or ROOM_CELL

		if p_Gaps[l_Name] ~= nil and p_Gaps[l_Name] < l_Far - 0.001 then
			local l_A, l_B = Vol.ACROSS[l_Name][1], Vol.ACROSS[l_Name][2]
			local l_Dir = Vec3(l_Way[1], l_Way[2], l_Way[3])
			local l_Hits = {}

			for _, l_Signs in ipairs({ { 1, 1 }, { 1, -1 }, { -1, 1 }, { -1, -1 } }) do
				local l_From = p_At + Off(l_A, l_Signs[1]) + Off(l_B, l_Signs[2])
				local l_Gap = Vol.Gap(l_From, l_Dir, l_Far)
				s_Rays = s_Rays + 1

				if l_Gap >= l_Far - 0.001 then
					p_Gaps.part[l_Name] = true

					if not VOLUME.THIN_WALLS then
						break
					end
				else
					p_Gaps[l_Name] = math.min(p_Gaps[l_Name], l_Gap)
					l_Hits[#l_Hits + 1] = { from = l_From, gap = l_Gap }
				end
			end

			-- what a corner met short of where the box ends (half its place): solid up to there, or room behind it (a ray back from
			-- there meets its far side more than 5 cm off)
			if VOLUME.THIN_WALLS and p_Gaps.part[l_Name] then
				local l_Half = l_Far * 0.5

				for _, l_Hit in ipairs(l_Hits) do
					if l_Hit.gap < l_Half - 0.05 then
						local l_Back = Vol.Gap(l_Hit.from + l_Dir * l_Half, l_Dir * -1.0, l_Half - l_Hit.gap)
						s_Rays = s_Rays + 1

						if l_Back < l_Half - l_Hit.gap - 0.001 and l_Back > 0.05 then
							p_Gaps.part[l_Name] = nil
							break
						end
					end
				end
			end
		end
	end

	return s_Rays
end

-- a point's side (p_Name, along the floor) towards a neighbour left out as outdoors (VOLUME.UNDER_ROOF): its middle ray went out through
-- the door there, so its corners were never looked at; one of them meeting the wall beside the door within a cell cuts the side at it
-- (else the box would reach out past that wall, into the open). How many rays it took.
function Vol.CloseSide(p_Cell, p_Name, p_Layer)
	local s_Gaps = p_Cell.gaps

	if s_Gaps == nil or p_Name == nil then
		return 0
	end

	local s_Way = Vol.WAYS[p_Name]
	local s_Dir = Vec3(s_Way[1], s_Way[2], s_Way[3])
	local s_A, s_B = Vol.ACROSS[p_Name][1], Vol.ACROSS[p_Name][2]
	local s_Near, s_Rays = nil, 0

	for _, l_Signs in ipairs({ { 1, 1 }, { 1, -1 }, { -1, 1 }, { -1, -1 } }) do
		local l_From = p_Cell.at + Vol.CornerOff(s_Gaps, s_A, l_Signs[1], p_Layer) + Vol.CornerOff(s_Gaps, s_B, l_Signs[2], p_Layer)
		local l_Gap = Vol.Gap(l_From, s_Dir, ROOM_CELL)
		s_Rays = s_Rays + 1

		if l_Gap < ROOM_CELL - 0.001 then
			s_Near = math.min(s_Near or l_Gap, l_Gap)
		end
	end

	if s_Near ~= nil then
		s_Gaps[p_Name] = math.min(s_Gaps[p_Name] or ROOM_CELL, s_Near)

		if s_Gaps.part ~= nil then
			s_Gaps.part[p_Name] = nil
		end
	end

	return s_Rays
end

-- the room's spread along the floor (in cells) still within the volume's grid with a point at (p_I, p_K) added; and adding it
function Vol.Fits(p_Spread, p_I, p_K)
	return math.max(p_Spread.maxI, p_I) - math.min(p_Spread.minI, p_I) < Vol.NX
		and math.max(p_Spread.maxK, p_K) - math.min(p_Spread.minK, p_K) < Vol.NZ
end

-- whether the room's grid holds a place at p_I, p_K: within its spread so far, or -- a second canister poured into it, VOLUME.MERGE --
-- within the grid where it was moved over to take in both (p_Room.window)
function Vol.FitsRoom(p_Room, p_I, p_K)
	local s_W = p_Room.window

	if s_W ~= nil then
		return p_I >= s_W.i0 and p_I < s_W.i0 + Vol.NX and p_K >= s_W.k0 and p_K < s_W.k0 + Vol.NZ
	end

	return Vol.Fits(p_Room.spread, p_I, p_K)
end

-- the grid's corner place (its lowest i and k) for a room filling over time: round its spread, centred; or where it was moved over
-- to take in a second canister (VOLUME.MERGE)
function Vol.SimCorner(p_Room)
	if p_Room.window ~= nil then
		return p_Room.window.i0, p_Room.window.k0
	end

	local s_Spread = p_Room.spread
	return s_Spread.minI - math.floor((Vol.NX - 1 - (s_Spread.maxI - s_Spread.minI)) / 2),
		s_Spread.minK - math.floor((Vol.NZ - 1 - (s_Spread.maxK - s_Spread.minK)) / 2)
end

function Vol.Spread(p_Spread, p_I, p_K)
	p_Spread.minI, p_Spread.maxI = math.min(p_Spread.minI, p_I), math.max(p_Spread.maxI, p_I)
	p_Spread.minK, p_Spread.maxK = math.min(p_Spread.minK, p_K), math.max(p_Spread.maxK, p_K)
end

function Vol.MakeEnv()
	local s_Logic = LogicVisualEnvironmentEntityData(Guid(Vol.GUIDS .. "01"))
	local s_Blueprint = VisualEnvironmentBlueprint(Guid(Vol.GUIDS .. "02"))
	local s_Environment = VisualEnvironmentEntityData(Guid(Vol.GUIDS .. "03"))

	s_Blueprint.name = "FX/TacticalSlots/VE_M18_Smoke_Volume"
	s_Blueprint.object = s_Environment
	s_Logic.visualEnvironment = s_Blueprint
	s_Logic.visibility = 1.0
	s_Environment.enabled = true
	s_Environment.priority = Vol.PRIORITY
	s_Environment.visibility = 1.0

	local s_Params = {}

	for l_Index, l_Name in ipairs(Vol.PARAMS) do
		local l_Param = ShaderParamsComponentData(Guid(Vol.GUIDS .. string.format("%02X", 3 + l_Index)))
		l_Param.excluded = false
		l_Param.isEventConnectionTarget = 3
		l_Param.isPropertyConnectionTarget = 3
		l_Param.indexInBlueprint = l_Index - 1
		l_Param.transform = LinearTransform()
		l_Param.parameterName = l_Name
		l_Param.value = Vec4(0.0, 0.0, 0.0, 0.0)
		s_Environment.components:add(l_Param)
		s_Params[#s_Params + 1] = l_Param
	end

	s_Environment.runtimeComponentCount = #s_Params

	local s_Entity = EntityManager:CreateEntity(s_Logic, LinearTransform())

	if s_Entity == nil then
		return nil
	end

	s_Entity:Init(Realm.Realm_Client, true)
	s_Entity:FireEvent("Enable")
	VisualEnvironmentManager:SetDirty(true)

	return { entity = s_Entity, logic = s_Logic, blueprint = s_Blueprint, environment = s_Environment, params = s_Params, found = false }
end

-- the volume's numbers into its environment's state (p_Values: parameter name -> Vec4); false while the state is not up yet
function Vol.SetParams(p_Values)
	if Vol.env == nil then
		return false
	end

	local s_State = nil

	for _, l_State in pairs(VisualEnvironmentManager:GetStates()) do
		if l_State.priority == Vol.PRIORITY or l_State.priority == 10000000 + Vol.PRIORITY then
			s_State = l_State
			break
		end
	end

	if s_State == nil then
		Vol.env.tries = (Vol.env.tries or 0) + 1

		if Vol.env.tries == 300 then
			LOG(string.format("⛔ the smoke's volume: no visual environment state with priority %d came up -- its numbers do not reach it",
				Vol.PRIORITY))
		end

		return false
	end

	local s_Written = 0

	for _, l_Param in pairs(s_State.shaderParams) do
		local l_Value = p_Values[l_Param.parameterName]

		if l_Value ~= nil then
			l_Param.value = l_Value
			s_Written = s_Written + 1
		end
	end

	VisualEnvironmentManager:SetDirty(true)

	-- once: what the state carries, and whether a written number reads back (a copy would not keep it)
	if not Vol.env.found then
		Vol.env.found = true
		local s_Names, s_Back = {}, "not read"

		for _, l_Param in pairs(s_State.shaderParams) do
			s_Names[#s_Names + 1] = tostring(l_Param.parameterName)

			if p_Values[l_Param.parameterName] ~= nil and s_Back == "not read" then
				local l_Want = p_Values[l_Param.parameterName]
				s_Back = (l_Param.value.x == l_Want.x and l_Param.value.w == l_Want.w) and "reads back" or "does NOT read back"
			end
		end

		LOG(string.format("the smoke's volume numbers: state priority %d with %d shader parameter(s) [%s], %d written, a written one %s",
			s_State.priority, #s_Names, table.concat(s_Names, ", "), s_Written, s_Back))
	end

	return true
end

-- the six sides of a point, towards its neighbours (i, j, k)
Vol.SIDES = { px = { 1, 0, 0 }, nx = { -1, 0, 0 }, up = { 0, 1, 0 }, down = { 0, -1, 0 }, pz = { 0, 0, 1 }, nz = { 0, 0, -1 } }

-- a point's box: its place in the grid (ROOM_CELL across, the room's layer high). On a side where the room has a point of its own the
-- box reaches it whole (the smoke goes on: whatever stands in between, a pillar, a crate's edge, the depth hides); on one where it has
-- none, it ends at whatever the measuring found there within a cell (along the floor) or a layer (up, down): short of its place's
-- edge, or past it, up to the wall, the ceiling, the floor (the next place, behind it, is no point of the room: nothing else fills that
-- strip). No smoke shows past a wall. Its extents, its point, and the sides something cut (p_Has: whether the room has a point at i, j, k).
function Vol.Box(p_Room, p_Cell, p_Has)
	local s_Half, s_Layer, s_Gaps = ROOM_CELL * 0.5, p_Room.layer, p_Cell.gaps or {}
	local s_X = p_Room.floor.x + p_Cell.i * ROOM_CELL
	local s_Y = p_Room.floor.y + s_Layer * (0.5 + p_Cell.j)
	local s_Z = p_Room.floor.z + p_Cell.k * ROOM_CELL
	local s_Cut = {}

	-- how far it reaches on the side p_Name: p_Whole where the room goes on or nothing is in the way within p_Far, else to what is.
	-- Where the room goes on past something solid across the whole side within that half (a wall, a floor: the room's point on its
	-- other side got to round it), to that (VOLUME.CUT_THROUGH; else whole: the box would reach through it)
	local function Reach(p_Name, p_Whole, p_Far)
		local l_Step = Vol.SIDES[p_Name]
		local l_Gap = s_Gaps[p_Name]

		if l_Gap == nil or l_Gap >= p_Far - 0.001 or (s_Gaps.part ~= nil and s_Gaps.part[p_Name]) then
			return p_Whole
		end

		if p_Has(p_Cell.i + l_Step[1], p_Cell.j + l_Step[2], p_Cell.k + l_Step[3])
			and (not VOLUME.CUT_THROUGH or l_Gap >= p_Whole - 0.001) then
			return p_Whole
		end

		s_Cut[p_Name] = true
		return l_Gap
	end

	return { x0 = s_X - Reach("nx", s_Half, ROOM_CELL), x1 = s_X + Reach("px", s_Half, ROOM_CELL),
		y0 = s_Y - Reach("down", s_Layer * 0.5, s_Layer), y1 = s_Y + Reach("up", s_Layer * 0.5, s_Layer),
		z0 = s_Z - Reach("nz", s_Half, ROOM_CELL), z1 = s_Z + Reach("pz", s_Half, ROOM_CELL), cell = p_Cell, cut = s_Cut }
end

-- the grid the shader smooths the room over: Vol.NX x Vol.NY x Vol.NZ cells (ROOM_CELL across, the room's layer high) round the room's
-- spread, centred, from its floor up, one bit a cell, 24 bits to a number (exact in a float). A cell is set where the room has a point,
-- and where something cut a point's box towards it: the far side of a wall, of the ceiling, reads as smoke to the shader's smoothing,
-- so the smoke stays thick up to it (its box ends there: none shows past it) -- unless another point reaches that cell with nothing in
-- between (then it is the smoke's open edge, where it thins out to nothing). Under the grid the shader reads its first layer on (the
-- floor). Its low corner, the numbers, how many cells were set for a wall, and how many points it could not hold. p_Points: the
-- room's points alone, no wall's far side (the one box: the shader keeps the smoke off the walls' far side by itself, and reads a cell
-- set as the room's own smoke). p_Within: only the points the smoke has got to by then (their path no longer than this; nil: all).
function Vol.Grid(p_Room, p_Boxes, p_Points, p_Within)
	local s_Spread = p_Room.spread
	local s_I0 = s_Spread.minI - math.floor((Vol.NX - 1 - (s_Spread.maxI - s_Spread.minI)) / 2)
	local s_K0 = s_Spread.minK - math.floor((Vol.NZ - 1 - (s_Spread.maxK - s_Spread.minK)) / 2)
	local s_Set, s_Wall, s_Open = {}, {}, {}

	for _, l_Box in ipairs(p_Boxes) do
		s_Set[l_Box.cell.i .. "," .. l_Box.cell.j .. "," .. l_Box.cell.k] = { l_Box.cell.i, l_Box.cell.j, l_Box.cell.k, l_Box.cell }
	end

	for _, l_Box in ipairs(p_Boxes) do
		for l_Name, l_Step in pairs(Vol.SIDES) do
			local l_Place = { l_Box.cell.i + l_Step[1], l_Box.cell.j + l_Step[2], l_Box.cell.k + l_Step[3] }
			local l_Key = l_Place[1] .. "," .. l_Place[2] .. "," .. l_Place[3]

			if s_Set[l_Key] == nil and not p_Points then
				if l_Box.cut[l_Name] then
					s_Wall[l_Key] = l_Place
				else
					s_Open[l_Key] = true
				end
			end
		end
	end

	-- 24 cells a number, 4 numbers a parameter (the last ones left empty)
	local s_Words = {}

	for i = 1, math.ceil(Vol.NX * Vol.NY * Vol.NZ / 96) * 4 do
		s_Words[i] = 0
	end

	local s_Walls, s_Off = 0, 0

	local function Set(p_Place)
		local l_X, l_Y, l_Z = p_Place[1] - s_I0, p_Place[2], p_Place[3] - s_K0

		if l_X < 0 or l_X >= Vol.NX or l_Y < 0 or l_Y >= Vol.NY or l_Z < 0 or l_Z >= Vol.NZ then
			return false
		end

		local l_Index = (l_Y * Vol.NZ + l_Z) * Vol.NX + l_X
		local l_Word = math.floor(l_Index / 24) + 1
		s_Words[l_Word] = s_Words[l_Word] + 2 ^ (l_Index % 24)
		return true
	end

	for _, l_Place in pairs(s_Set) do
		local l_There = p_Within == nil or (l_Place[4].path or 0.0) <= p_Within

		if l_There and not Set(l_Place) then
			s_Off = s_Off + 1
		end
	end

	for l_Key, l_Place in pairs(s_Wall) do
		if not s_Open[l_Key] and Set(l_Place) then
			s_Walls = s_Walls + 1
		end
	end

	return Vec3(p_Room.floor.x + (s_I0 - 0.5) * ROOM_CELL, p_Room.floor.y, p_Room.floor.z + (s_K0 - 0.5) * ROOM_CELL), s_Words, s_Walls,
		s_Off
end

-- boxes side by side of one size across joined into one, along x, then z, then up: the room's inside ends up a few big boxes (the ones
-- a wall cut stay apart where they differ). Fewer to draw, and the shader marches a view through one box where it went through many.
function Vol.Merge(p_Boxes)
	local s_Boxes = {}

	for l_Index, l_Box in ipairs(p_Boxes) do
		s_Boxes[l_Index] = { x0 = l_Box.x0, x1 = l_Box.x1, y0 = l_Box.y0, y1 = l_Box.y1, z0 = l_Box.z0, z1 = l_Box.z1 }
	end

	local function Mm(p_V)
		return math.floor(p_V * 1000.0 + 0.5)
	end

	-- twice round: a join along one axis can line boxes up for another
	for _, l_Axis in ipairs({ { "x0", "x1", "y0", "y1", "z0", "z1" }, { "z0", "z1", "x0", "x1", "y0", "y1" },
		{ "y0", "y1", "x0", "x1", "z0", "z1" }, { "x0", "x1", "y0", "y1", "z0", "z1" }, { "z0", "z1", "x0", "x1", "y0", "y1" },
		{ "y0", "y1", "x0", "x1", "z0", "z1" } }) do
		-- along this axis (its first two): sorted by the other extents, then where they start; one joins the one before it if it starts
		-- where that one ends and matches it across
		local l_Order = { l_Axis[3], l_Axis[4], l_Axis[5], l_Axis[6], l_Axis[1] }

		table.sort(s_Boxes, function(p_A, p_B)
			for _, l_Name in ipairs(l_Order) do
				if Mm(p_A[l_Name]) ~= Mm(p_B[l_Name]) then
					return Mm(p_A[l_Name]) < Mm(p_B[l_Name])
				end
			end

			return false
		end)

		local l_Joined = {}

		for _, l_Box in ipairs(s_Boxes) do
			local l_Last = l_Joined[#l_Joined]

			if l_Last ~= nil and Mm(l_Last[l_Axis[3]]) == Mm(l_Box[l_Axis[3]]) and Mm(l_Last[l_Axis[4]]) == Mm(l_Box[l_Axis[4]])
				and Mm(l_Last[l_Axis[5]]) == Mm(l_Box[l_Axis[5]]) and Mm(l_Last[l_Axis[6]]) == Mm(l_Box[l_Axis[6]])
				and Mm(l_Last[l_Axis[2]]) == Mm(l_Box[l_Axis[1]]) then
				l_Last[l_Axis[2]] = l_Box[l_Axis[2]]
			else
				l_Joined[#l_Joined + 1] = l_Box
			end
		end

		s_Boxes = l_Joined
	end

	return s_Boxes
end

-- A box reaching past its place's edge (up to a wall) may run into another box (two of them reaching into the same place round a
-- corner, a door's jamb): there the smoke would count twice. Such a box is drawn back to its place's edge on the sides that run into
-- the other. How many sides were drawn back.
function Vol.Unlap(p_Room, p_Boxes)
	local s_Half, s_Layer, s_Back = ROOM_CELL * 0.5, p_Room.layer, 0

	local function Over(p_A, p_B)
		return math.min(p_A.x1, p_B.x1) - math.max(p_A.x0, p_B.x0) > 0.001 and math.min(p_A.y1, p_B.y1) - math.max(p_A.y0, p_B.y0) > 0.001
			and math.min(p_A.z1, p_B.z1) - math.max(p_A.z0, p_B.z0) > 0.001
	end

	for _, l_Box in ipairs(p_Boxes) do
		local l_Cell = l_Box.cell
		local l_X = p_Room.floor.x + l_Cell.i * ROOM_CELL
		local l_Y = p_Room.floor.y + s_Layer * (0.5 + l_Cell.j)
		local l_Z = p_Room.floor.z + l_Cell.k * ROOM_CELL
		-- its place's edges, side by side with the fields they bound
		local l_Edges = { { "x0", l_X - s_Half, -1 }, { "x1", l_X + s_Half, 1 }, { "y0", l_Y - s_Layer * 0.5, -1 },
			{ "y1", l_Y + s_Layer * 0.5, 1 }, { "z0", l_Z - s_Half, -1 }, { "z1", l_Z + s_Half, 1 } }

		for _, l_Other in ipairs(p_Boxes) do
			if l_Other ~= l_Box and math.abs(l_Other.cell.i - l_Cell.i) <= 2 and math.abs(l_Other.cell.j - l_Cell.j) <= 2
				and math.abs(l_Other.cell.k - l_Cell.k) <= 2 and Over(l_Box, l_Other) then
				for _, l_Edge in ipairs(l_Edges) do
					local l_Field, l_At, l_Way = l_Edge[1], l_Edge[2], l_Edge[3]

					if (l_Box[l_Field] - l_At) * l_Way > 0.001 then
						-- the part past this edge
						local l_Past = { x0 = l_Box.x0, x1 = l_Box.x1, y0 = l_Box.y0, y1 = l_Box.y1, z0 = l_Box.z0, z1 = l_Box.z1 }
						l_Past[l_Way < 0 and (l_Field:sub(1, 1) .. "1") or (l_Field:sub(1, 1) .. "0")] = l_At

						if Over(l_Past, l_Other) then
							l_Box[l_Field] = l_At
							s_Back = s_Back + 1
						end
					end
				end
			end
		end
	end

	return s_Back
end

-- the volume of a room measured for it: a box a point, the grid's numbers, the boxes joined, and the one box round them all: a side of
-- it on the walls round the room (the points' boxes are cut to them), or, where one of the points' boxes on it is open (nothing cut
-- it there), half a cell further out (room for the smoke's soft edge past its last points)
Vol.BOUND_SIDES = { { "x0", "nx", -1 }, { "x1", "px", 1 }, { "y0", "down", -1 }, { "y1", "up", 1 }, { "z0", "nz", -1 },
	{ "z1", "pz", 1 } }

function Vol.Plan(p_Room)
	local s_Set = {}

	for _, l_Cell in ipairs(p_Room.cells) do
		s_Set[l_Cell.i .. "," .. l_Cell.j .. "," .. l_Cell.k] = true
	end

	local function Has(p_I, p_J, p_K)
		return s_Set[p_I .. "," .. p_J .. "," .. p_K] == true
	end

	local s_Boxes = {}

	for _, l_Cell in ipairs(p_Room.cells) do
		s_Boxes[#s_Boxes + 1] = Vol.Box(p_Room, l_Cell, Has)
	end

	-- and the places out of its openings to the open (VOLUME.EXITS), its points as well from here on (not the room's main space:
	-- Vol.MainBox leaves them out)
	for _, l_Cell in ipairs(Vol.ExitCells(p_Room)) do
		s_Boxes[#s_Boxes + 1] = Vol.Box(p_Room, l_Cell, Has)
	end

	local s_Back = Vol.Unlap(p_Room, s_Boxes)
	local s_Origin, s_Words, s_Walls, s_Off = Vol.Grid(p_Room, s_Boxes, VOLUME.ONE_WRITER)
	local s_Bound = { x0 = math.huge, y0 = math.huge, z0 = math.huge, x1 = -math.huge, y1 = -math.huge, z1 = -math.huge }

	for _, l_Box in ipairs(s_Boxes) do
		s_Bound.x0, s_Bound.y0, s_Bound.z0 = math.min(s_Bound.x0, l_Box.x0), math.min(s_Bound.y0, l_Box.y0), math.min(s_Bound.z0, l_Box.z0)
		s_Bound.x1, s_Bound.y1, s_Bound.z1 = math.max(s_Bound.x1, l_Box.x1), math.max(s_Bound.y1, l_Box.y1), math.max(s_Bound.z1, l_Box.z1)
	end

	local s_Open = {}

	-- (the places out of the room's openings never take its top or bottom further: over its ceiling may be a room upstairs)
	for _, l_Side in ipairs(Vol.BOUND_SIDES) do
		for _, l_Box in ipairs(s_Boxes) do
			if math.abs(l_Box[l_Side[1]] - s_Bound[l_Side[1]]) < 0.001 and not l_Box.cut[l_Side[2]]
				and not (l_Box.cell.exit and l_Side[1]:sub(1, 1) == "y") then
				s_Open[l_Side[1]] = true
				break
			end
		end
	end

	s_Bound.open = {}

	-- (a cloud in the open: its top is its own ceiling, where it has thinned out to nothing -- the shader thins it out under the box's
	-- top; and a room's smoke that flows, VOLUME.FLOW, never takes the box over the room's ceiling either: over it may be a room
	-- upstairs, a roof)
	for _, l_Side in ipairs(Vol.BOUND_SIDES) do
		if s_Open[l_Side[1]] and not ((p_Room.outside or VOLUME.FLOW) and l_Side[1] == "y1") then
			s_Bound[l_Side[1]] = s_Bound[l_Side[1]] + l_Side[3] * (l_Side[1]:sub(1, 1) == "y" and p_Room.layer or ROOM_CELL) * 0.5
			s_Bound.open[#s_Bound.open + 1] = l_Side[2]
		end
	end

	return { boxes = s_Boxes, joined = Vol.Merge(s_Boxes), origin = s_Origin, words = s_Words, walls = s_Walls, off = s_Off,
		back = s_Back, bound = s_Bound }
end

-- How deep the camera (p_At) is in the volume's smoke, 0 to 1, p_Age seconds into its canister's life (for the fog over the view): in
-- one of its points' boxes (cut to the walls: never on the far side of one, as the smoke drawn) where the smoke drawn is -- its point
-- held by the grid by then (Vol.Frame's own reach along the way, Vol.Path) and the camera within the shader's front, straight from the
-- mouth -- once the smoke has got there and thickened over ROOM_FOG_RISE; thinning out as the smoke does. A box of a point the smoke
-- drawn never gets to (round a wall, farther along its way than it spreads) is no smoke to be in, however near it is.
Vol.FRONT = 1.0 -- the shader's growing front thins out over its last this (m)

-- how far p is from a mouth as the growing front counts it (its height VOLUME.TALL of its spread along the floor), as the shader does
function Vol.FrontDistance(p_At, p_Mouth)
	local s_Way = p_At - p_Mouth
	local s_Up = s_Way.y * Vol.Tall()
	return math.sqrt(s_Way.x * s_Way.x + s_Up * s_Up + s_Way.z * s_Way.z)
end

-- (in 63rds, as the shader gets it)
function Vol.Tall()
	return math.max(1, math.floor(math.max(0.01, math.min(1.0, VOLUME.TALL or 1.0)) * 63.0 + 0.5)) / 63.0
end

-- the shader's mode word (TsSmokeC.w, whole numbers): the mode (3 bits), the front's height (6 bits, in 63rds), how open the two
-- bullets' holes are (7 bits each, Vol.holeBits) and, its top bit, the camera near the smoke (Vol.nearBit: the cheaper march)
function Vol.ModeWord(p_Mode)
	return p_Mode + 8 * math.floor(Vol.Tall() * 63.0 + 0.5) + (Vol.holeBits or 0) + (Vol.nearBit or 0)
end

-- whether p_At (the camera) is in the smoke drawn or within VOLUME.NEAR_QUALITY of it: of the room's volume's points' boxes, or a
-- volume of its own's box (VOLUME.NEAR_QUALITY 0: never)
Vol.NEAR_BIT = 8388608

function Vol.Near(p_At)
	local s_Far = VOLUME.NEAR_QUALITY or 0.0

	if p_At == nil or s_Far <= 0.0 then
		return false
	end

	local function In(p_B)
		return p_At.x > p_B.x0 - s_Far and p_At.x < p_B.x1 + s_Far and p_At.y > p_B.y0 - s_Far and p_At.y < p_B.y1 + s_Far
			and p_At.z > p_B.z0 - s_Far and p_At.z < p_B.z1 + s_Far
	end

	if Vol.now ~= nil and type(Vol.now.cells) == "table" then
		for _, l_Box in ipairs(Vol.now.cells) do
			if In(l_Box) then
				return true
			end
		end
	end

	for _, l_Other in ipairs(Vol.others or {}) do
		if not l_Other.gone and l_Other.box ~= nil and In(l_Other.box) then
			return true
		end
	end

	return false
end

-- the smoke's look, packed 8 bits a number into two whole numbers (TsSmokeC.y and z): the albedo, the billows' frequency (in
-- hundredths) and the open edge; the erosion, the shadow and the grid's cell across (0.5 m and hundredths over, 7 bits: up to 1.77 m)
-- -- and over it whether the side cut is off (VOLUME.SIDE false)
function Vol.Look()
	local function Byte(p_V)
		return math.max(0, math.min(255, math.floor(p_V + 0.5)))
	end

	return Byte(VOLUME.ALBEDO * 255.0) + 256 * Byte(VOLUME.NOISE * 100.0) + 65536 * Byte(VOLUME.EDGE * 255.0),
		Byte(VOLUME.EROSION * 255.0) + 256 * Byte(VOLUME.SHADOW * 255.0) + 65536 * math.min(127, Byte((ROOM_CELL - 0.5) * 100.0))
			+ (VOLUME.SIDE == false and 8388608 or 0)
end

function Vol.FogAt(p_Room, p_Age, p_At)
	if Vol.now == nil or Vol.now.down.room ~= p_Room or p_Room.ready == nil then
		return 0.0
	end

	if Vol.now.sim then
		return Vol.SimFog(p_At)
	end

	local s_Grown = math.min(Vol.Grow(p_Room) * math.max(0.0, p_Age - p_Room.ready), Vol.Spreads(p_Room))
	local s_Within = math.min(s_Grown + ROOM_CELL, Vol.Spreads(p_Room) + ROOM_CELL * 0.5)

	for _, l_Box in ipairs(Vol.now.cells) do
		if p_At.x >= l_Box.x0 and p_At.x <= l_Box.x1 and p_At.y >= l_Box.y0 and p_At.y <= l_Box.y1 and p_At.z >= l_Box.z0
			and p_At.z <= l_Box.z1 then
			if not Vol.Sees(l_Box.cell, p_At) or (VOLUME.FOG_DRAWN and (l_Box.cell.path or 0.0) > s_Within) then
				return 0.0
			end

			local l_Far = Vol.FrontDistance(p_At, p_Room.mouth or p_Room.source)
			local l_Front = VOLUME.FOG_DRAWN and math.max(0.0, math.min(1.0, (s_Grown - l_Far) / Vol.FRONT)) or 1.0

			-- (a cloud in the open thins out under its top, heaped or not, as drawn)
			if p_Room.outside and VOLUME.FOG_DRAWN and Vol.now.main ~= nil then
				local l_Top = VOLUME.OUT_ROUND and Vol.HeapTop(p_At, p_Room.mouth or p_Room.source, s_Grown, Vol.now.main.y0, Vol.now.top)
					or Vol.now.top
				l_Front = l_Front * Vol.TopFade(l_Top, p_At)
			end
			local l_There = p_Room.ready + (l_Box.cell.path or 0.0) / Vol.Grow(p_Room)
			return math.max(0.0, math.min(1.0, (p_Age - l_There) / (p_Room.fogRise or ROOM_FOG_RISE))) * l_Front
				* Vol.FogStrength(Vol.now.down, Vol.now.strength)
		end
	end

	return 0.0
end

-- whether p_At (the camera) sees the point of the room p_Cell (VOLUME.CAMERA_RAY): a box reaching past a wall's far side (into a door's
-- jamb, a room the smoke gets to round it) holds no smoke of its point on that side
function Vol.Sees(p_Cell, p_At)
	return not VOLUME.CAMERA_RAY or p_Cell == nil or p_Cell.at == nil or RaycastManager:Raycast(p_Cell.at, p_At, RAY_FLAGS) == nil
end

-- whether p_At (the camera) is in one of the points' boxes (their sides shrunk by a centimetre: on a side two share, in neither) and
-- sees its point; with p_Within, only the box of a point the smoke has got to by then (its path no longer than that: a box the smoke
-- has not reached is no smoke to be in)
function Vol.Inside(p_Boxes, p_At, p_Within)
	for _, l_Box in ipairs(p_Boxes) do
		if p_At.x > l_Box.x0 + 0.01 and p_At.x < l_Box.x1 - 0.01 and p_At.y > l_Box.y0 + 0.01 and p_At.y < l_Box.y1 - 0.01
			and p_At.z > l_Box.z0 + 0.01 and p_At.z < l_Box.z1 - 0.01 then
			return (p_Within == nil or l_Box.cell == nil or (l_Box.cell.path or 0.0) <= p_Within) and Vol.Sees(l_Box.cell, p_At)
		end
	end

	return false
end

-- a smoke open to the sky (a cloud in the open, the smoke out of a room's opening) thins out over its top VOLUME.OUT_TOP: in decimetres,
-- as its box's mark carries it (1 to 63; 0, a box with a ceiling over it)
function Vol.TopDm()
	return math.max(1, math.min(63, math.floor((VOLUME.OUT_TOP or 2.0) * 10.0 + 0.5)))
end

-- how much of a smoke open to the sky is left at p_At, its top at p_Top (as the shader thins it: nothing at the top, all OUT_TOP under)
function Vol.TopFade(p_Top, p_At)
	return math.max(0.0, math.min(1.0, (p_Top - p_At.y) / (Vol.TopDm() * 0.1)))
end

-- a cloud in the open heaped (VOLUME.OUT_ROUND), as the shader heaps it: its top at p_At, p_Top over the mouth (p_Mouth), coming down to
-- its floor (p_Floor) at the edge of its grown front (p_Grown, and Vol.FRONT past it)
function Vol.HeapTop(p_At, p_Mouth, p_Grown, p_Floor, p_Top)
	local s_R = math.max(p_Grown, 0.1) + Vol.FRONT
	local s_X, s_Z = p_At.x - p_Mouth.x, p_At.z - p_Mouth.z
	return p_Floor + (p_Top - p_Floor) * math.sqrt(math.max(0.0, math.min(1.0, 1.0 - (s_X * s_X + s_Z * s_Z) / (s_R * s_R))))
end

-- A box's matrix: its size on the diagonal, its middle as its place, and off the diagonal, in each row, its numbers (Vol.Pack: 23
-- bits as a number 1 to 2, which the vertex shader unpacks) and a free number (the steer, Vol.Steer). The game draws all the boxes
-- of one mesh at once, near to far by the distance from the camera to the middle of their bounds -- the box's matrix applied to the
-- mesh's declared bounds, whose middle is (1, 1, 1): the box's place plus each row's three numbers -- so the steer sets where the
-- game takes a box to be, and with it the order the boxes are drawn in, nothing else (the box, its smoke and the light it is lit by
-- stay where they are). Rows: x (size x, numbers 0, steer 0), y (numbers 1, size y, steer 1), z (numbers 2, steer 2, size z).
Vol.PAYLOAD = 8388608   -- 2^23

function Vol.Pack(p_Bits)
	return 1.0 + math.max(0, math.min(Vol.PAYLOAD - 1, math.floor(p_Bits))) / Vol.PAYLOAD
end

-- the matrix with its numbers (p_N0..2, packed) and its steer set for p_Sort (the point the game takes the box to be at: its middle
-- with no p_Sort)
function Vol.Raw(p_Size, p_At, p_N0, p_N1, p_N2, p_Sort)
	local s_S = p_Sort or p_At
	return LinearTransform(Vec3(p_Size.x, p_N1, p_N2), Vec3(p_N0, p_Size.y, s_S.z - p_At.z - p_Size.z - p_N2),
		Vec3(s_S.x - p_At.x - p_Size.x - p_N0, s_S.y - p_At.y - p_Size.y - p_N1, p_Size.z), p_At)
end

-- a box's matrix as it is with its steer set for p_Sort (nil: its middle)
function Vol.Steer(p_T, p_Sort)
	return Vol.Raw(Vec3(p_T.left.x, p_T.up.y, p_T.forward.z), p_T.trans, p_T.up.x, p_T.left.y, p_T.left.z, p_Sort)
end

function Vol.Middle(p_Box)
	return Vec3((p_Box.x0 + p_Box.x1) * 0.5, (p_Box.y0 + p_Box.y1) * 0.5, (p_Box.z0 + p_Box.z1) * 0.5)
end

function Vol.Size(p_Box)
	return Vec3(p_Box.x1 - p_Box.x0, p_Box.y1 - p_Box.y0, p_Box.z1 - p_Box.z0)
end

-- a box of the room's with nothing more (kind 0)
function Vol.PlainTransform(p_Box)
	return Vol.Raw(Vol.Size(p_Box), Vol.Middle(p_Box), Vol.Pack(0), Vol.Pack(0), Vol.Pack(0))
end

-- the one box's matrix with the room's main box in its numbers (kind 1; the shader reads it there, VOLUME.MAIN_FILL): how far in each
-- of the main box's sides is from the box's (in 4 cm, 9 bits each, rounded in), its open sides (1, 2, 4, 8 for +x, -x, +z, -z), how far
-- its open top thins out (p_Top, Vol.TopDm; 0: a ceiling over it) and whether a cloud is heaped (VOLUME.OUT_ROUND)
Vol.MAIN_STEP = 0.04

function Vol.MainTransform(p_Box, p_Main, p_Top)
	local function In(p_V)
		return math.max(0, math.min(511, math.ceil(math.max(0.0, p_V) / Vol.MAIN_STEP - 1e-6)))
	end

	local s_Open = p_Main.open
	local s_Mask = (s_Open.px and 1 or 0) + (s_Open.nx and 2 or 0) + (s_Open.pz and 4 or 0) + (s_Open.nz and 8 or 0)
	local s_Heap = ((p_Top or 0) > 0 and VOLUME.OUT_ROUND) and 1 or 0
	local s_Top = math.max(0, math.min(63, p_Top or 0))
	return Vol.Raw(Vol.Size(p_Box), Vol.Middle(p_Box),
		Vol.Pack(1 + 4 * In(p_Main.x0 - p_Box.x0) + 2048 * In(p_Box.x1 - p_Main.x1) + 1048576 * s_Heap
			+ 2097152 * math.floor(s_Top / 16)),
		Vol.Pack(In(p_Main.y0 - p_Box.y0) + 512 * In(p_Box.y1 - p_Main.y1) + 262144 * s_Mask),
		Vol.Pack(In(p_Main.z0 - p_Box.z0) + 512 * In(p_Box.z1 - p_Main.z1) + 262144 * (s_Top % 16)))
end

-- the room's main box, drawn full (VOLUME.MAIN_FILL; a cloud in the open always), or nil: none found, or -- an M320 round's smoke --
-- one that would stand in the air (its grid's floor in the air, or the block of its places not reaching down to the floor): its grid
-- then draws it alone, its bottom thinning out
function Vol.MainOf(p_Room, p_Plan)
	if not (VOLUME.MAIN_FILL or p_Room.outside) then
		return nil
	end

	local s_Ok, s_Main = pcall(Vol.MainBox, p_Room, p_Plan.boxes)

	if not (s_Ok and s_Main.points > 0 and s_Main.x1 > s_Main.x0 and s_Main.z1 > s_Main.z0) then
		return nil
	end

	if p_Room.hit ~= nil and (p_Room.hangs or s_Main.y0 > p_Room.floor.y + ROOM_MIN_HEIGHT) then
		return nil
	end

	return s_Main
end

-- p_Down's measured room drawn as the volume: its boxes made, the grid's numbers set (VOLUME.SIM: filling over time, Vol.SimStart)
function Vol.Start(p_Down)
	if VOLUME.SIM then
		return Vol.SimStart(p_Down)
	end

	local s_Room = p_Down.room
	local s_Plan = Vol.Plan(s_Room)
	local s_Boxes = {}
	local s_Single = VOLUME.ONE_WRITER and VOLUME.ONE_PASS
	local s_Draw = s_Single and { s_Plan.bound } or s_Plan.joined
	local s_Main = nil
	-- a cloud in the open: its top open, thinning out upwards (carried with the main box: the open always has one)
	local s_Top = s_Room.outside and Vol.TopDm() or 0

	if s_Single then
		s_Main = Vol.MainOf(s_Room, s_Plan)
	end

	-- (each box's matrix kept: Vol.Order sets its steer)
	local s_Drawn = {}

	for _, l_Box in ipairs(s_Draw) do
		local l_Transform = s_Main ~= nil and Vol.MainTransform(l_Box, s_Main, s_Top) or Vol.PlainTransform(l_Box)
		local l_Slot, l_Data = Vol.Slot(s_Drawn)
		local l_Entity = EntityManager:CreateEntity(l_Data, l_Transform)

		if l_Entity ~= nil then
			l_Entity:Init(Realm.Realm_Client, true)
			s_Boxes[#s_Boxes + 1] = l_Entity
			s_Drawn[#s_Drawn + 1] = { entity = l_Entity, raw = l_Transform, slot = l_Slot }
		end
	end

	if #s_Boxes == 0 then
		return false
	end

	local s_Values = {
		TsSmokeB = Vec4(s_Plan.origin.x, s_Plan.origin.y, s_Plan.origin.z, s_Room.layer),
	}

	for i = 0, #s_Plan.words / 4 - 1 do
		s_Values["TsSmokeBits" .. i] = Vec4(s_Plan.words[i * 4 + 1], s_Plan.words[i * 4 + 2], s_Plan.words[i * 4 + 3],
			s_Plan.words[i * 4 + 4])
	end

	Vol.now = { down = p_Down, boxes = s_Boxes, drawn = s_Drawn, values = s_Values, cells = s_Plan.boxes, joined = s_Plan.joined,
		single = s_Single, main = s_Main, top = s_Plan.bound.y1, bound = s_Plan.bound, origin = s_Plan.origin,
		holesBefore = Vol.holeCount or 0 }

	if p_Down.logged ~= nil then
		local l_B = s_Plan.bound
		LOG(string.format("smoke %d is drawn as a volume (%s): %d box(es) made of %d from the room's %d point(s) (%d off its grid, %d"
			.. " side(s) drawn back off another box), %d wall cell(s) set, layers of %.2f m, grid from (%.1f, %.1f, %.1f)%s", p_Down.logged,
			s_Single and "one box round them all draws every view" or (VOLUME.ONE_WRITER and "one box draws each view" or "each box its own stretch"),
			#s_Boxes, #s_Draw, #s_Room.cells, s_Plan.off, s_Plan.back, s_Plan.walls, s_Room.layer, s_Plan.origin.x, s_Plan.origin.y,
			s_Plan.origin.z, s_Single and string.format("; that box %.1f x %.1f x %.1f m round the %d joined one(s), from (%.1f, %.1f, %.1f)"
			.. " to (%.1f, %.1f, %.1f), half a cell out on its open side(s) [%s]", l_B.x1 - l_B.x0, l_B.y1 - l_B.y0, l_B.z1 - l_B.z0,
			#s_Plan.joined, l_B.x0, l_B.y0, l_B.z0, l_B.x1, l_B.y1, l_B.z1, table.concat(l_B.open, ", ")) or ""))

		-- its shape as the shader draws it, in one line (to rebuild it: the grid's numbers, the joined boxes, the main space and what the
		-- rays out of its sides met, low to high)
		local l_Joined = {}

		for _, l_J in ipairs(s_Plan.joined) do
			l_Joined[#l_Joined + 1] = string.format("%.2f %.2f %.2f %.2f %.2f %.2f", l_J.x0, l_J.y0, l_J.z0, l_J.x1, l_J.y1, l_J.z1)
		end

		local l_Words = {}

		for _, l_W in ipairs(s_Plan.words) do
			l_Words[#l_Words + 1] = string.format("%d", l_W)
		end

		local l_Bands = {}

		for _, l_Name in ipairs({ "px", "nx", "pz", "nz" }) do
			if s_Main ~= nil and s_Main.bands ~= nil and s_Main.bands[l_Name] ~= nil then
				l_Bands[#l_Bands + 1] = l_Name .. " " .. s_Main.bands[l_Name]
			end
		end

		LOG(string.format("smoke %d's shape: grid from (%.2f, %.2f, %.2f), layers %.3f m, cells [%s]; %d opening place(s) in it; joined"
			.. " [%s]; main %s; its sides' rays met [%s]", p_Down.logged, s_Plan.origin.x, s_Plan.origin.y, s_Plan.origin.z, s_Room.layer,
			table.concat(l_Words, " "), #(s_Room.exitCells or {}), table.concat(l_Joined, " | "), s_Main ~= nil and string.format(
			"%.2f %.2f %.2f %.2f %.2f %.2f", s_Main.x0, s_Main.y0, s_Main.z0, s_Main.x1, s_Main.y1, s_Main.z1) or "none",
			table.concat(l_Bands, ", ")))

		if s_Main ~= nil then
			LOG(string.format("smoke %d's room's main space drawn full: from (%.1f, %.1f, %.1f) to (%.1f, %.1f, %.1f), %d point(s),"
				.. " open on [%s%s%s%s]%s", p_Down.logged, s_Main.x0, s_Main.y0, s_Main.z0, s_Main.x1, s_Main.y1, s_Main.z1,
				s_Main.points, s_Main.open.px and "px " or "", s_Main.open.nx and "nx " or "", s_Main.open.pz and "pz " or "",
				s_Main.open.nz and "nz" or "", s_Top > 0 and string.format(", its top open (thinning out over %.1f m)", s_Top * 0.1) or ""))
		end
	end

	return true
end

-- p_Down's smoke, drawn while its room is measured (an M320 round's: VOLUME.M320_EARLY), drawn again with the room as measured by now:
-- the volume's grid and its one box (or its box of its own) made again from all the places measured so far, as Vol.Start makes them
-- (Vol.StartOther); its numbers written on its next frame, its box's matrix set by Vol.Order. True if drawn again
function Vol.Again(p_Down)
	local s_Room = p_Down.room
	local s_Now = Vol.now

	-- (the room filling over time follows its places as they are measured by itself, Vol.SimFrame)
	if s_Now ~= nil and s_Now.down == p_Down and s_Now.sim then
		return true
	end

	if s_Now ~= nil and s_Now.down == p_Down then
		if not s_Now.single or s_Now.drawn == nil or #s_Now.drawn ~= 1 or s_Now.values == nil then
			return false
		end

		local s_Plan = Vol.Plan(s_Room)
		local s_Main = Vol.MainOf(s_Room, s_Plan)
		local s_Drawn = s_Now.drawn[1]
		s_Drawn.raw = s_Main ~= nil and Vol.MainTransform(s_Plan.bound, s_Main, s_Room.outside and Vol.TopDm() or 0)
			or Vol.PlainTransform(s_Plan.bound)
		s_Drawn.dirty = true
		s_Now.values.TsSmokeB = Vec4(s_Plan.origin.x, s_Plan.origin.y, s_Plan.origin.z, s_Room.layer)
		s_Now.cells, s_Now.joined, s_Now.main, s_Now.top, s_Now.bound, s_Now.origin = s_Plan.boxes, s_Plan.joined, s_Main,
			s_Plan.bound.y1, s_Plan.bound, s_Plan.origin
		-- (written on its next frame whatever has changed: the grid from its new corner)
		s_Now.count, s_Now.grown = nil, nil
		return true
	end

	local s_Other = s_Room.other

	if s_Other ~= nil and not s_Other.gone then
		local s_Box = Vol.MainBox(s_Room, Vol.OtherBoxes(s_Room), true)

		if s_Box.points == 0 or s_Box.x1 <= s_Box.x0 or s_Box.y1 <= s_Box.y0 or s_Box.z1 <= s_Box.z0 then
			return false
		end

		local s_Open = s_Box.open
		s_Other.box = s_Box
		s_Other.mark = 1 + (s_Open.px and 1 or 0) + (s_Open.nx and 2 or 0) + (s_Open.pz and 4 or 0) + (s_Open.nz and 8 or 0)
			+ 16 * s_Other.top
		-- (its matrix made again on its next frame)
		s_Other.grown = nil
		return true
	end

	return false
end

function Vol.End()
	if Vol.now == nil then
		return
	end

	for _, l_Box in ipairs(Vol.now.boxes) do
		pcall(function() l_Box:Destroy() end)
	end

	local s_Now = Vol.now
	Vol.now = nil
	-- (the light, the billows' size and the front's height stay: the volumes of their own read them)
	local s_LookA, s_LookB = Vol.Look()
	pcall(Vol.SetParams, { TsSmokeC = Vec4(0.0, s_LookA, s_LookB, Vol.ModeWord(0)) })

	if s_Now.down.logged ~= nil then
		local s_Room = s_Now.down.room
		local s_Sim = s_Now.sim and s_Room.sim or nil
		LOG(string.format("smoke %d's volume gone: its numbers written %d time(s) over %.0f s (%s); %d bullet hole(s) through it; the"
			.. " camera in its smoke %.1f s, the fog over the view at most %.2f of its thickest%s",
			s_Now.down.logged, s_Now.writes or 0, s_Now.down.age - (s_Room.ready or 0.0), VOLUME.EVERY_FRAME and "every frame" or "only as they changed",
			(Vol.holeCount or 0) - (s_Now.holesBefore or 0), s_Now.down.fogTime or 0.0, s_Now.down.fogMost or 0.0,
			s_Sim ~= nil and string.format("; filling over time: %d step(s), its columns"
			.. " made %d time(s) (%d place(s), %d column(s), %d join(s) at the end), %.1f ms in all (%.2f ms at most in a frame) -- by part,"
			.. " ms in all (at most in a frame): %s; %.0f m3 held, %.0f m3 fell away with no floor under it, its front grown to %.1f m",
			s_Sim.steps or 0, s_Sim.topos or 0, #s_Room.cells, #(s_Sim.segs or {}), #(s_Sim.edges or {}), s_Room.simMs or 0.0,
			s_Room.simMsMost or 0.0, Vol.SimPartsSaid(s_Room), Vol.SimHeld(s_Room), (s_Sim.fell or 0.0) * ROOM_CELL * ROOM_CELL * s_Room.layer,
			s_Room.simFront or 0.0) or ""))
	end
end

-- how fast a room's smoke spreads (m/s): an M320 round's at once (VOLUME.M320_GROW), a canister's VOLUME.GROW
function Vol.Grow(p_Room)
	return p_Room.grow or VOLUME.GROW
end

-- how much a smoke's strength (how thick it still is, Vol.Strength) weighs the fog over the view in it: a canister's as it is; a
-- round's -- thinning out from the start -- as much as VOLUME.ROUND_FOG metres of its smoke as drawn hide (VOLUME.DENSITY times its
-- strength), against what they hide at its thickest
function Vol.FogStrength(p_Down, p_Strength)
	local s_S = math.max(0.0, p_Strength or 1.0)

	if p_Down == nil or p_Down.kind ~= "m320" or (VOLUME.ROUND_FOG or 0.0) <= 0.0 then
		return s_S
	end

	local s_K = VOLUME.DENSITY * VOLUME.ROUND_FOG
	return (1.0 - math.exp(-s_K * s_S)) / (1.0 - math.exp(-s_K))
end

-- how thick a smoke still is, 0 to 1: a canister's whole until VOLUME.CLEAR before p_End, thinning to nothing then; an M320 round's
-- (or the mortar's) thinning out from the start as its puffs do (their transparency over their life: 1 - 1.546 t + 0.548 t^2, t its
-- share of its time, VOLUME.M320_SECONDS or MORTAR_SECONDS)
function Vol.Strength(p_Down, p_End)
	if p_Down.kind == "m320" then
		local s_T = math.max(0.0, math.min(1.0, p_Down.age / math.max(p_Down.seconds or VOLUME.M320_SECONDS, 0.1)))
		return math.max(0.0, math.min(1.0, 1.0 - 1.54555535 * s_T + 0.547555447 * s_T * s_T))
	end

	return math.max(0.0, math.min(1.0, (p_End - p_Down.age) / VOLUME.CLEAR))
end

-- how far the smoke has grown from the canister, and how thick it is (thinning to nothing over VOLUME.CLEAR before its room's smoke
-- ends at p_End), written when either changed enough to show (a tenth of a metre, a fiftieth of its thickness) -- or every frame, with
-- VOLUME.EVERY_FRAME. The billows move on their own (the shader's clock).
function Vol.Frame(p_End)
	local s_Now = Vol.now

	if s_Now.sim then
		return Vol.SimFrame(p_End)
	end

	local s_Down = s_Now.down
	local s_Room = s_Down.room
	local s_Grown = math.min(Vol.Grow(s_Room) * math.max(0.0, s_Down.age - (s_Room.ready or s_Down.age)), Vol.Spreads(s_Room))
	local s_Strength = Vol.Strength(s_Down, p_End)

	-- one box drawing each view: the grid holds the points the smoke has got to by its way there (Vol.Path), a cell ahead of its front
	-- (the shader's own front, straight from the canister, thins it in): past a wall it shows only once it has gone round it, through
	-- the door; and the shader is told whether the camera is in the smoke -- in the box of a point the smoke has got to (then that box
	-- draws every view; with one box round them all, its view starts in the smoke) -- 2 or 4, else 1 or 3
	local s_Within, s_Count, s_Mode = nil, nil, 0.0

	if VOLUME.ONE_WRITER then
		local s_Camera = ClientUtils:GetCameraTransform()
		s_Within = math.min(s_Grown + ROOM_CELL, Vol.Spreads(s_Room) + ROOM_CELL * 0.5)
		s_Mode = ((s_Camera ~= nil and Vol.Inside(s_Now.cells, s_Camera.trans, s_Within)) and 2.0 or 1.0) + (s_Now.single and 2.0 or 0.0)
		Vol.nearBit = (s_Camera ~= nil and Vol.Near(s_Camera.trans)) and Vol.NEAR_BIT or 0
		s_Count = 0

		for _, l_Box in ipairs(s_Now.cells) do
			if (l_Box.cell.path or 0.0) <= s_Within then
				s_Count = s_Count + 1
			end
		end
	end

	-- due: the first time, a tenth of a metre more grown (or grown whole), a fiftieth thinner (or gone), a point more got to, the
	-- camera into or out of the boxes
	local s_Due = VOLUME.EVERY_FRAME or s_Now.grown == nil or math.abs(s_Grown - s_Now.grown) >= Vol.GrowStep()
		or (s_Grown >= Vol.Spreads(s_Room) and s_Now.grown < Vol.Spreads(s_Room)) or math.abs(s_Strength - s_Now.strength) >= Vol.ClearStep()
		or (s_Strength <= 0.0 and s_Now.strength > 0.0) or s_Count ~= s_Now.count or s_Mode ~= s_Now.mode
		or (Vol.holeBits or 0) ~= (s_Now.holeBits or 0) or Vol.holeStamp ~= s_Now.holeStamp or (Vol.nearBit or 0) ~= (s_Now.nearBit or 0)

	if not s_Due then
		return
	end

	local s_Values = s_Now.values

	if s_Count ~= nil and s_Count ~= s_Now.count then
		local _, l_Words = Vol.Grid(s_Room, s_Now.cells, true, s_Within)

		for i = 0, #l_Words / 4 - 1 do
			s_Values["TsSmokeBits" .. i] = Vec4(l_Words[i * 4 + 1], l_Words[i * 4 + 2], l_Words[i * 4 + 3], l_Words[i * 4 + 4])
		end
	end
	s_Values.TsSmokeA = Vec4(s_Room.mouth.x, s_Room.mouth.y, s_Room.mouth.z, s_Grown)
	local s_LookA, s_LookB = Vol.Look()
	s_Values.TsSmokeC = Vec4(VOLUME.DENSITY * s_Strength, s_LookA, s_LookB, Vol.ModeWord(s_Mode))
	-- (the bullets' holes, Vol.HoleFrame: their ends, relative to this grid's corner)
	s_Values.TsSmokeD = Vol.HoleEnds()

	if Vol.SetParams(s_Values) then
		s_Now.grown, s_Now.strength, s_Now.count, s_Now.mode = s_Grown, s_Strength, s_Count, s_Mode
		s_Now.holeBits, s_Now.holeStamp, s_Now.nearBit = Vol.holeBits or 0, Vol.holeStamp, Vol.nearBit or 0
		s_Now.writes = (s_Now.writes or 0) + 1
	end
end

-- ---- a volume of its own (VOLUME.OTHERS) ---------------------------------------------------------------------------------------------
-- A smoke going off while another one's room is drawn as the volume (the grid's numbers are that room's) is drawn by a box of its own,
-- whose numbers ride the box itself: its world matrix reaches the shader whole, and the shader places the box by its diagonal and its
-- place alone, reading the six numbers off the diagonal as this smoke's -- its canister's mouth, how far it has grown, how thick it is,
-- and which of the box's sides open onto more of the room. The smoke grows from the mouth, billowing, filling the box (thick up to the
-- walls its sides lie on, thinning out towards an open side).

-- of the 9 rays out of a main box's side, how many must meet something for the side to be a wall (more than half: a stairwell's wall
-- with its foot open to the hall, a third of it, is still a wall -- the smoke thick up to it)
Vol.WALL_MET = 5

-- the main box of a measured room: the biggest block of its points round the canister's (grown a row at a time while every place of
-- the next row along the floor holds a point of the room with a clear ray, at some layer, to the point next to it in the block: the
-- room's main space, never across a wall -- the room may hold points on both sides of one, got to round it), its sides where those
-- points' boxes end (none past a wall), and which sides the room goes on past (open)
-- (p_Own: the box of a volume of its own -- all of that smoke there is, no grid round it: the places it fills only lower down are
-- part of it as well, the box reaching their walls; only those over a ceiling or hanging over lower steps are not)
function Vol.MainBox(p_Room, p_Boxes, p_Own)
	local s_Columns = {}

	-- (the places out of the room's openings are no part of its main space)
	for _, l_Box in ipairs(p_Boxes) do
		if not l_Box.cell.exit then
			local l_Key = l_Box.cell.i .. "," .. l_Box.cell.k
			s_Columns[l_Key] = s_Columns[l_Key] or {}
			table.insert(s_Columns[l_Key], l_Box)
		end
	end

	-- whether every point of the place (p_I, p_K) has a clear ray to some point of the one next to it (p_NI, p_NK), and every point of
	-- that one to some point of this one: one point behind a wall -- a hall's beside a stairwell, under its own ceiling -- and it is not
	-- part of the block, however many of its others (on the floor over that hall) see the block's (this smoke grows straight from its
	-- canister: it would show through that wall); and a place whose points stand only over a roof (a low building in the open, a booth
	-- in a hall: the block's points under them see none of them) is not either (the block's box, drawn full from its floor, would fill
	-- that building). Any of the other one's points will do (a point kept off a pillar may stand on its other side from its neighbour at
	-- the same layer).
	-- (VOLUME.SIM: the other one's point at the same layer, by the clear ray the measuring found between them, Vol.Linked -- none cast
	-- again; with no point there, a ray to any as ever)
	local s_Links = VOLUME.SIM and p_Room.links ~= nil

	local function Sees(p_From, p_To)
		for _, l_A in ipairs(p_From) do
			local l_Seen, l_Level = false, nil

			if s_Links then
				for _, l_B in ipairs(p_To) do
					if l_B.cell.j == l_A.cell.j then
						l_Level = l_B
						break
					end
				end
			end

			if l_Level ~= nil then
				l_Seen = Vol.Linked(p_Room, l_A.cell, l_Level.cell)
			else
				for _, l_B in ipairs(p_To) do
					if RaycastManager:Raycast(l_A.cell.at, l_B.cell.at, RAY_FLAGS) == nil then
						l_Seen = true
						break
					end
				end
			end

			if not l_Seen then
				return false
			end
		end

		return true
	end

	local function Linked(p_I, p_K, p_NI, p_NK)
		local l_Here, l_There = s_Columns[p_I .. "," .. p_K], s_Columns[p_NI .. "," .. p_NK]
		return l_Here ~= nil and l_There ~= nil and Sees(l_Here, l_There) and Sees(l_There, l_Here)
	end

	local s_First = p_Room.cells[1]
	local s_I0, s_I1, s_K0, s_K1 = s_First.i, s_First.i, s_First.k, s_First.k

	-- (as the smoke flows, VOLUME.FLOW: only the places it fills up to as high as it gets at the canister -- the middle of its heap,
	-- drawn full from the floor; round that it is lower and thins out, the grid's to draw with its soft edge. And only those whose smoke
	-- goes down to the floor or to something low on it -- starting no higher than ROOM_MIN_HEIGHT over the room's floor: higher, it
	-- is over a ceiling, a room under it (a hall's, open over it to a stairwell) that the block's box, drawn full from its floor, would
	-- fill -- and not lower than at the canister: down a flight of stairs from a landing that box, flat at its bottom, would hang over
	-- the lower steps)
	local s_TopJ, s_Low = nil, nil

	if VOLUME.FLOW then
		for _, l_Box in ipairs(s_Columns[s_First.i .. "," .. s_First.k] or {}) do
			s_TopJ = math.max(s_TopJ or 0, l_Box.cell.j)
			s_Low = math.min(s_Low or math.huge, l_Box.y0)
		end
	end

	local function Full(p_I, p_K)
		if s_TopJ == nil then
			return true
		end

		local l_Top, l_Low = false, math.huge

		for _, l_Box in ipairs(s_Columns[p_I .. "," .. p_K] or {}) do
			l_Top = l_Top or l_Box.cell.j >= s_TopJ
			l_Low = math.min(l_Low, l_Box.y0)
		end

		return (l_Top or p_Own == true) and l_Low <= p_Room.floor.y + ROOM_MIN_HEIGHT and l_Low >= s_Low - 0.3 * p_Room.layer
	end

	-- the row at (p_I0..p_I1, p_K0..p_K1), each place linked to the one (p_DI, p_DK) back towards the block
	local function Row(p_I0, p_I1, p_K0, p_K1, p_DI, p_DK)
		for l_I = p_I0, p_I1 do
			for l_K = p_K0, p_K1 do
				if not Linked(l_I, l_K, l_I + p_DI, l_K + p_DK) or not Full(l_I, l_K) then
					return false
				end
			end
		end

		return true
	end

	local s_Grew = true

	while s_Grew do
		s_Grew = false

		if Row(s_I1 + 1, s_I1 + 1, s_K0, s_K1, -1, 0) then
			s_I1, s_Grew = s_I1 + 1, true
		end

		if Row(s_I0 - 1, s_I0 - 1, s_K0, s_K1, 1, 0) then
			s_I0, s_Grew = s_I0 - 1, true
		end

		if Row(s_I0, s_I1, s_K1 + 1, s_K1 + 1, 0, -1) then
			s_K1, s_Grew = s_K1 + 1, true
		end

		if Row(s_I0, s_I1, s_K0 - 1, s_K0 - 1, 0, 1) then
			s_K0, s_Grew = s_K0 - 1, true
		end
	end

	-- a side is open where the room goes on past it: half or more of the next row's places linked to the block (a corridor's wall with
	-- rooms behind it, got to through their doors, is no open side: the smoke stays thick up to it)
	local function Open(p_I0, p_I1, p_K0, p_K1, p_DI, p_DK)
		local l_Linked, l_All = 0, 0

		for l_I = p_I0, p_I1 do
			for l_K = p_K0, p_K1 do
				l_All = l_All + 1

				if Linked(l_I, l_K, l_I + p_DI, l_K + p_DK) then
					l_Linked = l_Linked + 1
				end
			end
		end

		return l_Linked * 2 >= l_All
	end

	local s_Open = { px = Open(s_I1 + 1, s_I1 + 1, s_K0, s_K1, -1, 0), nx = Open(s_I0 - 1, s_I0 - 1, s_K0, s_K1, 1, 0),
		pz = Open(s_I0, s_I1, s_K1 + 1, s_K1 + 1, 0, -1), nz = Open(s_I0, s_I1, s_K0 - 1, s_K0 - 1, 0, 1) }
	local s_Main = { x0 = -1e9, x1 = 1e9, y0 = 1e9, y1 = -1e9, z0 = -1e9, z1 = 1e9, points = 0, open = s_Open, i0 = s_I0, i1 = s_I1,
		k0 = s_K0, k1 = s_K1 }

	-- a block's side that is not open ends at the wall its places met there, within a cell: up to it (a point's box reaches only half a
	-- cell towards a point of the room behind that wall, short of the wall when the wall is farther), never past it (this smoke never
	-- gets behind it); a side none of whose places met a wall (only part of something there, or nothing within a cell), where their
	-- boxes end
	-- (the wall a place of that side met, or nil: only part of something there -- a door's place, a counter's edge -- or nothing within
	-- two cells: a wall farther than the cell its gap was measured over is looked for again from its point, out to two)
	local function Wall(p_Box, p_Name, p_Place, p_Sign)
		local l_Gaps = p_Box.cell.gaps
		local l_Gap = l_Gaps ~= nil and l_Gaps[p_Name] or nil

		if s_Open[p_Name] or l_Gap == nil or (l_Gaps.part ~= nil and l_Gaps.part[p_Name]) then
			return nil
		end

		if l_Gap < ROOM_CELL - 0.001 then
			return p_Place + p_Sign * l_Gap
		end

		local l_At = p_Box.cell.at
		local l_Way = Vec3(Vol.WAYS[p_Name][1], 0.0, Vol.WAYS[p_Name][3])
		local l_Hit = RaycastManager:Raycast(l_At, l_At + l_Way * (ROOM_CELL * 2.0), RAY_FLAGS)

		if l_Hit == nil then
			return nil
		end

		return p_Name:sub(2, 2) == "x" and l_Hit.position.x or l_Hit.position.z
	end

	-- each side: where its places' walls are (the innermost), else where their boxes end
	local s_Walls, s_Ends = {}, {}

	local function Note(p_Name, p_Wall, p_End, p_Sign)
		if p_Wall ~= nil then
			s_Walls[p_Name] = s_Walls[p_Name] == nil and p_Wall or (p_Sign > 0 and math.min(s_Walls[p_Name], p_Wall)
				or math.max(s_Walls[p_Name], p_Wall))
		end

		s_Ends[p_Name] = s_Ends[p_Name] == nil and p_End or (p_Sign > 0 and math.min(s_Ends[p_Name], p_End)
			or math.max(s_Ends[p_Name], p_End))
	end

	for l_I = s_I0, s_I1 do
		for l_K = s_K0, s_K1 do
			for _, l_Box in ipairs(s_Columns[l_I .. "," .. l_K]) do
				local l_X, l_Z = p_Room.floor.x + l_I * ROOM_CELL, p_Room.floor.z + l_K * ROOM_CELL
				s_Main.points = s_Main.points + 1
				s_Main.y0, s_Main.y1 = math.min(s_Main.y0, l_Box.y0), math.max(s_Main.y1, l_Box.y1)

				if l_I == s_I0 then
					Note("nx", Wall(l_Box, "nx", l_X, -1), l_Box.x0, -1)
				end

				if l_I == s_I1 then
					Note("px", Wall(l_Box, "px", l_X, 1), l_Box.x1, 1)
				end

				if l_K == s_K0 then
					Note("nz", Wall(l_Box, "nz", l_Z, -1), l_Box.z0, -1)
				end

				if l_K == s_K1 then
					Note("pz", Wall(l_Box, "pz", l_Z, 1), l_Box.z1, 1)
				end
			end
		end
	end

	s_Main.x0, s_Main.x1 = s_Walls.nx or s_Ends.nx, s_Walls.px or s_Ends.px
	s_Main.z0, s_Main.z1 = s_Walls.nz or s_Ends.nz, s_Walls.pz or s_Ends.pz

	-- a side none of whose places met a wall is where the room goes on (as far as it was measured, or farther): open; and so is one
	-- where most of the box's face is open air (a wall only up to a hall's ceiling, the room going on over it): 9 rays out from just
	-- inside it, fewer than Vol.WALL_MET meeting anything (else the smoke would end in a flat face there, in mid air; what each third
	-- of the face's height met goes to the log with the smoke's shape). A side with a wall that stops short of the top (a
	-- low building beside a cloud in the open: its third of the face highest up, or more, mostly open air) brings the box's top down to
	-- where the wall still stands: the room's smoke over that is the grid's, with its soft edge
	local s_Top = s_Main.y1

	for _, l_Name in ipairs({ "px", "nx", "pz", "nz" }) do
		if s_Walls[l_Name] == nil then
			s_Open[l_Name] = true
		elseif not s_Open[l_Name] then
			local l_Way = Vol.WAYS[l_Name]
			local l_X = l_Name:sub(2, 2) == "x"
			local l_Face = l_Way[1] + l_Way[3] > 0 and (l_X and s_Main.x1 or s_Main.z1) or (l_X and s_Main.x0 or s_Main.z0)
			local l_Lo, l_Hi = l_X and s_Main.z0 or s_Main.x0, l_X and s_Main.z1 or s_Main.x1
			local l_Met, l_Band = 0, {}

			for l_V = 1, 3 do
				l_Band[l_V] = 0

				for l_U = 1, 3 do
					local l_Along = l_Lo + (l_Hi - l_Lo) * (l_U - 0.5) / 3
					local l_Y = s_Main.y0 + (s_Main.y1 - s_Main.y0) * (l_V - 0.5) / 3
					local l_From = l_X and Vec3(l_Face - l_Way[1] * 0.05, l_Y, l_Along) or Vec3(l_Along, l_Y, l_Face - l_Way[3] * 0.05)
					local l_Dir = Vec3(l_Way[1], 0.0, l_Way[3])

					if RaycastManager:Raycast(l_From, l_From + l_Dir * 0.35, RAY_FLAGS) ~= nil then
						l_Met = l_Met + 1
						l_Band[l_V] = l_Band[l_V] + 1
					end
				end
			end

			s_Open[l_Name] = l_Met < Vol.WALL_MET
			s_Main.bands = s_Main.bands or {}
			s_Main.bands[l_Name] = l_Band[1] .. "/" .. l_Band[2] .. "/" .. l_Band[3]

			if not s_Open[l_Name] then
				for l_V = 2, 3 do
					if l_Band[l_V] * 2 < 3 then
						s_Top = math.min(s_Top, s_Main.y0 + (s_Main.y1 - s_Main.y0) * (l_V - 1) / 3)
						break
					end
				end
			end
		end
	end

	s_Main.y1 = s_Top
	return s_Main
end

-- the box's matrix with this smoke's numbers (kind 2; Vol.Raw: the vertex shader unpacks them): the mouth (8 bits an axis, across
-- the box), how far it has grown (centimetres), how thick it is (/127.5), and its mark -- 1, plus 1, 2, 4, 8 for an open side +x, -x,
-- +z, -z, plus 16 times how far its open top thins out (Vol.TopDm; 0: a ceiling over it), plus 1024 times the side it stands against
-- and 4096 times from how high there it opens (in tenths of a metre); and (VOLUME.SIM) whether it hangs with nothing under it, an M320
-- round's high on a wall: thinning out up from its bottom too
function Vol.OtherTransform(p_Other, p_Grown, p_Sigma)
	local s_B, s_M = p_Other.box, p_Other.mouth
	local s_Size = Vol.Size(s_B)
	local function Across(p_V, p_Lo, p_Span)
		return math.max(0, math.min(255, math.floor((p_V - p_Lo) / math.max(p_Span, 0.001) * 255.0 + 0.5)))
	end

	local s_Mark = math.max(0, math.floor(p_Other.mark + 0.5) - 1)
	local s_Open, s_Top = s_Mark % 16, math.floor(s_Mark / 16) % 64
	local s_Back, s_BackFrom = math.floor(s_Mark / 1024) % 4, math.min(127, math.floor(s_Mark / 4096))
	local s_Under = (VOLUME.SIM and p_Other.down ~= nil and p_Other.down.room ~= nil and p_Other.down.room.hangs) and 4194304 or 0
	return Vol.Raw(s_Size, Vol.Middle(s_B),
		Vol.Pack(2 + 4 * Across(s_M.x, s_B.x0, s_Size.x) + 1024 * Across(s_M.y, s_B.y0, s_Size.y) + 262144 * s_Open + s_Under),
		Vol.Pack(Across(s_M.z, s_B.z0, s_Size.z) + 256 * math.max(0, math.min(255, math.floor(p_Sigma * 127.5 + 0.5))) + 65536 * s_Top),
		Vol.Pack(math.max(0, math.min(16383, math.floor(p_Grown * 100.0 + 0.5))) + 16384 * s_Back + 65536 * s_BackFrom))
end

-- a room's places' boxes for its main box as a volume of its own: (VOLUME.SIM) each place's box cut to the walls as measured, no plan
-- of boxes made (its overlaps trimmed one against another: tens of milliseconds in a frame for a few hundred places); else the plan's
function Vol.OtherBoxes(p_Room)
	if VOLUME.SIM and p_Room.cellAt ~= nil then
		return (Vol.SimPlaces(p_Room))
	end

	return Vol.Plan(p_Room).boxes
end

-- p_Down's measured room drawn as a volume of its own: its main box made, nothing grown yet
function Vol.StartOther(p_Down)
	local s_Room = p_Down.room
	local s_Box = Vol.MainBox(s_Room, Vol.OtherBoxes(s_Room), true)

	if s_Box.points == 0 or s_Box.x1 <= s_Box.x0 or s_Box.y1 <= s_Box.y0 or s_Box.z1 <= s_Box.z0 then
		return nil
	end

	local s_Open = s_Box.open
	-- (a cloud in the open: its top open as well)
	local s_Other = { down = p_Down, box = s_Box, mouth = s_Room.mouth, top = s_Room.outside and Vol.TopDm() or 0,
		mark = 1 + (s_Open.px and 1 or 0) + (s_Open.nx and 2 or 0) + (s_Open.pz and 4 or 0) + (s_Open.nz and 8 or 0) }
	s_Other.mark = s_Other.mark + 16 * s_Other.top
	s_Other.raw = Vol.OtherTransform(s_Other, 0.0, 0.0)
	local s_Data
	s_Other.slot, s_Data = Vol.Slot()
	s_Other.entity = EntityManager:CreateEntity(s_Data, s_Other.raw)

	if s_Other.entity == nil then
		return nil
	end

	s_Other.entity:Init(Realm.Realm_Client, true)
	Vol.others[#Vol.others + 1] = s_Other

	if p_Down.logged ~= nil then
		local l_Sides = {}

		for _, l_Name in ipairs({ "px", "nx", "pz", "nz" }) do
			if s_Open[l_Name] then
				l_Sides[#l_Sides + 1] = l_Name
			end
		end

		if s_Other.top > 0 then
			l_Sides[#l_Sides + 1] = string.format("the top (thinning out over %.1f m)", s_Other.top * 0.1)
		end

		LOG(string.format("smoke %d is drawn as a volume of its own (the grid is %s), box mesh %d: its room's main box %.1f x %.1f x %.1f m,"
			.. " from (%.1f, %.1f, %.1f) to (%.1f, %.1f, %.1f), %d of the room's %d point(s), open on [%s]", p_Down.logged,
			Vol.now ~= nil and string.format("smoke %s's", tostring(Vol.now.down.logged or "(not logged)")) or "free", s_Other.slot,
			s_Box.x1 - s_Box.x0, s_Box.y1 - s_Box.y0, s_Box.z1 - s_Box.z0, s_Box.x0, s_Box.y0, s_Box.z0, s_Box.x1, s_Box.y1, s_Box.z1,
			s_Box.points, #s_Room.cells, table.concat(l_Sides, ", ")))
	end

	return s_Other
end

-- one frame of a volume of its own: grown from the canister as the volume is, thinning out over VOLUME.CLEAR before p_End; its box's
-- matrix made again when either changed enough to show (as the volume's numbers are written), and set on its box by Vol.Order (with
-- its steer)
function Vol.OtherFrame(p_Other, p_End)
	local s_Down = p_Other.down
	local s_Room = s_Down.room
	local s_Grown = math.min(Vol.Grow(s_Room) * math.max(0.0, s_Down.age - (s_Room.ready or s_Down.age)), Vol.Spreads(s_Room))
	local s_Strength = Vol.Strength(s_Down, p_End)
	p_Other.strength = s_Strength

	if not VOLUME.EVERY_FRAME and p_Other.grown ~= nil and math.abs(s_Grown - p_Other.grown) < Vol.GrowStep()
		and not (s_Grown >= Vol.Spreads(s_Room) and p_Other.grown < Vol.Spreads(s_Room)) and math.abs(s_Strength - p_Other.written) < Vol.ClearStep()
		and not (s_Strength <= 0.0 and p_Other.written > 0.0) then
		return
	end

	p_Other.raw = Vol.OtherTransform(p_Other, s_Grown, VOLUME.DENSITY * s_Strength)
	p_Other.dirty = true
	p_Other.grown, p_Other.written = s_Grown, s_Strength
	p_Other.writes = (p_Other.writes or 0) + 1
end

-- the order the smoke's boxes are drawn in (VOLUME.ORDER): every box drawn now -- the room's (Vol.now.drawn) and those of their own
-- (Vol.others) -- far to near, the one the camera is in last: each box's steer (Vol.Steer) puts where the game takes it to be at a
-- distance from the camera that grows in that order (from the nearest box's middle on, 2 m apart, straight up over the camera: a
-- camera that moves less than ORDER_SLACK keeps the order), so the game's near to far is that order. Far and near by how far the camera
-- is from each box (0 in it), then from its middle. A box's matrix is set on it here only: when its numbers change, when its place in
-- the order changes, and when the camera has moved ORDER_SLACK since the steers were set.
Vol.ORDER_GAP = 2.0
Vol.ORDER_SLACK = 0.5

function Vol.Drawn()
	local s_List = {}

	if Vol.now ~= nil then
		for _, l_Drawn in ipairs(Vol.now.drawn or {}) do
			s_List[#s_List + 1] = l_Drawn
		end
	end

	for _, l_Other in ipairs(Vol.others) do
		if not l_Other.gone and l_Other.entity ~= nil and l_Other.raw ~= nil then
			s_List[#s_List + 1] = l_Other
		end
	end

	return s_List
end

-- a mesh of the box (Vol.datas) no box drawn now uses -- nor one of p_Also --: its index and its data; with all of them in use, the one
-- used least (those boxes then share a draw, the game's order among them)
function Vol.Slot(p_Also)
	local s_Datas = (Vol.datas ~= nil and #Vol.datas > 0) and Vol.datas or { Vol.data }
	local s_Used = {}

	for _, l_List in ipairs({ Vol.Drawn(), p_Also or {} }) do
		for _, l_Drawn in ipairs(l_List) do
			if l_Drawn.slot ~= nil then
				s_Used[l_Drawn.slot] = (s_Used[l_Drawn.slot] or 0) + 1
			end
		end
	end

	local s_Best = 1

	for l_K = 1, #s_Datas do
		if (s_Used[l_K] or 0) < (s_Used[s_Best] or 0) then
			s_Best = l_K
		end
	end

	return s_Best, s_Datas[s_Best]
end

-- p_Cam: the camera's place; p_Set(the box's entity, its matrix): sets it (the game's; a test's own)
function Vol.Order(p_Cam, p_Set)
	local s_List = Vol.Drawn()
	local s_Ordered = VOLUME.ORDER and p_Cam ~= nil and #s_List > 1

	if not s_Ordered then
		-- (one box, or no order: each at its middle, as the game would take it)
		for _, l_Drawn in ipairs(s_List) do
			if l_Drawn.dirty or l_Drawn.rank ~= nil then
				if p_Set(l_Drawn.entity, Vol.Steer(l_Drawn.raw, nil)) then
					l_Drawn.dirty, l_Drawn.rank = false, nil
				end
			end
		end

		Vol.orderCam = nil
		return 0
	end

	local function Length(p_V)
		return math.sqrt(p_V.x * p_V.x + p_V.y * p_V.y + p_V.z * p_V.z)
	end

	local s_Moved = Vol.orderCam == nil or Length(p_Cam - Vol.orderCam) > Vol.ORDER_SLACK
	local s_Nearest = nil

	for _, l_Drawn in ipairs(s_List) do
		local l_T = l_Drawn.raw.trans
		local l_Away = Vec3(math.max(0.0, math.abs(p_Cam.x - l_T.x) - l_Drawn.raw.left.x * 0.5),
			math.max(0.0, math.abs(p_Cam.y - l_T.y) - l_Drawn.raw.up.y * 0.5), math.max(0.0, math.abs(p_Cam.z - l_T.z) - l_Drawn.raw.forward.z * 0.5))
		l_Drawn.away = Length(l_Away)
		l_Drawn.middle = Length(p_Cam - l_T)
		s_Nearest = math.min(s_Nearest or l_Drawn.middle, l_Drawn.middle)
	end

	table.sort(s_List, function(p_A, p_B)
		if p_A.away ~= p_B.away then
			return p_A.away > p_B.away
		end

		return p_A.middle > p_B.middle
	end)

	local s_Set = 0
	local s_From = s_Moved and p_Cam or Vol.orderCam
	local s_Base = math.max(0.1, s_Nearest)

	for l_Rank, l_Drawn in ipairs(s_List) do
		if s_Moved or l_Drawn.dirty or l_Drawn.rank ~= l_Rank then
			local l_Sort = s_From + Vec3(0.0, s_Base + Vol.ORDER_GAP * (l_Rank - 1), 0.0)

			if p_Set(l_Drawn.entity, Vol.Steer(l_Drawn.raw, l_Sort)) then
				l_Drawn.dirty, l_Drawn.rank = false, l_Rank
				s_Set = s_Set + 1
			end
		end
	end

	Vol.orderCam = s_From
	Vol.orderSets = (Vol.orderSets or 0) + s_Set

	if not Vol.orderSaid and #s_List > 1 and LOG ~= nil then
		Vol.orderSaid = true
		local s_Meshes, s_Count = {}, 0

		for _, l_Drawn in ipairs(s_List) do
			if l_Drawn.slot ~= nil and not s_Meshes[l_Drawn.slot] then
				s_Meshes[l_Drawn.slot] = true
				s_Count = s_Count + 1
			end
		end

		LOG(string.format("the smoke's boxes drawn far to near (VOLUME.ORDER): %d at once on %d box mesh(es), the first time", #s_List, s_Count))
	end

	return s_Set
end

function Vol.EndOther(p_Other)
	for l_Index, l_Other in ipairs(Vol.others) do
		if l_Other == p_Other then
			table.remove(Vol.others, l_Index)
			break
		end
	end

	pcall(function() p_Other.entity:Destroy() end)

	if p_Other.down.logged ~= nil then
		LOG(string.format("smoke %d's volume of its own gone: its box set %d time(s)", p_Other.down.logged, p_Other.writes or 0))
	end
end

-- the canister (another smoke's) whose smoke drawn as a volume p_At is in (VOLUME.JOIN): the volume's -- in one of its points' boxes
-- that sees it -- or one of its own -- in its box; nil if none
function Vol.JoinWhich(p_At)
	-- (the room filling over time: anywhere among its places, smoke there yet or not -- its smoke poured in with that one's, no box of
	-- its own: Vol.SimJoin)
	if Vol.now ~= nil and type(Vol.now.cells) == "table" and (Vol.now.sim and Vol.SimInside(Vol.now.cells, p_At, true)
		or (not Vol.now.sim and Vol.Inside(Vol.now.cells, p_At))) then
		return Vol.now.down
	end

	for _, l_Other in ipairs(Vol.others) do
		local l_B = l_Other.box

		if not l_Other.gone and l_B ~= nil and p_At.x > l_B.x0 and p_At.x < l_B.x1 and p_At.y > l_B.y0 and p_At.y < l_B.y1
			and p_At.z > l_B.z0 and p_At.z < l_B.z1 then
			return l_Other.down
		end
	end

	return nil
end

-- ---- bullets through the smoke (VOLUME.HOLES) ---------------------------------------------------------------------------------------
-- A bullet that hits something leaves a hole in the smoke drawn along its way (back from where it hit, as far as Vol.HOLE_REACH): the
-- shader clears it within its HOLE_RADIUS of that way, its edge wavering, and the hole shuts over VOLUME.HOLE_SECONDS. Two at once
-- (two of the shader's numbers each): a bullet along the way of an open one (a burst) opens that one again; else it takes the shut one,
-- or the older -- with VOLUME.WAKE the first alone (the second a soldier's wake: Vol.WakeFrame). Their ends ride TsSmokeD, packed 8 bits an axis 8 cm apart from 2 m short of the grid's low corner (the shader's
-- HOLE_FROM, HOLE_SPAN): a hole further off than that is cut short to it.
Vol.HOLE_REACH = 60.0
Vol.HOLE_FROM = -2.0
Vol.HOLE_SPAN = 0.08
Vol.holes = {}
Vol.holeClock = 0.0
Vol.holeStamp = 0

-- the part of the way p_A..p_B within the box p_Box (x0..x1, y0..y1, z0..z1), or nil
function Vol.Clip(p_A, p_B, p_Box)
	local s_T0, s_T1 = 0.0, 1.0
	local s_D = p_B - p_A

	for _, l_Axis in ipairs({ { "x", "x0", "x1" }, { "y", "y0", "y1" }, { "z", "z0", "z1" } }) do
		local l_A, l_D = p_A[l_Axis[1]], s_D[l_Axis[1]]
		local l_Lo, l_Hi = p_Box[l_Axis[2]], p_Box[l_Axis[3]]

		if math.abs(l_D) < 1e-9 then
			if l_A < l_Lo or l_A > l_Hi then
				return nil
			end
		else
			local l_U, l_V = (l_Lo - l_A) / l_D, (l_Hi - l_A) / l_D
			s_T0, s_T1 = math.max(s_T0, math.min(l_U, l_V)), math.min(s_T1, math.max(l_U, l_V))

			if s_T0 > s_T1 then
				return nil
			end
		end
	end

	return p_A + s_D * s_T0, p_A + s_D * s_T1
end

-- where the holes' ends are counted from: the grid's low corner (TsSmokeB), or, with no room drawn as the volume, the corner of the
-- volume of its own the last hole went through
function Vol.HoleOrigin()
	return (Vol.now ~= nil and (Vol.now.drawOrigin or Vol.now.origin)) or Vol.holeOrigin or Vec3(0.0, 0.0, 0.0)
end

-- the holes' ends packed for the shader (TsSmokeD): 0 for a shut one
function Vol.HoleEnds()
	local s_O = Vol.HoleOrigin()

	local function Pack(p_V)
		local function Step(p_C)
			return math.max(0, math.min(255, math.floor((p_C - Vol.HOLE_FROM) / Vol.HOLE_SPAN + 0.5)))
		end

		return Step(p_V.x - s_O.x) + 256 * Step(p_V.y - s_O.y) + 65536 * Step(p_V.z - s_O.z)
	end

	local s_A, s_B = Vol.holes[1], Vol.holes[2]
	return Vec4(s_A ~= nil and Pack(s_A.a) or 0, s_A ~= nil and Pack(s_A.b) or 0, s_B ~= nil and Pack(s_B.a) or 0,
		s_B ~= nil and Pack(s_B.b) or 0)
end

-- a bullet (p_Entity) hit something (p_Hit): its way back from there through the smoke drawn, a hole along it
function Vol.Bullet(p_Entity, p_Hit)
	local s_At = p_Hit.position
	local s_Way = Unit(SpatialEntity(p_Entity).transform.forward)

	if s_At == nil or s_Way == nil then
		return
	end

	local s_From = s_At - s_Way * Vol.HOLE_REACH
	local s_A, s_B, s_Origin = nil, nil, nil

	if Vol.now ~= nil and Vol.now.bound ~= nil then
		-- (the box as drawn: an M320 round's ball sinking drawn lower, Vol.SimSink)
		s_A, s_B = Vol.Clip(s_From, s_At, Vol.now.drawBound or Vol.now.bound)
	end

	if s_A == nil then
		for _, l_Other in ipairs(Vol.others) do
			if not l_Other.gone and l_Other.box ~= nil then
				s_A, s_B = Vol.Clip(s_From, s_At, l_Other.box)

				if s_A ~= nil then
					s_Origin = Vec3(l_Other.box.x0, l_Other.box.y0, l_Other.box.z0)
					break
				end
			end
		end
	end

	if s_A == nil then
		return
	end

	if Vol.now == nil then
		Vol.holeOrigin = s_Origin
	end

	-- (and within what the packed ends reach)
	local s_O = Vol.HoleOrigin()
	local s_Far = Vol.HOLE_FROM + 255.0 * Vol.HOLE_SPAN
	s_A, s_B = Vol.Clip(s_A, s_B, { x0 = s_O.x + Vol.HOLE_FROM, y0 = s_O.y + Vol.HOLE_FROM, z0 = s_O.z + Vol.HOLE_FROM, x1 = s_O.x + s_Far,
		y1 = s_O.y + s_Far, z1 = s_O.z + s_Far })

	if s_A == nil then
		return
	end

	-- along the way of an open hole (both ends within its radius and a half of that way): that one, opened again
	local function Off(p_P, p_Hole)
		local l_Line = p_Hole.b - p_Hole.a
		local l_Length = math.sqrt(Dot(l_Line, l_Line))

		if l_Length < 0.01 then
			return 1e9
		end

		local l_To = p_P - p_Hole.a
		local l_Across = Cross(l_To, l_Line)
		return math.sqrt(Dot(l_Across, l_Across)) / l_Length
	end

	local s_Slot = nil
	-- (the second hole a soldier's wake, VOLUME.WAKE: the bullets' the first alone)
	local s_Slots = VOLUME.WAKE and 1 or 2

	for l_Index = 1, s_Slots do
		local l_Hole = Vol.holes[l_Index]

		if l_Hole ~= nil and Off(s_A, l_Hole) < 0.75 and Off(s_B, l_Hole) < 0.75 then
			s_Slot = l_Index
			break
		end
	end

	if s_Slot == nil and s_Slots == 1 then
		s_Slot = 1
	elseif s_Slot == nil then
		s_Slot = Vol.holes[1] == nil and 1 or (Vol.holes[2] == nil and 2 or (Vol.holes[1].born <= Vol.holes[2].born and 1 or 2))
	end

	Vol.holes[s_Slot] = { a = s_A, b = s_B, born = Vol.holeClock }
	Vol.holeStamp = Vol.holeStamp + 1
	Vol.holeCount = (Vol.holeCount or 0) + 1

	-- (the first of a level: the hook's bullets do reach the smoke)
	if Vol.holeCount == 1 then
		LOG(string.format("a bullet's hole through the smoke: from (%.1f, %.1f, %.1f) to (%.1f, %.1f, %.1f), in %s", s_A.x, s_A.y, s_A.z,
			s_B.x, s_B.y, s_B.z, s_Origin ~= nil and "a volume of its own" or "the room's volume"))
	end
end

-- ---- a soldier's wake through the smoke (VOLUME.WAKE) --------------------------------------------------------------------------------
-- A soldier moving (Vol.WAKE_SPEED and faster) through the room's smoke -- their chest in one of its places' boxes whose smoke is drawn
-- and that sees its place, as the camera is counted in it -- leaves a wake: the second hole, along the way from a tail following them
-- (Vol.WAKE_LAG: about a metre behind at a run, closing up on them as they stop) to them, chest high (Vol.WAKE_CHEST); the shader
-- draws it wider and taller than a bullet's (WAKE_RADIUS, WAKE_TALL), opening towards them. It opens and shuts over Vol.WAKE_OPEN s:
-- shut once they stop or leave the smoke. One at a time: the nearest the camera, another player before the camera's own; another
-- soldier takes it over once it has shut. A soldier's speed is over the time since they last moved (another player's may move at the
-- network's pace, not every frame), along the floor.
Vol.WAKE_SPEED = 0.4
Vol.WAKE_LAG = 0.6
Vol.WAKE_CHEST = 0.9
Vol.WAKE_OPEN = 0.3
Vol.WAKE_STILL = 0.25   -- a soldier not moved for this long (s) is standing still

function Vol.WakeFrame(p_Delta)
	local s_W = Vol.wake

	if s_W == nil then
		s_W = { open = 0.0, seen = {} }
		Vol.wake = s_W
	end

	local s_Now = Vol.now
	local s_Up = Vec3(0.0, Vol.WAKE_CHEST, 0.0)
	local s_Moving = {}

	-- (the soldiers moving through the room's smoke drawn, and of them the one to take the wake: another player before the camera's
	-- own, then the nearest the camera)
	if VOLUME.WAKE and VOLUME.HOLES and s_Now ~= nil and s_Now.sim and s_Now.drawBound ~= nil and PlayerManager ~= nil then
		local s_Camera = ClientUtils:GetCameraTransform()
		local s_Eye = s_Camera ~= nil and s_Camera.trans or nil
		local s_Local = PlayerManager:GetLocalPlayer()
		local s_Seen, s_Best = {}, nil

		for _, l_Player in pairs(PlayerManager:GetPlayers()) do
			local l_Soldier = l_Player.soldier

			if l_Soldier ~= nil and l_Soldier.isAlive then
				-- (a copy: the soldier's own moves on with them)
				local l_T = l_Soldier.worldTransform.trans
				local l_At = Vec3(l_T.x, l_T.y, l_T.z)
				local l_Was = s_W.seen[l_Player.id]
				local l_Speed, l_Since = 0.0, p_Delta

				if l_Was ~= nil then
					local l_Moved = l_At - l_Was.at
					local l_Far = math.sqrt(l_Moved.x * l_Moved.x + l_Moved.z * l_Moved.z)
					l_Since = l_Was.since + p_Delta

					if l_Far > 0.001 then
						l_Speed, l_Since = l_Far / l_Since, 0.0
					elseif l_Since < Vol.WAKE_STILL then
						l_Speed = l_Was.speed
					end
				end

				s_Seen[l_Player.id] = { at = l_At, speed = l_Speed, since = l_Since }
				local l_Chest = l_At + s_Up

				if l_Speed >= Vol.WAKE_SPEED and Vol.InBox(s_Now.drawBound, l_Chest)
					and Vol.SimInside(s_Now.cells, l_Chest + Vec3(0.0, s_Now.sinkDrawn or 0.0, 0.0)) then
					local l_Way = s_Eye ~= nil and l_Chest - s_Eye or Vec3(0.0, 0.0, 0.0)
					local l_Pick = { id = l_Player.id, at = l_At, other = l_Player ~= s_Local, far = Dot(l_Way, l_Way) }
					s_Moving[l_Player.id] = l_Pick

					if s_Best == nil or (l_Pick.other and not s_Best.other)
						or (l_Pick.other == s_Best.other and l_Pick.far < s_Best.far) then
						s_Best = l_Pick
					end
				end
			end
		end

		s_W.seen = s_Seen
		s_Moving.best = s_Best
	else
		s_W.seen = {}
	end

	-- (the one it is open for on while it is open: shutting once they stop or leave; another taking it over once shut)
	local s_Target = nil

	if s_W.who ~= nil and s_W.open > 0.0 then
		s_Target = s_Moving[s_W.who]
	elseif s_Moving.best ~= nil then
		s_Target = s_Moving.best
		s_W.who, s_W.head, s_W.tail = s_Target.id, s_Target.at, s_Target.at
	end

	local s_Step = p_Delta / Vol.WAKE_OPEN
	s_W.open = s_Target ~= nil and math.min(1.0, s_W.open + s_Step) or math.max(0.0, s_W.open - s_Step)

	if s_Target ~= nil then
		s_W.head = s_Target.at
	end

	if s_W.open <= 0.0 or s_W.head == nil then
		s_W.who, s_W.head, s_W.tail, s_W.packed = nil, nil, nil, nil

		if Vol.holes[2] ~= nil and Vol.holes[2].wake then
			Vol.holes[2] = nil
			Vol.holeStamp = Vol.holeStamp + 1
		end

		return
	end

	s_W.tail = s_W.tail + (s_W.head - s_W.tail) * math.min(1.0, p_Delta / Vol.WAKE_LAG)
	local s_Hole = { a = s_W.tail + s_Up, b = s_W.head + s_Up, wake = true, open = s_W.open, born = Vol.holeClock }
	Vol.holes[2] = s_Hole
	-- (written again once either end has moved a step of the packed ends, Vol.HoleEnds)
	local s_Packed = Vol.HoleEnds()

	if s_W.packed == nil or s_Packed.z ~= s_W.packed.z or s_Packed.w ~= s_W.packed.w then
		s_W.packed = s_Packed
		Vol.holeStamp = Vol.holeStamp + 1
	end
end

-- each frame: the holes shutting (their opening as the shader gets it: 1 and easing down to nothing over VOLUME.HOLE_SECONDS; the
-- first's in 127ths, the second's in 63rds, the bit over them a soldier's wake, as open as Vol.WakeFrame has it), a shut one let go;
-- with no room drawn as the volume (a volume of its own alone), their numbers written here (else Vol.Frame writes them with the
-- volume's)
function Vol.HoleFrame(p_Delta)
	Vol.holeClock = Vol.holeClock + p_Delta
	Vol.WakeFrame(p_Delta)
	local s_Bits = 0

	for l_Index = 1, 2 do
		local l_Hole = Vol.holes[l_Index]

		if l_Hole ~= nil and l_Hole.wake then
			local l_Left = l_Hole.open
			s_Bits = s_Bits + 65536 * (64 + math.max(0, math.min(63, math.floor(l_Left * l_Left * (3.0 - 2.0 * l_Left) * 63.0 + 0.5))))
		elseif l_Hole ~= nil then
			local l_Left = 1.0 - (Vol.holeClock - l_Hole.born) / math.max(VOLUME.HOLE_SECONDS or 2.0, 0.05)
			local l_Most = l_Index == 1 and 127 or 63

			if l_Left <= 0.0 then
				Vol.holes[l_Index] = nil
			else
				local l_Open = math.floor(l_Left * l_Left * (3.0 - 2.0 * l_Left) * l_Most + 0.5)
				s_Bits = s_Bits + (l_Index == 1 and 512 or 65536) * math.max(0, math.min(l_Most, l_Open))
			end
		end
	end

	Vol.holeBits = s_Bits

	-- (with no room drawn as the volume, the camera near a volume of its own is worked out here; else Vol.Frame does it)
	if Vol.now == nil then
		local s_Camera = (#Vol.others > 0 and ClientUtils ~= nil) and ClientUtils:GetCameraTransform() or nil
		Vol.nearBit = (s_Camera ~= nil and Vol.Near(s_Camera.trans)) and Vol.NEAR_BIT or 0
	end

	if Vol.now == nil and (s_Bits ~= (Vol.holeWritten or 0) or Vol.holeStamp ~= Vol.holeWrittenStamp
		or (Vol.nearBit or 0) ~= (Vol.nearWritten or 0)) then
		local s_O = Vol.HoleOrigin()
		local s_LookA, s_LookB = Vol.Look()

		if Vol.SetParams({ TsSmokeB = Vec4(s_O.x, s_O.y, s_O.z, 1.0), TsSmokeC = Vec4(0.0, s_LookA, s_LookB, Vol.ModeWord(0)),
			TsSmokeD = Vol.HoleEnds() }) then
			Vol.holeWritten, Vol.holeWrittenStamp, Vol.nearWritten = s_Bits, Vol.holeStamp, Vol.nearBit or 0
		end
	end
end

-- How deep the camera (p_At) is in a volume of its own, 0 to 1 (as Vol.FogAt): in its box, within its grown smoke, seen from its
-- canister's point, once the smoke has got there and thickened
function Vol.FogOther(p_Room, p_Age, p_At)
	local s_Other = p_Room.other
	local s_B = s_Other.box

	if p_Room.ready == nil or p_At.x < s_B.x0 or p_At.x > s_B.x1 or p_At.y < s_B.y0 or p_At.y > s_B.y1 or p_At.z < s_B.z0
		or p_At.z > s_B.z1 or not Vol.Sees(p_Room.cells[1], p_At) then
		return 0.0
	end

	local s_Grown = math.min(Vol.Grow(p_Room) * math.max(0.0, p_Age - p_Room.ready), Vol.Spreads(p_Room))
	local s_Far = Vol.FrontDistance(p_At, s_Other.mouth)
	local s_Front = VOLUME.FOG_DRAWN and math.max(0.0, math.min(1.0, (s_Grown - s_Far) / Vol.FRONT)) or 1.0

	if VOLUME.FOG_DRAWN and (s_Other.top or 0) > 0 then
		s_Front = s_Front * Vol.TopFade(s_B.y1, p_At)
	end

	local s_There = p_Room.ready + s_Far / Vol.Grow(p_Room)
	return math.max(0.0, math.min(1.0, (p_Age - s_There) / (p_Room.fogRise or ROOM_FOG_RISE))) * s_Front
		* Vol.FogStrength(s_Other.down, s_Other.strength)
end

-- ---- the smoke out of a room's openings to the open (VOLUME.EXITS) ---------------------------------------------------------------------
-- Where the room's measuring met open sky past a point (VOLUME.UNDER_ROOF: a window, a door to the open), the room's smoke pours out
-- once it gets there: the places out there next to the opening are points of the room's grid as well (the same box draws them, in the
-- same march: two boxes of ours drawn over one another flicker, the game drawing them in an order of its own), each got to a cell
-- further along the smoke's way than the point of the room it was met from. Only the places the measuring met through the opening:
-- the smoke comes out at the opening's height and thins out above it and a cell out (the grid's soft edge), never a slab outside.
-- The openings: the places out of the room met side by side (across or up) on one side of it, each group one opening.
function Vol.Openings(p_Room)
	local s_Groups = {}

	for _, l_Open in ipairs(p_Room.openings or {}) do
		local l_Into = nil

		for _, l_Group in ipairs(s_Groups) do
			for _, l_Other in ipairs(l_Group.list) do
				if l_Group.side == l_Open.side
					and math.abs(l_Other.i - l_Open.i) + math.abs(l_Other.j - l_Open.j) + math.abs(l_Other.k - l_Open.k) == 1 then
					l_Into = l_Group
					break
				end
			end

			if l_Into ~= nil then
				break
			end
		end

		if l_Into == nil then
			l_Into = { side = l_Open.side, list = {} }
			s_Groups[#s_Groups + 1] = l_Into
		end

		l_Into.list[#l_Into.list + 1] = l_Open
	end

	return s_Groups
end

-- the places out of the room's nearest VOLUME.EXITS openings (by the smoke's way to them), as points of its grid: each place met out
-- there a cell along the smoke's way past the point it was met from, and round it -- a cell further out, a cell to either side, at the
-- same height -- the ones a clear ray from it gets to, under the open sky and no point of the room: a puff a few cells across in front
-- of the opening (one cell alone is thin all over: the grid's soft edge). Nothing measured round them (each box its whole place).
function Vol.ExitCells(p_Room)
	if p_Room.exitCells ~= nil then
		return p_Room.exitCells
	end

	local s_Groups = Vol.Openings(p_Room)

	for _, l_Group in ipairs(s_Groups) do
		l_Group.way = math.huge

		for _, l_Open in ipairs(l_Group.list) do
			l_Group.way = math.min(l_Group.way, (l_Open.cell.path or 0.0) + ROOM_CELL)
		end
	end

	table.sort(s_Groups, function(p_A, p_B) return p_A.way < p_B.way end)
	local s_Room = {}

	for _, l_Cell in ipairs(p_Room.cells) do
		s_Room[l_Cell.i .. "," .. l_Cell.j .. "," .. l_Cell.k] = true
	end

	local s_Cells, s_Seen = {}, {}

	local function Add(p_I, p_J, p_K, p_At, p_Path)
		local l_Key = p_I .. "," .. p_J .. "," .. p_K

		if not s_Seen[l_Key] and not s_Room[l_Key] then
			s_Seen[l_Key] = true
			s_Cells[#s_Cells + 1] = { i = p_I, j = p_J, k = p_K, at = p_At, gaps = {}, path = p_Path, exit = true }
		end
	end

	for l_Index = 1, math.min(#s_Groups, VOLUME.EXITS or 0) do
		for _, l_Open in ipairs(s_Groups[l_Index].list) do
			local l_Path = (l_Open.cell.path or 0.0) + ROOM_CELL
			Add(l_Open.i, l_Open.j, l_Open.k, l_Open.at, l_Path)
			local l_Way = Vol.WAYS[l_Open.side]
			local l_Steps = { { l_Way[1], l_Way[3] }, { l_Way[3], l_Way[1] }, { -l_Way[3], -l_Way[1] } }

			for _, l_Step in ipairs(l_Steps) do
				local l_I, l_K = l_Open.i + l_Step[1], l_Open.k + l_Step[2]
				local l_At = l_Open.at + Vec3(l_Step[1] * ROOM_CELL, 0.0, l_Step[2] * ROOM_CELL)
				local l_Sky = Vec3(l_At.x, math.max(l_At.y, p_Room.ceiling or l_At.y) + ROOM_CEILING, l_At.z)

				if not s_Seen[l_I .. "," .. l_Open.j .. "," .. l_K] and RaycastManager:Raycast(l_Open.at, l_At, RAY_FLAGS) == nil
					and RaycastManager:Raycast(l_At, l_Sky, RAY_FLAGS) == nil then
					Add(l_I, l_Open.j, l_K, l_At, l_Path + ROOM_CELL)
				end
			end
		end
	end

	p_Room.exitCells = s_Cells
	p_Room.exitGroups = math.min(#s_Groups, VOLUME.EXITS or 0)
	return s_Cells
end

-- a room measured (or, for an M320 round's smoke drawn as its place is measured, its first places: Vol.Early) taken by the volume:
-- inside another smoke's drawn as a volume it joins that one (VOLUME.JOIN); else the room drawn as a volume, if it can be (one at a
-- time, measured for it): then no streams; else a volume of its own (VOLUME.OTHERS)
function Vol.Take(p_Down)
	local s_Room = p_Down.room
	local s_Join = s_Room.forVolume and VOLUME.JOIN and Vol.JoinWhich(s_Room.source) or nil
	-- (VOLUME.MERGE: a canister into the room filling over time, among its places or near enough for its grid to take in both)
	local s_Merge, s_Why = nil, nil

	if s_Room.forVolume and (s_Join == nil or (Vol.now ~= nil and s_Join == Vol.now.down)) then
		s_Merge, s_Why = Vol.MergeWhere(s_Room)
	end

	if s_Merge ~= nil and s_Merge.recede then
		-- (too far for one grid with the smoke there: that smoke gives way first, VOLUME.RECEDE)
		Vol.RecedeStart(p_Down, s_Merge)
	elseif s_Merge ~= nil then
		Vol.PourInto(p_Down, s_Merge)
	elseif s_Join ~= nil then
		-- that smoke lasts on from now, as long as a new one; this one's room is drawn by it
		s_Join.room.start = s_Join.age
		s_Room.joined = s_Join
		s_Room.volume = true
		-- (filling over time: its smoke poured into that one's room)
		local s_Poured = Vol.now ~= nil and Vol.now.sim and Vol.now.down == s_Join and Vol.SimJoin(s_Join.room, s_Room)

		if p_Down.logged ~= nil then
			LOG(string.format("smoke %d went off in smoke %s's drawn smoke: it joins it, that one lasting on %.0f s from now%s",
				p_Down.logged, tostring(s_Join.logged or "(not logged)"), 1.0 + ROOM_STREAMS * ROOM_STREAM_EVERY + ROOM_STREAM_SECONDS
				+ ROOM_SMOKE_LIFE, s_Poured and string.format(", its %.0f m3 poured into that one's room", s_Room.amountMax or VOLUME.AMOUNT) or ""))
		end
	elseif s_Room.forVolume and Vol.Free() then
		local s_Ok, s_Started = pcall(Vol.Start, p_Down)

		if not s_Ok then
			LOG("⛔ the smoke's volume: " .. tostring(s_Started))
			pcall(Vol.End)
		end

		s_Room.volume = s_Ok and s_Started and Vol.now ~= nil
	elseif s_Room.forVolume and VOLUME.OTHERS and Vol.Ready() then
		-- the volume another smoke's: a volume of its own
		local s_Ok, s_Other = pcall(Vol.StartOther, p_Down)

		if not s_Ok then
			LOG("⛔ a smoke's volume of its own: " .. tostring(s_Other))
		end

		s_Room.other = s_Ok and s_Other or nil
		s_Room.volume = s_Room.other ~= nil

		if s_Why ~= nil and p_Down.logged ~= nil then
			LOG(string.format("smoke %d not poured into the room filling over time (VOLUME.MERGE): %s", p_Down.logged, s_Why))
		end
	end
end

-- where p_From (a smoke's room as measured so far) pours into the room filling over time (VOLUME.MERGE: Vol.SimMergeWhere); nil and
-- why not (nil: no room filling over time, or MERGE off)
function Vol.MergeWhere(p_From)
	local s_Now = Vol.now

	if not (VOLUME.MERGE and VOLUME.SIM) or s_Now == nil or not s_Now.sim or s_Now.down.room == p_From or s_Now.down.room.sim == nil then
		return nil
	end

	if s_Now.down.room.recede ~= nil then
		return nil, "the smoke there is giving way to another canister"
	end

	local s_Where, s_Why, s_Pick = Vol.SimMergeWhere(s_Now.down.room, p_From)

	-- (too far for one grid with the smoke there: that smoke giving way to it, VOLUME.RECEDE)
	if s_Where == nil and s_Pick ~= nil and (VOLUME.RECEDE or 0.0) > 0.0 then
		local l_Where, l_Why = Vol.SimRecedeWhere(s_Now.down.room, s_Pick)

		if l_Where == nil then
			return nil, s_Why .. "; " .. l_Why
		end

		return l_Where
	end

	return s_Where, s_Why
end

-- p_Down's smoke poured into the room filling over time at p_Where (Vol.SimMergeInto): that smoke lasting on from now, as long as a
-- new one; this one's room drawn by it, measured no further
function Vol.PourInto(p_Down, p_Where)
	local s_Room = p_Down.room
	local s_Into = Vol.now.down
	local s_Done = Vol.SimMergeInto(s_Into.room, s_Room, p_Where)
	s_Into.room.start = s_Into.age
	s_Room.joined = s_Into
	s_Room.volume = true

	if p_Down.logged ~= nil then
		local l_Way = s_Room.source - s_Into.room.source
		LOG(string.format("smoke %d poured into smoke %s's room filling over time (VOLUME.MERGE), %.1f m from its canister: at the"
			.. " room's place %d, %d, %d (%s), the grid moved over %d, %d place(s) to take in both (the smoke there and it %s places"
			.. " across; %d place(s) of room round it; %d measured place(s) left out, %.1f m3 of smoke back to the first canister), the"
			.. " room measured on for %.0f m3 in all; that one lasting on %.0f s from now", p_Down.logged,
			tostring(s_Into.logged or "(not logged)"), math.sqrt(Dot(l_Way, l_Way)), p_Where.i, p_Where.j, p_Where.k,
			s_Done.new and "measured now" or "one of its places already", s_Done.movedI, s_Done.movedK, p_Where.across, s_Done.room,
			s_Done.left, s_Done.back,
			(s_Into.room.amountMax or VOLUME.AMOUNT) + (s_Into.room.pouredIn or 0.0),
			1.0 + ROOM_STREAMS * ROOM_STREAM_EVERY + ROOM_STREAM_SECONDS + ROOM_SMOKE_LIFE))
	end
end

-- an M320 round's smoke drawn from the moment it hits (VOLUME.M320_EARLY): once Vol.EARLY_FIRST places round where it hit are measured
-- (its first frame) it is taken as a room measured whole would be (Vol.Take), growing from then on as far along its way as the places
-- measured so far reach; drawn again (Vol.Again) each time twice as many are measured -- while they are fewer than Vol.EARLY_UPTO of
-- the places its smoke fills (its amount over a place's size: past that, all of them are measured soon) -- and once all of them are
-- (RoomFrame). A smoke that could not be drawn then waits for its room measured whole, as a canister's does.
Vol.EARLY_FIRST = 4
Vol.EARLY_UPTO = 0.6

function Vol.Early(p_Down)
	local s_Room = p_Down.room

	if not s_Room.forVolume or not VOLUME.FLOW or not (VOLUME.ONE_WRITER and VOLUME.ONE_PASS) then
		return
	end

	local s_Clock = Vol.Clock()

	if s_Room.early == nil then
		if #s_Room.cells < Vol.EARLY_FIRST then
			return
		end

		-- (a canister's, filling over time: only into the grid, joining another's or poured into the room filling over time,
		-- VOLUME.MERGE; a volume of its own waits for its room measured whole, as before)
		if p_Down.kind ~= "m320" and not Vol.Free() and not (VOLUME.JOIN and Vol.JoinWhich(s_Room.source) ~= nil)
			and Vol.MergeWhere(s_Room) == nil then
			return
		end

		s_Room.early = { frame = s_Room.frames, points = #s_Room.cells, firstPoints = #s_Room.cells, again = 0 }
		Vol.Farthest(s_Room)
		s_Room.ready = p_Down.age
		Vol.Take(p_Down)

		if not s_Room.volume then
			s_Room.early.failed = true
			s_Room.ready = nil
		end
	elseif not s_Room.early.failed and s_Room.volume and s_Room.joined == nil and #s_Room.cells >= s_Room.early.points * 2
		and #s_Room.cells < Vol.EARLY_UPTO * (s_Room.amountMax or VOLUME.AMOUNT) / (ROOM_CELL * ROOM_CELL * s_Room.layer) then
		Vol.Farthest(s_Room)
		s_Room.early.points = #s_Room.cells

		if Vol.Again(p_Down) then
			s_Room.early.again = s_Room.early.again + 1
		end
	end

	Vol.Spent(s_Room, s_Clock, "drawMs")
end

-- the memory clean-up a little at a time (VOLUME.CLEANUP): every so many frames the young leftovers cleaned up (generational, asked
-- for each time: the game may set Lua back to its own way when a level loads -- said in the log when it had)
function Vol.Cleanup()
	Vol.cleanupFrames = (Vol.cleanupFrames or 0) + 1

	if Vol.cleanupFrames < VOLUME.CLEANUP then
		return
	end

	Vol.cleanupFrames = 0
	local s_Was = collectgarbage("generational", 0, 300)

	if s_Was ~= "generational" then
		LOG(string.format("the memory clean-up a little at a time (VOLUME.CLEANUP, every %d frames): Lua's was %s, generational from now",
			VOLUME.CLEANUP, tostring(s_Was)))
	end

	collectgarbage("step", 0)
end

-- the wall clock in milliseconds (nil where there is none)
function Vol.Clock()
	local s_Ok, s_Ns = pcall(function() return SharedUtils:GetTimeNS() end)
	return (s_Ok and tonumber(s_Ns) ~= nil) and tonumber(s_Ns) / 1000000.0 or nil
end

-- the time since p_From (Vol.Clock) added to p_Room's p_Field (ms), and the most of it in a frame to p_Field .. "Most"
function Vol.Spent(p_Room, p_From, p_Field)
	local s_Now = p_From ~= nil and Vol.Clock() or nil

	if s_Now == nil then
		return
	end

	p_Room[p_Field] = (p_Room[p_Field] or 0.0) + (s_Now - p_From)
	p_Room[p_Field .. "Most"] = math.max(p_Room[p_Field .. "Most"] or 0.0, s_Now - p_From)
end

-- one frame of a room filling: measured on; once measured, a stream more every ROOM_STREAM_EVERY, and every stream on its way
local function RoomFrame(p_Down, p_Delta)
	local s_Room = p_Down.room

	if not s_Room.done then
		local s_Clock = Vol.Clock()
		-- (VOLUME.MEASURE_MS: what is left of this frame's measuring time, all smokes together; none left, on in the next frame)
		local s_Cap = VOLUME.MEASURE_MS or 0.0
		s_Room.measureUntil = (s_Cap > 0.0 and s_Clock ~= nil) and s_Clock + s_Cap - (Vol.measureMs or 0.0) or nil

		if VOLUME.SIM and s_Room.joined ~= nil then
			-- (filling over time: a smoke that joined another's poured its smoke into that one's room; its own needs measuring no
			-- further)
			s_Room.flowEnd = "it joined another smoke's"
			Vol.FlowDone(s_Room)
		elseif s_Room.measureUntil == nil or s_Clock == nil or s_Room.measureUntil > s_Clock then
			RoomMeasure(s_Room, s_Room.forVolume and (p_Down.kind == "m320" and VOLUME.M320_RAYS or VOLUME.RAYS) or ROOM_RAYS)
		else
			s_Room.capped = (s_Room.capped or 0) + 1
		end

		Vol.Spent(s_Room, s_Clock, "ms")
		local s_After = s_Clock ~= nil and Vol.Clock() or nil
		Vol.measureMs = (Vol.measureMs or 0.0) + (s_After ~= nil and s_After - s_Clock or 0.0)

		if not s_Room.done then
			-- (an M320 round's smoke drawn as its place is measured; filling over time, VOLUME.SIM, a canister's as well)
			if (p_Down.kind == "m320" and VOLUME.M320_EARLY) or (p_Down.kind ~= "m320" and VOLUME.SIM) then
				local s_Ok, s_Err = pcall(Vol.Early, p_Down)

				-- (failing before it is drawn, it waits for its room measured whole; drawn, it is drawn again then)
				if not s_Ok and not s_Room.earlySaid then
					s_Room.earlySaid = true

					if not s_Room.volume then
						s_Room.early = s_Room.early or {}
						s_Room.early.failed = true
						s_Room.ready = nil
					end

					LOG("⛔ an M320 round's smoke drawn as its place is measured: " .. tostring(s_Err))
				end
			end

			return
		end

		local s_Early = s_Room.early ~= nil and not s_Room.early.failed
		s_Room.targets = StreamTargets(s_Room)
		s_Room.ready = s_Early and s_Room.ready or p_Down.age

		if p_Down.logged ~= nil then
			local s_Far, s_Top = 0.0, 0

			for _, l_Cell in ipairs(s_Room.cells) do
				s_Far = math.max(s_Far, l_Cell.reach)
				s_Top = math.max(s_Top, l_Cell.j)
			end

			LOG(string.format("smoke %d is %s (%s %.1f m over the floor%s): the room measured in %d frame(s) and %d ray(s): %d"
				.. " point(s) (%d left out as outdoors), as far as %.1f m, %d layer(s) of %.2f m%s; %d stream(s) to %d place(s)",
				p_Down.logged, s_Room.outside and "in the open, its cloud drawn as a volume" or "indoors",
				s_Room.outside and "its cloud's top" or "a ceiling", s_Room.height,
				((s_Room.drop or 0.0) > 0.0 and string.format(", %.2f m under the canister: it lies on something", s_Room.drop) or "")
				.. "; " .. tostring(s_Room.floorSaid) .. (s_Room.openSaid ~= nil and ("; " .. s_Room.openSaid) or "")
				.. (s_Room.farthest ~= nil and string.format("; its smoke flowed: %.0f of %.0f m3 filled (%s), the farthest %.1f m along"
				.. " its way, %d place(s) over a floor left out", s_Room.amount or 0.0, s_Room.amountMax or VOLUME.AMOUNT, tostring(s_Room.flowEnd),
				s_Room.farthest, s_Room.overFloors or 0) or ""),
				s_Room.frames, s_Room.rays, #s_Room.cells, s_Room.outdoors or 0, s_Far, s_Top + 1, s_Room.layer,
				s_Room.forVolume and " (for the volume)" or (" (NOT for the volume: " .. tostring(s_Room.notVolume) .. ")"),
				ROOM_STREAMS, #s_Room.targets) .. (s_Room.ms ~= nil and string.format("; its rays took %.1f ms (%.2f ms at most in a"
				.. " frame, %d ray(s) a frame; cut short by the frame's measuring time %d time(s), VOLUME.MEASURE_MS %.1f)", s_Room.ms,
				s_Room.msMost or 0.0, p_Down.kind == "m320" and VOLUME.M320_RAYS or VOLUME.RAYS, s_Room.capped or 0, VOLUME.MEASURE_MS or 0.0)
				or ""))
		end

		if s_Early then
			-- (an M320 round's smoke drawn since it hit: drawn again now with all of its place; one that joined another's stays so)
			local s_Clock = Vol.Clock()
			local s_Ok, s_Again = true, false

			if s_Room.joined == nil then
				Vol.Farthest(s_Room)
				s_Ok, s_Again = pcall(Vol.Again, p_Down)

				if not s_Ok then
					LOG("⛔ an M320 round's smoke drawn again with all of its place: " .. tostring(s_Again))
				end
			end

			Vol.Spent(s_Room, s_Clock, "drawMs")

			if p_Down.logged ~= nil then
				LOG(string.format("smoke %d was drawn from the moment %s: from its place's %d. frame of measuring, with"
					.. " %d point(s); drawn again %d time(s) as it was measured, and now with all %d of them (%s)%s", p_Down.logged,
					p_Down.kind == "m320" and "it hit (VOLUME.M320_EARLY)" or "it went off (VOLUME.SIM)",
					s_Room.early.frame, s_Room.early.firstPoints or 0, s_Room.early.again, #s_Room.cells,
					s_Room.joined ~= nil and "it joined another smoke" or (s_Ok and s_Again and "done" or "NOT drawn again"),
					s_Room.drawMs ~= nil and string.format("; drawing it again took %.1f ms (%.2f ms at most in a frame)", s_Room.drawMs,
					s_Room.drawMsMost or 0.0) or ""))
			end
		elseif not s_Room.volume then
			-- (taken now; one drawn already -- measured on for a canister poured into it, VOLUME.MERGE -- stays as it is)
			Vol.Take(p_Down)
		end

		-- a canister that held back its jet for the volume (VOLUME.JET) and whose room the volume does not draw after all (another
		-- smoke's took it meanwhile, or it failed): the jet pours now, with the streams (in the open, the plume); an M320 round's
		-- smoke, the round's own particles where it hit
		local s_Round = p_Down.kind == "m320"
		local s_Jet = s_Round and Vol.m320Particles or (s_Room.outside and m_SmokeEffect or m_SmokeIndoorEffect)

		if not s_Room.volume and p_Down.effect == nil and s_Room.jetFrame ~= nil and s_Jet ~= nil then
			p_Down.effect = EffectManager:PlayEffect(s_Jet, s_Round and At(s_Room.mouth) or s_Room.jetFrame, EffectParams(), false)

			if p_Down.logged ~= nil then
				LOG(string.format("smoke %d: its %s is not drawn as the volume (%s), so its %s pours after all (%s)", p_Down.logged,
					s_Room.outside and "cloud" or "room", s_Room.forVolume and Vol.now == nil and "it failed to start" or Vol.WhyNot(),
					s_Round and "round's own particles" or (s_Room.outside and "plume" or "jet"), tostring(p_Down.effect)))
			end
		end
	end

	-- (an M320 round's smoke is the volume or the round's own particles: no streams)
	if s_Room.volume or s_Room.outside or p_Down.kind == "m320" then
		return
	end

	while s_Room.launched < ROOM_STREAMS and p_Down.age - s_Room.ready >= s_Room.launched * ROOM_STREAM_EVERY do
		s_Room.launched = s_Room.launched + 1
		local l_Target = s_Room.targets[(s_Room.launched - 1) % #s_Room.targets + 1]
		local l_Path = StreamPath(s_Room.mouth, l_Target)
		local l_Stream = { path = l_Path, at = l_Path[1], leg = 1, t = 0.0 }
		l_Stream.effect = EffectManager:PlayEffect(m_SmokeRoomEffect, At(l_Stream.at), EffectParams(), false)
		s_Room.streams[#s_Room.streams + 1] = l_Stream
	end

	for _, l_Stream in ipairs(s_Room.streams) do
		if not l_Stream.done then
			l_Stream.done = StreamMove(l_Stream, p_Delta)

			-- at its place it stays, letting smoke out there for the rest of its time (its smoke, let out clear, thickens the room there)
			if l_Stream.effect ~= nil then
				pcall(function() EffectManager:SetEffectTransform(l_Stream.effect, At(l_Stream.at)) end)
			end
		end
	end
end

-- How deep p_Camera is in the smoke of a room being filled, 0 to 1, p_Age seconds into the canister's life: near one of the room's
-- points (within ROOM_CELL) with nothing in between (a wall in between is outside), once the streams have got there (flowing out at
-- about their mean speed) and thickening over ROOM_FOG_RISE; thinning out over the smoke's life once the streams stop.
local function FogAmount(p_Room, p_Age, p_Camera)
	-- (an M320 round's smoke drawn while its place is measured: as drawn)
	if (not p_Room.done and not p_Room.volume) or p_Room.ready == nil then
		return 0.0
	end

	-- drawn as the volume: in its boxes, the same smoke the view shows (or in its own box; a smoke that joined another's, in that one's)
	if p_Room.volume then
		return p_Room.other ~= nil and Vol.FogOther(p_Room, p_Age, p_Camera) or Vol.FogAt(p_Room, p_Age, p_Camera)
	elseif p_Room.outside then
		return 0.0
	end

	local s_Since = p_Age - p_Room.ready
	local s_Stopped = ROOM_STREAMS * ROOM_STREAM_EVERY + ROOM_STREAM_SECONDS
	local s_Left = 1.0

	if s_Since > s_Stopped then
		s_Left = math.max(0.0, 1.0 - (s_Since - s_Stopped) / ROOM_SMOKE_LIFE)
	end

	if s_Left <= 0.0 then
		return 0.0
	end

	local s_Near, s_Cell = nil, nil

	for _, l_Cell in ipairs(p_Room.cells) do
		local l_Way = p_Camera - l_Cell.at
		local l_Distance = math.sqrt(Dot(l_Way, l_Way))

		if l_Distance <= ROOM_CELL and (s_Near == nil or l_Distance < s_Near) then
			s_Near, s_Cell = l_Distance, l_Cell
		end
	end

	if s_Cell == nil then
		return 0.0
	end

	local s_There = s_Cell.reach / ((ROOM_STREAM_SPEED + ROOM_STREAM_SLOW) * 0.5)
	local s_Thick = math.max(0.0, math.min(1.0, (s_Since - s_There) / ROOM_FOG_RISE))

	if s_Thick <= 0.0 or RaycastManager:Raycast(s_Cell.at, p_Camera, RAY_FLAGS) ~= nil then
		return 0.0
	end

	return s_Thick * s_Left * (1.0 - 0.5 * s_Near / ROOM_CELL)
end

local function Spawn(p_Pose, p_Frame, p_Start, p_Smoke)
	local s_Entity = EntityManager:CreateEntity(m_CanisterData, p_Pose)

	if s_Entity ~= nil then
		s_Entity:Init(Realm.Realm_Client, true)
	end

	local s_Effect = p_Smoke ~= nil and EffectManager:PlayEffect(p_Smoke, p_Frame, EffectParams(), false) or nil
	local s_Hiss = m_HissEffect ~= nil and EffectManager:PlayEffect(m_HissEffect, p_Frame, EffectParams(), false) or nil
	local s_Down = { entity = s_Entity, effect = s_Effect, hiss = s_Hiss, pose = p_Pose, start = p_Start, age = 0.0, stopped = false }
	m_Down[#m_Down + 1] = s_Down
	return s_Down
end

-- one canister per grenade: a client can hold the thrower's own copy and the server's (same place, same moment)
-- (the two copies can go off a frame or more apart, one still in the air over where the other lies: within 1.5 m along the ground and
-- 3 m up or down of where the other went off, or of where its canister lies)
local function AlreadyDown(p_At)
	for _, l_Down in ipairs(m_Down) do
		if l_Down.age < 1.0 then
			for _, l_Then in ipairs({ l_Down.start, l_Down.pose ~= nil and l_Down.pose.trans or nil }) do
				local l_Way = p_At - l_Then

				if l_Way.x * l_Way.x + l_Way.z * l_Way.z < 1.5 * 1.5 and math.abs(l_Way.y) < 3.0 then
					return true
				end
			end
		end
	end

	return false
end

local function PutDown(p_T)
	local s_Pose, s_How = RestPose(p_T)
	local s_Floor, s_Ceiling, s_Outside, s_Open = SmokePlace(s_Pose)

	if s_Floor ~= nil and not s_Outside then
		s_Pose, s_How = IndoorPose(s_Pose, p_T.trans, s_How)
	end

	local s_Frame, s_Axis = SmokeFrame(s_Pose, true)
	-- indoors the jet, in the open the plume, unless the volume is to draw the room or the cloud (VOLUME.JET)
	local s_Smoke = m_SmokeEffect

	if s_Floor ~= nil then
		s_Smoke = s_Outside and m_SmokeEffect or m_SmokeIndoorEffect

		if not VOLUME.JET and Vol.WillDraw() then
			s_Smoke = nil
		end
	end

	local s_Down = Spawn(s_Pose, s_Frame, p_T.trans, s_Smoke)

	if s_Floor ~= nil then
		StartRoom(s_Down, s_Floor, s_Ceiling, s_Frame, s_Outside)
		s_Down.room.openSaid = s_Open
	end

	if m_Logged < SMOKES_LOGGED then
		m_Logged = m_Logged + 1
		s_Down.logged = m_Logged
		LOG(string.format("smoke %d went off at %.2f %.2f %.2f: canister %s (%s) at %.2f %.2f %.2f, smoke %s along %.2f %.2f, hiss %s",
			m_Logged, p_T.trans.x, p_T.trans.y, p_T.trans.z, s_Down.entity ~= nil and "put down" or "NOT created", s_How, s_Pose.trans.x,
			s_Pose.trans.y, s_Pose.trans.z, s_Down.effect ~= nil and tostring(s_Down.effect) or "held back for the volume", s_Axis.x,
			s_Axis.z, tostring(s_Down.hiss)))
	end
end

-- went off in the air: the canister, as the grenade was, falls on with the grenade's speed, smoking from its top; its smoke stays where
-- it was let out (a trail up along the fall) and, once it lies, pours on out of it there
local function Fall(p_T, p_Velocity)
	local s_Frame = SmokeFrame(p_T, false)
	-- (its trail of particles only when the volume is not to draw its smoke: they would be left hanging in the air over it)
	local s_Trail = (VOLUME.JET or not Vol.WillDraw()) and (m_SmokeFallEffect or m_SmokeEffect) or nil
	local s_Down = Spawn(p_T, s_Frame, p_T.trans, s_Trail)
	s_Down.falling = true
	s_Down.position = p_T.trans
	s_Down.velocity = p_Velocity
	s_Down.from = p_T.trans

	if m_Logged < SMOKES_LOGGED then
		m_Logged = m_Logged + 1
		s_Down.logged = m_Logged
		LOG(string.format("smoke %d went off in the AIR at %.2f %.2f %.2f, speed %.2f %.2f %.2f: the canister%s falls on, smoking (%s, %s)",
			m_Logged, p_T.trans.x, p_T.trans.y, p_T.trans.z, p_Velocity.x, p_Velocity.y, p_Velocity.z,
			s_Down.entity ~= nil and "" or " (NOT created)", tostring(s_Down.effect), s_Trail == nil and "no trail: the volume draws its smoke"
			or (m_SmokeFallEffect ~= nil and "its smoke left as a trail" or "its smoke carried along")))
	end
end

local function MoveTo(p_Down, p_Pose, p_OnGround)
	p_Down.pose = p_Pose

	if p_Down.entity ~= nil then
		pcall(function() SpatialEntity(p_Down.entity).transform = p_Pose end)
	end

	local s_Frame = SmokeFrame(p_Pose, p_OnGround)

	if p_Down.effect ~= nil then
		pcall(function() EffectManager:SetEffectTransform(p_Down.effect, s_Frame) end)
	end

	if p_Down.hiss ~= nil and not p_Down.stopped then
		pcall(function() EffectManager:SetEffectTransform(p_Down.hiss, s_Frame) end)
	end
end

-- a falling canister, one frame: in the air (as the grenade was) or sliding (lying on the ground: laid down once when the slide starts,
-- then carried along it), until it stops (laid there as any other)
local function Falling(p_Down, p_Delta)
	local s_Stopped = false

	if p_Down.sliding then
		s_Stopped = SlideStep(p_Down, p_Delta)
	else
		s_Stopped = FallStep(p_Down, p_Delta)
	end

	local s_T = p_Down.pose
	local s_At = LinearTransform(s_T.left, s_T.up, s_T.forward, p_Down.position)

	if not s_Stopped and not p_Down.sliding then
		p_Down.lying = nil
		MoveTo(p_Down, s_At, false)
		return
	end

	if not s_Stopped then
		if p_Down.lying == nil then
			local s_Lie = RestPose(s_At)
			p_Down.lying = s_Lie
			p_Down.lift = s_Lie.trans - p_Down.position
		end

		local s_Lie = p_Down.lying
		MoveTo(p_Down, LinearTransform(s_Lie.left, s_Lie.up, s_Lie.forward, p_Down.position + p_Down.lift), true)
		return
	end

	local s_Pose, s_How = RestPose(s_At)
	p_Down.falling = false
	p_Down.sliding = false
	local s_Floor, s_Ceiling, s_Outside, s_Open = SmokePlace(s_Pose)

	if s_Floor ~= nil and not s_Outside then
		s_Pose, s_How = IndoorPose(s_Pose, s_At.trans, s_How)
	end

	MoveTo(p_Down, s_Pose, true)

	-- indoors: the falling trail's jet stops (its smoke already out stays) and the indoor jet takes over from the mouth, the room's
	-- streams with it -- or the volume alone (VOLUME.JET); in the open with the volume to draw its cloud, the same with the plume
	if s_Floor ~= nil then
		local s_Frame = SmokeFrame(s_Pose, true)

		if p_Down.effect ~= nil then
			pcall(function() EffectManager:StopEffect(p_Down.effect) end)
		end

		p_Down.effect = nil

		if VOLUME.JET or not Vol.WillDraw() then
			p_Down.effect = EffectManager:PlayEffect(s_Outside and m_SmokeEffect or m_SmokeIndoorEffect, s_Frame, EffectParams(), false)
		end

		StartRoom(p_Down, s_Floor, s_Ceiling, s_Frame, s_Outside)
		p_Down.room.openSaid = s_Open
	end

	if p_Down.logged ~= nil then
		LOG(string.format("smoke %d landed after %.1f s, %d bounce(s), slid %.2f m, %.1f m below where it went off: %s", p_Down.logged,
			p_Down.age, p_Down.bounces or 0, p_Down.slid or 0.0, p_Down.from.y - s_Pose.trans.y, s_How))
	end
end

-- an M320's smoke round went off (VOLUME.M320): where it hit -- from its last place seen, on along its way to what it met -- its smoke
-- flows from, round there (a ball, sinking a little: M320_SHAPE_*, M320_GRAVITY) and down to the floor straight under it if that is no
-- more than M320_BELOW under it (a wall, a building's front hit higher up: the smoke round where it hit, down to that floor), else
-- hanging where it hit (its grid's floor M320_HANG under it, in the air); the room or the open round there measured and drawn as the
-- volume, from the moment it hits (M320_EARLY); but the round's own: no canister and no hiss (its detonation plays its own sound),
-- spreading at once (M320_GROW), M320_AMOUNT of it, thinning out from the start, gone after M320_SECONDS (Vol.Strength). With no
-- place for the volume, the round's own particles. The mortar's smoke round (p_Gone.kind "mortar", VOLUME.MORTAR) the same way -- its
-- explosion plays the same effect --, with its own MORTAR_GROW, MORTAR_AMOUNT and MORTAR_SECONDS; it comes down fast, its last place
-- seen a network update off where it hit -- short of it, or past it already under the ground (a ray from there meets nothing) --: its
-- hit looked for along its way from up to 30 m back (no farther back than where it was first seen: the round's entity let go while it
-- still climbs is no hit) to 40 m on, or coming down, straight under it; with nothing there (gone in the air, not gone off) it leaves
-- no smoke
function Vol.M320Off(p_Gone)
	local s_Mortar = p_Gone.kind == "mortar"
	local s_Seen = p_Gone.transform.trans
	local s_At = s_Seen
	local s_V = p_Gone.velocity or Vec3(0.0, 0.0, 0.0)
	local s_Speed = math.sqrt(Dot(s_V, s_V))
	local s_Hit = nil

	if s_Speed > 1.0 then
		local s_Dir = s_V * (1.0 / s_Speed)
		local s_Back = 0.5

		if s_Mortar and p_Gone.first ~= nil then
			local s_Came = s_Seen - p_Gone.first
			s_Back = math.max(0.5, math.min(30.0, math.sqrt(Dot(s_Came, s_Came))))
		end

		s_Hit = RaycastManager:Raycast(s_Seen - s_Dir * s_Back, s_Seen + s_Dir * math.min(s_Mortar and 40.0 or 8.0, s_Speed * 0.15 + 1.0),
			RAY_FLAGS)

		-- (a mortar's round coming down with nothing on its way -- its speed off a network update's jump --: straight under it, from
		-- 10 m over where it was seen last to 10 m under; never one still climbing)
		if s_Mortar and s_Hit == nil and s_V.y < 0.0 then
			s_Hit = RaycastManager:Raycast(s_Seen + Vec3(0.0, 10.0, 0.0), s_Seen - Vec3(0.0, 10.0, 0.0), RAY_FLAGS)
		end

		if s_Hit ~= nil then
			s_At = s_Hit.position + s_Hit.normal * 0.3
		end
	end

	if s_Mortar and s_Hit == nil then
		if m_Logged < SMOKES_LOGGED then
			local s_From = p_Gone.first or s_Seen
			LOG(string.format("a mortar's smoke round gone at %.2f %.2f %.2f (%.0f m/s, first seen at %.1f %.1f %.1f) with nothing on its"
				.. " way: no smoke", s_Seen.x, s_Seen.y, s_Seen.z, s_Speed, s_From.x, s_From.y, s_From.z))
		end

		return
	end

	if AlreadyDown(s_At) then
		return
	end

	-- its smoke's floor: the first thing facing up straight under where it hit, up to M320_BELOW under it; else it hangs there
	local s_Under = VOLUME.M320_BELOW > 0.0 and RaycastManager:Raycast(s_At, s_At - Vec3(0.0, VOLUME.M320_BELOW, 0.0), RAY_FLAGS) or nil
	local s_Hangs = s_Under == nil or s_Under.normal.y <= 0.3
	local s_FloorY = s_Hangs and s_At.y - VOLUME.M320_HANG or s_Under.position.y
	local s_How = s_Hangs and string.format("hanging where it hit: no floor within %.1f m under it", VOLUME.M320_BELOW)
		or string.format("its floor %.2f m under it", s_At.y - s_FloorY)
	-- (where it is placed as a canister lying on that floor would be: SmokePlace looks for the ceiling over it from there)
	local s_Floor, s_Ceiling, s_Outside, s_Open = SmokePlace(At(Vec3(s_At.x, s_FloorY + CANISTER_REST_HEIGHT + CANISTER_CLEARANCE, s_At.z)))
	-- (a round's smoke, kind "m320" either way; which round, and how long its smoke lasts)
	local s_Down = { pose = At(s_At), start = s_At, hit = s_At, age = 0.0, stopped = true, gone = true, kind = "m320",
		round = s_Mortar and "mortar" or "m320", seconds = s_Mortar and VOLUME.MORTAR_SECONDS or VOLUME.M320_SECONDS }
	m_Down[#m_Down + 1] = s_Down

	if s_Floor ~= nil then
		-- (its mouth -- the growing front's middle -- where it hit)
		StartRoom(s_Down, s_Floor, s_Ceiling, At(s_At - Vec3(0.0, JET_HEIGHT, 0.0)), s_Outside)
		s_Down.room.openSaid = s_Open
		s_Down.room.grow = s_Mortar and VOLUME.MORTAR_GROW or VOLUME.M320_GROW
		s_Down.room.amountMax = s_Mortar and VOLUME.MORTAR_AMOUNT or VOLUME.M320_AMOUNT
		s_Down.room.shape = { VOLUME.M320_SHAPE_X, VOLUME.M320_SHAPE_Y, VOLUME.M320_SHAPE_Z }
		s_Down.room.gravity = VOLUME.M320_GRAVITY
		-- (no floor under it: its grid's floor in the air, unless the rays round there found one; then no box drawn full from it)
		s_Down.room.hangs = s_Hangs and math.abs(s_Down.room.floor.y - s_FloorY) < 0.01
		-- (thick at once where it gets to, as the round's puffs are)
		s_Down.room.fogRise = 0.5
	elseif Vol.m320Particles ~= nil then
		s_Down.effect = EffectManager:PlayEffect(Vol.m320Particles, At(s_At), EffectParams(), false)
	end

	if m_Logged < SMOKES_LOGGED then
		m_Logged = m_Logged + 1
		s_Down.logged = m_Logged
		LOG(string.format("smoke %d is %s round: it hit at %.2f %.2f %.2f (%s; seen last at %.2f %.2f %.2f, %.0f m/s), its smoke"
			.. " from there (%s%s)%s", m_Logged, s_Mortar and "a mortar's" or "an M320's", s_At.x, s_At.y, s_At.z,
			s_Hit ~= nil and "on its way" or "where it was seen last",
			s_Seen.x, s_Seen.y, s_Seen.z, s_Speed, s_How, s_Down.room ~= nil and string.format("; the room's floor %.2f m under it%s",
			s_At.y - s_Down.room.floor.y, s_Down.room.hangs and ", in the air" or "") or "",
			s_Floor == nil and ": no place for the volume, the round's own particles" or ""))
	end
end

local function GoneOff(p_Gone)
	if p_Gone.kind == "m320" or p_Gone.kind == "mortar" then
		Vol.M320Off(p_Gone)
		return
	end

	local s_T = p_Gone.transform

	if AlreadyDown(s_T.trans) then
		if m_Logged < SMOKES_LOGGED then
			LOG(string.format("a smoke grenade went off at %.2f %.2f %.2f, within 1.5 m and 1 s of one that just did: taken for the"
				.. " same one (no canister of its own)", s_T.trans.x, s_T.trans.y, s_T.trans.z))
		end

		return
	end

	local s_Under = RaycastManager:Raycast(s_T.trans + Vec3(0.0, 0.1, 0.0), s_T.trans - Vec3(0.0, FALL_GROUND_GAP, 0.0), RAY_FLAGS)

	if s_Under ~= nil or not CANISTER_FALLS then
		PutDown(s_T)
	else
		Fall(s_T, p_Gone.velocity or Vec3(0.0, 0.0, 0.0))
	end
end

-- ---- the fog in the smoke (client) ---------------------------------------------------------------------------------------------------
-- A visual environment of our own, put together as one is at run time (a logic entity -> its blueprint -> the environment and its
-- components, here a single fog), enabled once a level is up and weighed every frame through its state's visibility: 0 out of smoke.
local FOG_GUIDS = "6B4E1801-0008-4D18-8018-0000000000"
local m_Fog = nil           -- { entity, shown, set, and the data it is made of (kept referenced) }

local function MakeFog()
	local s_Logic = LogicVisualEnvironmentEntityData(Guid(FOG_GUIDS .. "01"))
	local s_Blueprint = VisualEnvironmentBlueprint(Guid(FOG_GUIDS .. "02"))
	local s_Environment = VisualEnvironmentEntityData(Guid(FOG_GUIDS .. "03"))
	local s_FogData = FogComponentData(Guid(FOG_GUIDS .. "04"))

	s_Blueprint.name = "FX/TacticalSlots/VE_M18_Smoke_Fog"
	s_Blueprint.object = s_Environment
	s_Logic.visualEnvironment = s_Blueprint
	s_Logic.visibility = 1.0
	s_Environment.enabled = true
	s_Environment.priority = ROOM_FOG_PRIORITY
	s_Environment.visibility = 1.0

	s_FogData.excluded = false
	s_FogData.isEventConnectionTarget = 3
	s_FogData.isPropertyConnectionTarget = 3
	s_FogData.indexInBlueprint = 0
	s_FogData.transform = LinearTransform()
	s_FogData.realm = Realm.Realm_Client
	s_FogData.enable = true
	-- thick from the eye out to ROOM_FOG_END, in its own colour
	s_FogData.start = 0.0
	s_FogData.endValue = ROOM_FOG_END
	s_FogData.curve = Vec4(0.0, 0.0, 1.0, 0.0)
	s_FogData.fogDistanceMultiplier = 1.0
	s_FogData.fogColorEnable = true
	s_FogData.fogColor = ROOM_FOG_COLOR
	s_FogData.fogColorStart = 0.0
	s_FogData.fogColorEnd = ROOM_FOG_END
	s_FogData.fogColorCurve = Vec4(0.0, 0.0, 1.0, 0.0)
	s_FogData.transparencyFadeStart = 0.0
	s_FogData.transparencyFadeEnd = ROOM_FOG_END
	s_FogData.transparencyFadeClamp = 1.0
	s_FogData.fogGradientEnable = false
	s_FogData.heightFogEnable = false
	s_FogData.heightFogVisibilityRange = 100.0
	s_FogData.heightFogAltitude = 0.0
	s_FogData.heightFogDepth = 100.0
	s_FogData.heightFogFollowCamera = 0.0

	-- the whiteout: no contrast, darker, less colour
	local s_Whiteout = ColorCorrectionComponentData(Guid(FOG_GUIDS .. "05"))
	s_Whiteout.excluded = false
	s_Whiteout.isEventConnectionTarget = 3
	s_Whiteout.isPropertyConnectionTarget = 3
	s_Whiteout.indexInBlueprint = 1
	s_Whiteout.transform = LinearTransform()
	s_Whiteout.realm = Realm.Realm_Client
	s_Whiteout.enable = true
	s_Whiteout.brightness = Vec3(ROOM_WHITEOUT_BRIGHTNESS, ROOM_WHITEOUT_BRIGHTNESS, ROOM_WHITEOUT_BRIGHTNESS)
	s_Whiteout.contrast = Vec3(ROOM_WHITEOUT_CONTRAST, ROOM_WHITEOUT_CONTRAST, ROOM_WHITEOUT_CONTRAST)
	s_Whiteout.saturation = Vec3(ROOM_WHITEOUT_SATURATION, ROOM_WHITEOUT_SATURATION, ROOM_WHITEOUT_SATURATION)
	s_Whiteout.hue = ROOM_WHITEOUT_HUE
	s_Whiteout.colorGradingEnable = false

	s_Environment.components:add(s_FogData)
	s_Environment.components:add(s_Whiteout)
	s_Environment.runtimeComponentCount = 2

	local s_Entity = EntityManager:CreateEntity(s_Logic, LinearTransform())

	if s_Entity == nil then
		return nil
	end

	s_Entity:Init(Realm.Realm_Client, true)
	s_Entity:FireEvent("Enable")
	VisualEnvironmentManager:SetDirty(true)

	return { entity = s_Entity, shown = 0.0, set = -1.0, logic = s_Logic, blueprint = s_Blueprint, environment = s_Environment,
		fog = s_FogData, whiteout = s_Whiteout }
end

local function OurFog(p_State)
	return p_State.priority == ROOM_FOG_PRIORITY or p_State.priority == 10000000 + ROOM_FOG_PRIORITY
end

-- the level's own look under the fog (ROOM_FOG_MIRROR): of the states weighing anything -- not ours, not an effect's passing one --
-- the highest's fog and colour correction switches copied into ours (and the height fog's numbers, its texture of grading); what was
-- copied, said once a level
local function MirrorLevel(p_Ours)
	local s_Fog, s_FogP, s_Grade, s_GradeP = nil, -1, nil, -1

	for _, l_State in pairs(VisualEnvironmentManager:GetStates()) do
		if not OurFog(l_State) and l_State.entityName ~= "EffectEntity" and (l_State.visibility or 0.0) > 0.0 then
			if l_State.fog ~= nil and l_State.priority > s_FogP then
				s_Fog, s_FogP = l_State.fog, l_State.priority
			end

			if l_State.colorCorrection ~= nil and l_State.priority > s_GradeP then
				s_Grade, s_GradeP = l_State.colorCorrection, l_State.priority
			end
		end
	end

	local s_Said = {}
	local s_OurFog = p_Ours.fog
	local s_OurGrade = p_Ours.colorCorrection

	if s_Fog ~= nil and s_OurFog ~= nil then
		s_OurFog.fogColorEnable = s_Fog.fogColorEnable
		s_OurFog.fogGradientEnable = s_Fog.fogGradientEnable
		s_OurFog.heightFogEnable = s_Fog.heightFogEnable
		s_OurFog.heightFogVisibilityRange = s_Fog.heightFogVisibilityRange
		s_OurFog.heightFogAltitude = s_Fog.heightFogAltitude
		s_OurFog.heightFogDepth = s_Fog.heightFogDepth
		s_OurFog.heightFogFollowCamera = s_Fog.heightFogFollowCamera
		s_Said[#s_Said + 1] = string.format("fog colour of its own %s, gradient %s, height fog %s (priority %d)",
			tostring(s_Fog.fogColorEnable), tostring(s_Fog.fogGradientEnable), tostring(s_Fog.heightFogEnable), s_FogP)
	end

	if s_Grade ~= nil and s_OurGrade ~= nil then
		s_OurGrade.colorGradingEnable = s_Grade.colorGradingEnable
		s_OurGrade.colorGradingTexture = s_Grade.colorGradingTexture
		s_Said[#s_Said + 1] = string.format("colour grading %s (priority %d)", tostring(s_Grade.colorGradingEnable), s_GradeP)
	end

	VisualEnvironmentManager:SetDirty(true)
	local s_Line = #s_Said > 0 and table.concat(s_Said, ", ") or "none found to follow"

	if s_Line ~= m_Fog.mirrorSaid then
		m_Fog.mirrorSaid = s_Line
		LOG("the smoke's fog follows the level's own switches: " .. s_Line)
	end
end

-- the fog's weight now (its state: the one with our priority, as a logic entity's states are numbered 10000000 + its priority); as it
-- comes on, and each second while it weighs anything, its switches the level's (MirrorLevel)
local function SetFog(p_Visibility)
	if math.abs(m_Fog.set - p_Visibility) < 0.002 then
		return
	end

	for _, l_State in pairs(VisualEnvironmentManager:GetStates()) do
		if OurFog(l_State) then
			if ROOM_FOG_MIRROR and p_Visibility > 0.0 and (m_Fog.set <= 0.0 or (m_Fog.sinceMirror or 99.0) >= 1.0) then
				local s_Ok, s_Err = pcall(MirrorLevel, l_State)
				m_Fog.sinceMirror = 0.0

				if not s_Ok and not m_Fog.mirrorFailed then
					m_Fog.mirrorFailed = true
					LOG("⛔ the smoke's fog following the level's switches: " .. tostring(s_Err))
				end
			end

			l_State.visibility = p_Visibility
			VisualEnvironmentManager:SetDirty(true)

			if m_Fog.set < 0.0 then
				LOG(string.format("the smoke's fog is ready (its state found, priority %d)", l_State.priority))
			end

			m_Fog.set = p_Visibility
			return
		end
	end

	-- not there: looked for a while (it may take a frame or two to come up), then given up, said once
	m_Fog.tries = (m_Fog.tries or 0) + 1

	if m_Fog.tries > 300 then
		LOG(string.format("⛔ the smoke's fog: no visual environment state with priority %d came up -- no fog this level", ROOM_FOG_PRIORITY))
		m_Fog = nil
	end
end

-- every frame: how deep the camera is in any room's smoke, eased (no popping), as the fog's weight
local function FogFrame(p_Delta)
	local s_Target = 0.0
	local s_Camera = ClientUtils:GetCameraTransform()

	if s_Camera ~= nil then
		for _, l_Down in ipairs(m_Down) do
			if l_Down.room ~= nil and not l_Down.roomFailed then
				local l_Weight = FogAmount(l_Down.room, l_Down.age, s_Camera.trans)
				s_Target = math.max(s_Target, l_Weight)

				-- (how long the camera is in its smoke and how thick the fog gets there: said once it is gone, Vol.End)
				if l_Weight > 0.02 then
					l_Down.fogTime = (l_Down.fogTime or 0.0) + p_Delta
					l_Down.fogMost = math.max(l_Down.fogMost or 0.0, l_Weight)
				end
			end
		end
	end

	m_Fog.shown = m_Fog.shown + (s_Target * ROOM_FOG - m_Fog.shown) * math.min(1.0, p_Delta * 3.0)
	m_Fog.sinceMirror = (m_Fog.sinceMirror or 99.0) + p_Delta
	-- (its last hundredth, which shows nothing, let go at once: none of it weighs on past the smoke)
	SetFog(m_Fog.shown < 0.01 and 0.0 or m_Fog.shown)
end

if IS_CLIENT and SMOKE_ENABLED and SMOKE_BY_LUA and ROOM_SMOKE and ROOM_FOG > 0.0 then
	Events:Subscribe("Level:Loaded", function()
		local s_Ok, s_Fog = pcall(MakeFog)
		m_Fog = s_Ok and s_Fog or nil
		LOG(m_Fog ~= nil and "the smoke's fog made (visual environment, priority " .. tostring(ROOM_FOG_PRIORITY) .. ")" or
			("⛔ the smoke's fog could not be made: " .. tostring(s_Ok and "no entity" or s_Fog)))
	end)
end

-- the volume's numbers ride a visual environment of their own, made once a level is up
if IS_CLIENT and SMOKE_ENABLED and SMOKE_BY_LUA and ROOM_SMOKE and VOLUME.ON then
	Events:Subscribe("Level:Loaded", function()
		local s_Ok, s_Env = pcall(Vol.MakeEnv)
		Vol.env = s_Ok and s_Env or nil
		LOG(Vol.env ~= nil and "the smoke's volume environment made (priority " .. tostring(Vol.PRIORITY) .. ")" or
			("⛔ the smoke's volume environment could not be made: " .. tostring(s_Ok and "no entity" or s_Env)))
	end)
end

-- p_Kind: "m18" (ours, a canister), "m320" (the M320's smoke round, VOLUME.M320) or "mortar" (the mortar's, VOLUME.MORTAR)
local function Track(p_Entity, p_Kind)
	if p_Entity == nil then
		return
	end

	local s_Id = p_Entity.uniqueId

	if m_Grenades[s_Id] ~= nil then
		return
	end

	local s_Spatial = SpatialEntity(p_Entity)
	local s_First = s_Spatial.transform.trans
	-- (where it was first seen, copied: how far back along its way a mortar's round's hit may be looked for, Vol.M320Off)
	m_Grenades[s_Id] = { entity = s_Spatial, transform = s_Spatial.transform, velocity = Vec3(0.0, 0.0, 0.0), kind = p_Kind,
		first = Vec3(s_First.x, s_First.y, s_First.z) }

	-- (the first mortar's smoke round a level: said, so the log tells this client follows them)
	if p_Kind == "mortar" and not Vol.mortarSeen then
		Vol.mortarSeen = true
		LOG(string.format("a mortar's smoke round followed (its smoke drawn as the volume where it goes off), first seen at %.1f %.1f %.1f",
			s_Spatial.transform.trans.x, s_Spatial.transform.trans.y, s_Spatial.transform.trans.z))
	end

	p_Entity:RegisterDeinitCallback(function()
		local s_Grenade = m_Grenades[s_Id]
		m_Grenades[s_Id] = nil

		if s_Grenade ~= nil and m_SmokeEffect ~= nil then
			m_Gone[#m_Gone + 1] = { transform = s_Grenade.transform, velocity = s_Grenade.velocity, kind = s_Grenade.kind,
				first = s_Grenade.first }
		end
	end)
end

-- which of ours a projectile's data is: "m18", "m320", "mortar" (only with that round drawn as the volume) or nil
function Vol.KindOf(p_Data)
	if p_Data == nil then
		return nil
	elseif p_Data.instanceGuid == PROJ_DATA_INST then
		return "m18"
	elseif Vol.m320 and p_Data.instanceGuid == Vol.M320_DATA then
		return "m320"
	elseif Vol.mortar and p_Data.instanceGuid == Vol.MORTAR_DATA then
		return "mortar"
	end

	return nil
end

if IS_CLIENT and SMOKE_ENABLED and SMOKE_BY_LUA then
	Hooks:Install("EntityFactory:Create", 100, function(p_Hook, p_Data, p_Transform)
		local s_Kind = Vol.KindOf(p_Data)

		if s_Kind ~= nil then
			local s_Entity = p_Hook:Call()
			local s_Ok, s_Err = pcall(Track, s_Entity, s_Kind)

			if not s_Ok then
				LOG("⛔ following a smoke grenade: " .. tostring(s_Err))
			end
		end
	end)

	Hooks:Install("EntityFactory:CreateFromBlueprint", 100, function(p_Hook, p_Blueprint, p_Transform, p_Variation, p_Parent)
		if p_Blueprint ~= nil and (p_Blueprint.instanceGuid == PROJ_BP_INST or (Vol.m320 and p_Blueprint.instanceGuid == Vol.M320_BP)
				or (Vol.mortar and p_Blueprint.instanceGuid == Vol.MORTAR_BP)) then
			local s_Bus = p_Hook:Call()

			if s_Bus ~= nil then
				for _, l_Entity in ipairs(s_Bus.entities) do
					local l_Kind = Vol.KindOf(l_Entity.data)

					if l_Kind ~= nil then
						pcall(Track, l_Entity, l_Kind)
					end
				end
			end
		end
	end)

	-- a bullet that hits something on its way through the smoke drawn: a hole along that way (VOLUME.HOLES). The hook leaves the hit
	-- as it is (the game handles it as ever)
	if VOLUME.HOLES and VOLUME.ON then
		Hooks:Install("BulletEntity:Collision", 1, function(p_Hook, p_Entity, p_Hit, p_GiverInfo)
			if Vol.now == nil and #Vol.others == 0 then
				return
			end

			local s_Ok, s_Err = pcall(Vol.Bullet, p_Entity, p_Hit)

			if not s_Ok and not Vol.bulletFailed then
				Vol.bulletFailed = true
				LOG("⛔ a bullet's hole through the smoke: " .. tostring(s_Err))
			end
		end)
	end

	Events:Subscribe("UpdateManager:Update", function(p_Delta, p_Pass)
		if p_Pass ~= UpdatePass.UpdatePass_PreSim then
			return
		end

		-- the memory clean-up a little at a time (VOLUME.CLEANUP); this frame's measuring time not spent yet (VOLUME.MEASURE_MS)
		if (VOLUME.CLEANUP or 0) > 0 then
			pcall(Vol.Cleanup)
		end

		Vol.measureMs = 0.0

		-- the bullets' holes through the smoke drawn shutting (VOLUME.HOLES), and the camera near a volume of its own alone
		if VOLUME.ON then
			local s_Ok, s_Err = pcall(Vol.HoleFrame, p_Delta)

			if not s_Ok and not Vol.holeFailed then
				Vol.holeFailed = true
				LOG("⛔ the bullets' holes through the smoke: " .. tostring(s_Err))
			end
		end

		-- each grenade's last pose and its speed (what a canister that goes off in the air falls on with); the speed over the time since
		-- it last MOVED: another player's grenade can move at the network's pace, not every frame
		for _, l_Grenade in pairs(m_Grenades) do
			pcall(function()
				local l_Now = l_Grenade.entity.transform
				local l_Moved = l_Now.trans - l_Grenade.transform.trans
				l_Grenade.since = (l_Grenade.since or 0.0) + p_Delta

				if (l_Moved.x ~= 0.0 or l_Moved.y ~= 0.0 or l_Moved.z ~= 0.0) and l_Grenade.since > 0.0 then
					l_Grenade.velocity = l_Moved * (1.0 / l_Grenade.since)
					l_Grenade.since = 0.0
				end

				l_Grenade.transform = l_Now
			end)
		end

		if #m_Gone > 0 then
			local s_Gone = m_Gone
			m_Gone = {}

			for _, l_Gone in ipairs(s_Gone) do
				local s_Ok, s_Err = pcall(GoneOff, l_Gone)

				if not s_Ok then
					LOG("⛔ putting the canister and the smoke down: " .. tostring(s_Err))
				end
			end
		end

		for i = #m_Down, 1, -1 do
			local l_Down = m_Down[i]
			l_Down.age = l_Down.age + p_Delta

			if l_Down.falling then
				local s_Ok, s_Err = pcall(Falling, l_Down, p_Delta)

				if not s_Ok then
					l_Down.falling = false
					LOG("⛔ a falling canister: " .. tostring(s_Err))
				end
			end

			-- indoors: the room measured on and filled
			if l_Down.room ~= nil and not l_Down.roomFailed then
				local s_Ok, s_Err = pcall(RoomFrame, l_Down, p_Delta)

				if not s_Ok then
					l_Down.roomFailed = true
					LOG("⛔ filling a room with smoke: " .. tostring(s_Err))
				end
			end

			-- the signal's hiss loops until stopped: stopped when the smoke stops pouring (its own effect: the smoke thins out)
			if not l_Down.stopped and l_Down.age >= SMOKE_SECONDS and l_Down.hiss ~= nil then
				pcall(function() EffectManager:StopEffect(l_Down.hiss) end)
				l_Down.stopped = true
			end

			-- the canister goes with its smoke: by then the smoke has poured and thinned out, and whatever of it the game still holds
			-- is stopped with it, so no smoke outlives its canister
			if l_Down.age >= CANISTER_SECONDS and not l_Down.gone then
				l_Down.gone = true

				if l_Down.entity ~= nil then
					pcall(function() l_Down.entity:Destroy() end)
				end

				if l_Down.effect ~= nil then
					local s_Over = nil
					pcall(function() s_Over = EffectManager:IsEffectDead(l_Down.effect) end)
					pcall(function() EffectManager:StopEffect(l_Down.effect) end)

					if l_Down.logged ~= nil then
						LOG(string.format("smoke %d ended after %.0f s: the game's effect %s", l_Down.logged, l_Down.age,
							s_Over == true and "was already over" or (s_Over == false and "was STILL playing (stopped now)" or "unknown")))
					end
				end
			end

			-- a room's smoke hangs on after the canister: its last stream lets out its smoke and that lives its life, then all of it goes
			local l_End = CANISTER_SECONDS

			if l_Down.kind == "m320" then
				l_End = l_Down.seconds or VOLUME.M320_SECONDS
			elseif l_Down.room ~= nil then
				l_End = math.max(l_End, l_Down.room.start + 1.0 + ROOM_STREAMS * ROOM_STREAM_EVERY + ROOM_STREAM_SECONDS + ROOM_SMOKE_LIFE)
			end

			-- the room drawn as a volume: grown and thinned every frame, gone with its room's smoke
			if Vol.now ~= nil and Vol.now.down == l_Down then
				if l_Down.age >= l_End then
					pcall(Vol.End)
				else
					local s_Ok, s_Err = pcall(Vol.Frame, l_End)

					if not s_Ok then
						LOG("⛔ the smoke's volume: " .. tostring(s_Err))
						pcall(Vol.End)
					end
				end
			end

			-- or as a volume of its own
			local l_Other = l_Down.room ~= nil and l_Down.room.other or nil

			if l_Other ~= nil and not l_Other.gone then
				if l_Down.age >= l_End then
					l_Other.gone = true
					pcall(Vol.EndOther, l_Other)
				else
					local s_Ok, s_Err = pcall(Vol.OtherFrame, l_Other, l_End)

					if not s_Ok then
						LOG("⛔ a smoke's volume of its own: " .. tostring(s_Err))
						l_Other.gone = true
						pcall(Vol.EndOther, l_Other)
					end
				end
			end

			if l_Down.age >= l_End then
				if l_Down.room ~= nil then
					for _, l_Stream in ipairs(l_Down.room.streams) do
						if l_Stream.effect ~= nil then
							pcall(function() EffectManager:StopEffect(l_Stream.effect) end)
						end
					end
				end

				table.remove(m_Down, i)
			end
		end

		-- the smoke's boxes drawn far to near (VOLUME.ORDER), their matrices set
		if VOLUME.ON then
			local s_Ok, s_Err = pcall(function()
				local l_Camera = ClientUtils:GetCameraTransform()
				Vol.Order(l_Camera ~= nil and l_Camera.trans or nil, function(p_Entity, p_T)
					return pcall(function() SpatialEntity(p_Entity).transform = p_T end)
				end)
			end)

			if not s_Ok and not Vol.orderFailed then
				Vol.orderFailed = true
				LOG("⛔ the smoke's boxes' order: " .. tostring(s_Err))
			end
		end

		-- the fog: how deep the camera is in the smoke
		if m_Fog ~= nil then
			local s_Ok, s_Err = pcall(FogFrame, p_Delta)

			if not s_Ok then
				LOG("⛔ the smoke's fog: " .. tostring(s_Err))
				m_Fog = nil
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

	if m_Fog ~= nil then
		pcall(function() m_Fog.entity:Destroy() end)
		m_Fog = nil
	end

	pcall(Vol.End)

	for _, l_Other in ipairs(Vol.others) do
		pcall(function() l_Other.entity:Destroy() end)
	end

	Vol.others = {}
	Vol.holes, Vol.holeOrigin, Vol.holeBits, Vol.holeCount = {}, nil, 0, 0

	if Vol.env ~= nil then
		pcall(function() Vol.env.entity:Destroy() end)
		Vol.env = nil
	end

	Vol.data = nil
	m_Down = {}
	m_Grenades = {}
	m_Gone = {}
	m_Logged = 0
	m_SmokeEffect = nil
	m_SmokeFallEffect = nil
	m_SmokeRoomEffect = nil
	m_SmokeIndoorEffect = nil
	m_HissEffect = nil
	m_CanisterData = nil
end)
