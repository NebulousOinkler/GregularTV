// HLS for VideoDeck (GregularWeb): hls.js where the browser has Media
// Source Extensions, the browser's own HLS otherwise (older Safari on iPhone).
// hls.js is the light build, served from this site: no subtitles, no DRM.

import Hls, { FetchLoader } from "../vendor/hls.light.min.mjs";

/** Whether hls.js can play here; if not, a <video> may play HLS itself. */
export function supported() {
  return Hls.isSupported();
}

/** Times a dropped stream picks up where it was, since a piece last loaded. */
const RESUMES = 3;
/** Errors loading the next piece, which picking up again can get past. */
const RESUMABLE = new Set([
  Hls.ErrorDetails.FRAG_LOAD_ERROR,
  Hls.ErrorDetails.FRAG_LOAD_TIMEOUT,
  Hls.ErrorDetails.LEVEL_LOAD_ERROR,
  Hls.ErrorDetails.LEVEL_LOAD_TIMEOUT,
]);

/**
 * Plays `url` in `video` from `start` seconds, buffering up to `bufferAhead`
 * seconds ahead, and waiting up to `patience` seconds for each piece: a
 * server converting slower than real time can take that long to make the
 * next. Every request goes through fetch(), never sending cookies or a
 * referrer, and to plain http on the home network marked as such (`local`),
 * so Chrome lets it through after asking for local network access.
 * `onFailure(message)` is called once if it can't play. Returns
 * `{ destroy }`, to stop it and let go of the video.
 */
export function attach(video, url, start, bufferAhead, patience, local, onFailure) {
  const hls = new Hls({
    startPosition: start,
    maxBufferLength: bufferAhead,
    maxMaxBufferLength: Math.max(60, bufferAhead),
    backBufferLength: 30,
    fragLoadPolicy: {
      default: {
        maxTimeToFirstByteMs: patience * 1000,
        // The rest as hls.js has them.
        maxLoadTimeMs: 120_000,
        timeoutRetry: { maxNumRetry: 4, retryDelayMs: 0, maxRetryDelayMs: 0 },
        errorRetry: { maxNumRetry: 6, retryDelayMs: 1000, maxRetryDelayMs: 8000 },
      },
    },
    enableWorker: true,
    loader: FetchLoader,
    fetchSetup(context, init) {
      const options = { ...init, credentials: "omit", referrerPolicy: "no-referrer", cache: "no-store" };
      if (local) options.targetAddressSpace = "local";
      return new Request(context.url, options);
    },
  });
  let recovered = false;
  let resumes = 0;
  let failed = false;
  hls.on(Hls.Events.FRAG_LOADED, () => {
    resumes = 0;
  });
  hls.on(Hls.Events.ERROR, (_, data) => {
    if (!data.fatal || failed) return;
    // A decoding hiccup: try once to recover before giving up.
    if (data.type === Hls.ErrorTypes.MEDIA_ERROR && !recovered) {
      recovered = true;
      hls.recoverMediaError();
      return;
    }
    // The next piece didn't come (the server busy converting, or the
    // connection dropped): pick up where it was. Giving up would start the
    // server's conversion again from scratch.
    if (RESUMABLE.has(data.details) && resumes < RESUMES) {
      resumes += 1;
      hls.startLoad();
      return;
    }
    failed = true;
    onFailure(data.type === Hls.ErrorTypes.NETWORK_ERROR ? "network" : "media");
  });
  hls.attachMedia(video);
  hls.loadSource(url);
  return {
    destroy() {
      hls.destroy();
    },
  };
}
