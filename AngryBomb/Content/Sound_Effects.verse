# =====================================================================
#  SOUND EFFECTS  —  central home for gameplay audio
#
#  Keeps sound logic out of the gameplay devices. Each effect reads state
#  it needs and drives its own Audio Player.
#
#  (Ambient wind is NOT here - that's a separate looping Radio device.)
#
#  CURRENT EFFECTS
#   - Urgency beep: repeats while the bomb is in urgency mode (near the
#     tower it faces, or the final seconds of the fuse). Reads the cart's
#     UrgentShown, so the beep matches the flickering mesh exactly.
#
#  TUNE
#   BeepInterval - seconds between beeps. The clip is ~0.6s, so anything
#                  below that will overlap itself. Default 0.5 as asked;
#                  raise toward 0.7-0.8 if it sounds crowded.
#
#  SETUP: assign the Cart and an Audio Player device holding the beep.
#
#  # VERIFY: audio_player_device.Play()
# =====================================================================

using { /Fortnite.com/Devices }
using { /Verse.org/Simulation }
using { /UnrealEngine.com/Temporary/Diagnostics }

sound_effects_device := class(creative_device):

    @editable Cart : bomb_cart_device = bomb_cart_device{}

    # Audio Player holding the single ~0.6s beep.
    @editable UrgencyBeep : audio_player_device = audio_player_device{}

    @editable BeepInterval : float = 0.5

    # Audio Player holding the tension track.
    @editable TensionMusic : audio_player_device = audio_player_device{}

    # Trigger 1: the fuse running low. Fires ONCE per round, wherever the
    # bomb is.
    @editable TensionOnFuse : logic = true
    @editable TensionStartAt : float = 23.0

    # Trigger 2: the bomb entering urgency by nearing the tower it faces.
    # Fires EACH time urgency is newly entered that way - so if the bomb is
    # pushed back out and later returns, the track plays again.
    @editable TensionOnProximity : logic = false

    # Roughly how long the track runs. Used to know when it has finished,
    # so a proximity re-trigger can restart it rather than being ignored
    # (and so we never cut the track off mid-play to restart it).
    @editable TensionTrackSeconds : float = 22.0

    # Fires once whenever the push state changes - neutral to a team, a
    # team back to neutral, or one team overtaking the other. Mirrors the
    # push ring's colour changes.
    @editable CaptureSting : audio_player_device = audio_player_device{}

    # Looping bed that runs while the bomb is actually walking, and stops
    # when it halts. NOTE: audio_player_device has no Pause - only Play and
    # Stop - so this RESTARTS from the top each time the bomb resumes.
    @editable MovingLoop : audio_player_device = audio_player_device{}

    TickSeconds : float = 0.1     # how often we check whether urgency is on

    var Elapsed : float = 0.0     # time since the last beep
    var TensionPlaying : logic = false
    var TensionElapsed : float = 0.0     # how far into the track we are
    var FuseFired : logic = false        # fuse trigger used this round
    var WasProximityUrgent : logic = false
    var TensionFromProximity : logic = false   # started by proximity, not the fuse
    var LastRing : int = -1              # -1 = nothing observed yet
    var LoopPlaying : logic = false

    OnBegin<override>()<suspends> : void =
        Print("[Sound] Ready.")
        spawn{ UrgencyLoop() }
        spawn{ TensionLoop() }
        spawn{ PushAudioLoop() }

    UrgencyLoop()<suspends> : void =
        loop:
            # Beep only while the round is LIVE and urgency is on. Gating on
            # MatchLive matters because the cart doesn't clear UrgentShown
            # until the next round starts - without this the beep would keep
            # firing over the explosion and the round cinematic.
            var Beeping : logic = false
            if (Cart.MatchLive?):
                if (Cart.UrgentShown?):
                    set Beeping = true
            if (Beeping?):
                set Elapsed = Elapsed + TickSeconds
                if (Elapsed >= BeepInterval):
                    set Elapsed = 0.0
                    UrgencyBeep.Play()       # VERIFY: audio_player_device.Play()
            else:
                # Not beeping: prime the timer so the first beep fires
                # promptly next time urgency kicks in, rather than part-way
                # through an interval.
                set Elapsed = BeepInterval
            Sleep(TickSeconds)

    # Tension track: two independent triggers, both optional.
    TensionLoop()<suspends> : void =
        loop:
            if (Cart.MatchLive?):
                TickTension()
            else:
                StopTension()      # round over - silence and re-arm
            Sleep(TickSeconds)

    TickTension() : void =
        # Advance playback position; once the track has run its length it's
        # free to be started again.
        if (TensionPlaying?):
            set TensionElapsed = TensionElapsed + TickSeconds
            if (TensionElapsed >= TensionTrackSeconds):
                set TensionPlaying = false

        # Edge-detect proximity urgency (urgency that is NOT caused by the
        # fuse being low - i.e. the bomb nearing the tower it faces).
        NowProx := ProximityUrgent()
        var ProxJustStarted : logic = false
        if (NowProx?):
            if (not WasProximityUrgent?):
                set ProxJustStarted = true
        set WasProximityUrgent = NowProx

        # Proximity-driven music stops when the bomb leaves urgency (the
        # other team pushed it back). Fuse-driven music does NOT - the clock
        # is still running wherever the bomb is.
        if (TensionPlaying?):
            if (TensionFromProximity?):
                if (not NowProx?):
                    TensionMusic.Stop()       # VERIFY: audio_player_device.Stop()
                    set TensionPlaying = false
                    set TensionFromProximity = false
                    Print("[Sound] Tension music stopped - urgency over.")

        var FuseTriggered : logic = false
        var ProxTriggered : logic = false
        if (TensionOnFuse?):
            if (not FuseFired?):
                if (Cart.TimeLeft <= TensionStartAt):
                    set FuseTriggered = true
                    set FuseFired = true      # once per round
        if (TensionOnProximity?):
            if (ProxJustStarted?):
                set ProxTriggered = true      # every time it re-enters

        var ShouldStart : logic = false
        if (FuseTriggered?):
            set ShouldStart = true
        if (ProxTriggered?):
            set ShouldStart = true

        if (ShouldStart?):
            if (not TensionPlaying?):         # don't restart mid-track
                TensionMusic.Play()           # VERIFY: audio_player_device.Play()
                set TensionPlaying = true
                set TensionElapsed = 0.0
                # Remember why, so the fuse version isn't cut short.
                set TensionFromProximity = false
                if (ProxTriggered?):
                    if (not FuseTriggered?):
                        set TensionFromProximity = true
                Print("[Sound] Tension music started.")

    # Urgency that comes from proximity rather than the fuse: the cart is
    # showing urgency while the fuse is still above its final-seconds
    # window, so the cause must be the bomb nearing its faced tower.
    ProximityUrgent() : logic =
        var Result : logic = false
        if (Cart.UrgentShown?):
            if (Cart.TimeLeft > Cart.UrgencySeconds):
                set Result = true
        Result

    StopTension() : void =
        if (TensionPlaying?):
            TensionMusic.Stop()               # VERIFY: audio_player_device.Stop()
            set TensionPlaying = false
        set TensionElapsed = 0.0
        set FuseFired = false                 # re-arm for the next round
        set WasProximityUrgent = false
        set TensionFromProximity = false

    # ---- Push audio: a sting when the push state flips, and a loop while
    #      the bomb is actually walking. ----
    PushAudioLoop()<suspends> : void =
        loop:
            if (Cart.MatchLive?):
                TickPushAudio()
            else:
                StopPushAudio()
            Sleep(TickSeconds)

    TickPushAudio() : void =
        # Sting on any change of push state (white->blue, red->white,
        # red->blue, etc). The first observation of a round is skipped so
        # the round doesn't open with a sting.
        Now := RingState()
        if (LastRing <> Now):
            if (LastRing <> -1):
                CaptureSting.Play()       # VERIFY: audio_player_device.Play()
            set LastRing = Now

        # Movement bed follows the legs exactly.
        var WantLoop : logic = false
        if (Cart.CartMoving?):
            set WantLoop = true
        if (WantLoop?):
            if (not LoopPlaying?):
                MovingLoop.Play()
                set LoopPlaying = true
        else:
            if (LoopPlaying?):
                MovingLoop.Stop()         # VERIFY: audio_player_device.Stop()
                set LoopPlaying = false

    # 0 = blue ahead, 1 = red ahead, 2 = tied/neutral. Same rule the push
    # ring uses for its colour.
    RingState() : int =
        A := Cart.LastACount
        B := Cart.LastBCount
        var R : int = 2
        if (A > B):
            set R = 0
        else if (B > A):
            set R = 1
        R

    StopPushAudio() : void =
        if (LoopPlaying?):
            MovingLoop.Stop()
            set LoopPlaying = false
        set LastRing = -1                 # re-arm for the next round
