// Karaoke's menu tunes and sound effects, made as they play with the Web
// Audio API: no sound files, nothing fetched. Each theme is a short loop
// (chords, a bass line, an arpeggio and a beat) and a set of blips. The app
// calls play(theme) while its menus show, stop() before a song, and
// effect(name, theme) as things happen (GregularWeb's KaraokeSound).

// Notes are semitones from each theme's root; a chord is its notes, a bar long.
const THEMES = {
  // Four on the floor, octave-jumping bass, a bright saw arpeggio.
  neonDisco: {
    tempo: 120, root: 45, lead: "sawtooth", bass: "square", leadGain: 0.05,
    chords: [[0, 3, 7, 10], [5, 8, 12, 15], [3, 7, 10, 14], [-2, 2, 5, 9]],
    bassSteps: [0, 12, 0, 12, 0, 12, 0, 12, 0, 12, 0, 12, 0, 12, 0, 12],
    arp: [0, 1, 2, 3, 2, 1, 2, 3, 0, 1, 2, 3, 2, 1, 2, 3],
    kick: [1, 0, 0, 0, 1, 0, 0, 0, 1, 0, 0, 0, 1, 0, 0, 0],
    hat: [0, 0, 1, 0, 0, 0, 1, 0, 0, 0, 1, 0, 0, 0, 1, 0],
    blip: "square", blipNotes: [12, 19], tada: [0, 7, 12, 16, 19, 24],
  },
  // Big square-wave synth pop, half-time drums, a long arpeggio.
  karaokeBar: {
    tempo: 108, root: 48, lead: "square", bass: "sawtooth", leadGain: 0.04,
    chords: [[0, 4, 7, 11], [9, 12, 16, 19], [5, 9, 12, 16], [7, 11, 14, 17]],
    bassSteps: [0, null, 0, null, 0, null, 0, 7, 0, null, 0, null, 0, null, 12, 7],
    arp: [0, 1, 2, 3, 0, 1, 2, 3, 3, 2, 1, 0, 3, 2, 1, 0],
    kick: [1, 0, 0, 0, 0, 0, 0, 0, 1, 0, 1, 0, 0, 0, 0, 0],
    hat: [0, 0, 1, 0, 0, 0, 1, 0, 0, 0, 1, 0, 0, 0, 1, 1],
    blip: "square", blipNotes: [7, 12], tada: [0, 4, 7, 12, 7, 12, 16],
  },
  // Bouncy triangle-wave pop in a major key, skipping rhythm.
  bubblegumPop: {
    tempo: 132, root: 53, lead: "triangle", bass: "triangle", leadGain: 0.09,
    chords: [[0, 4, 7, 12], [7, 11, 14, 19], [9, 12, 16, 21], [5, 9, 12, 17]],
    bassSteps: [0, null, null, 0, null, null, 7, null, 0, null, null, 0, null, 7, null, null],
    arp: [0, 2, 1, 3, 0, 2, 1, 3, 2, 3, 1, 2, 0, 1, 2, 3],
    kick: [1, 0, 0, 1, 0, 0, 1, 0, 1, 0, 0, 1, 0, 0, 1, 0],
    hat: [0, 1, 0, 0, 1, 0, 0, 1, 0, 1, 0, 0, 1, 0, 0, 1],
    blip: "triangle", blipNotes: [19, 24], tada: [0, 4, 7, 12, 16, 19, 24, 28],
  },
  // Slow lounge swing: sine-wave sevenths, walking bass, brushed hats.
  vegasLounge: {
    tempo: 84, root: 43, lead: "sine", bass: "sine", leadGain: 0.08, swing: 0.18,
    chords: [[0, 4, 7, 11, 14], [5, 9, 12, 16], [2, 5, 9, 12], [7, 11, 14, 17]],
    bassSteps: [0, null, null, null, 4, null, null, null, 7, null, null, null, 9, null, null, null],
    arp: [0, null, 2, null, 1, null, 3, null, 2, null, 4, null, 3, null, 1, null],
    kick: [1, 0, 0, 0, 0, 0, 0, 0, 1, 0, 0, 0, 0, 0, 0, 0],
    hat: [0, 0, 0, 0, 1, 0, 0, 1, 0, 0, 0, 0, 1, 0, 0, 1],
    blip: "sine", blipNotes: [12, 16], tada: [0, 4, 7, 11, 14, 19],
  },
};

const LOOKAHEAD = 0.25; // seconds of notes scheduled ahead
const TICK = 60; // ms between scheduling
let context = null;
let music = null; // { theme, gain, step, time }
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

/** One note: an oscillator through a quick attack and decay. */
function tone(destination, type, note, start, length, gain) {
  const ctx = destination.context;
  const osc = ctx.createOscillator();
  const env = ctx.createGain();
  osc.type = type;
  osc.frequency.value = frequency(note);
  env.gain.setValueAtTime(0, start);
  env.gain.linearRampToValueAtTime(gain, start + 0.01);
  env.gain.exponentialRampToValueAtTime(0.0001, start + length);
  osc.connect(env).connect(destination);
  osc.start(start);
  osc.stop(start + length + 0.05);
}

/** A drum: a falling sine (kick), or a burst of noise (hat). */
function drum(destination, kind, start) {
  const ctx = destination.context;
  const env = ctx.createGain();
  env.connect(destination);
  if (kind === "kick") {
    const osc = ctx.createOscillator();
    osc.frequency.setValueAtTime(140, start);
    osc.frequency.exponentialRampToValueAtTime(45, start + 0.12);
    env.gain.setValueAtTime(0.35, start);
    env.gain.exponentialRampToValueAtTime(0.0001, start + 0.2);
    osc.connect(env);
    osc.start(start);
    osc.stop(start + 0.25);
  } else {
    const noise = ctx.createBufferSource();
    const buffer = ctx.createBuffer(1, ctx.sampleRate * 0.05, ctx.sampleRate);
    const data = buffer.getChannelData(0);
    for (let i = 0; i < data.length; i++) data[i] = Math.random() * 2 - 1;
    noise.buffer = buffer;
    const filter = ctx.createBiquadFilter();
    filter.type = "highpass";
    filter.frequency.value = 7000;
    env.gain.setValueAtTime(0.05, start);
    env.gain.exponentialRampToValueAtTime(0.0001, start + 0.05);
    noise.connect(filter).connect(env);
    noise.start(start);
  }
}

/** Schedules the loop's notes up to LOOKAHEAD ahead. */
function schedule() {
  if (!music) return;
  const t = THEMES[music.theme];
  const sixteenth = 60 / t.tempo / 4;
  while (music.time < context.currentTime + LOOKAHEAD) {
    const step = music.step % 16;
    const chord = t.chords[Math.floor(music.step / 16) % t.chords.length];
    const at = music.time + (step % 2 === 1 ? (t.swing ?? 0) * sixteenth : 0);
    const bass = t.bassSteps[step];
    if (bass !== null) tone(music.gain, t.bass, t.root - 12 + chord[0] + bass, at, sixteenth * 1.8, 0.09);
    const arp = t.arp[step];
    if (arp !== null) tone(music.gain, t.lead, t.root + 12 + chord[arp % chord.length], at, sixteenth * 1.5, t.leadGain);
    if (t.kick[step]) drum(music.gain, "kick", at);
    if (t.hat[step]) drum(music.gain, "hat", at);
    music.time += sixteenth;
    music.step += 1;
  }
}

/** Plays `theme`'s tune, fading out any other. */
export function play(theme) {
  if (!THEMES[theme] || music?.theme === theme) return;
  stop(0.4);
  const ctx = audio();
  const gain = ctx.createGain();
  gain.gain.setValueAtTime(0, ctx.currentTime);
  gain.gain.linearRampToValueAtTime(0.7, ctx.currentTime + 0.4);
  gain.connect(ctx.destination);
  music = { theme, gain, step: 0, time: ctx.currentTime + 0.05 };
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

/** A sound effect in `theme`'s voice: "move", "choose", "back" or "queue". */
export function effect(name, theme) {
  const t = THEMES[theme];
  if (!t) return;
  const ctx = audio();
  const out = ctx.createGain();
  out.gain.value = 0.6;
  out.connect(ctx.destination);
  const now = ctx.currentTime + 0.01;
  const base = t.root + 12;
  switch (name) {
    case "move":
      tone(out, t.blip, base + t.blipNotes[0], now, 0.06, 0.05);
      break;
    case "choose":
      t.blipNotes.forEach((note, i) => tone(out, t.blip, base + note, now + i * 0.06, 0.12, 0.07));
      break;
    case "back":
      [...t.blipNotes].reverse().forEach((note, i) => tone(out, t.blip, base + note - 5, now + i * 0.06, 0.1, 0.06));
      break;
    case "queue":
      t.tada.forEach((note, i) => tone(out, t.lead, base + note, now + i * 0.07, 0.3, 0.07));
      break;
  }
  setTimeout(() => out.disconnect(), 2000);
}
