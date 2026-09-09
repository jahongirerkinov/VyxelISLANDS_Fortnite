# =====================================================================
#  CART HUD  —  framed tug bar + bomb + fixed "BOOM IN" timer
#
#  Timer is FIXED at top-centre: "BOOM IN {secs}s" text on a stretched
#  PuffyBubble3 background. Bomb rides the seam on the bar below. No
#  pulse, no colour-change - clean and reliable.
#
#  The bubble is stretched WIDE (portrait source -> landscape) to hold
#  the text; its rounded corners/tail will stretch a bit. If that looks
#  off, swap the texture for a wide pill. All sizes tune by eye.
# =====================================================================

using { /Fortnite.com/Devices }
using { /Fortnite.com/UI }
using { /Fortnite.com/Game }
using { /Verse.org/Simulation }
using { /Verse.org/Assets }
using { /Verse.org/Colors }
using { /UnrealEngine.com/Temporary/UI }
using { /UnrealEngine.com/Temporary/SpatialMath }
using { /UnrealEngine.com/Temporary/Diagnostics }

HudMsg<localizes>(S : string) : message = "{S}"

hud_state := class<concrete>:
    var Added : logic = false
    var MaybeBlue : ?color_block = false
    var MaybeRed : ?color_block = false
    var MaybeSpacer : ?color_block = false
    # Fuse timer and pusher counts now live in the HUD_UI Widget Blueprint
    # (Burbank + outline), driven through its view-binding variables.
    var MaybeStyled : ?UI.HUD_UI = false


cart_hud_device := class(creative_device):

    @editable Cart : bomb_cart_device = bomb_cart_device{}

    # Round score for the HUD. Safe to reference: the tracker doesn't
    # reference this device or the cart, so there's no linker cycle.
    @editable Tracker : round_score_tracker_device = round_score_tracker_device{}
    @editable RefreshSeconds : float = 0.2

    ColTeamA : string = "2E7BE0"
    ColTeamB : string = "E24B4A"
    ColTimerText : string = "262626"   # dark: readable on the white pill center

    # ---- Sizes (tune by eye) ----
    TrackWidth : float = 565.0
    TrackHeight : float = 30.0      # taller so the fill reaches the frame's inner edges
    FrameWidth : float = 620.0
    FrameHeight : float = 78.0
    BombSize : float = 80.0
    @editable BarTop : float = 95.0   # bar's distance from the top - tune live in the Details panel

    var Huds : [player]hud_state = map{}

    OnBegin<override>()<suspends> : void =
        Print("[CartHUD] Ready.")
        spawn{ HudLoop() }

    HudLoop()<suspends> : void =
        loop:
            for (A : GetPlayspace().GetPlayers(), P := player[A]):
                EnsureHud(P)
            Sleep(RefreshSeconds)

    GetHud(P : player) : hud_state =
        if (H := Huds[P]):
            return H
        New := hud_state{}
        if (set Huds[P] = New) {}
        return New

    EnsureHud(P : player) : void =
        if (PlayerUI := GetPlayerUI[P]):
            H := GetHud(P)
            BuildIfNeeded(PlayerUI, H)
            UpdateHud(H, P)

    CurrentTeam(P : player) : int =
        if (Cart.IsOnTeamIndex[P, 0]):
            return 0
        if (Cart.IsOnTeamIndex[P, 1]):
            return 1
        return -1

    BuildIfNeeded(PlayerUI : player_ui, H : hud_state) : void =
        if (H.Added?):
            return
        HalfTrack := TrackWidth * 0.5
        HalfFrame := FrameWidth * 0.5
        StartFill := TrackWidth * 0.5
        StartSpacer := StartFill - BombSize * 0.5
        BarCentreY := BarTop + TrackHeight * 0.5
        FrameTop := BarCentreY - FrameHeight * 0.5
        BombTop := BarCentreY - BombSize * 0.5

        Frame := texture_block{ DefaultImage := ProgressBarIcon2, DefaultDesiredSize := vector2{X := FrameWidth, Y := FrameHeight} }
        BlueFill := color_block{ DefaultColor := MakeColorFromHex(ColTeamA), DefaultDesiredSize := vector2{X := StartFill, Y := TrackHeight} }
        RedFill := color_block{ DefaultColor := MakeColorFromHex(ColTeamB), DefaultDesiredSize := vector2{X := StartFill, Y := TrackHeight} }
        Spacer := color_block{ DefaultColor := MakeColorFromHex(ColTeamA), DefaultDesiredSize := vector2{X := StartSpacer, Y := 2.0} }
        Spacer.SetVisibility(widget_visibility.Hidden)
        Bomb := texture_block{ DefaultImage := BombLogo2, DefaultDesiredSize := vector2{X := BombSize, Y := BombSize} }

        BarBox := stack_box:
            Orientation := orientation.Horizontal
            Slots := array:
                stack_box_slot{ Widget := RedFill }
                stack_box_slot{ Widget := BlueFill }

        BombBox := stack_box:
            Orientation := orientation.Horizontal
            Slots := array:
                stack_box_slot{ Widget := Spacer }
                stack_box_slot{ Widget := Bomb }

        Root := canvas:
            Slots := array:
                canvas_slot:
                    Anchors := anchors{ Minimum := vector2{X := 0.5, Y := 0.0}, Maximum := vector2{X := 0.5, Y := 0.0} }
                    Offsets := margin{ Left := 0.0 - HalfTrack, Top := BarTop, Right := 0.0, Bottom := 0.0 }
                    Alignment := vector2{X := 0.0, Y := 0.0}
                    SizeToContent := true
                    Widget := BarBox
                canvas_slot:
                    Anchors := anchors{ Minimum := vector2{X := 0.5, Y := 0.0}, Maximum := vector2{X := 0.5, Y := 0.0} }
                    Offsets := margin{ Left := 0.0, Top := FrameTop, Right := 0.0, Bottom := 0.0 }
                    Alignment := vector2{X := 0.5, Y := 0.0}
                    SizeToContent := true
                    Widget := Frame
                canvas_slot:
                    Anchors := anchors{ Minimum := vector2{X := 0.5, Y := 0.0}, Maximum := vector2{X := 0.5, Y := 0.0} }
                    Offsets := margin{ Left := 0.0 - HalfTrack, Top := BombTop, Right := 0.0, Bottom := 0.0 }
                    Alignment := vector2{X := 0.0, Y := 0.0}
                    SizeToContent := true
                    Widget := BombBox

        PlayerUI.AddWidget(Root)

        # The styled text lives in its own Widget Blueprint layer, added on
        # top. Its layout is set inside the blueprint, not here.
        Styled := UI.HUD_UI{}
        PlayerUI.AddWidget(Styled, player_ui_slot{ InputMode := ui_input_mode.None })

        set H.MaybeBlue = option{BlueFill}
        set H.MaybeRed = option{RedFill}
        set H.MaybeSpacer = option{Spacer}
        set H.MaybeStyled = option{Styled}
        set H.Added = true

    UpdateHud(H : hud_state, P : player) : void =
        Progress := ClampProgress(Cart.Progress)
        # RED is the LEFT-hand side (Red vs Blue convention, matching the 3D
        # scoreboards), so the bar is mirrored: the seam is measured from
        # the red end, and everything positioned from the left follows it.
        Seam := (1.0 - Progress) * TrackWidth
        if (Red := H.MaybeRed?):
            Red.SetDesiredSize(vector2{X := Seam, Y := TrackHeight})
        if (Blue := H.MaybeBlue?):
            Blue.SetDesiredSize(vector2{X := TrackWidth - Seam, Y := TrackHeight})
        if (Spacer := H.MaybeSpacer?):
            Spacer.SetDesiredSize(vector2{X := ClampWidth(Seam - BombSize * 0.5), Y := 2.0})
        if (Styled := H.MaybeStyled?):
            if (Secs := Round[Cart.TimeLeft]):
                set Styled.ChangableText = HudMsg("BOOM IN {Secs}s")
            set Styled.BlueTeamPushers = HudMsg("{Cart.LastACount}")
            set Styled.RedTeamPushers = HudMsg("{Cart.LastBCount}")
            set Styled.RedTeamScore = HudMsg("{Tracker.GetRedWins()}")
            set Styled.BlueTeamScore = HudMsg("{Tracker.GetBlueWins()}")
            # Lifetime match wins for THIS player (persists between sessions).
            # >>> rename TrophyCount to your view-binding variable <<<
            set Styled.TrophyCount = HudMsg("{Tracker.GetTrophies(P)}")
            # Team badge visibility - the blueprint shows whichever is true,
            # so a team change needs no rebuild.
            Team := CurrentTeam(P)
            var Blue : logic = false
            var Red : logic = false
            if (Team = 0):
                set Blue = true
            if (Team = 1):
                set Red = true
            set Styled.IsBlueTeam = Blue
            set Styled.IsRedTeam = Red

            # Push direction indicator - same rule the push ring uses:
            # whichever side has more bodies in the zone is pushing.
            A := Cart.LastACount      # blue
            B := Cart.LastBCount      # red
            var BluePush : logic = false
            var RedPush : logic = false
            var Neutral : logic = false
            if (A > B):
                set BluePush = true
            else if (B > A):
                set RedPush = true
            else:
                set Neutral = true
            set Styled.IsBluePushing = BluePush
            set Styled.IsRedPushing = RedPush
            set Styled.IsNeutralPush = Neutral

    ClampWidth(V : float)<transacts> : float =
        if (V < 0.0):
            return 0.0
        return V

    ClampProgress(V : float)<transacts> : float =
        if (V < 0.02):
            return 0.02
        if (V > 0.98):
            return 0.98
        return V
