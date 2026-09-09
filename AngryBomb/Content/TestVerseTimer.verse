# =====================================================================
#  TEST VERSE TIMER  —  throwaway test device
#  Bridges Verse -> Widget Blueprint via a native hud_message_device.
#  The HUDMessage device's "HUD Widget" is set to TestWB (in-editor),
#  and this Verse device drives its text through the device's own
#  native, guaranteed-working Verse API (SetText/Show).
#  Safe to delete.
# =====================================================================

using { /Fortnite.com/Devices }
using { /Fortnite.com/Game }
using { /Verse.org/Simulation }
using { /UnrealEngine.com/Temporary/Diagnostics }

BridgeMsg<localizes>(S : string) : message = "{S}"

test_verse_timer_device := class(creative_device):

    @editable DisplayText : string = "Hello Verse"

    # Point this at the HUDMessage device that has TestWB assigned as its HUD Widget.
    @editable Messenger : hud_message_device = hud_message_device{}

    OnBegin<override>()<suspends> : void =
        Print("[TestVerseTimer] Ready.")
        Messenger.SetText(BridgeMsg(DisplayText))
        Messenger.Show()
