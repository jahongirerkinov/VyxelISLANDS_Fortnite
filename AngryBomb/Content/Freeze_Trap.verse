# =====================================================================
#  FREEZE TRAP  —  purchasable, separate device, references the cart
#
#  Each side's trap starts HIDDEN + DISARMED. A team buys it via their
#  Conditional Button (diamond cost); this device SUBSCRIBES to each
#  button's ActivatedEvent, and on purchase SHOWS the trap prop + ARMS
#  it. When the bomb reaches an armed trap it freezes the cart (movement
#  only - counting keeps running), shows ice + VFX, then melts after
#  FreezeSeconds and HIDES + DISARMS the trap again (so the team must
#  re-buy to use it once more). All traps reset off when a round ends.
#
#  SETUP: assign each team's Conditional Button to BuyButtonA (blue) /
#  BuyButtonB (red). No editor event-binding needed - the code subscribes.
#
#  STATUS: first pass. # VERIFY: creative_prop Show()/Hide(), vfx calls,
#  and that ArmTrapA/ArmTrapB are bindable from the button event.
# =====================================================================

using { /Fortnite.com/Devices }
using { /Verse.org/Simulation }
using { /UnrealEngine.com/Temporary/SpatialMath }
using { /UnrealEngine.com/Temporary/Diagnostics }

freeze_trap_device := class(creative_device):

    @editable Cart : bomb_cart_device = bomb_cart_device{}

    # Each team's purchase button (diamond cost handled on the device).
    # We subscribe to their ActivatedEvent below.
    @editable BuyButtonA : conditional_button_device = conditional_button_device{}   # Blue
    @editable BuyButtonB : conditional_button_device = conditional_button_device{}   # Red

    # "Purchased" checkmark props - shown while the trap is armed (button
    # disabled), hidden when it's purchasable again.
    @editable CheckA : creative_prop = creative_prop{}   # Blue
    @editable CheckB : creative_prop = creative_prop{}   # Red

    # Trap props (the fridge). Shown on purchase, hidden after use / round end.
    @editable TrapPropA : creative_prop = creative_prop{}   # Blue side
    @editable TrapPropB : creative_prop = creative_prop{}   # Red side

    # Ice props - shown while frozen, hidden after melting.
    @editable IceA : creative_prop = creative_prop{}
    @editable IceB : creative_prop = creative_prop{}

    # VFX: freeze burst + melt burst per side.
    @editable FreezeVFXA : vfx_spawner_device = vfx_spawner_device{}
    @editable MeltVFXA : vfx_spawner_device = vfx_spawner_device{}
    @editable FreezeVFXB : vfx_spawner_device = vfx_spawner_device{}
    @editable MeltVFXB : vfx_spawner_device = vfx_spawner_device{}

    # Tuning.
    @editable FreezeSeconds : float = 3.0    # how long the bomb stays frozen
    @editable TriggerRadiusM : float = 1.5   # how close the bomb must be to the trap centre

    # State.
    var ArmedA : logic = false       # trap A purchased + active
    var ArmedB : logic = false
    var WasLive : logic = false      # for detecting round end
    var FreezeActive : logic = false # a freeze sequence is running

    OnBegin<override>()<suspends> : void =
        Print("[FreezeTrap] Ready.")
        # Everything hidden + disarmed at start.
        TrapPropA.Hide()             # VERIFY: creative_prop.Hide()
        TrapPropB.Hide()
        IceA.Hide()
        IceB.Hide()
        CheckA.Hide()                # checkmarks start hidden (nothing purchased)
        CheckB.Hide()
        # Purchases arm the traps. (ActivatedEvent handler takes an agent.)
        BuyButtonA.ActivatedEvent.Subscribe(ArmTrapA)   # VERIFY: conditional_button_device.ActivatedEvent
        BuyButtonB.ActivatedEvent.Subscribe(ArmTrapB)
        spawn{ WatchTraps() }

    # ---- Purchase handlers (subscribed to each button's ActivatedEvent).
    #      Arming also DISABLES that button so diamonds can't be wasted
    #      re-buying an already-armed trap; it re-enables after use. ----
    ArmTrapA(Agent : agent) : void =
        set ArmedA = true
        TrapPropA.Show()             # VERIFY: creative_prop.Show()
        BuyButtonA.Disable()         # VERIFY: conditional_button_device.Disable() - no re-buying while armed
        CheckA.Show()                # purchased checkmark on
        Print("[FreezeTrap] Blue trap armed.")

    ArmTrapB(Agent : agent) : void =
        set ArmedB = true
        TrapPropB.Show()
        BuyButtonB.Disable()
        CheckB.Show()
        Print("[FreezeTrap] Red trap armed.")

    WatchTraps()<suspends> : void =
        loop:
            HandleRoundReset()
            CheckTrapsIfLive()
            Sleep(0.1)

    # When a round ends, turn every trap off (fresh economy each round).
    HandleRoundReset() : void =
        if (Cart.MatchLive?):
            set WasLive = true
        else:
            EndRoundCleanup()

    EndRoundCleanup() : void =
        if (WasLive?):               # just transitioned live -> not-live
            DisarmAll()
        set WasLive = false

    DisarmAll() : void =
        set ArmedA = false
        set ArmedB = false
        TrapPropA.Hide()
        TrapPropB.Hide()
        CheckA.Hide()                # purchasable again next round
        CheckB.Hide()
        BuyButtonA.Enable()          # new round: buying is available again
        BuyButtonB.Enable()

    CheckTrapsIfLive() : void =
        if (Cart.MatchLive?):
            CheckTrapsNow()

    CheckTrapsNow() : void =
        if (FreezeActive?):
            return                   # one freeze at a time; don't stack
        CheckTrap(TrapPropA, IceA, FreezeVFXA, MeltVFXA, BuyButtonA, CheckA, 0)
        CheckTrap(TrapPropB, IceB, FreezeVFXB, MeltVFXB, BuyButtonB, CheckB, 1)

    # Side 0 = A (blue), 1 = B (red). Only fires if that trap is armed.
    CheckTrap(TrapProp : creative_prop, Ice : creative_prop, FreezeVFX : vfx_spawner_device, MeltVFX : vfx_spawner_device, Button : conditional_button_device, Check : creative_prop, Side : int) : void =
        if (IsArmed[Side]):
            BombPos := Cart.CartProp.GetTransform().Translation    # VERIFY: Cart.CartProp reachable
            TrapPos := TrapProp.GetTransform().Translation
            if (Distance(BombPos, TrapPos) < TriggerRadiusM * 100.0):   # positions are in cm
                Disarm(Side)             # spent - must re-buy to use again
                spawn{ FreezeSequence(TrapProp, Ice, FreezeVFX, MeltVFX, Button, Check) }

    IsArmed(Side : int)<transacts><decides> : void =
        if (Side = 0):
            ArmedA?
        else:
            ArmedB?

    Disarm(Side : int) : void =
        if (Side = 0):
            set ArmedA = false
        else:
            set ArmedB = false

    # The freeze choreography. Hides the trap prop + checkmark + re-enables
    # the button at the end (trap used up -> team can buy again).
    FreezeSequence(TrapProp : creative_prop, Ice : creative_prop, FreezeVFX : vfx_spawner_device, MeltVFX : vfx_spawner_device, Button : conditional_button_device, Check : creative_prop)<suspends> : void =
        set FreezeActive = true
        Cart.Freeze()                # stop the bomb (movement only)
        Ice.Show()
        FreezeVFX.Enable()           # VERIFY: vfx_spawner_device.Enable() (freeze burst)
        Sleep(FreezeSeconds)
        FreezeVFX.Disable()          # VERIFY: vfx_spawner_device.Disable()
        MeltVFX.Enable()             # melt burst
        Ice.Hide()
        Cart.Unfreeze()              # bomb continues from where it froze
        TrapProp.Hide()              # fridge gone - re-buy to bring it back
        Check.Hide()                 # purchased checkmark off
        Button.Enable()              # trap spent -> purchasing available again
        Sleep(0.5)
        MeltVFX.Disable()
        set FreezeActive = false
