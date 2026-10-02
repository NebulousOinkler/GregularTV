// HLS for VideoDeck (GregularWeb): hls.js where the browser has Media
// Source Extensions, the browser's own HLS otherwise (older Safari on iPhone).
// hls.js is the light build, served from this site: no subtitles, no DRM.

import Hls, { FetchLoader } from "../vendor/hls.light.min.mjs";

/** Whether hls.js can play here; if not, a <video> may play HLS itself. */
export function supported() {
  return Hls.isSupported();
}

/**
 * Plays `url` in `video` from `start` seconds, buffering up to `bufferAhead`
 * seconds ahead. Every request goes through fetch(), never sending cookies or
 * a referrer, and to plain http on the home network marked as such (`local`),
 * so Chrome lets it through after asking for local network access.
 * `onFailure(message)` is called once if it can't play. Returns
 * `{ destroy }`, to stop it and let go of the video.
 */
export function attach(video, url, start, bufferAhead, local, onFailure) {
  const hls = new Hls({
    startPosition: start,
    maxBufferLength: bufferAhead,
    maxMaxBufferLength: Math.max(60, bufferAhead),
    backBufferLength: 30,
    enableWorker: true,
    loader: FetchLoader,
    fetchSetup(context, init) {
      const options = { ...init, credentials: "omit", referrerPolicy: "no-referrer", cache: "no-store" };
      if (local) options.targetAddressSpace = "local";
      return new Request(context.url, options);
    },
  });
  let recovered = false;
  let failed = false;
  hls.on(Hls.Events.ERROR, (_, data) => {
    if (!data.fatal || failed) return;
    // A decoding hiccup: try once to recover before giving up.
    if (data.type === Hls.ErrorTypes.MEDIA_ERROR && !recovered) {
      recovered = true;
      hls.recoverMediaError();
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
