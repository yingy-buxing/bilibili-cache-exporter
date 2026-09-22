#!/usr/bin/env bash
set -euo pipefail

project_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
app_path="$project_dir/dist/哔哩哔哩缓存导出.app"
ffmpeg_path="${FFMPEG_PATH:-}"

if [[ "$(uname -s)" != "Darwin" ]]; then
  echo "此工具需要在 macOS 上构建。" >&2
  exit 1
fi

if [[ -z "$ffmpeg_path" ]]; then
  ffmpeg_path="$(command -v ffmpeg || true)"
fi
if [[ -z "$ffmpeg_path" && -x "$HOME/Library/Application Support/bilibili/ffmpeg/ffmpeg" ]]; then
  ffmpeg_path="$HOME/Library/Application Support/bilibili/ffmpeg/ffmpeg"
fi
if [[ -z "$ffmpeg_path" || ! -x "$ffmpeg_path" ]]; then
  echo "没有找到 FFmpeg。请设置 FFMPEG_PATH 为本机 ffmpeg 可执行文件的绝对路径。" >&2
  exit 1
fi
if [[ -e "$app_path" ]]; then
  echo "目标应用已存在：$app_path" >&2
  echo "请先把旧应用移到其他位置，再重新运行构建脚本。" >&2
  exit 1
fi

staging_root="$(mktemp -d "${TMPDIR:-/tmp}/bili-cache-export.XXXXXX")"
staged_app="$staging_root/哔哩哔哩缓存导出.app"
mkdir -p "$staged_app/Contents/MacOS" "$staged_app/Contents/Resources"
MACOSX_DEPLOYMENT_TARGET=13.0 swiftc -swift-version 5 -O -framework Cocoa \
  -o "$staged_app/Contents/MacOS/BiliVideoTool" \
  "$project_dir/Sources/BiliVideoTool.swift"
cp "$project_dir/Info.plist" "$staged_app/Contents/Info.plist"
cp "$ffmpeg_path" "$staged_app/Contents/Resources/ffmpeg"
chmod 755 "$staged_app/Contents/MacOS/BiliVideoTool" "$staged_app/Contents/Resources/ffmpeg"
plutil -lint "$staged_app/Contents/Info.plist"
xattr -cr "$staged_app"
codesign --force --deep --sign - "$staged_app"
codesign --verify --deep --strict "$staged_app"
mkdir -p "$project_dir/dist"
mv "$staged_app" "$app_path"
rmdir "$staging_root"

echo "构建完成：$app_path"
