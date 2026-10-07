// Karaoke's menu tunes and sound effects, played with the Web Audio API as
// they go: no sound files, nothing fetched. The notes and instruments come
// from the app (GregularScreens' KaraokeMusic, through GregularWeb's
// KaraokeSound), so this only plays them, as the Apple TV version's
// synthesizer (KaraokeSynth.swift) does: a tune's intro, then its loop round
// and round; an effect once.
//
// A tune is { patches, kit, echoTime, echoFeedback, reverbTime, intro,
// introDuration, loop, duration }. A patch is an instrument (KaraokeMusic.Patch:
// waves, detune, attack, decay, sustain, release, cutoff, sweep, resonance,
// fmRatio, fmDepth, vibrato, tremolo, pan, echo, reverb, level, group). A note
// is { at, length, gain, pan } and either { part, note } (a MIDI note on an
// instrument) or { drum }.

const LOOKAHEAD = 0.25; // seconds of notes scheduled ahead
const TICK = 60; // ms between scheduling
const GROUPS = ["drums", "bass", "pad", "lead", "effects"];
let context = null;
let master = null; // where every tune and effect goes, through the limiter
let duck = null; // the tunes dip under an effect
let noise = null; // two seconds of white noise, shared by the drums
let music = null; // { id, bus, tune, start, nextIntro, nextLoop }
let timer = null;
let moodGains = Object.fromEntries(GROUPS.map((group) => [group, 1]));
const effectBuses = new Map();

function audio() {
  if (!context) {
    context = new AudioContext();
    // Browsers start sound only after a click or key: carry on at the next one.
    for (const type of ["pointerdown", "keydown"]) {
      addEventListener(type, () => context.state === "suspended" && context.resume(), { capture: true });
    }
    const limiter = context.createDynamicsCompressor();
    limiter.threshold.value = -8;
    limiter.knee.value = 6;
    limiter.ratio.value = 6;
    limiter.attack.value = 0.003;
    limiter.release.value = 0.25;
    limiter.connect(context.destination);
    master = context.createGain();
    master.gain.value = 0.8;
    master.connect(limiter);
    duck = context.createGain();
    duck.connect(master);
    noise = context.createBuffer(1, context.sampleRate * 2, context.sampleRate);
    const data = noise.getChannelData(0);
    for (let i = 0; i < data.length; i++) data[i] = Math.random() * 2 - 1;
  }
  if (context.state === "suspended") context.resume();
  return context;
}

const frequency = (note) => 440 * 2 ** ((note - 69) / 12);

/** A reverb's ring: stereo noise dying away over `seconds`. */
function impulse(ctx, seconds) {
  const length = Math.max(1, Math.floor(ctx.sampleRate * Math.max(seconds, 0.2)));
  const buffer = ctx.createBuffer(2, length, ctx.sampleRate);
  for (let channel = 0; channel < 2; channel++) {
    const data = buffer.getChannelData(channel);
    for (let i = 0; i < length; i++) data[i] = (Math.random() * 2 - 1) * 0.001 ** (i / length);
  }
  return buffer;
}

/** Where one tune (or a theme's effects) plays: a level for each group, an echo and a reverb, into `destination`. */
function makeBus(tune, destination) {
  const ctx = audio();
  const out = ctx.createGain();
  out.connect(destination);
  const groups = {};
  for (const group of GROUPS) {
    groups[group] = ctx.createGain();
    groups[group].gain.value = group === "effects" ? 1 : moodGains[group];
    groups[group].connect(out);
  }
  // A ping-pong echo, each repeat a little darker.
  const echo = ctx.createGain();
  const left = ctx.createDelay(2);
  const right = ctx.createDelay(2);
  left.delayTime.value = right.delayTime.value = Math.min(1.9, tune.echoTime);
  const tone = ctx.createBiquadFilter();
  tone.type = "lowpass";
  tone.frequency.value = 3500;
  const feedback = ctx.createGain();
  feedback.gain.value = Math.min(0.8, tune.echoFeedback);
  const merger = ctx.createChannelMerger(2);
  echo.connect(left);
  left.connect(right);
  right.connect(tone).connect(feedback).connect(left);
  left.connect(merger, 0, 0);
  right.connect(merger, 0, 1);
  const echoReturn = ctx.createGain();
  echoReturn.gain.value = 0.6;
  merger.connect(echoReturn).connect(out);
  const reverb = ctx.createConvolver();
  reverb.buffer = impulse(ctx, tune.reverbTime);
  const reverbReturn = ctx.createGain();
  reverbReturn.gain.value = 0.35;
  reverb.connect(reverbReturn).connect(out);
  return { out, groups, echo, reverb, patches: tune.patches, kit: tune.kit };
}

/** A gain node, set. */
function gainNode(ctx, value) {
  const node = ctx.createGain();
  node.gain.value = value;
  return node;
}

/** Sends `node` to the bus's group, echo and reverb, placed at `pan`. */
function route(bus, node, group, pan, echo, reverb) {
  const ctx = node.context;
  const panner = ctx.createStereoPanner();
  panner.pan.value = Math.max(-1, Math.min(1, pan));
  node.connect(panner).connect(bus.groups[group]);
  if (echo > 0) panner.connect(gainNode(ctx, echo)).connect(bus.echo);
  if (reverb > 0) panner.connect(gainNode(ctx, reverb)).connect(bus.reverb);
}

/** One note on an instrument, as the Apple TV's `Voice` plays it. */
function tone(bus, note, start) {
  const patch = bus.patches[note.part];
  if (!patch) return;
  const ctx = bus.out.context;
  const f = frequency(note.note);
  const hold = Math.max(note.length, patch.attack);
  const end = start + hold + patch.release * 1.5 + 0.05;
  const env = ctx.createGain();
  env.gain.setValueAtTime(0, start);
  env.gain.linearRampToValueAtTime(1, start + patch.attack);
  env.gain.setTargetAtTime(patch.sustain, start + patch.attack, patch.decay / 4);
  env.gain.setTargetAtTime(0, start + hold, patch.release / 5);
  let into = env;
  if (patch.cutoff + patch.sweep < 0.4 * ctx.sampleRate) {
    const filter = ctx.createBiquadFilter();
    filter.type = "lowpass";
    filter.Q.value = 20 * Math.log10(Math.max(patch.resonance, 0.5));
    filter.frequency.setValueAtTime(Math.min(patch.cutoff + patch.sweep, 0.45 * ctx.sampleRate), start);
    filter.frequency.setTargetAtTime(patch.cutoff, start, patch.decay / 3);
    filter.connect(env);
    into = filter;
  }
  const waves = patch.waves.slice(0, 3);
  const count = patch.fmRatio > 0 ? 1 : waves.length;
  const level = gainNode(ctx, 1 / Math.sqrt(count));
  level.connect(into);
  let vibrato = null;
  if (patch.vibrato > 0) {
    vibrato = ctx.createOscillator();
    vibrato.frequency.value = 5.5;
    vibrato.start(start);
    vibrato.stop(end);
  }
  for (let index = 0; index < count; index++) {
    const osc = ctx.createOscillator();
    osc.type = waves[index];
    osc.frequency.value = f;
    osc.detune.value = count === 1 ? 0 : patch.detune * (index / (count - 1) - 0.5);
    if (vibrato) vibrato.connect(gainNode(ctx, patch.vibrato)).connect(osc.detune);
    if (patch.fmRatio > 0) {
      const modulator = ctx.createOscillator();
      modulator.frequency.value = f * patch.fmRatio;
      const depth = ctx.createGain();
      depth.gain.setValueAtTime(patch.fmDepth * f * patch.fmRatio, start);
      depth.gain.setTargetAtTime(0, start, patch.decay / 3);
      modulator.connect(depth).connect(osc.frequency);
      modulator.start(start);
      modulator.stop(end);
    }
    osc.connect(level);
    osc.start(start);
    osc.stop(end);
  }
  let out = env;
  if (patch.tremolo > 0) {
    const wobble = gainNode(ctx, 1 - patch.tremolo / 2);
    const lfo = ctx.createOscillator();
    lfo.frequency.value = 5;
    lfo.connect(gainNode(ctx, patch.tremolo / 2)).connect(wobble.gain);
    lfo.start(start);
    lfo.stop(end);
    env.connect(wobble);
    out = wobble;
  }
  const loudness = gainNode(ctx, patch.level * note.gain);
  out.connect(loudness);
  route(bus, loudness, patch.group, patch.pan + (note.pan ?? 0), patch.echo, patch.reverb);
}

/** Noise through a filter, from `start`, into a new gain node (returned, for its envelope). */
function filteredNoise(ctx, type, frequencyHz, q, start, seconds) {
  const source = ctx.createBufferSource();
  source.buffer = noise;
  const filter = ctx.createBiquadFilter();
  filter.type = type;
  filter.frequency.value = Math.min(frequencyHz, 0.45 * ctx.sampleRate);
  filter.Q.value = q;
  const env = ctx.createGain();
  env.gain.value = 0;
  source.connect(filter).connect(env);
  source.start(start, Math.random() * 1.5);
  source.stop(start + seconds);
  return env;
}

/** A sine falling from `from` to `to` hertz, into a new gain node. */
function fallingTone(ctx, from, to, fall, start, seconds) {
  const osc = ctx.createOscillator();
  osc.frequency.setValueAtTime(from, start);
  osc.frequency.setTargetAtTime(to, start, fall);
  const env = ctx.createGain();
  env.gain.value = 0;
  osc.connect(env);
  osc.start(start);
  osc.stop(start + seconds);
  return env;
}

/** Rings: `peak` at `start`, dying away with time constant `tc`. */
function ring(param, peak, start, tc, attack = 0) {
  param.setValueAtTime(0, start);
  if (attack > 0) param.linearRampToValueAtTime(peak, start + attack);
  else param.setValueAtTime(peak, start);
  param.setTargetAtTime(0, start + attack, tc);
}

/** A drum, made from noise and falling tones, as the Apple TV's are. */
function drum(bus, note, start) {
  const ctx = bus.out.context;
  const { tune: t = 1, decay: d = 1, reverb = 0.15, level = 1 } = bus.kit ?? {};
  const g = note.gain * level;
  const parts = [];
  switch (note.drum) {
    case "kick": {
      const body = fallingTone(ctx, 150 * t, 45 * t, 0.03, start, 0.8 * d);
      ring(body.gain, g, start, 0.14 * d);
      const click = filteredNoise(ctx, "highpass", 1000, 0.7, start, 0.03);
      ring(click.gain, g * 0.25, start, 0.003);
      parts.push(body, click);
      break;
    }
    case "snare": {
      const body = fallingTone(ctx, 185 * t, 185 * t, 1, start, 0.4 * d);
      ring(body.gain, g * 0.5, start, 0.05 * d);
      const rattle = filteredNoise(ctx, "highpass", 1400 * t, 0.7, start, 0.5 * d);
      ring(rattle.gain, g * 0.8, start, 0.09 * d);
      parts.push(body, rattle);
      break;
    }
    case "clap": {
      const clap = filteredNoise(ctx, "bandpass", 1100 * t, 1.2, start, 0.5 * d);
      for (const offset of [0, 0.01, 0.02]) {
        clap.gain.setValueAtTime(g * 2.2, start + offset);
        clap.gain.setTargetAtTime(0, start + offset, 0.003);
      }
      clap.gain.setValueAtTime(g * 2.2, start + 0.03);
      clap.gain.setTargetAtTime(0, start + 0.03, 0.09 * d);
      parts.push(clap);
      break;
    }
    case "hat":
    case "openHat":
    case "shaker":
    case "crash": {
      const [cutoff, tc, attack] = { hat: [7000, 0.018, 0], openHat: [6500, 0.14, 0], shaker: [5000, 0.035, 0.008], crash: [4000, 0.55, 0] }[note.drum];
      const hiss = filteredNoise(ctx, "highpass", cutoff * t, 0.7, start, tc * d * 8);
      ring(hiss.gain, g, start, tc * d, attack);
      parts.push(hiss);
      break;
    }
    case "brush": {
      const swish = filteredNoise(ctx, "bandpass", 2600 * t, 0.7, start, 0.6 * d);
      ring(swish.gain, g * 1.6, start, 0.09 * d, 0.03);
      parts.push(swish);
      break;
    }
    case "tomHigh":
    case "tomLow": {
      const [from, to, tc] = note.drum === "tomHigh" ? [260, 200, 0.16] : [160, 120, 0.2];
      const body = fallingTone(ctx, from * t, to * t, 0.05, start, tc * d * 5);
      ring(body.gain, g, start, tc * d);
      parts.push(body);
      break;
    }
    case "rim": {
      const click = fallingTone(ctx, 900 * t, 900 * t, 1, start, 0.1);
      ring(click.gain, g, start, 0.012);
      const tick = filteredNoise(ctx, "bandpass", 2000 * t, 1.5, start, 0.1);
      ring(tick.gain, g, start, 0.008);
      parts.push(click, tick);
      break;
    }
    default:
      return;
  }
  const wet = ["snare", "clap", "tomHigh", "tomLow", "rim", "brush"].includes(note.drum) ? reverb : 0.05;
  for (const part of parts) route(bus, part, "drums", note.pan ?? 0, 0, wet);
}

function sound(bus, note, start) {
  if (note.drum) drum(bus, note, start);
  else tone(bus, note, start);
}

/** Schedules the tune's notes up to LOOKAHEAD ahead: the intro once, then the loop round and round. */
function schedule() {
  if (!music) return;
  const { tune, bus } = music;
  const until = context.currentTime + LOOKAHEAD;
  while (music.nextIntro < tune.intro.length) {
    const note = tune.intro[music.nextIntro];
    const at = music.start + note.at;
    if (at >= until) return;
    sound(bus, note, at);
    music.nextIntro += 1;
  }
  if (tune.loop.length === 0) return;
  const loopStart = music.start + tune.introDuration;
  for (;;) {
    const round = Math.floor(music.nextLoop / tune.loop.length);
    const note = tune.loop[music.nextLoop % tune.loop.length];
    const at = loopStart + round * tune.duration + note.at;
    if (at >= until) return;
    sound(bus, note, at);
    music.nextLoop += 1;
  }
}

/** Plays a tune: its intro, then round and round (`id` names it: the same one carries on), crossfading from any other. */
export function play(id, tune) {
  if (music?.id === id || tune.loop.length === 0) return;
  stop(0.6);
  const ctx = audio();
  const bus = makeBus(tune, duck);
  bus.out.gain.setValueAtTime(0, ctx.currentTime);
  bus.out.gain.linearRampToValueAtTime(1, ctx.currentTime + 0.4);
  music = { id, bus, tune, start: ctx.currentTime + 0.05, nextIntro: 0, nextLoop: 0 };
  schedule();
  timer ??= setInterval(schedule, TICK);
}

/** Fades the tune out over `seconds`, echoes and all. */
export function stop(seconds = 1.2) {
  if (!music) return;
  const { out } = music.bus;
  const now = context.currentTime;
  out.gain.cancelScheduledValues(now);
  out.gain.setValueAtTime(out.gain.value, now);
  out.gain.linearRampToValueAtTime(0, now + seconds);
  setTimeout(() => out.disconnect(), seconds * 1000 + 3000);
  music = null;
  clearInterval(timer);
  timer = null;
}

/** How loud each group is ({ drums, bass, pad, lead }: 0 to 1): soft under a title card, full otherwise. */
export function mood(gains) {
  moodGains = { ...moodGains, ...gains };
  if (!music || !context) return;
  for (const [group, value] of Object.entries(gains)) {
    music.bus.groups[group]?.gain.setTargetAtTime(value, context.currentTime, 0.3);
  }
}

/** Plays a sound effect's notes once, on theme `id`'s instruments, with the tune dipping under it. */
export function effect(id, tune, notes) {
  const ctx = audio();
  let bus = effectBuses.get(id);
  if (!bus) {
    bus = makeBus(tune, master);
    effectBuses.set(id, bus);
  }
  const now = ctx.currentTime + 0.01;
  let end = now;
  for (const note of notes) {
    sound(bus, note, now + note.at);
    end = Math.max(end, now + note.at + (note.length ?? 0.1));
  }
  duck.gain.cancelScheduledValues(now);
  duck.gain.setTargetAtTime(0.55, now, 0.01);
  duck.gain.setTargetAtTime(1, end + 0.15, 0.1);
}
