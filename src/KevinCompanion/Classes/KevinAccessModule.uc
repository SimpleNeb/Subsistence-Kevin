// Native inventory transaction with a supported 48-slot user interface.
// Same item actors move to this module only while the owner is using the UI.
class KevinAccessModule extends ColdAccessModule dependson(_ColdStructs);

var bool bStaged;
var bool bClosing;
var bool bCommitting;
var bool bResumeFollowing;

simulated function PreBeginPlay()
{
    // Apply inherited zero-valued overrides before ColdAccessModule sizes its
    // inventory and before its PostBeginPlay can create a crafting manager.
    InvSize = 48;
    CanShiftClickIn = false;
    HasCraftMgr = false;
    RemoteRole = ROLE_None;
    SetTickIsDisabled(false);
    super.PreBeginPlay();
}

function KevinCompanionPawn KevinPawn()
{
    return KevinCompanionPawn(OriginalOwner);
}

// Native Flash provides a 48-slot view, but the human inventory/save has 49.
// Reserve the eighth belt slot (pawn42); expose every clothing slot instead.
static function int PawnSlotForAccessSlot(int slotId)
{
    return slotId < 42 ? slotId : slotId + 1;
}

static function int AccessSlotForPawnSlot(int slotId)
{
    if (slotId == 42 || slotId < 0 || slotId >= 49) { return -1; }
    return slotId < 42 ? slotId : slotId - 1;
}

function bool StageInventory()
{
    local KevinCompanionPawn p;
    local KevinHunterController c;
    local ColdPlayerInvManager manager;
    local ColdInventoryItem item;
    local int i, j, pawnSlot;
    p = KevinPawn();
    if (p == none || p.Health <= 0 || p.IsKevinInventoryBusy()) { return false; }
    manager = p.GetPlayerInvMgr();
    if (manager == none || manager.GetInvItemCount() != 49 || GetItemCount() != 0) { return false; }
    if (manager.GetInvItem(42) != none) {
        LogInternal("KEVIN INVENTORY OPEN REFUSED occupied reserved pawn slot42; all items retained");
        return false;
    }
    // Validate the entire ownership set before any item is moved.
    for (i = 0; i < 49; i++) {
        item = manager.GetInvItem(i);
        if (item != none && (item.bDeleteMe || item.Owner != p)) { return false; }
        if (item != none) {
            for (j = 0; j < i; j++) { if (manager.GetInvItem(j) == item) { return false; } }
        }
    }
    c = KevinHunterController(p.Controller);
    bResumeFollowing = c != none && c.bFollowing;
    if (c != none) { c.SetFollowing(false); }
    p.StopFiring();
    manager.ClearEquiptToolBeltItem();
    p.bKevinInventoryOpen = true;
    bStaged = true;
    for (i = 0; i < 48; i++) {
        pawnSlot = PawnSlotForAccessSlot(i);
        item = manager.GetInvItem(pawnSlot);
        if (item == none) { continue; }
        manager.AddItemToInvArray(none, class'ColdInventoryItemUtils'.static.MakeInvSlotInfo(pawnSlot));
        super.AddInvItem(item, i);
    }
    SetTimer(0.5, true, 'VerifyAccess');
    LogInternal("KEVIN INVENTORY OPEN staged=" $ string(GetItemCount()));
    return true;
}

function bool CommitInventory()
{
    local KevinCompanionPawn p;
    local KevinHunterController c;
    local ColdPlayerInvManager manager;
    local ColdInventoryItem item;
    local int i;
    if (!bStaged) { return true; }
    if (bCommitting) { return false; }
    p = KevinPawn();
    if (p == none || p.GetPlayerInvMgr() == none) { return false; }
    manager = p.GetPlayerInvMgr();
    if (manager.GetInvItemCount() != 49 || Items.Length != 48) {
        p.bKevinInventoryCommitFailed = true; return false;
    }
    // No partial overwrite: a foreign item in a destination retains the AM data.
    for (i = 0; i < 49; i++) {
        if (manager.GetInvItem(i) != none) {
            p.bKevinInventoryCommitFailed = true;
            LogInternal("KEVIN INVENTORY COMMIT BLOCKED occupied pawn slot=" $ string(i));
            return false;
        }
    }
    bCommitting = true;
    // All destinations are empty. Functions run synchronously without a world tick.
    for (i = 0; i < Items.Length; i++) {
        item = Items[i];
        Items[i] = none;
        if (item == none || item.bDeleteMe) { continue; }
        manager.AddItemToInvArray(item, class'ColdInventoryItemUtils'.static.MakeInvSlotInfo(PawnSlotForAccessSlot(i)));
    }
    bCommitting = false;
    bStaged = false;
    p.bKevinInventoryOpen = false;
    p.bKevinInventoryCommitFailed = false;
    if (p.GetClothingManager() != none) {
        p.SetClothingConfig(p.GetClothingManager().GenerateClothingConfig());
    }
    ClearTimer('VerifyAccess');
    c = KevinHunterController(p.Controller);
    if (c != none && !p.bDeleteMe && p.Health > 0) { c.SetFollowing(bResumeFollowing); }
    LogInternal("KEVIN INVENTORY CLOSED committed");
    return true;
}

function InternalTakeOwnershipOfAssets(Actor p)
{
    local ColdPlayerPawn player;
    local KevinCompanionPawn companion;
    companion = KevinPawn();
    if (p != none && p != OriginalOwner) {
        player = ColdPlayerPawn(p);
        if (player == none || companion == none ||
            !companion.IsAccessible(ColdPlayerController(player.Controller)) || !StageInventory()) {
            if (player != none && player.GetPlayerInvMgr() != none &&
                player.GetPlayerInvMgr().ExternalInv == self) { player.GetPlayerInvMgr().ExternalInv = none; }
            SetOwner(OriginalOwner);
            LogInternal("KEVIN INVENTORY OPEN REFUSED");
            return;
        }
    }
    super.InternalTakeOwnershipOfAssets(p);
    if (p == none || p == OriginalOwner) { CommitInventory(); }
}

function CloseInventoryAccess()
{
    local ColdPlayerInvManager manager;
    if (bClosing) { return; }
    bClosing = true;
    manager = GetPlayerInvMgr();
    KickOutAccessingPlayer();
    if (manager != none && manager.ExternalInv == self) { manager.ReleaseExternalAccessModule(); }
    if (Owner != OriginalOwner) { InternalTakeOwnershipOfAssets(none); }
    else { CommitInventory(); }
    bClosing = false;
}

function VerifyAccess()
{
    local KevinCompanionPawn p;
    local ColdPlayerController pc;
    p = KevinPawn();
    pc = GetAccessingPlayerPc();
    if (!bStaged) { ClearTimer('VerifyAccess'); return; }
    if (p == none || p.bDeleteMe || p.Health <= 0 || pc == none || pc.bDeleteMe ||
        pc.Pawn == none || pc.Pawn.Health <= 0 || GetPlayerInvMgr() == none ||
        GetPlayerInvMgr().ExternalInv != self || VSize(p.Location - pc.Pawn.Location) > 450) {
        CloseInventoryAccess();
    }
}

// Reject unsupported nested inventories before taking possession of the item.
// Keep normal slot restrictions and prevent two worn items of the same category.
simulated function bool CheckCanMoveItemToSlot(ColdInventoryItem item, byte slotId, byte invType)
{
    local KevinCompanionPawn p;
    local ColdInventoryItem_Clothing clothing, other;
    local int i;
    p = KevinCompanionPawn(OriginalOwner);
    if (!bStaged || bCommitting || p == none || p.GetPlayerInvMgr() == none ||
        slotId >= 48 || item == none || item.bDeleteMe ||
        ColdInterfaceInventoryItemStorage(item) != none) { return false; }
    if (!p.GetPlayerInvMgr().CheckCanMoveItemToSlot(item,
        class'ColdInventoryItemUtils'.static.MakeInvSlotInfo(PawnSlotForAccessSlot(slotId)))) { return false; }
    if (p.GetPlayerInvMgr().IsClothingSlot(PawnSlotForAccessSlot(slotId))) {
        clothing = ColdInventoryItem_Clothing(item);
        if (clothing == none || clothing.IsBroken()) { return false; }
        for (i = 42; i < 48; i++) {
            other = ColdInventoryItem_Clothing(Items[i]);
            if (i != slotId && other != none && other != clothing &&
                other.ClothingType == clothing.ClothingType) { return false; }
        }
    }
    return true;
}

// The stock shift-in loop bypasses per-slot restrictions. Require drag/drop in.
function bool IsItemPermittedForShiftClickIn(ColdInventoryItem item) { return false; }

// Inventory snapshots also work while access is open. The registry uses this
// record instead of the temporarily empty pawn manager, never both inventories.
function JsonObject SnapshotInventory()
{
    local JsonObject result;
    local int i;
    result = new class'JsonObject';
    for (i = 0; i < Items.Length; i++) {
        if (Items[i] != none && !Items[i].bDeleteMe) {
            result.SetObject(string(PawnSlotForAccessSlot(i)), Items[i].Serialize());
        }
    }
    return result;
}

simulated function OpenAccessModuleHud()
{
    local LootContainerDetails details;
    if (!bStaged || GetHudMgr() == none || GetHudMgr().ExternalInvWrapper == none) { return; }
    details.PreviewName = "Kevin - 35 cargo / 7 toolbelt / 6 clothing";
    GetHudMgr().ExternalInvWrapper.InitializeView_LootStorage(48, details);
    super.OpenAccessModuleHud();
}

simulated function Destroyed()
{
    ClearTimer('VerifyAccess');
    CloseInventoryAccess();
    // Successfully returned items are no longer referenced in Items. If the pawn
    // is already unavailable, the base destructor owns the still-staged items.
    super.Destroyed();
}

defaultproperties
{
    InvSize=48
    CanShiftClickIn=false
    HasCraftMgr=false
    bTickIsDisabled=false
    RemoteRole=ROLE_None
}
