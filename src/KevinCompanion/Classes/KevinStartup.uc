// Production entry for the package hook after ColdGame.SpawnModManager.
// This transient actor registers the real mutator chain, then removes itself.
class KevinStartup extends Actor;

event PostBeginPlay()
{
    local GameInfo game;
    local Mutator currentMutator;
    local KevinMutator kevin;
    local string initError;
    local int chainLength;

    super.PostBeginPlay();
    if (WorldInfo == none || WorldInfo.NetMode != NM_Standalone ||
        class'ColdGame'.static.IsMenuMap() || !class'KevinActivation'.static.IsEnabled()) {
        Destroy(); return;
    }
    game = WorldInfo.Game;
    if (game == none) { Destroy(); return; }

    // A URL-added Kevin or a prior startup actor already owns this group.
    // Never add a second Kevin, including when an isolated test owns the chain.
    currentMutator = game.BaseMutator;
    while (currentMutator != none && chainLength < 256) {
        kevin = KevinMutator(currentMutator);
        if (kevin != none) { break; }
        currentMutator = currentMutator.NextMutator;
        chainLength++;
    }
    if (kevin == none && currentMutator != none) {
        LogInternal("KEVIN STARTUP REFUSED invalid or excessive mutator chain");
        Destroy(); return;
    }
    if (kevin == none) {
        // GameInfo performs AllowMutator, duplicate/group validation, Spawn,
        // and BaseMutator/NextMutator registration. It does not call InitMutator.
        game.AddMutator(PathName(class'KevinDefensiveMutator'), false);
        currentMutator = game.BaseMutator;
        chainLength = 0;
        while (currentMutator != none && chainLength < 256) {
            kevin = KevinMutator(currentMutator);
            if (kevin != none) { break; }
            currentMutator = currentMutator.NextMutator;
            chainLength++;
        }
    }
    if (kevin == none || kevin.bDeleteMe) {
        LogInternal("KEVIN STARTUP REFUSED GameInfo did not register a Kevin mutator");
        Destroy(); return;
    }

    // Native super.InitGame has already initialized pre-existing mutators.
    // Initialize only Kevin here; the shared guard makes repeat hooks harmless
    // and preserves the URL options of an already initialized Kevin/test mutator.
    kevin.InitializeKevinSession("", initError);
    if (initError != "") {
        LogInternal("KEVIN STARTUP INITIALIZATION ERROR " $ initError);
    } else {
        LogInternal("KEVIN STARTUP REGISTERED mutator=" $ string(kevin));
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
