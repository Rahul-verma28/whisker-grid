"""Synthesises all of the game's original music and sound effects.
   python tools/make_audio.py
Writes assets/audio/*.wav (effects) and assets/audio/music.ogg (seamless loop, needs ffmpeg).
"""
import os
import subprocess
import wave

import numpy as np

SR = 44100
ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
OUT = os.path.join(ROOT, "assets", "audio")
os.makedirs(OUT, exist_ok=True)
rng = np.random.default_rng(7)


def hz(note):
    """'A4' / 'C#5' / 'Bb3' -> frequency."""
    names = {"C": 0, "D": 2, "E": 4, "F": 5, "G": 7, "A": 9, "B": 11}
    n = names[note[0]]
    rest = note[1:]
    if rest[0] == "#":
        n += 1
        rest = rest[1:]
    elif rest[0] == "b":
        n -= 1
        rest = rest[1:]
    midi = 12 * (int(rest) + 1) + n
    return 440.0 * 2 ** ((midi - 69) / 12)


def t(sec):
    return np.arange(int(sec * SR)) / SR


def env(n, attack=0.005, decay=0.3, sustain=0.0, release=0.05):
    """Simple ADSR-ish: attack then exponential decay towards sustain, short release at the end."""
    x = np.arange(n) / SR
    a = np.clip(x / max(attack, 1e-4), 0, 1)
    d = sustain + (1 - sustain) * np.exp(-x / max(decay, 1e-4))
    r = np.clip((n / SR - x) / max(release, 1e-4), 0, 1)
    return a * d * r


def marimba(f, dur, decay=0.35, bright=0.25):
    x = t(dur)
    s = np.sin(2 * np.pi * f * x) + bright * np.sin(2 * np.pi * f * 4 * x) * np.exp(-x / 0.04)
    s += 0.12 * np.sin(2 * np.pi * f * 2 * x)
    return s * env(len(x), 0.002, decay, 0, 0.03)


def bell(f, dur, decay=0.6):
    x = t(dur)
    parts = [(1, 1), (2.76, 0.35), (5.4, 0.18), (8.93, 0.08)]
    s = sum(a * np.sin(2 * np.pi * f * k * x) * np.exp(-x * k / (decay * 3)) for k, a in parts)
    return s * env(len(x), 0.002, decay, 0, 0.05)


def soft_tri(f, dur, decay=0.25):
    x = t(dur)
    s = 2 / np.pi * np.arcsin(np.sin(2 * np.pi * f * x))
    return s * env(len(x), 0.004, decay, 0, 0.04)


def mix(parts, total=None):
    """parts: list of (start_sec, signal, gain)."""
    end = max(int(st * SR) + len(sig) for st, sig, _ in parts)
    out = np.zeros(total or end)
    for st, sig, g in parts:
        i = int(st * SR)
        j = min(len(out), i + len(sig))
        out[i:j] += sig[: j - i] * g
    return out


def reverb(x, wet=0.25, room=0.5):
    """Small Schroeder-style reverb: a few feedback combs + allpass."""
    out = np.copy(x)
    acc = np.zeros(len(x) + SR)
    for delay_ms, fb in ((29.7, 0.77), (37.1, 0.75), (41.1, 0.73), (43.7, 0.71)):
        d = int(delay_ms * SR / 1000)
        buf = np.zeros(len(x) + SR)
        buf[: len(x)] = x
        fbk = fb * (0.7 + 0.3 * room)
        for i in range(d, len(buf), d):
            buf[i : i + d] += buf[i - d : i][: len(buf[i : i + d])] * fbk
        acc += buf
    acc /= 4
    return np.concatenate([out, np.zeros(SR)]) * (1 - wet) + acc * wet


def lowpass(x, cutoff):
    a = np.exp(-2 * np.pi * cutoff / SR)
    y = np.zeros_like(x)
    prev = 0.0
    for i in range(len(x)):
        prev = (1 - a) * x[i] + a * prev
        y[i] = prev
    return y


def save_wav(name, x, peak=0.85):
    x = x / (np.max(np.abs(x)) + 1e-9) * peak
    # tiny fades so nothing clicks
    f = min(len(x) // 10, 200)
    x[:f] *= np.linspace(0, 1, f)
    x[-f:] *= np.linspace(1, 0, f)
    data = (x * 32767).astype(np.int16)
    with wave.open(os.path.join(OUT, name), "wb") as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(SR)
        w.writeframes(data.tobytes())
    print("wrote", name, f"{len(x) / SR:.2f}s")


def trim(x, thresh=1e-3):
    idx = np.nonzero(np.abs(x) > thresh * np.max(np.abs(x)))[0]
    return x[: idx[-1] + 1] if len(idx) else x


# ================================================================ effects

def effects():
    # UI click: tiny woody tick
    save_wav("click.wav", trim(marimba(hz("G6"), 0.12, 0.03, 0.6)), 0.6)
    # tap (X mark): soft pop with falling pitch
    x = t(0.09)
    f = 900 * np.exp(-x * 18) + 320
    save_wav("mark.wav", np.sin(2 * np.pi * np.cumsum(f) / SR) * env(len(x), 0.001, 0.03, 0, 0.02), 0.55)
    # erase: the pop reversed in pitch
    f = 320 + 500 * (1 - np.exp(-x * 18))
    save_wav("erase.wav", np.sin(2 * np.pi * np.cumsum(f) / SR) * env(len(x), 0.001, 0.03, 0, 0.02), 0.4)
    # correct animal: bright two-note chime + sparkle
    s = mix([(0, marimba(hz("E6"), 0.5, 0.25), 1.0), (0.07, marimba(hz("B6"), 0.6, 0.3), 0.9),
             (0.07, bell(hz("E7"), 0.5, 0.25), 0.25)])
    save_wav("place.wav", trim(reverb(s, 0.2)), 0.8)
    # colour completed: quick rising arpeggio
    notes = ["C6", "E6", "G6", "C7"]
    s = mix([(i * 0.055, bell(hz(n), 0.6, 0.3), 0.8) for i, n in enumerate(notes)])
    save_wav("region.wav", trim(reverb(s, 0.25)), 0.7)
    # wrong: soft cartoon "bonk" bonk
    s = mix([(0, soft_tri(hz("G3"), 0.18, 0.08), 1.0), (0.13, soft_tri(hz("D3"), 0.28, 0.12), 1.0)])
    save_wav("wrong.wav", lowpass(s, 1800), 0.7)
    # star: bell ding (game plays it 3x at rising pitch)
    save_wav("star.wav", trim(reverb(bell(hz("A6"), 1.2, 0.5), 0.3)), 0.75)
    # hint: magic shimmer down
    s = mix([(i * 0.04, bell(hz(n), 0.5, 0.25), 0.6) for i, n in enumerate(["E7", "C7", "A6", "E6"])])
    save_wav("hint.wav", trim(reverb(s, 0.35)), 0.6)
    # unlock: rising glissando sparkle
    seq = ["C6", "D6", "E6", "G6", "A6", "C7", "D7", "E7", "G7"]
    s = mix([(i * 0.045, bell(hz(n), 0.7, 0.35), 0.6) for i, n in enumerate(seq)])
    save_wav("unlock.wav", trim(reverb(s, 0.35)), 0.75)
    # win fanfare: arpeggio up, then a warm chord with sparkles on top
    arp = ["C5", "E5", "G5", "C6"]
    parts = [(i * 0.09, marimba(hz(n), 0.6, 0.35), 0.9) for i, n in enumerate(arp)]
    for n in ["C5", "E5", "G5", "C6", "E6"]:
        x = t(1.8)
        tone = np.sin(2 * np.pi * hz(n) * x) + 0.3 * np.sin(2 * np.pi * hz(n) * 2 * x)
        parts.append((0.4, tone * env(len(x), 0.04, 0.9, 0.2, 0.5), 0.35))
    for i, n in enumerate(["G6", "C7", "E7", "G7", "C8"]):
        parts.append((0.45 + i * 0.07, bell(hz(n), 0.8, 0.35), 0.25))
    save_wav("win.wav", trim(reverb(mix(parts), 0.3)), 0.85)
    # out of hearts: gentle descending "aww"
    s = mix([(i * 0.22, soft_tri(hz(n), 0.45, 0.25), 0.9) for i, n in enumerate(["E4", "D4", "C4", "B3"])])
    save_wav("lose.wav", trim(reverb(lowpass(s, 2200), 0.25)), 0.65)


# ================================================================ music

def music():
    bpm = 84
    beat = 60 / bpm
    bar = beat * 4
    bars = 16
    length = int(bars * bar * SR)
    # I - vi - IV - V in F, two bars each, repeated
    chords = [["F3", "A3", "C4", "E4"], ["D3", "F3", "A3", "C4"], ["Bb2", "D3", "F3", "A3"], ["C3", "E3", "G3", "Bb3"]]
    roots = ["F2", "D2", "Bb1", "C2"]
    parts = []

    # warm pad: detuned sines with slow swell, one chord every 2 bars
    for b in range(0, bars, 2):
        ch = chords[(b // 2) % 4]
        dur = 2 * bar + 0.6
        x = t(dur)
        for n in ch:
            f = hz(n)
            tone = sum(np.sin(2 * np.pi * f * d * x) for d in (0.997, 1.0, 1.003)) / 3
            tone += 0.15 * np.sin(2 * np.pi * f * 2 * x)
            parts.append((b * bar, tone * env(len(x), 0.6, 9.0, 0.6, 0.8), 0.07))
        # soft bass on beats 1 and 3
        for k in range(4):
            parts.append((b * bar + k * 2 * beat, marimba(hz(roots[(b // 2) % 4]), 1.2, 0.5, 0.05), 0.28))

    # music-box melody over F major pentatonic, composed as two 8-bar phrases
    phrase_a = ["A5", "C6", "D6", "C6", "A5", "G5", "F5", "-", "G5", "A5", "C6", "A5", "G5", "-", "D5", "F5",
                "F5", "G5", "A5", "C6", "D6", "C6", "A5", "-", "G5", "A5", "G5", "F5", "D5", "-", "C5", "-"]
    phrase_b = ["C6", "-", "A5", "C6", "D6", "F6", "D6", "C6", "A5", "-", "G5", "A5", "C6", "-", "A5", "G5",
                "F5", "A5", "C6", "A5", "G5", "-", "F5", "G5", "A5", "G5", "F5", "D5", "F5", "-", "-", "-"]
    melody = phrase_a + phrase_b   # 64 half-beats? no: 64 notes, one per half beat = 32 beats = 8 bars
    melody = melody + melody       # 16 bars
    step = beat / 2 * 2            # one note per beat
    for i, n in enumerate(melody):
        if n == "-" or i * step >= bars * bar:
            continue
        parts.append((i * step, marimba(hz(n), 1.0, 0.45, 0.18), 0.22))
        parts.append((i * step, bell(hz(n) * 2, 0.8, 0.25), 0.04))   # glassy shimmer

    # very soft shaker on the off-beats
    for k in range(bars * 4):
        x = t(0.08)
        noise = rng.standard_normal(len(x)) * env(len(x), 0.002, 0.02, 0, 0.02)
        parts.append((k * beat + beat / 2, np.diff(noise, prepend=0), 0.025))

    song = mix(parts, length + 4 * SR)
    song = reverb(song, 0.3, 0.8)
    # fold the tail back onto the start so the loop is seamless
    loop = song[:length].copy()
    tail = song[length:]
    loop[: len(tail)] += tail[: len(loop)]
    loop = lowpass(loop, 6000)
    path = os.path.join(OUT, "_music.wav")
    loop = loop / np.max(np.abs(loop)) * 0.8
    with wave.open(path, "wb") as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(SR)
        w.writeframes((loop * 32767).astype(np.int16).tobytes())
    subprocess.run(["ffmpeg", "-y", "-loglevel", "error", "-i", path, "-c:a", "libvorbis", "-q:a", "4",
                    os.path.join(OUT, "music.ogg")], check=True)
    os.remove(path)
    print("wrote music.ogg", f"{length / SR:.1f}s loop")


effects()
music()
