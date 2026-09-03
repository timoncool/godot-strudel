"""Сверка ЗВУКА плагина с эталоном, снятым офлайн-рендером самой Булки.

События уже сверены поимённо (compare.py). Здесь проверяется то, что событиями
не измеряется: уровень, спектр, положение ударов во времени.

    python tools/judge/compare_audio.py эталон.wav наш.wav

Числа, а не «звучит похоже»: расхождения печатаются в децибелах и герцах.
"""

import math
import struct
import sys
import wave
from pathlib import Path

if hasattr(sys.stdout, "reconfigure"):
    sys.stdout.reconfigure(encoding="utf-8", errors="replace")


def read_wav(path: Path) -> tuple[list[float], int]:
    with wave.open(str(path), "rb") as w:
        rate = w.getframerate()
        channels = w.getnchannels()
        width = w.getsampwidth()
        frames = w.readframes(w.getnframes())
    if width == 2:
        count = len(frames) // 2
        values = struct.unpack("<%dh" % count, frames[: count * 2])
        scale = 1.0 / 32768.0
    elif width == 4:
        count = len(frames) // 4
        values = struct.unpack("<%df" % count, frames[: count * 4])
        scale = 1.0
    else:
        raise SystemExit(f"не умею {width * 8}-битный WAV: {path}")
    mono = []
    for i in range(0, len(values) - channels + 1, channels):
        acc = sum(values[i + c] for c in range(channels))
        mono.append(acc * scale / channels)
    return mono, rate


def rms(xs) -> float:
    if not xs:
        return 0.0
    return math.sqrt(sum(x * x for x in xs) / len(xs))


def db(x: float) -> float:
    return 20.0 * math.log10(max(x, 1e-12))


def dft_bands(xs: list[float], rate: int, bands: list[tuple[float, float]]) -> list[float]:
    """Энергия по полосам через Гёрцеля — без сторонних библиотек."""
    n = min(len(xs), 1 << 15)
    chunk = xs[:n]
    out = []
    for low, high in bands:
        # несколько зондов на полосу, чтобы не зависеть от одной частоты
        total = 0.0
        probes = 6
        for p in range(probes):
            freq = low * (high / low) ** (p / max(probes - 1, 1))
            k = freq / rate
            w = 2.0 * math.pi * k
            coeff = 2.0 * math.cos(w)
            s0 = s1 = s2 = 0.0
            for x in chunk:
                s0 = x + coeff * s1 - s2
                s2 = s1
                s1 = s0
            power = s1 * s1 + s2 * s2 - coeff * s1 * s2
            total += max(power, 0.0)
        out.append(math.sqrt(total / probes / n))
    return out


def onsets(xs: list[float], rate: int, threshold: float = 0.12) -> list[float]:
    """Моменты ударов: где огибающая резко пошла вверх."""
    win = max(int(rate * 0.005), 1)
    env = []
    for i in range(0, len(xs) - win, win):
        env.append(rms(xs[i : i + win]))
    peak = max(env) if env else 0.0
    if peak <= 0.0:
        return []
    marks = []
    prev = 0.0
    for i, v in enumerate(env):
        if v > peak * threshold and prev <= peak * threshold:
            marks.append(i * win / rate)
        prev = v
    return marks


BANDS = [
    (40, 120), (120, 300), (300, 800), (800, 2000),
    (2000, 5000), (5000, 12000),
]
BAND_NAMES = ["низ 40-120", "120-300", "300-800", "800-2к", "2к-5к", "5к-12к"]


def main() -> int:
    if len(sys.argv) < 3:
        print(__doc__)
        return 2
    ref_path = Path(sys.argv[1])
    mine_path = Path(sys.argv[2])
    ref, rate_a = read_wav(ref_path)
    mine, rate_b = read_wav(mine_path)

    print(f"[звук] эталон {ref_path.name}: {len(ref)} отсчётов, {rate_a} Гц")
    print(f"[звук] плагин {mine_path.name}: {len(mine)} отсчётов, {rate_b} Гц")
    if rate_a != rate_b:
        print("!! частоты не совпадают — сравнивать нельзя")
        return 1

    n = min(len(ref), len(mine))
    ref, mine = ref[:n], mine[:n]

    r_rms, m_rms = rms(ref), rms(mine)
    r_peak, m_peak = max(abs(x) for x in ref), max(abs(x) for x in mine)
    print()
    print(f"[уровень] СКЗ:  эталон {db(r_rms):7.2f} дБ · плагин {db(m_rms):7.2f} дБ"
          f" · разница {db(m_rms) - db(r_rms):+.2f} дБ")
    print(f"[уровень] пик:  эталон {db(r_peak):7.2f} дБ · плагин {db(m_peak):7.2f} дБ"
          f" · разница {db(m_peak) - db(r_peak):+.2f} дБ")

    print()
    print("[спектр] энергия по полосам, дБ:")
    rb = dft_bands(ref, rate_a, BANDS)
    mb = dft_bands(mine, rate_a, BANDS)
    for name, a, b in zip(BAND_NAMES, rb, mb):
        print(f"    {name:>12}: эталон {db(a):7.2f} · плагин {db(b):7.2f} · разница {db(b) - db(a):+7.2f}")

    print()
    ro, mo = onsets(ref, rate_a), onsets(mine, rate_a)
    print(f"[удары] эталон {len(ro)}, плагин {len(mo)}")
    pairs = min(len(ro), len(mo))
    if pairs:
        deltas = [abs(mo[i] - ro[i]) * 1000.0 for i in range(pairs)]
        print(f"[удары] расхождение по времени: среднее {sum(deltas)/len(deltas):.2f} мс,"
              f" худшее {max(deltas):.2f} мс")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
