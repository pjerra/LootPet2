# LootPet2 — any vanity pet becomes a loot pet

Whatever vanity pet you have summoned walks to nearby corpses you or your group tapped and retrieves the loot.

An [ALE](https://github.com/azerothcore/mod-ale) (Lua) script for AzerothCore.
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

## Credit

Based on [Brytenwally/Lootpet](https://github.com/Brytenwally/Lootpet) by Brytenwally, MIT licensed. This
repository keeps that licence and adds its modifications under it; the original
copyright notice is retained in `LICENSE`.
