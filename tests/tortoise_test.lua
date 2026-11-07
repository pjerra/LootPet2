-- Plain-Lua test of the tortoise-wow (Eluna) branches:
--   lua tests/tortoise_test.lua [path/to/LootPet.lua]
-- Same style as harvest_test.lua: stub the engine API, load the real script,
-- drive its functions through a hook appended to the loaded source. The script
-- is loaded afresh into its own environment for each scenario, because the
-- engine is detected once at load. Exits non-zero on a failure.
-- luacheck: globals setfenv
local path = arg and arg[1] or "LootPet.lua"
local fails = 0
local function check(name, cond)
    if not cond then fails = fails + 1 end
    print((cond and "ok   " or "FAIL ") .. name)
end

local f = assert(io.open(path)); local SRC = f:read("*a"); f:close()
local EXPORT = [[T = { TORTOISE = TORTOISE, UNIT_DYNAMIC_FLAGS = UNIT_DYNAMIC_FLAGS,
    MAX_MONEY = MAX_MONEY, Harvest = HarvestCorpse, Remember = RememberPet,
    Preferred = PreferredPet, IsCompanion = IsCompanionSpell, Sweeper = Sweeper,
    DefaultPet = CONFIG.DEFAULT_PET_SPELL,
    SetStart = function(v) CONFIG.START_GROUP_ROLLS = v end }]]
local src = assert(SRC:gsub('print%(">> LootPet2 loaded%."%)', function() return EXPORT end))

-- Load the script into a fresh environment. `setup(env)` adds the engine API.
local function load_script(setup)
    local env = setmetatable({}, { __index = _G })
    env.print = function() end
    env.handlers = {}
    function env.RegisterPlayerEvent(id, fn) env.handlers[id] = fn end
    function env.GetPlayersInWorld() return {} end
    function env.GetItemLink() return "item" end
    env.executed = {}
    function env.CharDBExecute(q) env.executed[#env.executed + 1] = q end
    setup(env)
    local chunk = assert((loadstring or load)(src, "lootpet", "t", env))
    if setfenv then setfenv(chunk, env) end
    chunk()
    return env
end

local function ale(env)
    function env.GetCoreName() return "AzerothCore" end
end

-- Stubs of what the Tortoise Eluna build (patch 0011) provides.
local function tortoise(env)
    function env.GetCoreName() return "MaNGOS" end
    function env.GetStateMapId() return 0 end
    function env.GetSpellInfo(id)
        if id == 99999 then error("unknown spell id") end
        return { HasEffect = function(_, e) return e == 97 and (id == 4055 or id == 28738) end }
    end
    function env.GetItemTemplate(id)
        return { GetFlags = function() return 0 end,
                 GetQuality = function() return id == 2589 and 1 or 2 end,
                 GetSellPrice = function() return 0 end }
    end
end

local function mkplayer(name, key, opts)
    opts = opts or {}
    local p = { money = opts.money or 0, msgs = {}, events = {}, nextid = 0, removed = {},
                bags = {} }
    function p:GetGUIDLow() if opts.refused then error("got an object on another map: refused") end return key end
    function p:GetName() return name end
    function p:IsBot() return opts.bot or false end
    function p:SendBroadcastMessage(m) self.msgs[#self.msgs + 1] = m end
    function p:ModifyMoney(c) self.money = self.money + c end
    function p:GetCoinage() return self.money end
    function p:IsAtGroupRewardDistance() return opts.inrange ~= false end
    function p:GetAccountId() return opts.account or key end
    function p:GetAccountName() return opts.accname or ("PLAYER" .. key) end
    function p:HasQuestForItem() return false end
    function p:GetItemCount(id) return self.bags[id] or 0 end
    function p:AddItem(id, n) self.bags[id] = (self.bags[id] or 0) + n end
    function p:RemoveItem(id, n) self.bags[id] = (self.bags[id] or 0) - n end
    function p:RegisterEvent()
        self.nextid = self.nextid + 1
        self.events[self.nextid] = true
        return self.nextid
    end
    function p:RemoveEventById(id) self.removed[#self.removed + 1] = id; self.events[id] = nil end
    function p:ActiveEvents() local n = 0 for _ in pairs(self.events) do n = n + 1 end return n end
    return p
end

local function mkcorpse(money, items)
    local loot = { money = money, lt = 1, items = items or {}, unlooted = #(items or {}),
                   setlooted = 0, cleared = false }
    function loot:GetLootType() return self.lt end
    function loot:GetMoney() return self.money end
    function loot:SetMoney(m) self.money = m end
    function loot:GetItems() return self.items end
    function loot:GetQuestItems() return {} end
    function loot:GetUnlootedCount() return self.unlooted end
    function loot:SetUnlootedCount(n) self.unlooted = n end
    function loot:SetItemLooted(id)
        for _, it in ipairs(self.items) do
            if it.id == id and not it.is_looted then it.is_looted = true; self.setlooted = self.setlooted + 1; return true end
        end
        return false
    end
    function loot:Clear() self.cleared = true end
    local c = { loot = loot, flags = {}, allremoved = 0 }
    function c:GetLoot() return self.loot end
    function c:RemoveFlag(index, flag) self.flags[#self.flags + 1] = { index, flag } end
    function c:AllLootRemovedFromCorpse() self.allremoved = self.allremoved + 1 end
    return c
end

-- A group whose world-only GetMembers raises, as in a map state.
local function mkgroup(members, onmap)
    local g = { onmap_calls = 0 }
    function g:GetMembers() error("Group:GetMembers is not allowed in a map state") end
    function g:GetMembersOnMap() self.onmap_calls = self.onmap_calls + 1; return onmap or members end
    return g
end

local function run(env, owner, group, corpse)
    function owner:IsInGroup() return group ~= nil end
    function owner:GetGroup() return group end
    local haul = { copper = 0, counts = {}, order = {}, shared = {}, sharedOrder = {} }
    local took = env.T.Harvest(owner, owner:GetGUIDLow(), corpse, 1, 0, haul)
    return took, haul
end

-- 1. engine detection ---------------------------------------------------------
local E = load_script(ale)
check("AzerothCore core name is detected as ALE", E.T.TORTOISE == false)
check("ALE keeps its dynamic-flags index (0x4F)", E.T.UNIT_DYNAMIC_FLAGS == 0x4F)
check("ALE keeps its max money (2147483647)", E.T.MAX_MONEY == 2147483647)
check("ALE still hooks LOGIN and not MAP_CHANGE", E.handlers[3] and not E.handlers[28])

E = load_script(function() end)   -- no GetCoreName at all
check("no GetCoreName falls back to ALE", E.T.TORTOISE == false)

E = load_script(tortoise)
check("core name MaNGOS is detected as Tortoise", E.T.TORTOISE == true)
check("Tortoise hooks MAP_CHANGE (28)", E.handlers[28] ~= nil)
check("Tortoise LOGIN is a no-op (not hooked)", E.handlers[3] == nil)
check("Tortoise still hooks logout, loot item and spell cast",
      E.handlers[4] and E.handlers[32] and E.handlers[5])

-- 2. constants ------------------------------------------------------------------
check("Tortoise dynamic-flags index is 143", E.T.UNIT_DYNAMIC_FLAGS == 143)
check("Tortoise MAX_MONEY is 2147483646", E.T.MAX_MONEY == 2147483646)
local A = mkplayer("A", 1)
local corpse = mkcorpse(10)
run(E, A, nil, corpse)
check("RemoveFlag gets index 143 on an emptied corpse",
      #corpse.flags == 1 and corpse.flags[1][1] == 143 and corpse.flags[1][2] == 1)
local E2 = load_script(ale)
corpse = mkcorpse(10)
run(E2, mkplayer("A", 1), nil, corpse)
check("ALE RemoveFlag still gets index 0x4F", #corpse.flags == 1 and corpse.flags[1][1] == 0x4F)

-- full purse uses the Tortoise cap
local B = mkplayer("B", 2, { money = 2147483646 - 49 })
A = mkplayer("A", 1)
run(E, A, mkgroup({ A, B }), mkcorpse(100))
check("a purse that would pass 2147483646 gets no share", B.money == 2147483646 - 49 and A.money == 100)
B = mkplayer("B", 2, { money = 2147483646 - 50 })
A = mkplayer("A", 1)
run(E, A, mkgroup({ A, B }), mkcorpse(100))
check("a share that lands exactly on 2147483646 is paid", B.money == 2147483646 and A.money == 50)

-- 3. coin split goes through GetMembersOnMap ---------------------------------------
A, B = mkplayer("A", 1), mkplayer("B", 2)
local Far = mkplayer("Far", 3, { inrange = false })
local g = mkgroup({ A, B, Far })
local took = run(E, A, g, mkcorpse(101))
check("coin split works although GetMembers raises", took and A.money == 51 and B.money == 50)
check("coin split asked GetMembersOnMap", g.onmap_calls >= 1)
check("out-of-range member gets nothing", Far.money == 0)

-- 4. bots get no share on Tortoise -------------------------------------------------
A, B = mkplayer("A", 1), mkplayer("B", 2)
local Hired = mkplayer("Hired", 4, { bot = true, accname = "SOMEPLAYER" })
run(E, A, mkgroup({ A, B, Hired }), mkcorpse(100))
check("a hired bot (non-RNDBOT account) gets no share", Hired.money == 0 and #Hired.msgs == 0)
check("the human splits two ways", B.money == 50 and A.money == 50)
-- the same bot on ALE is an altbot and does share
A, B = mkplayer("A", 1), mkplayer("B", 2)
Hired = mkplayer("Hired", 4, { bot = true, accname = "SOMEPLAYER" })
function E2.CharDBQuery() return nil end
local g2 = { GetMembers = function() return { A, B, Hired } end }
run(E2, A, g2, mkcorpse(99))
check("ALE: the same altbot still shares (33)", Hired.money == 33)

-- 5. items under a roll are skipped --------------------------------------------------
local function item(id, extra)
    local it = { id = id, count = 1, is_underthreshold = true }
    for k, v in pairs(extra or {}) do it[k] = v end
    return it
end
local function quality_items()
    return {
        item(2589),                                                -- white, free: taken
        item(2592, { is_blocked = true }),                         -- roll running
        item(2593, { roll_winner_guid = {} }),                     -- won, waiting for the winner
        item(2594, { is_underthreshold = false }),                 -- at/above the threshold
    }
end
A, B = mkplayer("A", 1), mkplayer("B", 2)
local c = mkcorpse(0, quality_items())
-- make the three held-back items quality 1 so only the roll rules can stop them
function E.GetItemTemplate() return { GetFlags = function() return 0 end,
                                      GetQuality = function() return 1 end,
                                      GetSellPrice = function() return 0 end } end
run(E, A, mkgroup({ A, B }), c)
check("group: the free white item is taken", A.bags[2589] == 1)
check("group: an item under a roll is skipped", (A.bags[2592] or 0) == 0)
check("group: an already-won item is skipped", (A.bags[2593] or 0) == 0)
check("group: an item at/above the loot threshold is skipped", (A.bags[2594] or 0) == 0)
check("skipped items stay unlooted and the corpse is not cleared",
      not c.loot.items[2].is_looted and not c.loot.items[3].is_looted
      and not c.loot.items[4].is_looted and not c.loot.cleared and c.allremoved == 0)
A = mkplayer("A", 1)
c = mkcorpse(0, quality_items())
run(E, A, nil, c)
check("solo: the pet takes all four", A.bags[2589] == 1 and A.bags[2592] == 1
      and A.bags[2593] == 1 and A.bags[2594] == 1)
-- on ALE the new fields are ignored (byte-for-byte behaviour)
local E3 = load_script(ale)
function E3.GetItemTemplate() return { GetFlags = function() return 0 end,
                                       GetQuality = function() return 1 end,
                                       GetSellPrice = function() return 0 end } end
A = mkplayer("A", 1)
c = mkcorpse(0, quality_items())
run(E3, A, { GetMembers = function() return { A } end }, c)
check("ALE: roll fields are not consulted", A.bags[2592] == 1 and A.bags[2594] == 1)

-- 5b. the pet starts the group roll (Creature:StartGroupLootRoll) ---------------------
local function rollcorpse(items, result)
    local rc = mkcorpse(0, items)
    rc.rollcalls = 0
    function rc:GetName() return "Boar" end
    function rc:StartGroupLootRoll(who)
        self.rollcalls = self.rollcalls + 1
        self.rollwho = who
        if result == nil then result = true end
        return result
    end
    return rc
end
local function lootgroup(members, method)
    local lg = mkgroup(members)
    function lg:GetLootMethod() return method end
    return lg
end
-- one player in a group of the given loot method
local function runas(env, key, method, target)
    local who = mkplayer("A", key)
    return run(env, who, lootgroup({ who }, method), target)
end
local function green(extra) return item(2594, extra or { is_underthreshold = false }) end
local function rollenv(setup)
    local env = load_script(function(e)
        tortoise(e)
        if setup then setup(e) end
    end)
    env.GetItemTemplate = function() return { GetFlags = function() return 0 end,
                                              GetQuality = function() return 2 end,
                                              GetSellPrice = function() return 0 end } end
    return env
end
E = rollenv()
A, B = mkplayer("A", 1), mkplayer("B", 2)
c = rollcorpse({ green() })
run(E, A, lootgroup({ A, B }, 3), c)
check("roll: called once for an above-threshold item (group loot)", c.rollcalls == 1 and c.rollwho == A)
check("roll: the pet still takes nothing rolled", (A.bags[2594] or 0) == 0 and not c.loot.items[1].is_looted)
run(E, A, lootgroup({ A, B }, 3), c)
check("roll: the same corpse is not asked a second time", c.rollcalls == 1)
c = rollcorpse({ green() })
runas(E, 5, 4, c)
check("roll: called for need before greed too", c.rollcalls == 1)

c = rollcorpse({ green() })
run(E, mkplayer("A", 6), nil, c)
check("roll: not called solo", c.rollcalls == 0)
c = rollcorpse({ green() })
runas(E, 7, 2, c)
check("roll: not called for master loot", c.rollcalls == 0)
c = rollcorpse({ green({ is_underthreshold = false, freeforall = true }) })
runas(E, 8, 0, c)
check("roll: not called for free for all", c.rollcalls == 0)
c = rollcorpse({ green() })
runas(E, 9, 1, c)
check("roll: not called for round robin", c.rollcalls == 0)
c = rollcorpse({ green({ is_underthreshold = false, is_blocked = true }) })
runas(E, 10, 3, c)
check("roll: not called when a roll is already running", c.rollcalls == 0)
c = rollcorpse({ green({ is_underthreshold = false, roll_winner_guid = {} }) })
runas(E, 11, 3, c)
check("roll: not called when the item is already won", c.rollcalls == 0)
c = rollcorpse({ item(2589) })
runas(E, 12, 3, c)
check("roll: not called for an item under the threshold", c.rollcalls == 0)
c = rollcorpse({ green() }, false)
local took5 = runas(E, 13, 3, c)
check("roll: a refusal (false) leaves the item alone", c.rollcalls == 1 and not took5)

local Eoff = rollenv(function() end)
Eoff.T.SetStart(false)
c = rollcorpse({ green() })
runas(Eoff, 14, 3, c)
check("roll: not called when START_GROUP_ROLLS is off", c.rollcalls == 0)

local Eale = load_script(ale)
Eale.GetItemTemplate = E.GetItemTemplate
A = mkplayer("A", 15)
c = rollcorpse({ green() })
run(Eale, A, { GetMembers = function() return { A } end, GetLootMethod = function() return 3 end }, c)
check("roll: ALE never calls it", c.rollcalls == 0)

E = rollenv()
c = rollcorpse({ green() })
c.StartGroupLootRoll = nil
local rollok = pcall(runas, E, 16, 3, c)
check("roll: an engine without the method is fine", rollok)

-- 6. the sweeper starts on MAP_CHANGE, once -----------------------------------------
local P = mkplayer("P", 10)
E = load_script(tortoise)
E.handlers[28](28, P)
check("MAP_CHANGE starts a sweeper", P:ActiveEvents() == 1)
-- Leave the map: that state's events are dropped and their ids may be reused
-- by another script. Coming back must not remove the stale id.
P.events = {}
E.handlers[28](28, P)
check("leave and return: the stale sweeper id is not removed", #P.removed == 0)
check("leave and return: one sweeper runs", P:ActiveEvents() == 1)
E.handlers[4](4, P)
check("logout forgets the sweeper id", E.T.Sweeper[10] == nil)

-- 7. load loop ----------------------------------------------------------------------------
local p1, bad, p2 = mkplayer("P1", 21), mkplayer("Bad", 22, { refused = true }), mkplayer("P2", 23)
load_script(function(env)
    tortoise(env)
    function env.GetPlayersInWorld() return { p1, bad, p2 } end
end)
check("load loop survives a refused player and starts the rest",
      p1:ActiveEvents() == 1 and p2:ActiveEvents() == 1 and bad:ActiveEvents() == 0)

local w1 = mkplayer("W1", 31)
load_script(function(env)
    tortoise(env)
    function env.GetStateMapId() return -1 end
    function env.GetPlayersInWorld() return { w1 } end
end)
check("world state starts no sweeper", w1:ActiveEvents() == 0)

local a1 = mkplayer("A1", 41)
load_script(function(env)
    ale(env)
    function env.GetPlayersInWorld() return { a1 } end
end)
check("ALE load loop still starts a sweeper for everyone online", a1:ActiveEvents() == 1)

-- 8. companions -----------------------------------------------------------------------------
E = load_script(tortoise)
check("a companion is detected by effect 97", E.T.IsCompanion(4055) == true)
check("a non-companion spell is not", E.T.IsCompanion(100) == false)
check("the default pet is Speedy (28738) and is a companion", E.T.DefaultPet == 28738
    and E.T.IsCompanion(E.T.DefaultPet) == true)
local ok, res = pcall(E.T.IsCompanion, 99999)
check("an unknown spell id does not throw", ok and res == false)

-- 9. preferred pet: uncached, silent fallback ----------------------------------------------
local stored = 10674
local queries = 0
E = load_script(function(env)
    tortoise(env)
    function env.CharDBQuery()
        queries = queries + 1
        return stored and { GetUInt32 = function() return stored end } or nil
    end
end)
local pl = mkplayer("Pl", 51)
check("preferred pet is read from the database", E.T.Preferred(pl) == 10674)
stored = 10675
check("preferred pet is not cached (a change in another state shows)", E.T.Preferred(pl) == 10675)
check("each read hits the database", queries == 2)
stored = nil
check("no stored row gives nil", E.T.Preferred(pl) == nil)

E = load_script(function(env)
    tortoise(env)
    env.CharDBQuery = nil
end)
ok, res = pcall(E.T.Preferred, pl)
check("CharDBQuery missing: nil, no error", ok and res == nil)
E = load_script(function(env)
    tortoise(env)
    function env.CharDBQuery() error("unsafe method refused") end
end)
ok, res = pcall(E.T.Preferred, pl)
check("CharDBQuery raising (UseUnsafeMethods=0): nil, no error", ok and res == nil)

E = load_script(tortoise)
E.executed = {}
E.T.Remember(pl, 10674)
E.T.Remember(pl, 10674)
check("Tortoise writes the choice every time (no stale cache skip)", #E.executed == 2)

-- 10. no CharDB access (Eluna.UseUnsafeMethods = 0) must not break a cast ------
local function cast(env, who, spell)
    return pcall(env.handlers[5], 5, who, { GetEntry = function() return spell end })
end
E = load_script(function(env)
    tortoise(env)
    env.CharDBExecute = nil
end)
ok = cast(E, mkplayer("C", 61), 4055)
check("CharDBExecute missing: a companion cast does not raise", ok)
E = load_script(function(env)
    tortoise(env)
    function env.CharDBExecute() error("unsafe method refused") end
end)
ok = cast(E, mkplayer("C", 62), 4055)
check("CharDBExecute raising: a companion cast does not raise", ok)
ok = pcall(E.T.Remember, mkplayer("C", 63), 4055)
check("CharDBExecute raising: RememberPet does not raise", ok)

if fails > 0 then os.exit(1) end
