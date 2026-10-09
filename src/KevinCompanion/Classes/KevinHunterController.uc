// Friendly follow/wait controller isolated from stock hunter aggression.
// Additive development prototype. Inherits the shipped hunter class defaults.
// Must compile and pass a disposable-world runtime test before installation.
class KevinHunterController extends ColdHunterController;

var ColdPlayerController CompanionOwner;
var KevinRegistry CompanionRegistry;
var bool bFollowing;
var vector CompanionDestination;
var KevinGatheringJob GatheringJob;
var bool bCommandMenuOpen;
var bool bCatchUpSprint;
var float CatchUpSprintStartDistance;
var float CatchUpSprintStopDistance;

simulated function PreBeginPlay()
{
    // ColdGame compiler stubs can omit zero/None child default deltas. Apply
    // required behavior before the native parent can create hostile handlers
    // or schedule movement/home/disable callbacks.
    bIgnorePlayer = true;
    bUseDisableChecks = false;
    GotoDisabledStateAtDist = 0;
    bEnableCheckForMovement = false;
    bEnableCloseToHomeCheck = false;
    TakeHitHandlerClass = none;
    IdleStateName = 'KevinPassive';
    RoamStateName = 'KevinPassive';
    super.PreBeginPlay();
    // ColdHunterController.PreBeginPlay sets this false outside dev mode.
    bIgnorePlayer = true;
    bUseDisableChecks = false;
}

simulated function PostBeginPlay()
{
    super.PostBeginPlay();
    ClearAllTimers();
    bIgnorePlayer = true;
    bUseDisableChecks = false;
    _GotoState('KevinPassive', 'Begin', true);
    SetTimer(0.5, true, 'CompanionHeartbeat');
}

function InitializeCompanion(ColdPlayerController pc)
{
    CompanionOwner = pc;
    bFollowing = false;
    TargetPawn = none;
    SuspiciousOfPawn = none;
    Enemy = none;
    if (Pawn != none) {
        // Engine.Pawn.StartFire checks this before invoking Weapon.StartFire.
        // It also protects the original hunter pawn retained by adoption.
        Pawn.bNoWeaponFiring = true;
        Pawn.StopFiring();
        Pawn.Acceleration = vect(0,0,0);
        Pawn.Velocity = vect(0,0,0);
    }
    if (GetHumanPawn() != none && GetHumanPawn().GetPlayerInvMgr() != none) {
        GetHumanPawn().GetPlayerInvMgr().ClearEquiptToolBeltItem();
    }
    bIsDisabled = false;
    if (GetPawn() != none) { GetPawn().SetEnabled(); }
    _GotoState('KevinPassive', 'Begin', true);
    LogInternal("KEVIN ADOPTED controller=" $ string(self) $ " pawn=" $ string(Pawn) $ " squad=" $ string(GetSquad()));
}

function bool GetFollowingOrder()
{
    if (KevinCompanionPawn(Pawn) != none && KevinCompanionPawn(Pawn).KevinInventory != none &&
        KevinCompanionPawn(Pawn).KevinInventory.bStaged) {
        return KevinCompanionPawn(Pawn).KevinInventory.bResumeFollowing;
    }
    return bFollowing;
}

function SetFollowing(bool follow)
{
    CancelGathering(false);
    if (KevinCompanionPawn(Pawn) != none && KevinCompanionPawn(Pawn).IsKevinInventoryBusy() &&
        KevinCompanionPawn(Pawn).KevinInventory != none && KevinCompanionPawn(Pawn).KevinInventory.bStaged) {
        KevinCompanionPawn(Pawn).KevinInventory.bResumeFollowing = follow;
        follow = false;
    }
    bFollowing = follow;
    SetCompanionSprint(false);
    StopLatentExecution();
    if (Pawn != none) {
        Pawn.Acceleration = vect(0,0,0);
        Pawn.Velocity = vect(0,0,0);
        Pawn.StopFiring();
    }
    _GotoState('KevinPassive', 'Begin', true);
    LogInternal("KEVIN ORDER following=" $ string(bFollowing));
}

function ColdInventoryItem_Axe GetUsableAxe()
{
    local ColdPlayerInvManager inv;
    local ColdInventoryItem_Axe axe;
    local int i;
    if (GetHumanPawn() == none || KevinCompanionPawn(Pawn) == none ||
        KevinCompanionPawn(Pawn).IsKevinInventoryBusy()) { return none; }
    inv = GetHumanPawn().GetPlayerInvMgr();
    if (inv == none) { return none; }
    for (i = 35; i <= 41; i++) {
        axe = ColdInventoryItem_Axe(inv.GetInvItem(i));
        if (axe != none && !axe.bDeleteMe && axe.Health > 0 && !axe.IsBroken()) { return axe; }
    }
    for (i = 0; i < 35; i++) {
        axe = ColdInventoryItem_Axe(inv.GetInvItem(i));
        if (axe != none && !axe.bDeleteMe && axe.Health > 0 && !axe.IsBroken()) { return axe; }
    }
    return none;
}

function bool HasUsableAxe() { return GetUsableAxe() != none; }

function bool EquipGatheringAxe()
{
    local ColdPlayerInvManager inv;
    local ColdInventoryItem_Axe axe;
    local int i, fromSlot, beltSlot;
    axe = GetUsableAxe();
    if (axe == none) { return false; }
    inv = GetHumanPawn().GetPlayerInvMgr();
    fromSlot = -1;
    beltSlot = -1;
    for (i = 0; i <= 41; i++) { if (inv.GetInvItem(i) == axe) { fromSlot = i; break; } }
    if (fromSlot >= 35) { beltSlot = fromSlot; }
    else {
        for (i = 35; i <= 41; i++) { if (inv.GetInvItem(i) == none) { beltSlot = i; break; } }
        if (beltSlot < 0 || !inv.InternalMoveItemToSlot(
            class'ColdInventoryItemUtils'.static.MakeInvSlotInfo(fromSlot),
            class'ColdInventoryItemUtils'.static.MakeInvSlotInfo(beltSlot)) || inv.GetInvItem(beltSlot) != axe) { return false; }
    }
    if (inv.GetEquiptToolBeltItem() == axe && GetHeldWeapon() != none && GetHeldWeapon().WeaponInvItem == axe) { return true; }
    if (inv.CurrentToolBeltSlot == beltSlot) { inv.ClearEquiptToolBeltItem(); }
    inv.SwitchToBeltItem(byte(beltSlot - inv.ToolBeltSlotIdxStart + 1), true);
    return ColdWeapon_Axe(GetHeldWeapon()) != none && GetHeldWeapon().WeaponInvItem == axe;
}

function bool StartGathering(name job, out string reason)
{
    local KevinGatheringJob preparedJob;
    if (job != 'Wood' && job != 'Fiber') { reason = "Unknown gathering order."; return false; }
    if (WorldInfo.NetMode != NM_Standalone || Pawn == none || Pawn.Health <= 0 || CompanionOwner == none ||
        CompanionOwner.Pawn == none || CompanionOwner.Pawn.Health <= 0 || KevinCompanionPawn(Pawn) == none ||
        KevinCompanionPawn(Pawn).IsKevinInventoryBusy() || IsInCombat() || bIsInBase || IsInCave() || IsInLavaCave()) {
        reason = "Kevin cannot gather here right now."; return false;
    }
    if (job == 'Wood' && !HasUsableAxe()) { reason = "Give Kevin a usable axe first."; return false; }
    preparedJob = Spawn(class'KevinGatheringJob', self);
    if (preparedJob == none) { reason = "Could not start gathering."; return false; }
    if (!preparedJob.InitializeJob(self, job)) {
        preparedJob.Destroy(); reason = "Could not start gathering."; return false;
    }
    if (!preparedJob.CanFitSingle(job == 'Wood' ? class'ColdInventoryItem_Log' : class'ColdInventoryItem_Fibers', 1)) {
        preparedJob.Destroy(); reason = "Kevin's cargo is full."; return false;
    }
    if (job == 'Wood' && !EquipGatheringAxe()) {
        preparedJob.Destroy(); reason = "Kevin needs an empty toolbelt slot for his axe."; return false;
    }
    // A rejected menu choice leaves the existing order intact. Replace the old
    // job only after its replacement and any required tool are ready.
    SetFollowing(false);
    GatheringJob = preparedJob;
    if (!bCommandMenuOpen) { _GotoState('KevinGather', 'Begin', true); }
    reason = job == 'Wood' ? "Kevin is gathering nearby wood." : "Kevin is gathering nearby fiber.";
    LogInternal("KEVIN GATHER START job=" $ string(job));
    return true;
}

function name GetGatheringOrder()
{
    return GatheringJob != none ? GatheringJob.JobKind : '';
}

function string GetGatheringStatus()
{
    if (GatheringJob == none) { return bFollowing ? "Following" : "Staying"; }
    return (GatheringJob.JobKind == 'Wood' ? "Gathering wood" : "Gathering fiber") $
        " (" $ string(GatheringJob.UnitsGathered) $ " collected)";
}

function CancelGathering(optional bool resumeFollowing)
{
    local KevinGatheringJob oldJob;
    if (GatheringJob == none) { return; }
    oldJob = GatheringJob;
    GatheringJob = none;
    oldJob.Destroy();
    bFollowing = resumeFollowing;
    StopLatentExecution();
    SetCompanionSprint(false);
    if (Pawn != none) { Pawn.StopFiring(); Pawn.Acceleration = vect(0,0,0); Pawn.Velocity = vect(0,0,0); }
    Focus = none;
    _GotoState('KevinPassive', 'Begin', true);
}

function FinishGathering(string reason)
{
    LogInternal("KEVIN GATHER STOP reason=" $ reason);
    CancelGathering(true);
    if (CompanionOwner != none && CompanionOwner.GetHudMgr() != none) { CompanionOwner.GetHudMgr().Message("Kevin: " $ reason); }
}

function SetCommandMenuOpen(bool open)
{
    bCommandMenuOpen = open;
    StopLatentExecution();
    SetCompanionSprint(false);
    Focus = none;
    TargetPawn = none;
    Enemy = none;
    if (Pawn != none) { Pawn.StopFiring(); Pawn.bNoWeaponFiring = true; Pawn.Acceleration = vect(0,0,0); Pawn.Velocity = vect(0,0,0); }
    if (!open && GatheringJob != none) { _GotoState('KevinGather', 'Begin', true); }
    else { _GotoState('KevinPassive', 'Begin', true); }
}

function SetCompanionSprint(bool sprint)
{
    bCatchUpSprint = sprint;
    if (GetHumanPawn() != none) { GetHumanPawn().ServerSetSprint(sprint); }
    // Hunters normally use these controller speeds directly. This also works
    // when their human health manager does not run player stamina updates.
    if (Pawn != none) { Pawn.GroundSpeed = sprint ? SprintSpeed : WalkingSpeed; }
}

function PrepareCompanionMove(bool allowCatchUp)
{
    local float distance;
    if (Pawn == none) { return; }
    Focus = none;
    Enemy = none;
    LowerWeapon();
    if (CompanionOwner != none && CompanionOwner.Pawn != none) { distance = VSize(Pawn.Location - CompanionOwner.Pawn.Location); }
    if (!allowCatchUp || bCommandMenuOpen) { SetCompanionSprint(false); }
    else if (distance >= CatchUpSprintStartDistance) { SetCompanionSprint(true); }
    else if (distance <= CatchUpSprintStopDistance) { SetCompanionSprint(false); }
}

function CompanionHeartbeat()
{
    if (Pawn == none || Pawn.Health <= 0) { return; }
    TargetPawn = none;
    SuspiciousOfPawn = none;
    Enemy = none;
    Pawn.bNoWeaponFiring = true;
    Pawn.StopFiring();
    if (bCommandMenuOpen) { return; }
    if (CompanionOwner == none || CompanionOwner.bDeleteMe ||
        CompanionOwner.Pawn == none || CompanionOwner.Pawn.Health <= 0) {
        if (bFollowing || GatheringJob != none) { SetFollowing(false); }
    }
    if (GatheringJob != none) {
        if (!GatheringJob.CanWorkNow()) { FinishGathering("Gathering stopped; returning to you."); }
        else if (GetStateName() != 'KevinGather') { _GotoState('KevinGather'); }
    } else if (GetStateName() != 'KevinPassive') { _GotoState('KevinPassive'); }
}

function _GotoState(optional name newState, optional name label, optional bool bForceEvents, optional bool bKeepStack)
{
    if (newState != 'KevinPassive' && newState != 'KevinGather') { return; }
    if (newState == 'KevinGather' && (GatheringJob == none || bCommandMenuOpen)) { return; }
    super._GotoState(newState, label, bForceEvents, bKeepStack);
}

function GotoIdleState() { _GotoState('KevinPassive'); }
function bool CanCurrentlyBeDisabled() { return false; }
event bool IsInCombat(optional bool bForceCheck) { return false; }
function bool ShouldChaseAttackVehicle(ColdVehicle vehicle) { return false; }
function SetTargetPawn(Pawn playerToTarget) { TargetPawn = none; }
function EnableRage(Pawn p) {}
event SeePlayer(Pawn seenPlayer) {}
event SeeMonster(Pawn seen) {}
event HearNoise(float loudness, Actor noiseMaker, optional name noiseType) {}
event DamageTakenByPlayer(ColdHumanPawn p) {}
event DamageTakenByPlayerInBase(ColdHumanPawn p) {}
event DamageTakenByAnimal(ColdAnimalController animal) {}
event SquadMemberTakenDmg(Pawn dmgCauser, bool assistIfAvailable) {}
function NotifySquadMateThrownGrenade(vector atLoc) {}
function NotifyKilledAnotherPawn(Controller killedPlayer, Pawn killedPawn, class<DamageType> damageType) {}
event HumanExitedTargetVehicle(ColdVehicle vehicle) {}
event TargetHumanEnteredVehicle(ColdVehicle vehicle) {}
event PostTakenDamage(int damage, Controller instigatedBy, vector hitLoc, vector momentum,
    class<DamageType> dmgType, optional TraceHitInfo hitInfo, optional Actor damageCauser) {}

event MovedOnToBase(bool bHunterBase, ColdBuildable buildable, ColdHunterBase hunterBase)
{
    bIsInBase = true;
    bIsInHunterBase = bHunterBase;
    bIsInHomeBase = bHunterBase && hunterBase == GetHunterBase();
}
event MovedOffOfBase()
{
    bIsInBase = false;
    bIsInHunterBase = false;
    bIsInHomeBase = false;
}

simulated function Destroyed()
{
    ClearTimer('CompanionHeartbeat');
    if (GatheringJob != none) { GatheringJob.Destroy(); GatheringJob = none; }
    if (CompanionRegistry != none) { CompanionRegistry.NotifyControllerDestroyed(self); }
    CompanionRegistry = none;
    CompanionOwner = none;
    super.Destroyed();
}

// The independent KevinRegistry owns persistence after adoption. This marker
// helps diagnose any accidental legacy squad ownership without modifying it.
function JsonObject Serialize()
{
    local JsonObject data;
    data = super.Serialize();
    data.SetBoolValue("kevinSessionPrototype", true);
    return data;
}

auto state KevinPassive
{
    event BeginState(name PreviousStateName)
    {
        if (Pawn != none) {
            Pawn.StopFiring();
            Pawn.Acceleration = vect(0,0,0);
            Pawn.Velocity = vect(0,0,0);
        }
    }

    event bool NotifyHitWall(vector HitNormal, actor Wall)
    {
        StopLatentExecution();
        return false;
    }

Begin:
    if (Pawn != none && Pawn.Health > 0 && bFollowing && !bCommandMenuOpen &&
        CompanionOwner != none && CompanionOwner.Pawn != none && CompanionOwner.Pawn.Health > 0 &&
        (KevinCompanionPawn(Pawn) == none || !KevinCompanionPawn(Pawn).IsKevinInventoryBusy()) &&
        !bIsInBase && !IsInCave() && !IsInLavaCave() &&
        VSize(Pawn.Location - CompanionOwner.Pawn.Location) > 450) {
        PrepareCompanionMove(true);
        CompanionDestination = class'ColdPositionHelper'.static.GetNonBlockedPathTowardsLocation(
            Pawn, Pawn.Location, CompanionOwner.Pawn.Location,
            700, 0, 300, true, false, false, false, false);
        if (CompanionDestination != vect(0,0,0)) {
            // Facing a moving owner here causes stock hunter side/back strafing.
            // Native MoveTo with no focus turns Kevin toward his travel direction.
            MoveTo(CompanionDestination, none, 100, false);
        }
    } else {
        SetCompanionSprint(false);
    }
    Sleep(0.25);
    Goto('Begin');
}

state KevinGather
{
    event BeginState(name PreviousStateName)
    {
        SetCompanionSprint(false);
        Focus = none;
        if (Pawn != none) { Pawn.StopFiring(); Pawn.bNoWeaponFiring = true; }
    }

    event bool NotifyHitWall(vector HitNormal, Actor Wall)
    {
        if (GatheringJob != none) { GatheringJob.SkipTarget(); }
        StopLatentExecution();
        return false;
    }

Begin:
    if (GatheringJob == none) { _GotoState('KevinPassive'); Stop; }
    if (bCommandMenuOpen) { Sleep(0.25); Goto('Begin'); }
    if (!GatheringJob.CanWorkNow()) { FinishGathering("Gathering stopped; returning to you."); Stop; }
    if (GatheringJob.TargetResource == none && !GatheringJob.FindResource()) {
        FinishGathering(GatheringJob.LastReason); Stop;
    }
    if (!GatheringJob.IsTargetInReach()) {
        CompanionDestination = GatheringJob.GetApproachPoint();
        if (CompanionDestination == vect(0,0,0)) { GatheringJob.SkipTarget(); }
        else {
            PrepareCompanionMove(false);
            MoveTo(CompanionDestination, none, 30, false);
        }
        Sleep(0.25);
        Goto('Begin');
    }
    StopMovement();
    SetCompanionSprint(false);
    Focus = none;
    SetFocalPoint(GatheringJob.TargetLocation + vect(0,0,74));
    FinishRotation();
    if (GatheringJob.JobKind == 'Wood') {
        if (!EquipGatheringAxe()) { FinishGathering("Kevin needs a usable axe and an available toolbelt slot."); Stop; }
        if (IsEquippingWeapon(FloatVar)) { Sleep(FMax(0.1, FloatVar)); }
        if (GatheringJob == none || !GatheringJob.CanWorkNow()) { Goto('Begin'); }
        // Play the native held-axe animation without invoking weapon damage.
        // The resource transaction below rechecks the actual tree/range/axe.
        GetHumanPawn().PlayAnimation(GetHumanPawn().AnimFireAxe, 1, 0.2, 0.1, false, false, true);
        Sleep(0.7);
    } else { Sleep(0.5); }
    if (GatheringJob == none) { _GotoState('KevinPassive'); Stop; }
    if (!GatheringJob.PerformHarvest()) {
        if (GatheringJob.LastReason != "") { FinishGathering(GatheringJob.LastReason); Stop; }
        GatheringJob.SkipTarget();
    }
    Sleep(0.7);
    Goto('Begin');
}

defaultproperties
{
    bIgnorePlayer=true
    bUseDisableChecks=false
    GotoDisabledStateAtDist=0
    bEnableCheckForMovement=false
    bEnableCloseToHomeCheck=false
    TakeHitHandlerClass=None
    IdleStateName=KevinPassive
    RoamStateName=KevinPassive
    CatchUpSprintStartDistance=900
    CatchUpSprintStopDistance=550
}

