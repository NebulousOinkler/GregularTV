# Feeds: subscribing to someone's channels by link

A working to-do for the feed feature, planned with the user on 2026-10-26 and built from this file. When it's done, the lasting parts move into README, PLAN and AUDIT, and this file is deleted.

## The experience

It works like adding a podcast to a podcast app.

1. **Publishing.** A publisher keeps a few of their own channels (and set times on them) in one block of ten numbers, such as 50–59. On the editing page, *Share as a feed* saves that block as one file, with a name, a line about it, an optional small picture, and whose 8 PM the set times mean. They upload the file to any https host (GitHub Pages, a gist, their own site). Gregular has no backend.
2. **Subscribing is the close look.** A follower pastes the link on the editing page (Apple TV, or the web's channel editor). The app fetches it and shows the feed like a podcast's page: picture or badge, name, publisher, description, and each channel with a one-line summary. The follower picks a free block of ten numbers and presses *Subscribe*. The feed's channels and set times appear at once.
3. **Updates take one tap.** The app checks each feed when it opens, then every 6 hours while running. When a feed has changed, a small dot appears on Settings. The feed's entry shows short *what's new* lines and one *Get update* button. Ignoring it leaves the current version playing.
4. **Feed channels are the feed's.** The follower can't edit them or add set times to them. *Make a copy* turns one into the follower's own channel, which nothing updates.
5. **A link that stops working:** the last accepted version keeps playing, and the feed list marks the link as expired.
6. **Unfollowing** removes everything the feed brought, after a confirmation.
7. **The JSON tab** carries the follower's subscriptions as links, so a second device can follow the same feeds.

## Decisions (the user's, 2026-10-26)

| Question | Decision |
|---|---|
| Format | Our own JSON document at an https link, not RSS |
| What a feed carries | Its own channels and set times on them. Never the schedule code, never anything on the follower's own or bundled channels (option A) |
| Set times on the follower's channels | **Backlog (option D):** a per-feed switch, off by default, letting a feed add set times to the follower's channels |
| Updates | One tap, *Get update*, with short *what's new* lines; out of the way, as a dot on Settings and in the feed list |
| How many | Several feeds, each in a block of ten numbers the follower picks |
| Size | At most 10 channels per feed |
| Editing a feed channel | No, including set times; *Make a copy* instead |
| Subscribing | On the editing page (Apple TV) and in the web's channel editor (opened from Settings). The Apple TV's Settings lists feeds, gets updates and unfollows, but takes no typing |
| Checking | When the app opens, then every 6 hours while it's running |
| Link stops working | Keep the last accepted version, and mark the link as expired in the feed list |
| Unfollowing | Always removes the feed's channels and set times |
| Publishing | *Share as a feed* saves a file to host anywhere over https |
| Time zone | The publisher chooses per feed: the follower's local time, or a named zone |
| Picture | Optional, small and size-limited, from the publisher; a badge with initials when there isn't one |
| Web | No proxy. If a host doesn't let gregular.tv read it (CORS), say so and suggest hosts that do |
| JSON sharing | Carries subscriptions as links |

## Details I chose (to confirm or change)

- **Numbering by block.** A feed's channels sit in one decade on the publisher's side (50–59, say). Each keeps its last digit in the follower's block: the publisher's 52 is the follower's 72 if they chose the 70s. Numbers stay stable across updates, and ten per feed falls out of it. Blocks are 20–29 up to 90–99, the custom channel numbers, and can't overlap the follower's own channels or another feed.
- **The first version applies at once.** Subscribing (on the page, or by pasting JSON that lists a new link) is the consent. Only later changes wait for *Get update*.
- **Picture:** PNG only, embedded in the file (no second request), at most 32 KB and 256×256, checked before anything decodes it. On the web this needs `img-src data:` in the CSP.
- **Expired** means the host answered 404 or 410, or what came back isn't a feed. Not being able to reach it (offline, timeout) shows "Couldn't check; last reached <date>" instead.
- **Plain http:** allowed only on the home network, by the same rule as servers (`ServerAddress.isAllowed`), rather than https only.
- **Redirects:** only within the same host, as for the server (`TransportRules`). The web follows none.
- **What's sent to the feed's host:** a plain GET with `Accept: application/json` and no cookies, credentials or referrer. On Apple TV the User-Agent is just "GregularTV", not the default one naming the OS and device, and `Accept-Language: *`. A browser sends its own.
- **Following saves the page.** On the editing page, *Follow* and *Unfollow* save straight away, along with any other unsaved changes (the page says so); *Get Update* and *Unfollow* ask you to save first if there are changes.
- **Only the last 4 feeds looked at are kept** to follow without fetching again (audit T3).

## The file

```json
{
  "gregularFeed": 1,
  "title": "Dad's Network",
  "publisher": "Dad",
  "description": "Westerns all week, mysteries on Sunday nights.",
  "timeZone": "local",
  "image": "<base64 PNG, optional>",
  "channels": [
    { "number": 52, "name": "Westerns", "plays": "both",
      "rule": { "anyOf": [{ "genre": "Western" }], "allOf": [{ "years": { "from": 1950, "to": 1979 } }] } }
  ],
  "setTimes": [
    { "channel": 52, "programmes": [{ "series": "Columbo", "at": ["20:00"], "days": ["Sun"] }] }
  ]
}
```

- `gregularFeed`: the format's version. A newer one than the app knows fails closed, with "update the app" wording.
- `timeZone`: `"local"`, or an identifier such as `"America/New_York"`.
- `channels` use the editing document's channel shape. All their numbers must be in one decade from 20–29 to 90–99, with at most 10 channels.
- `setTimes` use the editing document's shape without a time zone (the feed's applies), only on the feed's own channels.
- **Limits:** the file is at most 256 KB, the title and publisher at most 60 characters each, and the description at most 300. Everything is checked as codes are (`ChannelLineup.adding`, `FixedTimesAreValid`). Text goes on screen only as text.

## Where things go

| Part | What |
|---|---|
| GregularJellyfin | `PublicFile`: the one gateway for a request that isn't to the media server. https only, no `Authorization`, the size cap, redirects as `TransportRules` allows, checked again on the reply. It uses the same `HTTPTransport` |
| GregularScreens/Feeds | `FeedDocument` (read, check and resolve a file, and make one for *Share as a feed*), `Feed` (a subscription: link, block, accepted version, last reached, expired), `FeedChanges` (the *what's new* lines), and the badge's initials and colour |
| GregularCore | `AppPreferences.feeds`: each subscription as its link, block, accepted file and the date it was last reached |
| AppModel | Subscribe, check (on open and every 6 hours), get update, unfollow, make a copy, `hasFeedUpdates` for the dot. The line-up is the bundled channels, your own, and the feeds' |
| EditingDocument / EditingAPI | `feeds` in the document (link and first number). New endpoints `/api/feeds/look`, `/api/feeds/update` and `/api/feeds/share`. The state lists feeds and their channels |
| Editing page | A *Feeds* tab: paste a link, preview it, pick a block, subscribe; the feed list with *Get update*, *Unfollow* and *Make a copy*; *Share as a feed*. Own channels can't take a number inside a feed's block |
| Apple TV | The Settings section *Feeds* (badge or picture, name, status, *what's new*, *Get update*, *Unfollow*), and the dot on the guide's Settings button |
| Web | The same section in Settings, and the dot on Settings' buttons |
| Text | Every word in `Text/FeedText.swift` |

## To do

- [x] 1. `PublicFile` gateway in GregularJellyfin, with tests: https only, no auth, size cap, redirect rule, User-Agent
- [x] 2. `FeedDocument`: read and check a file, resolve it into a block, make one from your own channels; tests for every limit and the version
- [x] 3. `Feed` and `AppPreferences.feeds`; the privacy check and tables
- [x] 4. `FeedChanges`: the *what's new* lines
- [x] 5. AppModel: subscribe, check, get update, unfollow, make a copy, line-up with feeds, the 6-hour check, `hasFeedUpdates`; tests on a fake transport
- [x] 6. EditingDocument `feeds` and EditingAPI endpoints; own channels and set times refused in a feed's block; tests
- [x] 7. The editing page's *Feeds* tab and *Share as a feed*; local-page CSP `img-src data:`
- [x] 8. Apple TV Settings *Feeds* section and the dot
- [x] 9. Web Settings *Feeds* section, the dot, and `img-src data:` in `_headers`
- [x] 10. Walkthroughs: the demo server serves a feed; the web walkthrough follows it, sees it in Settings and unfollows it. (Apple TV can't be driven to the editing page from a test, so following there is covered by the unit tests; Get Update is covered by unit tests on both.)
- [x] 11. Docs: README (*Feeds*, *Privacy*, *Security*), PLAN §3, §4 and §12, TODO.md (D in the backlog)
- [x] 12. The release audit (AUDIT.md, *Sixth audit*) and the clean-up pass. T1 (what a feed's host learns) was accepted by the user on 2026-10-26, with improving it later as TODO.md item 8. T2 (decoding a stranger's picture) was accepted on 2026-10-26: pictures stay
- [x] 13. Every check and suite, then report to the user. Commit, push and merge only when asked. (The run found two things, both fixed: the 6-hour check kept WasmKit's test run from ending, so tests give `checksFeedsEvery: nil`; and the walkthrough's feed link lacked its `http://`.)
- [x] 14. Close the test gaps (asked 2026-10-26): the demo server serves a feed that changes; the web walkthrough gets Get Update, the dot and the picture, Make a Copy, and Share as a feed's download (which found T9: the file didn't save in Safari or Firefox, now fixed); the Apple TV walkthrough follows a feed through the editing page, gets its update and unfollows it; a unit test for the 6-hour repeat. Then every suite again

## Backlog

- **D:** let a feed set times on the follower's channels, as a per-feed switch, off by default, with clash rules (the follower's own win, then feed order).
