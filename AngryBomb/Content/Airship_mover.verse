# =====================================================================
#  AIRSHIP MOVER  —  flies a prop in an endless loop through waypoints
#
#  Place the airship prop and 6 marker props around the orbit. The airship
#  flies 1 -> 2 -> 3 -> 4 -> 5 -> 6 -> 1 -> ... forever, moving to each
#  marker's POSITION *and* ROTATION - so to control which way the airship
#  faces along the path, just ROTATE each marker in the editor to point the
#  direction you want the airship heading there. (No facing math needed.)
#
#  TUNE:
#    Speed - metres/second. Each leg's time is computed from the real
#            distance between markers, so the airship moves at a CONSTANT
#            speed no matter how far apart the points are.
#
#  Slow + far = straight legs between 6 points read as a smooth orbit.
#
#  STATUS: first pass. MoveTo(pos, rot, secs) is the confirmed prop-move
#  pattern; # VERIFY on compile.
# =====================================================================

using { /Fortnite.com/Devices }
using { /Verse.org/Simulation }
using { /UnrealEngine.com/Temporary/SpatialMath }
using { /UnrealEngine.com/Temporary/Diagnostics }

airship_mover_device := class(creative_device):

    @editable Airship : creative_prop = creative_prop{}

    # Six orbit waypoints, in order. Rotate each marker in the editor to
    # set which way the airship faces as it reaches that point.
    @editable P1 : creative_prop = creative_prop{}
    @editable P2 : creative_prop = creative_prop{}
    @editable P3 : creative_prop = creative_prop{}
    @editable P4 : creative_prop = creative_prop{}
    @editable P5 : creative_prop = creative_prop{}
    @editable P6 : creative_prop = creative_prop{}
    @editable P7 : creative_prop = creative_prop{}

    @editable Speed : float = 4.0        # metres/second (slow drift)

    OnBegin<override>()<suspends> : void =
        Print("[Airship] Ready.")
        # Start ON the path: snap instantly to P1 so the first leg isn't a
        # giant slow crawl from wherever the airship was placed.
        StartT := P1.GetTransform()
        if (Airship.TeleportTo[StartT.Translation, StartT.Rotation]) {}   # snap onto P1
        spawn{ FlyLoop() }

    FlyLoop()<suspends> : void =
        loop:
            FlyTo(P2)      # already at P1, so head to P2 first
            FlyTo(P3)
            FlyTo(P4)
            FlyTo(P5)
            FlyTo(P6)
            FlyTo(P7)
            FlyTo(P1)

    MinLegSeconds : float = 0.25         # floor so MoveTo never gets a ~0 duration

    FlyTo(Marker : creative_prop)<suspends> : void =
        Here := Airship.GetTransform().Translation
        There := Marker.GetTransform()
        Dist := Distance(Here, There.Translation)   # cm
        var Secs : float = Dist / (Speed * 100.0)
        if (Secs < MinLegSeconds):
            set Secs = MinLegSeconds
        Airship.MoveTo(There.Translation, There.Rotation, Secs)   # VERIFY: creative_prop.MoveTo(pos, rot, secs)
