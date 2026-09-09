# =====================================================================
#  ROUND SCORE TRACKER
#
#  The missing signal was "which round is this?". round_settings_device
#  exposes RoundNumber (?int), which gives it to us:
#
#     Round 1   -> a NEW match  -> score starts at 0-0
#     Round 2+  -> continuing   -> load the score carried over
#
#  That single fact fixes both old problems at once:
#   - Solo play now scores correctly (round 2 loads round 1's result).
#   - A player who quit a match at 2-0 can't seed a fresh game, because
#     round 1 always resets regardless of what they carried in.
#
#  Storage layers:
#   1. LIVE (device vars) - authority for the current round. Immune to
#      player churn: respawners copy FROM it, so nothing zeroes out if
#      everyone dies at once. Resets when the device re-inits each round.
#   2. PERSISTED (player-keyed weak_map) - the only thing that survives a
#      round transition. Written to every player on each round win and
#      read back at the start of the next round.
#
#  Other devices READ via GetBlueWins()/GetRedWins()/MatchWinner().
#  Keep WinsToWinMatch in sync with Island Settings.
#
#  # VERIFY: round_settings_device.RoundNumber is the LIVE round, not the
#  device's configured round. The Print at round start reports it - watch
#  that it counts 1, 2, 3 as rounds pass.
# =====================================================================

using { /Fortnite.com/Devices }
using { /Fortnite.com/UI }
using { /Verse.org/Simulation }
using { /UnrealEngine.com/Temporary/SpatialMath }
using { /UnrealEngine.com/Temporary/UI }
using { /UnrealEngine.com/Temporary/Diagnostics }

# Persistable per-player record - survives round transitions.
score_record := class<final><persistable>:
    BlueWins<public> : int = 0
    RedWins<public> : int = 0

var ScoreMap : weak_map(player, score_record) = map{}

# Lifetime match wins. Account-scoped persistence is the right fit here -
# a trophy SHOULD follow the player between sessions.
# NOTE: Epic caps a project at TWO player weak_maps; this is the second.
trophy_record := class<final><persistable>:
    Wins<public> : int = 0

var TrophyMap : weak_map(player, trophy_record) = map{}

round_score_tracker_device := class(creative_device):

    # One Round Settings device - we only read RoundNumber from it.
    @editable RoundSettings : round_settings_device = round_settings_device{}

    # Every Player Spawner, so we catch joins, rejoins and respawns.
    @editable Spawners : []player_spawner_device = array{}

    # Keep in sync with Island Settings "rounds to win".
    @editable WinsToWinMatch : int = 3

    # The game never ends (continuous play - no results screen, so the
    # lobby stays together), so the score is reset HERE after a team wins
    # the match. Must be LONGER than the cart's CelebrationDelay plus the
    # celebration's MatchCelebrationSeconds, or the score would clear
    # before the big cinematic has read it.
    @editable MatchResetDelay : float = 14.0

    # Temporary on-screen readout while we verify round detection.
    # Turn OFF before publishing.
    @editable ShowDebugUI : logic = true

    # ---- LIVE score: authority for this round.
    var LiveBlue : int = 0
    var LiveRed : int = 0

    var RoundNum : int = 0
    var Huds : [player]debug_hud = map{}

    OnBegin<override>()<suspends> : void =
        R := CurrentRound()
        set RoundNum = R
        Print("[RoundScore] Round {R} starting.")
        if (R > 1):
            LoadCarriedScore()      # continuing a match
        else:
            SetLive(0, 0)           # round 1 (or unknown) -> fresh match
            WriteToAll(0, 0)
            Print("[RoundScore] New match - 0-0.")
        for (S : Spawners):
            S.SpawnedEvent.Subscribe(OnPlayerSpawned)
        GetPlayspace().PlayerRemovedEvent().Subscribe(OnPlayerLeft)
        if (ShowDebugUI?):
            for (P : GetPlayspace().GetPlayers()):
                BuildHudFor(P)
            spawn{ HudLoop() }

    # The live round number, or 0 if the device doesn't report one.
    CurrentRound() : int =
        RoundSettings.RoundNumber      # VERIFY: live round, not configured round

    # Round 2+: recover the score written to the players at the end of the
    # previous round. Any present player carries it.
    LoadCarriedScore() : void =
        var B : int = 0
        var Rd : int = 0
        for (P : GetPlayspace().GetPlayers()):
            if (Rec := ScoreMap[P]):
                set B = Rec.BlueWins
                set Rd = Rec.RedWins
        SetLive(B, Rd)
        Print("[RoundScore] Carried over {B}-{Rd}.")

    # Every spawn (join, rejoin, respawn) adopts the live score. This is
    # what stops a rejoiner dragging an old score in, and stops respawners
    # being zeroed after a wipe.
    OnPlayerSpawned(A : agent) : void =
        if (P := player[A]):
            WriteToPlayer(P, LiveBlue, LiveRed)
            if (ShowDebugUI?):
                if (not Huds[P]):
                    BuildHudFor(P)

    OnPlayerLeft(P : player) : void =
        if (set ScoreMap[P] = score_record{}) {}

    SetLive(B : int, R : int) : void =
        set LiveBlue = B
        set LiveRed = R

    WriteToPlayer(P : player, B : int, R : int) : void =
        if (set ScoreMap[P] = score_record{ BlueWins := B, RedWins := R }) {}

    WriteToAll(B : int, R : int) : void =
        for (P : GetPlayspace().GetPlayers()):
            WriteToPlayer(P, B, R)

    # ---- Called BY THE CART when a round ends (push, not poll - a mutual
    #      device reference would be a linker cycle). Bumps the live score
    #      and persists it to every player so it survives the round change.
    CreditRoundWin<public>(Winner : int) : void =
        var NewB : int = LiveBlue
        var NewR : int = LiveRed
        if (Winner = 0):
            set NewB = LiveBlue + 1
        else if (Winner = 1):
            set NewR = LiveRed + 1
        SetLive(NewB, NewR)
        WriteToAll(NewB, NewR)
        Print("[RoundScore] Blue {NewB} - {NewR} Red")
        var Clinched : logic = false
        if (NewB >= WinsToWinMatch):
            Print("[RoundScore] BLUE won the match.")
            set Clinched = true
        else if (NewR >= WinsToWinMatch):
            Print("[RoundScore] RED won the match.")
            set Clinched = true
        if (Clinched?):
            AwardTrophies(Winner)
            spawn{ ResetAfterCelebration() }

    # +1 lifetime win for everyone on the winning team.
    AwardTrophies(WinningTeam : int) : void =
        for (P : GetPlayspace().GetPlayers()):
            if (IsOnTeamIndex[P, WinningTeam]):
                Now := GetTrophies(P)
                if (set TrophyMap[P] = trophy_record{ Wins := Now + 1 }) {}
        Print("[RoundScore] Trophies awarded to team {WinningTeam}.")

    # Same team lookup the cart uses.
    IsOnTeamIndex(Agent : agent, Index : int)<transacts><decides> : void =
        TeamCollection := GetPlayspace().GetTeamCollection()
        Teams := TeamCollection.GetTeams()
        Team := Teams[Index]
        TeamCollection.IsOnTeam[Agent, Team]

    # Lifetime match wins for a player (0 if they have none yet).
    GetTrophies<public>(P : player)<transacts> : int =
        var N : int = 0
        if (Rec := TrophyMap[P]):
            set N = Rec.Wins
        N

    # Wipe the score once the match-win celebration has finished, so the
    # next match starts fresh without anyone leaving the session.
    ResetAfterCelebration()<suspends> : void =
        Sleep(MatchResetDelay)
        SetLive(0, 0)
        WriteToAll(0, 0)
        Print("[RoundScore] Match over - score reset, play continues.")

    # ---------------- PUBLIC GETTERS (other devices read these) ----------
    GetBlueWins()<transacts> : int = LiveBlue

    GetRedWins()<transacts> : int = LiveRed

    # -1 = no winner yet, 0 = Blue won the match, 1 = Red won the match.
    MatchWinner()<transacts> : int =
        if (LiveBlue >= WinsToWinMatch):
            return 0
        if (LiveRed >= WinsToWinMatch):
            return 1
        return -1

    # ---------------- Temporary debug readout ----------------
    BuildHudFor(P : player) : void =
        if (PUI := GetPlayerUI[P]):
            H := debug_hud{}
            H.Build(PUI)
            if (set Huds[P] = H) {}

    HudLoop()<suspends> : void =
        loop:
            for (P -> H : Huds):
                H.Update(RoundNum, LiveBlue, LiveRed)
            Sleep(0.25)

# Shows the round number alongside the score, so we can confirm the round
# counter actually advances (1, 2, 3...) rather than reporting a fixed value.
debug_hud := class:
    Text : text_block = text_block{}

    Build(PC : player_ui) : void =
        Canvas := canvas:
            Slots := array:
                canvas_slot:
                    Anchors := anchors{ Minimum := vector2{ X := 0.5, Y := 1.0 }, Maximum := vector2{ X := 0.5, Y := 1.0 } }
                    Alignment := vector2{ X := 0.5, Y := 1.0 }
                    Offsets := margin{ Top := 0.0, Left := 0.0, Right := 0.0, Bottom := 140.0 }
                    SizeToContent := true
                    Widget := Text
        PC.AddWidget(Canvas)

    Update(RoundNo : int, Blue : int, Red : int) : void =
        Text.SetText(DebugMsg("ROUND {RoundNo}    BLUE {Blue} - {Red} RED"))

DebugMsg<localizes>(S : string) : message = "{S}"
