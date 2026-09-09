# =====================================================================
#  BOMB CART  —  two towers, one track, one live bomb
#
#  RULES (v1, locked):
#   - Cart sits mid-track. Players near it push it.
#   - NET DIFFERENCE model: only the head-count difference matters.
#       empty zone      -> stopped
#       2v2 / 1v1       -> stopped
#       2v1             -> creeps toward the outnumbered side
#       2v0             -> full speed
#   - Cart reaches a tower  -> that tower explodes, its team LOSES.
#   - Timer expires         -> the team it's CLOSER to loses.
#                              (dead centre = draw)
#   - Unlimited ammo. Fixed mats per life. No shop. (island settings)
#
#  The push zone is computed as a RADIUS AROUND THE CART, not a placed
#  mutator zone - a placed zone can't follow a moving cart.
#
#  Position is tracked as Progress 0.0 -> 1.0 along the TowerA->TowerB
#  axis, so "how far along" and "who's closer" are the same number.
#  Track length comes from where you place the two markers, so the
#  10m-vs-80m question settles itself in the editor.
#

# =====================================================================

using { /Fortnite.com/Devices }
using { /Fortnite.com/Characters }
using { /Fortnite.com/Game }
using { /Verse.org/Simulation }
using { /UnrealEngine.com/Temporary/SpatialMath }
using { /UnrealEngine.com/Temporary/Diagnostics }

CartMsg<localizes>(S : string) : message = "{S}"

bomb_cart_device := class(creative_device):

    # ---- The cart itself ----
    @editable CartProp : creative_prop = creative_prop{}

    # ---- The walking-bomb skeletal mesh (visual only). Set it to LOOP +
    #      START PAUSED in its Details panel; Verse plays/pauses the legs. ----
    @editable AnimatedMesh : animated_mesh_device = animated_mesh_device{}
    # Same bomb model, same position on CartProp, but with the flickering
    # (red/black) urgency material. Kept in perfect sync with AnimatedMesh
    # (both Play/Pause together); only ONE is visible at a time.
    @editable AnimatedMeshUrgent : animated_mesh_device = animated_mesh_device{}
    # animated_mesh_device has NO Show/Hide, so each mesh is attached to an
    # (invisible) creative_prop WRAPPER; hiding the wrapper hides the mesh
    # while it keeps animating (so the two stay perfectly in sync).
    @editable NormalWrapper : creative_prop = creative_prop{}   # holds AnimatedMesh
    @editable UrgentWrapper : creative_prop = creative_prop{}   # holds AnimatedMeshUrgent

    # ---- Tower reference points: drop an invisible marker prop at each
    #      tower's cart-arrival point. Everything is measured off these. ----
    @editable TowerAMarker : creative_prop = creative_prop{}
    @editable TowerBMarker : creative_prop = creative_prop{}

    # ---- Explosives at each tower (that team loses when theirs fires) ----
    @editable TowerAExplosive : explosive_device = explosive_device{}
    @editable TowerBExplosive : explosive_device = explosive_device{}

    # ---- End Game devices, BOTH set to "What to End: End Round" in their
    #      panel. One with Winning Team = Team Index 0, the other = Index 1. ----
    @editable EndRoundTeamAWins : end_game_device = end_game_device{}
    @editable EndRoundTeamBWins : end_game_device = end_game_device{}

    # ---- VFX spaced along the track; the one nearest the cart fires on
    #      a timeout detonation. 5-8 is plenty. ----
    @editable TrackVFX : []vfx_spawner_device = array{}

    # ---- Optional readout: distance + countdown ----
    @editable ProgressBillboard : billboard_device = billboard_device{}

    # ---- Tuning ----
    @editable RoundSeconds : float = 180.0        # bomb fuse
    @editable PushRadiusMeters : float = 4.0      # how close counts as "on the cart"
    @editable MetersPerSecondPerNet : float = 1.2 # speed per net attacker (2v1 = 1x, 2v0 = 2x)
    @editable MaxNetPush : int = 3                # cap so 5v0 isn't absurd
    @editable ArrivalMeters : float = 2.0         # close enough to a tower = detonation
    @editable TickInterval : float = 0.1
    @editable TurnSeconds : float = 0.75          # time to pivot 180 when the push reverses
    @editable CelebrationDelay : float = 5.0      # pause after a win (for the celebration) before the round advances
    # Read to tell whether the round just won also WON THE MATCH, so the
    # round advance can be held back for the long celebration cinematic.
    @editable Tracker : round_score_tracker_device = round_score_tracker_device{}
    # Extra hold on the match-deciding round. Keep this slightly ABOVE the
    # celebration device's MatchCelebrationSeconds so End Game fires just
    # after the cinematic finishes, not during it.
    @editable MatchWinExtraSeconds : float = 10.5
    # TESTING ONLY - treat every round as a match win (long delay + the big
    # celebration) so the cinematic can be tuned. Untick before publishing.
    @editable DebugCelebrateEveryRound : logic = false

    @editable UrgencySeconds : float = 30.0       # final seconds of the fuse -> urgency flicker anywhere
    @editable UrgencyNearFraction : float = 0.15  # within this fraction of the faced tower -> urgency flicker
    @editable HiddenDropCm : float = 6000.0        # how far DOWN to drop the inactive wrapper (out of view)
    @editable BombHideDelay : float = 0.1          # pause after the explosion before the bomb vanishes

    # ---- State ----
    var Progress : float = 0.5      # 0.0 = Tower A, 1.0 = Tower B
    var TimeLeft : float = 0.0
    var MatchLive : logic = false
    var Frozen : logic = false      # freeze trap: pauses MOVEMENT only (counting keeps running)
    var TrackLengthCm : float = 1.0
    var LastACount : int = 0        # Team A players in the push zone (debug readout)
    var LastBCount : int = 0        # Team B players in the push zone
    var LastWinner : int = -1       # winning team of the last ended round (-1 = none); read by celebration
    var CartMoving : logic = false  # are the legs currently playing?
    var UrgentShown : logic = false # is the flickering (urgency) mesh currently the visible one?
    var FacingTowardB : logic = true  # which tower the cart's front points at
    var Turning : logic = false       # a 180 pivot is in progress (movement gated)

    OnBegin<override>()<suspends> : void =
        Sleep(2.0)   # let players load in
        StartMatch()
        spawn{ CartLoop() }

    StartMatch() : void =
        set Progress = 0.5
        set TimeLeft = RoundSeconds
        set TrackLengthCm = TrackLength()
        set MatchLive = true
        set Frozen = false          # clear any leftover freeze on a new round
        set LastWinner = -1         # clear so celebration only fires on a fresh win
        set CartMoving = false
        set FacingTowardB = true    # place the cart at centre FACING TOWER B in the editor
        set Turning = false
        PauseWalk()   # begin with the legs frozen (cart starts still)
        # Start each round on the NORMAL mesh: drop the urgent wrapper far
        # below (out of view), leave the normal wrapper up at the bomb.
        DropWrapper(UrgentWrapper)
        set UrgentShown = false
        Print("[Cart] Match live. Track length: {TrackLengthCm / 100.0} m.")

    # ---- Freeze switch (called by the freeze-trap device) ----
    # Pauses MOVEMENT only. Pusher counting, the fuse, and the HUD keep
    # running - so no leave/re-enter glitch on the counts.
    Freeze() : void =
        set Frozen = true

    Unfreeze() : void =
        set Frozen = false

    TrackLength()<transacts> : float =
        A := TowerAMarker.GetTransform().Translation
        B := TowerBMarker.GetTransform().Translation
        Len := Distance(A, B)
        if (Len > 1.0):
            return Len
        return 1.0   # guard against unplaced markers

    # =================== MAIN LOOP ===================
    CartLoop()<suspends> : void =
        var TextTick : int = 0
        loop:
            if (MatchLive?):
                set TimeLeft = TimeLeft - TickInterval   # fuse always burns
                Net := NetPush()                          # counting ALWAYS runs (live pusher counts)
                if (Frozen?):
                    StopLegsIfMoving()   # bomb encased in ice: no movement, legs stop
                else:
                    HandlePush(Net)      # normal movement
                CheckWinConditions()
                UpdateUrgencyVisual()    # flicker mesh when near faced tower or final seconds
                set TextTick = TextTick + 1
                if (TextTick >= 5):     # refresh the readout ~2x/sec
                    set TextTick = 0
                    UpdateBillboard(Net)
            Sleep(TickInterval)

    # =================== PUSH + FACING + ANIMATION ===================
    # Decides each tick what the cart does: stop, turn to face its travel
    # direction, or walk. During a 180 pivot the cart is frozen (position
    # AND legs) - a turn is a deliberate "momentum shifted" beat.
    HandlePush(Net : int) : void =
        if (Turning?):
            return                 # a pivot is running; ignore push until it finishes
        if (Net = 0):
            StopLegsIfMoving()     # contested / empty -> freeze in place
            return
        if (Net > 0):
            # wants to move toward Tower B
            if (FacingTowardB?):
                StartLegsIfStopped()
                AdvanceCart(Net)
            else:
                BeginTurn(true)    # facing A, must wheel around first
        else:
            # Net < 0: wants to move toward Tower A
            if (FacingTowardB?):
                BeginTurn(false)
            else:
                StartLegsIfStopped()
                AdvanceCart(Net)

    # Start a pivot: freeze legs now, run the timed turn async.
    BeginTurn(ToB : logic) : void =
        set Turning = true
        PauseWalk()                # legs freeze mid-stride and hold through the turn
        spawn{ TurnTo(ToB) }

    TurnTo(ToB : logic)<suspends> : void =
        CartPos := CartProp.GetTransform().Translation
        if (ToB?):
            CartProp.MoveTo(CartPos, FacingRotationForB(), TurnSeconds)   # VERIFY: MoveTo interpolates rotation
            set FacingTowardB = true
        else:
            CartProp.MoveTo(CartPos, FacingRotationForA(), TurnSeconds)
            set FacingTowardB = false
        set Turning = false        # legs resume next tick if the push continues

    # Facings are read straight off the tower markers' rotations - set the
    # TowerA marker to (0,0,0) and the TowerB marker to (180,0,180) in editor.
    FacingRotationForA()<transacts> : rotation = TowerAMarker.GetTransform().Rotation
    FacingRotationForB()<transacts> : rotation = TowerBMarker.GetTransform().Rotation

    StartLegsIfStopped() : void =
        if (CartMoving?):
            return                 # already walking, nothing to do
        set CartMoving = true
        PlayWalk()

    StopLegsIfMoving() : void =
        if (CartMoving?):
            set CartMoving = false
            PauseWalk()

    PlayWalk() : void =
        AnimatedMesh.Play()        # VERIFY: animated_mesh_device.Play() (may be binding-only)
        AnimatedMeshUrgent.Play()  # keep the urgency mesh in lockstep

    PauseWalk() : void =
        AnimatedMesh.Pause()       # VERIFY: animated_mesh_device.Pause()
        AnimatedMeshUrgent.Pause()

    # ---- Urgency flicker: show the flickering mesh when the bomb is close
    #      to the tower it's facing, OR in the final UrgencySeconds. ----
    UrgencyActive() : logic =
        if (TimeLeft <= UrgencySeconds):
            return true                 # final seconds - could blow anywhere
        if (FacingTowardB?):
            if (Progress > (1.0 - UrgencyNearFraction)):
                return true             # near Tower B and facing it
        else:
            if (Progress < UrgencyNearFraction):
                return true             # near Tower A and facing it
        return false

    UpdateUrgencyVisual() : void =
        Want := UrgencyActive()      # compute first (reads vars), then branch
        if (Want?):
            GoUrgent()
        else:
            GoNormal()

    GoUrgent() : void =
        if (UrgentShown?):
            return                      # already showing the flicker mesh
        RaiseWrapperToOther(UrgentWrapper, NormalWrapper)  # urgent up to where normal is
        DropWrapper(NormalWrapper)                         # normal down out of view
        set UrgentShown = true

    GoNormal() : void =
        if (UrgentShown?):
            RaiseWrapperToOther(NormalWrapper, UrgentWrapper)  # normal back up to where urgent is
            DropWrapper(UrgentWrapper)                          # urgent down out of view
            set UrgentShown = false

    # After the boom, sink the whole cart out of sight. The wrappers are
    # attached, so they go with it and the bomb disappears from the scene.
    # Nothing to undo: the round restart puts everything back.
    HideBombAfterExplosion()<suspends> : void =
        Sleep(BombHideDelay)
        T := CartProp.GetTransform()
        Pos := T.Translation
        Down := vector3{ X := Pos.X, Y := Pos.Y, Z := Pos.Z - HiddenDropCm }
        if (CartProp.TeleportTo[Down, T.Rotation]) {}

    # Drop a wrapper straight down by HiddenDropCm from its current spot.
    DropWrapper(W : creative_prop) : void =
        T := W.GetTransform()
        Pos := T.Translation
        Down := vector3{ X := Pos.X, Y := Pos.Y, Z := Pos.Z - HiddenDropCm }
        if (W.TeleportTo[Down, T.Rotation]) {}   # VERIFY: does teleport hold on an attached child?

    # Put wrapper W at the (visible) Other wrapper's position, so it appears
    # exactly where the bomb is.
    RaiseWrapperToOther(W : creative_prop, Other : creative_prop) : void =
        OT := Other.GetTransform()
        if (W.TeleportTo[OT.Translation, OT.Rotation]) {}

    # =================== PUSH MATH ===================
    # Positive net = Team A outnumbers -> cart rolls toward Tower B.
    NetPush()<transacts> : int =
        CartPos := CartProp.GetTransform().Translation
        RadiusCm := PushRadiusMeters * 100.0
        var ACount : int = 0
        var BCount : int = 0
        for (Agent : GetPlayspace().GetPlayers()):
            if (FC := Agent.GetFortCharacter[], FC.IsActive[]):     # VERIFY: IsActive[] guards dead players
                Pos := FC.GetTransform().Translation
                if (Distance(Pos, CartPos) <= RadiusCm):
                    if (IsOnTeamIndex[Agent, 0]):
                        set ACount = ACount + 1
                    else if (IsOnTeamIndex[Agent, 1]):
                        set BCount = BCount + 1
        set LastACount = ACount
        set LastBCount = BCount
        return Clamp(ACount - BCount, -MaxNetPush, MaxNetPush)

    # Team lookup by index into the playspace team collection.
    IsOnTeamIndex(Agent : agent, Index : int)<transacts><decides> : void =
        TeamCollection := GetPlayspace().GetTeamCollection()
        Teams := TeamCollection.GetTeams()
        Team := Teams[Index]
        TeamCollection.IsOnTeam[Agent, Team]      # VERIFY: IsOnTeam[agent, team]

    AdvanceCart(Net : int) : void =
        if (Net <> 0):
            # metres this tick -> fraction of the track. Magnitude comes from a
            # helper that returns a float directly, so no int->float is needed.
            Units := StepUnits(Net)
            StepFrac := Units * MetersPerSecondPerNet * 100.0 * TickInterval / TrackLengthCm
            if (Net > 0):
                set Progress = ClampFloat(Progress + StepFrac, 0.0, 1.0)
            else:
                set Progress = ClampFloat(Progress - StepFrac, 0.0, 1.0)
            MoveCartToProgress()
            # TODO (VERIFY): break player-built structures the cart rolls into.
            # No confirmed Verse API for destroying builds - once found, this
            # is where it hooks in. Until then the cart may stall on walls.

    MoveCartToProgress() : void =
        A := TowerAMarker.GetTransform().Translation
        B := TowerBMarker.GetTransform().Translation
        Target := A + (B - A) * Progress
        Rot := CartProp.GetTransform().Rotation
        spawn{ SlideCart(Target, Rot) }

    SlideCart(Target : vector3, Rot : rotation)<suspends> : void =
        CartProp.MoveTo(Target, Rot, TickInterval)   # VERIFY: creative_prop.MoveTo(pos, rot, time)

    # =================== WIN CONDITIONS ===================
    CheckWinConditions() : void =
        ArrivalFrac := (ArrivalMeters * 100.0) / TrackLengthCm
        if (Progress <= ArrivalFrac):
            EndMatch("TEAM A's BASE DESTROYED  -  TEAM B WINS", 1)   # winner = Team B
        else if (Progress >= 1.0 - ArrivalFrac):
            EndMatch("TEAM B's BASE DESTROYED  -  TEAM A WINS", 0)   # winner = Team A
        else if (TimeLeft <= 0.0):
            ResolveTimeout()

    ResolveTimeout() : void =
        # Whichever base the bomb is closer to is the team that loses. A true
        # dead-centre draw is folded into "closer side" here (exact centre ->
        # Team A wins) so the round always ends - see the note in chat.
        FireNearestVFX()
        Off := Progress - 0.5
        if (Off < 0.0):
            # nearer Tower A -> Team A's base -> Team B wins
            EndMatch("TIME UP - bomb nearer TEAM A's base  -  TEAM B WINS", 1)
        else:
            # nearer Tower B (or dead centre) -> Team A wins
            EndMatch("TIME UP - bomb nearer TEAM B's base  -  TEAM A WINS", 0)

    # WinningTeam: 0 = Team A, 1 = Team B. The LOSING team's tower explodes,
    # and that team's opponent is declared the round winner via End Game device.
    EndMatch(Result : string, WinningTeam : int) : void =
        if (MatchLive?):
            set MatchLive = false
            set LastWinner = WinningTeam        # celebration device reads this
            StopLegsIfMoving()     # freeze the legs the moment the match ends
            Print("[Cart] {Result}")
            ProgressBillboard.SetText(CartMsg(Result))
            # The losing tower explodes NOW (the visual boom).
            if (Instigator := GetPlayspace().GetPlayers()[0]):
                if (WinningTeam = 0):
                    TowerBExplosive.Explode(Instigator)        # Team B's base falls
                else if (WinningTeam = 1):
                    TowerAExplosive.Explode(Instigator)        # Team A's base falls
            # Advance the round AFTER the celebration window (gives the
            # celebration device time to stage + show the statues).
            # Tell the tracker who won (push, not poll - a mutual device
            # reference would be a linker cycle). Done here so MatchWinner
            # is already correct when the advance timer checks it.
            Tracker.CreditRoundWin(WinningTeam)
            spawn{ HideBombAfterExplosion() }   # bomb vanishes just after the boom
            spawn{ AdvanceRoundAfterCelebration(WinningTeam) }

    AdvanceRoundAfterCelebration(WinningTeam : int)<suspends> : void =
        Sleep(CelebrationDelay)
        # On the match-deciding round the big celebration cinematic needs
        # room, so hold the round advance longer - otherwise native
        # matchpoint ends the game and cuts the cinematic short. By now the
        # tracker has credited the win, so its MatchWinner is reliable.
        var Extend : logic = false
        if (DebugCelebrateEveryRound?):
            set Extend = true
        else:
            W := Tracker.MatchWinner()
            if (W >= 0):
                set Extend = true
        if (Extend?):
            Sleep(MatchWinExtraSeconds)
        if (Instigator := GetPlayspace().GetPlayers()[0]):
            if (WinningTeam = 0):
                EndRoundTeamAWins.Activate(Instigator)     # VERIFY: end_game_device.Activate(agent)
            else if (WinningTeam = 1):
                EndRoundTeamBWins.Activate(Instigator)

    # Fires whichever track VFX sits closest to the cart's final position.
    FireNearestVFX() : void =
        CartPos := CartProp.GetTransform().Translation
        var BestIdx : int = -1
        var BestDist : float = 999999.0
        for (Idx -> FX : TrackVFX):
            D := Distance(FX.GetTransform().Translation, CartPos)
            if (D < BestDist):
                set BestDist = D
                set BestIdx = Idx
        if (BestIdx >= 0, FX := TrackVFX[BestIdx]):
            FX.Enable()      # VERIFY: how a vfx_spawner_device is triggered

    # =================== READOUT ===================
    UpdateBillboard(Net : int) : void =
        MetresToA := Progress * TrackLengthCm / 100.0
        MetresToB := (1.0 - Progress) * TrackLengthCm / 100.0
        Diff := LastACount - LastBCount     # signed: + = Team A ahead, - = Team B ahead
        if (Secs := Round[TimeLeft]):               # Round[] is failable -> wrap it
            Line := "FUSE: {Secs}s\nTeam A pushing: {LastACount}\nTeam B pushing: {LastBCount}\nNet (A-B): {Diff}   [applied: {Net}]\nBomb  A:{MetresToA}m  B:{MetresToB}m"
            ProgressBillboard.SetText(CartMsg(Line))    # VERIFY: billboard_device.SetText(message); \n may or may not render multiline

    # =================== SMALL HELPERS ===================
    # Imbalance magnitude as a float (capped small), so no int->float is needed.
    StepUnits(Net : int)<transacts> : float =
        if (Net < 0):
            return StepUnitsPos(-Net)
        return StepUnitsPos(Net)

    StepUnitsPos(N : int)<transacts> : float =
        if (N >= 3) { return 3.0 }
        if (N = 2) { return 2.0 }
        if (N = 1) { return 1.0 }
        return 0.0

    ClampFloat(V : float, Lo : float, Hi : float)<transacts> : float =
        if (V < Lo) { return Lo }
        if (V > Hi) { return Hi }
        return V
