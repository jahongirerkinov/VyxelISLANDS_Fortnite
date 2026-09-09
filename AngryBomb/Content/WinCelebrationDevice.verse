# =====================================================================
#  WIN CELEBRATION  —  the big cinematic, on MATCH win only
#
#  Fires when a team reaches WinsToWinMatch (read from the round score
#  tracker), NOT on every round win. Regular rounds get the short
#  explosion cinematic from round_cinematic instead.
#
#  TIMING on the match-deciding round:
#     0.0s                     explosion
#     Cart.CelebrationDelay    cinematic starts (players saw the boom)
#       + MatchCelebrationSeconds   cinematic ends
#     Cart.CelebrationDelay + Cart.MatchWinExtraSeconds -> End Game fires
#
#  So keep the cart's MatchWinExtraSeconds slightly ABOVE this device's
#  MatchCelebrationSeconds, or the game ends mid-cinematic.
#
#  TESTING: tick DebugCelebrateEveryRound ON THE CART - it makes the cart
#  hold every round AND makes this device celebrate every round, so the
#  cinematic can be tuned without winning three rounds first.
#
#  Statues are filled MIDDLE-OUT: winner[0] -> Statues[0], etc.
# =====================================================================

using { /Fortnite.com/Devices }
using { /Fortnite.com/Game }
using { /Verse.org/Simulation }
using { /UnrealEngine.com/Temporary/Diagnostics }

win_celebration_device := class(creative_device):

    @editable Cart : bomb_cart_device = bomb_cart_device{}

    # Source of truth for the match score.
    @editable Tracker : round_score_tracker_device = round_score_tracker_device{}

    @editable Statues : []player_reference_device = array{}

    # Cinematic Sequence device (set to "Everyone" so Play() works).
    @editable Cinematic : cinematic_sequence_device = cinematic_sequence_device{}

    # Firework VFX spawners, enabled during the celebration.
    @editable Fireworks : []vfx_spawner_device = array{}

    # How long the match-win cinematic runs before the game ends.
    @editable MatchCelebrationSeconds : float = 10.0

    var WasLive : logic = false

    OnBegin<override>()<suspends> : void =
        Print("[Celebration] Ready with {Statues.Length} statues.")
        HideAll()
        spawn{ WatchRounds() }

    WatchRounds()<suspends> : void =
        loop:
            if (Cart.MatchLive?):
                set WasLive = true
            else:
                var JustEnded : logic = false
                if (WasLive?):
                    set JustEnded = true
                set WasLive = false
                if (JustEnded?):
                    MaybeCelebrate()
            Sleep(0.1)

    MaybeCelebrate()<suspends> : void =
        # Hold off until the explosion has been seen. Uses the cart's own
        # CelebrationDelay so there's a single number controlling it.
        Sleep(Cart.CelebrationDelay)
        Team := TeamToCelebrate()
        if (Team >= 0):
            Celebrate(Team)
            Sleep(MatchCelebrationSeconds)
            Reset()
            Print("[Celebration] Done.")

    # Which team to celebrate, or -1 for none.
    #   Normal:  only the team that just won the MATCH.
    #   Debug:   whoever won this round.
    TeamToCelebrate() : int =
        var Team : int = Tracker.MatchWinner()
        if (Cart.DebugCelebrateEveryRound?):
            if (Team < 0):
                set Team = Cart.LastWinner
        Team

    Celebrate(WinningTeam : int) : void =
        Print("[Celebration] Team {WinningTeam} wins the match - staging statues.")
        var Winners : []agent = array{}
        for (P : GetPlayspace().GetPlayers()):
            if (Cart.IsOnTeamIndex[P, WinningTeam]):
                set Winners = Winners + array{P}
        for (I -> Statue : Statues):
            if (Winner := Winners[I]):
                Statue.Register(Winner)
                Statue.Enable()
            else:
                Statue.Disable()
        for (FX : Fireworks):
            FX.Enable()
        Cinematic.Play()

    Reset() : void =
        Cinematic.Stop()
        for (FX : Fireworks):
            FX.Disable()
        for (Statue : Statues):
            Statue.Clear()
            Statue.Disable()

    HideAll() : void =
        for (Statue : Statues):
            Statue.Disable()
        for (FX : Fireworks):
            FX.Disable()
