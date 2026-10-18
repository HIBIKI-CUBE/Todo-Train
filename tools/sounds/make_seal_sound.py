#!/usr/bin/env python3
"""丸い印と角判の効果音を決定的に合成する。

どちらも 80〜120ms、立ち上がり 5ms 以内の短い「トン」。
丸い印は高めの軽い音、角判は 152Hz に 2〜6kHz の打撃を重ねた重い音。
数値は下のレシピだけ。変えたら再実行する。

    python3 tools/sounds/make_seal_sound.py
"""

from __future__ import annotations

import math
import struct
import subprocess
import wave
from dataclasses import dataclass
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
SOUND_DIR = ROOT / "Todo train" / "Resources" / "Sounds"
SAMPLE_RATE = 44_100


@dataclass(frozen=True)
class Recipe:
    name: str
    duration_ms: int
    attack_ms: float
    end_fade_ms: float
    peak: float
    body_hz: float
    body_decay_ms: float
    body_gain: float
    strike_hz: float
    strike_decay_ms: float
    strike_gain: float
    tick_hz: float
    tick_decay_ms: float
    tick_gain: float
    noise_decay_ms: float
    noise_gain: float
    noise_seed: int
    body_hz_low: float
    body_hz_high: float
    min_high_share: float
    min_low_share: float
    max_low_share: float


# 丸い印。高めの短い打撃。低い胴は載せない。
ROUND = Recipe(
    name="round_stamp",
    duration_ms=90,
    attack_ms=1.6,
    end_fade_ms=6.0,
    peak=0.52,
    body_hz=480.0,
    body_decay_ms=16.0,
    body_gain=0.38,
    strike_hz=3_200.0,
    strike_decay_ms=4.0,
    strike_gain=0.90,
    tick_hz=5_200.0,
    tick_decay_ms=2.4,
    tick_gain=0.42,
    noise_decay_ms=2.8,
    noise_gain=0.28,
    noise_seed=0xA11CE,
    body_hz_low=400.0,
    body_hz_high=620.0,
    min_high_share=0.25,
    min_low_share=0.0,
    max_low_share=0.22,
)

# 角判。152Hz の「トン」に中高域の芯を重ねる。
SEAL = Recipe(
    name="seal_stamp",
    duration_ms=100,
    attack_ms=2.0,
    end_fade_ms=8.0,
    peak=0.89,
    body_hz=152.0,
    body_decay_ms=28.0,
    body_gain=0.42,
    strike_hz=2_400.0,
    strike_decay_ms=8.0,
    strike_gain=0.78,
    tick_hz=4_600.0,
    tick_decay_ms=4.0,
    tick_gain=0.46,
    noise_decay_ms=4.0,
    noise_gain=0.42,
    noise_seed=0x5E41,
    body_hz_low=120.0,
    body_hz_high=190.0,
    min_high_share=0.35,
    min_low_share=0.25,
    max_low_share=1.0,
)


def envelope(t_ms: float, attack_ms: float, decay_ms: float) -> float:
    if t_ms < 0:
        return 0.0
    attack = t_ms / attack_ms if t_ms < attack_ms else 1.0
    return attack * math.exp(-t_ms / decay_ms)


def noise_samples(count: int, seed: int) -> list[float]:
    x = seed
    raw: list[float] = []
    for _ in range(count):
        x = (1_103_515_245 * x + 12_345) & 0x7FFFFFFF
        raw.append((x / 0x7FFFFFFF) * 2.0 - 1.0)
    out = [0.0] * count
    prev = 0.0
    for i, sample in enumerate(raw):
        out[i] = sample - 0.97 * prev
        prev = sample
    return out


def synthesize(recipe: Recipe) -> list[float]:
    count = int(SAMPLE_RATE * recipe.duration_ms / 1000)
    noise = noise_samples(count, recipe.noise_seed)
    samples = [0.0] * count
    for i in range(count):
        t = i / SAMPLE_RATE
        t_ms = t * 1000.0
        body = math.sin(2.0 * math.pi * recipe.body_hz * t) * envelope(
            t_ms, recipe.attack_ms, recipe.body_decay_ms
        ) * recipe.body_gain
        strike = math.sin(2.0 * math.pi * recipe.strike_hz * t) * envelope(
            t_ms, recipe.attack_ms, recipe.strike_decay_ms
        ) * recipe.strike_gain
        tick = math.sin(2.0 * math.pi * recipe.tick_hz * t) * envelope(
            t_ms, recipe.attack_ms, recipe.tick_decay_ms
        ) * recipe.tick_gain
        click = noise[i] * envelope(t_ms, recipe.attack_ms, recipe.noise_decay_ms) * recipe.noise_gain
        samples[i] = body + strike + tick + click
    fade = int(SAMPLE_RATE * recipe.end_fade_ms / 1000)
    if fade > 0:
        start = max(0, count - fade)
        span = count - start
        for j in range(span):
            window = 0.5 * (1.0 + math.cos(math.pi * j / span))
            samples[start + j] *= window
    peak = max(abs(sample) for sample in samples) or 1.0
    scale = recipe.peak / peak
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
    peak_bin = max(range(1, n // 2), key=lambda index: mags[index])
    return peak_bin * SAMPLE_RATE / n


def measured_attack_ms(samples: list[float]) -> float:
    peak = max(abs(sample) for sample in samples)
    threshold = peak * 0.8
    for index, sample in enumerate(samples):
        if abs(sample) >= threshold:
            return index / SAMPLE_RATE * 1000.0
    return 1_000.0


def rms(samples: list[float]) -> float:
    if not samples:
        return 0.0
    return math.sqrt(sum(sample * sample for sample in samples) / len(samples))


def measure(recipe: Recipe, samples: list[float]) -> dict[str, float]:
    duration_ms = len(samples) / SAMPLE_RATE * 1000.0
    rise = measured_attack_ms(samples)
    body_start = int(SAMPLE_RATE * 0.012)
    body_end = int(SAMPLE_RATE * min(0.080, recipe.duration_ms / 1000.0))
    body_hz = dominant_hz(samples[body_start:body_end])
    attack = samples[: int(SAMPLE_RATE * 0.015)]
    high_share = band_energy(attack, 2_000.0, 6_000.0)
    low_share = band_energy(attack, 80.0, 400.0)
    tail = samples[-max(1, int(SAMPLE_RATE * 0.001)) :]
    stats = {
        "duration_ms": duration_ms,
        "attack_ms": rise,
        "body_hz": body_hz,
        "high_share": high_share,
        "low_share": low_share,
        "peak": max(abs(sample) for sample in samples),
        "tail_rms": rms(tail),
        "rms": rms(samples),
    }
    print(
        f"{recipe.name}: duration={stats['duration_ms']:.1f}ms attack={stats['attack_ms']:.2f}ms "
        f"body={stats['body_hz']:.1f}Hz high_2_6k={stats['high_share']:.2f} "
        f"low_80_400={stats['low_share']:.2f} peak={stats['peak']:.3f} "
        f"rms={stats['rms']:.3f} tail_rms={stats['tail_rms']:.4f}"
    )
    return stats


def check_one(recipe: Recipe, stats: dict[str, float]) -> None:
    if not 80.0 <= stats["duration_ms"] <= 120.0:
        raise SystemExit(f"{recipe.name}: duration out of range")
    if stats["attack_ms"] >= 5.0:
        raise SystemExit(f"{recipe.name}: attack slower than 5ms")
    if not recipe.body_hz_low <= stats["body_hz"] <= recipe.body_hz_high:
        raise SystemExit(f"{recipe.name}: body frequency out of range ({stats['body_hz']})")
    if stats["high_share"] < recipe.min_high_share:
        raise SystemExit(f"{recipe.name}: high band is low ({stats['high_share']})")
    if stats["low_share"] < recipe.min_low_share or stats["low_share"] > recipe.max_low_share:
        raise SystemExit(f"{recipe.name}: low band out of range ({stats['low_share']})")
    if stats["peak"] > 0.95:
        raise SystemExit(f"{recipe.name}: peak too hot")
    if stats["tail_rms"] > 0.02:
        raise SystemExit(f"{recipe.name}: tail does not fade")


def check_pair(light: dict[str, float], heavy: dict[str, float]) -> None:
    if not light["body_hz"] > heavy["body_hz"]:
        raise SystemExit("round stamp is not higher than the seal")
    if not light["peak"] < heavy["peak"]:
        raise SystemExit("round stamp is not quieter than the seal")
    if not light["low_share"] < heavy["low_share"]:
        raise SystemExit("round stamp is not lighter in the low band")
    if not light["rms"] < heavy["rms"]:
        raise SystemExit("round stamp rms is not below the seal")


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
    rendered = {recipe.name: synthesize(recipe) for recipe in (ROUND, SEAL)}
    stats = {recipe.name: measure(recipe, rendered[recipe.name]) for recipe in (ROUND, SEAL)}
    for recipe in (ROUND, SEAL):
        check_one(recipe, stats[recipe.name])
    check_pair(stats[ROUND.name], stats[SEAL.name])
    for recipe in (ROUND, SEAL):
        wav_path = Path(f"/tmp/{recipe.name}.wav")
        caf_path = SOUND_DIR / f"{recipe.name}.caf"
        write_wav(wav_path, rendered[recipe.name])
        write_caf(wav_path, caf_path)
        print(f"wrote {caf_path}")


if __name__ == "__main__":
    main()
