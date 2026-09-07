# -*- coding: utf-8 -*-
"""Сверка одного узла: свежая запись Булки против моего рендера.

    python tools/ab.py "<код Strudel>" [секунд]

Берёт САМУЮ СВЕЖУЮ запись из Булки, рендерит тот же код движком плагина и
печатает разницу по полосам после снятия разницы общего уровня. Так проверяется
один узел за раз — зал, эхо, сжатие, — а не «трек вообще».
"""
import glob
import io
import os
import subprocess
import sys
import wave

import numpy as np

GODOT = "D:/Programs/Godot/Godot_v4.7.1-stable_win64_console.exe"
PLUGIN = "D:/Projects/TEMP/godot-strudel"
SAMPLES = "D:/Projects/TEMP/aquarelle/audio/strudel"
RECS = "F:/AI/Bulka-app/recordings"


def newest_recording():
    files = glob.glob(RECS + "/*.wav") + glob.glob(RECS + "/*/*.wav")
    return max(files, key=os.path.getmtime)


def read(path):
    w = wave.open(path)
    n = w.getnframes()
    ch = w.getnchannels()
    d = np.frombuffer(w.readframes(n), dtype="<i2").astype(float) / 32768.0
    return d.reshape(-1, ch).mean(axis=1) if ch == 2 else d


def onset(x):
    thr = np.abs(x).max() * 0.05
    return int(np.argmax(np.abs(x) > thr))


def main():
    code = sys.argv[1]
    seconds = float(sys.argv[2]) if len(sys.argv) > 2 else 6.0

    src = PLUGIN + "/ab_tmp.js"
    io.open(src, "w", encoding="utf-8").write(code)
    out = PLUGIN + "/ab_tmp.wav"
    subprocess.run([GODOT, "--headless", "--path", PLUGIN, "--script",
                    "res://tools/render_wav.gd", "--",
                    "--file=" + src, "--samples=" + SAMPLES,
                    "--out=" + out, "--seconds=%g" % seconds],
                   capture_output=True)

    a = read(newest_recording())
    b = read(out)
    oa, ob = onset(a), onset(b)
    n = min(len(a) - oa, len(b) - ob, int(48000 * (seconds - 1)))
    a = a[oa:oa + n]
    b = b[ob:ob + n]

    ra = np.sqrt((a * a).mean())
    rb = np.sqrt((b * b).mean())
    print("Булка:  пик %.4f  СКЗ %.5f" % (np.abs(a).max(), ra))
    print("плагин: пик %.4f  СКЗ %.5f" % (np.abs(b).max(), rb))
    print("уровень: %+.2f дБ" % (20 * np.log10(max(rb, 1e-12) / max(ra, 1e-12))))

    k = ra / max(rb, 1e-12)
    sa = np.abs(np.fft.rfft(a * np.hanning(n)))
    sb = np.abs(np.fft.rfft(b * np.hanning(n))) * k
    fr = np.fft.rfftfreq(n, 1 / 48000)
    print()
    print("%-14s %8s %8s %8s" % ("полоса", "Булка", "плагин", "разница"))
    worst = 0.0
    for lo, hi in [(80, 300), (300, 800), (800, 2000), (2000, 5000), (5000, 12000)]:
        m = (fr >= lo) & (fr < hi)
        da = 20 * np.log10(max(np.sqrt((sa[m] ** 2).mean()), 1e-12))
        db = 20 * np.log10(max(np.sqrt((sb[m] ** 2).mean()), 1e-12))
        worst = max(worst, abs(db - da))
        print("%5d-%-7d %8.1f %8.1f %8.2f" % (lo, hi, da, db, db - da))
    print("\nхудшая полоса: %.2f дБ" % worst)


if __name__ == "__main__":
    main()
