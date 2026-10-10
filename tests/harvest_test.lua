-- Plain-Lua regression test: lua tests/harvest_test.lua [path/to/LootPet.lua]
-- Stubs the ALE API, loads the script, and drives the real HarvestCorpse
-- through a hook appended to the loaded source. Exits non-zero on a failure,
-- so reverting a T641 fix fails CI.
-- luacheck: globals RegisterPlayerEvent GetPlayersInWorld GetItemLink CharDBExecute CharDBQuery GetSpellInfo HP_TEST HP_REMEMBER HP_PREFERRED
local path = arg and arg[1] or "LootPet.lua"
local fails = 0
local function check(name, cond)
    if not cond then fails = fails + 1 end
    print((cond and "ok   " or "FAIL ") .. name)
end

local MAXM = 2147483647
local function mkplayer(name, key, opts)
    opts = opts or {}
    local p = { money = opts.money or 0, msgs = {} }
    function p:GetGUIDLow() return key end
    function p:GetName() return name end
    function p:IsBot() return opts.bot or false end
    function p:SendBroadcastMessage(m) self.msgs[#self.msgs + 1] = m end
    function p:ModifyMoney(c) self.money = self.money + c end
    function p:GetCoinage() return self.money end
    function p:IsAtGroupRewardDistance() return opts.inrange ~= false end
    function p:GetAccountId() return key end
    function p:RegisterEvent() end
    return p
end

local function mkcorpse(loot_type, money)
    local loot = { money = money, lt = loot_type, cleared = false }
    function loot:GetLootType() return self.lt end
    function loot:GetMoney() return self.money end
    function loot:SetMoney(m) self.money = m end
    function loot:GetItems() return {} end
    function loot:GetQuestItems() return {} end
    function loot:Clear() self.cleared = true; self.lt = 0 end
    local c = { loot = loot, allremoved = 0 }
    function c:GetLoot() return self.loot end
    function c:RemoveFlag() end
    function c:AllLootRemovedFromCorpse() self.allremoved = self.allremoved + 1 end
    return c
end

-- ALE globals the script touches at load time.
local handlers = {}
function RegisterPlayerEvent(id, fn) handlers[id] = fn end
function GetPlayersInWorld() return {} end
function GetItemLink() return "item" end
local executed, stored = {}, nil
function CharDBExecute(q) executed[#executed + 1] = q end
function CharDBQuery() return stored end
function GetSpellInfo()
    return { HasEffect = function() return true end, GetEffectMiscValueB = function() return 41 end }
end
local function row(v) return { GetUInt32 = function() return v end } end

local f = assert(io.open(path)); local src = f:read("*a"); f:close()
src = src:gsub('print%(">> LootPet2 loaded%."%)', "HP_TEST = HarvestCorpse; HP_REMEMBER = RememberPet; HP_PREFERRED = PreferredPet")
assert((loadstring or load)(src, "lootpet"))()
local harvest = assert(HP_TEST, "hook not installed")

local function run(owner, members, corpse)
    local group = members and { GetMembers = function() return members end } or nil
    function owner:IsInGroup() return group ~= nil end
    function owner:GetGroup() return group end
    local haul = { copper = 0, counts = {}, order = {}, shared = {}, sharedOrder = {} }
    local took = harvest(owner, owner:GetGUIDLow(), corpse, 1, 0, haul)
    -- the announcements are sent by the caller; replay the shares here
    for _, k in ipairs(haul.sharedOrder) do haul.shared[k].member:SendBroadcastMessage("share") end
    return took, haul
end

-- 1. coin
local A, B, C, Bot = mkplayer("A", 1), mkplayer("B", 2), mkplayer("C", 3, { inrange = false }),
                     mkplayer("Bot", 4, { bot = true })
run(A, { A, B, C, Bot }, mkcorpse(1, 101))
check("owner gets remainder share (51)", A.money == 51)
check("in-range real member gets 50", B.money == 50 and #B.msgs == 1)
check("out-of-range member gets nothing", C.money == 0 and #C.msgs == 0)
check("bot gets nothing", Bot.money == 0 and #Bot.msgs == 0)

A = mkplayer("A", 1)
run(A, nil, mkcorpse(1, 101))
check("solo owner keeps all 101", A.money == 101)

A, B = mkplayer("A", 1), mkplayer("B", 2, { money = MAXM })
run(A, { A, B }, mkcorpse(1, 100))
check("full purse: owner keeps the share", A.money == 100 and B.money == MAXM and #B.msgs == 0)

-- 2. skinning
A = mkplayer("A", 1)
local skin = mkcorpse(6, 50)
local took = run(A, nil, skin)
check("skin window open: nothing taken", not took and A.money == 0 and not skin.loot.cleared
      and skin.allremoved == 0)

local empty = mkcorpse(0, 0)
run(A, nil, empty)
check("empty skinned corpse is not re-marked", empty.allremoved == 0)

local fresh = mkcorpse(1, 10)
run(A, nil, fresh)
check("emptied corpse is marked looted", fresh.allremoved == 1)

-- 3. the chosen pet is per account and survives a restart
executed = {}
local P = mkplayer("P", 7)
HP_REMEMBER(P, 10674)
check("choice is written to the database", #executed == 1 and executed[1]:find("10674", 1, true)
      and executed[1]:find("lootpet_preferred_pet", 1, true))
executed = {}
handlers[5](5, mkplayer("Caster", 11), { GetEntry = function() return 10675 end })
check("casting a companion records the choice", #executed == 1 and executed[1]:find("10675", 1, true))
stored = row(10674)
local alt = mkplayer("Alt", 8)   -- another account: nothing cached, reads the row
check("a fresh account reads its stored pet", HP_PREFERRED(alt) == 10674)
stored = nil
check("no stored choice means the configured default", HP_PREFERRED(mkplayer("N", 9)) == nil)

if fails > 0 then os.exit(1) end
