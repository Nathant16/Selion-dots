#!/usr/bin/env python3
"""Recursive wallpaper indexer wrapping `serpantinum-core wallpaper index`."""

import fcntl
import hashlib
import json
import os
import shutil
import subprocess
import sys
import time
import urllib.parse

try:
    from PIL import Image
    HAS_PIL = True
except ImportError:
    HAS_PIL = False

IMG_EXTS = {".jpg", ".jpeg", ".png", ".webp", ".gif", ".bmp"}
VID_EXTS = {".mp4", ".mkv", ".mov", ".webm"}


def get_hash(text: str) -> str:
    return hashlib.sha256(text.encode("utf-8")).hexdigest()[:16]


def get_color_bucket(hex_str: str) -> str:
    if not hex_str:
        return "Monochrome"
    hex_str = str(hex_str).strip().lstrip("#")[:6]
    if len(hex_str) != 6:
        return "Monochrome"
    try:
        r = int(hex_str[0:2], 16) / 255.0
        g = int(hex_str[2:4], 16) / 255.0
        b = int(hex_str[4:6], 16) / 255.0
    except ValueError:
        return "Monochrome"

    mx, mn = max(r, g, b), min(r, g, b)
    d = mx - mn
    if mx == mn:
        h = 0.0
    elif mx == r:
        h = ((g - b) / d + (6.0 if g < b else 0.0)) * 60.0
    elif mx == g:
        h = ((b - r) / d + 2.0) * 60.0
    else:
        h = ((r - g) / d + 4.0) * 60.0
    s = 0.0 if mx == 0 else d / mx
    v = mx

    if s < 0.05 or v < 0.08:
        return "Monochrome"
    if h >= 345 or h < 15:
        return "Red"
    if h < 45:
        return "Orange"
    if h < 75:
        return "Yellow"
    if h < 165:
        return "Green"
    if h < 260:
        return "Blue"
    if h < 315:
        return "Purple"
    if h < 345:
        return "Pink"
    return "Monochrome"


def fallback_extract_color(filepath: str) -> str:
    if HAS_PIL:
        try:
            with Image.open(filepath) as im:
                im = im.convert("RGB").resize((1, 1), Image.Resampling.BOX)
                r, g, b = im.getpixel((0, 0))
                return f"#{r:02x}{g:02x}{b:02x}"
        except Exception:
            pass
    if shutil.which("magick"):
        try:
            out = subprocess.check_output(
                ["magick", f"{filepath}[0]", "-resize", "1x1!", "-format", "%[hex:p{0,0}]", "info:-"],
                stderr=subprocess.DEVNULL,
                timeout=5,
            ).decode("utf-8").strip()
            if len(out) >= 6:
                return f"#{out[:6]}"
        except Exception:
            pass
    return "#808080"


def fallback_video_poster(video_path: str, poster_path: str) -> bool:
    if os.path.exists(poster_path) and os.path.getsize(poster_path) > 1024:
        return True
    os.makedirs(os.path.dirname(poster_path), exist_ok=True)
    tmp_poster = f"{poster_path}.tmp.jpg"
    for seek in ("00:00:01", "00:00:00.5", None):
        cmd = ["ffmpeg", "-y", "-hide_banner", "-loglevel", "error"]
        if seek:
            cmd += ["-ss", seek]
        cmd += ["-i", video_path, "-vframes", "1", "-vf", "scale=960:-2:force_original_aspect_ratio=decrease", "-q:v", "2", tmp_poster]
        try:
            subprocess.run(cmd, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, check=True, timeout=8)
            if os.path.exists(tmp_poster) and os.path.getsize(tmp_poster) > 512:
                os.replace(tmp_poster, poster_path)
                return True
        except Exception:
            pass
    if os.path.exists(tmp_poster):
        try:
            os.remove(tmp_poster)
        except OSError:
            pass
    return False


def index_subdir_with_core(subdir: str, cache_dir: str, run_dir: str) -> list:
    if not shutil.which("serpantinum-core"):
        return None
    sub_hash = get_hash(os.path.abspath(subdir))
    sub_cache = os.path.join(cache_dir, "subdirs", sub_hash)
    os.makedirs(sub_cache, exist_ok=True)
    try:
        res = subprocess.run(
            ["serpantinum-core", "wallpaper", "index", subdir, sub_cache, run_dir],
            stdout=subprocess.PIPE,
            stderr=subprocess.DEVNULL,
            text=True,
            timeout=60,
        )
        if res.returncode == 0 and res.stdout.strip():
            parsed = json.loads(res.stdout)
            if isinstance(parsed, dict) and isinstance(parsed.get("items"), list):
                return parsed["items"]
    except Exception:
        pass
    return None


def index_subdir_fallback(subdir: str, cache_dir: str) -> list:
    sub_hash = get_hash(os.path.abspath(subdir))
    per_dir = os.path.join(cache_dir, "dirs", sub_hash)
    poster_dir = os.path.join(per_dir, "posters")
    idx_file = os.path.join(per_dir, "fallback_index.json")
    os.makedirs(poster_dir, exist_ok=True)

    prev = {}
    if os.path.isfile(idx_file):
        try:
            with open(idx_file, "r", encoding="utf-8") as fp:
                for it in json.load(fp).get("items", []):
                    if it.get("fileName"):
                        prev[it["fileName"]] = it
        except Exception:
            prev = {}

    items = []
    try:
        entries = list(os.scandir(subdir))
    except OSError:
        entries = []

    for entry in entries:
        try:
            if not entry.is_file():
                continue
            ext = os.path.splitext(entry.name)[1].lower()
            if ext not in IMG_EXTS and ext not in VID_EXTS:
                continue
            st = entry.stat()
            mtime, size = int(st.st_mtime), int(st.st_size)
        except OSError:
            continue

        cached = prev.get(entry.name)
        is_vid = ext in VID_EXTS
        fpath = os.path.abspath(entry.path)
        if cached and cached.get("mtime") == mtime and cached.get("size") == size:
            if not is_vid or (cached.get("posterPath") and os.path.isfile(cached["posterPath"])):
                items.append(cached)
                continue

        if is_vid:
            poster_path = os.path.join(poster_dir, f"{get_hash(fpath)}.jpg")
            fallback_video_poster(fpath, poster_path)
            hx = fallback_extract_color(poster_path) if os.path.isfile(poster_path) else "#808080"
            items.append({
                "fileName": entry.name,
                "filePath": fpath,
                "fileUrl": f"file://{fpath}",
                "isVideo": True,
                "posterPath": poster_path if os.path.isfile(poster_path) else "",
                "posterUrl": f"file://{poster_path}" if os.path.isfile(poster_path) else "",
                "hex": hx,
                "bucket": "Video",
                "mtime": mtime,
                "size": size,
            })
        else:
            hx = fallback_extract_color(fpath)
            items.append({
                "fileName": entry.name,
                "filePath": fpath,
                "fileUrl": f"file://{fpath}",
                "isVideo": False,
                "posterPath": "",
                "posterUrl": "",
                "hex": hx,
                "bucket": get_color_bucket(hx),
                "mtime": mtime,
                "size": size,
            })

    tmp = f"{idx_file}.tmp"
    try:
        with open(tmp, "w", encoding="utf-8") as fp:
            json.dump({"items": items}, fp)
        os.replace(tmp, idx_file)
    except OSError:
        pass
    return items


def collect_media_dirs(src_abs: str, show_selion: bool) -> list:
    if not os.path.isdir(src_abs):
        return []
    if not show_selion and os.path.basename(src_abs) == "Selion":
        return []

    media_dirs = []
    seen_real_dirs = set()
    for root, subdirs, files in os.walk(src_abs, followlinks=True):
        real_root = os.path.realpath(root)
        if real_root in seen_real_dirs:
            subdirs[:] = []
            continue
        seen_real_dirs.add(real_root)

        rel_root = os.path.relpath(root, src_abs)
        subdirs[:] = sorted(
            d for d in subdirs
            if not d.startswith(".")
            and (show_selion or not (rel_root == "." and d == "Selion"))
        )

        if any(os.path.splitext(f)[1].lower() in (IMG_EXTS | VID_EXTS) for f in files if not f.startswith(".")):
            media_dirs.append(os.path.abspath(root))
    return media_dirs


def build_recursive_index(src_abs: str, cache_dir: str, run_dir: str, show_selion: bool) -> dict:
    media_dirs = collect_media_dirs(src_abs, show_selion)
    merged = {}
    seen_real_files = set()

    for subdir in media_dirs:
        sub_items = index_subdir_with_core(subdir, cache_dir, run_dir)
        if sub_items is None:
            sub_items = index_subdir_fallback(subdir, cache_dir)

        for it in sub_items:
            fpath = it.get("filePath") or (os.path.join(subdir, it.get("fileName", "")))
            if not fpath or not os.path.isfile(fpath):
                continue
            real_f = os.path.realpath(fpath)
            if real_f in seen_real_files:
                continue
            seen_real_files.add(real_f)

            rel_name = os.path.relpath(fpath, src_abs).replace(os.sep, "/")
            if not rel_name or rel_name.startswith("../"):
                rel_name = os.path.basename(fpath)

            try:
                mtime = it.get("mtime") or int(os.stat(fpath).st_mtime)
            except OSError:
                mtime = 0

            normalized = dict(it)
            normalized["fileName"] = rel_name
            normalized["filePath"] = fpath
            normalized["fileUrl"] = f"file://{fpath}"
            normalized["mtime"] = mtime
            merged[rel_name] = normalized

    items = [merged[k] for k in sorted(merged.keys())]
    out = {
        "srcDir": src_abs,
        "showSelion": show_selion,
        "dirHash": get_hash(src_abs),
        "updatedAt": int(time.time()),
        "items": items,
    }

    current_index = os.path.join(cache_dir, "current_index.json")
    tmp_out = f"{current_index}.tmp.{os.getpid()}"
    try:
        with open(tmp_out, "w", encoding="utf-8") as fp:
            json.dump(out, fp)
        os.replace(tmp_out, current_index)
    except OSError:
        pass
    return out


def main():
    if len(sys.argv) < 2:
        return
    src_dir = sys.argv[1]
    if src_dir.startswith("file://"):
        src_dir = urllib.parse.unquote(src_dir[7:])
    src_abs = os.path.abspath(os.path.expanduser(src_dir))

    cache_dir = sys.argv[2] if len(sys.argv) > 2 else "/tmp"
    run_dir = sys.argv[3] if len(sys.argv) > 3 else cache_dir
    show_selion = True
    if len(sys.argv) > 4:
        show_selion = sys.argv[4] not in ("0", "false", "False", "no")

    os.makedirs(cache_dir, exist_ok=True)
    os.makedirs(run_dir, exist_ok=True)

    lock_path = os.path.join(run_dir, f"recursive_indexer_{get_hash(src_abs)}.lock")
    with open(lock_path, "w") as lock_fd:
        fcntl.flock(lock_fd, fcntl.LOCK_EX)
        data = build_recursive_index(src_abs, cache_dir, run_dir, show_selion)
        sys.stdout.write(json.dumps(data))
        sys.stdout.flush()


if __name__ == "__main__":
    main()

