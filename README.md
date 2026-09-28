# 哔哩哔哩缓存导出

一个读取哔哩哔哩桌面客户端离线缓存的本地工具，支持 macOS 和 Windows。以四列封面卡片显示视频，并按需导出：

| 选项 | 输出 | 内容 |
| --- | --- | --- |
| 仅视频画面 | `.mp4` | 无声视频 |
| 仅音频 | `.m4a` | AAC 音频 |
| 画面＋音频 | `.mp4` | 有声视频 |

卡片显示封面、标题、时长和分辨率。每次选择一个视频导出；原缓存不会被修改。

## macOS 构建

需要 macOS 13 或更新版本、Xcode 命令行工具，以及本机可执行的 FFmpeg。仓库不包含 FFmpeg 二进制文件，也不包含任何缓存视频。

```bash
git clone https://github.com/yingy-buxing/bilibili-cache-exporter.git
cd bilibili-cache-exporter
./build.sh
```

脚本先查找 `PATH` 中的 `ffmpeg`，随后尝试哔哩哔哩 Mac 客户端的本机路径。也可以明确指定：

```bash
FFMPEG_PATH="/你的/ffmpeg/绝对路径" ./build.sh
```

构建结果位于 `dist/哔哩哔哩缓存导出.app`，可将应用拖到桌面后双击打开。再次构建前，请先移走旧的 `dist/哔哩哔哩缓存导出.app`。

## Windows 使用与构建

Windows 10/11 上需要 Python 3.10 或更新版本，以及 `ffmpeg.exe`。可从 [FFmpeg 官网](https://ffmpeg.org/download.html) 获取 Windows 构建。将 `ffmpeg.exe` 放在程序或打包后的 EXE 同目录，或将它所在目录加入系统 `PATH`；也可以设置 `FFMPEG_PATH` 为完整文件路径。仓库不包含 FFmpeg 二进制文件。

下载仓库后，在 PowerShell 中运行源码版：

```powershell
python -m pip install Pillow
python windows\app.py
```

要打包成单文件、无控制台窗口的 EXE，在仓库根目录运行：

```powershell
.\build_windows.ps1
```

结果位于 `dist\windows\哔哩哔哩缓存导出-Windows.exe`。打包脚本会安装 Pillow 和 PyInstaller 到独立的 `.venv-windows`，不会修改系统 Python 环境。GitHub Actions 的 `Windows EXE` 工作流也会生成可下载的构建产物。

Windows 版会尝试扫描用户的 `Videos\bilibili`、`Downloads\bilibili` 和 AppData 下的常见目录。**实际路径以哔哩哔哩客户端「设置 → 下载设置」显示的下载目录为准**；如果列表为空，请点「选择文件夹…」定位该目录，也可直接选择单个视频 `.m4s` 文件。界面提供与 macOS 版相同的三种导出模式；若缓存无音轨，只能导出视频画面。

Windows 测试：

```powershell
python -m unittest discover -s windows\tests -v
```

## macOS 使用

1. 打开应用，点击一张视频卡片。
2. 在“导出内容”里选择三种模式之一。
3. 点击右下角的导出按钮，选择保存位置。

如果某个缓存没有音频分片，仅视频画面仍可导出；另外两个选项会暂时不可用。

## 工作方式

哔哩哔哩缓存中的画面和音频分别保存在 `.m4s` 文件里，文件开头可能多出 9 字节标记。工具先在临时目录生成可读取的副本，再用 FFmpeg 将所选轨道封装成 MP4 或 M4A。导出时使用流复制，不重新编码。

目前按哔哩哔哩桌面客户端常见的 `-30280.m4s` 或 `audio.m4s` 音频缓存格式识别音轨。其他缓存格式尚未验证。Windows 版会递归扫描所选目录下最多四层子目录。
