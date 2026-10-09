// Starts one persistent Kevin beside the ready player after native mod selection.
// The production hook registers KevinDefensiveMutator through KevinStartup.
class KevinMutator extends Mutator;

// Set true only in test-mutator subclasses, never by config or URL.
var bool bAllowIsolatedFixtures;
var bool bAutomaticTest;
var bool bKevinInitialized;
var bool bExitAfterTest;
var bool bFixtureStarted;
var int ReadinessChecks;
var int StartupChecks;
var Actor ActiveFixture;
var class<KevinRegistry> RegistryClass;
var class<Actor> FixtureClass;

function InitMutator(string Options, out string ErrorMessage)
{
    // Preserve native chain initialization on the ordinary GameInfo path.
    super.InitMutator(Options, ErrorMessage);
    InitializeKevinSession(Options, ErrorMessage);
}

// Late startup after GameInfo.InitGame must not reinitialize unrelated mutators.
// Both the ordinary native path and KevinStartup enter this exactly-once gate.
function InitializeKevinSession(string Options, out string ErrorMessage)
{
    if (bKevinInitialized) { return; }
    bKevinInitialized = true;
    if (WorldInfo.NetMode != NM_Standalone) { return; }
    bAutomaticTest = WorldInfo.Game.ParseOption(Options, "KevinTest") == "1";
    bExitAfterTest = WorldInfo.Game.ParseOption(Options, "KevinExitAfterTest") == "1";
    LogInternal("KEVIN MUTATOR LOADED automaticTest=" $ string(bAutomaticTest));
    if (bAllowIsolatedFixtures) {
        if (bAutomaticTest) { SetTimer(1.0, true, 'RunAutomaticTest'); }
        else { LogInternal("KEVIN FIXTURE REFUSED test mutator requires explicit KevinTest=1"); }
        return; // A test entrypoint never starts a production companion.
    }
    if (bAutomaticTest) {
        bAutomaticTest = false;
        LogInternal("KEVIN FIXTURE REFUSED production mutator has no test bypass");
        return;
    }
    SetTimer(1.0, true, 'EnsureCompanion');
}

function bool IsIsolatedFixtureSession()
{
    return bAllowIsolatedFixtures && bAutomaticTest && FixtureClass != none && WorldInfo.NetMode == NM_Standalone &&
        !class'ColdGame'.static.IsMenuMap();
}

function ColdPlayerController ReadyPlayer()
{
    local ColdGame game;
    local ColdPlayerController pc;
    game = ColdGame(WorldInfo.Game);
    pc = ColdPlayerController(GetALocalPlayerController());
    if (WorldInfo.NetMode != NM_Standalone || game == none ||
        class'ColdGame'.static.IsMenuMap() || game.LoadingSaveGameState != none ||
        game.bIsLoadingSaveGame || game.bGameEnding || game.PersistentPlayerStateMgr == none || pc == none ||
        pc.Pawn == none || pc.Pawn.Health <= 0 || pc.CachedPersistentPlayerStateIdx < 0 ||
        pc.PlayerId_Int != pc.CachedPersistentPlayerStateIdx) { return none; }
    return pc;
}

// Called after world/player/save readiness; any initialized record, including
// dead/pending/unsupported/failed records, prevents a second companion.
function EnsureCompanion()
{
    local ColdPlayerController pc;
    local KevinRegistry registry;
    local vector spawnLocation;
    local rotator direction;
    local int i;
    // No test bypass, machine id, Workshop folder id, or launch option may
    // substitute for native selection in this production path.
    if (bAllowIsolatedFixtures) { ClearTimer('EnsureCompanion'); return; }
    StartupChecks++;
    if (!class'KevinActivation'.static.HasSessionManager()) {
        if (StartupChecks >= 120) { ClearTimer('EnsureCompanion'); }
        return;
    }
    if (!class'KevinActivation'.static.IsEnabled()) {
        ClearTimer('EnsureCompanion');
        LogInternal("KEVIN STARTUP DISABLED native mod not selected");
        return;
    }
    pc = ReadyPlayer();
    if (pc == none) {
        if (StartupChecks >= 120) {
            ClearTimer('EnsureCompanion'); LogInternal("KEVIN STARTUP DEFERRED no ready player");
        }
        return;
    }
    foreach DynamicActors(class'KevinRegistry', registry) {
        if (!registry.bDeleteMe && registry.bInitialized) {
            ClearTimer('EnsureCompanion');
            LogInternal("KEVIN STARTUP existing registry retained=" $ string(registry)); return;
        }
    }
    // This first-spawn search only supports nearby surface terrain. A cave
    // player's landscape trace can hit a surface above/below the actual floor.
    if (pc.GetPlayerPawn() == none || pc.GetPlayerPawn().IsInCave() || pc.GetPlayerPawn().IsInLavaCave()) {
        if (StartupChecks >= 120) {
            ClearTimer('EnsureCompanion'); LogInternal("KEVIN STARTUP DEFERRED surface player required");
        }
        return;
    }
    registry = Spawn(RegistryClass);
    if (registry == none) { ClearTimer('EnsureCompanion'); LogInternal("KEVIN STARTUP registry spawn failed"); return; }
    for (i = 0; i < 8; i++) {
        direction.Yaw = pc.Pawn.Rotation.Yaw + 16384 + i * 8192;
        spawnLocation = pc.Pawn.Location + vector(direction) * 300;
        spawnLocation = class'ColdPositionHelper'.static.GetPathingLocationFromLoc(
            pc.Pawn, spawnLocation, true, 300, false, false, false, false);
        if (spawnLocation != vect(0,0,0) && Abs(spawnLocation.Z - pc.Pawn.Location.Z) <= 200 &&
            registry.CreateCompanion(pc, spawnLocation)) {
            ClearTimer('EnsureCompanion');
            pc.PrintToConsole("Kevin is following. Interact with him to open his inventory.");
            return;
        }
    }
    registry.Destroy();
    if (StartupChecks >= 120) { ClearTimer('EnsureCompanion'); LogInternal("KEVIN STARTUP BLOCKED no safe nearby location"); }
}

function KevinHunterController FindCompanion(ColdPlayerController pc)
{
    local KevinHunterController companion;
    foreach DynamicActors(class'KevinHunterController', companion) {
        if (companion.CompanionOwner == pc && companion.Pawn != none &&
            companion.Pawn.Health > 0 && !companion.bDeleteMe) { return companion; }
    }
    return none;
}

function Mutate(string MutateString, PlayerController Sender)
{
    local ColdPlayerController pc;
    local KevinHunterController companion;
    local KevinRegistry registry;
    if (!(MutateString ~= "Kevin") && !(MutateString ~= "KevinFollow") &&
        !(MutateString ~= "KevinWait") && !(MutateString ~= "KevinStatus") &&
        !(MutateString ~= "KevinTest") && !(MutateString ~= "KevinInventory")) {
        super.Mutate(MutateString, Sender); return;
    }
    pc = ReadyPlayer();
    if (pc == none || Sender != pc) {
        LogInternal("KEVIN COMMAND REFUSED no ready standalone player"); return;
    }
    if (MutateString ~= "KevinTest") {
        if (!IsIsolatedFixtureSession()) {
            pc.PrintToConsole("Kevin tests require the separate isolated test entrypoint."); return;
        }
        if (ActiveFixture != none && !ActiveFixture.bDeleteMe) {
            pc.PrintToConsole("Kevin test already running."); return;
        }
        ActiveFixture = Spawn(FixtureClass, self); return;
    }
    if (!class'KevinActivation'.static.IsEnabled()) {
        pc.PrintToConsole("Kevin is disabled in this session. Stored companion data is retained."); return;
    }
    companion = FindCompanion(pc);
    if (MutateString ~= "KevinStatus") {
        if (companion != none) {
            pc.PrintToConsole("Kevin: " $ (companion.GetFollowingOrder() ? "following" : "waiting") $
                ", health=" $ string(companion.Pawn.Health) $
                ", distance=" $ string(int(VSize(companion.Pawn.Location - pc.Pawn.Location))));
        } else {
            pc.PrintToConsole("No active Kevin companion.");
        }
        foreach DynamicActors(class'KevinRegistry', registry) {
            if (registry.bInitialized) {
                pc.PrintToConsole("Kevin save: pending=" $ string(registry.bRestorePending) $
                    ", disabled=" $ string(registry.bDormantDisabled) $
                    ", failed=" $ string(registry.bRestoreFailed) $
                    ", dead=" $ string(registry.bCompanionDead));
            }
        }
        return;
    }
    if (companion == none) { pc.PrintToConsole("Kevin is unavailable; use mutate KevinStatus for saved status."); return; }
    if (MutateString ~= "KevinInventory") { pc.AccessItem(companion.Pawn); return; }
    if (MutateString ~= "Kevin") {
        companion.SetFollowing(!companion.GetFollowingOrder());
        pc.PrintToConsole(companion.GetFollowingOrder() ? "Kevin: following." : "Kevin: waiting."); return;
    }
    companion.SetFollowing(MutateString ~= "KevinFollow");
    pc.PrintToConsole(companion.GetFollowingOrder() ? "Kevin: following." : "Kevin: waiting.");
}

function RunAutomaticTest()
{
    local ColdPlayerController pc;
    if (!IsIsolatedFixtureSession()) { ClearTimer('RunAutomaticTest'); return; }
    if (bFixtureStarted) {
        if (ActiveFixture != none && !ActiveFixture.bDeleteMe) { return; }
        ClearTimer('RunAutomaticTest');
        LogInternal("KEVIN AUTOMATIC FIXTURE FINISHED; inspect KEVIN_TEST_SUMMARY");
        if (bExitAfterTest) { SetTimer(1.0, false, 'ExitTest'); }
        return;
    }
    ReadinessChecks++;
    pc = ReadyPlayer();
    if (pc == none) {
        if (ReadinessChecks >= 120) {
            ClearTimer('RunAutomaticTest');
            LogInternal("KEVIN_TEST_FAIL no ready player after 120 seconds");
            if (bExitAfterTest) { SetTimer(1.0, false, 'ExitTest'); }
        }
        return;
    }
    bFixtureStarted = true;
    LogInternal("KEVIN AUTOMATIC FIXTURE START player=" $ string(pc));
    ActiveFixture = Spawn(FixtureClass, self);
    if (ActiveFixture == none) { LogInternal("KEVIN_TEST_FAIL fixture spawn returned None"); }
}

function ExitTest()
{
    local PlayerController pc;
    pc = GetALocalPlayerController();
    if (pc != none) { pc.ConsoleCommand("quit"); }
}

defaultproperties
{
    RegistryClass=class'KevinRegistry'
    GroupNames(0)="KevinCompanion"
    bHidden=true
    RemoteRole=ROLE_None
}
