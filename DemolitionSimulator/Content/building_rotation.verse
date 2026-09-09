# =====================================================================
#  BUILDING ROTATION  —  one building on site at a time
#
#  Every prefab root starts stacked at the construction site, inside the
#  prop manipulator's zone, so all their pieces are registered at load.
#  On begin they drop underground, and they're raised back one at a time
#  as contracts complete.
#
#  Buildings CANNOT be brought in from elsewhere: the prop manipulator
#  only registers what's in its zone at load, so a building moved in
#  during play is never counted. Tested and confirmed. Everything has to
#  start here.
#
#  SETUP
#   - Parent each prefab to a creative_prop root. Verse can only move
#     props it can address - it can't reach a gallery prefab's own root.
#   - Place every root at the site, overlapping, inside the zone.
#   - Assign them to Buildings in the order they should appear.
#
#  The site position is read from the first building at startup, so
#  wherever you place them is where they return to.
# =====================================================================

using { /Fortnite.com/Devices }
using { /Verse.org/Random }
using { /Verse.org/Simulation }
using { /UnrealEngine.com/Temporary/SpatialMath }
using { /UnrealEngine.com/Temporary/Diagnostics }

building_rotation_device := class(creative_device):

    # Prefab roots, in the order they should be presented. All placed
    # together at the site.
    @editable Buildings : []creative_prop = array{}

    # How far below the site the waiting ones sit.
    @editable ParkDepthCm : float = 8000.0

    var SitePos : vector3 = vector3{}
    var SiteRot : rotation = IdentityRotation()   # VERIFY: overwritten at startup anyway
    var Current : int = -1

    OnBegin<override>()<suspends> : void =
        Print("[Buildings] {Buildings.Length} prefabs.")
        # Wherever they were placed is the construction site.
        if (First := Buildings[0]):
            T := First.GetTransform()
            set SitePos = T.Translation
            set SiteRot = T.Rotation
        ParkAll()
        RaiseNext()

    ParkAll() : void =
        for (B : Buildings):
            Park(B)

    Park(B : creative_prop) : void =
        Down := vector3{ X := SitePos.X, Y := SitePos.Y, Z := SitePos.Z - ParkDepthCm }
        if (B.TeleportTo[Down, SiteRot]) {}

    # Clear the wreckage and bring the next building up.
    RaiseNext<public>() : void =
        ParkCurrent()
        Next := Current + 1
        if (B := Buildings[Next]):
            if (B.TeleportTo[SitePos, SiteRot]) {}
            set Current = Next
            Print("[Buildings] Raised building {Next}.")
        else:
            Print("[Buildings] No buildings left.")

    # Clear the site and raise a RANDOM building instead of the next in
    # order. Avoids repeating the one just demolished when there's more
    # than one to choose from.
    RaiseRandom<public>() : void =
        ParkCurrent()
        if (Buildings.Length > 0):
            var Pick : int = GetRandomInt(0, Buildings.Length - 1)
            if (Buildings.Length > 1):
                if (Pick = Current):
                    set Pick = Mod[Pick + 1, Buildings.Length] or 0
            if (B := Buildings[Pick]):
                if (B.TeleportTo[SitePos, SiteRot]) {}
                set Current = Pick
                Print("[Buildings] Raised building {Pick} (random).")

    ParkCurrent<public>() : void =
        if (B := Buildings[Current]):
            Park(B)

    # How many are still waiting after the current one.
    Remaining<public>()<transacts> : int =
        R := Buildings.Length - Current - 1
        R
