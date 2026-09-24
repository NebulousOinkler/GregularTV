# To do

Planned features, not built yet. Each has a plan so it can be picked up later.

## 1. Create custom channels easily

**Goal:** make a new channel from the Apple TV itself, without editing `channels.json` and rebuilding the app.

**Today:** the line-up is `Sources/GregularTVCore/Resources/channels.json`, bundled into the app. A channel is a number, a name, a content rule (`ChannelSource`: all, genre, series, years, tag), item types, a strategy, a seed, `padTo` and a filler.

**Plan**
1. **Editor screen.** Add *Settings › Channels › Add Channel*, a short form:
   - name, and a number from a free range (for example 20–99, so it never clashes with the bundled channels);
   - episodes, movies or both;
   - one content rule, picked from lists built from the library already in memory: genres, series, a year range, or tags;
   - optional: half-hour slots and commercials (on by default, like every channel).
   Strategy, seed and filler take the defaults (`derangement`, a seed made from the number, `derangement`), so there's nothing technical to choose.
2. **Preview.** Before saving, show how many programmes match, and the next few hours as they'd air. Both come from `ChannelSchedule` with no server calls.
3. **Merge into the line-up.** `ChannelLineup` gains the custom channels alongside the bundled ones. They're built, hidden when empty, and listed in the guide exactly like bundled channels. Edit and Delete sit next to Add.
4. **Keep the schedule code meaningful.** The same code only gives the same schedule if both Apple TVs have the same channels. Add a **channel code**: the channel's definition packed into a short text to type into another Apple TV (like the schedule code), so households can share custom channels.
5. **Tests:** decode and encode round trips, number clashes rejected, a custom channel's schedule identical on two "devices" given the same code and channel code, and the privacy test extended.

**Decision needed first: privacy.** Saving a custom channel means saving its rule on the Apple TV. A rule such as *genre = Comedy* or *series = Taskmaster* names things in your library, and the privacy rules only allow storing what's needed to stream. Options:
- **(a)** Allow it, as client configuration the viewer typed. It goes in `AppPreferences`, never with IDs, artwork or anything fetched beyond the name used in the rule. `scripts/privacy-check.sh` and the privacy tests would be updated to allow exactly this.
- **(b)** Store custom channels only as channel codes the viewer keeps elsewhere, typed in each launch. Nothing is saved on the device, but it's clumsy.
- **(c)** Allow only rules that don't name library content (item types and year ranges).

Recommendation: (a), with the settings screen saying what's stored.

## 2. Fixed-time programmes ("appointment viewing")

**Goal:** on a channel, insist that certain programmes always air at set times, once or N times a day (for example *The Simpsons* at 6:00 PM and 6:30 PM, or a movie every day at 8:00 PM), with every remaining slot filled by the derangement as now.

**Today:** `ChannelSchedule` cuts time into 24-hour runs from the channel's epoch. A `SlotWalker` places programmes back to back through each run, and at the run's end passes over up to 15 programmes that wouldn't fit, then fills what's left with commercials. Everything is computed on demand from the channel key and the run number, so nothing is stored.

**Plan**
1. **Configuration** in `channels.json`, per channel:
   ```json
   "timeZone": "America/New_York",
   "fixed": [
     { "series": "The Simpsons", "at": ["18:00", "18:30"] },
     { "item": "Groundhog Day", "at": ["20:00"], "days": ["Feb 2"] }
   ]
   ```
   - Each entry matches a series or a single item, by name as the other content rules do, and gives local times.
   - An optional `days` limits it to weekdays or dates.
   - `timeZone` is required with `fixed`: every Apple TV must agree on what "6:00 PM" means, so it can't be the device's own zone.
   - Validation at load: times inside a day, no two fixed slots overlapping, and each fixed programme's slot fits before the next fixed time.
2. **Pinned slots come first.** For each run, work out the pinned instants by turning the run's date plus each local time into a moment in `timeZone`. That also handles daylight-saving days correctly. Each pinned programme gets a slot of its length rounded up by `padTo`, starting exactly at its time.
   - **Runs follow the local day.** Runs start at midnight UTC today. A programme pinned at 7:30 PM in New York (23:30 UTC) could then run across a run boundary. So a channel with `fixed` starts its runs at local midnight in `timeZone`, and a run is one calendar day: 23 or 25 hours on daylight-saving days. `runIndex(containing:)` becomes "days since the epoch in `timeZone`", still one calculation with no replay.
3. **The derangement fills the gaps.** The `SlotWalker` treats each pinned slot as a hard edge, the way it already treats the end of a run:
   - it fills up to the edge with the derangement stream;
   - it passes over programmes that wouldn't finish in time (the existing up-to-15 rule);
   - it gives any leftover to the last slot before the edge, so it becomes a commercial break before the pinned programme.
   The derangement stream carries on across pinned slots, so the shuffle is unchanged apart from being interrupted.
4. **Which episode a pinned series plays:** its own counter, the number of pinned airings of that series since the epoch, counted from the calendar: the days it was scheduled × its times per day, plus its index today. So it steps forward one episode per airing, cycling at the end, and can be worked out for any day without replaying history. Movies just play.
5. **Kept out of the shuffle (optional):** a flag `"exclusive": true` removes the pinned series from the channel's derangement, so it only appears at its set times.
6. **Everything else follows automatically:** `tune(at:)`, `airings(from:to:)`, the guide, commercial breaks and the player all read from the `SlotWalker`, so pinned programmes need no player or UI changes.
7. **Tests:**
   - a pinned programme airs at exactly its time every day for a year, including DST changes;
   - the gaps are filled with no overlaps;
   - the derangement order is preserved outside pinned slots;
   - the pinned series' episodes go up by one per airing;
   - validation rejects overlapping times;
   - laziness: tuning still walks at most a day of programmes.

**Later, with feature 1:** add fixed-time programmes to the channel editor.

## 3. Show clearly when a channel's programme is over and it's in a break

**Goal:** at a glance, anywhere a channel is shown, tell apart "the programme is on" from "the programme has ended and the channel is in a commercial break (or blank airtime) until the next one". Clean and simple: one consistent look, no extra screens or settings.

**Today:**
- On the watch screen, the banner already says **Commercial break · Back at 12:00 AM with Clannad** and stays up for the whole break.
- The **channel list** (`ChannelListView.swift`, `ChannelRow`) uses `programme(at:)`. In a break it still shows the finished programme's title, a full progress bar and "until 11:42 PM", a time already past. That reads as if the programme is still on.
- The **guide** (`GuideView.swift`) draws each programme as one cell across its whole slot, break included. Nothing marks where the programme stops and the break starts.

**Plan**
1. **One question in Core.** `ChannelSchedule.commercialBreak(at:)` already returns the break's span. Add a small `Onscreen` value (`.programme(Airing)` or `.breakBefore(next: Airing, until: Date)`) returned by one method, e.g. `nowShowing(at:)`, so every view asks the same question the same way. A padding gap (no clips, or commercials off) counts as a break too: the programme has ended either way. Pure calculation, no server calls, nothing stored.
2. **Channel list.** In a break the row reads, in the same layout:
   - title line: **Up next: Clannad**
   - progress bar: the break's progress, in a dimmer style;
   - caption: **Commercial break · starts 12:00 AM**.
3. **Guide.** Split each cell's slot visually: the programme part as now, and the break as a thin, darker tail at the cell's right edge (no text; it's usually too narrow). Focusing a cell during its break shows "Programme ended · commercial break until 12:00 AM" in the detail line, with the time range showing the programme's real end.
4. **Watch screen** is unchanged: the banner already covers the break. For consistency, use the same wording as the channel list ("Commercial break").
5. **One style for "break":** a single colour and style (e.g. secondary colour, a small `tv` or `pause` symbol) used in the list, the guide tail and the banner, so it reads the same everywhere.
6. **Tests:**
   - Core: `nowShowing(at:)` returns the programme just before its end, a break just after, and the next programme at the slot end, including commercials off and a gap of 60 s or less.
   - App: the channel list row's text for a channel in a break.

**Keep it simple:** no new settings, no new screens, no extra requests to Jellyfin.

## 4. Finish the re-encode retry fix (stashed)

**Goal:** when Jellyfin can't re-encode a programme fast enough (seen with *Casper* and *Singin' in the Rain* on the Raspberry Pi), stop repeating the same request that just failed, and stop starting expensive transcodes for the last minute of a programme.

**Status:** written and set aside, not finished. The code is in `stash/reencode-retry.patch`. The app does **not** include it; `ChannelPlayer.swift` and the tests are back to their state before the change.

**What the patch does** (all in `App/GregularTV/Player/ChannelPlayer.swift`, plus tests):
1. **Retry with less work.** When a programme Jellyfin re-encodes fails or stalls, the retry asks for 720p, then one step lower on each further failure (4 Mbps → 1.5 Mbps), for that programme only. It uses the existing programme fix (`fixedProgramme` / `programmeFix`), so Settings shows it, and it goes back to standard on the next programme or a channel change. The server's processor is the bottleneck, not the connection, so in Auto it no longer re-measures the connection before this kind of retry. New helper: `stepDownAfterReencodeFailure(of:from:)`, called from `fail(_:airing:)`.
2. **Don't start with too little left.** A programme Jellyfin would re-encode isn't started with under `minReencodedTimeLeft` (180 s) to go. The screen is blank with "Up next" until the break after it, or the next programme if there's no break. Checked in `tune()` right after the PlaybackInfo request; the stream itself is never requested.
3. **Tests:**
   - `ProgrammeFixTests.aReencodeThatFailsRetriesAt720pThenLower`: expects requested caps 10 → 4 → 1.5 Mbps and the fix shown as 720p, then Step Down. `ProgrammeFixTests.Server` gains a `reply` parameter for this.
   - `HeadStartTests.aReencodedProgrammeWithTooLittleLeftIsntStarted` and `aRemuxedProgrammeWithLittleLeftStillPlays`. The `player(reply:)` helper gains an `elapsed` parameter.

**To finish**
1. Apply the patch from the project folder (check first, then apply):
   ```bash
   patch -p1 --dry-run < stash/reencode-retry.patch
   patch -p1 < stash/reencode-retry.patch
   ```
   If the dry run reports rejected hunks, those files have changed since; apply the listed changes by hand from the patch.
2. **Fix the failing test.** The app test run failed when the work was stopped, and which test failed was never identified. Run the app tests and read the failures:
   ```bash
   xcodebuild test -project App/GregularTV.xcodeproj -scheme GregularTV -destination 'platform=tvOS Simulator,name=GregularTV Tests' -derivedDataPath .build/xcode-app 2>&1 | grep -E "recorded an issue|failed|TEST (SUCCEEDED|FAILED)"
   ```
   Likely suspects:
   - `aReencodeThatFailsRetriesAt720pThenLower`: it depends on real failure timing (DNS for `tv.invalid`, the 5 s retry wait, the head-start cushion wait) and may need longer waits.
   - `aReencodedProgrammeWithTooLittleLeftIsntStarted`: the break check or the `until` time may not match the test's expectation.
3. Run `swift test` and `scripts/privacy-check.sh` too, then rebuild Release and watch a channel whose programme Jellyfin re-encodes.
4. Update the docs: the header comment in `ChannelPlayer.swift` is already in the patch; add the behaviour to README (playback section) and PLAN.
5. Delete `stash/reencode-retry.patch` (and the empty `stash/` folder) once it's applied.

**Undo, if needed:** `patch -p1 -R < stash/reencode-retry.patch` reverses it.
