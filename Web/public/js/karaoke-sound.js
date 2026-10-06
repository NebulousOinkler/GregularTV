// Karaoke's menu tunes and sound effects, played with the Web Audio API as
// they go: no sound files, nothing fetched. The notes come from the app
// (GregularScreens' KaraokeMusic, through GregularWeb's KaraokeSound), so
// this only plays them: a tune round and round, an effect once.
//
// A note is { at, length, gain } (seconds, seconds, 0 to 1) and either
// { wave, note } (an oscillator: "sine", "square", "sawtooth" or "triangle";
// a MIDI note) or { drum } ("kick" or "hat").

const LOOKAHEAD = 0.25; // seconds of notes scheduled ahead
const TICK = 60; // ms between scheduling
let context = null;
let music = null; // { id, gain, notes, duration, start, next }
let timer = null;

function audio() {
  if (!context) {
    context = new AudioContext();
    // Browsers start sound only after a click or key: carry on at the next one.
    for (const type of ["pointerdown", "keydown"]) {
      addEventListener(type, () => context.state === "suspended" && context.resume(), { capture: true });
    }
  }
  if (context.state === "suspended") context.resume();
  return context;
}

const frequency = (note) => 440 * 2 ** ((note - 69) / 12);

/** One note, at `start` (the context's time), into `destination`. */
function sound(destination, note, start) {
  const ctx = destination.context;
  const env = ctx.createGain();
  env.connect(destination);
  if (note.drum === "kick") {
    const osc = ctx.createOscillator();
    osc.frequency.setValueAtTime(140, start);
    osc.frequency.exponentialRampToValueAtTime(45, start + 0.12);
    env.gain.setValueAtTime(note.gain, start);
    env.gain.exponentialRampToValueAtTime(0.0001, start + note.length);
    osc.connect(env);
    osc.start(start);
    osc.stop(start + note.length + 0.05);
  } else if (note.drum === "hat") {
    const noise = ctx.createBufferSource();
    const buffer = ctx.createBuffer(1, Math.ceil(ctx.sampleRate * note.length), ctx.sampleRate);
    const data = buffer.getChannelData(0);
    for (let i = 0; i < data.length; i++) data[i] = Math.random() * 2 - 1;
    noise.buffer = buffer;
    const filter = ctx.createBiquadFilter();
    filter.type = "highpass";
    filter.frequency.value = 7000;
    env.gain.setValueAtTime(note.gain, start);
    env.gain.exponentialRampToValueAtTime(0.0001, start + note.length);
    noise.connect(filter).connect(env);
    noise.start(start);
  } else {
    const osc = ctx.createOscillator();
    osc.type = note.wave;
    osc.frequency.value = frequency(note.note);
    env.gain.setValueAtTime(0, start);
    env.gain.linearRampToValueAtTime(note.gain, start + 0.01);
    env.gain.exponentialRampToValueAtTime(0.0001, start + note.length);
    osc.connect(env);
    osc.start(start);
    osc.stop(start + note.length + 0.05);
  }
}

/** Schedules the tune's notes up to LOOKAHEAD ahead, round and round. */
function schedule() {
  if (!music) return;
  const until = context.currentTime + LOOKAHEAD;
  for (;;) {
    const round = Math.floor(music.next / music.notes.length);
    const note = music.notes[music.next % music.notes.length];
    const at = music.start + round * music.duration + note.at;
    if (at >= until) return;
    sound(music.gain, note, at);
    music.next += 1;
  }
}

/** Plays a tune round and round (`id` names it: the same one carries on), fading out any other. */
export function play(id, duration, notes) {
  if (music?.id === id || notes.length === 0) return;
  stop(0.4);
  const ctx = audio();
  const gain = ctx.createGain();
  gain.gain.setValueAtTime(0, ctx.currentTime);
  gain.gain.linearRampToValueAtTime(0.7, ctx.currentTime + 0.4);
  gain.connect(ctx.destination);
  music = { id, gain, notes, duration, start: ctx.currentTime + 0.05, next: 0 };
  schedule();
  timer ??= setInterval(schedule, TICK);
}

/** Fades the tune out over `seconds`. */
export function stop(seconds = 1.2) {
  if (!music) return;
  const { gain } = music;
  const now = context.currentTime;
  gain.gain.cancelScheduledValues(now);
  gain.gain.setValueAtTime(gain.gain.value, now);
  gain.gain.linearRampToValueAtTime(0, now + seconds);
  setTimeout(() => gain.disconnect(), seconds * 1000 + 100);
  music = null;
  clearInterval(timer);
  timer = null;
}

/** Plays a sound effect's notes once. */
export function effect(notes) {
  const ctx = audio();
  const out = ctx.createGain();
  out.gain.value = 0.6;
  out.connect(ctx.destination);
  const now = ctx.currentTime + 0.01;
  for (const note of notes) sound(out, note, now + note.at);
  setTimeout(() => out.disconnect(), 2000);
}
