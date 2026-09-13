# LootPet2 — any vanity pet becomes a loot pet

Whatever vanity pet you have summoned walks to nearby corpses you or your group tapped and retrieves the loot.

An [ALE](https://github.com/azerothcore/mod-ale) (Lua) script for AzerothCore.
Drop `LootPet2.lua` into `env/dist/etc/modules/lua_scripts/` and restart the world —
ALE loads it at world start, so no rebuild is needed.

Installed for you by [Yu'lon](https://github.com/DadsMmoLab/dads-mmo-lab) from
this repository.

## Configuration

Everything tunable is the `CONFIG` table at the top of the file, commented in
place. Yu'lon's **Tuning** tab reads and writes those keys directly.

## Credit

Based on [Brytenwally/Lootpet](https://github.com/Brytenwally/Lootpet) by Brytenwally, MIT licensed. This
repository keeps that licence and adds its modifications under it; the original
copyright notice is retained in `LICENSE`.
