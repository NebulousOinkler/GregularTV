# To do

1. **A servers page as the app's main page.** It lists the Jellyfin servers the app is signed in to, opens one to watch, and adds another (the sign-in screen, as now). Today the app holds one server: its credentials are one Keychain entry, and launching goes straight to live TV. To work out:
   - Keeping several servers' credentials in the Keychain, one entry per server, and signing out of one. The privacy table (README.md and PLAN.md §3) needs a row for it. What the page shows about each server (its address and name) must be only what's needed to sign in again.
   - Whether launching opens the page, or the last server watched with the page one step back.
   - Whether channels, set times and the schedule code stay the same for every server, or belong to each one.
2. **Remote buttons that move around the app correctly**, once the servers page exists. Decide what each button does on each screen (`RemoteControls` in `Sources/GregularScreens/Remote/RemoteControls.swift`), for example:
   - Menu while watching. It opens the guide now and never leaves the app, but it should probably lead back to the servers page. Apple asks that Menu on an app's main screen goes to the Home screen.
   - Getting back from the guide, the channel list and Settings to live TV, and from live TV to the servers page, without a dead end or a surprise exit.
   - Checking each screen with the real Siri Remote behaviour, and with the debug keys in the simulator.

## Done

1. **Custom channels made on the Apple TV**, with a preview, channel codes for sharing them, and custom channels saved as their codes (privacy option (a)). See README.md, *Your own channels*, and PLAN.md §9c.
2. **Programmes at set times ("appointment viewing")**, in `channels.json` and in Settings for any channel, laid over the shared schedule so households sharing a schedule code stay in step, and shared by set-times code. See README.md, *Programmes at set times*, and PLAN.md §9c.

The special rules both needed, with the rule that the same movie never airs twice in a row, are in one registry, `ScheduleRules` (PLAN.md §9c).
