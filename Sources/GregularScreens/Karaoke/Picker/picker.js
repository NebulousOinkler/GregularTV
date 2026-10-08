"use strict";
// Karaoke's song picker (SongPickerHTML), after local-page.js: guests add
// songs to the queue on the TV from a phone on the home network, with the
// code shown on the TV. It sees only the songs' names.
let songs = [];
const shown = 200; // songs listed at once; search narrows them down

async function api(path, body) {
  const text = body === undefined ? undefined : JSON.stringify(body);
  return answered(await askAppleTV(body === undefined ? "GET" : "POST", path, text), "picker", "Apple TV");
}

onCode(async () => {
  try {
    const data = await api("/api/songs");
    songs = data.songs;
    showStage(data.stage);
    renderSongs();
    $("connect").hidden = true;
    $("picker").hidden = false;
    say("");
  } catch (error) { say(error.message); }
});

/** Lower case, without accents, for search. */
const plain = (text) => (text || "").normalize("NFD").replace(/\p{M}/gu, "").toLowerCase();

function renderSongs() {
  const terms = plain($("search").value).split(/\s+/).filter(Boolean);
  const matching = songs.filter((song) => {
    const text = plain([song.title, song.credit, song.album].join(" "));
    return terms.every((term) => text.includes(term));
  });
  $("songs").replaceChildren(...matching.slice(0, shown).map((song) => el("li", {},
    el("button", { type: "button", className: "song", onclick: () => add(song) },
      el("span", { className: "text" },
        el("span", { className: "title", text: song.title }),
        el("span", { className: "credit", text: [song.credit, song.album].filter(Boolean).join(" · ") })),
      song.video ? el("span", { className: "badge", text: "Video" }) : null,
      song.lyrics ? null : el("span", { className: "badge quiet", text: "No lyrics" })))));
  if (matching.length > shown) $("songs").append(el("li", { className: "dim", text: "Type to find more." }));
  if (!matching.length) $("songs").append(el("li", { className: "dim", text: "No songs match." }));
}

async function add(song) {
  try {
    showStage(await api("/api/queue", { id: song.id }));
    say("“" + song.title + "” is in the queue.", true);
  } catch (error) { say(error.message); }
}

function showStage(stage) {
  $("now").textContent = stage.now ? stage.now.title + " — " + stage.now.credit : "Nothing yet.";
  $("queue").replaceChildren(...stage.queue.map((line) => el("li", { text: line.title + " — " + line.credit })));
}

$("search").addEventListener("input", renderSongs);

// The queue changes on the TV too: look again now and then.
setInterval(async () => {
  if ($("picker").hidden) return;
  try { showStage(await api("/api/queue")); } catch (error) {}
}, 5000);
