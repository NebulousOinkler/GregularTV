// The sign-ins, kept encrypted in this browser (GregularBrowser's
// BrowserCredentialStore). The key is an AES-GCM key made here by WebCrypto
// and kept in IndexedDB as non-extractable: script on this page can use it,
// but it can never be read out, so a copy of the browser's files alone
// doesn't give the sign-ins away. (Script running on the page could still
// use them; the Content Security Policy in _headers is what stops that.)
//
// The only IndexedDB use in the app (scripts/privacy-check.sh).

const DATABASE = "gregular";
const STORE = "vault";
const KEY = "key";
const SIGN_INS = "sign-ins";

function open() {
  return new Promise((resolve, reject) => {
    const request = indexedDB.open(DATABASE, 1);
    request.onupgradeneeded = () => request.result.createObjectStore(STORE);
    request.onsuccess = () => resolve(request.result);
    request.onerror = () => reject(request.error);
  });
}

function run(database, mode, use) {
  return new Promise((resolve, reject) => {
    const transaction = database.transaction(STORE, mode);
    const request = use(transaction.objectStore(STORE));
    transaction.oncomplete = () => resolve(request.result);
    transaction.onerror = () => reject(transaction.error);
    transaction.onabort = () => reject(transaction.error);
  });
}

async function key(database) {
  const existing = await run(database, "readonly", (store) => store.get(KEY));
  if (existing) return existing;
  const made = await crypto.subtle.generateKey({ name: "AES-GCM", length: 256 }, false, ["encrypt", "decrypt"]);
  await run(database, "readwrite", (store) => store.put(made, KEY));
  return made;
}

/** The saved text, or null if there's none (or it can't be read). */
export async function load() {
  try {
    const database = await open();
    try {
      const saved = await run(database, "readonly", (store) => store.get(SIGN_INS));
      if (!saved) return null;
      const plain = await crypto.subtle.decrypt({ name: "AES-GCM", iv: saved.iv }, await key(database), saved.data);
      return new TextDecoder().decode(plain);
    } finally {
      database.close();
    }
  } catch {
    return null;
  }
}

/** Replaces the saved text, encrypted with a fresh nonce. */
export async function save(text) {
  const database = await open();
  try {
    const iv = crypto.getRandomValues(new Uint8Array(12));
    const data = await crypto.subtle.encrypt({ name: "AES-GCM", iv }, await key(database), new TextEncoder().encode(text));
    await run(database, "readwrite", (store) => store.put({ iv, data }, SIGN_INS));
  } finally {
    database.close();
  }
}

/** Forgets the sign-ins and the key. */
export function erase() {
  return new Promise((resolve) => {
    const request = indexedDB.deleteDatabase(DATABASE);
    request.onsuccess = request.onerror = request.onblocked = () => resolve();
  });
}
