// Starts Gregular TV: the browser's helpers the Swift code calls, then the
// app itself (GregularWeb, compiled to WebAssembly by scripts/build-web.sh).
// Everything is served from this site; nothing loads from anywhere else.

// Trusted Types (see _headers): the only script URLs allowed are this page's
// own blob: workers, which hls.js makes to read video off the main thread.
// (The default policy, since hls.js passes plain strings.)
if (globalThis.trustedTypes) {
  trustedTypes.createPolicy("default", {
    createScriptURL(url) {
      if (url.startsWith("blob:" + location.origin + "/")) return url;
      throw new TypeError("Only this page's own workers may run.");
    },
  });
}

import * as hls from "./hls-player.js";
import * as vault from "./vault.js";
import { init } from "../app/index.js";

globalThis.gregularHLS = hls;
globalThis.gregularVault = vault;

// If the app itself stops (a crash in its WebAssembly), say so rather than
// leave a frozen picture. The details stay in this browser's console.
let stopped = false;
function showStopped(reason) {
  if (stopped || !(reason instanceof WebAssembly.RuntimeError)) return;
  stopped = true;
  const note = document.createElement("dialog");
  note.className = "confirm";
  note.append(Object.assign(document.createElement("h2"), { textContent: "Gregular TV stopped" }),
              Object.assign(document.createElement("p"), { textContent: "Something went wrong. Reload the page to start again." }));
  const reload = Object.assign(document.createElement("button"), { textContent: "Reload", className: "primary" });
  reload.addEventListener("click", () => location.reload());
  note.append(reload);
  document.body.append(note);
  note.showModal();
}
addEventListener("error", (event) => showStopped(event.error));
addEventListener("unhandledrejection", (event) => showStopped(event.reason));

/**
 * The app, joined from its parts as they download (scripts/build-web.sh
 * splits it: Cloudflare serves no file over 25 MiB). All the parts are
 * asked for at once, and the browser compiles the app as they arrive.
 */
async function app() {
  const manifest = await (await fetch(new URL("../app/wasm.json", import.meta.url), { cache: "no-cache" })).json();
  const downloads = manifest.parts.map((part) => fetch(new URL("../app/" + part, import.meta.url)));
  let next = 0;
  let reader = null;
  const joined = new ReadableStream({
    async pull(controller) {
      for (;;) {
        if (!reader) {
          if (next === downloads.length) return controller.close();
          const response = await downloads[next++];
          if (!response.ok) throw new Error("Couldn't download the app (" + response.status + ").");
          reader = response.body.getReader();
        }
        const { done, value } = await reader.read();
        if (!done) return controller.enqueue(value);
        reader = null;
      }
    },
  });
  return new Response(joined, { headers: { "Content-Type": "application/wasm" } });
}

try {
  await init({ module: app() });
} catch (error) {
  const page = document.querySelector("#app .page") ?? document.body;
  const note = document.createElement("p");
  note.className = "error";
  note.textContent = "Gregular TV couldn't start in this browser. It needs a recent Chrome, Edge, Safari or Firefox.";
  page.append(note);
  throw error;
}
