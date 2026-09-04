"""Делает маленький пак сэмплов для примера «свой банк».

Никаких чужих файлов в репозитории: звуки синтезируются здесь же, чтобы
пример работал сразу после клонирования и ничего не тянул из сети.

    python examples/02_own_samples/make_pack.py
"""

import json
import math
import random
import struct
import wave
from pathlib import Path

HERE = Path(__file__).resolve().parent
PACK = HERE / "pack"
RATE = 44100


def write_wav(path: Path, samples: list[float]) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    data = b"".join(struct.pack("<h", int(max(-1.0, min(1.0, s)) * 32000)) for s in samples)
    with wave.open(str(path), "wb") as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(RATE)
        w.writeframes(data)


def kick(length=0.35, start=110.0, end=45.0) -> list[float]:
    out = []
    n = int(RATE * length)
    phase = 0.0
    for i in range(n):
        t = i / n
        freq = end + (start - end) * math.exp(-6.0 * t)
        phase += freq / RATE
        env = math.exp(-5.0 * t)
        out.append(math.sin(2 * math.pi * phase) * env)
    return out


def snare(length=0.22) -> list[float]:
    out = []
    n = int(RATE * length)
    rnd = random.Random(7)
    phase = 0.0
    for i in range(n):
        t = i / n
        env = math.exp(-14.0 * t)
        phase += 190.0 / RATE
        tone = math.sin(2 * math.pi * phase) * 0.35
        noise = (rnd.random() * 2 - 1) * 0.65
        out.append((tone + noise) * env)
    return out


def hat(length=0.08, bright=1.0) -> list[float]:
    out = []
    n = int(RATE * length)
    rnd = random.Random(11)
    prev = 0.0
    for i in range(n):
        t = i / n
        env = math.exp(-38.0 * t)
        white = rnd.random() * 2 - 1
        # простой верхний срез, чтобы звучало как тарелочка
        high = white - prev
        prev = white
        out.append(high * env * bright)
    return out


def tone(midi: int, length=1.2) -> list[float]:
    """Нота для многосэмплированного инструмента."""
    out = []
    n = int(RATE * length)
    freq = 440.0 * 2 ** ((midi - 69) / 12)
    for i in range(n):
        t = i / n
        env = math.exp(-3.0 * t)
        v = 0.0
        for h, amp in ((1, 1.0), (2, 0.5), (3, 0.25), (4, 0.12)):
            v += math.sin(2 * math.pi * freq * h * i / RATE) * amp
        out.append(v / 1.9 * env)
    return out


def main() -> None:
    write_wav(PACK / "bd" / "bd.wav", kick())
    write_wav(PACK / "bd" / "bd_low.wav", kick(0.45, 90.0, 38.0))
    write_wav(PACK / "sd" / "sd.wav", snare())
    write_wav(PACK / "hh" / "hh.wav", hat())
    write_wav(PACK / "hh" / "hh_open.wav", hat(0.28, 0.8))

    # Многосэмплированный инструмент: три записанные высоты, между ними
    # плагин растягивает ближайшую — как это делает Strudel.
    for name, midi in (("c3", 48), ("g3", 55), ("c4", 60)):
        write_wav(PACK / "bell" / f"{name}.wav", tone(midi))

    sample_map = {
        "_base": "pack/",
        "bd": ["bd/bd.wav", "bd/bd_low.wav"],
        "sd": ["sd/sd.wav"],
        "hh": ["hh/hh.wav", "hh/hh_open.wav"],
        "bell": {"C3": "bell/c3.wav", "G3": "bell/g3.wav", "C4": "bell/c4.wav"},
    }
    (HERE / "mypack.json").write_text(
        json.dumps(sample_map, indent=2, ensure_ascii=False), encoding="utf-8"
    )

    files = sorted(p.relative_to(HERE).as_posix() for p in PACK.rglob("*.wav"))
    print(f"пак готов: {len(files)} звуков + карта mypack.json")
    for f in files:
        print("   ", f)


if __name__ == "__main__":
    main()
