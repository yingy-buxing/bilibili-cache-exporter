import json
import subprocess
import tempfile
import unittest
from pathlib import Path

import sys
sys.path.insert(0, str(Path(__file__).resolve().parents[1]))

from cache_exporter import export, find_ffmpeg, make_readable_copy, safe_filename, scan_folder


class CacheExporterTests(unittest.TestCase):
    def test_scan_nested_cache_and_metadata(self):
        with tempfile.TemporaryDirectory() as directory:
            folder = Path(directory) / "123" / "456"
            folder.mkdir(parents=True)
            (folder / "123-30080.m4s").write_bytes(b"000000000video")
            (folder / "123-30280.m4s").write_bytes(b"000000000audio")
            (folder / "videoInfo.json").write_text(json.dumps({"title": "测试视频", "duration": 65}), encoding="utf-8")
            (folder / ".playurl").write_text(json.dumps({"data": {"dash": {"video": [{"width": 1920, "height": 1080}]}}}), encoding="utf-8")
            items = scan_folder(Path(directory))
            self.assertEqual(len(items), 1)
            self.assertEqual((items[0].title, items[0].duration, items[0].resolution), ("测试视频", 65, "1920×1080"))
            self.assertEqual(items[0].audio.name, "123-30280.m4s")

    def test_header_and_filename(self):
        with tempfile.TemporaryDirectory() as directory:
            source = Path(directory) / "source.m4s"
            destination = Path(directory) / "copy.m4s"
            source.write_bytes(b"000000000payload")
            make_readable_copy(source, destination)
            self.assertEqual(destination.read_bytes(), b"payload")
            source.write_bytes(b"plain-data")
            make_readable_copy(source, destination)
            self.assertEqual(destination.read_bytes(), b"plain-data")
        self.assertEqual(safe_filename(' A:B? '), "A-B-")

    @unittest.skipUnless(find_ffmpeg(), "FFmpeg is unavailable")
    def test_three_export_modes(self):
        ffmpeg = find_ffmpeg()
        with tempfile.TemporaryDirectory() as directory:
            folder = Path(directory) / "cache"
            folder.mkdir()
            video = folder / "1-30080.m4s"
            audio = folder / "1-30280.m4s"
            subprocess.run([str(ffmpeg), "-loglevel", "error", "-f", "lavfi", "-i", "color=c=blue:s=160x90:r=2:d=1", "-an", "-c:v", "mpeg4", "-f", "mp4", str(video)], check=True)
            subprocess.run([str(ffmpeg), "-loglevel", "error", "-f", "lavfi", "-i", "sine=frequency=440:duration=1", "-vn", "-c:a", "aac", "-f", "mp4", str(audio)], check=True)
            video.write_bytes(b"000000000" + video.read_bytes())
            audio.write_bytes(b"000000000" + audio.read_bytes())
            item = scan_folder(Path(directory))[0]
            for mode, suffix in (("video", ".mp4"), ("audio", ".m4a"), ("combined", ".mp4")):
                output = Path(directory) / (mode + suffix)
                export(item, mode, output, ffmpeg)
                self.assertTrue(output.is_file() and output.stat().st_size > 0)
                probe = subprocess.run([str(ffmpeg), "-hide_banner", "-i", str(output)], capture_output=True, text=True)
                self.assertIn("Video:", probe.stderr) if mode != "audio" else self.assertNotIn("Video:", probe.stderr)
                self.assertIn("Audio:", probe.stderr) if mode != "video" else self.assertNotIn("Audio:", probe.stderr)


if __name__ == "__main__":
    unittest.main()
