// Transient work order. Resources come only from validated native world pools.
// Never serialize or resume an in-flight pickup, container or tree action.
class KevinGatheringJob extends Actor
    dependson(ColdLootSpawner);

const MaxOwnerTargetDistance = 5000;
const MaxOwnerWorkDistance = 5500;
const ApproachTimeoutSeconds = 35;

var KevinHunterController Worker;
var KevinWoodHarvester WoodHarvester;
var name JobKind;
var vector SearchOrigin;
var Actor TargetResource;
var vector TargetLocation;
var vector StandLocation;
var vector HitLocation;
var byte TargetBush;
var float TargetStartedAt;
var float SearchRadius;
var int UnitsGathered;
var array<Actor> SkippedResources;
var string LastReason;
var string TargetRejection;
var string FiberContextRejection;
var string LootContextRejection;
var float TargetWorkStartedAt;
var float TargetWorkLastAt;
var bool bSkippedForCapacity;

function bool InitializeJob(KevinHunterController controller, name kind)
{
    Worker = controller;
    JobKind = kind;
    if (Worker == none || Worker.Pawn == none || (kind != 'Wood' && kind != 'Fiber' && kind != 'Loot' && kind != 'Scrap' && kind != 'All')) { return false; }
    SearchOrigin = Worker.Pawn.Location;
    if (kind == 'Wood') {
        WoodHarvester = Spawn(class'KevinWoodHarvester', self);
        if (WoodHarvester == none) { return false; }
        WoodHarvester.Job = self;
    }
    return true;
}

function ColdPlayerInvManager GetInventory()
{
    if (Worker == none || Worker.GetHumanPawn() == none) { return none; }
    return Worker.GetHumanPawn().GetPlayerInvMgr();
}

function bool CanWorkNow()
{
    return Role == ROLE_Authority && WorldInfo.NetMode == NM_Standalone && Worker != none &&
        !Worker.bDeleteMe && !Worker.bCommandMenuOpen && Worker.Pawn != none && Worker.Pawn.Health > 0 &&
        Worker.CompanionOwner != none && Worker.CompanionOwner.Pawn != none && Worker.CompanionOwner.Pawn.Health > 0 &&
        KevinCompanionPawn(Worker.Pawn) != none && !KevinCompanionPawn(Worker.Pawn).IsKevinInventoryBusy() &&
        !Worker.IsInCombat() && Worker.Pawn.Physics != PHYS_Swimming &&
        (Worker.Pawn.PhysicsVolume == none || !Worker.Pawn.PhysicsVolume.bWaterVolume) && !Worker.bIsInBase && !Worker.IsInCave() && !Worker.IsInLavaCave() &&
        VSize(Worker.Pawn.Location - Worker.CompanionOwner.Pawn.Location) <= MaxOwnerWorkDistance && GetInventory() != none;
}

function bool CanFitSingle(class<ColdInventoryItem> itemClass, int count)
{
    local array<ChosenLootItem> items;
    local ChosenLootItem entry;
    entry.ItemClass = itemClass;
    entry.Count = count;
    items.AddItem(entry);
    return CanFitYield(items);
}

function bool HasCargoRoom()
{
    local ColdInventoryItem item;
    local int i;
    if (GetInventory() == none) { return false; }
    for (i = 0; i < 35; i++) {
        item = GetInventory().GetInvItem(i);
        if (item == none || (!item.bDeleteMe && item.bIsStackable && item.Count < item.MaxStackCount)) { return true; }
    }
    return false;
}

function bool CanStartOrder()
{
    if (JobKind == 'Wood') { return CanFitSingle(class'ColdInventoryItem_Log', 1); }
    if (JobKind == 'Fiber') { return CanFitSingle(class'ColdInventoryItem_Fibers', 1); }
    // Actual per-item capacity is checked when the native yield is known. A full
    // cargo can still receive a matching partial stack; never assume it is fiber.
    return (JobKind == 'Loot' || JobKind == 'Scrap' || JobKind == 'All') && HasCargoRoom();
}

function bool CanFitCargoItem(ColdInventoryItem item)
{
    local ColdInventoryItem current;
    local int i, remaining;
    local bool freeSlot;
    if (item == none || item.bDeleteMe || item.Count < 1 || GetInventory() == none ||
        !class'KevinAccessModule'.static.HasSupportedItemStorage(item)) { return false; }
    remaining = item.Count;
    for (i = 0; i < 35; i++) {
        current = GetInventory().GetInvItem(i);
        if (current == none) { freeSlot = true; }
        else if (item.bIsStackable && !current.bDeleteMe && current.CanStackItem(item)) {
            remaining -= Max(0, current.MaxStackCount - current.Count);
        }
    }
    return remaining <= 0 || freeSlot;
}

function bool CanFitPreparedItems(array<ColdInventoryItem> prepared)
{
    local ColdInventoryItem slots[35];
    local int counts[35];
    local int i, j, remaining, amount;
    if (GetInventory() == none) { return false; }
    for (i = 0; i < 35; i++) {
        slots[i] = GetInventory().GetInvItem(i);
        if (slots[i] != none) { counts[i] = slots[i].Count; }
    }
    // Predict native insertion without modifying live item counts, perishability
    // or ownership. CanStackItem respects native edible-state restrictions.
    for (i = 0; i < prepared.Length; i++) {
        if (prepared[i] == none || prepared[i].bDeleteMe || prepared[i].Count < 1 ||
            !class'KevinAccessModule'.static.HasSupportedItemStorage(prepared[i])) { return false; }
        remaining = prepared[i].Count;
        if (prepared[i].bIsStackable) {
            for (j = 0; j < 35; j++) {
                if (slots[j] == none || slots[j].bDeleteMe || !slots[j].CanStackItem(prepared[i])) { continue; }
                amount = Min(remaining, Max(0, slots[j].MaxStackCount - counts[j]));
                counts[j] += amount;
                remaining -= amount;
            }
        }
        if (remaining > 0) {
            for (j = 0; j < 35; j++) {
                if (slots[j] == none) { slots[j] = prepared[i]; counts[j] = remaining; remaining = 0; break; }
            }
        }
        if (remaining > 0) { return false; }
    }
    return true;
}

function bool IsEligiblePickup(ColdLootVegetation plant)
{
    local class<ColdLootVegetation> kind;
    if (plant == none || plant.bDeleteMe || plant.bHidden || plant.bHasHadFakePickup) { return false; }
    kind = plant.Class;
    if (JobKind == 'Fiber') {
        return kind == class'ColdLootVegetation_FiberPlant' || kind == class'ColdLootVegetation_FiberPatch';
    }
    if (JobKind == 'Scrap') { return kind == class'ColdLootVegetation_ScrapMetal'; }
    if (JobKind != 'All') { return false; }
    // Exact native classes, backed by the surface vegetation factory. Dropped
    // inventory, grown crops, cave mushrooms and underwater pickups are separate.
    return kind == class'ColdLootVegetation_FiberPlant' || kind == class'ColdLootVegetation_FiberPatch' ||
        kind == class'ColdLootVegetation_ScrapMetal' || kind == class'ColdLootVegetation_Berries' ||
        kind == class'ColdLootVegetation_RosehipBerries' || kind == class'ColdLootVegetation_Carrot' ||
        kind == class'ColdLootVegetation_Onion' || kind == class'ColdLootVegetation_Potato' ||
        kind == class'ColdLootVegetation_Cotton' || kind == class'ColdLootVegetation_Strawberry' ||
        kind == class'ColdLootVegetation_Wheat' || kind == class'ColdLootVegetation_MedicinalCluster' ||
        kind == class'ColdLootVegetation_LogPile';
}

function bool GetLootContext(ColdLootContainer container, out ColdLootPool_LootContainers pool,
    out ColdSpawnPoint_LootFactory factory, out ColdAccessModule_LootStorage module)
{
    local int slot;
    LootContextRejection = "not an ordinary live loot box";
    pool = none; factory = none; module = none;
    if (container == none || container.bDeleteMe || container.bHidden || !container.bUsesLootPool ||
        (container.Class != class'ColdLootContainer_Ammo' && container.Class != class'ColdLootContainer_Medical' &&
        container.Class != class'ColdLootContainer_BuildingSupplies') ||
        (JobKind != 'Loot' && JobKind != 'All') || Worker == none || Worker.CompanionOwner == none) { return false; }
    pool = container.GetOwningLootPool();
    LootContextRejection = "loot box belongs to another or missing player pool";
    if (pool == none || pool.bDeleteMe || pool.GetPc() != Worker.CompanionOwner ||
        pool.SpawnPointBelongingTo == none || pool.SpawnPointBelongingTo.bDeleteMe ||
        ColdSpawnPointWater(pool.SpawnPointBelongingTo) != none ||
        ColdSpawnPointCave(pool.SpawnPointBelongingTo) != none ||
        ColdSpawnPointLavaCave(pool.SpawnPointBelongingTo) != none) { return false; }
    factory = pool.GetLootFactory();
    slot = container.LootPoolIdx;
    LootContextRejection = "loot box has no matching surface factory slot";
    if (factory == none || factory.bDeleteMe || factory.IsInCave() || factory.SpawnPoint != pool.SpawnPointBelongingTo ||
        slot >= ArrayCount(pool.ContainerSpawnsSpawned) || slot >= ArrayCount(factory.ContainerSpawns) ||
        pool.ContainerSpawnsSpawned[slot] != container || factory.ContainerSpawns[slot].Type == 0 ||
        factory.ContainerSpawns[slot].Loc != container.Location ||
        pool.ContainerSpawns[slot].Loc != container.Location ||
        pool.ContainerSpawns[slot].Type != factory.ContainerSpawns[slot].Type ||
        class'ColdLootPoolHelper'.static.GetLootContainerTypeById(factory.ContainerSpawns[slot].Type) != container.Class ||
        pool.ContainerSpawns[slot].bIsOpen != factory.ContainerSpawns[slot].bIsOpen ||
        container.bIsOpen != factory.ContainerSpawns[slot].bIsOpen) { return false; }
    LootContextRejection = "loot box is being accessed or unlocked by the player";
    if (container.bIsBeingUnlocked || container.IsBeingAccessed() || pool.ContainerSpawns[slot].bIsBeingAccessed ||
        factory.ContainerSpawns[slot].bIsBeingAccessed) { return false; }
    module = ColdAccessModule_LootStorage(factory.ContainerSpawns[slot].AM);
    LootContextRejection = "loot box inventory ownership differs";
    if (factory.ContainerSpawns[slot].AM != none && (module == none || module.bDeleteMe ||
        module.Owner != factory || module.OriginalOwner != factory || module.LootPoolIdx != slot ||
        module.InvSize < 1 || module.InvSize != module.Items.Length || module.Items.Length > 49)) { return false; }
    if ((container.bIsOpen && module == none) || (!container.bIsOpen && module != none)) { return false; }
    LootContextRejection = "";
    return true;
}

function bool IsLootItemOwned(ColdInventoryItem item, ColdAccessModule_LootStorage module, int slot)
{
    local int i;
    if (item == none || item.bDeleteMe || item.Count < 1 || module == none || module.bDeleteMe || GetInventory() == none ||
        slot < 0 || slot >= module.Items.Length || module.GetInvItem(slot) != item ||
        item.Owner != module.Owner || item.InvSlotInfo.InvTypeId != 1 || item.InvSlotInfo.SlotId != slot ||
        item.InvSlotInfo.ParentItem != none || !class'KevinAccessModule'.static.HasSupportedItemStorage(item)) { return false; }
    for (i = 0; i < module.Items.Length; i++) { if (i != slot && module.GetInvItem(i) == item) { return false; } }
    // A stale duplicate reference must not move an actor already owned by cargo.
    for (i = 0; i < 49; i++) { if (GetInventory().GetInvItem(i) == item) { return false; } }
    return true;
}

function bool LootContainer()
{
    local ColdLootContainer container;
    local ColdLootPool_LootContainers pool;
    local ColdSpawnPoint_LootFactory factory;
    local ColdAccessModule_LootStorage module;
    local ColdInventoryItem item;
    local class<ColdLootContainer> containerClass;
    local int i, count, slot;
    if (!CanWorkNow() || !IsTargetInReach()) { return false; }
    container = ColdLootContainer(TargetResource);
    if (!GetLootContext(container, pool, factory, module)) { return false; }
    if (!HasCargoRoom()) { LastReason = "Kevin's cargo is full."; return false; }
    slot = container.LootPoolIdx;
    if (!container.bIsOpen) {
        // Spend the native unlock duration at the box. Do not borrow the player's
        // inventory/UI or hold its ownership across ticks. Every attempt rechecks
        // the live slot and stops if the player starts accessing it.
        if (TargetWorkStartedAt < 0 || TargetWorkLastAt < 0 || WorldInfo.TimeSeconds - TargetWorkLastAt > 2.5) {
            TargetWorkStartedAt = WorldInfo.TimeSeconds;
        }
        TargetWorkLastAt = WorldInfo.TimeSeconds;
        if (WorldInfo.TimeSeconds - TargetWorkStartedAt < FMax(0.0, container.TimeToUnlock)) { return true; }
        containerClass = container.Class;
        // This native guarded entry point rolls the active table once, marks
        // open/looted, and preserves difficulty, season and respawn accounting.
        containerClass.static.FinishedUnlocking(Worker.CompanionOwner, none, pool, byte(slot));
        if (!GetLootContext(container, pool, factory, module) || !container.bIsOpen || module == none) { return false; }
    }
    for (i = 0; i < module.Items.Length; i++) {
        item = module.GetInvItem(i);
        if (!IsLootItemOwned(item, module, i)) { continue; }
        if (!CanFitCargoItem(item)) { bSkippedForCapacity = true; continue; }
        count = item.Count;
        // Detach before native stacking. Reset the entire slot record after the
        // native notification, including its replication bit, so merging the last
        // unit cannot ask Kevin's manager to clear the former external slot.
        module.ClearSlot(i, false);
        item.InvSlotInfo = class'ColdInventoryItem'.default.InvSlotInfo;
        if (!AddPreparedItem(item)) {
            // Native insertion drops any remainder at Kevin. All other actual
            // items remain in the crate; never delete or recreate its contents.
            LastReason = "Kevin's cargo changed; any loose collected items are at his feet.";
            return false;
        }
        UnitsGathered += count;
    }
    // This native release path removes only an empty crate, destroys its empty
    // module, updates visible pools and starts the ordinary respawn cooldown.
    if (module.GetItemCount() == 0) { factory.NotifyPlayerReleasedContainerAccessModule(byte(slot), module); }
    else { SkipTarget(); }
    TargetResource = none;
    TargetWorkStartedAt = -1; TargetWorkLastAt = -1;
    return true;
}

function bool CanFitYield(array<ChosenLootItem> items)
{
    local ColdPlayerInvManager inv;
    local ColdInventoryItem current;
    local int i, j, count, room, maxStack, emptySlots, neededSlots;
    local bool handled;
    inv = GetInventory();
    if (inv == none) { return false; }
    for (i = 0; i < 35; i++) { if (inv.GetInvItem(i) == none) { emptySlots++; } }
    for (i = 0; i < items.Length; i++) {
        if (items[i].ItemClass == none || items[i].Count < 1) { return false; }
        handled = false;
        for (j = 0; j < i; j++) { if (items[j].ItemClass == items[i].ItemClass) { handled = true; } }
        if (handled) { continue; }
        count = 0;
        for (j = i; j < items.Length; j++) { if (items[j].ItemClass == items[i].ItemClass) { count += items[j].Count; } }
        room = 0;
        maxStack = items[i].ItemClass.default.bIsStackable ? Max(1, items[i].ItemClass.static.GetMaxStackCount()) : 1;
        if (items[i].ItemClass.default.bIsStackable) {
            for (j = 0; j < 35; j++) {
                current = inv.GetInvItem(j);
                if (current != none && current.Class == items[i].ItemClass && !current.bDeleteMe) {
                    room += Max(0, current.MaxStackCount - current.Count);
                }
            }
        }
        neededSlots += (Max(0, count - room) + maxStack - 1) / maxStack;
    }
    return neededSlots <= emptySlots;
}

function bool AddPreparedItem(ColdInventoryItem item)
{
    local array<int> avoid;
    local int i;
    if (item == none || GetInventory() == none) { return false; }
    // Harvests go into cargo only. Never fill belt/clothing or reserved slot42.
    for (i = 35; i < 49; i++) { avoid.AddItem(i); }
    return GetInventory().InternalAddItemToInventory(item, 0, none, false, false, avoid);
}

function bool IsTreeAvailable(ColdTree tree)
{
    local ColdPlayerPawn ownerPawn;
    local int i;
    if (tree == none || tree.bDeleteMe || tree.bIsOutsideWorld || tree.GetNumLogsToYield() <= 0 ||
        Worker == none || Worker.CompanionOwner == none) { return false; }
    ownerPawn = ColdPlayerPawn(Worker.CompanionOwner.Pawn);
    if (ownerPawn == none || ownerPawn.HarvestManager == none) { return false; }
    for (i = 0; i < ownerPawn.HarvestManager.HarvestedTrees.Length; i++) {
        if (ownerPawn.HarvestManager.HarvestedTrees[i].treeId == string(tree)) {
            return ownerPawn.HarvestManager.HarvestedTrees[i].chopProgress >= 0 &&
                ownerPawn.HarvestManager.HarvestedTrees[i].logsSpawned < tree.GetNumLogsToYield();
        }
    }
    return true;
}

function bool GetPickupContext(ColdLootVegetation plant, out ColdLootPool pool,
    out ColdSpawnPoint_VegetationFactory factory, out class<ColdLootVegetation> vegetationClass)
{
    local int slot;
    FiberContextRejection = "not a supported live surface pickup";
    if (!IsEligiblePickup(plant) || Worker == none || Worker.CompanionOwner == none) { return false; }
    pool = plant.GetLootPool();
    FiberContextRejection = "missing owning loot pool";
    if (pool == none || pool.bDeleteMe) { return false; }
    FiberContextRejection = "loot pool belongs to another player";
    if (pool.GetPc() != Worker.CompanionOwner) { return false; }
    FiberContextRejection = "loot pool has no spawn point";
    if (pool.SpawnPointBelongingTo == none || pool.SpawnPointBelongingTo.bDeleteMe ||
        ColdSpawnPointWater(pool.SpawnPointBelongingTo) != none ||
        ColdSpawnPointCave(pool.SpawnPointBelongingTo) != none ||
        ColdSpawnPointLavaCave(pool.SpawnPointBelongingTo) != none) { return false; }
    factory = pool.SpawnPointBelongingTo.VegetationFactory;
    slot = plant.LootPoolIdx;
    FiberContextRejection = "missing live vegetation factory";
    if (factory == none || factory.bDeleteMe || ColdSpawnPoint_UnderwaterVegetationFactory(factory) != none) { return false; }
    FiberContextRejection = "loot slot out of range";
    if (slot >= ArrayCount(pool.VegetationLootSpawnsSpawned) || slot >= ArrayCount(factory.VegetationLootSpawns)) { return false; }
    FiberContextRejection = "loot slot actor identity differs";
    if (pool.VegetationLootSpawnsSpawned[slot] != plant) { return false; }
    FiberContextRejection = "factory slot already consumed";
    if (factory.VegetationLootSpawns[slot].LootType < 1) { return false; }
    FiberContextRejection = "factory location differs from actor";
    if (factory.VegetationLootSpawns[slot].Loc != plant.Location) { return false; }
    FiberContextRejection = "pool and factory states differ";
    if (pool.VegetationLootSpawns[slot]._State != factory.VegetationLootSpawns[slot]._State) { return false; }
    vegetationClass = class'ColdLootPoolHelper'.static.GetVegetationTypeById(factory.VegetationLootSpawns[slot].LootType);
    FiberContextRejection = "factory vegetation class differs";
    if (vegetationClass == none || plant.Class != vegetationClass) { return false; }
    FiberContextRejection = "";
    return true;
}

function bool SelectPickup(ColdLootVegetation plant, out vector atLocation, out byte bushId)
{
    local ColdLootPool pool;
    local ColdSpawnPoint_VegetationFactory factory;
    local class<ColdLootVegetation> vegetationClass;
    local ColdLootVegetation_Cluster cluster;
    local int i;
    if (!GetPickupContext(plant, pool, factory, vegetationClass)) { return false; }
    cluster = ColdLootVegetation_Cluster(plant);
    if (cluster == none) { atLocation = plant.Location; bushId = 0; return true; }
    for (i = 0; i < 8; i++) {
        if (cluster.ShowingBushes[i] == 1 && cluster.IsBushNumInState(byte(i))) {
            atLocation = cluster.TransformLocalLocToWorld(cluster.BushPositions[i].Loc);
            bushId = byte(i);
            return true;
        }
    }
    FiberContextRejection = "cluster has no visible unpicked bush";
    return false;
}

// Retained entry points for existing fiber validation and callers.
function bool GetFiberContext(ColdLootVegetation plant, out ColdLootPool pool,
    out ColdSpawnPoint_VegetationFactory factory, out class<ColdLootVegetation> vegetationClass)
{
    if (plant == none || (plant.Class != class'ColdLootVegetation_FiberPlant' &&
        plant.Class != class'ColdLootVegetation_FiberPatch')) { return false; }
    return GetPickupContext(plant, pool, factory, vegetationClass);
}

function bool SelectFiberBush(ColdLootVegetation plant, out vector atLocation, out byte bushId)
{
    if (plant == none || (plant.Class != class'ColdLootVegetation_FiberPlant' &&
        plant.Class != class'ColdLootVegetation_FiberPatch')) { return false; }
    return SelectPickup(plant, atLocation, bushId);
}

function bool SetResourceTarget(Actor resource, vector resourceLocation, optional byte bushId)
{
    local vector start, hitLoc, hitNorm, ground, direction;
    local Actor hit;
    TargetRejection = "missing actor";
    if (resource == none || Worker == none || Worker.Pawn == none) { return false; }
    TargetRejection = "too far from player";
    if (Worker.CompanionOwner == none || Worker.CompanionOwner.Pawn == none ||
        VSize(resourceLocation - Worker.CompanionOwner.Pawn.Location) > MaxOwnerTargetDistance) { return false; }
    ground = resourceLocation;
    if (ColdTree(resource) != none) {
        ground = ColdTree(resource).GetGroundLocAtBaseOfTree();
        TargetRejection = "tree ground trace failed";
        if (ground == vect(0,0,0)) { return false; }
        start = Worker.Pawn.Location;
        hit = Worker.Pawn.Trace(hitLoc, hitNorm, ground + vect(0,0,74), start, true);
        TargetRejection = "trunk blocked by " $ string(hit);
        if (hit != resource) { return false; }
        ground = hitLoc + Normal(start - hitLoc) * (Worker.Pawn.GetCollisionRadius() + 20);
    } else if (ColdLootContainer(resource) != none) {
        // Trace the ground beside the crate. A downward trace through its center
        // hits the crate mesh instead of the landscape and cannot yield a stand.
        direction = Worker.Pawn.Location - resourceLocation;
        direction.Z = 0;
        if (VSize(direction) < 1) { direction = vect(1,0,0); }
        ground = resourceLocation + Normal(direction) * 130;
    }
    StandLocation = class'ColdPositionHelper'.static.GetPathingLocationFromLoc(
        Worker.Pawn, ground, true, 300, false, false, false, false);
    TargetRejection = "stand ground trace failed";
    if (StandLocation == vect(0,0,0)) { return false; }
    TargetRejection = "stand elevation difference";
    if (Abs(StandLocation.Z - Worker.Pawn.Location.Z) > 240) { return false; }
    if (TargetResource != resource || TargetBush != bushId) { TargetWorkStartedAt = -1; TargetWorkLastAt = -1; }
    TargetResource = resource;
    TargetLocation = resourceLocation;
    TargetBush = bushId;
    TargetStartedAt = WorldInfo.TimeSeconds;
    TargetRejection = "";
    return true;
}

function bool FindResource()
{
    local ColdTree tree;
    local ColdLootVegetation plant;
    local ColdLootContainer container;
    local ColdLootPool_LootContainers lootPool;
    local ColdSpawnPoint_LootFactory lootFactory;
    local ColdAccessModule_LootStorage lootModule;
    local Actor best;
    local vector bestLocation, atLocation;
    local byte bush, bestBush;
    local float distance, bestDistance;
    local int checked, found, available, allFiber, outsideRange, skipped;
    LastReason = "";
    if (!CanWorkNow()) { LastReason = "Gathering is unavailable here."; return false; }
    // Continue from Kevin's current position after each resource, rather than
    // exhausting only the small patch where the order was first issued.
    SearchOrigin = Worker.Pawn.Location;
    bestDistance = 1000000;
    if (JobKind == 'Wood') {
        if (!Worker.HasUsableAxe()) { LastReason = "Give Kevin a usable axe to gather wood."; return false; }
        if (!CanFitSingle(class'ColdInventoryItem_Log', 1)) { LastReason = "Kevin's cargo is full."; return false; }
        foreach CollidingActors(class'ColdTree', tree, SearchRadius, SearchOrigin) {
            distance = VSize(tree.Location - SearchOrigin);
            if (distance > SearchRadius) { outsideRange++; continue; }
            found++;
            if (SkippedResources.Find(tree) != INDEX_NONE) { skipped++; continue; }
            if (!IsTreeAvailable(tree)) { continue; }
            available++;
            checked++;
            // Inspect the complete local query; actor enumeration order must
            // not hide a reachable target beyond an arbitrary first64 entries.
            if (distance >= bestDistance) { continue; }
            if (distance < bestDistance && SetResourceTarget(tree, tree.Location)) {
                best = tree; bestLocation = tree.Location; bestDistance = distance;
            }
            else if (checked <= 8) {
                LogInternal("KEVIN GATHER TREE candidate=" $ string(tree) $ " loc=" $ string(tree.Location) $
                    " distance=" $ string(distance) $ " rejected=" $ TargetRejection);
            }
        }
    } else if (JobKind != 'Loot') {
        foreach DynamicActors(class'ColdLootVegetation', plant) {
            if (!IsEligiblePickup(plant)) { continue; }
            allFiber++;
            if (VSize(plant.Location - SearchOrigin) > SearchRadius) { outsideRange++; continue; }
            found++;
            if (SkippedResources.Find(plant) != INDEX_NONE) { skipped++; continue; }
            if (!SelectPickup(plant, atLocation, bush)) {
                if (found <= 8) { LogInternal("KEVIN GATHER FIBER context=" $ FiberContextRejection $ " actor=" $ string(plant)); }
                continue;
            }
            available++;
            checked++;
            distance = VSize(atLocation - Worker.Pawn.Location);
            if (distance < bestDistance && SetResourceTarget(plant, atLocation, bush)) {
                best = plant; bestLocation = atLocation; bestBush = bush; bestDistance = distance;
            }
        }
    }
    if (JobKind == 'Loot' || JobKind == 'All') {
        foreach DynamicActors(class'ColdLootContainer', container) {
            distance = VSize(container.Location - SearchOrigin);
            if (distance > SearchRadius) { continue; }
            if (SkippedResources.Find(container) != INDEX_NONE || distance >= bestDistance) { continue; }
            if (!GetLootContext(container, lootPool, lootFactory, lootModule)) { continue; }
            found++;
            available++;
            checked++;
            if (SetResourceTarget(container, container.Location)) {
                best = container; bestLocation = container.Location; bestBush = 0; bestDistance = distance;
            }
        }
    }
    if (best != none) { return SetResourceTarget(best, bestLocation, bestBush); }
    TargetResource = none;
    LogInternal("KEVIN GATHER SEARCH EMPTY kind=" $ string(JobKind) $ " worker=" $ string(Worker.Pawn.Location) $
        " owner=" $ string(Worker.CompanionOwner.Pawn.Location) $ " origin=" $ string(SearchOrigin) $
        " radius=" $ string(SearchRadius) $ " outsideRange=" $ string(outsideRange) $ " skipped=" $ string(skipped) $
        " candidates=" $ string(found) $ " available=" $ string(available) $ " checked=" $ string(checked) $
        " allRenderedFiber=" $ string(allFiber));
    if (JobKind == 'Wood') { LastReason = "No reachable wood remains nearby."; }
    else if (JobKind == 'Fiber') { LastReason = "No reachable fiber remains nearby."; }
    else if (JobKind == 'Scrap') { LastReason = "No reachable scrap metal remains nearby."; }
    else if (JobKind == 'Loot') { LastReason = "No reachable ordinary loot boxes remain nearby."; }
    else { LastReason = "No reachable surface pickups or ordinary loot boxes remain nearby."; }
    if (bSkippedForCapacity) { LastReason = "No more nearby loot fits Kevin's cargo; leftovers stay in the world."; }
    return false;
}

function bool IsTargetInReach()
{
    local Actor hit;
    local vector hitNorm, end, start;
    if (TargetResource == none || TargetResource.bDeleteMe || Worker == none || Worker.Pawn == none) { return false; }
    if (Worker.CompanionOwner == none || Worker.CompanionOwner.Pawn == none ||
        VSize(TargetLocation - Worker.CompanionOwner.Pawn.Location) > MaxOwnerTargetDistance) { return false; }
    start = Worker.Pawn.GetWeaponStartTraceLocation();
    if (ColdTree(TargetResource) != none) {
        end = ColdTree(TargetResource).GetGroundLocAtBaseOfTree() + vect(0,0,74);
        hit = Worker.Pawn.Trace(HitLocation, hitNorm, end, start, true);
        return hit == TargetResource && VSize(HitLocation - start) <= 180;
    }
    if (VSize(TargetLocation - Worker.Pawn.Location) > 220) { return false; }
    hit = Worker.Pawn.Trace(HitLocation, hitNorm, TargetLocation + vect(0,0,30), start, true);
    return hit == none || hit == TargetResource;
}

function vector GetApproachPoint()
{
    if (TargetResource == none || TargetResource.bDeleteMe ||
        WorldInfo.TimeSeconds - TargetStartedAt > ApproachTimeoutSeconds) { return vect(0,0,0); }
    return class'ColdPositionHelper'.static.GetNonBlockedPathTowardsLocation(
        Worker.Pawn, Worker.Pawn.Location, StandLocation, 600, 0, 300, true, false, false, false, false);
}

function SkipTarget()
{
    if (TargetResource != none && SkippedResources.Find(TargetResource) == INDEX_NONE) { SkippedResources.AddItem(TargetResource); }
    TargetResource = none;
    TargetWorkStartedAt = -1;
    TargetWorkLastAt = -1;
}

function bool PerformHarvest()
{
    if (!CanWorkNow() || !IsTargetInReach()) { return false; }
    if (JobKind == 'Wood') {
        if (!Worker.HasUsableAxe()) { LastReason = "Kevin needs a usable axe."; return false; }
        if (!CanFitSingle(class'ColdInventoryItem_Log', 1)) { LastReason = "Kevin's cargo is full."; return false; }
        if (WoodHarvester == none || !WoodHarvester.ChopActualTree(ColdTree(TargetResource), HitLocation)) {
            LastReason = "Kevin cannot harvest this tree."; return false;
        }
        if (!IsTreeAvailable(ColdTree(TargetResource))) { TargetResource = none; }
        return true;
    }
    if (ColdLootContainer(TargetResource) != none) { return LootContainer(); }
    return HarvestPickup();
}

function bool HarvestFiber()
{
    if (ColdLootVegetation_FiberPlant(TargetResource) == none &&
        ColdLootVegetation_FiberPatch(TargetResource) == none) { return false; }
    return HarvestPickup();
}

function bool HarvestPickup()
{
    local ColdLootVegetation plant;
    local ColdLootVegetation_Cluster cluster;
    local ColdLootPool pool;
    local ColdSpawnPoint_VegetationFactory factory;
    local class<ColdLootVegetation> vegetationClass;
    local array<ChosenLootItem> items;
    local array<ColdInventoryItem> prepared;
    local ColdInventoryItem item;
    local byte interaction, oldState, newState, slot;
    local int i, j, count;
    local bool changeState;
    plant = ColdLootVegetation(TargetResource);
    if (!CanWorkNow() || !IsTargetInReach() || !GetPickupContext(plant, pool, factory, vegetationClass)) { return false; }
    slot = plant.LootPoolIdx;
    oldState = factory.VegetationLootSpawns[slot]._State;
    interaction = 0;
    cluster = ColdLootVegetation_Cluster(plant);
    if (cluster != none) {
        if (TargetBush >= 8 || cluster.ShowingBushes[TargetBush] != 1 || !cluster.IsBushNumInState(TargetBush)) { return false; }
        interaction = cluster.IsLastBush(TargetBush) ? byte(class'ColdLootVegetation_Cluster'.const.InteractionIdForPickedFinalPlant) : TargetBush;
    }
    if (!vegetationClass.static.IsPickupInteractionAllowed(interaction, oldState)) { return false; }
    // Use the active native/modded table once. Check capacity before world mutation.
    items = vegetationClass.static.ChooseYield();
    if (!CanFitYield(items)) {
        if (JobKind == 'All' && HasCargoRoom()) { bSkippedForCapacity = true; SkipTarget(); return true; }
        LastReason = "Kevin's cargo is full."; return false;
    }
    for (i = 0; i < items.Length; i++) {
        item = Spawn(items[i].ItemClass, self);
        if (item == none) {
            for (j = 0; j < prepared.Length; j++) { prepared[j].Destroy(); }
            LastReason = "Could not collect this pickup."; return false;
        }
        item.SetInitialCount(items[i].Count);
        prepared.AddItem(item);
        count += items[i].Count;
    }
    if (!CanFitPreparedItems(prepared)) {
        for (j = 0; j < prepared.Length; j++) { prepared[j].Destroy(); }
        if (JobKind == 'All' && HasCargoRoom()) { bSkippedForCapacity = true; SkipTarget(); return true; }
        LastReason = "Kevin cannot fit this pickup in his cargo."; return false;
    }
    changeState = vegetationClass.static.ShouldPickupChangeStateInsteadOfRemove(interaction, oldState, newState);
    if (changeState) { factory.UpdateVegetationState(slot, newState); }
    else { factory.RemoveVegetation(slot, true); }
    if ((changeState && (newState == oldState || factory.VegetationLootSpawns[slot]._State != newState)) ||
        (!changeState && factory.VegetationLootSpawns[slot].LootType != 0)) {
        for (j = 0; j < prepared.Length; j++) { prepared[j].Destroy(); }
        LastReason = "This pickup is no longer available."; return false;
    }
    // The factory has now consumed this exact bush and updated the visible pool.
    // Native insertion owns/merges each actor; an unexpected failure drops the
    // real item at Kevin and ends work instead of deleting it or rewarding twice.
    for (i = 0; i < prepared.Length; i++) {
        if (!AddPreparedItem(prepared[i])) {
            for (j = i + 1; j < prepared.Length; j++) { prepared[j].Action_Drop(Worker.Pawn); }
            LastReason = "Kevin's cargo is full; collected items are at his feet."; return false;
        }
    }
    UnitsGathered += count;
    Worker.Pawn.PlaySound(vegetationClass.default.PickupSound);
    TargetResource = none;
    return true;
}

simulated function Destroyed()
{
    if (WoodHarvester != none) { WoodHarvester.Destroy(); WoodHarvester = none; }
    Worker = none;
    TargetResource = none;
    super.Destroyed();
}

defaultproperties
{
    TargetWorkStartedAt=-1
    TargetWorkLastAt=-1
    SearchRadius=4500
    bHidden=true
    bCollideActors=false
    bBlockActors=false
    RemoteRole=ROLE_None
}
