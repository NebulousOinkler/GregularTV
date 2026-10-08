"use strict";
// The editing page, for every version of the app (EditingPageHTML), after
// local-page.js. Either the Apple TV serves it on the home network
// (LocalPage.editing), and it sends
// the code shown on the TV with every request; or the web version opens it
// inside itself, as `host`, which answers it directly: no network, no code.
const host = window.parent !== window ? window.parent.gregularEditor : undefined;
let state = null;
let doc = null;
let dirty = false;

function changed() { dirty = true; $("dirty").textContent = "Not saved yet."; $("json").value = JSON.stringify(doc, null, 2); }

async function api(path, body) {
  const method = body === undefined ? "GET" : "POST";
  const text = body === undefined ? undefined : JSON.stringify(body);
  if (!host) return answered(await askAppleTV(method, path, text), "editor", "Apple TV");
  const reply = await host.request(method, path, text ?? "");
  let data = {};
  try { data = JSON.parse(reply.body); } catch (e) {}
  return answered({ status: reply.status, data }, "editor", "app");
}

onCode(load);

async function load() {
  try {
    use(await api("/api/state"));
    $("connect").hidden = true;
    $("editor").hidden = false;
    say("");
  } catch (error) { say(error.message); }
}

function use(newState) {
  state = newState;
  doc = JSON.parse(JSON.stringify(state.document));
  dirty = false;
  $("dirty").textContent = "";
  for (const [id, names] of [["genre", state.library.genres], ["series", state.library.series], ["tag", state.library.tags], ["film", state.library.films]]) {
    $("list-" + id).replaceChildren(...names.map((name) => el("option", { value: name })));
  }
  render();
}

function render() {
  renderChannels();
  renderSetTimes();
  $("json").value = JSON.stringify(doc, null, 2);
}

// Channels

const kinds = { genre: "Genre", series: "Series", tag: "Tag", years: "Years" };
const joins = { anyOf: "Any of", allOf: "All of", noneOf: "None of" };

function describe(match) {
  if (match.years) return (match.years.from ?? "any year") + "–" + (match.years.to ?? "now");
  const kind = Object.keys(match)[0];
  return match[kind];
}

function freeNumber() {
  const taken = new Set([...state.channels.map((c) => c.number), ...doc.channels.map((c) => c.number)]);
  for (let n = state.customNumbers.from; n <= state.customNumbers.to; n++) if (!taken.has(n)) return n;
  return state.customNumbers.from;
}

function renderChannels() {
  const tab = $("tab-channels");
  tab.replaceChildren(
    ...doc.channels.map((channel, index) => channelCard(channel, index)),
    el("div", { className: "row" },
      el("button", { type: "button", text: "Add a Channel", onclick: () => {
        doc.channels.push({ number: freeNumber(), name: "", plays: "both", rule: {}, halfHourSlots: true, commercials: true });
        changed(); renderChannels();
      } })),
    el("p", { className: "dim", text: "A programme is on a channel when it matches any of the “any of” conditions (or there are none), all of the “all of” ones, and none of the “none of” ones. No conditions at all plays everything." }));
}

function channelCard(channel, index) {
  const conditions = el("div");
  for (const join of Object.keys(joins)) {
    const list = channel.rule[join] || [];
    if (!list.length) continue;
    conditions.append(el("div", { className: "row" },
      el("strong", { text: joins[join] + ":" }),
      ...list.map((match, i) => el("span", { className: "chip" },
        el("span", { text: kinds[Object.keys(match)[0]] + ": " + describe(match) }),
        el("button", { type: "button", title: "Remove", text: "✕", onclick: () => {
          list.splice(i, 1);
          if (!list.length) delete channel.rule[join];
          changed(); renderChannels();
        } })))));
  }
  const join = el("select", {}, ...Object.entries(joins).map(([value, text]) => el("option", { value, text })));
  const kind = el("select", {}, ...Object.entries(kinds).map(([value, text]) => el("option", { value, text })));
  const name = el("input", { placeholder: "Start typing a name", list: "list-genre" });
  const from = el("input", { type: "number", placeholder: "From", hidden: true });
  const to = el("input", { type: "number", placeholder: "To", hidden: true });
  kind.addEventListener("change", () => {
    const years = kind.value === "years";
    name.hidden = years; from.hidden = !years; to.hidden = !years;
    name.setAttribute("list", "list-" + kind.value);
  });
  const preview = el("div", { className: "dim" });
  return el("div", { className: "card" },
    el("div", { className: "row" },
      el("label", { text: "Number " }, el("input", { type: "number", min: state.customNumbers.from, max: state.customNumbers.to, value: channel.number,
        onchange: (e) => {
          // Its set times move with it.
          const old = channel.number;
          channel.number = Number(e.target.value);
          for (const group of doc.setTimes) if (group.channel === old) group.channel = channel.number;
          changed(); renderSetTimes();
        } })),
      el("input", { placeholder: "Channel name", value: channel.name, maxLength: 60,
        oninput: (e) => { channel.name = e.target.value; changed(); } })),
    el("div", { className: "row" },
      el("label", { text: "Plays " }, el("select", { onchange: (e) => { channel.plays = e.target.value; changed(); } },
        ...[["both", "Episodes and movies"], ["episodes", "Episodes"], ["movies", "Movies"]].map(([value, text]) =>
          el("option", { value, text, selected: channel.plays === value })))),
      el("label", {}, el("input", { type: "checkbox", checked: channel.halfHourSlots !== false,
        onchange: (e) => { channel.halfHourSlots = e.target.checked; changed(); } }), "Half-hour slots"),
      el("label", {}, el("input", { type: "checkbox", checked: channel.commercials !== false,
        onchange: (e) => { channel.commercials = e.target.checked; changed(); } }), "Commercials")),
    conditions.childElementCount ? conditions : el("p", { className: "dim", text: "No conditions: plays everything." }),
    el("div", { className: "row" }, join, kind, name, from, to,
      el("button", { type: "button", text: "Add Condition", onclick: () => {
        let match;
        if (kind.value === "years") {
          const f = from.value ? Number(from.value) : undefined, t = to.value ? Number(to.value) : undefined;
          if (f === undefined && t === undefined) return say("Type a first year, a last year, or both.");
          match = { years: { from: f, to: t } };
        } else {
          if (!name.value.trim()) return say("Type or pick a name first.");
          match = { [kind.value]: name.value.trim() };
        }
        const count = Object.values(channel.rule).reduce((n, list) => n + list.length, 0);
        if (count >= state.mostConditions) return say("A channel has at most " + state.mostConditions + " conditions.");
        (channel.rule[join.value] ||= []).push(match);
        say(""); changed(); renderChannels();
      } })),
    el("div", { className: "row" },
      el("button", { type: "button", text: "Preview", onclick: async () => {
        preview.replaceChildren(el("span", { text: "Working it out…" }));
        try {
          const result = await api("/api/preview", channel);
          preview.replaceChildren(el("div", { text: result.matching + " programmes match. Next three hours:" }),
            el("ul", { className: "preview" }, ...result.upcoming.map((line) => el("li", { text: line.when + "  " + line.title }))));
        } catch (error) { preview.replaceChildren(el("span", { text: error.message })); }
      } }),
      el("button", { type: "button", className: "danger", text: "Delete Channel", onclick: () => {
        if (!confirm("Delete channel " + channel.number + "? Any set times on it go when you save.")) return;
        doc.channels.splice(index, 1);
        doc.setTimes = doc.setTimes.filter((s) => s.channel !== channel.number);
        changed(); render();
      } })),
    preview);
}

// Set times

const weekdays = ["Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"];

function channelOptions(selected) {
  const all = [...state.channels.filter((c) => c.number < state.customNumbers.from || c.number > state.customNumbers.to),
               ...doc.channels.map((c) => ({ number: c.number, name: c.name || "(new)" }))];
  return all.map((c) => el("option", { value: c.number, text: c.number + "  " + c.name, selected: c.number === selected }));
}

function renderSetTimes() {
  const tab = $("tab-settimes");
  tab.replaceChildren(
    ...doc.setTimes.map((group, index) => setTimesCard(group, index)),
    el("div", { className: "row" }, el("button", { type: "button", text: "Add Set Times on a Channel", onclick: () => {
      const used = new Set(doc.setTimes.map((s) => s.channel));
      const free = state.channels.find((c) => !used.has(c.number));
      doc.setTimes.push({ channel: free ? free.number : 1, timeZone: state.timeZone, programmes: [] });
      changed(); renderSetTimes();
    } })),
    el("p", { className: "dim", text: "Set times air at exactly those times, in the time zone given. The rest of the time the channel is the same as for everyone with your schedule code. Times are 24-hour, like 18:30. Dates look like Feb 2." }));
}

function setTimesCard(group, index) {
  return el("div", { className: "card" },
    el("div", { className: "row" },
      el("label", { text: "Channel " }, el("select", { onchange: (e) => { group.channel = Number(e.target.value); changed(); } }, ...channelOptions(group.channel))),
      el("label", { text: "Time zone " }, el("input", { value: group.timeZone, onchange: (e) => { group.timeZone = e.target.value.trim(); changed(); } }))),
    ...group.programmes.map((programme, i) => programmeRow(group, programme, i)),
    el("div", { className: "row" },
      el("button", { type: "button", text: "Add a Programme", onclick: () => { group.programmes.push({ series: "", at: [] }); changed(); renderSetTimes(); } }),
      el("button", { type: "button", className: "danger", text: "Remove These Set Times", onclick: () => {
        doc.setTimes.splice(index, 1); changed(); renderSetTimes();
      } })));
}

function programmeRow(group, programme, i) {
  const isFilm = "item" in programme;
  const days = programme.days || [];
  const dates = days.filter((d) => !weekdays.includes(d.slice(0, 3)));
  return el("div", { className: "card" },
    el("div", { className: "row" },
      el("select", { onchange: (e) => {
        const name = programme.series ?? programme.item ?? "";
        delete programme.series; delete programme.item;
        programme[e.target.value] = name; changed(); renderSetTimes();
      } }, el("option", { value: "series", text: "Series", selected: !isFilm }), el("option", { value: "item", text: "Film", selected: isFilm })),
      el("input", { placeholder: isFilm ? "Film" : "Series", list: isFilm ? "list-film" : "list-series", value: programme.series ?? programme.item ?? "",
        oninput: (e) => { programme[isFilm ? "item" : "series"] = e.target.value; changed(); } })),
    el("div", { className: "row" },
      el("input", { placeholder: "Times, like 18:00, 18:30", value: (programme.at || []).join(", "),
        onchange: (e) => { programme.at = e.target.value.split(/[ ,]+/).filter(Boolean); changed(); } })),
    el("div", { className: "row" },
      ...weekdays.map((day) => el("label", {}, el("input", { type: "checkbox", checked: days.some((d) => d.slice(0, 3) === day),
        onchange: (e) => {
          const rest = (programme.days || []).filter((d) => d.slice(0, 3) !== day);
          programme.days = e.target.checked ? [...rest, day] : rest;
          if (!programme.days.length) delete programme.days;
          changed();
        } }), day)),
      el("input", { placeholder: "Dates, like Feb 2, Dec 25", value: dates.join(", "),
        onchange: (e) => {
          const chosen = (programme.days || []).filter((d) => weekdays.includes(d.slice(0, 3)));
          const typed = e.target.value.split(",").map((s) => s.trim()).filter(Boolean);
          programme.days = [...chosen, ...typed];
          if (!programme.days.length) delete programme.days;
          changed();
        } })),
    el("div", { className: "row" },
      el("label", {}, el("input", { type: "checkbox", checked: !!programme.exclusive,
        onchange: (e) => { if (e.target.checked) programme.exclusive = true; else delete programme.exclusive; changed(); } }),
        "Only at these times"),
      el("button", { type: "button", className: "danger", text: "Remove", onclick: () => {
        group.programmes.splice(i, 1); changed(); renderSetTimes();
      } })));
}

// Tabs, JSON and saving

for (const button of document.querySelectorAll("[data-tab]")) {
  button.addEventListener("click", () => {
    for (const other of document.querySelectorAll("[data-tab]")) {
      other.setAttribute("aria-selected", String(other === button));
      $("tab-" + other.dataset.tab).hidden = other !== button;
    }
  });
}

$("use-json").addEventListener("click", () => {
  try {
    const parsed = JSON.parse($("json").value);
    if (!Array.isArray(parsed.channels) || !Array.isArray(parsed.setTimes)) throw new Error("It needs “channels” and “setTimes” lists.");
    doc = parsed; dirty = true; $("dirty").textContent = "Not saved yet.";
    renderChannels(); renderSetTimes();
    say(host ? "Using the JSON. Save to use it." : "Using the JSON. Save to send it to the Apple TV.", true);
  } catch (error) { say("That JSON can't be used: " + error.message); }
});

$("save").addEventListener("click", async () => {
  try {
    use(await api("/api/save", doc));
    say(host ? "Saved. Your channels have been rebuilt." : "Saved. The Apple TV has rebuilt its channels.", true);
  } catch (error) { say(error.message); }
});

window.addEventListener("beforeunload", (event) => { if (dirty) event.preventDefault(); });

if (host) {
  // Inside the web version: no code to enter, and it asks before closing with changes not saved.
  host.isDirty = () => dirty;
  $("intro").textContent = "Your channels and set times, saved in this browser.";
  $("save").textContent = "Save";
  $("connect").hidden = true;
  load();
} else {
  const fromLink = location.hash.slice(1);
  if (/^\d{6}$/.test(fromLink)) { $("code").value = fromLink; code = fromLink; history.replaceState(null, "", location.pathname); load(); }
}
