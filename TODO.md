# To do

Planned features, not built yet. Each has a plan so it can be picked up later.

## 1. Create custom channels easily

**Goal:** make a new channel from the Apple TV itself, without editing `channels.json` and rebuilding the app.

**Today:** the line-up is `Sources/GregularCore/Resources/channels.json`, bundled into the app. A channel is a number, a name, a content rule (`ChannelSource`: all, genre, series, years, tag), item types, a strategy, a seed, `padTo` and a filler.

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
