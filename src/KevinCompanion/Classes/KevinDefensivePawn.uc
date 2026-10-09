// Guarded weapon firing and wear on the actual clothing supplied to Kevin.
class KevinDefensivePawn extends KevinCompanionPawn;

function bool BotFire(bool bFinished)
{
    local KevinDefensiveHunterController defender;
    local bool result;
    defender = KevinDefensiveHunterController(Controller);
    if (Role != Role_Authority || IsKevinInventoryBusy() || defender == none ||
        !defender.CanCompanionFire()) {
        bNoWeaponFiring = true;
        StopFiring();
        return false;
    }
    bNoWeaponFiring = false;
    // Skip the passive override and ColdHunterPawn's hostile-squad notification.
    result = super(ColdHumanPawn).BotFire(bFinished);
    StopFiring();
    bNoWeaponFiring = true;
    return result;
}

event TakeDamage(int Damage, Controller InstigatedBy, vector HitLocation, vector Momentum,
    class<DamageType> DamageType, optional TraceHitInfo HitInfo, optional Actor DamageCauser)
{
    // Stock hunter armor already protects health; wear is only applied to
    // player pawns. Apply the same wear to Kevin's actual supplied clothes.
    super.TakeDamage(Damage, InstigatedBy, HitLocation, Momentum, DamageType, HitInfo, DamageCauser);
    if (Role == Role_Authority && !IsKevinInventoryBusy() && ClothingManager != none && Damage > 0) {
        ClothingManager.TakeDamageToClothing(Damage, HitLocation, DamageType, HitInfo, DamageCauser);
    }
}

defaultproperties
{
    ControllerClass=class'KevinDefensiveHunterController'
    bNoWeaponFiring=true
}
