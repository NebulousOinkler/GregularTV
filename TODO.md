# To do

1. **A servers page as the app's main page.** It lists the Jellyfin servers the app is signed in to, opens one to watch, and adds another (the sign-in screen, as now). Today the app holds one server: its credentials are one Keychain entry, and launching goes straight to live TV. To work out:
   - Keeping several servers' credentials in the Keychain, one entry per server, and signing out of one. The privacy table (README.md and PLAN.md §3) needs a row for it. What the page shows about each server (its address and name) must be only what's needed to sign in again.
   - Whether launching opens the page, or the last server watched with the page one step back.
   - Whether channels, set times and the schedule code stay the same for every server, or belong to each one.
2. **Remote buttons that move around the app correctly**, once the servers page exists. Decide what each button does on each screen (`RemoteControls` in `Sources/GregularScreens/Remote/RemoteControls.swift`), for example:
   - Menu while watching. It opens the guide now and never leaves the app, but it should probably lead back to the servers page. Apple asks that Menu on an app's main screen goes to the Home screen.
   - Getting back from the guide, the channel list and Settings to live TV, and from live TV to the servers page, without a dead end or a surprise exit.
   - Checking each screen with the real Siri Remote behaviour, and with the debug keys in the simulator.
3. **"Buffering…" that may not clear.** Once, just after launch on channel 5 of a real server, the banner said "Buffering…" while a commercial was visibly playing. It wasn't seen again. `ChannelPlayer.isBuffering` is set from the on-screen deck's state on each heartbeat, so a stale value should clear within a second; one that stays suggests `AVPlayerDeck` reported `.waiting` while the picture played (for example, `AVQueuePlayer` waiting to minimise stalls on a clip it had already started), or that the wrong deck was read around a swap. Reproduce with *Show playback diagnostics* on, and watch the deck state it shows.
4. **Tests still to cover**, left out of the walkthrough (`App/GregularTVUITests`, README.md *Debug options*):
   - **Reopening Settings straight after changing quality.** The quality change re-tunes, and Settings should open again at once. The walkthrough's first test tries it, but its steps from the guide back to live TV don't reliably get there first, so it never checks this; fix the steps, then the check.
   - **Settings opening on the quality in use** (`test5SettingsOpensOnTheQualityInUse`). Its screenshot shows Settings reopening with 720p highlighted, as it should, but the test never finished: it hung on its last step, choosing Auto again to put the quality back, and was stopped. So its checks, including the one-line close hint ("Play/Pause, Menu or Done: close"), never reported. Find where `choose("Auto")` hangs (probably moving up from 720p past the focus section), then run it to the end.
   - **Signing in all the way.** The demo server (`scripts/demo-server.py`) has no sign-in endpoints, so the walkthrough stops at the insecure-address message. Add fake ones (`/Users/AuthenticateByName`, `/System/Info/Public`) that accept any name, never a real account's password.
   - **Slides and a light touch on a real remote's touch surface.** XCUIRemote can't slide or touch on Apple TV, so these were only tried with the letter keys (`w`/`a`/`s`/`d`, `t`). Try them on an Apple TV, or with the simulator's own Siri Remote window.

5. **The editing page on a real Apple TV.** In the simulator, Network's `acceptLocalOnly` refused every connection, so the app checks the caller's address itself (`EditingPage.isLocal`). On a device, check that a phone on the same Wi-Fi reaches the address shown, whether tvOS asks for local-network permission the first time (the usage text is set), and that the page stops when its screen closes.

## Done

1. **Custom channels made on the Apple TV**, with a preview, channel codes for sharing them, and custom channels saved as their codes (privacy option (a)). See README.md, *Your own channels*, and PLAN.md §9c.
2. **Programmes at set times ("appointment viewing")**, in `channels.json` and in Settings for any channel, laid over the shared schedule so households sharing a schedule code stay in step, and shared by set-times code. See README.md, *Programmes at set times*, and PLAN.md §9c.

The special rules both needed, with the rule that the same movie never airs twice in a row, are in one registry, `ScheduleRules` (PLAN.md §9c).
