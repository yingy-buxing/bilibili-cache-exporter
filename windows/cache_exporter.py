"""Read Bilibili desktop cache folders and remux their media streams."""

from __future__ import annotations

import json
import os
import re
import shutil
import subprocess
import sys
import tempfile
from dataclasses import dataclass
from pathlib import Path


@dataclass(frozen=True)
class CacheItem:
    title: str
    folder: Path
    video: Path
    audio: Path | None
    cover: Path | None
    duration: int = 0
    resolution: str = "未知"


def default_cache_folders() -> list[Path]:
    """Try common locations; the client's configured download folder remains authoritative."""
    home = Path.home()
    candidates = [
        home / "Videos" / "bilibili",
        home / "Downloads" / "bilibili",
        Path(os.environ.get("APPDATA", home / "AppData" / "Roaming")) / "bilibili" / "download",
        Path(os.environ.get("LOCALAPPDATA", home / "AppData" / "Local")) / "bilibili" / "download",
    ]
    return [folder for folder in dict.fromkeys(candidates) if folder.is_dir()]


def _json(path: Path) -> dict:
    try:
        value = json.loads(path.read_text(encoding="utf-8-sig"))
        return value if isinstance(value, dict) else {}
    except (OSError, UnicodeError, json.JSONDecodeError):
        return {}


def _prefix(path: Path) -> str:
    return re.sub(r"-\d{5,6}$", "", path.stem)


def item_from_folder(folder: Path) -> CacheItem | None:
    try:
        streams = [p for p in folder.iterdir() if p.is_file() and p.suffix.lower() == ".m4s"]
    except OSError:
        return None
    audio_files = [p for p in streams if p.stem.lower() == "audio" or p.stem.endswith("-30280")]
    video_files = [p for p in streams if p not in audio_files]
    if not video_files:
        return None
    try:
        video = max(video_files, key=lambda p: p.stat().st_size)
    except OSError:
        return None
    matching_audio = [p for p in audio_files if _prefix(p) == _prefix(video)]
    audio = (matching_audio or audio_files or [None])[0]
    info = _json(folder / "videoInfo.json")
    title = info.get("title") or info.get("groupTitle") or folder.name
    if not isinstance(title, str) or not title.strip():
        title = folder.name
    try:
        duration = max(0, int(float(info.get("duration") or 0)))
    except (TypeError, ValueError):
        duration = 0
    playurl = _json(folder / ".playurl")
    data = playurl.get("data")
    dash = data.get("dash") if isinstance(data, dict) else None
    videos = dash.get("video", []) if isinstance(dash, dict) else []
    resolution = "未知"
    if isinstance(videos, list) and videos and isinstance(videos[0], dict):
        width, height = videos[0].get("width"), videos[0].get("height")
        if isinstance(width, int) and isinstance(height, int) and width > 0 and height > 0:
            resolution = f"{width}×{height}"
    cover = next((folder / name for name in ("image.jpg", "image.png", "group.jpg", "group.png") if (folder / name).is_file()), None)
    return CacheItem(title.strip(), folder, video, audio, cover, duration, resolution)


def scan_folder(root: Path, max_depth: int = 4) -> list[CacheItem]:
    if not root.is_dir():
        return []
    results: list[CacheItem] = []
    for current, dirs, _ in os.walk(root):
        folder = Path(current)
        depth = len(folder.relative_to(root).parts)
        if depth > max_depth:
            dirs[:] = []
            continue
        item = item_from_folder(folder)
        if item:
            results.append(item)
            dirs[:] = []
        elif depth == max_depth:
            dirs[:] = []
    return sorted(results, key=lambda item: item.title.casefold())


def item_from_file(path: Path) -> CacheItem | None:
    if not path.is_file() or path.suffix.lower() != ".m4s":
        return None
    item = item_from_folder(path.parent)
    if path.stem.lower() == "audio" or path.stem.endswith("-30280"):
        return item
    if item:
        audio = item.audio if item.audio and _prefix(item.audio) == _prefix(path) else None
        return CacheItem(item.title, item.folder, path, audio, item.cover, item.duration, item.resolution)
    return CacheItem(path.stem, path.parent, path, None, None)


def safe_filename(title: str) -> str:
    clean = re.sub(r'[<>:"/\\|?*\x00-\x1f]', "-", title).strip(" .")[:80].rstrip(" .")
    return clean or "哔哩哔哩视频"


def find_ffmpeg() -> Path | None:
    candidates = [os.environ.get("FFMPEG_PATH"), Path(sys.executable).parent / "ffmpeg.exe", Path(__file__).resolve().parent / "ffmpeg.exe", shutil.which("ffmpeg")]
    return next((Path(value) for value in candidates if value and Path(value).is_file()), None)


def make_readable_copy(source: Path, destination: Path) -> None:
    with source.open("rb") as input_file, destination.open("wb") as output_file:
        header = input_file.read(9)
        if header != b"000000000":
            output_file.write(header)
        shutil.copyfileobj(input_file, output_file, length=4 * 1024 * 1024)


def export(item: CacheItem, mode: str, output: Path, ffmpeg: Path | None = None) -> None:
    if mode not in ("video", "audio", "combined"):
        raise ValueError("未知导出模式")
    if mode != "video" and not item.audio:
        raise ValueError("缓存中缺少音频文件")
    executable = ffmpeg or find_ffmpeg()
    if not executable:
        raise FileNotFoundError("找不到 ffmpeg.exe。请将它放在程序旁边，或加入 PATH。")
    output = output.resolve()
    with tempfile.TemporaryDirectory(prefix="bili-export-") as temporary:
        temp = Path(temporary)
        video = temp / "video.m4s"
        audio = temp / "audio.m4s"
        if mode != "audio":
            make_readable_copy(item.video, video)
        if mode != "video":
            make_readable_copy(item.audio, audio)
        base = [str(executable), "-hide_banner", "-loglevel", "error", "-y"]
        if mode == "video":
            arguments = ["-i", str(video), "-map", "0:v:0", "-an", "-c:v", "copy", "-movflags", "+faststart"]
        elif mode == "audio":
            arguments = ["-i", str(audio), "-map", "0:a:0", "-vn", "-c:a", "copy"]
        else:
            arguments = ["-i", str(video), "-i", str(audio), "-map", "0:v:0", "-map", "1:a:0", "-c", "copy", "-movflags", "+faststart"]
        partial = output.with_name(output.stem + ".partial" + output.suffix)
        try:
            result = subprocess.run(base + arguments + [str(partial)], capture_output=True, text=True, errors="replace", creationflags=getattr(subprocess, "CREATE_NO_WINDOW", 0))
            if result.returncode:
                raise RuntimeError(result.stderr.strip() or f"FFmpeg 退出代码 {result.returncode}")
            partial.replace(output)
        finally:
            partial.unlink(missing_ok=True)
