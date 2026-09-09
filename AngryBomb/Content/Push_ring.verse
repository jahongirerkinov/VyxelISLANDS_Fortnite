# =====================================================================
#  PUSH RING  —  colour-coded push-zone ring on the bomb
#
#  Three ring meshes (blue / red / white) are attached to the bomb root
#  in the editor, so they move with the bomb. This device shows exactly
#  ONE at a time based on the cart's live pusher counts:
#     blue  ahead  -> blue ring
#     red   ahead  -> red ring
#     tied/none    -> white ring
#  Reads Cart.LastACount / LastBCount (recomputed every tick, so it stays
#  correct even during a freeze). Only rebuilds visibility on a CHANGE,
#  so no flicker.
#
#  STATUS: first pass. # VERIFY: creative_prop Show()/Hide() (same call
#  the freeze trap uses for its props).
# =====================================================================

using { /Fortnite.com/Devices }
using { /Verse.org/Simulation }
using { /UnrealEngine.com/Temporary/Diagnostics }

push_ring_device := class(creative_device):

    @editable Cart : bomb_cart_device = bomb_cart_device{}

    # The three ring meshes attached to the bomb root.
    @editable RingBlue : creative_prop = creative_prop{}
    @editable RingRed : creative_prop = creative_prop{}
    @editable RingWhite : creative_prop = creative_prop{}

    @editable RefreshSeconds : float = 0.15

    # -1 = nothing shown yet, 0 = blue, 1 = red, 2 = white
    var Current : int = -1

    OnBegin<override>()<suspends> : void =
        Print("[PushRing] Ready.")
        # Start with all hidden; the loop will show the right one.
        RingBlue.Hide()              # VERIFY: creative_prop.Hide()
        RingRed.Hide()
        RingWhite.Hide()
        spawn{ RingLoop() }

    RingLoop()<suspends> : void =
        loop:
            UpdateRing()
            Sleep(RefreshSeconds)

    UpdateRing() : void =
        Want := DesiredRing()
        if (Want <> Current):        # only change on an actual switch (no flicker)
            ShowOnly(Want)
            set Current = Want

    # 0 = blue ahead, 1 = red ahead, 2 = tied / nobody.
    DesiredRing() : int =
        A := Cart.LastACount
        B := Cart.LastBCount
        if (A > B):
            return 0
        if (B > A):
            return 1
        return 2

    ShowOnly(Which : int) : void =
        # hide all, then show the one we want
        RingBlue.Hide()
        RingRed.Hide()
        RingWhite.Hide()
        if (Which = 0):
            RingBlue.Show()          # VERIFY: creative_prop.Show()
        else if (Which = 1):
            RingRed.Show()
        else:
            RingWhite.Show()
