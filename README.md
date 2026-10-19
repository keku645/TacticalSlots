# TacticalSlots

A Venice Unleashed mod for Battlefield 3 that adds two loadout slots to the deploy screen, between gadget 2 and the specialization:

- **Knife**: Machete, ACB-90 or Knife.
- **Grenade**: M67, M18 smoke or M84 flashbang.

Each player's choice is remembered by the server and restored the next time they join.

And the engineer gets one more launcher in his own gadget 1 slot: the **M136 AT4**, the game's own (from the campaign and one
multiplayer map), last in the list after the launchers and crossbows. It is picked in the game's own picker like any gadget, named
"M136 AT4" with its picture there and on the slot, and kept the same way; in the customization's loadout its gadget 1 row shows it
the same way, its arrows step to it, and its info box shows it as a weapon (ammo, rate of fire, range, fire mode) in the player's
language; on the kits screen the engineer's gadget 1 shows its name and small picture.

And the recon, on both sides, gets one more rifle in his primary weapon slot: the **M82A3**, the game's own (from the campaign), last
in the list after the sniper rifles, with its own accessories -- twelve optics, a laser sight or a flashlight -- and the "no camo"
row every rifle has, chosen on the game's own accessories screen like any rifle's. It has no bipod: the game has no bipod
animations for it (deployed, the soldier's animations would break), so its bipod is left out of the list. It shows the same way as the M136 on every screen (the deploy screen's picker and
slot, the loadout, the kits screen), its info box as a semi-automatic rifle; its accessories show as the game shows the same
accessories on its multiplayer rifles, in the player's language, on the accessories screen and as the small pictures under the rifle
(the game describes them itself, all but the laser sight, which is named and described as the game describes the L96's).
Seen in third person its barrel sits in front of the rifle on every screen: the game's multiplayer pose for it leaves the barrel
floating over the stock on the customization screen, so the mod carries its third person mesh with the barrel moved into place
(fixed to the rifle: it does not recoil in third person).

## The M84 flashbang

- In the hand, first and third person: an M84, animated with the M67's own pin-pull and throw (its pin ring moves with the M67's).
- Thrown: the game's own flashbang (its mesh, its collision, its textures), with a 1.5 s fuse; it bounces and rolls. One more in
  reserve than the M67.
- When it goes off: sparks, a puff of smoke and a bang for everybody around; 5 damage within 7 m, a shockwave out to 12 m, the
  camera shaken within 3 m, the game's stun and ringing ears, suppression, and players in the area cannot be spotted for 1 s.
- The flash: the view goes bright white and blurred for whoever is within 10 m and sees the point where it went off -- the more
  squarely they face it and the nearer they are, the stronger --, held for 4 s and fading out by 10 s. Nobody is flashed through a
  wall, nor when dead or in a vehicle. A flashbang of the player's own team (his own included) gives only a short, weak flash
  (0.6 s), unless friendly fire is on.

## The M18 smoke grenade

- In the hand, first and third person: an M18 canister, animated with the M67's own pin-pull and throw.
- Thrown: the canister bounces and rolls on a capsule collision of its own.
- When it goes off: no damage, and players in the area cannot be spotted for 10 s. Grey smoke pours out of the canister, level with the ground,
  for 10 s and then thins out, with a hiss. The canister stays on the ground for 16 s, always laid on the ground's surface.
- If it goes off in the air, the canister keeps falling from there (down a cliff too); it bounces, slides to a stop as fast as it
  came in, and pours on from where it lies (with the smoke drawn as a volume, below, no trail of particles behind it on the way down).
- The M320's smoke round (the launcher's and the rifles' underslung ones) pours this same smoke: where it hits, its smoke is put down
  as the volume below -- through doors, holed by bullets, filling rooms -- but as the round's own: no canister, the round's own sound,
  drawn from the moment it hits and out at once over metres round where it hit (growing as the place round it is measured, over its
  first frames), a ball round that point sinking a little, thinning out from the start and gone after 20 s, as the game's own
  round's smoke does. Hit high on a wall or a building's front, the smoke is round where it hit and down to the floor under it (up
  to 4 m under it); higher than that, it hangs where it hit.
- The mortar's smoke round (the deployed mortar's second round) pours it the same way (`VOLUME.MORTAR`): its explosion plays the very
  effect the M320 round's does -- the same puffs and sound --, so its smoke is put down where it lands with the same size, spread and
  20 s, the round's own sound and no canister.
- Indoors (a ceiling over it) the room fills with smoke from the canister out (where the canister pours a jet there, a shorter one,
  turned away from a wall right in front of it). The room is measured with rays: a grid of points, each reached from the one before
  by a clear ray (a wall stops it, an open door lets it through, furniture is gone round or over).
- Where the smoke goes is one rule everywhere: a fixed amount of it (250 m3) flows from the canister, always into the cheapest place
  next to those it fills already -- the farther the dearer, higher up dearer and lower down cheaper -- and a wall stops it. So it
  settles to the floor and fills a room from the floor up; a closed room smaller than that amount fills whole; out of a door or a
  window it pours, and down outside, once that is cheaper than climbing; down a flight of stairs it goes first; in the open it lies
  in a low, wide heap. The same rule under a porch, in a stairwell, in a hall: nothing is decided case by case. How far a place is
  counts along the smoke's way there (through a door, the next room fills from that door); a place whose middle is in something low
  (a bed, a sofa) is filled from over it, the smoke round it down to the floor; a place standing on a floor across it (a stairwell's
  upper part over a hall's ceiling) over air the smoke has not got to is left empty, so no smoke shows through that floor.
- The smoke FILLS its place over time (`VOLUME.SIM`, on): the canister pours its smoke out -- half of it over its first 1.5 s, the rest
  over the next seconds -- into the place it lies in, and from there the smoke goes from place to place as its levels even out, never
  through a wall: it stacks up from the floor, pours down a flight of stairs or off a ledge first, goes on through a door or over a
  window's sill once it stands higher than the sill, piles up in a heap in the open (never steeper than a set slope), and a full room
  presses it on out of its doors; none of it is ever lost or made up (where a place is found to be no place after all, its smoke goes
  back to where the smoke started). An M320 round's smoke is let out at once in a ball round where it hit, hanging there and sinking;
  where there is no floor under it (a round that hit a wall high up), the smoke does not stack up on the air: it hangs, sinking to the
  lowest places and staying there for its life (a canister's smoke poured over a roof's edge falls away instead). The place is measured
  as it fills (half again more of it than the smoke fills, room to spread) and the smoke is drawn from its first places on, as they are
  measured. What the shader gets is, for each column of places, where its smoke starts and how high it stands, a third of a layer at a
  time (`VOLUME.SIM_COLUMNS`); each column's step fades in at the pace its smoke rises or sinks (up to a second and a half), the columns
  at the smoke's edge first, a few at a time, so the smoke spreads over the floor in thin layers and rises smoothly instead of a whole
  place (a layer high) standing at once. A column on the floor that the smoke is just getting to shows its first step in three parts,
  a part more each time its smoke gets a third of the way further (from a third of the way on, not only once it is all there), each
  part fading in: the smoke's edge creeps on over the floor instead of a column's width at a time. Across, the smoke is smoothed between the columns' middles; its top rolls. Where a
  column has smoke on two floors (a hall under a floor that is open to a stairwell over it), it holds the floor the camera is on:
  through that floor the other is out of sight. With `SIM_COLUMNS` off, what the shader gets is how full each place is (empty, half or
  full), a place or two changing step a frame. It is drawn within a front that grows from where it started as it spreads (soft at its
  edge), so a round's ball swells out instead of standing whole at once; a canister's front grows as fast as a smoke of its own does
  (`VOLUME.SIM_FRONT_CANISTER`, 1.4 m/s), its smoke seen pouring out as a ball growing round it. One box round the places the smoke is
  in is drawn (growing as it spreads, never past the room's walls round it): no main space is drawn full, so no flat faces nor
  pillars. A smoke that goes off among another's places (smoke there yet or not) joins that one: its smoke is poured into it
  (a canister's) or let out round where it hit (an M320 round's), drawn together, so smokes near each other never stand as boxes of
  their own. A second canister going off near the first's smoke -- near enough for one grid (12 x 12 places, 14.4 m across) to take in
  both -- pours into the first's room as a second canister (`VOLUME.MERGE`): the grid moves over to take in both, the room is measured
  on from where the second lies, and its smoke fills it the way the first's does, seen growing out of it within a front of its own: one
  smoke the shape of the rooms round both, lasting as long as a new one. The first's smoke, once settled, stays where it is: the new
  smoke spreads round it and over it (`VOLUME.HOLD`). Too far off for the grid to take in both smokes as they are drawn, the first
  gives way (`VOLUME.RECEDE`): its sides past the grid that takes in both draw in at an even pace (about 2 s at most), its smoke
  there thinning out as they pass, and the second pours in once they are in -- the first's front split from the second's, so the
  second's smoke is seen spreading out of it as a new one's is. More than a grid apart, it is a smoke of its own. Once a
  canister's place is measured, its smoke is simulated on ahead to where it ends up and that is what is drawn, its front showing it
  (`VOLUME.SIM_AHEAD`): nothing drawn creeps on a column at a time; an M320 round's ball, once measured, is drawn as it is then,
  sinking evenly until it rests on the floor. Two ways for a canister's smoke to come out (`VOLUME.SIM_PACE`): at the simulated
  smoke's own pace -- nothing for the second or two its smoke takes to be simulated on to where it ends up, then as far along its way
  as the smoke had got by then: fast as it bursts out, slower as it spreads, waiting while it fills a room before a door, easing in
  and out --, or (false) at once, at an even pace. Smoke behind a wall is shown no sooner than it gets there along its way, round
  through the door (`VOLUME.SIM_WAY`): it comes in through the door, never through the wall. Seen from outside the smoke, its
  smoothing between the grid's columns never draws it through a wall, a floor or a ceiling (`VOLUME.SIDE`): a column counts only
  where no surface on the screen stands between it and the point drawn -- no thin wavy smoke on the near side of a wall with smoke
  behind it, none on a ceiling from the floor over it. With `VOLUME.SIM` off, all of it is as below.
- It grows and clears smoothly (its numbers written as they change, every frame or so), and its open edges waver instead of running
  straight along the grid of 1.2 m cells it is measured on (never past a wall). Seen from farther than 2 m it is drawn at its best;
  from closer, or from inside it (where it fills the view and costs the most), a cheaper way that looks the same but for a slightly
  finer grain deep in it.
- A bullet through the smoke leaves a hole along its way, its edge ragged, that shuts over 2 s (a burst along the same way keeps it
  open). The hole follows the bullet back from where it hit something; one that hits nothing leaves none. A soldier moving through
  the room's smoke leaves a wake in it (`VOLUME.WAKE`): a way through it from about a metre behind them to where they are, knees to
  head, opening towards them and closing up behind them; it shuts once they stop or leave the smoke. One at a time -- the nearest the
  camera, another player before the camera's own --, the bullets' holes one at a time with it (two without it).
- That smoke is a VOLUME, drawn with a shader of the mod's own. The room is measured floor to ceiling; each measured point becomes a
  box cut to the walls round it, and one box round them all (its sides on the walls round the room) is drawn: each view through it is
  ray marched once, from where it enters that box, through the smoke's density: grown from the canister along its way there
  (round through a door, never through a wall; filling the room's height as it spreads, so in a corridor its front fills the
  corridor; the room's main space full up to its walls, floor and ceiling), billowing, eaten into wisps at its open edges, lit by
  the light of the place from its brightest side and darker where thick smoke stands between it and that light; stopping where it
  meets anything solid. No smoke shows past a wall, not even round an opening in it; seen from outside, it fades in where the view
  enters it. A canister lying on a table, a counter or a sofa fills the room from its floor, under the table too; one on a stairs'
  landing or a ramp, from the floor the stairs or the ramp go down to, the smoke pouring down them. Out through a window or a door
  to the open sky, the room's smoke pours out as it flows, drawn with the room's own smoke, its top soft (never into a room over it,
  never over the room's ceiling height: the grid holds three layers, so smoke out of an upper floor's window stays at that floor's
  height and does not fall to the street). The volume alone draws the
  room's smoke (the canister hisses, its jet held back). A smoke going off while another one's room is drawn so is a volume of its
  own: it grows from its canister in the main space of its room (a box of the room's points round it, its sides on the walls),
  thinning out towards a side where the room goes on, without flowing out through a door; one going off inside the other's smoke
  joins it instead, the smoke there lasting on as long as a new one. However many smokes are drawn at once (one behind another down
  a corridor, a dozen players' at a time), they are drawn far to near, each over the ones behind it: the game draws the boxes of
  one composite mesh together, in an order of its own, so each smoke's box is a mesh of its own (twelve alike in the bundle), drawn
  on its own, near to far by where the game takes it to be -- and each box's matrix carries, beside its numbers, one the game alone
  reads that sets where that is. With the volume's bundle turned off, a room fills with particle streams and the canister's jet.
- In the open the smoke is a volume as well: a cloud measured round the canister the same way, a heap up to 5 m high over it,
  thinning out upwards, cut at the walls round it and getting into a building only through its door. A canister under a roof (a
  porch, an eave, a canopy) fills under it and flows out from under it into the open as its smoke flows.
- Standing in the smoke, the whole view fogs over and greys out (a visual environment weighed by how deep you are in the smoke drawn;
  a wall between you and the smoke keeps it off, and so does a place the smoke never gets to).

## Installation

1. Copy the `TacticalSlots` folder into your server's `Admin/Mods/` folder.
2. Add `TacticalSlots` to `Admin/ModList.txt`.
3. Restart the server. Clients download the mod from the server as usual.

It works on every multiplayer map, base game and expansions. The machete's, the smoke's, the flashbang's, the M136's and the M82A3's game pieces are
references to each player's own game data; only the M18's and the M84's hand meshes, the canister's collision, the smoke volume's box and shader
and the M82A3's third person mesh (its barrel moved into place) ship inside the mod.

## Settings

- `ext/Shared/__init__.lua`: `DEFAULT_KNIFE`, the knife sent when a player has not chosen one; `PRINTS`, the mod's diagnostic
  lines in the console (off); `VOLUME_ENABLED`, whether the smoke's volume bundle loads;
  `FLASH_ENABLED`, whether the flashbang's bundle loads; `M136_ENABLED`, whether the M136's bundle loads; `M82A3_ENABLED`, whether
  the M82A3's bundle loads.
- `ext/Shared/M136.lua`: `M136_ENABLED` (false: the engineer's gadget 1 list as the game ships it).
- `ext/Shared/M82A3.lua`: `M82A3_ENABLED` (false: the recon's primary weapon list as the game ships it).
- `ext/Shared/Flashbang.lua`, at the top: `FLASH_ENABLED`; the grenade (`FUSE_SECONDS`, `MIN_BOUNCE_SPEED`,
  `COLLISION_SPEED_MULTIPLIER`, `GRAVITY`, `SPARE_GRENADES`, `RELOAD_SECONDS`, `AMMO_BAG_DELAY`); the detonation (`BLAST_*`,
  `INNER_BLAST_RADIUS`, `SHOCKWAVE_*`, `CAMERA_SHOCKWAVE_RADIUS`, `STUN`, `HEARING_LOSS`, `SUPPRESSION`, `UNSPOTTABLE_SECONDS`), what it
  shows and sounds like (`PARTICLES`; `BANG`: `campaign`, `grenade` or `none`; `BANG_FALLOFF`); the flash (`WHITEOUT`: `own` or
  `effect`; `FLASH_SECONDS`, `FLASH_HOLD`, `FRIEND_SECONDS`, `REACH`, `STRENGTH_POWER`, `WHITE_BRIGHTNESS`, `WHITE_CONTRAST`,
  `WHITE_SATURATION`, `WHITE_HUE` -- the campaign flashbang's own look --, `BLUR`, `BLUR_SPREAD`, `OCCLUSION`, `IGNORE_DEAD`, `VEHICLES_SHIELD`, `TEAMS`, `THROWER_REACH`; with `effect`,
  `LOOK` and `FADE_SECONDS`).
- `ext/Shared/SmokeGrenade.lua`, at the top:
  - `SMOKE_ENABLED`, `DEFAULT_GRENADE`;
  - the fuse and bounce (`FUSE_SECONDS`, `MIN_BOUNCE_SPEED`, `COLLISION_SPEED_MULTIPLIER`) and `UNSPOTTABLE_SECONDS`;
  - the smoke's look (`SMOKE_COLOR_START`, `SMOKE_COLOR_END`, `PLUME_SIZE_SCALE`, `PUFF_*`, `JET_*`, `PLUME_RISE`);
  - its durations (`SMOKE_SECONDS`, `PUFF_SECONDS`, `CANISTER_SECONDS`) and sound (`SMOKE_SOUND`: `hiss`, `pop` or `none`);
  - how the canister rests on the ground (`CANISTER_CLEARANCE`, `CANISTER_MAX_SLOPE`, `CANISTER_STEP`) and whether it falls on
    when it goes off in the air (`CANISTER_FALLS`), how it bounces (`FALL_BOUNCE`, `FALL_BOUNCE_MAX`, `FALL_BOUNCE_GRIP`) and slides
    (`SLIDE_FRICTION`, `SLIDE_HOLD`, `SLIDE_STOP`);
  - indoors (`ROOM_SMOKE`, `ROOM_CEILING`, `ROOM_MIN_HEIGHT`, `ROOM_CELL`, `ROOM_REACH`, `ROOM_MAX_POINTS`, `JET_INDOORS`, `JET_ROOM`,
    `ROOM_STREAM*`, `ROOM_SMOKE_*`, its look included), the volume (`VOLUME`: on/off, growth, density, albedo, billows' size and how
    deep they eat in, open edges, shadow, clearing, how far it spreads, how many points and rays a frame its room is measured with, and
    whether its numbers are written every frame or only as they change, one box round them all drawing every view or one of the
    points' boxes drawing each, or each box its own stretch, whether a wall with an opening in it -- beside a door, round a hatch --
    cuts the boxes, whether the camera must see a box's point to be in its smoke, whether a canister lying on a table fills the
    room from its floor, whether the canister's own jet pours as well while the volume draws the room, whether the smoke stops at a
    door to the open sky, whether a second smoke at the same time is a volume of its own, how much the growing smoke's height
    counts against its spread -- a ball, or filling a corridor's height as it goes --, whether the room's main space is drawn full
    up to its walls, floor and ceiling, whether a wall or a floor right across a box cuts it; in the open, whether the cloud is drawn
    as a volume, how much of the place round a canister under a roof must be open to the sky for it to count as in the open, how
    high the cloud stands, over how much of its height its open top thins out, whether it is heaped or as high all over; how many of
    a room's openings to the open its smoke pours out of; whether a smoke going off inside another one's joins it; whether the smoke
    flows -- the one rule above, `FLOW`: off, the room measured out to a fixed reach -- how much of it there is
    (`AMOUNT`), the shape it would rather spread in (`SHAPE_X`, `SHAPE_Y`, `SHAPE_Z`, `ROUNDNESS`) and how much it settles
    (`GRAVITY`: under 0 it rises), whether how far a place is counts along the smoke's way (`FLOW_BY_WAY`), whether a place whose
    middle is in something low is filled from over it (`FLOW_OVER`), whether a place on a floor over air the smoke has not got to is
    left empty (`FLOW_FLOORS`), whether it grows smoothly (`SMOOTH`), how near the camera must be for the cheaper drawing
    (`NEAR_QUALITY`, 0: never), whether several smokes at once are drawn far to near (`ORDER`), whether the M320's smoke round is
    drawn as this smoke too and how its smoke spreads, how much of it there is and how long it lasts (`M320`, `M320_GROW`,
    `M320_AMOUNT`, `M320_SECONDS`), whether it is drawn from the moment it hits (`M320_EARLY`) and how many rays a frame measure the
    place round it (`M320_RAYS`), how far under where it hits a floor is still its smoke's floor and where it hangs higher than that
    (`M320_BELOW`, `M320_HANG`, `M320_OVER`), the shape it spreads in and how much it settles (`M320_SHAPE_X`, `M320_SHAPE_Y`,
    `M320_SHAPE_Z`, `M320_GRAVITY`), whether the mortar's smoke round is drawn so too and its own spread, amount and time
    (`MORTAR`, `MORTAR_GROW`, `MORTAR_AMOUNT`, `MORTAR_SECONDS`; the rest as the M320's), how grey the view goes in a round's smoke
    as it thins out (`ROUND_FOG`: as much as that many metres of the smoke drawn hide), and the bullets' holes (`HOLES`,
    `HOLE_SECONDS`; how wide they
    are, `HOLE_RADIUS`, and how far its edges waver, `WARP`, are in the shader) and a soldier's wake through the smoke (`WAKE`; how
    wide and tall, `WAKE_RADIUS`, `WAKE_TALL`, in the shader); whether the smoke fills its place over time (`SIM`),
    how much more of the place is measured than it fills (`SIM_ROOM`), how fast its levels even out (`SIM_SPREAD`), the steepest its
    top stands (`SIM_SLOPE`), how much of a canister's smoke pours out at first and over how long (`SIM_POUR`, `SIM_BURST`), how fast an
    M320 round's ball sinks (`SIM_SINK`), how fast the front it is drawn within grows (`SIM_FRONT`; a canister's,
    `SIM_FRONT_CANISTER`), whether it is simulated on ahead to where it ends up (`SIM_AHEAD`), whether its fronts move at the
    simulated smoke's own pace and how fast at most (`SIM_PACE`, `SIM_PACE_MOST`), whether smoke behind a wall waits until it gets
    there round through the door (`SIM_WAY`), whether its smoothing is kept from drawing it through a wall, a floor or a ceiling
    (`SIDE`), whether the grid holds columns
    (thin, fading steps) or places (`SIM_COLUMNS`); whether a canister near another's smoke pours into it (`MERGE`), how fast that
    smoke gives way to one too far for its grid (`RECEDE`, m/s; 0: a smoke of its own there) and whether the smoke settled there
    stays where it is (`HOLD`); the most of a frame measuring
    the smokes' places takes (`MEASURE_MS`) and how often a small clean-up of the memory the mod no longer uses runs (`CLEANUP`)) and
    the fog in the smoke (`ROOM_FOG*`, `ROOM_WHITEOUT_*`: only where the smoke drawn is).

## Files

| Path | What it does |
|---|---|
| `ext/Shared/__init__.lua` | Loads the mod's bundles, adds the machete to every kit's knife list and applies the knife choice. |
| `ext/Shared/SmokeGrenade.lua` | Builds the M18 smoke grenade, adds it and the flashbang to every kit's grenade list and applies the grenade choice; puts the canister and the smoke down where a smoke grenade goes off. |
| `ext/Shared/Flashbang.lua` | Builds the M84 flashbang; the server tells every client where one went off and whose it was, and each client plays its flash. |
| `ext/Shared/M136.lua` | Registers the game's M136 and puts it at the end of every engineer kit's gadget 1 list. |
| `ext/Shared/M82A3.lua` | Registers the game's M82A3 and its accessories and puts it at the end of every recon kit's primary weapon list. |
| `ext/Server/__init__.lua` | Keeps each player's knife and grenade in `mod.db`. |
| `ext/Client/KnifeTab.lua` | Hears the knife and the grenade picked in the deploy screen's slots. |
| `ext/Client/TacticalSlotsClient.lua`, `ext/Shared/TacticalSlotsShared.lua` | Generated together with the deploy screen's UI bundle: do not edit by hand. |
| `sb/Win32/tacticalslots/` | The machete's, the smoke grenade's (and its volume's), the flashbang's, the M136's and the M82A3's superbundles. |
| `sb/Win32/tacticalslotsui/` | The deploy screen's UI, the kits screen's, the kit rows' (the M136's, the M82A3's and its accessories' names, pictures and info) and the pictures. |

`mod.db` is created by the server on first run and is not part of the repository.

## License

MIT: see [LICENSE](LICENSE).
