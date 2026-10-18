#!/usr/bin/env python3
"""判専用の効果音 seal_stamp.caf を決定的に合成する。

長さ 100ms（80〜120ms）。立ち上がりは 2ms で、5ms 以内。
152Hz の短い「トン」に、2.4kHz と 4.6kHz の打撃と高域のノイズを重ねる。
アタックを鋭くし、中高域に芯を残して、音楽の低域に埋もれにくくする。

数値は下の定数だけ。変えたら再実行する。

    python3 tools/sounds/make_seal_sound.py
"""

from __future__ import annotations

import math
import struct
import subprocess
import wave
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
CAF_PATH = ROOT / "Todo train" / "Resources" / "Sounds" / "seal_stamp.caf"

SAMPLE_RATE = 44_100
DURATION_MS = 100
ATTACK_MS = 2.0
END_FADE_MS = 8.0
PEAK = 0.89

# 低い「トン」。固定の 152Hz。減衰は短く、余韻を伸ばさない。
BODY_HZ = 152.0
BODY_DECAY_MS = 28.0
BODY_GAIN = 0.42

# 打撃の芯。2〜6kHz。音楽の低域より上に置く。
STRIKE_HZ = 2_400.0
STRIKE_DECAY_MS = 8.0
STRIKE_GAIN = 0.78

TICK_HZ = 4_600.0
TICK_DECAY_MS = 4.0
TICK_GAIN = 0.46

# 紙に当たった瞬間の高域。決定的な乱数。
NOISE_DECAY_MS = 4.0
NOISE_GAIN = 0.42
NOISE_SEED = 0x5E41


def attack_decay(t_ms: float, decay_ms: float) -> float:
    if t_ms < 0:
        return 0.0
    if t_ms < ATTACK_MS:
        attack = t_ms / ATTACK_MS
    else:
        attack = 1.0
    return attack * math.exp(-t_ms / decay_ms)


def noise_samples(count: int) -> list[float]:
    x = NOISE_SEED
    raw: list[float] = []
    for _ in range(count):
        x = (1_103_515_245 * x + 12_345) & 0x7FFFFFFF
        raw.append((x / 0x7FFFFFFF) * 2.0 - 1.0)
    # 1 次の差分で低い成分を落とし、打撃の芯を中高域に寄せる。
    out = [0.0] * count
    prev = 0.0
    for i, sample in enumerate(raw):
        out[i] = sample - 0.97 * prev
        prev = sample
    return out


def synthesize() -> list[float]:
    count = int(SAMPLE_RATE * DURATION_MS / 1000)
    noise = noise_samples(count)
    samples = [0.0] * count
    for i in range(count):
        t = i / SAMPLE_RATE
        t_ms = t * 1000.0
        body = math.sin(2.0 * math.pi * BODY_HZ * t) * attack_decay(t_ms, BODY_DECAY_MS) * BODY_GAIN
        strike = math.sin(2.0 * math.pi * STRIKE_HZ * t) * attack_decay(t_ms, STRIKE_DECAY_MS) * STRIKE_GAIN
        tick = math.sin(2.0 * math.pi * TICK_HZ * t) * attack_decay(t_ms, TICK_DECAY_MS) * TICK_GAIN
        click = noise[i] * attack_decay(t_ms, NOISE_DECAY_MS) * NOISE_GAIN
        samples[i] = body + strike + tick + click
    fade = int(SAMPLE_RATE * END_FADE_MS / 1000)
    if fade > 0:
        start = count - fade
        for j in range(fade):
            # 終端のクリックを出さない。
            window = 0.5 * (1.0 + math.cos(math.pi * j / fade))
            samples[start + j] *= window
    peak = max(abs(sample) for sample in samples) or 1.0
    scale = PEAK / peak
    return [sample * scale for sample in samples]


def fft_magnitudes(samples: list[float]) -> tuple[list[float], int]:
    n = 1
    while n < len(samples):
        n *= 2
    buf = [complex(samples[i], 0.0) if i < len(samples) else 0j for i in range(n)]
    reversed_index = 0
    for index in range(1, n):
        bit = n >> 1
        while reversed_index & bit:
            reversed_index ^= bit
            bit >>= 1
        reversed_index ^= bit
        if index < reversed_index:
            buf[index], buf[reversed_index] = buf[reversed_index], buf[index]
    length = 2
    while length <= n:
        half = length // 2
        angle = -2.0 * math.pi / length
        w_step = complex(math.cos(angle), math.sin(angle))
        for start in range(0, n, length):
            w = 1 + 0j
            for k in range(half):
                a = buf[start + k]
                b = buf[start + k + half] * w
                buf[start + k] = a + b
                buf[start + k + half] = a - b
                w *= w_step
        length *= 2
    return [abs(value) for value in buf], n


def band_energy(samples: list[float], low_hz: float, high_hz: float) -> float:
    mags, n = fft_magnitudes(samples)
    total = 0.0
    band = 0.0
    for bin_index, mag in enumerate(mags[: n // 2]):
        hz = bin_index * SAMPLE_RATE / n
        power = mag * mag
        total += power
        if low_hz <= hz < high_hz:
            band += power
    if total <= 0:
        return 0.0
    return band / total


def dominant_hz(samples: list[float]) -> float:
    mags, n = fft_magnitudes(samples)
    # 直流を除き、打撃が消えたあとの胴の音を見る。
    peak_bin = max(range(1, n // 2), key=lambda index: mags[index])
    return peak_bin * SAMPLE_RATE / n


def attack_ms(samples: list[float]) -> float:
    peak = max(abs(sample) for sample in samples)
    threshold = peak * 0.8
    for index, sample in enumerate(samples):
        if abs(sample) >= threshold:
            return index / SAMPLE_RATE * 1000.0
    return DURATION_MS


def check(samples: list[float]) -> None:
    duration_ms = len(samples) / SAMPLE_RATE * 1000.0
    rise = attack_ms(samples)
    body_start = int(SAMPLE_RATE * 0.012)
    body_end = int(SAMPLE_RATE * 0.080)
    body_hz = dominant_hz(samples[body_start:body_end])
    attack_count = int(SAMPLE_RATE * 0.015)
    attack = samples[:attack_count]
    high_share = band_energy(attack, 2_000.0, 6_000.0)
    low_share = band_energy(attack, 80.0, 400.0)
    tail = samples[-int(SAMPLE_RATE * 0.001) :]
    tail_rms = math.sqrt(sum(sample * sample for sample in tail) / len(tail))
    peak = max(abs(sample) for sample in samples)
    print(
        f"duration={duration_ms:.1f}ms attack={rise:.2f}ms "
        f"body={body_hz:.1f}Hz high_2_6k={high_share:.2f} low_80_400={low_share:.2f} "
        f"peak={peak:.3f} tail_rms={tail_rms:.4f}"
    )
    if not 80.0 <= duration_ms <= 120.0:
        raise SystemExit(f"duration out of range: {duration_ms}")
    if rise >= 5.0:
        raise SystemExit(f"attack slower than 5ms: {rise}")
    if not 120.0 <= body_hz <= 190.0:
        raise SystemExit(f"body frequency out of range: {body_hz}")
    if high_share < 0.35:
        raise SystemExit(f"2–6kHz share in the attack is low: {high_share}")
    if peak > 0.95:
        raise SystemExit(f"peak too hot: {peak}")
    if tail_rms > 0.02:
        raise SystemExit(f"tail does not fade: {tail_rms}")


def write_wav(path: Path, samples: list[float]) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    with wave.open(str(path), "w") as handle:
        handle.setnchannels(1)
        handle.setsampwidth(2)
        handle.setframerate(SAMPLE_RATE)
        frames = bytearray()
        for sample in samples:
            clamped = max(-1.0, min(1.0, sample))
            frames += struct.pack("<h", int(round(clamped * 32767.0)))
        handle.writeframes(frames)


def write_caf(wav_path: Path, caf_path: Path) -> None:
    caf_path.parent.mkdir(parents=True, exist_ok=True)
    if caf_path.exists():
        caf_path.unlink()
    subprocess.check_call(
        [
            "afconvert",
            "-f",
            "caff",
            "-d",
            "LEI16@44100",
            "-c",
            "1",
            str(wav_path),
            str(caf_path),
        ]
    )


def main() -> None:
    samples = synthesize()
    check(samples)
    wav_path = Path("/tmp/seal_stamp.wav")
    write_wav(wav_path, samples)
    write_caf(wav_path, CAF_PATH)
    print(f"wrote {CAF_PATH}")


if __name__ == "__main__":
    main()
