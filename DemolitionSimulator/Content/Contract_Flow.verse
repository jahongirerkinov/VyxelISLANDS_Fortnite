# =====================================================================
#  CONTRACT FLOW  —  one per location (city, arctic, zombieland...)
#
#  The loop:
#    1. Player walks into the hologram zone in the lobby -> prompt shows
#    2. They press the accept button -> a random building is raised at
#       that location's site and they're teleported there
#    3. Destruction inside the prop manipulator's zone is counted
#    4. They press the recall button on the truck -> paid, sent back to
#       the lobby, the wreckage is cleared
#
#  SETUP
#    HologramZone    - mutator zone around the lobby hologram
#    AcceptButton    - button beside the hologram
#    ToSite          - teleporter to the location
#    ToLobby         - teleporter back
#    RecallButton    - button on the truck at the location
#    Buildings       - that location's building_rotation_device
#    PropManipulator - the zone device over the construction site
#    Economy         - the player_economy_device
#
#  ONE CONTRACT AT A TIME: the site has a single building, so a second
#  player accepting while one is active would fight over it. Accepting is
#  refused while a contract is running.
#
#  # VERIFY: mutator_zone_device Agent enters/exits events, button
#  InteractedWithEvent, teleporter_device.Teleport(agent).
# =====================================================================

using { /Fortnite.com/Devices }
using { /Fortnite.com/UI }
using { /Verse.org/Assets }
using { /UnrealEngine.com/Temporary/SpatialMath }
using { /UnrealEngine.com/Temporary/UI }
using { /Verse.org/Simulation }
using { /UnrealEngine.com/Temporary/Diagnostics }

contract_flow_device := class(creative_device):

    @editable LocationName : string = "CITY"

    @editable HologramZone : mutator_zone_device = mutator_zone_device{}
    @editable AcceptButton : button_device = button_device{}
    @editable RecallButton : button_device = button_device{}

    @editable ToSite : teleporter_device = teleporter_device{}
    @editable ToLobby : teleporter_device = teleporter_device{}

    @editable Buildings : building_rotation_device = building_rotation_device{}
    @editable PropManipulator : prop_manipulator_device = prop_manipulator_device{}
    @editable Economy : player_economy_device = player_economy_device{}

    # This location's truck charges.
    @editable Dynamite : location_dynamite_device = location_dynamite_device{}

    # Paid per piece destroyed.
    @editable PayPerPiece : float = 25.0
    # Extra for reaching the target before recalling.
    @editable TargetPieces : int = 40
    @editable CompletionBonus : float = 500.0

    var Active : logic = false
    var Destroyed : int = 0
    var Worker : ?agent = false
    var Huds : [player]contract_hud = map{}
    var AcceptUIs : [player]accept_ui = map{}

    OnBegin<override>()<suspends> : void =
        Print("[Contract:{LocationName}] Ready.")
        HologramZone.AgentEntersEvent.Subscribe(OnEnterHologram)
        HologramZone.AgentExitsEvent.Subscribe(OnExitHologram)
        AcceptButton.InteractedWithEvent.Subscribe(OnAccept)   # optional physical button
        RecallButton.InteractedWithEvent.Subscribe(OnRecall)
        PropManipulator.DestroyedEvent.Subscribe(OnPropDestroyed)

    # ---------------- Hologram prompt ----------------
    OnEnterHologram(Agent : agent) : void =
        if (P := player[Agent]):
            if (Active?):
                GetHud(P).Show("{LocationName} — contract already in progress")
            else:
                GetAcceptUI(P).Open()
                Economy.SetHudVisible(Agent, false)

    OnExitHologram(Agent : agent) : void =
        if (P := player[Agent]):
            CloseAcceptUI(P)
            if (H := Huds[P]):
                if (not Active?):
                    H.Hide()

    CloseAcceptUI(P : player) : void =
        if (Panel := AcceptUIs[P]):       # not 'UI' - that's the assets module
            Panel.Close()
        Economy.SetHudVisible(P, true)

    # Fired by the widget's accept button.
    OnAcceptPressed(P : player) : void =
        if (not Active?):
            CloseAcceptUI(P)
            OnAccept(P)

    # ---------------- Accept ----------------
    OnAccept(Agent : agent) : void =
        if (Active?):
            Print("[Contract:{LocationName}] Refused - already running.")
        else:
            set Active = true
            set Destroyed = 0
            set Worker = option{Agent}
            Buildings.RaiseRandom()
            Dynamite.DeployFor(Agent)       # charges appear on the truck
            ToSite.Teleport(Agent)          # VERIFY: teleporter_device.Teleport(agent)
            if (P := player[Agent]):
                GetHud(P).Show("{LocationName}  —  0 destroyed")
            Print("[Contract:{LocationName}] Accepted.")

    # ---------------- Demolition ----------------
    OnPropDestroyed(Agent : agent) : void =
        if (Active?):
            set Destroyed = Destroyed + 1
            if (W := Worker?):
                if (P := player[W]):
                    GetHud(P).Show(ProgressText())

    ProgressText()<transacts> : string =
        "{LocationName}  —  {Destroyed} / {TargetPieces} destroyed"

    # ---------------- Recall ----------------
    OnRecall(Agent : agent) : void =
        if (Active?):
            Pay := Payout()
            Economy.AddMoney(Agent, Pay)
            ToLobby.Teleport(Agent)
            Buildings.ParkCurrent()         # clear the wreckage
            Dynamite.ClearAll()             # despawn any unused charges
            set Active = false
            set Worker = false
            if (P := player[Agent]):
                GetHud(P).Hide()
            Print("[Contract:{LocationName}] Recalled. Paid {Pay} for {Destroyed}.")

    Payout()<transacts> : float =
        var Total : float = 0.0
        for (I := 0..Destroyed - 1):
            set Total = Total + PayPerPiece
        if (Destroyed >= TargetPieces):
            set Total = Total + CompletionBonus
        Total

    GetAcceptUI(P : player) : accept_ui =
        if (Panel := AcceptUIs[P]):
            return Panel
        New := accept_ui{}
        if (PlayerUI := GetPlayerUI[P]):
            New.Init(PlayerUI)
            spawn{ WatchAccept(P, New) }
        if (set AcceptUIs[P] = New) {}
        return New

    # One loop per player, waiting on their panel's accept button.
    WatchAccept(P : player, Panel : accept_ui)<suspends> : void =
        loop:
            Panel.WaitForPress()
            OnAcceptPressed(P)

    # ---------------- Prompt widget ----------------
    GetHud(P : player) : contract_hud =
        if (H := Huds[P]):
            return H
        New := contract_hud{}
        if (PlayerUI := GetPlayerUI[P]):
            New.Build(PlayerUI)
        if (set Huds[P] = New) {}
        return New

# The ContractAcceptUI_WB panel. Its AcceptContractButton_Var is an
# event, so it's AWAITED in a loop rather than subscribed to.
accept_ui := class:
    Widget : UI.ContractAcceptUI_WB = UI.ContractAcceptUI_WB{}

    var MaybeUI : ?player_ui = false
    var Open_ : logic = false

    Init(PlayerUI : player_ui) : void =
        set MaybeUI = option{PlayerUI}

    # Blocks until the widget's accept button fires.
    WaitForPress()<suspends> : void =
        Widget.AcceptContractButton_Var.Await()

    Open() : void =
        if (PlayerUI := MaybeUI?):
            if (not Open_?):
                # Input mode All so the button can be clicked.
                PlayerUI.AddWidget(Widget, player_ui_slot{ InputMode := ui_input_mode.All })
                set Open_ = true

    Close() : void =
        if (PlayerUI := MaybeUI?):
            if (Open_?):
                PlayerUI.RemoveWidget(Widget)
                set Open_ = false

contract_hud := class:
    Text : text_block = text_block{}

    Build(PC : player_ui) : void =
        Canvas := canvas:
            Slots := array:
                canvas_slot:
                    Anchors := anchors{ Minimum := vector2{ X := 0.5, Y := 0.0 }, Maximum := vector2{ X := 0.5, Y := 0.0 } }
                    Alignment := vector2{ X := 0.5, Y := 0.0 }
                    Offsets := margin{ Top := 120.0, Left := 0.0, Right := 0.0, Bottom := 0.0 }
                    SizeToContent := true
                    Widget := Text
        PC.AddWidget(Canvas)
        Text.SetVisibility(widget_visibility.Hidden)

    Show(S : string) : void =
        Text.SetText(ContractMsg(S))
        Text.SetVisibility(widget_visibility.Visible)

    Hide() : void =
        Text.SetVisibility(widget_visibility.Hidden)

ContractMsg<localizes>(S : string) : message = "{S}"
