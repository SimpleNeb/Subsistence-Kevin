// Own Canvas UI over the existing HUD. No replacement player/HUD or Flash assets.
class KevinCommandMenu extends Actor;

var KevinCompanionPawn Kevin;
var ColdPlayerController PlayerRef;
var HUD HudRef;
var KevinMenuInput Input;
var bool bOpen;
var bool bInputLocked;
var bool bClosing;
var ColdPlayerQuickActions QuickActionsRef;
var bool bQuickActionsWereEnabled;
var int SelectedRow;
var int PlayerHealthAtOpen;
var int KevinHealthAtOpen;
var float CursorX, CursorY, ViewWidth, ViewHeight;
var float PanelX, PanelY, PanelWidth, RowY, RowHeight, UiScale;
var string Feedback;
var int RenderedFrames;
// Player-local, unsaved recall overlay. The registry outlives Kevin's pawn.
var KevinRegistry RecallRegistry;
var bool bRecallHud;
var bool bRecallCursor;

function bool InitializeRecallHud(KevinRegistry registry, ColdPlayerController pc)
{
    local vector2d size;
    if (registry == none || pc == none || pc.MyHUD == none || LocalPlayer(pc.Player) == none) { return false; }
    RecallRegistry = registry; PlayerRef = pc; HudRef = pc.MyHUD;
    bRecallHud = true;
    LocalPlayer(pc.Player).ViewportClient.GetViewportSize(size);
    ViewWidth = size.X; ViewHeight = size.Y;
    Input = new(pc) class'KevinMenuInput';
    Input.Menu = self; Input.Init(); Input.OnInitialize();
    pc.Interactions.InsertItem(0, Input);
    HudRef.AddPostRenderedActor(self);
    return true;
}

function bool CanUseRecallHud()
{
    local KevinCompanionPawn p;
    if (!bRecallHud || bClosing || RecallRegistry == none || RecallRegistry.bDeleteMe ||
        !RecallRegistry.IsRuntimeEnabled() || PlayerRef == none || PlayerRef.bDeleteMe ||
        PlayerRef != RecallRegistry.FindCompanionOwner() || PlayerRef.MyHUD != HudRef ||
        HudRef == none || !HudRef.bShowHUD || PlayerRef.GetPlayerPawn() == none ||
        PlayerRef.Pawn.bDeleteMe || PlayerRef.Pawn.Health <= 0 ||
        !RecallRegistry.IsRecallPlayerUiReady(PlayerRef)) { return false; }
    p = KevinCompanionPawn(RecallRegistry.CompanionPawn);
    return p == none || p.KevinOrdersMenu == none || p.KevinOrdersMenu.bDeleteMe;
}

function bool SetRecallCursor(bool enabled)
{
    if (!bRecallHud || enabled == bRecallCursor) { return false; }
    if (enabled) {
        if (!CanUseRecallHud()) { return false; }
        bRecallCursor = true;
        CursorX = PanelX + PanelWidth * 0.5;
        CursorY = RowY + RowHeight * 0.5;
        PlayerRef.IgnoreMoveInput(true); PlayerRef.IgnoreLookInput(true);
        bInputLocked = true;
        PlayerRef.Pawn.StopFiring();
        PlayerHealthAtOpen = PlayerRef.Pawn.Health;
        QuickActionsRef = PlayerRef.GetPlayerPawn().QuickActions;
        if (QuickActionsRef != none) {
            bQuickActionsWereEnabled = QuickActionsRef.bEnabled;
            QuickActionsRef.bEnabled = false;
            QuickActionsRef.ClearAllInReach(); QuickActionsRef.HandleShowCrosshair(none);
        }
    } else {
        bRecallCursor = false;
        if (PlayerRef != none && bInputLocked) {
            PlayerRef.IgnoreMoveInput(false); PlayerRef.IgnoreLookInput(false);
        }
        bInputLocked = false;
        if (QuickActionsRef != none && !QuickActionsRef.bDeleteMe) {
            QuickActionsRef.bEnabled = bQuickActionsWereEnabled;
            QuickActionsRef.ClearAllInReach();
        }
        QuickActionsRef = none;
    }
    return true;
}

function bool HitRecall(float x, float y)
{
    return bRecallHud && RowHeight > 0 && x >= PanelX + 8 * UiScale &&
        x <= PanelX + PanelWidth - 8 * UiScale && y >= RowY && y <= RowY + RowHeight;
}

function bool ExecuteRecall()
{
    local bool result;
    if (!bRecallCursor || !CanUseRecallHud()) { return false; }
    SetRecallCursor(false);
    result = RecallRegistry.RequestRecall(PlayerRef, Feedback);
    if (PlayerRef.GetHudMgr() != none) { PlayerRef.GetHudMgr().Message(Feedback); }
    LogInternal("KEVIN HUD RECALL result=" $ string(result) $ " reason=" $ Feedback);
    return result;
}

function RenderRecallHud(Canvas c)
{
    local string status;
    local float distance;
    if (!CanUseRecallHud()) { return; }
    ViewWidth = c.SizeX; ViewHeight = c.SizeY;
    UiScale = FClamp(FMin(ViewWidth / 1280.0, ViewHeight / 720.0), 0.65, 1.25);
    PanelWidth = 260 * UiScale;
    PanelX = ViewWidth - PanelWidth - 20 * UiScale;
    PanelY = 110 * UiScale;
    RowY = PanelY + 52 * UiScale; RowHeight = 28 * UiScale;
    c.SetPos(PanelX, PanelY); c.SetDrawColor(9, 18, 15, 218); c.DrawRect(PanelWidth, 88 * UiScale);
    c.SetPos(PanelX, PanelY); c.SetDrawColor(158, 189, 125, 255); c.DrawRect(PanelWidth, 2 * UiScale);
    c.Font = class'Engine'.static.GetSmallFont();
    DrawLabel(c, PanelX + 12 * UiScale, PanelY + 9 * UiScale, "KEVIN", 231, 238, 218, 0.95);
    status = RecallRegistry.GetRecallStatus();
    if (!RecallRegistry.bCompanionDead && RecallRegistry.CompanionPawn != none) {
        distance = VSize(RecallRegistry.CompanionPawn.Location - PlayerRef.Pawn.Location);
        status $= distance <= 600 ? " - nearby" : " - away";
    }
    DrawLabel(c, PanelX + 12 * UiScale, PanelY + 30 * UiScale, status, 168, 188, 165, 0.78);
    c.SetPos(PanelX + 8 * UiScale, RowY);
    if (bRecallCursor && HitRecall(CursorX, CursorY)) { c.SetDrawColor(60, 86, 52, 255); }
    else { c.SetDrawColor(30, 49, 34, 255); }
    c.DrawRect(PanelWidth - 16 * UiScale, RowHeight);
    DrawLabel(c, PanelX + 16 * UiScale, RowY + 7 * UiScale,
        bRecallCursor ? "CLICK: RECALL KEVIN" : "F6: RECALL KEVIN", 234, 239, 226, 0.82);
    if (bRecallCursor) {
        DrawLabel(c, PanelX, PanelY + 94 * UiScale, "F6 / Esc / right-click: cancel", 216, 216, 190, 0.72);
        if (RecallRegistry.bCompanionDead) {
            DrawLabel(c, PanelX, PanelY + 113 * UiScale, "His equipment stays in his death bag.", 216, 195, 144, 0.68);
        }
        c.SetDrawColor(238, 238, 210, 255); c.SetPos(CursorX - 5, CursorY - 1);
        c.DrawRect(11, 3); c.SetPos(CursorX - 1, CursorY - 5); c.DrawRect(3, 11);
    }
    RenderedFrames++;
}

static function bool OpenFor(KevinCompanionPawn p, ColdPlayerController pc)
{
    local KevinCommandMenu menu;
    if (p == none || !p.IsKevinOwnerInReach(pc) || p.IsKevinInventoryBusy() ||
        pc.MyHUD == none || LocalPlayer(pc.Player) == none ||
        ColdPlayerPawn(pc.Pawn) == none || ColdPlayerPawn(pc.Pawn).bInHud) { return false; }
    if (p.KevinOrdersMenu != none && !p.KevinOrdersMenu.bDeleteMe) { return true; }
    menu = p.Spawn(class'KevinCommandMenu', p);
    if (menu == none) { return false; }
    p.KevinOrdersMenu = menu;
    if (!menu.Initialize(p, pc)) { menu.Destroy(); return false; }
    return true;
}

function bool Initialize(KevinCompanionPawn p, ColdPlayerController pc)
{
    local vector2d size;
    local KevinHunterController c;
    if (p == none || !p.IsKevinOwnerInReach(pc) || pc.MyHUD == none ||
        LocalPlayer(pc.Player) == none) { return false; }
    c = KevinHunterController(p.Controller);
    if (c == none) { return false; }
    Kevin = p;
    PlayerRef = pc;
    HudRef = pc.MyHUD;
    LocalPlayer(pc.Player).ViewportClient.GetViewportSize(size);
    ViewWidth = size.X; ViewHeight = size.Y;
    CursorX = ViewWidth * 0.5; CursorY = ViewHeight * 0.5;
    Input = new(pc) class'KevinMenuInput';
    Input.Menu = self;
    Input.Init();
    Input.OnInitialize();
    pc.Interactions.InsertItem(0, Input);
    pc.IgnoreMoveInput(true); pc.IgnoreLookInput(true);
    bInputLocked = true;
    pc.Pawn.StopFiring();
    PlayerHealthAtOpen = pc.Pawn.Health;
    KevinHealthAtOpen = p.Health;
    c.SetCommandMenuOpen(true);
    bOpen = true;
    QuickActionsRef = ColdPlayerPawn(pc.Pawn).QuickActions;
    if (QuickActionsRef != none) {
        bQuickActionsWereEnabled = QuickActionsRef.bEnabled;
        QuickActionsRef.bEnabled = false;
        QuickActionsRef.ClearAllInReach();
        QuickActionsRef.HandleShowCrosshair(none);
    }
    HudRef.AddPostRenderedActor(self);
    LogInternal("KEVIN MENU OPEN player=" $ string(pc) $ " companion=" $ string(p));
    return true;
}

function CloseMenu()
{
    local KevinHunterController c;
    // Destroyed is invoked synchronously before native bDeleteMe is reliable.
    // Clean up once even when the native destruction callback reenters here.
    if (bClosing) { return; }
    if (bRecallCursor) { SetRecallCursor(false); }
    bClosing = true;
    bOpen = false;
    if (HudRef != none) { HudRef.RemovePostRenderedActor(self); }
    if (PlayerRef != none) {
        if (Input != none) { PlayerRef.Interactions.RemoveItem(Input); }
        if (bInputLocked) { PlayerRef.IgnoreMoveInput(false); PlayerRef.IgnoreLookInput(false); }
    }
    bInputLocked = false;
    if (QuickActionsRef != none && !QuickActionsRef.bDeleteMe) {
        QuickActionsRef.bEnabled = bQuickActionsWereEnabled;
        QuickActionsRef.ClearAllInReach();
    }
    QuickActionsRef = none;
    if (Input != none) { Input.Menu = none; }
    Input = none;
    if (Kevin != none) {
        if (Kevin.KevinOrdersMenu == self) { Kevin.KevinOrdersMenu = none; }
        c = KevinHunterController(Kevin.Controller);
        if (c != none && !c.bDeleteMe) { c.SetCommandMenuOpen(false); }
    }
    if (!bDeleteMe) { Destroy(); }
}

simulated event Destroyed()
{
    CloseMenu();
    Kevin = none; RecallRegistry = none; PlayerRef = none; HudRef = none;
    super.Destroyed();
}

event Tick(float DeltaTime)
{
    if (bRecallHud) {
        if (RecallRegistry == none || RecallRegistry.bDeleteMe || !RecallRegistry.IsRuntimeEnabled() ||
            PlayerRef == none || PlayerRef.bDeleteMe || PlayerRef.MyHUD != HudRef ||
            PlayerRef != RecallRegistry.FindCompanionOwner()) { CloseMenu(); return; }
        if (bRecallCursor && (!CanUseRecallHud() || PlayerRef.Pawn.Health < PlayerHealthAtOpen)) { SetRecallCursor(false); }
        return;
    }
    if (!bOpen) { return; }
    if (Kevin == none || Kevin.bDeleteMe || Kevin.Health <= 0 ||
        PlayerRef == none || PlayerRef.bDeleteMe || PlayerRef.Pawn == none ||
        PlayerRef.Pawn.Health <= 0 || PlayerRef.MyHUD != HudRef ||
        ColdPlayerPawn(PlayerRef.Pawn) == none || ColdPlayerPawn(PlayerRef.Pawn).bInHud ||
        Kevin.Health < KevinHealthAtOpen || PlayerRef.Pawn.Health < PlayerHealthAtOpen ||
        VSize(Kevin.Location - PlayerRef.Pawn.Location) > 450) { CloseMenu(); }
}

function bool ExecuteRow(int row)
{
    local KevinHunterController c;
    local KevinCompanionPawn p;
    local ColdPlayerController pc;
    local string reason;
    local bool result;
    if (!bOpen || Kevin == none || !Kevin.IsKevinOwnerInReach(PlayerRef) ||
        Kevin.IsKevinInventoryBusy() || row < 0 || row > 4) { return false; }
    c = KevinHunterController(Kevin.Controller);
    if (c == none) { return false; }
    p = Kevin; pc = PlayerRef;
    if (row == 3 || row == 4) {
        result = c.StartGathering(row == 3 ? 'Wood' : 'Fiber', reason);
        if (!result) { Feedback = reason; return false; }
    } else if (row < 2) {
        c.SetFollowing(row == 0);
    }
    LogInternal("KEVIN MENU COMMAND row=" $ string(row));
    CloseMenu();
    if (row == 2) {
        // Crouch is only the menu-opening gesture, not an inventory restriction.
        p.bKevinOpeningInventory = true;
        pc.AccessItem(p);
        p.bKevinOpeningInventory = false;
        return p.bKevinInventoryOpen;
    }
    if (pc.GetHudMgr() != none) {
        pc.GetHudMgr().Message(row == 0 ? "Kevin is following you." :
            (row == 1 ? "Kevin is staying here." : "Kevin: " $ c.GetGatheringStatus()));
    }
    return true;
}

function int HitRow(float x, float y)
{
    local int row;
    if (RowHeight <= 0 || x < PanelX + 18 * UiScale ||
        x > PanelX + PanelWidth - 18 * UiScale || y < RowY) { return -1; }
    row = int((y - RowY) / RowHeight);
    if (row >= 0 && row < 5) { return row; }
    return -1;
}

function DrawLabel(Canvas c, float x, float y, string text, byte r, byte g, byte b,
    optional float size = 1.0)
{
    c.SetPos(x, y); c.SetDrawColor(r, g, b, 255);
    c.DrawText(text, false, UiScale * size, UiScale * size);
}

simulated event PostRenderFor(PlayerController pc, Canvas canvas, vector cameraPosition, vector cameraDir)
{
    local KevinHunterController c;
    local int i;
    local float y;
    local string title, rowHelp, status;
    if (bRecallHud && pc == PlayerRef && canvas != none) { RenderRecallHud(canvas); return; }
    if (!bOpen || pc != PlayerRef || Kevin == none || canvas == none) { return; }
    c = KevinHunterController(Kevin.Controller);
    if (c == none) { return; }
    ViewWidth = canvas.SizeX; ViewHeight = canvas.SizeY;
    UiScale = FMin(FMin(ViewWidth / 760.0, ViewHeight / 540.0), 1.25);
    PanelWidth = 590 * UiScale;
    PanelX = (ViewWidth - PanelWidth) * 0.5;
    PanelY = (ViewHeight - 420 * UiScale) * 0.5;
    RowHeight = 54 * UiScale;
    RowY = PanelY + 90 * UiScale;
    canvas.SetDrawColor(9, 18, 15, 242); canvas.SetPos(PanelX, PanelY);
    canvas.DrawRect(PanelWidth, 420 * UiScale);
    canvas.SetDrawColor(158, 189, 125, 255); canvas.SetPos(PanelX, PanelY);
    canvas.DrawRect(PanelWidth, 3 * UiScale);
    canvas.Font = class'Engine'.static.GetMediumFont();
    DrawLabel(canvas, PanelX + 24 * UiScale, PanelY + 18 * UiScale, "KEVIN", 231, 238, 218, 1.35);
    canvas.Font = class'Engine'.static.GetSmallFont();
    status = c.GetGatheringOrder() != '' ? c.GetGatheringStatus() :
        (c.GetFollowingOrder() ? "Following you" : "Staying here");
    DrawLabel(canvas, PanelX + 24 * UiScale, PanelY + 56 * UiScale, status, 168, 188, 165);
    for (i = 0; i < 5; i++) {
        y = RowY + i * RowHeight;
        canvas.SetPos(PanelX + 16 * UiScale, y);
        if (i == SelectedRow) { canvas.SetDrawColor(44, 70, 49, 255); }
        else { canvas.SetDrawColor(21, 35, 28, 255); }
        canvas.DrawRect(PanelWidth - 32 * UiScale, RowHeight - 4 * UiScale);
        switch (i) {
            case 0: title = "1   FOLLOW ME"; rowHelp = "Travel together. Kevin runs to catch up."; break;
            case 1: title = "2   STAY HERE"; rowHelp = "Wait here until you give another order."; break;
            case 2: title = "3   INVENTORY & EQUIPMENT"; rowHelp = "Carry supplies, equip weapons, and change clothing."; break;
            case 3: title = "4   GATHER WOOD"; rowHelp = c.HasUsableAxe() ? "Chop nearby trees with his supplied axe." : "Give Kevin a usable axe first."; break;
            case 4: title = "5   GATHER FIBER"; rowHelp = "Collect nearby fiber until his cargo is full."; break;
        }
        DrawLabel(canvas, PanelX + 30 * UiScale, y + 8 * UiScale, title, 234, 239, 226);
        DrawLabel(canvas, PanelX + 30 * UiScale, y + 29 * UiScale, rowHelp, 165, 184, 164, 0.82);
    }
    DrawLabel(canvas, PanelX + 24 * UiScale, PanelY + 365 * UiScale,
        Feedback != "" ? Feedback : "Click a command, press 1-5, or use arrows + Enter.", 216, 195, 144, 0.86);
    DrawLabel(canvas, PanelX + 24 * UiScale, PanelY + 391 * UiScale, "Esc / right-click: close", 152, 171, 151, 0.8);
    canvas.SetDrawColor(238, 238, 210, 255); canvas.SetPos(CursorX - 5, CursorY - 1);
    canvas.DrawRect(11, 3); canvas.SetPos(CursorX - 1, CursorY - 5); canvas.DrawRect(3, 11);
    RenderedFrames++;
}

defaultproperties
{
    bHidden=true
    bCollideActors=false
    bBlockActors=false
    bPostRenderIfNotVisible=true
    RemoteRole=ROLE_None
}
