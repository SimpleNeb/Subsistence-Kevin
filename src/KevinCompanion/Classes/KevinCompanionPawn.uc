// Friendly hunter body with native inventory and crouch-plus-Use orders.
class KevinCompanionPawn extends ColdHunterPawn dependson(_ColdStructs)
    implements(ColdInterfaceAccessible, ColdInterfaceInteractable);

var KevinAccessModule KevinInventory;
var bool bKevinInventoryOpen;
var bool bKevinInventoryCommitFailed;
var bool bKevinPromptInitialized;
var bool bKevinPromptCrouched;
var bool bKevinPromptFollowing;
var KevinCommandMenu KevinOrdersMenu;
var bool bKevinOpeningInventory;
var KevinRegistry KevinDeathRegistry;

simulated function bool IsKevinOwnerInReach(ColdPlayerController pc)
{
    local KevinHunterController c;
    c = KevinHunterController(Controller);
    return WorldInfo.NetMode == NM_Standalone && Health > 0 && !bDeleteMe && c != none &&
        pc != none && c.CompanionOwner == pc && pc.Pawn != none && pc.Pawn.Health > 0 &&
        VSize(Location - pc.Pawn.Location) <= 350;
}

simulated function bool IsKevinOrderGesture(ColdPlayerController pc)
{
    return !bKevinOpeningInventory && IsKevinOwnerInReach(pc) && pc.Pawn.bIsCrouched && !IsKevinInventoryBusy() &&
        ColdPlayerPawn(pc.Pawn) != none && !ColdPlayerPawn(pc.Pawn).bInHud;
}

simulated function bool IsKevinInventoryBusy()
{
    return bKevinInventoryOpen || bKevinInventoryCommitFailed;
}

// Keep the last fully committed clothing meshes while the real items are in
// the access module. Metadata still follows the actual pawn inventory, so a
// save made during access cannot carry a stale outfit into reconstruction.
// Successful commit rebuilds visuals from the actual returned items once.
function SetClothingConfig(ClothingConfigStruct newConfig)
{
    if (bKevinInventoryOpen) {
        Appearance.ClothingConfig = newConfig;
        return;
    }
    super.SetClothingConfig(newConfig);
}

function SpawnAccessModule()
{
    if (WorldInfo.NetMode == NM_Standalone && KevinInventory == none && !bDeleteMe) {
        KevinInventory = Spawn(class'KevinAccessModule', self);
    }
}

simulated function ColdAccessModule GetAccessModule()
{
    if (KevinInventory == none) { SpawnAccessModule(); }
    return KevinInventory;
}

simulated function bool IsBeingAccessed() { return bKevinInventoryOpen; }
simulated function SetIsBeingAccessed(bool value) { bKevinInventoryOpen = value; }

simulated function bool IsAccessible(optional ColdPlayerController pcAccessing,
    optional out string cantAccessReason)
{
    cantAccessReason = "";
    if (pcAccessing == none) { pcAccessing = ColdPlayerController(GetALocalPlayerController()); }
    if (!IsKevinOwnerInReach(pcAccessing)) { return false; }
    // Native Use checks Accessible before Interactable. A blank refusal while
    // crouched lets the same bound Use action reach the order interface below.
    if (IsKevinOrderGesture(pcAccessing)) { return false; }
    if (bKevinInventoryCommitFailed) {
        cantAccessReason = "Kevin's inventory is waiting to close safely."; return false;
    }
    if (GetPlayerInvMgr() != none && GetPlayerInvMgr().GetInvItem(42) != none) {
        cantAccessReason = "Kevin has an unsupported item in his reserved slot; all items are retained.";
        return false;
    }
    return true;
}

function NotifyPlayerReleasedAccessModule() {}
simulated function LinkClientRefToAccessModule(ColdAccessModule am) { KevinInventory = KevinAccessModule(am); }
simulated function ClearClientRefToAccessModule() {}

simulated function GetActionIconData(out string actionIcon, out string actionText,
    out InputGlyphData inputGlyph, out InputPromptImageData promptImg)
{
    local ColdPlayerController pc;
    pc = ColdPlayerController(GetALocalPlayerController());
    actionIcon = "img://ColdHudImageLibrary.ActionIcon_Inventory";
    actionText = GetToggleText();
    if (pc != none && pc.GetPlayerInput() != none && pc.GetPlayerInput().InputGlyphs != none) {
        inputGlyph = pc.GetPlayerInput().InputGlyphs.GetGlyph_Use();
    }
}

simulated function string GetActionIconImage()
{
    return "img://ColdHudImageLibrary.ActionIcon_Inventory";
}

simulated function string GetToggleText()
{
    local KevinHunterController c;
    local ColdPlayerController pc;
    c = KevinHunterController(Controller);
    pc = ColdPlayerController(GetALocalPlayerController());
    if (IsKevinOrderGesture(pc) && c != none) {
        return "Kevin: commands (stand for inventory)";
    }
    return "Kevin's inventory (crouch for commands)";
}

simulated function NotifyPlayerLookingAt(vector hitLoc, TraceHitInfo hitInfo) {}

simulated function byte GetInteractionCommandId()
{
    return IsKevinOrderGesture(ColdPlayerController(GetALocalPlayerController())) ? 1 : 0;
}

simulated function bool CanClientInteract(ColdPlayerPawn actingPawn, byte interactionCmdId)
{
    return interactionCmdId == 1 && actingPawn != none &&
        IsKevinOrderGesture(ColdPlayerController(actingPawn.Controller));
}

simulated function bool PreAskServerToInteract(byte interactionCmdId, ColdPlayerController interactingPlayer)
{
    return interactingPlayer != none &&
        CanClientInteract(ColdPlayerPawn(interactingPlayer.Pawn), interactionCmdId);
}

function InteractWithItem(ColdPlayerPawn actingPawn, byte interactionCmdId)
{
    local ColdPlayerController pc;
    if (Role != ROLE_Authority || !CanClientInteract(actingPawn, interactionCmdId)) { return; }
    pc = ColdPlayerController(actingPawn.Controller);
    class'KevinCommandMenu'.static.OpenFor(self, pc);
}

simulated function bool HasChangedSinceLastTick()
{
    local ColdPlayerController pc;
    local KevinHunterController c;
    local bool crouched, following, changed;
    pc = ColdPlayerController(GetALocalPlayerController());
    c = KevinHunterController(Controller);
    crouched = pc != none && pc.Pawn != none && pc.Pawn.bIsCrouched;
    following = c != none && c.GetFollowingOrder();
    changed = !bKevinPromptInitialized || crouched != bKevinPromptCrouched || following != bKevinPromptFollowing;
    bKevinPromptInitialized = true;
    bKevinPromptCrouched = crouched;
    bKevinPromptFollowing = following;
    return changed;
}

function CloseKevinInventory()
{
    if (KevinInventory != none) { KevinInventory.CloseInventoryAccess(); }
}

function JsonObject SnapshotKevinInventory()
{
    if (KevinInventory != none && KevinInventory.bStaged) { return KevinInventory.SnapshotInventory(); }
    if (GetPlayerInvMgr() != none) { return GetPlayerInvMgr().Serialize(); }
    return none;
}

// Damage ends the inventory transaction before armor/weapon calculations run.
event TakeDamage(int Damage, Controller InstigatedBy, vector HitLocation,
    vector Momentum, class<DamageType> DamageType, optional TraceHitInfo HitInfo,
    optional Actor DamageCauser)
{
    if (KevinOrdersMenu != none) { KevinOrdersMenu.CloseMenu(); }
    CloseKevinInventory();
    super.TakeDamage(Damage, InstigatedBy, HitLocation, Momentum, DamageType, HitInfo, DamageCauser);
}

function bool Died(Controller Killer, class<DamageType> DamageType, vector HitLocation)
{
    local bool diedNormally;
    if (KevinOrdersMenu != none) { KevinOrdersMenu.CloseMenu(); }
    CloseKevinInventory();
    if (Role == ROLE_Authority && Health <= 0 && KevinHunterController(Controller) != none) {
        KevinDeathRegistry = KevinHunterController(Controller).CompanionRegistry;
        if (KevinDeathRegistry != none) { KevinDeathRegistry.PrepareCompanionDeath(self); }
    }
    diedNormally = super.Died(Killer, DamageType, HitLocation);
    if (KevinDeathRegistry != none) {
        if (diedNormally && Health <= 0) { KevinDeathRegistry.NotifyCompanionDeath(self); }
        else { KevinDeathRegistry.CancelPreparedDeath(self); }
    }
    return diedNormally;
}

// Stock hunter death synthesizes a random loot kit. Kevin drops the exact carried
// items through the native gear container instead, preserving identity and count.
function FillDroppedGear(ColdLootContainer droppedGear)
{
    local ColdInventoryItem item;
    local ColdPlayerInvManager manager;
    local int i, dropSlot;
    CloseKevinInventory();
    manager = GetPlayerInvMgr();
    if (droppedGear == none || droppedGear.AM == none || manager == none) {
        LogInternal("KEVIN GEAR DROP FAILED missing container or manager"); return;
    }
    if (KevinDeathRegistry != none && KevinRevivalBag(droppedGear) != none) {
        KevinDeathRegistry.RegisterDeathBag(KevinRevivalBag(droppedGear));
    }
    droppedGear.AM.SetInvSize(48);
    for (i = 0; i < 49; i++) {
        dropSlot = class'KevinAccessModule'.static.AccessSlotForPawnSlot(i);
        if (dropSlot < 0) { continue; }
        item = manager.GetInvItem(i);
        if (item == none) { continue; }
        manager.AddItemToInvArray(none, class'ColdInventoryItemUtils'.static.MakeInvSlotInfo(i));
        droppedGear.AM.AddInvItem(item, dropSlot);
    }
    // A failed commit retains items in the module; transfer those too only into
    // empty death-container slots, never overwrite a conflicting destination.
    if (KevinInventory != none && KevinInventory.bStaged) {
        for (i = 0; i < KevinInventory.Items.Length; i++) {
            item = KevinInventory.Items[i];
            if (item == none || droppedGear.AM.GetInvItem(i) != none) { continue; }
            KevinInventory.Items[i] = none;
            droppedGear.AM.AddInvItem(item, i);
        }
    }
    // An external mod could still place an item in the reserved human slot.
    // The native helper puts it in a free gear slot or drops that exact item
    // into the world if the bag is full; never hide it outside the 48-slot UI.
    item = manager.GetInvItem(42);
    if (item != none) {
        manager.AddItemToInvArray(none, class'ColdInventoryItemUtils'.static.MakeInvSlotInfo(42));
        droppedGear.AM.AddItemToInventory(item);
    }
}

simulated function Destroyed()
{
    if (KevinOrdersMenu != none) { KevinOrdersMenu.CloseMenu(); }
    CloseKevinInventory();
    if (KevinInventory != none) { KevinInventory.Destroy(); }
    KevinInventory = none;
    super.Destroyed();
}

function bool BotFire(bool bFinished)
{
    StopFiring();
    return false;
}

defaultproperties
{
    ControllerClass=class'KevinHunterController'
    DroppedGearClass=class'KevinRevivalBag'
    bNoWeaponFiring=true
}

