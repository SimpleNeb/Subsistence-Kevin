// Authority-only adapter around the game's actual shared tree-depletion ledger.
// UNCOMPILED feature work. The player's axe module remains entirely untouched.
class KevinWoodHarvester extends ColdModuleAxeChop;

var KevinGatheringJob Job;
var ColdInventoryItem PendingLog;
var ColdTree ExpectedTree;
var bool bNativeChopInProgress;
var bool bDeliveredLog;

simulated event PostBeginPlay()
{
    super(Actor).PostBeginPlay();
    SetTickIsDisabled(true);
    Efficiency = class'ColdModuleAxeChop'.default.Efficiency;
    ChopStrength = class'ColdModuleAxeChop'.default.ChopStrength;
}

simulated function ColdPlayerPawn GetPawn()
{
    if (Job == none || Job.Worker == none || Job.Worker.CompanionOwner == none) { return none; }
    return ColdPlayerPawn(Job.Worker.CompanionOwner.Pawn);
}

simulated function bool IsStrengthBoostActive() { return false; }
simulated function ToggleProgressHud(bool bInRange, optional int chopProgress, optional string colorStr) {}
simulated function Tick(float DeltaTime) {}

function bool ChopActualTree(ColdTree tree, vector hitLocation)
{
    local ColdInventoryItem_Axe axe;
    local ColdPlayerPawn ownerPawn;
    local int i;
    local bool willYield;
    if (Role != ROLE_Authority || Job == none || !Job.CanWorkNow() ||
        tree == none || !Job.IsTreeAvailable(tree) || !Job.IsTargetInReach()) { return false; }
    ownerPawn = GetPawn();
    axe = Job.Worker.GetUsableAxe();
    if (ownerPawn == none || ownerPawn.HarvestManager == none || axe == none ||
        !Job.CanFitSingle(class'ColdInventoryItem_Log', 1)) { return false; }
    for (i = 0; i < ownerPawn.HarvestManager.HarvestedTrees.Length; i++) {
        if (ownerPawn.HarvestManager.HarvestedTrees[i].treeId == string(tree)) {
            willYield = ownerPawn.HarvestManager.HarvestedTrees[i].chopProgress + Efficiency * ChopStrength > 360;
            break;
        }
    }
    // Reserve the actual item before changing native progress. Failure leaves
    // the tree and axe unchanged. No item exists until a native yield is due.
    if (willYield) {
        PendingLog = Spawn(class'ColdInventoryItem_Log', self);
        if (PendingLog == none) { return false; }
        PendingLog.SetInitialCount(1);
    }
    ExpectedTree = tree;
    bDeliveredLog = false;
    bNativeChopInProgress = true;
    // This updates the same HarvestedTrees entry that the owner's native axe
    // reads, and honors ColdTree.GetNumLogsToYield and native chop strength.
    super.ChopTree(tree, hitLocation);
    bNativeChopInProgress = false;
    ExpectedTree = none;
    if (PendingLog != none) { PendingLog.Destroy(); PendingLog = none; }
    // Stock hunter tools never wear. Apply the supplied axe's native Wood cost
    // with a small minimum for this job when the shipped tree cost is zero.
    axe.MinusHealth(FMax(0.1, axe.GetWeaponUseDamageForMaterialType(none, 'Wood')));
    return !willYield || bDeliveredLog;
}

simulated event SpawnWood(vector hitLocation, Actor tree, byte logNum)
{
    // Only the inherited completed-chop callback may transfer the reserved log.
    if (!bNativeChopInProgress || tree != ExpectedTree || PendingLog == none ||
        Job == none || logNum < 1 || logNum > ExpectedTree.GetNumLogsToYield()) { return; }
    bDeliveredLog = Job.AddPreparedItem(PendingLog);
    PendingLog = none; // Native add owns or drops this same actor; never clone it.
    if (bDeliveredLog) { Job.UnitsGathered++; }
}

simulated function Destroyed()
{
    if (PendingLog != none) { PendingLog.Destroy(); PendingLog = none; }
    Job = none;
    super(Actor).Destroyed(); // Do not clear the actual player's quick-action HUD.
}

defaultproperties
{
    bHidden=true
    bCollideActors=false
    bBlockActors=false
    RemoteRole=ROLE_None
}
