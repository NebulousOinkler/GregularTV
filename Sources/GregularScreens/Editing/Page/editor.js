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
  for (const [id, names] of [["genre", state.library.genres], ["series", state.library.series], ["tag", state.library.tags], ["studio", state.library.studios], ["film", state.library.films]]) {
    $("list-" + id).replaceChildren(...names.map((name) => el("option", { value: name })));
  }
  render();
}

function render() {
  renderChannels();
  renderSetTimes();
  renderFeeds();
  $("json").value = JSON.stringify(doc, null, 2);
}

// Channels

const kinds = { genre: "Genre", series: "Series", tag: "Tag", studio: "Studio", years: "Years" };
const joins = { anyOf: "Any of", allOf: "All of", noneOf: "None of" };

function describe(match) {
  if (match.years) return (match.years.from ?? "any year") + "–" + (match.years.to ?? "now");
  const kind = Object.keys(match)[0];
  return match[kind];
}

/** The first free number for a channel of yours: not taken, and not in a feed's block. */
function freeNumber() {
  const taken = new Set([...state.channels.map((c) => c.number), ...doc.channels.map((c) => c.number)]);
  const inFeed = (n) => (doc.feeds || []).some((f) => n >= f.firstNumber && n <= f.firstNumber + 9);
  for (let n = state.customNumbers.from; n <= state.customNumbers.to; n++) if (!taken.has(n) && !inFeed(n)) return n;
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
  const join = el("select", { "aria-label": "Join" }, ...Object.entries(joins).map(([value, text]) => el("option", { value, text })));
  const kind = el("select", { "aria-label": "Condition" }, ...Object.entries(kinds).map(([value, text]) => el("option", { value, text })));
  const name = el("input", { placeholder: "Start typing a name", list: "list-genre" });
  const { firstYear, lastYear } = state.library;
  const from = el("input", { type: "number", min: 1, max: 9999, hidden: true, "aria-label": "First year",
                             placeholder: firstYear ? "From (" + firstYear + ")" : "From" });
  const to = el("input", { type: "number", min: 1, max: 9999, hidden: true, "aria-label": "Last year",
                           placeholder: lastYear ? "To (" + lastYear + ")" : "To" });
  kind.addEventListener("change", () => {
    const years = kind.value === "years";
    name.hidden = years; from.hidden = !years; to.hidden = !years;
    name.setAttribute("list", "list-" + kind.value);
    // Years narrow the rest ("Comedy, from 1990 to 1999"), rather than
    // adding to it ("Comedy, or anything from the 1990s").
    if (years) join.value = "allOf";
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

// Feeds

/** A feed's picture, or its badge: initials on a colour. */
function feedArt(feed) {
  if (feed.details && feed.details.image) {
    return el("img", { className: "feed-art", alt: "", src: "data:image/png;base64," + feed.details.image });
  }
  const badge = el("div", { className: "feed-art feed-badge", text: feed.badge.initials, "aria-hidden": "true" });
  badge.style.backgroundColor = "hsl(" + feed.badge.hue + " 45% 38%)";
  return badge;
}

function feedHead(feed, ...lines) {
  return el("div", { className: "feed-head" }, feedArt(feed),
    el("div", {}, el("h2", { text: feed.title }), ...lines.filter(Boolean).map((text) => el("div", { className: "dim", text }))));
}

/** "70–79". */
const block = (first) => first + "–" + (first + 9);

/** Saves the document now: following and unfollowing take effect at once. */
async function saveNow(done) {
  try {
    use(await api("/api/save", doc));
    say(done, true);
  } catch (error) { say(error.message); render(); }
}

/** Blocks a new feed could take, given what's on the page now, not just what's saved. */
function freeBlocks(blocks) {
  const used = [...doc.channels.map((c) => c.number), ...doc.setTimes.map((s) => s.channel)];
  return blocks.filter((b) => !used.some((n) => n >= b && n <= b + 9) && !(doc.feeds || []).some((f) => f.firstNumber === b));
}

function renderFeeds() {
  const tab = $("tab-feeds");
  const link = el("input", { type: "url", placeholder: "The link to the feed", "aria-label": "Feed link", autocomplete: "off", spellcheck: false });
  const look = el("div");
  const follow = el("form", { className: "card" },
    el("h2", { text: "Follow a feed" }),
    el("p", { className: "dim", text: "Paste the link to someone's feed: their channels, and set times on them, in a block of ten numbers you pick. When they change it, you get the update when you choose." }),
    el("div", { className: "row" }, link, el("button", { className: "primary", text: "Look" })),
    look);
  follow.addEventListener("submit", async (event) => {
    event.preventDefault();
    look.replaceChildren(el("p", { className: "dim", text: "Getting it…" }));
    try {
      look.replaceChildren(feedPreview(await api("/api/feeds/look", { link: link.value })));
      say("");
    } catch (error) { look.replaceChildren(); say(error.message); }
  });
  tab.replaceChildren(follow,
    ...(state.feeds.length ? state.feeds.map(feedCard) : [el("p", { className: "dim", text: "You don't follow any feeds." })]),
    shareCard());
}

/** A feed looked at, before following it: like a podcast's page. */
function feedPreview(found) {
  const blocks = freeBlocks(found.freeBlocks);
  const where = el("select", { "aria-label": "Channel numbers" },
    ...blocks.map((first) => el("option", { value: first, text: "Channels " + block(first) })));
  return el("div", {},
    feedHead(found, found.details.publisher && "From " + found.details.publisher, found.details.description, found.details.times),
    el("ul", { className: "lines" }, ...found.channels.map((c) => el("li", { text: c.name + ": " + c.summary }))),
    blocks.length
      ? el("div", { className: "row" }, where,
          el("button", { type: "button", className: "primary", text: "Follow", onclick: () => {
            doc.feeds = [...(doc.feeds || []), { link: found.link, firstNumber: Number(where.value) }];
            saveNow("Following " + found.title + ".");
          } }),
          el("span", { className: "dim", text: dirty ? "Following also saves your other changes." : "" }))
      : el("p", { className: "dim", text: "There's no free block of ten numbers for it. Unfollow a feed, or move some of your channels." }));
}

/** A feed followed: where it stands, its update, its channels to copy, and unfollowing. */
function feedCard(feed) {
  const unsaved = () => dirty && (say("Save or undo your changes first."), true);
  return el("div", { className: "card" },
    feedHead(feed, "Channels " + block(feed.firstNumber) + (feed.details && feed.details.publisher ? " · From " + feed.details.publisher : ""),
             feed.details && feed.details.description, feed.status),
    feed.hasUpdate ? el("div", {},
      el("ul", { className: "lines" }, ...feed.whatsNew.map((line) => el("li", { text: line }))),
      el("div", { className: "row" }, el("button", { type: "button", className: "primary", text: "Get Update", onclick: async () => {
        if (unsaved()) return;
        try { use(await api("/api/feeds/update", { link: feed.link })); say(feed.title + " is up to date.", true); } catch (error) { say(error.message); }
      } }))) : null,
    el("ul", { className: "lines" }, ...feed.channels.map((line) => el("li", {},
      el("span", { text: line.number + "  " + line.name + ": " + line.summary + " " }),
      el("button", { type: "button", text: "Make a Copy", title: "Copy it to your own channels, where you can change it", onclick: () => {
        const number = freeNumber();
        doc.channels.push({ ...JSON.parse(JSON.stringify(line.channel)), number });
        if (line.setTimes) doc.setTimes.push({ ...JSON.parse(JSON.stringify(line.setTimes)), channel: number });
        changed(); render();
        say("Copied to your channel " + number + ". Save to keep it.", true);
      } })))),
    el("div", { className: "row" }, el("button", { type: "button", className: "danger", text: "Unfollow", onclick: () => {
      if (unsaved()) return;
      if (!confirm("Unfollow " + feed.title + "? Its channels and set times will be removed. To keep one, make a copy of it first.")) return;
      doc.feeds = (doc.feeds || []).filter((f) => f.link !== feed.link);
      saveNow("Unfollowed " + feed.title + ".");
    } })));
}

/** Share as a feed: a block of your channels, as a file to put on any https host. */
function shareCard() {
  const yours = [...new Set(state.document.channels.map((c) => Math.floor(c.number / 10) * 10))].sort((a, b) => a - b);
  const card = el("form", { className: "card" }, el("h2", { text: "Share as a feed" }),
    el("p", { className: "dim", text: "Saves a block of ten of your channels, and their set times, as a file. Put it on any https host that lets web apps read it, such as GitHub Pages or a GitHub gist, and share the link. When you change the channels, share again and replace the file: followers get it as an update." }));
  if (!yours.length) return card.append(el("p", { className: "dim", text: "Make some channels of your own first." })), card;
  const which = el("select", { "aria-label": "Channels to share" }, ...yours.map((first) => el("option", { value: first, text: "Your channels " + block(first) })));
  const title = el("input", { placeholder: "Feed name, like Dad's Network", maxLength: 60, required: true, "aria-label": "Feed name" });
  const publisher = el("input", { placeholder: "From (optional), like Dad", maxLength: 60, "aria-label": "Publisher" });
  const about = el("input", { placeholder: "A line about it (optional)", maxLength: 300, "aria-label": "Description" });
  const local = el("input", { type: "radio", name: "share-zone", checked: true });
  const named = el("input", { type: "radio", name: "share-zone" });
  const zone = el("input", { value: state.timeZone, "aria-label": "Time zone", onfocus: () => { named.checked = true; } });
  const picture = el("input", { type: "file", accept: "image/png", "aria-label": "Picture" });
  const result = el("div");
  card.append(
    el("div", { className: "row" }, which, title),
    el("div", { className: "row" }, publisher, about),
    el("div", { className: "row" }, el("label", {}, local, "Set times in each follower's own time"),
      el("label", {}, named, "Set times in"), zone),
    el("div", { className: "row" }, el("label", { text: "Picture (optional): a PNG, at most 32 KB and 256 × 256 " }, picture)),
    el("div", { className: "row" }, el("button", { className: "primary", text: "Save Feed File" })),
    result);
  card.addEventListener("submit", async (event) => {
    event.preventDefault();
    if (dirty) return say("Save your changes first: the feed is made from what's saved.");
    let image;
    const file = picture.files[0];
    if (file) {
      const bytes = new Uint8Array(await file.arrayBuffer());
      image = btoa(Array.from(bytes, (b) => String.fromCharCode(b)).join(""));
    }
    try {
      const made = await api("/api/feeds/share", { block: Number(which.value), title: title.value, publisher: publisher.value,
        description: about.value, timeZone: local.checked ? "local" : zone.value.trim(), image });
      const url = URL.createObjectURL(new Blob([made.file], { type: "application/json" }));
      // Inside the web version, the page around this one saves it: a download from a frame counts as loading it there.
      const save = el("a", { href: url, download: made.fileName, text: "Save " + made.fileName,
        ...(host && { onclick: (event) => { event.preventDefault(); host.saveFile(made.fileName, made.file); } }) });
      result.replaceChildren(el("p", {}, save), el("textarea", { readOnly: true, value: made.file, "aria-label": "The feed file" }));
      save.click();
      say("Made " + made.fileName + ". Upload it, and share its link.", true);
    } catch (error) { say(error.message); }
  });
  return card;
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
    if (parsed.feeds !== undefined && !Array.isArray(parsed.feeds)) throw new Error("“feeds” is a list.");
    doc = parsed; dirty = true; $("dirty").textContent = "Not saved yet.";
    render();
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
