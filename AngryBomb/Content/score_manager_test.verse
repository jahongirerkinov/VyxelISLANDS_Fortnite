# =====================================================================
#  SCORE MANAGER PERSISTENCE TEST  —  throwaway diagnostic
#
#  ONE QUESTION: does a Score Manager device's score survive a ROUND
#  transition? If yes, it's the right home for the match score, because a
#  device belongs to the GAME (not a player's account), so nothing can
#  follow a player into a future match.
#
#  Each round end: award 1 point to every player on the winning team, then
#  print both teams' scores. Play 2-3 rounds and read the log.
#
#     Blue 1 - Red 0  ->  Blue 2 - Red 0   = ACCUMULATES (we can use it)
#     Blue 1 - Red 0  ->  Blue 1 - Red 0   = RESETS every round (no good)
#
#  We read the HIGHEST score among a team's players, not the first found,
#  so a player who joined late (and is still on 0) doesn't hide the real
#  total.
#
#  SETUP:
#   - Assign the Cart.
#   - Place TWO Score Manager devices. In each Details panel set
#     "Activating Team" to that team. Assign as ScoreA (blue) / ScoreB (red).
#   - Set each one's score award to 1 (we also call SetScoreAward(1)).
#
#  DELETE THIS DEVICE once we have the answer.
# =====================================================================

using { /Fortnite.com/Devices }
using { /Fortnite.com/UI }
using { /Verse.org/Simulation }
using { /UnrealEngine.com/Temporary/SpatialMath }
using { /UnrealEngine.com/Temporary/UI }
using { /UnrealEngine.com/Temporary/Diagnostics }

score_manager_test_device := class(creative_device):

    @editable Cart : bomb_cart_device = bomb_cart_device{}

    @editable ScoreA : score_manager_device = score_manager_device{}   # Blue / team index 0
    @editable ScoreB : score_manager_device = score_manager_device{}   # Red  / team index 1

    var WasLive : logic = false
    var Huds : [player]test_hud = map{}
    var AtRoundStart : string = "-"      # what the managers read when this round began

    OnBegin<override>()<suspends> : void =
        Print("[ScoreTest] Ready.")
        ScoreA.SetScoreAward(1)      # VERIFY: score_manager_device.SetScoreAward(int)
        ScoreB.SetScoreAward(1)
        # Capture what the managers hold at the START of this round - this
        # is the persistence answer.
        StartB := ReadTeam(0, ScoreA)
        StartR := ReadTeam(1, ScoreB)
        set AtRoundStart = "{StartB}-{StartR}"
        ReportScores("on begin")
        for (P : GetPlayspace().GetPlayers()):
            BuildHudFor(P)
        RefreshHuds()
        spawn{ WatchRounds() }

    WatchRounds()<suspends> : void =
        loop:
            if (Cart.MatchLive?):
                set WasLive = true
            else:
                if (WasLive?):
                    OnRoundEnded()
                set WasLive = false
            Sleep(0.25)

    OnRoundEnded() : void =
        Winner := Cart.LastWinner
        if (Winner = 0):
            AwardTeam(0, ScoreA)
        else if (Winner = 1):
            AwardTeam(1, ScoreB)
        ReportScores("after round")
        RefreshHuds()

    # Award to every player on the winning team.
    AwardTeam(TeamIndex : int, Manager : score_manager_device) : void =
        for (P : GetPlayspace().GetPlayers()):
            if (Cart.IsOnTeamIndex[P, TeamIndex]):
                Manager.Activate(P)        # VERIFY: score_manager_device.Activate(agent)

    # Highest score held by any player on that team (late joiners sit on 0).
    ReadTeam(TeamIndex : int, Manager : score_manager_device)<transacts> : int =
        var Best : int = 0
        for (P : GetPlayspace().GetPlayers()):
            if (Cart.IsOnTeamIndex[P, TeamIndex]):
                Got := Manager.GetCurrentScore(P)   # VERIFY: GetCurrentScore(agent) : int
                if (Got > Best):
                    set Best = Got
        Best

    ReportScores(When : string) : void =
        B := ReadTeam(0, ScoreA)
        R := ReadTeam(1, ScoreB)
        Print("[ScoreTest] {When}: Blue {B} - Red {R}")

    # ---------------- On-screen readout ----------------
    BuildHudFor(P : player) : void =
        if (PUI := GetPlayerUI[P]):
            H := test_hud{}
            H.Build(PUI)
            if (set Huds[P] = H) {}

    RefreshHuds() : void =
        B := ReadTeam(0, ScoreA)
        R := ReadTeam(1, ScoreB)
        for (P -> H : Huds):
            H.Update(B, R, AtRoundStart)

# Shows the live manager score AND what it read at round start.
# "start" carrying a non-zero value into a new round = it PERSISTED.
test_hud := class:
    Text : text_block = text_block{}

    Build(PC : player_ui) : void =
        Canvas := canvas:
            Slots := array:
                canvas_slot:
                    Anchors := anchors{ Minimum := vector2{ X := 0.5, Y := 1.0 }, Maximum := vector2{ X := 0.5, Y := 1.0 } }
                    Alignment := vector2{ X := 0.5, Y := 1.0 }
                    Offsets := margin{ Top := 0.0, Left := 0.0, Right := 0.0, Bottom := 170.0 }
                    SizeToContent := true
                    Widget := Text
        PC.AddWidget(Canvas)

    Update(Blue : int, Red : int, StartedAt : string) : void =
        Text.SetText(TestMsg("SM now {Blue}-{Red}   (round began at {StartedAt})"))

TestMsg<localizes>(S : string) : message = "{S}"
