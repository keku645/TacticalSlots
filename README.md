# TacticalSlots

A Venice Unleashed mod for Battlefield 3 that adds two loadout slots to the deploy screen, between gadget 2 and the specialization:

- **Knife**: Machete, ACB-90 or Knife.
- **Grenade**: M67 or M18 smoke.

Each player's choice is remembered by the server and restored the next time they join.

## The M18 smoke grenade

- In the hand, first and third person: an M18 canister, animated with the M67's own pin-pull and throw.
- Thrown: the canister bounces and rolls on a capsule collision of its own.
- When it goes off: no damage, and players in the area cannot be spotted for 10 s. Grey smoke pours out of the canister, level with the ground,
  for 10 s and then thins out, with a hiss. The canister stays on the ground for 16 s, always laid on the ground's surface.

## Installation

1. Copy the `TacticalSlots` folder into your server's `Admin/Mods/` folder.
2. Add `TacticalSlots` to `Admin/ModList.txt`.
3. Restart the server. Clients download the mod from the server as usual.

It works on every multiplayer map, base game and expansions. The machete and the smoke's game pieces are references to each player's own
game data; only the M18's hand meshes and the canister's collision ship inside the mod.

## Settings

- `ext/Shared/__init__.lua`: `DEFAULT_KNIFE`, the knife sent when a player has not chosen one; `PRINTS`, the mod's lines in the
  console (off; the server keeps them in `mod.db` either way).
- `ext/Shared/SmokeGrenade.lua`, at the top:
  - `SMOKE_ENABLED`, `DEFAULT_GRENADE`;
  - the fuse and bounce (`FUSE_SECONDS`, `MIN_BOUNCE_SPEED`, `COLLISION_SPEED_MULTIPLIER`) and `UNSPOTTABLE_SECONDS`;
  - the smoke's look (`SMOKE_COLOR_START`, `SMOKE_COLOR_END`, `PLUME_SIZE_SCALE`, `PUFF_*`, `JET_*`, `PLUME_RISE`);
  - its durations (`SMOKE_SECONDS`, `PUFF_SECONDS`, `CANISTER_SECONDS`) and sound (`SMOKE_SOUND`: `hiss`, `pop` or `none`);
  - how the canister rests on the ground (`CANISTER_CLEARANCE`, `CANISTER_MAX_SLOPE`, `CANISTER_STEP`).

## Files

| Path | What it does |
|---|---|
| `ext/Shared/__init__.lua` | Loads the mod's bundles, adds the machete to every kit's knife list and applies the knife choice. |
| `ext/Shared/SmokeGrenade.lua` | Builds the M18 smoke grenade, adds it to every kit's grenade list and applies the grenade choice; puts the canister and the smoke down where a smoke grenade goes off. |
| `ext/Server/__init__.lua` | Keeps each player's knife and grenade, and a log, in `mod.db`. |
| `ext/Client/KnifeTab.lua` | Hears the deploy screen's slots (picks and layout). |
| `ext/Client/TacticalSlotsClient.lua`, `ext/Shared/TacticalSlotsShared.lua` | Generated together with the deploy screen's UI bundle: do not edit by hand. |
| `sb/Win32/tacticalslots/` | The machete's and the smoke grenade's superbundles. |
| `sb/Win32/tacticalslotsui/` | The deploy screen's UI and its pictures. |

`mod.db` is created by the server on first run and is not part of the repository.

## License

MIT: see [LICENSE](LICENSE).
