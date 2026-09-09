# =====================================================================
#  PLAYER ECONOMY  —  owns every player's balance
#
#  The single source of truth for money. Other devices don't hold
#  balances of their own; they call the API here.
#
#  SCOPE: this device owns the BALANCE and the operations on it. It does
#  NOT own prices or what purchases do - a shop knows its own costs and
#  calls TrySpend, and this just answers yes or no. Keeping that line
#  stops it becoming a dumping ground for everything money-adjacent.
#
#  Also drives the EconomyHUD_WB widget's Money variable:
#
#     $543        under a thousand
#     $5.6k       thousands
#     $12.5M      millions
#     $1.4B       billions
#
#  Money is a FLOAT rather than an int: Verse has no int-to-float
#  conversion, and splitting a number into "whole" and "first decimal"
#  needs division, so ints would leave no way to format it.
#
#  PUBLIC API for other devices:
#     AddMoney(Agent, Amount)   - earn (or spend, with a negative)
#     TrySpend(Agent, Cost)     - returns logic; deducts only if affordable
#     GetMoney(Agent)           - current balance
#
#  NOTE: balances are in-session only. Persisting them means a player
#  weak_map, and Epic caps a project at two - worth deciding what else
#  needs persistence before spending one.
#
#  The widget's Money variable is a message, so strings are wrapped
#  through MoneyMsg before assignment.
# =====================================================================

using { /Fortnite.com/Devices }
using { /Fortnite.com/UI }
using { /UnrealEngine.com/Temporary/UI }
using { /Verse.org/Assets }
using { /Verse.org/Simulation }
using { /UnrealEngine.com/Temporary/Diagnostics }

player_economy_device := class(creative_device):

    # Every Player Spawner, so the HUD reaches players as they arrive.
    @editable Spawners : []player_spawner_device = array{}

    @editable StartingMoney : float = 0.0

    # How long the widget's change animations run. Match this to the
    # animation length set in the blueprint.
    @editable AnimSeconds : float = 0.3

    # ---- TESTING ONLY - remove these before publishing ----
    @editable TestAddButton : button_device = button_device{}
    @editable TestSpendButton : button_device = button_device{}
    @editable TestAmount : float = 100.0

    var Balances : [player]float = map{}
    var Huds : [player]money_hud = map{}

    OnBegin<override>()<suspends> : void =
        Print("[Economy] Ready.")
        for (P : GetPlayspace().GetPlayers()):
            Setup(P)
        for (S : Spawners):
            S.SpawnedEvent.Subscribe(OnSpawn)
        # Test buttons - remove with the fields above once the economy is
        # driven by real gameplay.
        TestAddButton.InteractedWithEvent.Subscribe(OnTestAdd)     # VERIFY: button_device.InteractedWithEvent
        TestSpendButton.InteractedWithEvent.Subscribe(OnTestSpend)

    OnSpawn(A : agent) : void =
        if (P := player[A]):
            Setup(P)

    Setup(P : player) : void =
        if (not Balances[P]):
            if (set Balances[P] = StartingMoney) {}
        if (not Huds[P]):
            if (PlayerUI := GetPlayerUI[P]):
                H := money_hud{}
                H.AddToPlayer(PlayerUI)
                if (set Huds[P] = H) {}
        Refresh(P)

    OnTestAdd(Agent : agent) : void =
        AddMoney(Agent, TestAmount)
        Print("[Economy] Test +{TestAmount}")

    OnTestSpend(Agent : agent) : void =
        OK := TrySpend(Agent, TestAmount)
        if (OK?):
            Print("[Economy] Test -{TestAmount}")
        else:
            Print("[Economy] Test spend refused - not enough money.")

    # ---------------- Public API ----------------
    AddMoney<public>(Agent : agent, Amount : float) : void =
        if (P := player[Agent]):
            New := GetMoneyFor(P) + Amount
            if (set Balances[P] = New) {}
            Refresh(P)
            # A negative amount is a spend, so play the right one.
            if (Amount < 0.0):
                PlayChange(P, false)
            else if (Amount > 0.0):
                PlayChange(P, true)

    # Returns true and deducts if they can afford it, false and changes
    # nothing otherwise. NOT <decides>: a failable function that also
    # writes picks up the no_rollback effect and can't be called from an
    # if-condition. Callers assign the result first, then branch on it.
    TrySpend<public>(Agent : agent, Cost : float) : logic =
        var OK : logic = false
        if (P := player[Agent]):
            Have := GetMoneyFor(P)
            if (Have >= Cost):
                if (set Balances[P] = Have - Cost) {}
                Refresh(P)
                PlayChange(P, false)
                set OK = true
        OK

    # Hide the money HUD while a full-screen UI is open.
    SetHudVisible<public>(Agent : agent, Visible : logic) : void =
        if (P := player[Agent]):
            if (H := Huds[P]):
                H.SetVisible(Visible)

    GetMoney<public>(Agent : agent) : float =
        var V : float = 0.0
        if (P := player[Agent]):
            set V = GetMoneyFor(P)
        V

    GetMoneyFor(P : player) : float =
        var V : float = 0.0
        if (B := Balances[P]):
            set V = B
        V

    Refresh(P : player) : void =
        if (H := Huds[P]):
            H.SetAmount(FormatMoney(GetMoneyFor(P)))

    PlayChange(P : player, Increase : logic) : void =
        if (H := Huds[P]):
            spawn{ H.PlayAnim(Increase, AnimSeconds) }

# Holds one player's widget instance.
money_hud := class:
    Widget : UI.EconomyHUD_WB = UI.EconomyHUD_WB{}

    var MaybeUI : ?player_ui = false
    var Shown : logic = false

    AddToPlayer(PlayerUI : player_ui) : void =
        set MaybeUI = option{PlayerUI}
        PlayerUI.AddWidget(Widget, player_ui_slot{ InputMode := ui_input_mode.None })
        set Shown = true

    # Pulled off screen while a full-screen UI is up, then put back.
    SetVisible(Visible : logic) : void =
        if (PlayerUI := MaybeUI?):
            if (Visible?):
                if (not Shown?):
                    PlayerUI.AddWidget(Widget, player_ui_slot{ InputMode := ui_input_mode.None })
                    set Shown = true
            else:
                if (Shown?):
                    PlayerUI.RemoveWidget(Widget)
                    set Shown = false

    SetAmount(Text : string) : void =
        set Widget.Money = MoneyMsg(Text)   # bound variable is a message

    # Animations are driven by setting their bound value to 1.0 and back
    # to 0.0 once they've run.
    PlayAnim(Increase : logic, Seconds : float)<suspends> : void =
        if (Increase?):
            set Widget.MoneyIncreaseAnimationFloat_Var = 1.0
            Sleep(Seconds)
            set Widget.MoneyIncreaseAnimationFloat_Var = 0.0
        else:
            set Widget.MoneyDecreaseAnimationFloat_Var = 1.0
            Sleep(Seconds)
            set Widget.MoneyDecreaseAnimationFloat_Var = 0.0

# $543 / $5.6k / $12.5M / $1.4B
# Each tier takes the whole part, then the first decimal by dividing to
# one place finer and subtracting the whole part shifted up.
FormatMoney(Amount : float) : string =
    var Out : string = "$0"
    if (Amount < 1000.0):
        if (W := Floor[Amount]):
            set Out = "${W}"
    else if (Amount < 1000000.0):
        if (W := Floor[Amount / 1000.0]):
            if (Tenths := Floor[Amount / 100.0]):
                D := Tenths - W * 10
                set Out = "${W}.{D}k"
    else if (Amount < 1000000000.0):
        if (W := Floor[Amount / 1000000.0]):
            if (Tenths := Floor[Amount / 100000.0]):
                D := Tenths - W * 10
                set Out = "${W}.{D}M"
    else:
        if (W := Floor[Amount / 1000000000.0]):
            if (Tenths := Floor[Amount / 100000000.0]):
                D := Tenths - W * 10
                set Out = "${W}.{D}B"
    Out

MoneyMsg<localizes>(S : string) : message = "{S}"
