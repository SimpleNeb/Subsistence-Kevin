// Transient work order. Resources come only from a validated world tree/bush.
// UNCOMPILED feature work; never serialize or resume an in-flight resource action.
class KevinGatheringJob extends Actor
    dependson(ColdLootSpawner);

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

function bool InitializeJob(KevinHunterController controller, name kind)
{
    Worker = controller;
    JobKind = kind;
    if (Worker == none || Worker.Pawn == none || (kind != 'Wood' && kind != 'Fiber')) { return false; }
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
        !Worker.IsInCombat() && !Worker.bIsInBase && !Worker.IsInCave() && !Worker.IsInLavaCave() &&
        VSize(Worker.Pawn.Location - Worker.CompanionOwner.Pawn.Location) <= 1800 && GetInventory() != none;
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

function bool GetFiberContext(ColdLootVegetation plant, out ColdLootPool pool,
    out ColdSpawnPoint_VegetationFactory factory, out class<ColdLootVegetation> vegetationClass)
{
    local int slot;
    FiberContextRejection = "not a live fiber actor";
    if (plant == none || plant.bDeleteMe || (ColdLootVegetation_FiberPlant(plant) == none &&
        ColdLootVegetation_FiberPatch(plant) == none)) { return false; }
    pool = plant.GetLootPool();
    FiberContextRejection = "missing owning loot pool";
    if (pool == none || pool.bDeleteMe) { return false; }
    FiberContextRejection = "loot pool belongs to another player";
    if (pool.GetPc() != Worker.CompanionOwner) { return false; }
    FiberContextRejection = "loot pool has no spawn point";
    if (pool.SpawnPointBelongingTo == none) { return false; }
    factory = pool.SpawnPointBelongingTo.VegetationFactory;
    slot = plant.LootPoolIdx;
    FiberContextRejection = "missing live vegetation factory";
    if (factory == none || factory.bDeleteMe) { return false; }
    FiberContextRejection = "loot slot out of range";
    if (slot >= ArrayCount(pool.VegetationLootSpawnsSpawned)) { return false; }
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

function bool SelectFiberBush(ColdLootVegetation plant, out vector atLocation, out byte bushId)
{
    local ColdLootPool pool;
    local ColdSpawnPoint_VegetationFactory factory;
    local class<ColdLootVegetation> vegetationClass;
    local ColdLootVegetation_Cluster cluster;
    local int i;
    if (!GetFiberContext(plant, pool, factory, vegetationClass)) { return false; }
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

function bool SetResourceTarget(Actor resource, vector resourceLocation, optional byte bushId)
{
    local vector start, hitLoc, hitNorm, ground;
    local Actor hit;
    TargetRejection = "missing actor";
    if (resource == none || Worker == none || Worker.Pawn == none) { return false; }
    TargetRejection = "too far from player";
    if (Worker.CompanionOwner == none || Worker.CompanionOwner.Pawn == none ||
        VSize(resourceLocation - Worker.CompanionOwner.Pawn.Location) > 1650) { return false; }
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
    }
    StandLocation = class'ColdPositionHelper'.static.GetPathingLocationFromLoc(
        Worker.Pawn, ground, true, 300, false, false, false, false);
    TargetRejection = "stand ground trace failed";
    if (StandLocation == vect(0,0,0)) { return false; }
    TargetRejection = "stand elevation difference";
    if (Abs(StandLocation.Z - Worker.Pawn.Location.Z) > 240) { return false; }
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
    local Actor best;
    local vector bestLocation, atLocation;
    local byte bush, bestBush;
    local float distance, bestDistance;
    local int checked, found, available, allFiber;
    LastReason = "";
    if (!CanWorkNow()) { LastReason = "Gathering is unavailable here."; return false; }
    bestDistance = 1000000;
    if (JobKind == 'Wood') {
        if (!Worker.HasUsableAxe()) { LastReason = "Give Kevin a usable axe to gather wood."; return false; }
        if (!CanFitSingle(class'ColdInventoryItem_Log', 1)) { LastReason = "Kevin's cargo is full."; return false; }
        foreach CollidingActors(class'ColdTree', tree, SearchRadius, SearchOrigin) {
            found++;
            if (SkippedResources.Find(tree) != INDEX_NONE || !IsTreeAvailable(tree)) { continue; }
            available++;
            if (++checked > 64) { break; }
            distance = VSize(tree.Location - Worker.Pawn.Location);
            if (distance >= bestDistance) { continue; }
            if (distance < bestDistance && SetResourceTarget(tree, tree.Location)) {
                best = tree; bestLocation = tree.Location; bestDistance = distance;
            }
            else if (checked <= 8) {
                LogInternal("KEVIN GATHER TREE candidate=" $ string(tree) $ " loc=" $ string(tree.Location) $
                    " distance=" $ string(distance) $ " rejected=" $ TargetRejection);
            }
        }
    } else {
        foreach DynamicActors(class'ColdLootVegetation', plant) {
            if (ColdLootVegetation_FiberPlant(plant) == none && ColdLootVegetation_FiberPatch(plant) == none) { continue; }
            allFiber++;
            if (VSize(plant.Location - SearchOrigin) > SearchRadius || SkippedResources.Find(plant) != INDEX_NONE) { continue; }
            found++;
            if (!SelectFiberBush(plant, atLocation, bush)) {
                if (found <= 8) { LogInternal("KEVIN GATHER FIBER context=" $ FiberContextRejection $ " actor=" $ string(plant)); }
                continue;
            }
            available++;
            if (++checked > 64) { break; }
            distance = VSize(atLocation - Worker.Pawn.Location);
            if (distance < bestDistance && SetResourceTarget(plant, atLocation, bush)) {
                best = plant; bestLocation = atLocation; bestBush = bush; bestDistance = distance;
            }
        }
    }
    if (best != none) { return SetResourceTarget(best, bestLocation, bestBush); }
    TargetResource = none;
    LogInternal("KEVIN GATHER SEARCH EMPTY kind=" $ string(JobKind) $ " worker=" $ string(Worker.Pawn.Location) $
        " owner=" $ string(Worker.CompanionOwner.Pawn.Location) $ " origin=" $ string(SearchOrigin) $
        " candidates=" $ string(found) $ " available=" $ string(available) $ " checked=" $ string(checked) $
        " allRenderedFiber=" $ string(allFiber));
    LastReason = JobKind == 'Wood' ? "No reachable wood remains nearby." : "No reachable fiber remains nearby.";
    return false;
}

function bool IsTargetInReach()
{
    local Actor hit;
    local vector hitNorm, end, start;
    if (TargetResource == none || TargetResource.bDeleteMe || Worker == none || Worker.Pawn == none) { return false; }
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
    if (TargetResource == none || TargetResource.bDeleteMe || WorldInfo.TimeSeconds - TargetStartedAt > 20) { return vect(0,0,0); }
    return class'ColdPositionHelper'.static.GetNonBlockedPathTowardsLocation(
        Worker.Pawn, Worker.Pawn.Location, StandLocation, 600, 0, 300, true, false, false, false, false);
}

function SkipTarget()
{
    if (TargetResource != none && SkippedResources.Find(TargetResource) == INDEX_NONE) { SkippedResources.AddItem(TargetResource); }
    TargetResource = none;
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
    return HarvestFiber();
}

function bool HarvestFiber()
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
    if (!CanWorkNow() || !IsTargetInReach() || !GetFiberContext(plant, pool, factory, vegetationClass)) { return false; }
    slot = plant.LootPoolIdx;
    oldState = factory.VegetationLootSpawns[slot]._State;
    interaction = 0;
    cluster = ColdLootVegetation_Cluster(plant);
    if (cluster != none) {
        if (TargetBush >= 8 || cluster.ShowingBushes[TargetBush] != 1 || !cluster.IsBushNumInState(TargetBush)) { return false; }
        interaction = cluster.IsLastBush(TargetBush) ? byte(class'ColdLootVegetation_Cluster'.const.InteractionIdForPickedFinalPlant) : TargetBush;
    }
    if (!vegetationClass.static.IsPickupInteractionAllowed(interaction, oldState)) { return false; }
    // Use the actual active native/modded table once; never award a fixed fiber
    // amount independently of the bush. Capacity is checked before world mutation.
    items = vegetationClass.static.ChooseYield();
    if (!CanFitYield(items)) { LastReason = "Kevin's cargo is full."; return false; }
    for (i = 0; i < items.Length; i++) {
        item = Spawn(items[i].ItemClass, self);
        if (item == none) {
            for (j = 0; j < prepared.Length; j++) { prepared[j].Destroy(); }
            LastReason = "Could not collect this fiber."; return false;
        }
        item.SetInitialCount(items[i].Count);
        prepared.AddItem(item);
        count += items[i].Count;
    }
    changeState = vegetationClass.static.ShouldPickupChangeStateInsteadOfRemove(interaction, oldState, newState);
    if (changeState) { factory.UpdateVegetationState(slot, newState); }
    else { factory.RemoveVegetation(slot, true); }
    if ((changeState && (newState == oldState || factory.VegetationLootSpawns[slot]._State != newState)) ||
        (!changeState && factory.VegetationLootSpawns[slot].LootType != 0)) {
        for (j = 0; j < prepared.Length; j++) { prepared[j].Destroy(); }
        LastReason = "This fiber is no longer available."; return false;
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
    SearchRadius=1400
    bHidden=true
    bCollideActors=false
    bBlockActors=false
    RemoteRole=ROLE_None
}
