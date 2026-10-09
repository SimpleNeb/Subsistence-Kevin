// Native gear container: standing Use loots; crouch + Use revives its Kevin.
// The bag owns the dropped items. Revival never removes or clones its contents.
class KevinRevivalBag extends ColdLootContainer_PlayerGear dependson(_ColdStructs)
    implements(ColdInterfaceInteractable);

var KevinRegistry RevivalRegistry;
var int KevinOwnerPlayerId;
var int KevinDeathGeneration;
var bool bKevinFixtureBag;
var string LastRevivalPrompt;

function BindRevivalRegistry(KevinRegistry registry, int generation, bool testOnly)
{
    if (registry == none || generation <= 0) { return; }
    RevivalRegistry = registry;
    KevinOwnerPlayerId = registry.OwnerPlayerId;
    KevinDeathGeneration = generation;
    bKevinFixtureBag = testOnly;
}

simulated function KevinRegistry FindRevivalRegistry()
{
    local KevinRegistry registry;
    if (RevivalRegistry != none && !RevivalRegistry.bDeleteMe &&
        RevivalRegistry.bInitialized && RevivalRegistry.bCompanionDead &&
        RevivalRegistry.OwnerPlayerId == KevinOwnerPlayerId &&
        RevivalRegistry.DeathGeneration == KevinDeathGeneration) { return RevivalRegistry; }
    RevivalRegistry = none;
    if (KevinDeathGeneration <= 0) { return none; }
    foreach DynamicActors(class'KevinRegistry', registry) {
        if (!registry.bDeleteMe && registry.bInitialized && registry.bCompanionDead &&
            registry.OwnerPlayerId == KevinOwnerPlayerId && registry.DeathGeneration == KevinDeathGeneration) {
            RevivalRegistry = registry;
            return registry;
        }
    }
    return none;
}

simulated function bool IsReviveGesture(ColdPlayerController pc)
{
    local KevinRegistry registry;
    registry = FindRevivalRegistry();
    return WorldInfo.NetMode == NM_Standalone && registry != none && pc != none &&
        pc.GetPlayerPawn() != none && pc.Pawn.bIsCrouched && !pc.GetPlayerPawn().bInHud &&
        !bIsBeingAccessed && VSize(pc.Pawn.Location - Location) <= 350 && registry.CanRevive(pc);
}

simulated function bool IsAccessible(optional ColdPlayerController pcAccessing,
    optional out string cantAccessReason)
{
    if (pcAccessing == none) { pcAccessing = ColdPlayerController(GetALocalPlayerController()); }
    if (IsReviveGesture(pcAccessing)) { cantAccessReason = ""; return false; }
    return super.IsAccessible(pcAccessing, cantAccessReason);
}

// Native Use tries the locked-container route before Interactable whenever
// IsAccessible returns false. Gear bags are already open; a crouched revival
// gesture must not start the generic chest-unlocking progress meter.
simulated function bool CanPlayerUnlock(ColdPlayerController pc, optional bool bNotifyHudIfCantUnlock = false)
{
    return false;
}

static function string GetAccessModulePreviewName() { return "Kevin's dropped equipment"; }

simulated function GetActionIconData(out string actionIcon, out string actionText,
    out InputGlyphData inputGlyph, out InputPromptImageData promptImg)
{
    super.GetActionIconData(actionIcon, actionText, inputGlyph, promptImg);
    actionText = GetToggleText();
}

simulated function string GetActionIconImage() { return "img://ColdHudImageLibrary.ActionIcon_Inventory"; }

simulated function string GetToggleText()
{
    local KevinRegistry registry;
    registry = FindRevivalRegistry();
    if (IsReviveGesture(ColdPlayerController(GetALocalPlayerController()))) {
        return "Revive Kevin here (equipment stays in bag)";
    }
    if (registry != none && registry.IsRuntimeEnabled()) {
        return "Kevin's gear: crouch to revive / return in " $ string(registry.GetRevivalSecondsRemaining()) $ "s";
    }
    return "Kevin's dropped equipment";
}

simulated function NotifyPlayerLookingAt(vector hitLoc, TraceHitInfo hitInfo) {}

simulated function byte GetInteractionCommandId()
{
    return IsReviveGesture(ColdPlayerController(GetALocalPlayerController())) ? 1 : 0;
}

simulated function bool CanClientInteract(ColdPlayerPawn actingPawn, byte interactionCmdId)
{
    return interactionCmdId == 1 && actingPawn != none &&
        IsReviveGesture(ColdPlayerController(actingPawn.Controller));
}

simulated function bool PreAskServerToInteract(byte interactionCmdId, ColdPlayerController interactingPlayer)
{
    return interactingPlayer != none && CanClientInteract(ColdPlayerPawn(interactingPlayer.Pawn), interactionCmdId);
}

function InteractWithItem(ColdPlayerPawn actingPawn, byte interactionCmdId)
{
    local KevinRegistry registry;
    local ColdPlayerController pc;
    if (Role != ROLE_Authority || !CanClientInteract(actingPawn, interactionCmdId)) { return; }
    registry = FindRevivalRegistry();
    pc = ColdPlayerController(actingPawn.Controller);
    if (registry != none && !registry.RequestRevival(pc) && pc != none && pc.GetHudMgr() != none) {
        pc.GetHudMgr().Message("No safe place for Kevin here yet. Clear the area or wait for his return.");
    }
}

simulated function bool HasChangedSinceLastTick()
{
    local string prompt;
    prompt = GetToggleText();
    if (prompt == LastRevivalPrompt) { return false; }
    LastRevivalPrompt = prompt;
    return true;
}

function bool ShouldMasterSaveStateHandleSave()
{
    return !bKevinFixtureBag && super.ShouldMasterSaveStateHandleSave();
}

function string Serialize()
{
    local JsonObject data;
    data = class'JsonObject'.static.DecodeJson(super.Serialize());
    if (data == none) { return ""; }
    data.SetIntValue("KevinOwnerPlayerId", KevinOwnerPlayerId);
    data.SetIntValue("KevinDeathGeneration", KevinDeathGeneration);
    return class'JsonObject'.static.EncodeJson(data);
}

function Deserialize(JsonObject data)
{
    if (data == none) { return; }
    KevinOwnerPlayerId = data.GetIntValue("KevinOwnerPlayerId");
    KevinDeathGeneration = data.GetIntValue("KevinDeathGeneration");
    super.Deserialize(data);
}
