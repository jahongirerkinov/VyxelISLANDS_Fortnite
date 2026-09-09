# =====================================================================
#  SCOREBOARD  —  3D number props below the lobby, driven by the score
#
#  Reads the match score from the round_score_tracker (single source of
#  truth) and shows exactly one BLUE number (0-3) and one RED number (0-3),
#  hiding the rest. Updates only when the score changes (no flicker).
#
#  These are creative_props, so Show()/Hide() is reliable.
#
#  SETUP:
#   - Assign the Tracker.
#   - Assign the 8 number props: Blue0..Blue3 and Red0..Red3.
#   - (Supports scores 0-3, matching WinsToWinMatch = 3. If you raise the
#      win target later, add more number props + slots here.)
# =====================================================================

using { /Fortnite.com/Devices }
using { /Verse.org/Simulation }
using { /UnrealEngine.com/Temporary/Diagnostics }

scoreboard_device := class(creative_device):

    @editable Tracker : round_score_tracker_device = round_score_tracker_device{}

    # Blue number props, index = the number shown.
    @editable Blue0 : creative_prop = creative_prop{}
    @editable Blue1 : creative_prop = creative_prop{}
    @editable Blue2 : creative_prop = creative_prop{}
    @editable Blue3 : creative_prop = creative_prop{}
    # Red number props.
    @editable Red0 : creative_prop = creative_prop{}
    @editable Red1 : creative_prop = creative_prop{}
    @editable Red2 : creative_prop = creative_prop{}
    @editable Red3 : creative_prop = creative_prop{}

    @editable RefreshSeconds : float = 0.25

    # Last shown values, so we only update props on a change.
    var ShownBlue : int = -1
    var ShownRed : int = -1

    OnBegin<override>()<suspends> : void =
        Print("[Scoreboard] Ready.")
        loop:
            Refresh()
            Sleep(RefreshSeconds)

    Refresh() : void =
        B := Tracker.GetBlueWins()
        R := Tracker.GetRedWins()
        if (B <> ShownBlue):
            ShowBlue(B)
            set ShownBlue = B
        if (R <> ShownRed):
            ShowRed(R)
            set ShownRed = R

    # Show only the matching blue number, hide the others.
    ShowBlue(N : int) : void =
        HideAllBlue()
        if (N = 0) { Blue0.Show() }
        else if (N = 1) { Blue1.Show() }
        else if (N = 2) { Blue2.Show() }
        else if (N = 3) { Blue3.Show() }

    ShowRed(N : int) : void =
        HideAllRed()
        if (N = 0) { Red0.Show() }
        else if (N = 1) { Red1.Show() }
        else if (N = 2) { Red2.Show() }
        else if (N = 3) { Red3.Show() }

    HideAllBlue() : void =
        Blue0.Hide()
        Blue1.Hide()
        Blue2.Hide()
        Blue3.Hide()

    HideAllRed() : void =
        Red0.Hide()
        Red1.Hide()
        Red2.Hide()
        Red3.Hide()
