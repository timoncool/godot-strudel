"""Перевод пака сэмплов в WAV.

Зачем: Godot умеет ЗАГРУЗИТЬ ogg и mp3, но не отдаёт из них PCM в GDScript,
а он нужен для пер-голосовой цепи эффектов. Поэтому пак переводится один раз
заранее, а не на каждом запуске.

    python tools/convert_samples.py <папка-с-паком> [--out=<куда>] [--rate=44100]

Рядом с звуками переносятся и карты сэмплов (*.json) — пути в них не меняются,
меняются только расширения файлов.

Нужен ffmpeg в PATH.
"""

import argparse
import json
import shutil
import subprocess
import sys
from pathlib import Path

CONVERTIBLE = {".ogg", ".mp3", ".flac", ".m4a", ".aac", ".opus", ".aiff", ".aif"}


def have_ffmpeg() -> bool:
    return shutil.which("ffmpeg") is not None


def convert(src: Path, dst: Path, rate: int) -> bool:
    dst.parent.mkdir(parents=True, exist_ok=True)
    result = subprocess.run(
        ["ffmpeg", "-y", "-loglevel", "error", "-i", str(src),
         "-ar", str(rate), "-acodec", "pcm_s16le", str(dst)],
        capture_output=True,
    )
    if result.returncode != 0:
        print(f"  !! {src.name}: {result.stderr.decode('utf-8', 'replace').strip()[:120]}")
        return False
    return True


def fix_map(src: Path, dst: Path) -> None:
    """Переписывает расширения в карте сэмплов, не трогая структуру."""
    try:
        data = json.loads(src.read_text(encoding="utf-8"))
    except Exception as exc:  # noqa: BLE001
        print(f"  !! карта {src.name} не разобралась: {exc}")
        shutil.copy2(src, dst)
        return

    def swap(value):
        if isinstance(value, str):
            p = Path(value)
            return str(p.with_suffix(".wav")).replace("\\", "/") if p.suffix.lower() in CONVERTIBLE else value
        if isinstance(value, list):
            return [swap(v) for v in value]
        if isinstance(value, dict):
            return {k: (v if k.startswith("_") else swap(v)) for k, v in value.items()}
        return value

    dst.parent.mkdir(parents=True, exist_ok=True)
    dst.write_text(json.dumps(swap(data), indent=2, ensure_ascii=False), encoding="utf-8")


def main() -> int:
    parser = argparse.ArgumentParser(description="Перевод пака сэмплов в WAV")
    parser.add_argument("folder", help="папка с паком")
    parser.add_argument("--out", default="", help="куда класть (по умолчанию рядом, с суффиксом -wav)")
    parser.add_argument("--rate", type=int, default=44100, help="частота дискретизации")
    args = parser.parse_args()

    src_root = Path(args.folder).resolve()
    if not src_root.is_dir():
        print(f"нет папки: {src_root}", file=sys.stderr)
        return 1
    dst_root = Path(args.out).resolve() if args.out else src_root.with_name(src_root.name + "-wav")

    if not have_ffmpeg():
        print("нужен ffmpeg в PATH: https://ffmpeg.org/download.html", file=sys.stderr)
        return 1

    converted = copied = maps = failed = 0
    for src in sorted(src_root.rglob("*")):
        if src.is_dir():
            continue
        rel = src.relative_to(src_root)
        suffix = src.suffix.lower()
        if suffix in CONVERTIBLE:
            if convert(src, dst_root / rel.with_suffix(".wav"), args.rate):
                converted += 1
            else:
                failed += 1
        elif suffix == ".json":
            fix_map(src, dst_root / rel)
            maps += 1
        elif suffix == ".wav":
            (dst_root / rel).parent.mkdir(parents=True, exist_ok=True)
            shutil.copy2(src, dst_root / rel)
            copied += 1

    print(f"переведено {converted}, скопировано {copied} WAV, карт {maps}, не вышло {failed}")
    print(f"готовый пак: {dst_root}")
    print("укажите эту папку в samples_path у StrudelPlayer")
    return 1 if failed else 0


if __name__ == "__main__":
    raise SystemExit(main())
