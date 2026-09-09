# =====================================================================
#  XP AWARDS  —  grants Battle Pass XP via Accolade devices
#
#  Three rewards, each fired by calling Award(agent) on its Accolade
#  device (set the XP tier on each device in its Details panel):
#     WinAccolade    (Very Large) - every player on the winning team,
#                                   at round end (read from the cart).
#     KillAccolade   (Medium)     - the eliminator, per elimination,
#                                   via an Elimination Manager device.
#     PassiveAccolade(Small)      - every present player, every 30s.
#
#  SETUP:
#   - Place 3 Accolade devices, set their XP tiers, assign them below.
#   - Place 1 Elimination Manager, set it to track ALL PLAYERS (a team
#     filter makes half the eliminations not fire), assign it below.
#
#  NOTE: XP only actually appears once the island is PUBLISHED and Epic's
#  calibration runs. In private testing you'll see the Print/award fire,
#  but no real XP - that's expected, not a bug.
#
#  STATUS: first pass. # VERIFY: accolades_device.Award(agent),
#  elimination_manager_device.EliminationEvent + payload fields.
# =====================================================================

using { /Fortnite.com/Devices }
using { /Fortnite.com/Game }
using { /Verse.org/Simulation }
using { /UnrealEngine.com/Temporary/Diagnostics }

xp_awards_device := class(creative_device):

    @editable Cart : bomb_cart_device = bomb_cart_device{}

    @editable WinAccolade : accolades_device = accolades_device{}      # Very Large
    @editable KillAccolade : accolades_device = accolades_device{}     # Medium
    @editable PassiveAccolade : accolades_device = accolades_device{}  # Small

    # Set this device to track ALL PLAYERS in its Details panel.
    @editable EliminationManager : elimination_manager_device = elimination_manager_device{}

    @editable PassiveSeconds : float = 30.0

    var WasLive : logic = false      # for detecting a round-end transition

    OnBegin<override>()<suspends> : void =
        Print("[XPAwards] Ready.")
        # Kills: the manager reports every elimination with eliminator + eliminated.
        EliminationManager.EliminationEvent.Subscribe(OnElimination)   # VERIFY: elimination_manager_device.EliminationEvent
        spawn{ WatchForWin() }
        spawn{ PassiveLoop() }

    # ---- Win: award the winning team when a round ends ----
    WatchForWin()<suspends> : void =
        loop:
            if (Cart.MatchLive?):
                set WasLive = true
            else:
                if (WasLive?):
                    AwardWinners()       # just transitioned live -> ended
                set WasLive = false
            Sleep(0.25)

    AwardWinners() : void =
        Winner := Cart.LastWinner
        if (Winner >= 0):
            for (A : GetPlayspace().GetPlayers()):
                if (Cart.IsOnTeamIndex[A, Winner]):
                    WinAccolade.Award(A)     # VERIFY: accolades_device.Award(agent)
            Print("[XPAwards] Win XP -> team {Winner}.")

    # ---- Elimination: award the eliminator ----
    # The manager hands the ELIMINATOR straight to us as ?agent (None if
    # the kill was environmental).
    OnElimination(Agent : ?agent) : void =
        if (Eliminator := Agent?):       # unwrap; skip environmental kills
            KillAccolade.Award(Eliminator)   # VERIFY: accolades_device.Award(agent)
            Print("[XPAwards] Kill XP awarded.")

    # ---- Passive: award everyone present every PassiveSeconds ----
    PassiveLoop()<suspends> : void =
        loop:
            Sleep(PassiveSeconds)
            for (A : GetPlayspace().GetPlayers()):
                PassiveAccolade.Award(A)
