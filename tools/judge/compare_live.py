"""Сверка ЖИВОЙ записи Булки со звуком плагина.

    python tools/judge/compare_live.py запись_булки.wav рендер_плагина.wav

Зачем отдельно от `compare_audio.py`: тот считает офлайн-рендер, который
начинается ровно с нуля и снят на том же мастере. Живая запись устроена иначе,
и на ней он врёт двумя способами сразу:

🔴 РАЗГОН. Запись включается ДО того, как пойдёт звук, — первые доли секунды
   тишина. Полосы там считались по первым 32768 отсчётам, то есть по этой самой
   тишине: печаталось −240 дБ при живом СКЗ −52.

🔴 ГРОМКОСТЬ МАСТЕРА. Уровень записи задаёт ползунок в окне Булки, а не
   паттерн. Постоянный сдвиг во всех полосах — это ползунок, и сравнивать надо
   ПОСЛЕ его вычитания: важно, одинаково ли лежит звук по полосам и во времени,
   а не насколько громко его писали.

Поэтому здесь: сначала выравнивание по огибающей (взаимная корреляция),
потом снятие постоянной громкости, и только затем спектр, ход уровня и удары.
Печатается и сам сдвиг — если он большой, значит разошлись не громкости, а темп.
"""

import sys
import wave
from pathlib import Path

import numpy as np

if hasattr(sys.stdout, "reconfigure"):
    sys.stdout.reconfigure(encoding="utf-8", errors="replace")

BANDS = [(40, 120), (120, 300), (300, 800), (800, 2000), (2000, 5000), (5000, 12000)]
HOP = 0.010  # шаг огибающей, с


def read_wav(path: Path):
    with wave.open(str(path), "rb") as w:
        rate, ch, width = w.getframerate(), w.getnchannels(), w.getsampwidth()
        raw = w.readframes(w.getnframes())
    if width != 2:
        raise SystemExit("жду 16-битный WAV: %s" % path)
    x = np.frombuffer(raw, dtype="<i2").astype(np.float64) / 32768.0
    if ch > 1:
        x = x.reshape(-1, ch).mean(axis=1)
    return x, rate


def db(x):
    return 20.0 * np.log10(np.maximum(x, 1e-12))


def envelope(x, rate):
    n = int(rate * HOP)
    m = len(x) // n
    return np.sqrt((x[: m * n].reshape(m, n) ** 2).mean(axis=1))


def align(a, b, rate):
    """Где в рендере плагина лежит записанный кусок. → (сдвиг в шагах, согласие).

    🔴 Сводить надо по ЛОГАРИФМУ огибающей. У перкуссии несколько ударов
    забирают почти всю энергию, и линейная огибающая сводится по ним одним —
    совпадение выходит случайным. В логарифме слышно всю ткань, и пик выходит
    острый: у sampleDemo он шириной в три шага по 10 мс.

    🔴 Рендер плагина берётся ДЛИННЕЕ записи: живая запись включается через
    несколько секунд после начала партии, и куда именно она попала — заранее
    неизвестно. Окно ищется по всему рендеру, а не в узкой полосе вокруг нуля.
    """
    ea, eb = np.log10(envelope(a, rate) + 1e-6), np.log10(envelope(b, rate) + 1e-6)
    ea = ea - ea.mean()
    win = len(ea)
    if len(eb) <= win:
        # рендер не длиннее записи — ищем сдвиг в обе стороны по общей части
        span = min(len(eb) // 2, int(6.0 / HOP))
        best, best_lag = -2.0, 0
        for lag in range(-span, span + 1):
            u, v = (ea[lag:], eb[: len(eb) - lag]) if lag >= 0 else (ea[: len(ea) + lag], eb[-lag:])
            k = min(len(u), len(v))
            if k < span:
                continue
            uu, vv = u[:k] - u[:k].mean(), v[:k] - v[:k].mean()
            c = float(np.dot(uu, vv) / (np.linalg.norm(uu) * np.linalg.norm(vv) + 1e-18))
            if c > best:
                best, best_lag = c, lag
        return best_lag, best
    best, best_lag = -2.0, 0
    for lag in range(0, len(eb) - win):
        v = eb[lag : lag + win]
        v = v - v.mean()
        c = float(np.dot(ea, v) / (np.linalg.norm(ea) * np.linalg.norm(v) + 1e-18))
        if c > best:
            best, best_lag = c, lag
    return -best_lag, best


def bands_db(x, rate):
    win = 1 << 14
    step = win
    acc = np.zeros(len(BANDS))
    frames = 0
    for start in range(0, len(x) - win, step):
        seg = x[start : start + win] * np.hanning(win)
        spec = np.abs(np.fft.rfft(seg)) ** 2
        freqs = np.fft.rfftfreq(win, 1.0 / rate)
        for i, (lo, hi) in enumerate(BANDS):
            sel = (freqs >= lo) & (freqs < hi)
            acc[i] += spec[sel].sum()
        frames += 1
    if frames == 0:
        return np.full(len(BANDS), -240.0)
    return db(np.sqrt(acc / frames / win))


def onsets(x, rate, rel=0.25):
    """Моменты ударов по огибающей, порог ОТНОСИТЕЛЬНЫЙ — иначе тихая запись
    не даёт ни одного удара, а громкая даёт лишние."""
    e = envelope(x, rate)
    if e.max() <= 0:
        return np.array([])
    e = e / e.max()
    rise = np.diff(e, prepend=e[0])
    hit = (rise > rel * rise.max()) & (e > 0.08)
    idx = np.flatnonzero(hit)
    keep, last = [], -99
    for i in idx:
        if i - last > 4:
            keep.append(i)
            last = i
    return np.array(keep) * HOP


def main():
    if len(sys.argv) < 3:
        raise SystemExit(__doc__)
    ref_path, our_path = Path(sys.argv[1]), Path(sys.argv[2])
    a, ra = read_wav(ref_path)
    b, rb = read_wav(our_path)
    if ra != rb:
        raise SystemExit("разные частоты: %d и %d" % (ra, rb))
    print("[звук] Булка  %s: %.2f с" % (ref_path.name, len(a) / ra))
    print("[звук] плагин %s: %.2f с" % (our_path.name, len(b) / rb))

    lag, agree = align(a, b, ra)
    print("\n[сведение] сдвиг %+.0f мс, согласие огибающих %.3f" % (lag * HOP * 1000, agree))
    if lag > 0:
        a = a[int(lag * HOP * ra):]
    elif lag < 0:
        b = b[int(-lag * HOP * rb):]
    k = min(len(a), len(b))
    a, b = a[:k], b[:k]
    print("[сведение] сверяется %.2f с" % (k / ra))

    ra_rms, rb_rms = np.sqrt((a ** 2).mean()), np.sqrt((b ** 2).mean())
    gain = db(rb_rms) - db(ra_rms)
    print("\n[уровень] СКЗ: Булка %7.2f дБ · плагин %7.2f дБ · мастер Булки ниже на %+.2f дБ"
          % (db(ra_rms), db(rb_rms), gain))
    a = a * (rb_rms / max(ra_rms, 1e-12))  # снимаем громкость мастера

    print("\n[спектр] после снятия громкости мастера, дБ:")
    ba, bb = bands_db(a, ra), bands_db(b, rb)
    worst = 0.0
    for (lo, hi), x, y in zip(BANDS, ba, bb):
        d = y - x
        worst = max(worst, abs(d))
        print("   %5d-%-6d Булка %8.2f · плагин %8.2f · разница %+7.2f" % (lo, hi, x, y, d))
    print("   худшая полоса: %+.2f дБ" % worst)

    ea, eb = envelope(a, ra), envelope(b, rb)
    m = min(len(ea), len(eb))
    ea, eb = ea[:m], eb[:m]
    corr = float(np.corrcoef(ea, eb)[0, 1])
    print("\n[ход уровня] согласие огибающих %.3f" % corr)

    oa, ob = onsets(a, ra), onsets(b, rb)
    print("[удары] Булка %d, плагин %d" % (len(oa), len(ob)))
    if len(oa) and len(ob):
        diffs = [abs(t - ob[np.argmin(np.abs(ob - t))]) for t in oa]
        print("[удары] расхождение по времени: среднее %.1f мс, худшее %.1f мс"
              % (1000 * float(np.mean(diffs)), 1000 * float(np.max(diffs))))


main()
