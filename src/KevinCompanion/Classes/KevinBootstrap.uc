// Spawn this actor to adopt one existing hunter, or toggle an existing companion.
// Does not spawn a hunter or alter global hunter settings. The independent
// registry removes just the adopted member from its former squad's live count.
class KevinBootstrap extends Actor;

static function KevinHunterController AdoptHunter(ColdHunterController oldController, ColdPlayerController pc)
{
    local ColdHunterPawn existingPawn;
    local ColdHunterSquad squad;
    local KevinHunterController replacement;
    local int memberIndex;
    local name previousState;

    if (oldController == none || pc == none || pc.Pawn == none ||
        oldController.WorldInfo.NetMode != NM_Standalone ||
        oldController.class != class'ColdHunterController' || oldController.Pawn == none ||
        oldController.Pawn.class != class'ColdHunterPawn' || oldController.Pawn.Health <= 0 ||
        oldController.IsInCombat() || oldController.TargetPawn != none || oldController.bIsInBase) { return none; }
    existingPawn = ColdHunterPawn(oldController.Pawn);
    squad = existingPawn.BelongsToSquad;
    if (squad == none || squad.class != class'ColdHunterSquad') { return none; }
    memberIndex = squad.SquadMembers.Find(oldController);
    if (memberIndex == INDEX_NONE) { return none; }
    replacement = oldController.Spawn(class'KevinHunterController', pc,, existingPawn.Location, existingPawn.Rotation);
    if (replacement == none) { return none; }
    replacement.CompanionOwner = pc;
    previousState = oldController.GetStateName();
    existingPawn.StopFiring();
    oldController.StopLatentExecution();
    // Disabled explicitly ignores UnPossess/Possess in ColdAiController.
    // An empty state runs normal EndState cleanup without suppressing handoff.
    oldController._GotoState('');
    oldController.UnPossess();
    if (oldController.Pawn != none || existingPawn.Controller != none) {
        oldController._GotoState(previousState);
        replacement.Destroy();
        return none;
    }
    replacement.Possess(existingPawn, false);
    if (replacement.Pawn != existingPawn || existingPawn.Controller != replacement) {
        if (replacement.Pawn == existingPawn) { replacement.UnPossess(); }
        oldController.Possess(existingPawn, false);
        oldController._GotoState(previousState);
        replacement.Destroy();
        return none;
    }
    squad.SquadMembers[memberIndex] = replacement;
    // BelongsToSquad and HunterSpawnedCount deliberately retain their values.
    oldController.ClearAllTimers();
    // Pawn is now None; normal helper cleanup and vanilla Logout notification run.
    oldController.Destroy();
    replacement.InitializeCompanion(pc);
    return replacement;
}

event PostBeginPlay()
{
    local ColdPlayerController pc;
    local ColdHunterController hunter, selected;
    local KevinHunterController companion;
    local KevinRegistry registry, existingRegistry;
    local float distance, bestDistance;

    super.PostBeginPlay();
    if (WorldInfo.NetMode != NM_Standalone) { Destroy(); return; }
    pc = ColdPlayerController(GetALocalPlayerController());
    if (pc == none || pc.Pawn == none || pc.Pawn.Health <= 0) {
        LogInternal("KEVIN BOOTSTRAP NO LIVE PLAYER"); Destroy(); return;
    }
    foreach DynamicActors(class'KevinRegistry', registry) {
        if (!registry.bInitialized || registry.bDeleteMe) { continue; }
        if (existingRegistry != none) {
            pc.PrintToConsole("Kevin refused: duplicate registries."); Destroy(); return;
        }
        existingRegistry = registry;
    }
    if (existingRegistry != none) {
        if (existingRegistry.OwnerPlayerId != pc.PlayerId_Int || existingRegistry.Companion == none ||
            existingRegistry.CompanionPawn == none || existingRegistry.CompanionPawn.Health <= 0) {
            pc.PrintToConsole("Kevin unavailable: check status or saved restoration log."); Destroy(); return;
        }
        companion = existingRegistry.Companion;
        companion.SetFollowing(!companion.bFollowing);
        pc.PrintToConsole(companion.bFollowing ? "Kevin: following." : "Kevin: waiting.");
        Destroy(); return;
    }
    foreach DynamicActors(class'KevinHunterController', companion) {
        if (companion.CompanionOwner == pc && companion.Pawn != none) {
            companion.SetFollowing(!companion.bFollowing);
            pc.PrintToConsole(companion.bFollowing ? "Kevin: following." : "Kevin: waiting.");
            Destroy(); return;
        }
    }
    bestDistance = 3000;
    foreach DynamicActors(class'ColdHunterController', hunter) {
        if (hunter.class != class'ColdHunterController' || hunter.Pawn == none || hunter.Pawn.Health <= 0 ||
            hunter.IsInCombat() || hunter.TargetPawn != none || hunter.bIsInBase ||
            hunter.GetSquad() == none || hunter.GetSquad().class != class'ColdHunterSquad') { continue; }
        distance = VSize(hunter.Pawn.Location - pc.Pawn.Location);
        if (distance < bestDistance) { bestDistance = distance; selected = hunter; }
    }
    registry = none;
    if (selected != none) { registry = Spawn(class'KevinRegistry'); }
    if (registry != none && registry.AdoptHunter(selected, pc)) {
        pc.PrintToConsole("Kevin recruited: waiting. Activate again to follow.");
    } else {
        if (registry != none) { registry.Destroy(); }
        pc.PrintToConsole("Kevin: no eligible idle hunter within range.");
        LogInternal("KEVIN NO ELIGIBLE HUNTER");
    }
    Destroy();
}

defaultproperties
{
    bHidden=true
    bCollideActors=false
    bBlockActors=false
    RemoteRole=ROLE_None
}

