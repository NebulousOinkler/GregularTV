"""The station card's music: "Marimba Bop", 15 seconds of marimba, glockenspiel,
bass, claps and brushes at 104 bpm in D major. Every sound is synthesised
here (pure Python, no samples), so the music is the app's own.

    python3 scripts/make-station-music.py

writes App/GregularTV/Audio/station-card.m4a (through macOS's afconvert).
Edit the tune or the instruments, then rerun.
"""
import math
import os
import random
import struct
import subprocess
import sys
import tempfile
import wave

SR = 44100
LENGTH = 15.0
TAU = 2 * math.pi
OUTPUT = "App/GregularTV/Audio/station-card.m4a"


def midi(m):
    return 440.0 * 2 ** ((m - 69) / 12)


class Mix:
    """A stereo mix, plus a reverb send."""

    def __init__(self, seconds=LENGTH):
        n = int(seconds * SR)
        self.left = [0.0] * n
        self.right = [0.0] * n
        self.send = [0.0] * n
        self.n = n

    def add(self, start, samples, gain=1.0, pan=0.0, reverb=0.25):
        i0 = int(start * SR)
        gl = gain * math.cos((pan + 1) * math.pi / 4)
        gr = gain * math.sin((pan + 1) * math.pi / 4)
        left, right, send = self.left, self.right, self.send
        for k, s in enumerate(samples):
            i = i0 + k
            if i >= self.n:
                break
            if i < 0:
                continue
            left[i] += s * gl
            right[i] += s * gr
            send[i] += s * gain * reverb

    def finish(self, fade=1.2):
        # Schroeder reverb on the send: combs in parallel, then allpasses, a little wider on the right.
        for out, combs in ((self.left, (1557, 1617, 1491, 1422)), (self.right, (1587, 1647, 1521, 1452))):
            wet = [0.0] * self.n
            for delay in combs:
                buf = [0.0] * delay
                j = 0
                feedback = 0.80
                for i in range(self.n):
                    y = buf[j]
                    buf[j] = self.send[i] + y * feedback
                    j = (j + 1) % delay
                    wet[i] += y * 0.25
            for delay in (225, 556):
                buf = [0.0] * delay
                j = 0
                for i in range(self.n):
                    b = buf[j]
                    y = -wet[i] + b
                    buf[j] = wet[i] + b * 0.5
                    j = (j + 1) % delay
                    wet[i] = y
            for i in range(self.n):
                out[i] += wet[i] * 0.35
        peak = max(max(abs(x) for x in self.left), max(abs(x) for x in self.right)) or 1
        scale = 0.89 / peak   # about -1 dBFS
        fade_n = int(fade * SR)
        for ch in (self.left, self.right):
            for i in range(self.n):
                g = scale
                if i < 400:
                    g *= i / 400
                if i > self.n - fade_n:
                    g *= max(0.0, (self.n - i) / fade_n) ** 1.5
                ch[i] = math.tanh(ch[i] * g * 1.1) / math.tanh(1.1)

    def write(self, path):
        with wave.open(path, "wb") as w:
            w.setnchannels(2)
            w.setsampwidth(2)
            w.setframerate(SR)
            frames = bytearray()
            for l, r in zip(self.left, self.right):
                frames += struct.pack("<hh", int(max(-1, min(1, l)) * 32767), int(max(-1, min(1, r)) * 32767))
            w.writeframes(bytes(frames))


# MARK: Instruments: each returns a list of samples.

def tone(freq, seconds, partials, attack=0.004, release=0.05, vibrato=0.0, vib_rate=5.5):
    """Additive tone: partials are (frequency ratio, level, decay per second)."""
    n = int(seconds * SR)
    out = [0.0] * n
    rel_n = int(release * SR)
    for ratio, level, decay in partials:
        f = freq * ratio
        phase = 0.0
        for i in range(n):
            t = i / SR
            if vibrato:
                phase += TAU * f * (1 + vibrato * math.sin(TAU * vib_rate * t) * min(1, t / 0.25)) / SR
            else:
                phase += TAU * f / SR
            env = math.exp(-decay * t)
            out[i] += math.sin(phase) * level * env
    att_n = max(1, int(attack * SR))
    for i in range(n):
        g = min(1.0, i / att_n)
        if i > n - rel_n:
            g *= (n - i) / rel_n
        out[i] *= g
    return out


def glockenspiel(m, seconds=1.4):
    return tone(midi(m), seconds, [(1, 1.0, 2.8), (2.756, 0.32, 6.0), (5.404, 0.12, 10.0)], attack=0.002)


def marimba(m, seconds=0.9):
    return tone(midi(m), seconds, [(1, 1.0, 5.0), (3.93, 0.22, 16.0), (9.2, 0.05, 30.0)], attack=0.003)


def round_bass(m, seconds=0.45):
    return tone(midi(m), seconds, [(1, 1.0, 3.0), (2, 0.25, 6.0)], attack=0.006, release=0.06)


def kick(seconds=0.35):
    n = int(seconds * SR)
    out = [0.0] * n
    phase = 0.0
    for i in range(n):
        t = i / SR
        f = 48 + 90 * math.exp(-t * 28)
        phase += TAU * f / SR
        out[i] = math.sin(phase) * math.exp(-t * 9) + (0.3 * math.exp(-t * 400) if i < 200 else 0)
    return out


def noise_hit(rng, seconds, decay, highpass=0.0, lowpass=1.0, bursts=(0.0,)):
    n = int(seconds * SR)
    out = [0.0] * n
    prev_x = prev_y = lp = 0.0
    for i in range(n):
        t = i / SR
        x = rng.uniform(-1, 1)
        hp = x - prev_x + highpass * prev_y if highpass else x
        prev_x, prev_y = x, hp
        lp = lp + lowpass * (hp - lp)
        env = sum(math.exp(-(t - b) * decay) for b in bursts if t >= b)
        out[i] = lp * env
    return out


def clap(rng):
    return noise_hit(rng, 0.25, 32, highpass=0.5, lowpass=0.45, bursts=(0.0, 0.011, 0.022))


def brush(rng):
    return noise_hit(rng, 0.22, 16, highpass=0.7, lowpass=0.35)


# MARK: The tune

class Song:
    def __init__(self, bpm, beats_per_bar):
        self.beat = 60 / bpm
        self.bar = self.beat * beats_per_bar
        self.mix = Mix()

    def at(self, bar, beat):
        return 0.05 + bar * self.bar + beat * self.beat

    def notes(self, instrument, bar, part, gain, pan=0.0, reverb=0.25):
        for beat, length, m in part:
            self.mix.add(self.at(bar, beat), instrument(m, max(0.3, length * self.beat + 0.6)), gain, pan, reverb)


def chord(root, quality):
    third = 3 if quality == "m" else 4
    return [root, root + third, root + 7]


def marimba_bop(rng):
    """Syncopated marimba, claps, brushes and bass: 104 bpm, D major, 6 bars and a ring."""
    s = Song(104, 4)
    progression = [(62, ""), (59, "m"), (55, ""), (57, ""), (55, ""), (62, "")]
    riff = [0, 0.75, 1.5, 2, 2.75, 3.5]
    for bar, (root, q) in enumerate(progression):
        notes = chord(root, q)
        tones = [notes[0] + 12, notes[1] + 12, notes[2] + 12, notes[0] + 24, notes[2] + 12, notes[1] + 12]
        if bar == 4:   # G then A
            tones = [67, 71, 74, 69, 73, 76]
        if bar == 5:   # a rolled D chord, held by a soft pad until the fade
            for k, m in enumerate([74, 78, 81, 86]):
                s.mix.add(s.at(bar, k * 0.25), marimba(m, 2.0), 0.24, pan=0.1, reverb=0.4)
            for m in (62, 66, 69):
                s.mix.add(s.at(bar, 0), tone(midi(m), 3.4, [(1, 1, 0.9), (2, .2, 1.6)], attack=0.02, release=0.6), 0.09, reverb=0.4)
        else:
            for beat, m in zip(riff, tones):
                s.mix.add(s.at(bar, beat), marimba(m), 0.24, pan=0.15, reverb=0.3)
        bass = root - 24 if root >= 60 else root - 12
        line = [(0, bass), (1.5, bass + 7), (2.5, bass + 12)] if bar < 5 else [(0, bass)]
        if bar == 4:
            line = [(0, 43), (2, 45)]
        for beat, m in line:
            s.mix.add(s.at(bar, beat), round_bass(m, 0.5 if bar < 5 else 2.0), 0.36, reverb=0.05)
    lead = [
        [(1, .5, 78), (1.5, .5, 81), (3, 1, 78)],
        [(1, .5, 74), (1.5, .5, 78), (3, 1, 83)],
        [(1, .5, 79), (1.5, .5, 83), (3, 1, 86)],
        [(1, .5, 85), (1.5, .5, 83), (3, 1, 81)],
        [(0, .5, 83), (1, .5, 81), (2, .5, 85), (3, .5, 88)],
    ]
    for bar, part in enumerate(lead):
        s.notes(glockenspiel, bar, part, 0.13, pan=-0.2, reverb=0.4)
    for bar in range(6):
        for b in ([0, 2.5] if bar < 5 else [0]):
            s.mix.add(s.at(bar, b), kick(), 0.42, reverb=0.0)
        if bar < 5:
            for b in (1, 3):
                s.mix.add(s.at(bar, b), clap(rng), 0.20, pan=0.15, reverb=0.3)
            for k in range(8):
                s.mix.add(s.at(bar, k / 2 + 0.25), brush(rng), 0.05, pan=-0.35, reverb=0.1)
    return s.mix


if __name__ == "__main__":
    mix = marimba_bop(random.Random(7))
    mix.finish()
    with tempfile.TemporaryDirectory() as tmp:
        wav = os.path.join(tmp, "station-card.wav")
        mix.write(wav)
        os.makedirs(os.path.dirname(OUTPUT), exist_ok=True)
        subprocess.run(["afconvert", "-f", "m4af", "-d", "aac", "-b", "192000", wav, OUTPUT], check=True)
    print("wrote", OUTPUT)
