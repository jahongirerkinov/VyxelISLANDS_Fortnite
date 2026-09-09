# =====================================================================
#  BOMB FOOTSTEPS  —  stomp sound synced to the walk cycle
#
#  The walk animation is a fixed 0.83s cycle = two foot-plants per cycle,
#  so a stomp every ~0.415s. This device counts time only while the bomb
#  is actually MOVING; when it stops or freezes, the timer HOLDS, so the
#  rhythm resumes in phase (no early stomp on resume).
#
#  TUNE:
#    StepInterval - seconds between stomps (0.83 cycle / 2 = ~0.415).
#    StartDelay   - time of the first foot-plant in the cycle (e.g. 0.09).
#                   Applied only to the FIRST stomp; after that the rhythm
#                   is pure StepInterval. Since 2 x StepInterval = the cycle,
#                   the stomps stay locked to the plants forever. The timer
#                   HOLDS while stopped/frozen, so it resumes in phase with
#                   the (also-paused) animation - it never re-syncs.
#
#  Fires the audio by triggering a device (radio / trigger) at each step.
#  Sync is tick-based (not frame-perfect), but a heavy slow "boom" is very
#  forgiving; tune StepInterval (and StartDelay) to line it up by ear.
#
#  STATUS: first pass. # VERIFY the audio trigger call for your device.
# =====================================================================

using { /Fortnite.com/Devices }
using { /Verse.org/Simulation }
using { /UnrealEngine.com/Temporary/Diagnostics }

bomb_footsteps_device := class(creative_device):

    @editable Cart : bomb_cart_device = bomb_cart_device{}

    # The stomp sound (Audio Player device attached to the bomb).
    @editable StompAudio : audio_player_device = audio_player_device{}

    @editable StepInterval : float = 0.415   # 0.83s cycle / 2 foot-plants
    @editable StartDelay : float = 0.09      # time of the FIRST foot-plant in the cycle; applied once, then rhythm self-syncs

    TickSeconds : float = 0.03               # tight tick to keep stomps close to on-beat

    var Elapsed : float = 0.0                # time counted toward the next stomp
    var Started : logic = false              # has the first-ever stomp fired?

    OnBegin<override>()<suspends> : void =
        Print("[BombFootsteps] Ready.")
        spawn{ StepLoop() }

    StepLoop()<suspends> : void =
        loop:
            if (BombMoving[]):
                OnMovingTick()
            # Stopped/frozen: do NOTHING - the timer HOLDS, so the rhythm
            # resumes in phase with the (also-paused) animation. Because
            # 2 x StepInterval = the 0.83s cycle, the stomps stay locked to
            # the foot-plants indefinitely once aligned.
            Sleep(TickSeconds)

    OnMovingTick() : void =
        set Elapsed = Elapsed + TickSeconds
        if (Started?):
            # rhythm: a stomp every StepInterval, keeping the remainder so
            # tiny tick rounding doesn't accumulate into drift
            if (Elapsed >= StepInterval):
                set Elapsed = Elapsed - StepInterval
                Stomp()
        else:
            # first-EVER stomp lands at StartDelay (the first foot-plant in
            # the cycle, e.g. 0.09s); after that it's pure StepInterval
            if (Elapsed >= StartDelay):
                set Elapsed = Elapsed - StartDelay
                set Started = true
                Stomp()

    # Moving = match live, not frozen, and the legs are actually playing.
    BombMoving()<transacts><decides> : void =
        Cart.MatchLive?
        Cart.CartMoving?                     # cart already tracks whether the legs are walking

    Stomp() : void =
        StompAudio.Play()                    # VERIFY: audio_player_device.Play()
