// Player-local command menu and opt-in recall cursor. A closed recall HUD
// passes normal gameplay input through unchanged.
class KevinMenuInput extends Interaction;

var KevinCommandMenu Menu;

function bool HandleKey(int ControllerId, name Key, EInputEvent EventType,
    optional float AmountDepressed = 1.0, optional bool bGamepad)
{
    if (Menu == none || Menu.PlayerRef == none ||
        LocalPlayer(Menu.PlayerRef.Player) == none ||
        ControllerId != LocalPlayer(Menu.PlayerRef.Player).ControllerId) { return false; }
    if (Menu.bRecallHud) {
        // A native modal can pause world ticks. Release our cursor on input
        // as well, so it never intercepts that menu while waiting for Tick.
        if (Menu.bRecallCursor && !Menu.CanUseRecallHud()) { Menu.SetRecallCursor(false); return false; }
        if (Key == 'F6' && EventType == IE_Pressed) {
            if (Menu.bRecallCursor) { Menu.SetRecallCursor(false); return true; }
            return Menu.SetRecallCursor(true);
        }
        if (!Menu.bRecallCursor || EventType == IE_Released) { return false; }
        if (EventType != IE_Pressed) { return true; }
        if (Key == 'Escape' || Key == 'RightMouseButton' || Key == 'XboxTypeS_B') {
            Menu.SetRecallCursor(false); return true;
        }
        if (Key == 'LeftMouseButton' && Menu.HitRecall(Menu.CursorX, Menu.CursorY)) { Menu.ExecuteRecall(); }
        return true;
    }
    if (!Menu.bOpen) { return false; }
    // Let released movement/crouch keys clear their normal held state.
    if (EventType == IE_Released) { return false; }
    if (EventType != IE_Pressed && EventType != IE_Repeat) { return true; }
    if (Key == 'Escape' || Key == 'RightMouseButton' || Key == 'XboxTypeS_B') {
        Menu.CloseMenu(); return true;
    }
    if (Key == 'Up' || Key == 'XboxTypeS_DPad_Up' || Key == 'MouseScrollUp') {
        Menu.SelectedRow = (Menu.SelectedRow + 4) % 5; return true;
    }
    if (Key == 'Down' || Key == 'XboxTypeS_DPad_Down' || Key == 'MouseScrollDown') {
        Menu.SelectedRow = (Menu.SelectedRow + 1) % 5; return true;
    }
    if (EventType != IE_Pressed) { return true; }
    if (Key == 'Enter' || Key == 'XboxTypeS_A') { Menu.ExecuteRow(Menu.SelectedRow); return true; }
    if (Key == 'LeftMouseButton') {
        if (Menu.HitRow(Menu.CursorX, Menu.CursorY) >= 0) {
            Menu.ExecuteRow(Menu.HitRow(Menu.CursorX, Menu.CursorY));
        }
        return true;
    }
    if (Key == 'One' || Key == 'NumPadOne') { Menu.ExecuteRow(0); }
    else if (Key == 'Two' || Key == 'NumPadTwo') { Menu.ExecuteRow(1); }
    else if (Key == 'Three' || Key == 'NumPadThree') { Menu.ExecuteRow(2); }
    else if (Key == 'Four' || Key == 'NumPadFour') { Menu.ExecuteRow(3); }
    else if (Key == 'Five' || Key == 'NumPadFive') { Menu.ExecuteRow(4); }
    return true;
}

function bool HandleAxis(int ControllerId, name Key, float Delta, float DeltaTime,
    optional bool bGamepad)
{
    local int hover;
    if (Menu == none || (!Menu.bOpen && !Menu.bRecallCursor) || Menu.PlayerRef == none ||
        LocalPlayer(Menu.PlayerRef.Player) == none ||
        ControllerId != LocalPlayer(Menu.PlayerRef.Player).ControllerId) { return false; }
    if (Menu.bRecallHud && !Menu.CanUseRecallHud()) { Menu.SetRecallCursor(false); return false; }
    if (Key == 'MouseX') { Menu.CursorX = FClamp(Menu.CursorX + Delta, 0, Menu.ViewWidth - 1); }
    else if (Key == 'MouseY') { Menu.CursorY = FClamp(Menu.CursorY - Delta, 0, Menu.ViewHeight - 1); }
    if (Key == 'MouseX' || Key == 'MouseY') {
        hover = Menu.HitRow(Menu.CursorX, Menu.CursorY);
        if (hover >= 0) { Menu.SelectedRow = hover; }
    }
    return true;
}

function bool HandleChar(int ControllerId, string Unicode)
{
    if (Menu != none && Menu.bRecallHud && Menu.bRecallCursor && !Menu.CanUseRecallHud()) {
        Menu.SetRecallCursor(false); return false;
    }
    return Menu != none && (Menu.bOpen || Menu.bRecallCursor) && Menu.PlayerRef != none &&
        LocalPlayer(Menu.PlayerRef.Player) != none &&
        ControllerId == LocalPlayer(Menu.PlayerRef.Player).ControllerId;
}

function NotifyGameSessionEnded()
{
    if (Menu != none) { Menu.CloseMenu(); }
    Menu = none;
}

defaultproperties
{
    OnReceivedNativeInputKey=HandleKey
    OnReceivedNativeInputAxis=HandleAxis
    OnReceivedNativeInputChar=HandleChar
}
