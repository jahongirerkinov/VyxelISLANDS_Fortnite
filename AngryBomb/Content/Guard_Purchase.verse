# =====================================================================
#  GUARD PURCHASE  —  buy a guard NPC per team (one per round)
#
#  Each team has a Guard Spawner + a Conditional Button (diamond cost).
#  This device subscribes to each button's ActivatedEvent; on purchase it
#  spawns that team's guard and DISABLES the button (one-time per round).
#  Buttons re-enable when a new round starts (fresh economy each round).
#
#  SETUP: assign each team's Guard Spawner + Conditional Button, plus the
#  cart (used to detect round end).
#
#  STATUS: first pass. # VERIFY: the guard spawn call (Spawn()?) and the
#  conditional_button Disable()/Enable().
# =====================================================================

using { /Fortnite.com/Devices }
using { /Verse.org/Simulation }
using { /UnrealEngine.com/Temporary/Diagnostics }

guard_purchase_device := class(creative_device):

    @editable Cart : bomb_cart_device = bomb_cart_device{}

    # Each team's guard spawner + purchase button.
    @editable GuardSpawnerA : guard_spawner_device = guard_spawner_device{}   # Blue
    @editable GuardSpawnerB : guard_spawner_device = guard_spawner_device{}   # Red
    @editable BuyButtonA : conditional_button_device = conditional_button_device{}
    @editable BuyButtonB : conditional_button_device = conditional_button_device{}

    # "Purchased" checkmark props - shown once bought, hidden next round.
    @editable CheckA : creative_prop = creative_prop{}   # Blue
    @editable CheckB : creative_prop = creative_prop{}   # Red

    var WasLive : logic = false      # for detecting round end -> re-enable buttons

    OnBegin<override>()<suspends> : void =
        Print("[GuardPurchase] Ready.")
        CheckA.Hide()                # checkmarks start hidden
        CheckB.Hide()
        BuyButtonA.ActivatedEvent.Subscribe(BuyGuardA)   # VERIFY: conditional_button_device.ActivatedEvent
        BuyButtonB.ActivatedEvent.Subscribe(BuyGuardB)
        # Re-buy on death: when a team's guard is eliminated, free up its
        # purchase again. EliminatedEvent is listenable(payload).
        GuardSpawnerA.EliminatedEvent.Subscribe(OnGuardDeadA)   # VERIFY: guard_spawner_device.EliminatedEvent (payload)
        GuardSpawnerB.EliminatedEvent.Subscribe(OnGuardDeadB)
        spawn{ WatchRounds() }

    # ---- Purchase handlers (agent = buyer). Spawn the guard + disable
    #      the button so it can't be bought again this round. ----
    BuyGuardA(Agent : agent) : void =
        GuardSpawnerA.Spawn()        # VERIFY: guard_spawner_device.Spawn()
        BuyButtonA.Disable()         # VERIFY: conditional_button_device.Disable()
        CheckA.Show()                # purchased checkmark on
        Print("[GuardPurchase] Blue guard bought.")

    BuyGuardB(Agent : agent) : void =
        GuardSpawnerB.Spawn()
        BuyButtonB.Disable()
        CheckB.Show()
        Print("[GuardPurchase] Red guard bought.")

    # ---- Guard death -> free up the purchase again (re-buyable mid-round).
    #      EliminatedEvent payload type is # VERIFY - if the compiler rejects
    #      device_ai_interaction_result, it will name the expected type. ----
    OnGuardDeadA(Result : device_ai_interaction_result) : void =
        BuyButtonA.Enable()          # guard died -> can buy another
        CheckA.Hide()
        Print("[GuardPurchase] Blue guard died - re-buyable.")

    OnGuardDeadB(Result : device_ai_interaction_result) : void =
        BuyButtonB.Enable()
        CheckB.Hide()
        Print("[GuardPurchase] Red guard died - re-buyable.")

    # Re-enable both buttons when a fresh round starts.
    WatchRounds()<suspends> : void =
        loop:
            HandleRoundReset()
            Sleep(0.25)

    HandleRoundReset() : void =
        if (Cart.MatchLive?):
            RegisterLive()
        else:
            set WasLive = false

    RegisterLive() : void =
        if (WasLive?):
            return                   # already counted this round
        CheckA.Hide()                # purchasable again next round
        CheckB.Hide()
        BuyButtonA.Enable()          # new round -> buying available again
        BuyButtonB.Enable()
        set WasLive = true
