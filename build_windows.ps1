$ErrorActionPreference = 'Stop'
Set-Location -LiteralPath $PSScriptRoot

if (-not (Get-Command py -ErrorAction SilentlyContinue)) {
    throw '需要安装 Python 3.10 或更新版本。'
}

if (-not (Test-Path '.venv-windows\Scripts\python.exe')) {
    py -3 -m venv .venv-windows
}

$python = Join-Path $PSScriptRoot '.venv-windows\Scripts\python.exe'
& $python -m pip install --disable-pip-version-check -r windows\requirements-build.txt
if ($LASTEXITCODE -ne 0) { throw '依赖安装失败。' }
& $python -m PyInstaller --noconfirm --clean --onefile --windowed --name '哔哩哔哩缓存导出-Windows' --distpath dist\windows --workpath build\windows --specpath build\windows windows\app.py
if ($LASTEXITCODE -ne 0) { throw 'Windows 程序打包失败。' }

Write-Host '完成：dist\windows\哔哩哔哩缓存导出-Windows.exe'
Write-Host '运行时还需要 ffmpeg.exe：放在 EXE 同目录，或将 FFmpeg 加入 PATH。'
