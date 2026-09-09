# =====================================================================
#  PROP SPINNER  —  tiny standalone device
#  Rotates a placed prop continuously for the whole match. Cosmetic.
#  Drop this device in, point CartProp... no - point SpinProp at the
#  spinner, tune the two numbers, done. Independent of the cart code.
#
#  NOTE: yaw is rotation about the vertical (up) axis. If your spinner
#  should spin about a different axis, change SpinAxis in the editor.
# =====================================================================

using { /Fortnite.com/Devices }
using { /Verse.org/Simulation }
using { /UnrealEngine.com/Temporary/SpatialMath }
using { /UnrealEngine.com/Temporary/Diagnostics }

prop_spinner_device := class(creative_device):

    # The prop to spin.
    @editable SpinProp : creative_prop = creative_prop{}

    # Degrees turned per second. Negative reverses direction.
    @editable DegreesPerSecond : float = 30.0

    # How often the rotation updates (seconds). Smaller = smoother but
    # more work; 0.05 (20x/sec) looks smooth, 0.1 is fine for slow spins.
    @editable TickInterval : float = 0.05

    OnBegin<override>()<suspends> : void =
        Print("[Spinner] Spinning at {DegreesPerSecond} deg/s.")
        spawn{ SpinLoop() }

    SpinLoop()<suspends> : void =
        # Radians to add each tick = deg/s * tick / (180/pi).
        StepDegrees := DegreesPerSecond * TickInterval
        StepRadians := StepDegrees * 3.1415926535 / 180.0
        loop:
            RotateStep(StepRadians)
            Sleep(TickInterval)

    RotateStep(DeltaRadians : float) : void =
        Current := SpinProp.GetTransform()
        # Rotate the current orientation a little further about the up axis.
        UpAxis := vector3{ X := 0.0, Y := 0.0, Z := 1.0 }   # editor: change if needed
        Spun := Current.Rotation.RotateBy(MakeRotation(UpAxis, DeltaRadians))   # VERIFY: RotateBy / MakeRotation
        if (SpinProp.TeleportTo[Current.Translation, Spun]) {}   # VERIFY: prop.TeleportTo[pos, rot]
