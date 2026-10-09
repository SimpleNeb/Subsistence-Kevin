// Stable identity is release/config/KevinIdentity.json.
// Native mod selection is the production switch. Presence of the .u is not activation.
class KevinActivation extends Object config(Kevin);

const MOD_UUID = "20b4beb3-1cc9-48e8-bcfc-c41410f6fdbf";
const SUPPORTED_GAME_VERSION = "68.19";

// UDKGame/Config/UDKKevin.ini, [KevinCompanion.KevinActivation].
// The installer disables gameplay while retaining this package for saved records.
var config bool bLoaderEnabled;

static function bool HasSessionManager()
{
    local WorldInfo wi;
    wi = class'WorldInfo'.static.GetWorldInfo();
    // Do not call GetInst in the menu or before InitGame has created the manager:
    // native GetInst emits an error and ScriptTrace when no manager exists.
    return wi != none && wi.NetMode == NM_Standalone && ColdGame(wi.Game) != none &&
        !class'ColdGame'.static.IsMenuMap() && ColdGame(wi.Game).ModManager != none;
}

static function bool IsEnabled()
{
    local ColdModManager manager;
    if (!default.bLoaderEnabled) { return false; }
    if (!HasSessionManager()) { return false; }
    // Steam can update the game after installation. Saved registry classes must
    // remain available, but unvalidated builds retain dormant data rather than
    // instantiate an AI or touch its inventory with potentially changed APIs.
    if (class'ColdGame'.static.GetGameVersionStr() != SUPPORTED_GAME_VERSION) { return false; }
    manager = class'ColdModManager'.static.GetInst();
    return manager != none && manager.IsModActive(MOD_UUID);
}

// Config properties are supplied by the installer in UDKKevin.ini. With no
// installation config, activation is deliberately false.
