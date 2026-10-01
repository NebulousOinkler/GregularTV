# To do

1. **The main page and Menu on a real Siri Remote.** Built 2026-10-01 (see Done). Check on an Apple TV: holding a click on a server opens its Sign Out menu, Menu goes back one level at a time (guide → live TV → main page → Home screen), click ▼ and slide ▲ open the guide reliably with the real remote (and a light touch near the bottom edge doesn't), and the channel carries on smoothly behind the main page. Also how the main page looks with several servers, and a server name that's long.
2. **"Buffering…" that may not clear.** Once, just after launch on channel 5 of a real server, the banner said "Buffering…" while a commercial was visibly playing. It wasn't seen again. `ChannelPlayer.isBuffering` is set from the on-screen deck's state on each heartbeat, so a stale value should clear within a second; one that stays suggests `AVPlayerDeck` reported `.waiting` while the picture played (for example, `AVQueuePlayer` waiting to minimise stalls on a clip it had already started), or that the wrong deck was read around a swap. Reproduce with *Show playback diagnostics* on, and watch the deck state it shows.
3. **Tests still to cover**, left out of the walkthrough (`App/GregularTVUITests`, README.md *Debug options*):
   - **Signing in all the way.** The demo server (`scripts/demo-server.py`) has no sign-in endpoints, so the walkthrough stops at the insecure-address message. Add fake ones (`/Users/AuthenticateByName`, `/System/Info/Public`) that accept any name, never a real account's password.
   - **Slides and a light touch on a real remote's touch surface.** XCUIRemote can't slide or touch on Apple TV, so these were only tried with the letter keys (`w`/`a`/`s`/`d`, `t`). Try them on an Apple TV, or with the simulator's own Siri Remote window.

4. **The editing page on a real Apple TV.** In the simulator, Network's `acceptLocalOnly` refused every connection, so the app checks the caller's address itself (`EditingPage.isLocal`). On a device, check that a phone on the same Wi-Fi reaches the address shown, whether tvOS asks for local-network permission the first time (the usage text is set), and that the page stops when its screen closes.

## Done


1. **Custom channels made on the Apple TV**, with a preview, channel codes for sharing them, and custom channels saved as their codes (privacy option (a)). See README.md, *Your own channels*, and PLAN.md §9c.
2. **Programmes at set times ("appointment viewing")**, in `channels.json` and in Settings for any channel, laid over the shared schedule so households sharing a schedule code stay in step, and shared by set-times code. See README.md, *Programmes at set times*, and PLAN.md §9c.
3. **A main page of servers, and Menu.** The app opens on the servers signed in to (several, in one Keychain item, the one watched last first; names asked live, never stored), with Add a Server and Sign Out of each. Schedule code, channels and set times are shared by every server. Menu goes back one level at a time (guide → live TV → main page → Home screen); the guide opens with click ▼ or slide ▲, and the channel plays on behind the main page so going back is instant. See README.md, *The main page and your servers*, and `RemoteControls`.

The special rules both needed, with the rule that the same movie never airs twice in a row, are in one registry, `ScheduleRules` (PLAN.md §9c).
