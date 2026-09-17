-- ============================================================================
-- LOOTPET2: ANY VANITY PET
-- ============================================================================
-- Author:   hypeer & Claude
-- Based on: LootPet by Brytenwally (Gemini AI & User Collaboration)
--           https://github.com/Brytenwally/Lootpet
-- Description: Whatever vanity pet you have summoned walks to nearby corpses
--              you (or your group) tapped and retrieves the loot.
--
-- Detection is a corpse sweep, not a kill hook. The original
-- PLAYER_EVENT_ON_GIVE_XP hook only fired when the kill awarded XP, so grey
-- mobs never triggered it -- and neither did anything killed at max level, or
-- anything a party member or bot killed while you were capped. Sweeping for
-- corpses you are entitled to loot covers all of those.
-- ============================================================================

local CONFIG = {
    -- Max distance between player and corpse for the pet to be sent.
    MAX_LOOT_DISTANCE   = 60,

    -- Distance pet must reach to "loot" the body.
    ARRIVE_DISTANCE     = 2.5,

    -- Once the pet reaches a corpse it also empties every other corpse of
    -- yours within this many yards of where it is standing, so an AoE pull
    -- is one trip rather than one trip per body. 0 turns this off.
    AOE_LOOT_RADIUS     = 10,

    -- Party Settings
    LOOT_IN_PARTY       = true,  -- If true, pet loots during group play.

    -- RARITY FILTER (Party Only)
    -- Ignored when you are solo -- alone the pet always takes everything.
    -- In a group the pet takes items of this quality or lower and leaves the
    -- rest on the corpse for the party to roll on. Coin is always taken, and
    -- quest loot has its own rules further down.
    --
    --   0 = Poor (Grey)        4 = Epic (Purple)
    --   1 = Common (White)     5 = Legendary (Orange)
    --   2 = Uncommon (Green)   6 = Artifact
    --   3 = Rare (Blue)        7 = Heirloom
    --
    -- Anything at or above the group's loot threshold (uncommon, by default)
    -- is the core's to roll on, and the roll starts when someone first opens
    -- the corpse. A pet that takes such an item either pre-empts the roll or,
    -- if one is already running, leaves the winner a second copy: the roll
    -- does not check what the pet marked. 1 leaves everything from green up
    -- alone. Raise it to 7 only on a free-for-all server, or when the party
    -- is bots.
    --
    -- Lowering it has a second effect worth knowing: anything left behind also
    -- blocks quest loot on that corpse, because handing quest loot over means
    -- clearing the whole corpse and that would take the group's roll with it.
    MAX_QUALITY_IN_PARTY = 1,

    -- How often (ms) each player is checked for reachable corpses.
    SCAN_INTERVAL       = 1000,

    -- How often (ms) we check whether the pet has reached the corpse.
    ARRIVE_POLL         = 200,

    -- Give up on a corpse if the pet has not arrived within this many ms.
    ARRIVE_TIMEOUT      = 10000,

    -- After giving up on a corpse, ignore it for this many seconds.
    RETRY_SECONDS       = 30,

    -- Say something when the rarity filter makes the pet leave loot behind,
    -- so you know a corpse is still worth walking to. Nothing is said when
    -- MAX_QUALITY_IN_PARTY is high enough that the pet took the lot, and
    -- nothing is said solo, where the filter does not apply.
    ANNOUNCE_LEFT_BEHIND = true,

    -- Where that announcement goes.
    --   "player" : only you, as a system line
    --   "party"  : your party, in party chat, from you (in a raid: your
    --              own subgroup, which is what party chat means there)
    --   "raid"   : the whole raid, in raid chat; behaves as "party" when
    --              the group is not a raid
    -- Solo it always comes to you alone, since there is nobody else to tell.
    ANNOUNCE_TO         = "player",

    -- Report what the pet brought back, as one line per trip rather than one
    -- per corpse. Note that the client already prints its own "You receive
    -- item" line for each item -- Player:AddItem sends it -- so at "player"
    -- this doubles up on items. What it adds there is the coin, which is
    -- otherwise silent. Set it to "party" and it tells the group instead,
    -- which nothing else does.
    ANNOUNCE_LOOT       = true,
    ANNOUNCE_LOOT_TO    = "player",  -- "player", "party" or "raid"

    -- At most this many item names in one line, then "+N more", so a big AoE
    -- pull cannot produce an unreadable wall of links.
    ANNOUNCE_LOOT_MAX   = 8,

    -- Quest loot can only be handed over by clearing the whole corpse, which
    -- also drops any copy a group member has not taken yet. With this off, the
    -- pet only takes quest loot nobody else in the group has a quest for.
    -- With it on, it will also take yours once the corpse has sat untouched
    -- for PARTY_QUEST_GRACE seconds. Bots loot their copy within a second of
    -- the kill; a real player who is still fighting needs long enough to walk
    -- over, so this is measured for people, not bots.
    QUEST_LOOT_IN_PARTY = true,
    PARTY_QUEST_GRACE   = 30,

    -- Keep a looting pet out on every real player. When none has been out
    -- for AUTO_SUMMON_DELAY seconds, the companion the player last summoned
    -- comes back -- or DEFAULT_PET_SPELL until they have summoned one.
    -- Summoning any other companion replaces it, as it always has; this only
    -- fills the gap when there is none. Bots are left alone.
    --
    -- Off by default: dismissing a companion is the same spell cast as
    -- summoning it, so with this on the pet came back a few seconds after
    -- every dismissal and there was no way to put it away.
    AUTO_SUMMON_DELAY   = 0,
    DEFAULT_PET_SPELL   = 4055,  -- Mechanical Squirrel

    -- Where the pet sits when it is done. Unit:MoveFollow defaults to a
    -- distance and angle of 0, which parks the pet inside the player.
    -- The angle is added to the player's orientation and grows counter-
    -- clockwise, so math.pi / 2 is the player's left. Use math.pi for the
    -- core's own pet position (directly behind), or 3 * math.pi / 4 for left
    -- and slightly back.
    FOLLOW_DISTANCE     = 1.0,
    FOLLOW_ANGLE        = math.pi / 2,
}

-- UNIT_DYNAMIC_FLAGS is OBJECT_END + 0x0049, and OBJECT_END is 0x0006.
-- AllLootRemovedFromCorpse does not touch this field -- it only sets the
-- skinnable flag and shortens corpse decay -- so the sparkle has to come off
-- by hand or an emptied corpse keeps glittering.
local UNIT_DYNAMIC_FLAGS   = 0x0006 + 0x0049
local UNIT_DYNFLAG_LOOTABLE = 0x0001

-- ItemTemplate.Flags, from ItemTemplate.h. An item with this flag drops one
-- copy per group member -- quest starters, most of them -- and the core keeps
-- a per-player list of which copies are taken that Lua cannot see.
local ITEM_FLAG_MULTI_DROP = 0x00000800

-- ChatMsg and Language, from SharedDefines.h.
local CHAT_MSG_PARTY = 0x02
local CHAT_MSG_RAID  = 0x03
local LANG_UNIVERSAL = 0

-- SPELL_EFFECT_SUMMON from SharedDefines.h. A companion summon carries the
-- SummonProperties id in EffectMiscValueB, and 41 is the companion entry
-- (Type = SUMMON_TYPE_MINIPET) every 3.3.5 companion spell points at.
local SPELL_EFFECT_SUMMON = 28
local SUMMON_PROPERTIES_COMPANION = 41

local ARRIVE_LIMIT = math.max(1, math.floor(CONFIG.ARRIVE_TIMEOUT / CONFIG.ARRIVE_POLL))
-- A fetch gets two arrive timeouts (pathed, then straight) and some slack.
-- One still marked in flight after that has lost its harvest event -- the only
-- way that happens is a Lua error inside it -- and would block the player's
-- pet for good unless somebody lets go of it.
local STALE_TICKS  = math.max(1, math.floor((2 * CONFIG.ARRIVE_TIMEOUT + 5000) / CONFIG.SCAN_INTERVAL))
local RETRY_TICKS  = math.max(1, math.floor((CONFIG.RETRY_SECONDS * 1000) / CONFIG.SCAN_INTERVAL))
local GRACE_TICKS  = math.max(1, math.floor((CONFIG.PARTY_QUEST_GRACE * 1000) / CONFIG.SCAN_INTERVAL))
local SUMMON_TICKS = math.max(1, math.floor((CONFIG.AUTO_SUMMON_DELAY * 1000) / CONFIG.SCAN_INTERVAL))
-- Corpses despawn well inside five minutes, so a record that old is dead.
local HANDLOOT_TICKS = math.max(1, math.floor(300000 / CONFIG.SCAN_INTERVAL))

-- Per-player state, keyed by low GUID (a number). ObjectGuids come across as
-- userdata and cannot be used as table keys by value.
local Fetching = {}  -- [pKey] = { guid = corpse guid, key = corpse low guid, polls = n }
local Skipped  = {}  -- [pKey] = { [corpse low guid] = tick at which it is retried }
local Seen     = {}  -- [pKey] = { [corpse low guid] = tick it first came into range }
local HandLooted = {} -- [pKey] = { [corpse low guid] = tick the record expires }
local Announced = {}  -- [pKey] = { [corpse low guid] = tick the record expires }
local Tick     = {}  -- [pKey] = sweep counter
local Petless  = {}  -- [pKey] = consecutive sweeps with no vanity pet out
local Preferred = {} -- [pKey] = spell of the companion the player last summoned;
                     -- deliberately not cleared on login, so it survives a relog

local HarvestLoot

-- ============================================================================
-- PET LOOKUP
-- ============================================================================
-- Vanity pets (companions/critters) live on the player critter GUID, not the
-- combat pet slot. Looking only there means every vanity pet qualifies, while
-- hunter pets and warlock minions are left alone.

local function GetVanityPet(player, map)
    map = map or player:GetMap()
    if not map then return nil end

    local critterGUID = player:GetCritterGUID()
    if not critterGUID then return nil end

    local obj = map:GetWorldObject(critterGUID)
    if not obj then return nil end

    return obj:ToUnit()
end

-- Send the pet back to heel. Always go through this rather than calling
-- MoveFollow directly, so the follow position stays in one place.
local function SendPetToHeel(pet, player)
    if pet then
        pet:MoveFollow(player, CONFIG.FOLLOW_DISTANCE, CONFIG.FOLLOW_ANGLE)
    end
end

-- True if casting this spell puts a companion out.
local function IsCompanionSpell(spellId)
    local info = GetSpellInfo(spellId)
    if not info or not info:HasEffect(SPELL_EFFECT_SUMMON) then return false end

    for index = 0, 2 do
        if info:GetEffectMiscValueB(index) == SUMMON_PROPERTIES_COMPANION then
            return true
        end
    end

    return false
end

-- Bring a companion back for a player who has none out. Counts sweeps rather
-- than acting at once, so the brief gap while one companion is swapped for
-- another does not get a third one summoned into the middle of it.
local function MaybeSummonPet(player, pKey)
    if CONFIG.AUTO_SUMMON_DELAY <= 0 then return end
    if player:IsBot() then return end

    -- A dead player cannot hold a companion. Start counting again on respawn.
    if not player:IsAlive() then
        Petless[pKey] = 0
        return
    end

    local gone = (Petless[pKey] or 0) + 1
    Petless[pKey] = gone
    if gone < SUMMON_TICKS then return end

    Petless[pKey] = 0
    player:CastSpell(player, Preferred[pKey] or CONFIG.DEFAULT_PET_SPELL, true)
end

-- Deliver a line to `where` -- "player", "party" or "raid". Whenever there is
-- nobody else to tell, it goes to the owner alone.
local function Announce(player, msg, where)
    local group = (where == "party" or where == "raid") and player:GetGroup() or nil

    if not group then
        player:SendBroadcastMessage(msg)
        return
    end

    local isRaid = group:IsRaidGroup()
    local chatType = (where == "raid" and isRaid) and CHAT_MSG_RAID or CHAT_MSG_PARTY

    for _, member in ipairs(group:GetMembers() or {}) do
        -- Party chat inside a raid only reaches your own subgroup.
        if where == "raid" or not isRaid or group:SameSubGroup(player, member) then
            player:SendChatMessageToPlayer(chatType, LANG_UNIVERSAL, msg, member)
        end
    end
end

-- One trip's takings. Items are tallied by id so three separate stacks of
-- the same cloth read as one entry, and `order` keeps them in the order they
-- were picked up rather than whatever order pairs() feels like.
local function NewHaul()
    return { copper = 0, counts = {}, order = {} }
end

local function AddToHaul(haul, itemID, count)
    if not haul or not itemID or count <= 0 then return end

    if not haul.counts[itemID] then
        haul.counts[itemID] = 0
        haul.order[#haul.order + 1] = itemID
    end

    haul.counts[itemID] = haul.counts[itemID] + count
end

local function FormatMoney(copper)
    local parts = {}
    local gold   = math.floor(copper / 10000)
    local silver = math.floor((copper % 10000) / 100)
    local left   = copper % 100

    if gold > 0 then parts[#parts + 1] = gold .. "g" end
    if silver > 0 then parts[#parts + 1] = silver .. "s" end
    if left > 0 or #parts == 0 then parts[#parts + 1] = left .. "c" end

    return table.concat(parts, " ")
end

local function AnnounceHaul(player, haul)
    if not CONFIG.ANNOUNCE_LOOT or not haul then return end

    local parts = {}
    local shown = 0

    for _, itemID in ipairs(haul.order) do
        if shown >= CONFIG.ANNOUNCE_LOOT_MAX then
            parts[#parts + 1] = "+" .. (#haul.order - shown) .. " more"
            break
        end

        local count = haul.counts[itemID]
        local link = GetItemLink(itemID) or tostring(itemID)
        parts[#parts + 1] = (count > 1) and (link .. " x" .. count) or link
        shown = shown + 1
    end

    if haul.copper > 0 then
        parts[#parts + 1] = FormatMoney(haul.copper)
    end

    if #parts == 0 then return end

    Announce(player, "Your companion brought back " .. table.concat(parts, ", ") .. ".",
             CONFIG.ANNOUNCE_LOOT_TO)
end

-- ============================================================================
-- LOOT FILTERING
-- ============================================================================
-- Quest loot is handled apart from everything else, and only when solo.
--
-- A quest drop cannot be removed on its own. QuestItem.index points into
-- loot->quest_items, and every player's list in PlayerQuestItems holds those
-- indexes, so erasing one element shifts the rest out from under everyone.
-- The one safe hand-over is to take the item and drop the whole Loot in the
-- same pass: Clear() releases PlayerQuestItems along with the vector, so a
-- shifted index never exists. Dropping the whole Loot is only correct when
-- there is nobody else it could belong to, which is why this is solo only --
-- in a group the quest drop is left for the party to take by hand.

-- Item IDs that appear in loot->quest_items. Loot:RemoveItem takes an item ID,
-- not a slot: it clears the ID out of loot->items and, if the requested count
-- is not satisfied there, keeps going into quest_items. Never asking it to
-- remove an ID that also exists as quest loot means it can never reach that
-- vector, whatever the counts say.
--
-- The same index problem lives in loot->items. Loot:RemoveItem *erases* the
-- entry, and every later item moves up a slot -- but PlayerFFAItems and
-- PlayerNonQuestNonFFAConditionalItems hold slot indexes per player, exactly
-- as PlayerQuestItems does. Erase one item from a corpse two players share
-- and the other player's copy of a multi-drop item points at the wrong slot:
-- it still shows in their loot window, and the server refuses it. So a whole
-- stack is marked looted in place (Loot:SetItemLooted) and the slots never
-- move. Loot:RemoveItem is not called on a corpse at all any more.
local function QuestItemIds(loot)
    local ids = {}
    for _, questItem in ipairs(loot:GetQuestItems() or {}) do
        if questItem.id then ids[questItem.id] = true end
    end
    return ids
end

-- Hand an item over and report how many actually landed in the bags.
--
-- Do not use Player:AddItem's return value. Its no-space path is
--
--     if (itemCount == 0 || dest.empty())
--         return 1;
--
-- which tells Lua a result is on the stack without pushing one, so the caller
-- gets an argument back instead of the documented nil -- truthy, on the exact
-- path that means nothing was stored. Counting the bags is the only honest
-- answer, and it also catches a partial store into a nearly full bag.
local function GiveItem(player, itemID, count)
    local before = player:GetItemCount(itemID, false)
    player:AddItem(itemID, count)
    local stored = player:GetItemCount(itemID, false) - before

    if stored < 0 then return 0 end
    if stored > count then return count end
    return stored
end

-- Loot:SetItemLooted marks the *first* stack with a given id and count,
-- looted or not, so a second identical stack on the same corpse can never be
-- reached by it. Only the first of each (id, count) is ever taken -- the twin
-- is left for a hand loot rather than handed out twice -- and the sweep must
-- agree with the harvest on that, or the pet walks to a twin for ever.
-- Returns the set of entries that are the first of their kind.
local function FirstOfKind(items)
    local first, reachable = {}, {}
    for _, itemData in ipairs(items or {}) do
        local itemID = itemData.id
        if itemID then
            local kind = itemID .. ":" .. (itemData.count or 1)
            if not first[kind] then
                first[kind] = true
                reachable[itemData] = true
            end
        end
    end
    return reachable
end

-- Items the pet marks looted stay in the list, so "empty" is counted by the
-- flag rather than by length.
local function AnyUnlooted(items)
    for _, itemData in ipairs(items or {}) do
        if not itemData.is_looted then return true end
    end
    return false
end

local function ShouldTakeItem(itemID, inGroup)
    if not inGroup then return true end

    local itemTemplate = GetItemTemplate(itemID)
    if not itemTemplate then return false end

    -- A multi-drop item is one copy per member, and which copies are taken is
    -- kept per player where Lua cannot reach. The shared entry the pet could
    -- mark is not any one player's copy, so in a group these are left for
    -- each member to take by hand.
    local flags = itemTemplate:GetFlags() or 0
    if flags % (ITEM_FLAG_MULTI_DROP * 2) >= ITEM_FLAG_MULTI_DROP then
        return false
    end

    return itemTemplate:GetQuality() <= CONFIG.MAX_QUALITY_IN_PARTY
end

-- Links for anything on this corpse the rarity filter will not let the pet
-- take. Empty when MAX_QUALITY_IN_PARTY is high enough to take the lot, and
-- empty solo, where the filter does not apply at all.
local function LeftBehindLinks(loot, inGroup)
    local links = {}
    if not inGroup then return links end

    local questIds = QuestItemIds(loot)

    for _, itemData in ipairs(loot:GetItems() or {}) do
        local itemID = itemData.id
        if itemID and itemID > 0
           and not itemData.is_looted
           and not itemData.needs_quest
           and not questIds[itemID]
           and not ShouldTakeItem(itemID, inGroup) then
            links[#links + 1] = GetItemLink(itemID) or tostring(itemID)
        end
    end

    return links
end

-- True only if there is something on this corpse we would actually take.
-- Greens left for a group roll do not count, so the pet never walks to a
-- corpse just to take nothing from it.
local function NeedsQuestItem(player, questItem)
    local itemID = questItem.id
    return itemID and itemID > 0
       and not questItem.is_looted
       and player:HasQuestForItem(itemID)
end

-- Everyone besides the owner with a claim on the quest loot still on this
-- corpse, split by whether we can settle it here and now.
--
-- Clearing the corpse is the only way to hand a quest drop over, and it takes
-- everyone's copy with it. That is fine for anyone standing close enough to
-- be handed one first -- they lose nothing. It is not fine for anyone too far
-- away to receive one, and those are what the grace period waits out.
--
-- A member who already looted this corpse by hand has taken what it had for
-- them; a corpse never offers a second copy, so they are not a claimant.
--
-- Group:GetMembers only reports members who are online. An offline member
-- cannot loot the corpse either, and it despawns long before they return, but
-- they are invisible to this check.
local function QuestClaimants(player, corpse, corpseKey, loot)
    local reachable, unreachable = {}, 0

    local group = player:GetGroup()
    if not group then return reachable, 0 end

    local pKey = player:GetGUIDLow()

    for _, member in ipairs(group:GetMembers() or {}) do
        local mKey = member:GetGUIDLow()
        local handed = HandLooted[mKey]

        if mKey ~= pKey and not (handed and handed[corpseKey]) then
            local wants = false
            for _, questItem in ipairs(loot:GetQuestItems() or {}) do
                if NeedsQuestItem(member, questItem) then
                    wants = true
                    break
                end
            end

            if wants then
                if member:IsAtLootRewardDistance(corpse) then
                    reachable[#reachable + 1] = member
                else
                    unreachable = unreachable + 1
                end
            end
        end
    end

    return reachable, unreachable
end

-- Whether the quest loot on this corpse is ours to take. Free when nobody
-- else has a claim. Otherwise it costs the rest of the group their unlooted
-- copies, so we wait out the grace period first -- party members and bots
-- take their own quest drops within a second of the kill.
local function MayTakeQuestLoot(player, pKey, corpseKey, loot, ageTicks, unreachable)
    -- The player already emptied part of this corpse by hand. Their own copy
    -- of a quest drop is marked looted per player, in a flag Lua cannot read,
    -- while the item stays in quest_items looking untouched -- so handing it
    -- over again is how you get two.
    local handed = HandLooted[pKey]
    if handed and handed[corpseKey] then return false end

    -- Nobody is left out of pocket: either no other member wants this drop, or
    -- every member who does is close enough to be handed one before we clear.
    -- Two pets racing for the same corpse both land here, so whichever arrives
    -- first serves the other's owner too.
    if unreachable == 0 then return true end

    if not CONFIG.QUEST_LOOT_IN_PARTY then return false end
    return ageTicks >= GRACE_TICKS
end

local function HasLootWorthFetching(player, loot, inGroup, mayTakeQuest)
    if not loot then return false end

    if (loot:GetMoney() or 0) > 0 then return true end

    -- A drop we are not entitled to yet is not a reason to skip the corpse:
    -- there may still be coin or a grey on it worth the walk.
    if mayTakeQuest then
        for _, questItem in ipairs(loot:GetQuestItems() or {}) do
            if NeedsQuestItem(player, questItem) then return true end
        end
    end

    local questIds = QuestItemIds(loot)
    local items = loot:GetItems()
    local reachable = FirstOfKind(items)

    for _, itemData in ipairs(items or {}) do
        local itemID = itemData.id
        if itemID and itemID > 0
           and not itemData.is_looted
           and not itemData.needs_quest
           and not questIds[itemID]
           and reachable[itemData]
           and ShouldTakeItem(itemID, inGroup) then
            return true
        end
    end

    return false
end

-- ============================================================================
-- FETCH BOOKKEEPING
-- ============================================================================

local function ClearPlayer(pKey)
    Fetching[pKey] = nil
    Skipped[pKey]  = nil
    Seen[pKey]     = nil
    HandLooted[pKey] = nil
    Announced[pKey] = nil
    Tick[pKey]     = nil
    Petless[pKey]  = nil
end

-- Stop fetching, and optionally ignore this corpse for a while.
local function EndFetch(pKey, target, skip)
    -- Only let go of the fetch we were handed. If the stale valve in Sweep
    -- already replaced it, the new one is not ours to cancel.
    if Fetching[pKey] == target then
        Fetching[pKey] = nil
    end

    local corpseKey = target and target.key
    if skip and corpseKey then
        Skipped[pKey] = Skipped[pKey] or {}
        Skipped[pKey][corpseKey] = (Tick[pKey] or 0) + RETRY_TICKS
    end
end

-- ============================================================================
-- THE HARVEST ENGINE
-- ============================================================================

-- Empty one corpse into the player's bags. Returns true if anything at all
-- was taken. `age` is how many sweeps ago the corpse first came into range,
-- which the party quest grace is measured in.
local function HarvestCorpse(player, pKey, corpse, corpseKey, age, haul)
    local loot = corpse:GetLoot()
    if not loot then return false end

    local inGroup = player:IsInGroup()

    -- 1. Money (always taken)
    local copper = loot:GetMoney() or 0
    if copper > 0 then
        player:ModifyMoney(copper)
        loot:SetMoney(0)
        if haul then haul.copper = haul.copper + copper end
    end

    -- 2. Items. Each one is removed from the corpse only for the amount that
    -- actually reached the bags, so the next sweep cannot hand out a second
    -- copy and a full bag cannot make loot vanish.
    local questIds = QuestItemIds(loot)
    local heldBack = false  -- something is still on the corpse for someone
    local itemsTaken = 0

    local items = loot:GetItems()
    local reachable = FirstOfKind(items)  -- see FirstOfKind

    for _, itemData in ipairs(items or {}) do
        local itemID = itemData.id
        local count  = itemData.count or 1

        if itemID and itemID > 0 and not itemData.is_looted then
            if itemData.needs_quest
               or questIds[itemID]
               or not reachable[itemData]
               or not ShouldTakeItem(itemID, inGroup) then
                heldBack = true
            else
                local stored = GiveItem(player, itemID, count)

                if stored >= count then
                    -- Whole stack: mark it in place, the slot stays put.
                    loot:SetItemLooted(itemID, count, true)
                    itemsTaken = itemsTaken + 1
                    AddToHaul(haul, itemID, stored)
                else
                    -- Bags are full, or nearly. The corpse cannot be told
                    -- about a partial take without Loot:RemoveItem, which
                    -- may erase, so whatever was stored goes back and the
                    -- stack stays whole on the corpse.
                    if stored > 0 then
                        player:RemoveItem(itemID, stored)
                    end
                    heldBack = true
                end
            end
        end
    end

    -- 3. Quest loot. Taking it commits us to clearing the whole Loot below,
    -- so it only runs once the corpse holds nothing else at all: a green held
    -- back for a group roll, or an item the bags could not take, blocks it.
    -- MayTakeQuestLoot decides the rest -- see its comment.
    local questTaken, questMissed = 0, 0

    local reachable, unreachable = QuestClaimants(player, corpse, corpseKey, loot)

    if not heldBack and MayTakeQuestLoot(player, pKey, corpseKey, loot, age, unreachable) then
        for _, questItem in ipairs(loot:GetQuestItems() or {}) do
            local count = questItem.count or 1

            -- Party members first. Once the owner has been handed a copy the
            -- clear below is forced, so anyone who would have lost theirs is
            -- served while backing out is still possible.
            for _, member in ipairs(reachable) do
                if NeedsQuestItem(member, questItem) then
                    if GiveItem(member, questItem.id, count) >= count then
                        questTaken = questTaken + 1
                        member:SendBroadcastMessage((GetItemLink(questItem.id) or "Quest loot")
                            .. " was fetched for you by " .. player:GetName() .. "'s companion.")
                    else
                        questMissed = questMissed + 1
                        member:SendBroadcastMessage("A companion could not hand you "
                            .. (GetItemLink(questItem.id) or "quest loot")
                            .. " - your bags are full.")
                    end
                end
            end

            if NeedsQuestItem(player, questItem) then
                if GiveItem(player, questItem.id, count) >= count then
                    questTaken = questTaken + 1
                    AddToHaul(haul, questItem.id, count)
                else
                    questMissed = questMissed + 1
                end
            end
        end
    end

    -- 4. Cleanup.
    -- Once a quest item has been handed over, clearing is required rather than
    -- cosmetic: the item is still sitting in quest_items and could be looted a
    -- second time by hand. Otherwise clear only when the corpse is genuinely
    -- empty -- GetItems() does not report quest loot, so it is counted apart.
    local nothingLeft = (loot:GetMoney() or 0) == 0
                        and not AnyUnlooted(loot:GetItems())
                        and #(loot:GetQuestItems() or {}) == 0

    if questTaken > 0 or nothingLeft then
        loot:Clear()
        corpse:RemoveFlag(UNIT_DYNAMIC_FLAGS, UNIT_DYNFLAG_LOOTABLE)
        corpse:AllLootRemovedFromCorpse()
    end

    if questMissed > 0 then
        player:SendBroadcastMessage("Your companion could not carry all of the quest loot - your bags are full.")
    end

    return copper > 0 or itemsTaken > 0 or questTaken > 0
end

HarvestLoot = function(eventId, player, target)
    local pKey = player:GetGUIDLow()

    local function abort(skip)
        player:RemoveEventById(eventId)
        EndFetch(pKey, target, skip)
        SendPetToHeel(GetVanityPet(player), player)
    end

    local map = player:GetMap()
    if not map then return abort(false) end

    local obj = map:GetWorldObject(target.guid)
    local corpse = obj and obj:ToCreature() or nil
    if not corpse or not corpse:IsDead() then return abort(false) end

    local pet = GetVanityPet(player, map)
    if not pet or player:GetDistance(corpse) > CONFIG.MAX_LOOT_DISTANCE then
        return abort(true)
    end

    if pet:GetDistance(corpse) > CONFIG.ARRIVE_DISTANCE then
        target.polls = target.polls + 1

        if target.polls >= ARRIVE_LIMIT then
            -- A generated path cannot reach every corpse. Underwater is the
            -- one that shows up in play: a ground critter has nowhere to walk
            -- to. Before giving up, send it again in a straight line, which
            -- MovePoint will do when genPath is false.
            if target.straight then return abort(true) end

            target.straight = true
            target.polls = 0
            pet:MoveTo(1, corpse:GetX(), corpse:GetY(), corpse:GetZ(), false)
        end

        return
    end

    player:RemoveEventById(eventId)

    local now = Tick[pKey] or 0

    -- The corpse we walked to. A visit that comes back with nothing means we
    -- cannot make progress here -- full bags, or loot the filter will never
    -- accept -- so it goes on the retry list instead of being walked to on
    -- every sweep.
    local haul = NewHaul()

    local took = HarvestCorpse(player, pKey, corpse, target.key, now - (target.seen or now), haul)
    EndFetch(pKey, target, not took)

    -- Everything else of ours within reach of where the pet now stands. These
    -- are not put on the retry list: if one held only a green, the sweep was
    -- never going to send the pet to it anyway, and if it held a quest drop
    -- still inside its grace, skipping it would only delay the pickup.
    if CONFIG.AOE_LOOT_RADIUS > 0 then
        local seen = Seen[pKey] or {}
        local skipped = Skipped[pKey]

        for _, other in ipairs(pet:GetCreaturesInRange(CONFIG.AOE_LOOT_RADIUS, 0, 0, 2) or {}) do
            local otherKey = other:GetGUIDLow()

            if otherKey ~= target.key
               and not (skipped and skipped[otherKey])
               and other:IsDead()
               and other:IsTappedBy(player) then
                HarvestCorpse(player, pKey, other, otherKey, now - (seen[otherKey] or now), haul)
            end
        end
    end

    AnnounceHaul(player, haul)
    SendPetToHeel(pet, player)
end

-- ============================================================================
-- THE SWEEP
-- ============================================================================

local function Sweep(player)
    if not player then return end

    local map = player:GetMap()
    if not map then return end

    local pKey = player:GetGUIDLow()
    local tick = (Tick[pKey] or 0) + 1
    Tick[pKey] = tick

    local skipped = Skipped[pKey]
    if skipped then
        for corpseKey, expiry in pairs(skipped) do
            if expiry <= tick then skipped[corpseKey] = nil end
        end
    end

    local handed = HandLooted[pKey]
    if handed then
        for corpseKey, expiry in pairs(handed) do
            if expiry <= tick then handed[corpseKey] = nil end
        end
    end

    local announced = Announced[pKey]
    if announced then
        for corpseKey, expiry in pairs(announced) do
            if expiry <= tick then announced[corpseKey] = nil end
        end
    end

    -- Already walking to something -- unless that fetch has plainly died.
    local inFlight = Fetching[pKey]
    if inFlight then
        if tick - (inFlight.started or tick) < STALE_TICKS then return end
        Fetching[pKey] = nil
    end

    if not CONFIG.LOOT_IN_PARTY and player:IsInGroup() then return end

    -- Cheap bail: no vanity pet out, nothing to do. This is the common case
    -- for every other player and bot on the server.
    local pet = GetVanityPet(player, map)
    if not pet then
        MaybeSummonPet(player, pKey)
        return
    end
    Petless[pKey] = 0

    -- range, entryId (0 = any), hostile (0 = both), dead (2 = dead only)
    local corpses = player:GetCreaturesInRange(CONFIG.MAX_LOOT_DISTANCE, 0, 0, 2)
    if not corpses then return end

    local inGroup = player:IsInGroup()
    local best, bestKey, bestDist, bestSeen

    -- Rebuilt every sweep from the corpses actually in range, so it prunes
    -- itself as they despawn or we walk away.
    local seenBefore = Seen[pKey] or {}
    local seenNow = {}

    for _, corpse in ipairs(corpses) do
        local corpseKey = corpse:GetGUIDLow()
        local firstSeen = seenBefore[corpseKey] or tick
        seenNow[corpseKey] = firstSeen

        if not (skipped and skipped[corpseKey])
           and corpse:IsDead()
           and corpse:IsTappedBy(player) then
            local loot = corpse:GetLoot()
            -- A corpse with nothing left on it should not still be
            -- glittering, whether or not the pet ever walked to it. The pet
            -- only visits corpses worth a trip, and the AoE pass only reaches
            -- what is near where it stopped, so anything already empty is
            -- cleared here instead of waiting for a visit that is not coming.
            if loot and (loot:GetMoney() or 0) == 0
               and not AnyUnlooted(loot:GetItems())
               and #(loot:GetQuestItems() or {}) == 0 then
                corpse:RemoveFlag(UNIT_DYNAMIC_FLAGS, UNIT_DYNFLAG_LOOTABLE)
            end

            -- Only worth asking who else has a claim when there is quest
            -- loot here at all; the answer costs a walk over the group.
            local mayTakeQuest = false
            if loot and #(loot:GetQuestItems() or {}) > 0 then
                local _, unreachable = QuestClaimants(player, corpse, corpseKey, loot)
                mayTakeQuest = MayTakeQuestLoot(player, pKey, corpseKey, loot,
                                                tick - firstSeen, unreachable)
            end

            -- Said here rather than on arrival: a corpse holding nothing but a
            -- green is never worth a trip, so the pet never goes, so arrival
            -- would never announce the one case this is for.
            if CONFIG.ANNOUNCE_LEFT_BEHIND and loot
               and not (announced and announced[corpseKey]) then
                local links = LeftBehindLinks(loot, inGroup)

                if #links > 0 then
                    announced = announced or {}
                    Announced[pKey] = announced
                    announced[corpseKey] = tick + HANDLOOT_TICKS

                    Announce(player, "Your companion left "
                        .. table.concat(links, ", ")
                        .. " on " .. corpse:GetName() .. " for the group.",
                        CONFIG.ANNOUNCE_TO)
                end
            end

            if HasLootWorthFetching(player, loot, inGroup, mayTakeQuest) then
                local dist = player:GetDistance(corpse)
                if not bestDist or dist < bestDist then
                    best, bestKey, bestDist, bestSeen = corpse, corpseKey, dist, firstSeen
                end
            end
        end
    end

    Seen[pKey] = seenNow

    if not best then return end

    local target = { guid = best:GetGUID(), key = bestKey, polls = 0,
                     seen = bestSeen, started = tick }
    Fetching[pKey] = target

    pet:MoveTo(1, best:GetX(), best:GetY(), best:GetZ())
    player:RegisterEvent(function(eventId, delay, calls, p)
        HarvestLoot(eventId, p, target)
    end, CONFIG.ARRIVE_POLL, 0)
end

-- ============================================================================
-- LIFECYCLE
-- ============================================================================

local function StartSweeper(player)
    if not player then return end

    player:RegisterEvent(function(eventId, delay, calls, p)
        Sweep(p)
    end, CONFIG.SCAN_INTERVAL, 0)
end

-- Remember which corpses the player has emptied by hand.
--
-- The event is documented as (event, player, item, count) but the hook pushes
-- a fifth value, the GUID of whatever the item came from:
--
--     void ALE::OnLootItem(Player* pPlayer, Item* pItem, uint32 count, ObjectGuid guid)
--
-- Player:AddItem does not go through the loot system, so the pet's own
-- deliveries never land here.
local function OnLootItem(event, player, item, count, guid)
    if not guid then return end

    local corpseKey = GetGUIDLow(guid)
    if not corpseKey then return end

    local pKey = player:GetGUIDLow()
    HandLooted[pKey] = HandLooted[pKey] or {}
    HandLooted[pKey][corpseKey] = (Tick[pKey] or 0) + HANDLOOT_TICKS
end

-- Remember the companion a player chooses, so that is the one that comes
-- back. Fires for every spell cast, so the cheap checks go first.
local function OnSpellCast(event, player, spell, skipCheck)
    if not spell or player:IsBot() then return end

    local spellId = spell:GetEntry()
    if IsCompanionSpell(spellId) then
        Preferred[player:GetGUIDLow()] = spellId
    end
end

local function OnLogin(event, player)
    ClearPlayer(player:GetGUIDLow())
    StartSweeper(player)
end

local function OnLogout(event, player)
    ClearPlayer(player:GetGUIDLow())
end

RegisterPlayerEvent(3, OnLogin)      -- PLAYER_EVENT_ON_LOGIN
RegisterPlayerEvent(4, OnLogout)     -- PLAYER_EVENT_ON_LOGOUT
RegisterPlayerEvent(32, OnLootItem)  -- PLAYER_EVENT_ON_LOOT_ITEM
RegisterPlayerEvent(5, OnSpellCast)   -- PLAYER_EVENT_ON_SPELL_CAST

-- Pick up everyone already online, so .reload ale works without relogging.
local ok, online = pcall(GetPlayersInWorld)
if ok and online then
    for _, p in ipairs(online) do
        ClearPlayer(p:GetGUIDLow())
        StartSweeper(p)
    end
end

print(">> LootPet2 loaded.")
