// DRAFT: additive layer over inventory-draft's Kevin classes. Not runtime tested.
class KevinDefensiveHunterController extends KevinHunterController;

var Pawn DamageThreat;
var float DamageThreatUntil;
var float DefenseRange;
var float OwnerDefenseLeash;
var vector DefenseAim;

function bool IsProtectedPawn(Pawn p)
{
    if (p == none) { return false; }
    return p == Pawn || ColdPlayerPawn(p) != none || PlayerController(p.Controller) != none ||
        ColdVehicle(p) != none || KevinHunterController(p.Controller) != none ||
        (CompanionOwner != none && p == CompanionOwner.Pawn);
}

function bool CanUseDefense()
{
    return Role == Role_Authority && !bCommandMenuOpen && Pawn != none && !Pawn.bDeleteMe && Pawn.Health > 0 &&
        KevinCompanionPawn(Pawn) != none && !KevinCompanionPawn(Pawn).IsKevinInventoryBusy() &&
        CompanionOwner != none && !CompanionOwner.bDeleteMe && CompanionOwner.Pawn != none &&
        CompanionOwner.Pawn.Health > 0 &&
        VSize(Pawn.Location - CompanionOwner.Pawn.Location) <= OwnerDefenseLeash;
}

function bool IsDefensiveThreat(Pawn p)
{
    local ColdAIController ai;
    if (!CanUseDefense() || p == none || p.bDeleteMe || p.Health <= 0 || IsProtectedPawn(p)) { return false; }
    if (ColdHunterPawn(p) == none && ColdAnimalPawn(p) == none) { return false; }
    // Docile animals use TargetPawn for the human they are fleeing from.
    // Exclude them before either targeting or recent-damage authorization.
    if (ColdAnimalPawnDocile(p) != none) { return false; }
    if (VSize(p.Location - Pawn.Location) > DefenseRange ||
        VSize(p.Location - CompanionOwner.Pawn.Location) > DefenseRange) { return false; }
    if (p == DamageThreat && WorldInfo.TimeSeconds < DamageThreatUntil) { return true; }
    ai = ColdAIController(p.Controller);
    return ai != none && (ai.TargetPawn == Pawn || ai.TargetPawn == CompanionOwner.Pawn);
}

function SetTargetPawn(Pawn playerToTarget)
{
    TargetPawn = IsDefensiveThreat(playerToTarget) ? playerToTarget : none;
    Enemy = TargetPawn;
    SuspiciousOfPawn = none;
}

function BeginDefense(Pawn attacker)
{
    if (!IsDefensiveThreat(attacker)) { return; }
    if (GatheringJob != none) { CancelGathering(true); }
    SetCompanionSprint(false);
    SetTargetPawn(attacker);
    if (TargetPawn != none && GetStateName() != 'KevinDefend') {
        StopLatentExecution();
        _GotoState('KevinDefend');
    }
}

function EndDefense()
{
    if (Pawn != none) { Pawn.bNoWeaponFiring = true; Pawn.StopFiring(); }
    TargetPawn = none;
    Enemy = none;
    Focus = none;
    if (GetStateName() != 'KevinPassive' && GetStateName() != 'KevinGather') { _GotoState('KevinPassive'); }
}

function CompanionHeartbeat()
{
    local ColdAIController ai;
    if (Pawn == none || Pawn.Health <= 0) { return; }
    // A shot opens the native firing gate only inside the guarded pawn call.
    Pawn.bNoWeaponFiring = true;
    bIgnorePlayer = true;
    SuspiciousOfPawn = none;
    if (bCommandMenuOpen) { EndDefense(); return; }
    if (!CanUseDefense()) {
        EndDefense();
        if (CompanionOwner == none || CompanionOwner.Pawn == none || CompanionOwner.Pawn.Health <= 0) {
            if (bFollowing || GatheringJob != none) { SetFollowing(false); }
        }
        return;
    }
    if (IsDefensiveThreat(TargetPawn)) { return; }
    if (TargetPawn != none || GetStateName() == 'KevinDefend') { EndDefense(); }
    if (IsDefensiveThreat(DamageThreat)) { BeginDefense(DamageThreat); return; }
    foreach WorldInfo.AllControllers(class'ColdAIController', ai) {
        if (ai != self && IsDefensiveThreat(ai.Pawn)) { BeginDefense(ai.Pawn); return; }
    }
    // When no threat wins priority, run the shared passive/gathering lifecycle.
    super.CompanionHeartbeat();
}

function _GotoState(optional name newState, optional name label, optional bool bForceEvents, optional bool bKeepStack)
{
    if (newState != 'KevinPassive' && newState != 'KevinDefend' && newState != 'KevinGather') { return; }
    if (newState == 'KevinGather' && (GatheringJob == none || bCommandMenuOpen)) { return; }
    if (newState == 'KevinDefend' && !IsDefensiveThreat(TargetPawn)) { return; }
    // Skip KevinHunterController's passive-only gate, retain our own strict gate.
    super(ColdHunterController)._GotoState(newState, label, bForceEvents, bKeepStack);
}

event PostTakenDamage(int damage, Controller instigatedBy, vector hitLoc, vector momentum,
    class<DamageType> dmgType, optional TraceHitInfo hitInfo, optional Actor damageCauser)
{
    if (damage <= 0 || instigatedBy == none || instigatedBy == self ||
        IsProtectedPawn(instigatedBy.Pawn)) { return; }
    DamageThreat = instigatedBy.Pawn;
    DamageThreatUntil = WorldInfo.TimeSeconds + 8.0;
    BeginDefense(DamageThreat);
}

event bool IsInCombat(optional bool bForceCheck)
{
    return GetStateName() == 'KevinDefend' && IsDefensiveThreat(TargetPawn);
}

function NotifyKilledAnotherPawn(Controller killedPlayer, Pawn killedPawn, class<DamageType> damageType)
{
    if (killedPawn == TargetPawn) { EndDefense(); }
}

// Never inherit hunter item fabrication or scripted weapon selection.
function EnsureHasAmmoForWeapon() {}
function AddAmmoForCurrentWeapon() {}
function SwitchToWeapon(class<ColdWeapon> weaponType) {}
function EquiptAWeapon(optional bool andReload = true) {}
event NotifyEmptyWeaponFireAttempt()
{
    if (GetHeldWeapon() != none && GetHeldWeapon().HasStorageAmmo()) { Reload(); }
}

function bool IsAllowedDefenseItem(ColdInventoryItem_Weapon item)
{
    if (item == none || item.bDeleteMe || item.IsBroken()) { return false; }
    return AllowedDefenseProjectile(item.WeaponClass, item.GetCurrentAmmoType()) != none;
}

function class<ColdProjectile> AllowedDefenseProjectile(class<ColdWeapon> w, class<ColdInventoryItem> ammo)
{
    // Exact weapon + ammo pairs. Incendiary ProcessTouch applies burning before
    // base impact, so checking only DamageRadius or the weapon class is unsafe.
    if (ammo == class'ColdInventoryItem_Ammo9mm') {
        if (w == class'ColdWeapon_M9') { return class'ColdProjectile9mm'; }
        if (w == class'ColdWeapon_Red9') { return class'ColdProjectile9mmRed9'; }
    }
    if (ammo == class'ColdInventoryItem_AmmoShotgunShells') {
        if (w == class'ColdWeapon_ShotgunM37') { return class'ColdProjectileShotgunShell'; }
        if (w == class'ColdWeapon_ShotgunDoubleBarrel') { return class'ColdProjectileShotgunShell_DB'; }
    }
    if (ammo == class'ColdInventoryItem_AmmoShotgunSlugs' && w == class'ColdWeapon_ShotgunDoubleBarrel') {
        return class'ColdProjectileShotgunSlug';
    }
    if (ammo == class'ColdInventoryItem_AmmoRifleRounds') {
        if (w == class'ColdWeapon_Rifle') { return class'ColdProjectileRifleCartridge'; }
        if (w == class'ColdWeapon_RifleLeverAction') { return class'ColdProjectileRifleLeverActionCartridge'; }
    }
    if (ammo == class'ColdInventoryItem_Ammo44Rounds' && w == class'ColdWeapon_Revolver') {
        return class'ColdProjectile44Round';
    }
    return none;
}

function bool IsAllowedLoadedAmmo(ColdWeapon w)
{
    local class<ColdProjectile> expectedProjectile;
    if (w == none || !IsAllowedDefenseItem(w.WeaponInvItem) ||
        w.WeaponInvItem.WeaponClass != w.Class ||
        w.AmmoClass != w.WeaponInvItem.GetCurrentAmmoType()) { return false; }
    expectedProjectile = AllowedDefenseProjectile(w.Class, w.AmmoClass);
    return expectedProjectile != none && expectedProjectile.default.DamageRadius <= 0 &&
        w.WeaponProjectiles.Length == 1 && w.WeaponProjectiles[0] == expectedProjectile;
}

function bool ItemHasDefenseAmmo(ColdInventoryItem_Weapon item, ColdPlayerInvManager inv)
{
    return IsAllowedDefenseItem(item) && (item.MagAmmoCount > 0 ||
        (item.GetCurrentAmmoType() != none && inv.GetItemCount(item.GetCurrentAmmoType()) > 0));
}

function bool EquipGivenDefenseWeapon()
{
    local ColdPlayerInvManager inv;
    local ColdInventoryItem_Weapon item;
    local int i, freeBelt, chosenSlot;
    local InventorySlotInfo fromSlot, toSlot;
    if (!CanUseDefense() || GetHumanPawn() == none) { return false; }
    inv = GetHumanPawn().GetPlayerInvMgr();
    if (inv == none) { return false; }
    item = ColdInventoryItem_Weapon(inv.GetEquiptToolBeltItem());
    if (inv.CurrentToolBeltSlot >= 35 && inv.CurrentToolBeltSlot <= 41 &&
        ItemHasDefenseAmmo(item, inv) && GetHeldWeapon() != none &&
        GetHeldWeapon().WeaponInvItem == item) { return true; }
    freeBelt = -1;
    chosenSlot = -1;
    // Prefer a supplied belt weapon. Never toggle an already selected slot off.
    for (i = 35; i <= 41; i++) {
        item = ColdInventoryItem_Weapon(inv.GetInvItem(i));
        if (ItemHasDefenseAmmo(item, inv)) { chosenSlot = i; break; }
        if (inv.GetInvItem(i) == none && freeBelt < 0) { freeBelt = i; }
    }
    if (chosenSlot < 0 && freeBelt >= 0) {
        // Move the existing item actor into a vacant belt slot; never clone it.
        for (i = 0; i < inv.ToolBeltSlotIdxStart; i++) {
            item = ColdInventoryItem_Weapon(inv.GetInvItem(i));
            if (ItemHasDefenseAmmo(item, inv)) {
                fromSlot = class'ColdInventoryItemUtils'.static.MakeInvSlotInfo(i);
                toSlot = class'ColdInventoryItemUtils'.static.MakeInvSlotInfo(freeBelt);
                inv.InternalMoveItemToSlot(fromSlot, toSlot);
                if (inv.GetInvItem(freeBelt) == item) { chosenSlot = freeBelt; }
                break;
            }
        }
    }
    if (chosenSlot < 0) { return false; }
    if (inv.CurrentToolBeltSlot == chosenSlot) { inv.ClearEquiptToolBeltItem(); }
    inv.SwitchToBeltItem(byte(chosenSlot - inv.ToolBeltSlotIdxStart + 1), true);
    TimeLastEquippedWeapon = WorldInfo.TimeSeconds;
    return GetHeldWeapon() != none && IsAllowedDefenseItem(GetHeldWeapon().WeaponInvItem);
}

function bool CanCompanionFire()
{
    local ColdWeapon w;
    local Pawn friendly;
    local vector start, line, closest, hitLoc, hitNorm;
    local float length, along;
    local Actor hit;
    if (GetStateName() != 'KevinDefend' || !IsDefensiveThreat(TargetPawn)) { return false; }
    w = GetHeldWeapon();
    if (w == none || !IsAllowedLoadedAmmo(w) ||
        !w.HasAmmo(0) || IsReloadingWeapon() || !IsAimingWeapon()) { return false; }
    start = Pawn.GetWeaponStartTraceLocation();
    line = DefenseAim - start;
    length = VSize(line);
    if (length < 1 || length > DefenseRange + 500) { return false; }
    line = Normal(line);
    // World/structure obstruction check, then a broad friendly corridor check.
    hit = Pawn.Trace(hitLoc, hitNorm, DefenseAim, start, true);
    if (hit != none && hit != TargetPawn) { return false; }
    foreach WorldInfo.AllPawns(class'Pawn', friendly) {
        if (friendly != Pawn && IsProtectedPawn(friendly)) {
            along = (friendly.Location - start) dot line;
            if (along > -150 && along < length + 500) {
                closest = start + line * along;
                if (VSize(friendly.Location - closest) < 240 + friendly.GetCollisionRadius()) { return false; }
            }
        }
    }
    return true;
}

// Retain inherited Attacking lifecycle/animation helpers, replace its player-
// retargeting handlers and statecode that exits into raid/chase/cover states.
state KevinDefend extends Attacking
{
ignores SeePlayer, SeeMonster, HearNoise, DamageTakenByPlayer, DamageTakenByPlayerInBase, DamageTakenByAnimal, SquadMemberTakenDmg;

    function ChooseStateCode() {}

    event EndState(name NextStateName)
    {
        if (Pawn != none) { Pawn.bNoWeaponFiring = true; Pawn.StopFiring(); }
        super.EndState(NextStateName);
    }

Begin:
    if (!IsDefensiveThreat(TargetPawn) || !EquipGivenDefenseWeapon()) { EndDefense(); Stop; }
    StopMovement();
    if (IsEquippingWeapon(FloatVar)) { Sleep(FMax(0.1, FloatVar)); }
    if (!IsDefensiveThreat(TargetPawn) || GetHeldWeapon() == none) { EndDefense(); Stop; }
    if (!GetHeldWeapon().HasAmmo(0) && GetHeldWeapon().HasStorageAmmo()) { Reload(); }
    if (IsReloadingWeapon(FloatVar)) { Sleep(FMax(0.1, FloatVar)); }
    if (!IsDefensiveThreat(TargetPawn) || GetHeldWeapon() == none) { EndDefense(); Stop; }
    RaiseWeapon();
    Sleep(FMax(0.1, GetWeaponAimDuration()));
    if (!IsDefensiveThreat(TargetPawn)) { EndDefense(); Stop; }
    DefenseAim = GetAimLocation(TargetPawn);
    Focus = none;
    SetFocalPoint(DefenseAim);
    FinishRotation();
    // Guard runs again in the pawn immediately before the native fire call.
    if (CanCompanionFire()) { Pawn.BotFire(true); Pawn.StopFiring(); }
    Sleep(FMax(0.25, GetDelayBetweenShots()));
    Goto('Begin');
}

defaultproperties
{
    DefenseRange=2200
    OwnerDefenseLeash=1800
}
