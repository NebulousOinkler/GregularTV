"use strict";
// What every page the Apple TV serves on the home network shares
// (LocalPageHTML): making elements, saying things, and asking the Apple TV,
// with the code shown on the TV. Names from the library are only ever put
// on a page as text (textContent), never as HTML.

const $ = (id) => document.getElementById(id);

/** A new element: `props` sets its text, listeners ("onclick") and properties. */
function el(tag, props, ...children) {
  const node = document.createElement(tag);
  for (const [key, value] of Object.entries(props || {})) {
    if (key === "text") node.textContent = value;
    else if (key.startsWith("on")) node.addEventListener(key.slice(2), value);
    else if (key === "list") node.setAttribute("list", value);
    else if (key in node) node[key] = value;
    else node.setAttribute(key, value);
  }
  for (const child of children.flat()) if (child) node.append(child);
  return node;
}

/** Shows `text` in the page's #message box, as good news or bad; nothing for "". */
function say(text, good) {
  const box = $("message");
  box.replaceChildren();
  if (text) box.append(el("div", { className: "message " + (good ? "good" : "bad"), text }));
}

/** The code shown on the TV, sent with every request. */
let code = "";

/** Takes the code from the form #connect each time it's sent, then runs `start`. */
function onCode(start) {
  $("connect").addEventListener("submit", async (event) => {
    event.preventDefault();
    code = $("code").value.trim();
    await start();
  });
}

/** Asks the Apple TV, with the code: `{ status, data }`, with `data` the reply's JSON (or {}). */
async function askAppleTV(method, path, text) {
  const response = await fetch(path, {
    method,
    headers: { "X-Gregular-Code": code, "Content-Type": "application/json" },
    body: text,
    cache: "no-store", credentials: "omit", referrerPolicy: "no-referrer",
  });
  let data = {};
  try { data = await response.json(); } catch (e) {}
  return { status: response.status, data };
}

/**
 * A reply's data, or an error saying what `who` answered. A wrong code, or a
 * page locked by too many (401, 423), shows the form #connect again in place
 * of the element `page`.
 */
function answered({ status, data }, page, who) {
  if (status === 401 || status === 423) { $(page).hidden = true; $("connect").hidden = false; }
  if (status < 200 || status >= 300) throw new Error(data.error || ("The " + who + " said " + status + "."));
  return data;
}
