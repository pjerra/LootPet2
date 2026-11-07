# LootPet2 — any vanity pet becomes a loot pet

Whatever vanity pet you have summoned walks to nearby corpses you or your group tapped and retrieves the loot.

An [ALE](https://github.com/azerothcore/mod-ale) (Lua) script for AzerothCore, and
the same file also runs on [tortoise-wow](#tortoise-wow-eluna)'s Eluna. It detects
which engine it is on when it loads.
Drop `LootPet.lua` into `env/dist/etc/modules/lua_scripts/` and restart the world —
ALE loads it at world start, so no rebuild is needed.

Installed for you by [Yu'lon](https://github.com/DadsMmoLab/dads-mmo-lab) from
this repository.

## Why the file is `LootPet.lua`

The repository is LootPet2; the script is `LootPet.lua`. That is deliberate. ALE loads
**every** `.lua` in `lua_scripts/`, so a file called `LootPet2.lua` sitting beside an existing
`LootPet.lua` would run both scripts and loot every corpse twice. Keeping the original name
makes an upgrade an overwrite.

## Configuration

Everything tunable is the `CONFIG` table at the top of the file, commented in
place. Yu'lon's **Tuning** tab reads and writes those keys directly.

### Behaviour worth knowing

- **Coin is shared in a party.** Money the pet picks up is split the way the game splits group
  money: equal shares among the players in the party in range of that corpse (random bots get none; the player's own altbots share), the
  remainder - and any share a full purse cannot hold - to the owner, and each member is told their share. Solo is unchanged. `SHARE_COIN_IN_PARTY = false`
  gives the owner everything, as before.
- **The pet you choose follows your account.** The companion you last summoned is remembered per
  account (table `lootpet_preferred_pet` in the characters database, created on load), so alts and
  a server restart bring back the same pet instead of falling back to `DEFAULT_PET_SPELL`. The
  script's own automatic summons are not remembered as a choice. `DEFAULT_PET_SPELL` is only
  used until an account has chosen one. Automatic summoning stays off until `AUTO_SUMMON_DELAY`
  is above 0; the summon is a triggered cast, so the character does not need to know the spell.
- **No second skin.** The pet leaves a corpse alone while it is being skinned, and never marks an
  emptied, already-skinned corpse skinnable again.

## tortoise-wow (Eluna)

The same `LootPet.lua` runs on tortoise-wow (a VMaNGOS 1.12 core). On AzerothCore nothing
below applies and the script behaves exactly as before.

Requirements:

- An Eluna build with the tortoise-wow patches 0001-0011 (patch 0011 adds the `Loot`,
  `ItemTemplate` and `Roll` types and the methods this script calls).
- `Eluna.Enabled = 1`.
- `Eluna.UseUnsafeMethods = 1`. Only the pet the player last chose needs it: it is read
  with `CharDBQuery`, which is an unsafe method. Without it the script still works and
  falls back to `DEFAULT_PET_SPELL`, silently.
- `LootPet.lua` in the folder `Eluna.ScriptPath` points at (default `./lua_scripts`, next
  to the server binary). `.reload eluna` reloads it.

What differs from AzerothCore:

- The sweeper starts on map entry (`PLAYER_EVENT_ON_MAP_CHANGE`), not at login: every
  map and instance has its own Lua state, and a state's timers end when the player
  leaves its map.
- In a group the pet never takes an item that is under a roll, already won and waiting
  for its winner, or at or above the group's loot threshold, whatever `MAX_QUALITY_IN_PARTY`
  says. Those stay on the corpse for the roll.
- With `START_GROUP_ROLLS` (default true) and group loot or need before greed, the pet
  starts the group's roll on an item at or above the threshold when it reaches the corpse
  (`Creature:StartGroupLootRoll`, patch 0011), so the group gets the roll popups without
  anyone walking over. The core gives the item to the winner; the pet never takes it.
- Coin is shared with real players only: every bot, TortoiseBots bots included, gets no
  share. Only party members on the same map take part, because the group list a map
  state can read is limited to that map.
- Bots (TortoiseBots bots) never get a looting pet: no sweeper is started for them.
- A companion is a spell with the `SUMMON_CRITTER` effect (97); 1.12 has no summon
  properties.
- The chosen pet is read from the database each time it is needed instead of being
  cached, so a choice made on another map is seen.

## Tests

`lua tests/harvest_test.lua` and `lua tests/tortoise_test.lua` stub the engine API and
drive the real script (CI runs them on Lua 5.1, 5.2 and 5.4, plus `luacheck`).

## Credit

Based on [Brytenwally/Lootpet](https://github.com/Brytenwally/Lootpet) by Brytenwally, MIT licensed. This
repository keeps that licence and adds its modifications under it; the original
copyright notice is retained in `LICENSE`.
