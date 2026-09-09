# =====================================================================
#  DYNAMITE  —  buy in the lobby, deploy at the truck, blow it remotely
#
#  Three devices:
#
#    dynamite_inventory_device   ONE in the level. Holds how many charges
#                                each player owns.
#    dynamite_shop_device        In the lobby. Buy button -> spends money
#                                and adds charges.
#    location_dynamite_device    ONE per location. Owns that truck's
#                                carryable spawners, deploys the player's
#                                charges when a contract starts, and
#                                detonates them.
#
#  ARMING: a charge only detonates after it has been picked up AND put
#  down. Fresh ones sitting on the truck are inert, so a player can't
#  blow the truck up by accident. Picking one back up disarms it again.
#
#  Several charges can be placed before detonating - rig the whole
#  building, walk clear, then fire.
#
#  DETONATION: the truck button, or the Signal Remote item's primary
#  fire (via signal_remote_manager_device).
#
#  # VERIFY: carryable events (PickUpEvent / DropEvent), Spawn/Despawn/
#  Explode, and whether explosion damage registers with the prop
#  manipulator's DestroyedEvent (test before building around it).
# =====================================================================

using { /Fortnite.com/Devices }
using { /Verse.org/Simulation }
using { /UnrealEngine.com/Temporary/Diagnostics }

# ---------------------------------------------------------------------
#  How many charges each player owns.
# ---------------------------------------------------------------------
dynamite_inventory_device := class(creative_device):

    var Counts : [player]int = map{}

    Add<public>(Agent : agent, N : int) : void =
        New := Get(Agent) + N        # compute first - Get reads vars
        if (P := player[Agent]):
            if (set Counts[P] = New) {}
        Print("[Dynamite] Charges now {New}.")

    Get<public>(Agent : agent) : int =
        var N : int = 0
        if (P := player[Agent]):
            if (C := Counts[P]):
                set N = C
        N

    # Take charges off the player. Returns how many were actually taken.
    Take<public>(Agent : agent, N : int) : int =
        Have := Get(Agent)
        var Taken : int = N
        if (Have < N):
            set Taken = Have
        if (P := player[Agent]):
            if (set Counts[P] = Have - Taken) {}
        Taken

# ---------------------------------------------------------------------
#  Lobby shop.
# ---------------------------------------------------------------------
dynamite_shop_device := class(creative_device):

    @editable BuyButton : button_device = button_device{}
    @editable Economy : player_economy_device = player_economy_device{}
    @editable Inventory : dynamite_inventory_device = dynamite_inventory_device{}

    @editable Price : float = 250.0
    @editable AmountPerPurchase : int = 1

    OnBegin<override>()<suspends> : void =
        BuyButton.InteractedWithEvent.Subscribe(OnBuy)

    OnBuy(Agent : agent) : void =
        Paid := Economy.TrySpend(Agent, Price)
        if (Paid?):
            Inventory.Add(Agent, AmountPerPurchase)
        else:
            Print("[Dynamite] Purchase refused - not enough money.")

# ---------------------------------------------------------------------
#  One per location: the truck's charges.
# ---------------------------------------------------------------------
location_dynamite_device := class(creative_device):

    # Carryable spawners on the truck - one per charge that can be
    # carried at once. Place about 8.
    @editable Spawners : []carryable_spawner_device = array{}

    @editable DetonateButton : button_device = button_device{}
    # Signal Remote item - primary fire (the trigger) detonates, so the
    # player can blow the charges from wherever they're standing.
    @editable SignalRemote : signal_remote_manager_device = signal_remote_manager_device{}

    @editable Inventory : dynamite_inventory_device = dynamite_inventory_device{}

    var Slots : []dynamite_slot = array{}

    OnBegin<override>()<suspends> : void =
        set Slots = for (S : Spawners):
            dynamite_slot{ Spawner := S }
        for (Slot : Slots):
            Slot.Init()
        DetonateButton.InteractedWithEvent.Subscribe(OnDetonateButton)
        SignalRemote.PrimarySignalEvent.Subscribe(OnDetonateRemote)
        Print("[Dynamite] Location ready with {Slots.Length} slots.")

    # Called when a contract starts: put the player's charges on the truck.
    DeployFor<public>(Agent : agent) : void =
        Want := Inventory.Get(Agent)
        var Placed : int = 0
        for (Slot : Slots):
            if (Placed < Want):
                Slot.Deploy()
                set Placed = Placed + 1
        Taken := Inventory.Take(Agent, Placed)
        Print("[Dynamite] Deployed {Placed} (took {Taken}).")

    # Called when the contract ends: clear anything left.
    ClearAll<public>() : void =
        for (Slot : Slots):
            Slot.Clear()

    OnDetonateButton(Agent : agent) : void =
        Detonate(Agent)

    # PrimarySignalEvent sends the agent directly.
    OnDetonateRemote(Agent : agent) : void =
        Detonate(Agent)

    # Blow every charge that's been placed on the ground.
    Detonate(Agent : agent) : void =
        var Count : int = 0
        for (Slot : Slots):
            Went := Slot.Fire(Agent)
            if (Went?):
                set Count = Count + 1
        Print("[Dynamite] Detonated {Count}.")

# One carryable spawner and whether its charge is armed.
dynamite_slot := class:
    Spawner : carryable_spawner_device = carryable_spawner_device{}

    # Armed only once put down after being carried.
    var Armed : logic = false

    Init() : void =
        Spawner.PickUpEvent.Subscribe(OnPickUp)
        Spawner.DropEvent.Subscribe(OnDrop)

    OnPickUp(Agent : agent) : void =
        set Armed = false      # in hand - inert again

    OnDrop(Agent : agent) : void =
        set Armed = true       # placed - live

    Deploy() : void =
        set Armed = false
        Spawner.Spawn()

    Clear() : void =
        set Armed = false
        Spawner.Despawn()

    # Explodes if armed. Returns whether it went off.
    Fire(Agent : agent) : logic =
        var Went : logic = false
        if (Armed?):
            Spawner.Explode(Agent)
            set Armed = false
            set Went = true
        Went
