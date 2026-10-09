// Auto-created companion with staged inventory and loss-resistant persistence.
class KevinRegistry extends Actor implements(ColdInterfaceSaveGameState);

var class<KevinCompanionPawn> CompanionPawnClass;
var KevinHunterController Companion;
var ColdHunterPawn CompanionPawn;
var int OwnerPlayerId;
var bool bInitialized;
var bool bCompanionDead;
var bool bTestOnly;
var bool bShuttingDown;
var bool bRestorePending;
var bool bRestoreFailed;
var bool bDormantDisabled;
var JsonObject StoredRecord;
var int ReadinessChecks;
// Schema 2 stores the active-play revival countdown, never a second gear copy.
var bool bDeathPrepared;
var bool bHasDeathLocation;
var bool bRevivalBusy;
var bool bDeathWasFemale;
var bool bDeathHadBeard;
var vector DeathLocation;
var rotator DeathRotation;
var float DeathStartingHealth;
var float RevivalDelay;
var float RevivalSecondsRemaining;
var float RevivalLastTick;
var int DeathGeneration;
var KevinRevivalBag DeathBag;

// The bypass exists only on a registry owned by a live disposable fixture,
// itself owned by an explicitly enabled test-mutator session. Never serialized.
function bool AuthorizeIsolatedFixture(Actor fixture)
{
    if (bInitialized || fixture == none || !fixture.IsA('KevinFriendlyFixture') || fixture != Owner || fixture.bDeleteMe ||
        KevinMutator(fixture.Owner) == none ||
        !KevinMutator(fixture.Owner).IsIsolatedFixtureSession()) { return false; }
    bTestOnly = true;
    return true;
}

function bool IsRuntimeEnabled()
{
    local Actor fixture;
    if (!bTestOnly) { return class'KevinActivation'.static.IsEnabled(); }
    fixture = Owner;
    return fixture != none && fixture.IsA('KevinFriendlyFixture') && !fixture.bDeleteMe && KevinMutator(fixture.Owner) != none &&
        KevinMutator(fixture.Owner).IsIsolatedFixtureSession();
}

function bool HasAnotherRegistry()
{
    local KevinRegistry other;
    foreach DynamicActors(class'KevinRegistry', other) {
        if (other != self && !other.bDeleteMe && other.bInitialized) { return true; }
    }
    return false;
}

function ColdPlayerController FindCompanionOwner()
{
    local ColdPlayerController pc;
    foreach WorldInfo.AllControllers(class'ColdPlayerController', pc) {
        if (pc.PlayerId_Int == OwnerPlayerId && pc.CachedPersistentPlayerStateIdx >= 0 &&
            pc.PlayerId_Int == pc.CachedPersistentPlayerStateIdx && !pc.bDeleteMe) { return pc; }
    }
    return none;
}

function PrepareCompanionDeath(ColdHunterPawn dyingPawn)
{
    local JsonObject appearance;
    if (bShuttingDown || !bInitialized || dyingPawn != CompanionPawn ||
        dyingPawn == none || dyingPawn.Health > 0 || bCompanionDead || bDeathPrepared) { return; }
    bDeathPrepared = true;
    DeathGeneration = Max(1, DeathGeneration + 1);
    DeathLocation = dyingPawn.Location;
    DeathRotation = dyingPawn.Rotation;
    bHasDeathLocation = true;
    DeathStartingHealth = FMax(1.0, dyingPawn.StartingHealth);
    appearance = class'JsonObject'.static.DecodeJson(dyingPawn.Serialize());
    bDeathWasFemale = appearance != none && appearance.GetBoolValue("isF");
    bDeathHadBeard = appearance != none && appearance.GetBoolValue("hb");
    RevivalSecondsRemaining = FMax(1.0, RevivalDelay);
}

function RegisterDeathBag(KevinRevivalBag bag)
{
    if (bag == none || (!bDeathPrepared && !bCompanionDead) || bShuttingDown) { return; }
    DeathBag = bag;
    bag.BindRevivalRegistry(self, DeathGeneration, bTestOnly);
}

function NotifyCompanionDeath(ColdHunterPawn dyingPawn)
{
    local ColdPlayerController pc;
    if (bShuttingDown || dyingPawn == none || dyingPawn != CompanionPawn || dyingPawn.Health > 0) { return; }
    if (bCompanionDead) { return; }
    PrepareCompanionDeath(dyingPawn);
    bDeathPrepared = false;
    bCompanionDead = true;
    bRestorePending = false;
    bRestoreFailed = false;
    StoredRecord = none;
    ClearTimer('RestoreWhenReady');
    StartRevivalCountdown();
    pc = FindCompanionOwner();
    if (pc != none && pc.GetHudMgr() != none) {
        pc.GetHudMgr().Message("Kevin is down: crouch + Use on his bag to revive. Returns in 2 minutes; gear stays behind.");
    }
    LogInternal("KEVIN DEATH RECORDED generation=" $ string(DeathGeneration) $
        " returnSeconds=" $ string(RevivalSecondsRemaining));
}

function CancelPreparedDeath(ColdHunterPawn subject)
{
    if (subject != CompanionPawn || bCompanionDead) { return; }
    bDeathPrepared = false;
    bHasDeathLocation = false;
    DeathBag = none;
}

function StartRevivalCountdown()
{
    if (bShuttingDown || !bCompanionDead || !IsRuntimeEnabled() || bRestoreFailed) { return; }
    RevivalLastTick = WorldInfo.TimeSeconds;
    SetTimer(1.0, true, 'RevivalTick');
}

function int GetRevivalSecondsRemaining()
{
    return Max(0, int(RevivalSecondsRemaining + 0.999));
}

function bool IsRevivalOwnerReady(ColdPlayerController pc)
{
    local ColdGame game;
    game = ColdGame(WorldInfo.Game);
    return Role == ROLE_Authority && WorldInfo.NetMode == NM_Standalone && bInitialized &&
        bCompanionDead && !bShuttingDown && !bRevivalBusy && !bRestoreFailed &&
        IsRuntimeEnabled() && !HasAnotherRegistry() && game != none &&
        !game.bIsLoadingSaveGame && game.LoadingSaveGameState == none && !game.bGameEnding &&
        pc != none && pc == FindCompanionOwner() && pc.GetPlayerPawn() != none &&
        !pc.Pawn.bDeleteMe && pc.Pawn.Health > 0;
}

function bool CanRevive(ColdPlayerController pc)
{
    return IsRevivalOwnerReady(pc) && bHasDeathLocation &&
        VSize(pc.Pawn.Location - DeathLocation) <= 600 &&
        pc.Pawn.FastTrace(DeathLocation, pc.Pawn.Location);
}

function string GetRevivalStatus()
{
    if (!bCompanionDead) { return "Kevin is alive."; }
    if (!IsRuntimeEnabled()) { return "Kevin is disabled; his return is paused."; }
    if (bRestoreFailed) { return "Kevin's saved record needs a compatible update."; }
    if (GetRevivalSecondsRemaining() > 0) {
        return "Revive at Kevin's bag, or he returns in " $ string(GetRevivalSecondsRemaining()) $ " seconds. Gear stays in the bag.";
    }
    return "Kevin returns when you are alive on safe surface ground. His gear stays in the bag.";
}

function bool RequestRevival(ColdPlayerController pc)
{
    if (!CanRevive(pc)) { return false; }
    return TryReviveNear(pc, true);
}

function RevivalTick()
{
    local ColdPlayerController pc;
    local float elapsed;
    if (!bCompanionDead || bShuttingDown) { ClearTimer('RevivalTick'); return; }
    if (!IsRuntimeEnabled()) {
        bDormantDisabled = true;
        ClearTimer('RevivalTick');
        return;
    }
    elapsed = FMax(0.0, WorldInfo.TimeSeconds - RevivalLastTick);
    RevivalLastTick = WorldInfo.TimeSeconds;
    pc = FindCompanionOwner();
    // Offline/loading/dead-owner time never consumes the saved countdown.
    if (!IsRevivalOwnerReady(pc)) { return; }
    RevivalSecondsRemaining = FMax(0.0, RevivalSecondsRemaining - elapsed);
    if (RevivalSecondsRemaining <= 0 && !pc.GetPlayerPawn().IsInCave() &&
        !pc.GetPlayerPawn().IsInLavaCave()) { TryReviveNear(pc, false); }
}

function bool TryReviveNear(ColdPlayerController pc, bool atDeathSpot)
{
    local vector center, candidate;
    local rotator direction;
    local int ring, spoke;
    local bool inCave, inLava;
    if (!IsRevivalOwnerReady(pc) || (atDeathSpot && !CanRevive(pc))) { return false; }
    inCave = pc.GetPlayerPawn().IsInCave();
    inLava = pc.GetPlayerPawn().IsInLavaCave();
    if (!atDeathSpot && (inCave || inLava)) { return false; }
    bRevivalBusy = true;
    center = atDeathSpot ? DeathLocation : pc.Pawn.Location;
    // Bounded ground search plus LOS, vertical and native spawn collision checks.
    // No forced collision bypass and no teleport into an unrelated cave/surface.
    for (ring = 0; ring < 3; ring++) {
        for (spoke = 0; spoke < 8; spoke++) {
            direction.Yaw = pc.Pawn.Rotation.Yaw + spoke * 8192;
            candidate = center + vector(direction) * (180 + ring * 150);
            candidate = class'ColdPositionHelper'.static.GetPathingLocationFromLoc(
                pc.Pawn, candidate, !atDeathSpot, 300, false, false, inCave, inLava);
            if (candidate == vect(0,0,0) || Abs(candidate.Z - center.Z) > 200 ||
                !pc.Pawn.FastTrace(candidate, pc.Pawn.Location)) { continue; }
            if (SpawnRevivedCompanion(pc, candidate)) {
                bRevivalBusy = false;
                return true;
            }
        }
    }
    bRevivalBusy = false;
    return false;
}

private function bool SpawnRevivedCompanion(ColdPlayerController pc, vector atLocation)
{
    local KevinCompanionPawn p;
    local KevinHunterController controller;
    local int i;
    if (!bRevivalBusy || !bCompanionDead || !IsRuntimeEnabled() || HasAnotherRegistry()) { return false; }
    p = Spawn(CompanionPawnClass, self,, atLocation, DeathRotation);
    if (p == none) { return false; }
    controller = KevinHunterController(p.Controller);
    if (p.Controller != none && controller == none) { CleanupSpawnedPawn(p, p.Controller); return false; }
    if (controller == none) {
        controller = KevinHunterController(Spawn(p.ControllerClass, self,, p.Location, p.Rotation));
        if (controller == none) { CleanupSpawnedPawn(p, none); return false; }
        controller.Possess(p, false);
    }
    if (controller.Pawn != p || p.Controller != controller || p.GetPlayerInvMgr() == none ||
        p.GetPlayerInvMgr().GetInvItemCount() != 49) { CleanupSpawnedPawn(p, controller); return false; }
    // Never restore the dead pawn inventory, generate a kit, or touch its bag.
    for (i = 0; i < 49; i++) {
        if (p.GetPlayerInvMgr().GetInvItem(i) != none) { CleanupSpawnedPawn(p, controller); return false; }
    }
    p.SetIsFemale(bDeathWasFemale);
    p.SetHasBeard(bDeathHadBeard);
    if (DeathStartingHealth > 0) { p.StartingHealth = DeathStartingHealth; }
    p.Health = Max(1, int(p.StartingHealth * 0.5));
    if (p.GetClothingManager() != none) { p.SetClothingConfig(p.GetClothingManager().GenerateClothingConfig()); }
    Companion = controller;
    CompanionPawn = p;
    controller.CompanionRegistry = self;
    controller.InitializeCompanion(pc);
    controller.SetFollowing(true);
    bCompanionDead = false;
    bDeathPrepared = false;
    bHasDeathLocation = false;
    bDormantDisabled = false;
    bRestoreFailed = false;
    bRestorePending = false;
    RevivalSecondsRemaining = 0;
    StoredRecord = none;
    DeathBag = none; // The real loot actor and every item remain in the world.
    ClearTimer('RevivalTick');
    if (pc.GetHudMgr() != none) { pc.GetHudMgr().Message("Kevin is back. Recover his equipment from the bag where he fell."); }
    LogInternal("KEVIN REVIVAL COMPLETE generation=" $ string(DeathGeneration) $
        " pawn=" $ string(p) $ " health=" $ string(p.Health) $ " inventoryEmpty=True");
    return true;
}

// The existing pawn is retained. The registry takes ownership BEFORE its exact
// squad slot is removed, preventing the squad from destroying or saving Kevin.
function bool AdoptHunter(ColdHunterController oldController, ColdPlayerController pc)
{
    local ColdHunterSquad squad;
    local KevinHunterController adopted;
    local int memberIndex;
    if (!class'KevinActivation'.static.IsEnabled() || bTestOnly ||
        bInitialized || HasAnotherRegistry() || pc == none || oldController == none ||
        WorldInfo.NetMode != NM_Standalone || oldController.GetHunterPawn() == none ||
        oldController.GetHunterPawn().GetPlayerInvMgr() == none) { return false; }
    squad = oldController.GetHunterPawn().BelongsToSquad;
    if (squad == none || squad.HunterSpawnedCount <= 0) { return false; }
    if (!ValidateInventoryRecord(oldController.GetHunterPawn().GetPlayerInvMgr().Serialize(),
        oldController.GetHunterPawn().GetPlayerInvMgr().GetInvItemCount())) { return false; }
    memberIndex = squad.SquadMembers.Find(oldController);
    if (memberIndex == INDEX_NONE) { return false; }
    adopted = class'KevinBootstrap'.static.AdoptHunter(oldController, pc);
    if (adopted == none) { return false; }
    Companion = adopted;
    CompanionPawn = adopted.GetHunterPawn();
    OwnerPlayerId = pc.PlayerId_Int;
    bInitialized = true;
    adopted.CompanionRegistry = self;
    // AdoptHunter synchronously replaced this exact slot. No world tick occurred.
    squad.SquadMembers.Remove(memberIndex, 1);
    squad.HunterSpawnedCount = Max(0, squad.HunterSpawnedCount - 1);
    CompanionPawn.RemoveFromSquad();
    // Unequip the active weapon actor while retaining all inventory items.
    if (CompanionPawn.GetPlayerInvMgr() != none) {
        CompanionPawn.GetPlayerInvMgr().ClearEquiptToolBeltItem();
    }
    LogInternal("KEVIN REGISTRY ADOPTED pawn=" $ string(CompanionPawn) $
        " owner=" $ string(OwnerPlayerId) $ " formerSquad=" $ string(squad));
    return true;
}

// Production creation is independent of the explicit disposable fixture API.
function bool CreateCompanion(ColdPlayerController pc, vector atLocation)
{
    if (!class'KevinActivation'.static.IsEnabled() || bTestOnly) { return false; }
    return CreateNewCompanion(pc, atLocation, false);
}

function bool CreateFriendlyFixture(ColdPlayerController pc, vector atLocation)
{
    if (!bTestOnly || !IsRuntimeEnabled()) { return false; }
    return CreateNewCompanion(pc, atLocation, true);
}

private function bool CreateNewCompanion(ColdPlayerController pc, vector atLocation, bool testOnly)
{
    local KevinCompanionPawn p;
    local KevinHunterController controller;
    if (testOnly != bTestOnly || !IsRuntimeEnabled() ||
        bInitialized || HasAnotherRegistry() || pc == none || pc.Pawn == none || pc.Pawn.Health <= 0 ||
        WorldInfo.NetMode != NM_Standalone) { return false; }
    p = Spawn(CompanionPawnClass, self,, atLocation);
    if (p == none) { return false; }
    controller = KevinHunterController(p.Controller);
    if (p.Controller != none && controller == none) { CleanupSpawnedPawn(p, p.Controller); return false; }
    if (controller == none) {
        controller = KevinHunterController(Spawn(p.ControllerClass, self,, p.Location, p.Rotation));
        if (controller == none) { p.Destroy(); return false; }
        controller.Possess(p, false);
    }
    if (controller.Pawn != p || p.Controller != controller) {
        controller.UnPossess(); controller.Destroy(); p.Destroy(); return false;
    }
    if (p.GetPlayerInvMgr() == none || p.GetPlayerInvMgr().GetInvItemCount() != 49) {
        CleanupSpawnedPawn(p, controller); return false;
    }
    controller.InitializeCompanion(pc);
    p.SetKitProfileType(class'ColdHunterKitProfiles'.const.HunterKitProfile_Default);
    class'ColdHunterKitProfiles'.static.AddKitLoadout(p, 6.1, true); // Clothing only, no weapons.
    if (p.GetPlayerInvMgr().GetInvItem(44) == none || p.GetPlayerInvMgr().GetInvItem(45) == none ||
        p.GetPlayerInvMgr().GetInvItem(46) == none) {
        CleanupSpawnedPawn(p, controller); return false;
    }
    Companion = controller;
    CompanionPawn = p;
    OwnerPlayerId = pc.PlayerId_Int;
    bInitialized = true;
    bTestOnly = testOnly;
    controller.CompanionRegistry = self;
    if (!testOnly) { controller.SetFollowing(true); }
    LogInternal((testOnly ? "KEVIN FRIENDLY FIXTURE CREATED pawn=" : "KEVIN COMPANION CREATED pawn=") $ string(p));
    return true;
}

function bool ShouldMasterSaveStateHandleSave()
{
    return bInitialized && !bTestOnly && !bShuttingDown;
}

function string Serialize()
{
    local JsonObject record, inventory;
    if (!bInitialized) { return ""; }
    // Dormant/failed/deferred records retain all data, even unknown future fields.
    if ((bDormantDisabled || bRestorePending || bRestoreFailed) && StoredRecord != none) {
        StoredRecord.SetStringValue("Name", PathName(self));
        return class'JsonObject'.static.EncodeJson(StoredRecord);
    }
    record = new class'JsonObject';
    record.SetStringValue("Name", PathName(self));
    record.SetStringValue("ObjectArchetype", PathName(ObjectArchetype));
    record.SetIntValue("KevinSchema", 2);
    record.SetIntValue("OwnerPlayerId", OwnerPlayerId);
    record.SetIntValue("DeathGeneration", DeathGeneration);
    record.SetBoolValue("Dead", bCompanionDead || CompanionPawn == none || CompanionPawn.Health <= 0);
    if (bCompanionDead) {
        record.SetIntValue("KevinRevivalVersion", 1);
        record.SetBoolValue("DeathHasLocation", bHasDeathLocation);
        if (bHasDeathLocation) {
            class'KevinJson'.static.SetPosition(record, "DeathLocation", DeathLocation);
            class'KevinJson'.static.SetRotation(record, "DeathRotation", DeathRotation);
        }
        record.SetFloatValue("RevivalRemaining", FMax(0.0, RevivalSecondsRemaining));
        record.SetFloatValue("DeathStartingHealth", DeathStartingHealth);
        record.SetBoolValue("DeathWasFemale", bDeathWasFemale);
        record.SetBoolValue("DeathHadBeard", bDeathHadBeard);
    }
    if (!bCompanionDead && CompanionPawn != none && CompanionPawn.Health > 0) {
        record.SetObject("Pawn", class'JsonObject'.static.DecodeJson(CompanionPawn.Serialize()));
        class'KevinJson'.static.SetPosition(record, "Location", CompanionPawn.Location);
        class'KevinJson'.static.SetRotation(record, "Rotation", CompanionPawn.Rotation);
        record.SetIntValue("Health", CompanionPawn.Health);
        record.SetFloatValue("StartingHealth", CompanionPawn.StartingHealth);
        if (KevinCompanionPawn(CompanionPawn) != none &&
            KevinCompanionPawn(CompanionPawn).KevinInventory != none &&
            KevinCompanionPawn(CompanionPawn).KevinInventory.bStaged) {
            record.SetBoolValue("Following", KevinCompanionPawn(CompanionPawn).KevinInventory.bResumeFollowing);
        } else { record.SetBoolValue("Following", Companion != none && Companion.bFollowing); }
        if (CompanionPawn.GetPlayerInvMgr() != none) {
            if (KevinCompanionPawn(CompanionPawn) != none) {
                inventory = KevinCompanionPawn(CompanionPawn).SnapshotKevinInventory();
                if (KevinCompanionPawn(CompanionPawn).bKevinInventoryCommitFailed) {
                    record.SetBoolValue("KevinInventoryCommitFailed", true);
                    record.SetObject("KevinUncommittedPawnInventory", CompanionPawn.GetPlayerInvMgr().Serialize());
                }
            } else { inventory = CompanionPawn.GetPlayerInvMgr().Serialize(); }
            record.SetObject("Inventory", inventory);
            record.SetIntValue("InventorySlots", CompanionPawn.GetPlayerInvMgr().GetInvItemCount());
        }
    }
    return class'JsonObject'.static.EncodeJson(record);
}

function Deserialize(JsonObject data)
{
    if (bInitialized || data == none || WorldInfo.NetMode != NM_Standalone) { return; }
    // Preserve unsupported records without spawning or silently overwriting them.
    StoredRecord = data;
    bInitialized = true;
    // Save compatibility runs even when the gameplay loader is absent/disabled.
    // Decide activation before reading/changing any record-specific values.
    if (!IsRuntimeEnabled()) {
        bDormantDisabled = true;
        LogInternal("KEVIN SAVE DORMANT native mod inactive; full data retained without spawning");
        return;
    }
    if ((data.GetIntValue("KevinSchema") != 1 && data.GetIntValue("KevinSchema") != 2) ||
        data.GetBoolValue("KevinInventoryCommitFailed")) {
        bRestoreFailed = true;
        LogInternal("KEVIN RESTORE REFUSED unsupported schema or unresolved inventory; full data retained");
        return;
    }
    OwnerPlayerId = data.GetIntValue("OwnerPlayerId");
    DeathGeneration = Max(0, data.GetIntValue("DeathGeneration"));
    bCompanionDead = data.GetBoolValue("Dead");
    if (HasAnotherRegistry()) {
        bRestoreFailed = true;
        LogInternal("KEVIN RESTORE REFUSED duplicate registry");
        return;
    }
    if (bCompanionDead) {
        if (data.GetIntValue("KevinSchema") == 2 && data.GetIntValue("KevinRevivalVersion") != 1) {
            bRestoreFailed = true;
            LogInternal("KEVIN REVIVAL REFUSED unsupported saved revival version; full data retained");
            return;
        }
        if (data.GetIntValue("KevinSchema") == 1) {
            // Original dead records have no body/position/inventory. A fresh
            // delayed, empty return migrates them without inventing old loot.
            RevivalSecondsRemaining = FMax(1.0, RevivalDelay);
            DeathGeneration = Max(1, DeathGeneration);
        } else {
            bHasDeathLocation = data.GetBoolValue("DeathHasLocation");
            DeathLocation = class'KevinJson'.static.GetPosition(data, "DeathLocation");
            DeathRotation = class'KevinJson'.static.GetRotation(data, "DeathRotation");
            RevivalSecondsRemaining = FClamp(data.GetFloatValue("RevivalRemaining"), 0.0, FMax(1.0, RevivalDelay));
            DeathStartingHealth = data.GetFloatValue("DeathStartingHealth");
            bDeathWasFemale = data.GetBoolValue("DeathWasFemale");
            bDeathHadBeard = data.GetBoolValue("DeathHadBeard");
        }
        StoredRecord = none;
        StartRevivalCountdown();
        return;
    }
    bRestorePending = true;
    SetTimer(0.5, true, 'RestoreWhenReady');
}

function bool ValidateInventoryRecord(JsonObject inventory, int slots)
{
    local int i, itemId;
    local JsonObject itemRecord;
    if (inventory == none || slots <= 0 || slots > 49) { return false; }
    // The native 48-slot UI reserves human belt slot42. Retain an incompatible
    // complete record instead of spawning a companion with an inaccessible item.
    if (inventory.GetObject("42") != none) { return false; }
    for (i = 0; i < slots; i++) {
        itemRecord = inventory.GetObject(string(i));
        if (itemRecord == none) { continue; }
        // Container-within-item restoration needs its own bounded validation.
        // Ordinary hunter kits have no nested item storage; retain rather than lose
        // an unsupported saved record if one is introduced by another mod later.
        if (itemRecord.GetObject("si") != none) { return false; }
        itemId = itemRecord.GetIntValue("~");
        if (itemId < 0 || itemId >= class'ColdInvItemList'.default.ItemList.Length ||
            class'ColdInvItemList'.default.ItemList[itemId] == none ||
            itemRecord.GetIntValue("c") - itemId <= 0) { return false; }
    }
    return true;
}

// ColdInventoryManager.Deserialize refuses hunter owners. This uses its actual
// item reconstruction calls, all of which explicitly accept a Pawn/Human owner.
function bool RestoreInventory(ColdHunterPawn p, JsonObject inventory, int slots)
{
    local ColdPlayerInvManager manager;
    local ColdInventoryItem item;
    local JsonObject itemRecord;
    local class<ColdInventoryItem> itemClass;
    local int i;
    manager = p.GetPlayerInvMgr();
    if (manager == none || manager.GetInvItemCount() != slots ||
        !ValidateInventoryRecord(inventory, slots)) { return false; }
    // Fresh restore pawns should have no kit; refuse to overwrite unexpected items.
    for (i = 0; i < slots; i++) {
        if (manager.GetInvItem(i) != none) { return false; }
    }
    for (i = 0; i < slots; i++) {
        itemRecord = inventory.GetObject(string(i));
        if (itemRecord == none) { continue; }
        itemClass = class'ColdInvItemList'.default.ItemList[itemRecord.GetIntValue("~")];
        item = Spawn(itemClass);
        if (item == none) { return false; }
        item.GiveTo(p);
        item.Deserialize(itemRecord, 1);
        manager.AddItemToInvArray(item, class'ColdInventoryItemUtils'.static.MakeInvSlotInfo(i));
        if (manager.GetInvItem(i) != item || item.Owner != p) { item.Destroy(); return false; }
    }
    return true;
}

function CleanupSpawnedPawn(ColdHunterPawn p, Controller spawnedController)
{
    local int i;
    local ColdInventoryItem item;
    if (KevinCompanionPawn(p) != none) { KevinCompanionPawn(p).CloseKevinInventory(); }
    if (spawnedController != none) {
        if (KevinHunterController(spawnedController) != none) {
            KevinHunterController(spawnedController).CompanionRegistry = none;
        }
        spawnedController.UnPossess();
        spawnedController.Destroy();
    }
    if (p != none) {
        if (p.GetPlayerInvMgr() != none) {
            for (i = 0; i < p.GetPlayerInvMgr().GetInvItemCount(); i++) {
                item = p.GetPlayerInvMgr().GetInvItem(i);
                if (item != none && item.Owner == p) { item.Destroy(); }
            }
        }
        p.Destroy();
    }
}

function RestoreWhenReady()
{
    local ColdGame game;
    local ColdPlayerController pc;
    local KevinCompanionPawn p;
    local KevinHunterController controller;
    local int health;
    if (!bRestorePending || StoredRecord == none || bShuttingDown) { ClearTimer('RestoreWhenReady'); return; }
    if (!IsRuntimeEnabled()) {
        bRestorePending = false;
        bDormantDisabled = true;
        ClearTimer('RestoreWhenReady');
        LogInternal("KEVIN RESTORE DORMANT native mod inactive; full data retained");
        return;
    }
    game = ColdGame(WorldInfo.Game);
    pc = FindCompanionOwner();
    ReadinessChecks++;
    if (game == none || game.LoadingSaveGameState != none || pc == none || pc.Pawn == none) {
        if (ReadinessChecks >= 240) {
            bRestorePending = false; bRestoreFailed = true; ClearTimer('RestoreWhenReady');
            LogInternal("KEVIN RESTORE DEFERRED data retained; world/owner never became ready");
        }
        return;
    }
    ClearTimer('RestoreWhenReady');
    bRestorePending = false;
    bRestoreFailed = true; // Remains true until the entire reconstruction succeeds.
    health = StoredRecord.GetIntValue("Health");
    if (HasAnotherRegistry() || health <= 0 || StoredRecord.GetFloatValue("StartingHealth") <= 0 ||
        StoredRecord.GetObject("Pawn") == none ||
        !ValidateInventoryRecord(StoredRecord.GetObject("Inventory"), StoredRecord.GetIntValue("InventorySlots"))) {
        LogInternal("KEVIN RESTORE REFUSED invalid or duplicate record; data retained"); return;
    }
    // Spawn uses collision checks. Never force through geometry or silently relocate.
    p = Spawn(CompanionPawnClass, self,, class'KevinJson'.static.GetPosition(StoredRecord, "Location"),
        class'KevinJson'.static.GetRotation(StoredRecord, "Rotation"));
    if (p == none) { LogInternal("KEVIN RESTORE BLOCKED spawn collision; data retained"); return; }
    controller = KevinHunterController(p.Controller);
    if (p.Controller != none && controller == none) { CleanupSpawnedPawn(p, p.Controller); return; }
    if (controller == none) {
        controller = KevinHunterController(Spawn(p.ControllerClass, self,, p.Location, p.Rotation));
        if (controller == none) { CleanupSpawnedPawn(p, none); return; }
        controller.Possess(p, false);
    }
    if (controller.Pawn != p || p.Controller != controller) { CleanupSpawnedPawn(p, controller); return; }
    p.Deserialize(StoredRecord.GetObject("Pawn"));
    p.SetHasBeard(StoredRecord.GetObject("Pawn").GetBoolValue("hb"));
    p.SetIsFemale(StoredRecord.GetObject("Pawn").GetBoolValue("isF"));
    p.StartingHealth = StoredRecord.GetFloatValue("StartingHealth");
    p.Health = health;
    if (!RestoreInventory(p, StoredRecord.GetObject("Inventory"), StoredRecord.GetIntValue("InventorySlots"))) {
        CleanupSpawnedPawn(p, controller);
        LogInternal("KEVIN RESTORE BLOCKED inventory reconstruction; data retained"); return;
    }
    Companion = controller;
    CompanionPawn = p;
    controller.CompanionRegistry = self;
    controller.InitializeCompanion(pc);
    controller.SetFollowing(StoredRecord.GetBoolValue("Following"));
    bRestoreFailed = false;
    StoredRecord = none;
    LogInternal("KEVIN RESTORE COMPLETE pawn=" $ string(p) $ " health=" $ string(p.Health));
}

function NotifyControllerDestroyed(KevinHunterController controller)
{
    if (bShuttingDown || controller != Companion) { return; }
    if (CompanionPawn != none && CompanionPawn.Health <= 0) { NotifyCompanionDeath(CompanionPawn); }
    Companion = none;
}

simulated function Destroyed()
{
    bShuttingDown = true;
    ClearTimer('RestoreWhenReady');
    ClearTimer('RevivalTick');
    CleanupSpawnedPawn(CompanionPawn, Companion);
    CompanionPawn = none;
    Companion = none;
    StoredRecord = none;
    super.Destroyed();
}

defaultproperties
{
    CompanionPawnClass=class'KevinCompanionPawn'
    bHidden=true
    bCollideActors=false
    bBlockActors=false
    RemoteRole=ROLE_None
    RevivalDelay=120.0
}

