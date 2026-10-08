# Gregular TV and Tunarr

[Tunarr](https://github.com/chrisbenincasa/tunarr) also turns a media library into live TV channels. It's the best-known project of its kind. This compares it, as of v2026.9.0 (26 September 2026), with Gregular TV 1.2. Each list is ordered by how much the difference matters to someone watching.

## How they differ at heart

| | Gregular TV | Tunarr |
|---|---|---|
| What it is | An Apple TV app, and the same app in a web browser (gregular.tv) | A server (Docker or a binary) with a web interface |
| Where channels play | On the Apple TV running the app, or in a browser on a phone, tablet or computer | Anywhere that can play its streams: Plex or Jellyfin Live TV, IPTV apps (UHF on Apple TV, TiviMate, VLC), a web player |
| Sources | One Jellyfin server | Plex, Jellyfin, Emby and local folders, mixed |
| How a channel is defined | A rule (genre, series, years, tag, or everything) and a strategy. The schedule is worked out from the clock and a seed, so it never needs saving or rebuilding | A line-up you build in the web editor, by hand or with the scheduling tools. It's saved and loops |
| Video | Jellyfin plays the file as it is where it can, and transcodes only what the Apple TV can't play | Always re-encoded with FFmpeg, so programmes from different files join seamlessly |
| Data kept | Credentials in the Keychain, and settings. No library, schedule, history or logs | A server database of sources, channels, line-ups and filler, plus logs and backups |

## What Tunarr has that Gregular TV doesn't

1. **Watching on any device.** Tunarr channels play on phones, tablets, computers, Android TV, Fire TV, Roku, smart TVs and the web, through Plex or Jellyfin Live TV or an IPTV app. Gregular TV plays on an Apple TV and in a web browser (gregular.tv), but not in IPTV apps, or on Android TV, Fire TV, Roku or smart TVs except through a browser.
2. **Subtitles and audio language.** Tunarr sets the subtitle and audio-language preferences for each channel. Gregular TV never shows subtitles: it asks Jellyfin for none, to avoid burning them into the picture, which would force a full transcode. It plays each file's default audio track.
3. **Recording (DVR).** Through Plex or Jellyfin Live TV, a Tunarr channel can be recorded like an antenna channel. Gregular TV can't record.
4. **More than one library server, and other kinds.** Tunarr mixes Plex, Jellyfin, Emby and local folders on one channel. Gregular TV watches one Jellyfin server at a time, though it can be signed in to several.
5. **A full channel editor.** Tunarr's editor works in a web browser:
   - drag-and-drop line-ups;
   - search, filter and sort across every library;
   - custom shows;
   - smart collections (saved searches).

   Gregular TV makes custom channels on the TV itself. Each one has a single rule, and its number must be from 20 to 99. The 16 bundled channels, which adapt to the library, are changed in `channels.json`, which means rebuilding the app.
6. **Richer scheduling.** Tunarr's scheduling tools:
   - time slots by day or week, with padding and a "max lateness" allowance;
   - a slot editor with fixed or random slots;
   - block shuffle and cyclic shuffle;
   - slot linking, so slots share one show's episode order, either continuing it or rerunning it later the same day;
   - replicate and consolidate.

   Gregular TV has five strategies and set times laid over the shared schedule. That covers "this series at 6 PM on weekdays", but not a whole channel built from time blocks, such as cartoons on Saturday mornings.
7. **Richer filler.** Tunarr has several filler lists per channel. Each list has a weight, a cooldown for the list, and a cooldown before the same clip can play again. Filler can go in several places:
   - at the head or tail of a slot;
   - before or after a programme;
   - mid-roll;
   - as fallback.

   So bumpers, idents, music videos and commercials can mix. Gregular TV has one `Commercials` library. Each pass through it is shuffled, and it's used after programmes and mid-roll. It skips clips Jellyfin would have to re-encode.
8. **Channel logos and on-screen watermarks.** Gregular TV draws channel names only.
9. **Any file plays, and every channel looks the same.** Because Tunarr always re-encodes, odd codecs, frame rates and loudness are evened out. Hardware encoding is supported (NVENC, VAAPI, QuickSync, VideoToolbox), with transcode profiles for each channel. Gregular TV relies on what the Apple TV and Jellyfin can do, which is usually better quality, but files can differ in look and loudness.
10. **Music and music videos as sources.** Gregular TV uses episodes and movies only.
11. **Server admin.** Tunarr has:
    - automatic configuration backups;
    - an API;
    - optional basic auth;
    - play-status reporting to each source server, which can be configured.

    Gregular TV deliberately never reports what you watched (see below).

## What Gregular TV has that Tunarr doesn't

1. **Nothing to host.** You install the app and sign in to Jellyfin. There's no server, Docker, FFmpeg or second app, and no extra machine kept on to transcode. Tunarr needs all of that, plus a client app to watch.
2. **An app made for the Siri Remote.** Gregular TV is designed for the remote:
   - Channel surfing by clicking the pad's edges, with a banner previewing each channel.
   - A second player, so the next programme or channel is ready, with fades between them.
   - A slide for the channel list and a light touch for the info banner.
   - A six-hour guide on Menu, and Settings on click and hold.
   - Pause, then jump back to live.
   - A "Commercial break · Back at 9:30 PM" badge and "Up next" cards.

   With Tunarr on an Apple TV, the experience is whatever the IPTV app or Plex provides.
3. **Original quality, and a light load on the server.** Gregular TV plays files as they are where it can, so the picture is the original. It adds no transcoding load beyond Jellyfin's own. Each Apple TV sets its own streaming quality. A programme that fails or stalls is retried at lower quality, for that programme only. Tunarr re-encodes every stream it serves.
4. **Privacy by design.** The app stores no library data, schedules, history or logs, and never reports what you watch to Jellyfin as history. Nothing appears in "Now Playing", and watched status and resume points are untouched. A build check enforces this, along with Apple's privacy manifest. Tunarr is a server that keeps a database of your library and logs. It can update play status on each source server, and that can be configured for each server.
5. **Schedules that never run out or need rebuilding.** Gregular TV works a channel's schedule out from a seed and the clock. Any moment can be looked up directly, nothing is saved, and new episodes join at the next launch. Tunarr loops a saved line-up. New items join when the schedule is generated again, from smart collections and the slot tools.
6. **The same channels in another household, with no shared server.** Two Apple TVs show the same programmes at the same moment if they have the same library and the same codes:
   - a 10-character **schedule code**;
   - **channel codes** for custom channels;
   - **set-times codes** for set times.

   The codes are short enough to type. To share Tunarr channels, everyone streams from one Tunarr server, so it has to be reachable and has to transcode for each viewer.
7. **A carefully even shuffle.** Each pass plays every show once, in a fresh shuffle. Each show moves on one episode per pass, and the same movie or episode never airs twice in a row. For 10 items or fewer, every order is exactly as likely; above that, the order comes from a tested Feistel permutation (PLAN.md §9b). Tunarr's shuffles are tools for building one line-up.
8. **Set times that keep you in step.** A programme at a set time is laid over the shared schedule. Outside its times, the channel is exactly what everyone on the same schedule code sees. An "only at these times" option keeps a programme off the channel at other times.
9. **Making channels on the TV.** You make a channel on the Apple TV, with a preview of how many programmes match and the next few hours. No computer is needed.
10. **Hardened against a bad server or a bad code.** Gregular TV protects itself in several ways:
    - Plain `http` is refused beyond the home network.
    - Redirects are followed only within the same server.
    - Replies are capped in size.
    - Every code is checked before use.

    Tunarr is meant to run on a trusted home network; the release adds optional basic auth.

## What both do

- Linear channels that you join partway through, as on real TV.
- A programme guide.
- Commercial-style filler, including mid-roll breaks inside films.
- Padding so programmes start on the half hour.
- Shuffled and in-order programming.
- Programmes at chosen times.
- Jellyfin as a source.

## In short

Tunarr is the more powerful and flexible **channel station**. It suits someone who will run a server, wants to watch on many devices, needs subtitles or recording, or wants to hand-craft channels in detail.

Gregular TV is a **set-top box** for an Apple TV, or a browser. Nothing needs hosting or maintaining, it plays at original quality, it remembers nothing about you, and households can share the same channels by schedule code and a channels document. Its biggest gaps for a viewer are subtitles and audio-track choice. After those come one server at a time, and simpler scheduling and filler.

Sources: Tunarr's [README](https://github.com/chrisbenincasa/tunarr), [documentation](https://tunarr.com/) (scheduling, time slots, channels, filler, filler selection, smart collections, clients, FAQ) and [v2026.9.0 release notes](https://github.com/chrisbenincasa/tunarr/releases/tag/v2026.9.0).
