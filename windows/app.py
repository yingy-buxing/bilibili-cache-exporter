"""Windows desktop interface for Bilibili cache export."""

from __future__ import annotations

import threading
import tkinter as tk
from pathlib import Path
from tkinter import filedialog, messagebox, ttk

from cache_exporter import CacheItem, default_cache_folders, export, find_ffmpeg, item_from_file, safe_filename, saved_cache_folder, save_cache_folder, scan_folder

try:
    from PIL import Image, ImageTk
except ImportError:
    Image = ImageTk = None


def duration_text(seconds: int) -> str:
    if seconds <= 0:
        return "未知"
    hours, remainder = divmod(seconds, 3600)
    minutes, seconds = divmod(remainder, 60)
    return f"{hours}:{minutes:02}:{seconds:02}" if hours else f"{minutes:02}:{seconds:02}"


class App(tk.Tk):
    def __init__(self) -> None:
        super().__init__()
        self.title("哔哩哔哩缓存导出 · Windows")
        self.geometry("1100x740")
        self.minsize(860, 540)
        self.items: list[CacheItem] = []
        self.selected: int | None = None
        self.cards: list[tk.Frame] = []
        self.images: list[object] = []
        self.busy = False
        self.source_folder: Path | None = saved_cache_folder()
        self.source_file: Path | None = None
        self.mode = tk.StringVar(value="video")
        self.status = tk.StringVar(value="准备就绪")
        self.detail = tk.StringVar(value="选择缓存视频后即可导出。")
        self._build()
        self.after(100, self._refresh)

    def _build(self) -> None:
        self.configure(bg="#f5f6fa")
        header = tk.Frame(self, bg="#f5f6fa")
        header.pack(fill="x", padx=24, pady=(20, 12))
        tk.Label(header, text="哔哩哔哩缓存导出", bg="#f5f6fa", font=("Microsoft YaHei UI", 20, "bold")).pack(anchor="w")
        tk.Label(header, text="选择本地缓存，导出视频、音频或合并后的 MP4。原缓存不会改变。", bg="#f5f6fa", fg="#646875", font=("Microsoft YaHei UI", 10)).pack(anchor="w", pady=(4, 0))

        holder = tk.Frame(self, bg="white", highlightbackground="#d8dbe4", highlightthickness=1)
        holder.pack(fill="both", expand=True, padx=24)
        self.canvas = tk.Canvas(holder, bg="white", highlightthickness=0)
        scroll = ttk.Scrollbar(holder, orient="vertical", command=self.canvas.yview)
        self.canvas.configure(yscrollcommand=scroll.set)
        scroll.pack(side="right", fill="y")
        self.canvas.pack(side="left", fill="both", expand=True)
        self.grid_frame = tk.Frame(self.canvas, bg="white")
        self.canvas_window = self.canvas.create_window((0, 0), window=self.grid_frame, anchor="nw")
        self.grid_frame.bind("<Configure>", lambda _: self.canvas.configure(scrollregion=self.canvas.bbox("all")))
        self.canvas.bind("<Configure>", lambda event: self.canvas.itemconfigure(self.canvas_window, width=event.width))
        self.canvas.bind_all("<MouseWheel>", self._scroll)

        bottom = tk.Frame(self, bg="#f5f6fa")
        bottom.pack(fill="x", padx=24, pady=(12, 20))
        tk.Label(bottom, textvariable=self.detail, bg="#f5f6fa", fg="#525866", anchor="w", font=("Microsoft YaHei UI", 10)).pack(fill="x", pady=(0, 12))
        modes = tk.Frame(bottom, bg="#f5f6fa")
        modes.pack(fill="x", pady=(0, 12))
        tk.Label(modes, text="导出内容：", bg="#f5f6fa", font=("Microsoft YaHei UI", 10)).pack(side="left")
        for label, value in (("仅视频画面", "video"), ("仅音频", "audio"), ("画面＋音频", "combined")):
            ttk.Radiobutton(modes, text=label, variable=self.mode, value=value, command=self._update_selection).pack(side="left", padx=(4, 18))
        actions = tk.Frame(bottom, bg="#f5f6fa")
        actions.pack(fill="x")
        self.refresh_button = ttk.Button(actions, text="刷新缓存列表", command=self._refresh)
        self.refresh_button.pack(side="left")
        self.folder_button = ttk.Button(actions, text="选择文件夹…", command=self._choose_folder)
        self.folder_button.pack(side="left", padx=(8, 0))
        self.file_button = ttk.Button(actions, text="选择 .m4s 文件…", command=self._choose_file)
        self.file_button.pack(side="left", padx=(8, 0))
        self.export_button = ttk.Button(actions, text="导出选中视频…", command=self._choose_output, state="disabled")
        self.export_button.pack(side="right")
        tk.Label(actions, textvariable=self.status, bg="#f5f6fa", fg="#646875").pack(side="right", padx=12)

    def _scroll(self, event: tk.Event) -> None:
        self.canvas.yview_scroll(-int(event.delta / 120), "units")

    def _refresh(self) -> None:
        if self.source_file is not None:
            self._load_file(self.source_file)
        elif self.source_folder is not None:
            self._scan_folder(self.source_folder)
        else:
            self._load_defaults()

    def _load_defaults(self) -> None:
        folders = default_cache_folders()
        if not folders:
            self._show_items([], "未找到默认缓存目录。请在 B 站客户端的“设置 → 下载设置”中查看路径，并手动选择文件夹。")
            return
        self._set_busy(True, "正在扫描缓存…")

        def work() -> None:
            found = {}
            for folder in folders:
                for item in scan_folder(folder):
                    found[item.folder] = item
            items = sorted(found.values(), key=lambda item: item.title.casefold())
            self.after(0, lambda: self._show_items(items, f"找到 {len(items)} 个缓存"))

        threading.Thread(target=work, daemon=True).start()

    def _choose_folder(self) -> None:
        options = {"initialdir": str(self.source_folder)} if self.source_folder else {}
        path = filedialog.askdirectory(title="选择哔哩哔哩缓存文件夹", **options)
        if not path:
            return
        self.source_folder = Path(path)
        self.source_file = None
        try:
            save_cache_folder(self.source_folder)
        except OSError:
            pass
        self._scan_folder(self.source_folder)

    def _scan_folder(self, folder: Path) -> None:
        self._set_busy(True, "正在扫描缓存…")

        def work() -> None:
            items = scan_folder(folder)
            self.after(0, lambda: self._show_items(items, f"找到 {len(items)} 个缓存"))

        threading.Thread(target=work, daemon=True).start()

    def _choose_file(self) -> None:
        path = filedialog.askopenfilename(title="选择视频 .m4s 文件", filetypes=[("M4S 缓存", "*.m4s")])
        if path:
            self.source_file = Path(path)
            self._load_file(self.source_file)

    def _load_file(self, path: Path) -> None:
        item = item_from_file(path)
        self._show_items([item] if item else [], "已载入缓存文件" if item else "无法识别缓存文件")

    def _show_items(self, items: list[CacheItem], status: str) -> None:
        self.items = items
        self.selected = None
        self.images.clear()
        for child in self.grid_frame.winfo_children():
            child.destroy()
        self.cards.clear()
        for index, item in enumerate(items):
            card = tk.Frame(self.grid_frame, bg="#fff", highlightbackground="#d8dbe4", highlightthickness=1, width=235, height=205)
            card.grid(row=index // 4, column=index % 4, padx=10, pady=10, sticky="nsew")
            card.grid_propagate(False)
            self.cards.append(card)
            image = self._cover(item.cover)
            cover_area = tk.Frame(card, bg="#171923", height=132)
            cover_area.pack(fill="x")
            cover_area.pack_propagate(False)
            cover = tk.Label(cover_area, image=image, text="无封面" if image is None else "", bg="#171923", fg="white")
            cover.pack(fill="both", expand=True)
            if image is not None:
                self.images.append(image)
            tk.Label(card, text=item.title, bg="white", anchor="w", font=("Microsoft YaHei UI", 10, "bold"), wraplength=215, height=2, justify="left").pack(fill="x", padx=8, pady=(5, 0))
            tk.Label(card, text=f"{duration_text(item.duration)}  ·  {item.resolution}", bg="white", fg="#717684", anchor="w").pack(fill="x", padx=8)
            self._bind_card(card, index)
        for column in range(4):
            self.grid_frame.grid_columnconfigure(column, weight=1)
        self._set_busy(False, status)
        if items:
            self._select(0)
        else:
            self.detail.set("此位置没有找到视频缓存。请确认已缓存完成，或选择正确的下载目录。")

    def _cover(self, path: Path | None) -> object | None:
        if not path or Image is None:
            return None
        try:
            with Image.open(path) as source:
                image = source.convert("RGB")
                image.thumbnail((233, 132))
                return ImageTk.PhotoImage(image)
        except (OSError, ValueError):
            return None

    def _bind_card(self, widget: tk.Widget, index: int) -> None:
        widget.bind("<Button-1>", lambda _: self._select(index))
        for child in widget.winfo_children():
            self._bind_card(child, index)

    def _select(self, index: int) -> None:
        self.selected = index
        for number, card in enumerate(self.cards):
            card.configure(highlightbackground="#e84284" if number == index else "#d8dbe4", highlightthickness=3 if number == index else 1)
        self._update_selection()

    def _update_selection(self) -> None:
        item = self.items[self.selected] if self.selected is not None and self.selected < len(self.items) else None
        enabled = bool(item and (self.mode.get() == "video" or item.audio) and not self.busy)
        self.export_button.configure(state="normal" if enabled else "disabled", text="导出选中音频…" if self.mode.get() == "audio" else "导出选中视频…")
        if item:
            self.detail.set("这个缓存缺少音频文件，请选择“仅视频画面”。" if not item.audio and self.mode.get() != "video" else f"已选择：{item.title}    {duration_text(item.duration)}  ·  {item.resolution}")

    def _set_busy(self, busy: bool, status: str) -> None:
        self.busy = busy
        self.status.set(status)
        state = "disabled" if busy else "normal"
        for button in (self.refresh_button, self.folder_button, self.file_button):
            button.configure(state=state)
        self._update_selection()

    def _choose_output(self) -> None:
        if self.selected is None:
            return
        item, mode = self.items[self.selected], self.mode.get()
        suffix = ".m4a" if mode == "audio" else ".mp4"
        output = filedialog.asksaveasfilename(title="保存导出文件", defaultextension=suffix, initialfile=safe_filename(item.title) + suffix, filetypes=[("媒体文件", "*" + suffix)])
        if not output:
            return
        if not find_ffmpeg():
            messagebox.showerror("缺少 FFmpeg", "找不到 ffmpeg.exe。请将它放在程序旁边，或加入系统 PATH。")
            return
        self._set_busy(True, "正在导出…")

        def work() -> None:
            try:
                export(item, mode, Path(output))
                self.after(0, lambda: self._export_done(output, None))
            except Exception as error:
                self.after(0, lambda error=error: self._export_done(output, error))

        threading.Thread(target=work, daemon=True).start()

    def _export_done(self, output: str, error: Exception | None) -> None:
        self._set_busy(False, "处理失败" if error else "导出完成")
        if error:
            messagebox.showerror("处理失败", str(error))
        else:
            messagebox.showinfo("导出完成", f"文件已保存：\n{output}")


if __name__ == "__main__":
    App().mainloop()
