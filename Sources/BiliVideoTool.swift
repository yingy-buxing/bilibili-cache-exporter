import Cocoa
import UniformTypeIdentifiers

enum ExportMode: Int {
    case videoOnly = 0
    case audioOnly = 1
    case videoWithAudio = 2

    var fileExtension: String { self == .audioOnly ? "m4a" : "mp4" }
    var displayName: String {
        switch self {
        case .videoOnly: return "仅视频画面"
        case .audioOnly: return "仅音频"
        case .videoWithAudio: return "画面＋音频"
        }
    }
}

final class CacheItem: NSObject {
    let title: String
    let folder: URL
    let videoFile: URL
    let audioFile: URL?
    let coverFile: URL?
    let duration: Int
    let resolution: String

    init(title: String, folder: URL, videoFile: URL, audioFile: URL? = nil, coverFile: URL? = nil, duration: Int = 0, resolution: String = "未知") {
        self.title = title
        self.folder = folder
        self.videoFile = videoFile
        self.audioFile = audioFile
        self.coverFile = coverFile
        self.duration = duration
        self.resolution = resolution
    }
}

final class VideoGridItem: NSCollectionViewItem {
    let coverView = NSImageView()
    let titleLabel = NSTextField(wrappingLabelWithString: "")
    let metaLabel = NSTextField(labelWithString: "")

    override func loadView() {
        view = NSView()
        view.wantsLayer = true
        view.layer?.cornerRadius = 9
        view.layer?.borderWidth = 1
        view.layer?.borderColor = NSColor.separatorColor.cgColor
        view.layer?.backgroundColor = NSColor.controlBackgroundColor.cgColor
        coverView.imageScaling = .scaleAxesIndependently
        coverView.wantsLayer = true
        coverView.layer?.cornerRadius = 8
        coverView.layer?.masksToBounds = true
        coverView.layer?.backgroundColor = NSColor.black.cgColor
        titleLabel.font = .systemFont(ofSize: 13, weight: .semibold)
        titleLabel.maximumNumberOfLines = 2
        titleLabel.lineBreakMode = .byTruncatingTail
        metaLabel.font = .systemFont(ofSize: 11)
        metaLabel.textColor = .secondaryLabelColor
        [coverView, titleLabel, metaLabel].forEach {
            $0.translatesAutoresizingMaskIntoConstraints = false
            view.addSubview($0)
        }
        NSLayoutConstraint.activate([
            coverView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            coverView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            coverView.topAnchor.constraint(equalTo: view.topAnchor),
            coverView.heightAnchor.constraint(equalTo: coverView.widthAnchor, multiplier: 9.0 / 16.0),
            titleLabel.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 9),
            titleLabel.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -9),
            titleLabel.topAnchor.constraint(equalTo: coverView.bottomAnchor, constant: 8),
            metaLabel.leadingAnchor.constraint(equalTo: titleLabel.leadingAnchor),
            metaLabel.trailingAnchor.constraint(equalTo: titleLabel.trailingAnchor),
            metaLabel.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 5)
        ])
    }

    override var isSelected: Bool {
        didSet {
            view.layer?.borderWidth = isSelected ? 3 : 1
            view.layer?.borderColor = isSelected ? NSColor.systemPink.cgColor : NSColor.separatorColor.cgColor
            view.layer?.backgroundColor = (isSelected ? NSColor.selectedContentBackgroundColor.withAlphaComponent(0.12) : NSColor.controlBackgroundColor).cgColor
        }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate, NSCollectionViewDataSource, NSCollectionViewDelegate, NSCollectionViewDelegateFlowLayout, NSWindowDelegate {
    private var window: NSWindow!
    private var collectionView: NSCollectionView!
    private var statusLabel: NSTextField!
    private var detailLabel: NSTextField!
    private var exportButton: NSButton!
    private var exportModeControl: NSSegmentedControl!
    private var spinner: NSProgressIndicator!
    private var items: [CacheItem] = []
    private let defaultCache = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent("Movies/bilibili", isDirectory: true)

    func applicationDidFinishLaunching(_ notification: Notification) {
        buildUI()
        scanDefaultCache()
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }

    private func buildUI() {
        window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 1080, height: 720),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = "哔哩哔哩缓存导出"
        window.center()
        window.minSize = NSSize(width: 900, height: 560)
        window.delegate = self

        guard let content = window.contentView else { return }

        let title = NSTextField(labelWithString: "哔哩哔哩缓存导出")
        title.font = .systemFont(ofSize: 24, weight: .bold)
        title.translatesAutoresizingMaskIntoConstraints = false

        let subtitle = NSTextField(labelWithString: "选择缓存视频和导出内容，生成可直接播放的文件。原缓存不会改变。")
        subtitle.textColor = .secondaryLabelColor
        subtitle.translatesAutoresizingMaskIntoConstraints = false

        let scroll = NSScrollView()
        scroll.hasVerticalScroller = true
        scroll.borderType = .bezelBorder
        scroll.translatesAutoresizingMaskIntoConstraints = false

        let layout = NSCollectionViewFlowLayout()
        layout.minimumInteritemSpacing = 12
        layout.minimumLineSpacing = 14
        layout.sectionInset = NSEdgeInsets(top: 12, left: 12, bottom: 12, right: 12)
        collectionView = NSCollectionView()
        collectionView.collectionViewLayout = layout
        collectionView.isSelectable = true
        collectionView.allowsMultipleSelection = false
        collectionView.delegate = self
        collectionView.dataSource = self
        collectionView.backgroundColors = [.textBackgroundColor]
        collectionView.register(VideoGridItem.self, forItemWithIdentifier: NSUserInterfaceItemIdentifier("videoCard"))
        scroll.documentView = collectionView

        detailLabel = NSTextField(wrappingLabelWithString: "")
        detailLabel.textColor = .secondaryLabelColor
        detailLabel.font = .systemFont(ofSize: 12)
        detailLabel.translatesAutoresizingMaskIntoConstraints = false

        let refreshButton = NSButton(title: "刷新缓存列表", target: self, action: #selector(refreshClicked))
        refreshButton.bezelStyle = .rounded
        refreshButton.translatesAutoresizingMaskIntoConstraints = false

        let chooseButton = NSButton(title: "选择其他文件或文件夹…", target: self, action: #selector(chooseOtherClicked))
        chooseButton.bezelStyle = .rounded
        chooseButton.translatesAutoresizingMaskIntoConstraints = false

        exportButton = NSButton(title: "导出选中视频…", target: self, action: #selector(exportClicked))
        exportButton.bezelStyle = .rounded
        exportButton.keyEquivalent = "\r"
        exportButton.isEnabled = false
        exportButton.translatesAutoresizingMaskIntoConstraints = false

        let modeLabel = NSTextField(labelWithString: "导出内容：")
        modeLabel.translatesAutoresizingMaskIntoConstraints = false
        exportModeControl = NSSegmentedControl(labels: ["仅视频画面", "仅音频", "画面＋音频"],
                                               trackingMode: .selectOne, target: self, action: #selector(exportModeChanged))
        exportModeControl.selectedSegment = ExportMode.videoOnly.rawValue
        exportModeControl.translatesAutoresizingMaskIntoConstraints = false

        spinner = NSProgressIndicator()
        spinner.style = .spinning
        spinner.controlSize = .small
        spinner.isDisplayedWhenStopped = false
        spinner.translatesAutoresizingMaskIntoConstraints = false

        statusLabel = NSTextField(labelWithString: "")
        statusLabel.translatesAutoresizingMaskIntoConstraints = false

        [title, subtitle, scroll, detailLabel, modeLabel, exportModeControl, refreshButton, chooseButton, exportButton, spinner, statusLabel].forEach {
            content.addSubview($0)
        }

        NSLayoutConstraint.activate([
            title.topAnchor.constraint(equalTo: content.topAnchor, constant: 22),
            title.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 24),
            title.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -24),
            subtitle.topAnchor.constraint(equalTo: title.bottomAnchor, constant: 6),
            subtitle.leadingAnchor.constraint(equalTo: title.leadingAnchor),
            subtitle.trailingAnchor.constraint(equalTo: title.trailingAnchor),
            scroll.topAnchor.constraint(equalTo: subtitle.bottomAnchor, constant: 16),
            scroll.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 24),
            scroll.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -24),
            scroll.bottomAnchor.constraint(equalTo: detailLabel.topAnchor, constant: -10),
            detailLabel.leadingAnchor.constraint(equalTo: scroll.leadingAnchor),
            detailLabel.trailingAnchor.constraint(equalTo: scroll.trailingAnchor),
            detailLabel.bottomAnchor.constraint(equalTo: modeLabel.topAnchor, constant: -12),
            modeLabel.leadingAnchor.constraint(equalTo: scroll.leadingAnchor),
            modeLabel.centerYAnchor.constraint(equalTo: exportModeControl.centerYAnchor),
            exportModeControl.leadingAnchor.constraint(equalTo: modeLabel.trailingAnchor, constant: 8),
            exportModeControl.bottomAnchor.constraint(equalTo: refreshButton.topAnchor, constant: -12),
            refreshButton.leadingAnchor.constraint(equalTo: scroll.leadingAnchor),
            refreshButton.bottomAnchor.constraint(equalTo: content.bottomAnchor, constant: -22),
            chooseButton.leadingAnchor.constraint(equalTo: refreshButton.trailingAnchor, constant: 8),
            chooseButton.centerYAnchor.constraint(equalTo: refreshButton.centerYAnchor),
            exportButton.trailingAnchor.constraint(equalTo: scroll.trailingAnchor),
            exportButton.centerYAnchor.constraint(equalTo: refreshButton.centerYAnchor),
            spinner.trailingAnchor.constraint(equalTo: exportButton.leadingAnchor, constant: -10),
            spinner.centerYAnchor.constraint(equalTo: exportButton.centerYAnchor),
            statusLabel.trailingAnchor.constraint(equalTo: spinner.leadingAnchor, constant: -8),
            statusLabel.centerYAnchor.constraint(equalTo: exportButton.centerYAnchor),
            statusLabel.leadingAnchor.constraint(greaterThanOrEqualTo: chooseButton.trailingAnchor, constant: 8),
            scroll.heightAnchor.constraint(greaterThanOrEqualToConstant: 220)
        ])
    }

    func numberOfSections(in collectionView: NSCollectionView) -> Int { 1 }

    func collectionView(_ collectionView: NSCollectionView, numberOfItemsInSection section: Int) -> Int { items.count }

    func collectionView(_ collectionView: NSCollectionView, itemForRepresentedObjectAt indexPath: IndexPath) -> NSCollectionViewItem {
        let cell = collectionView.makeItem(withIdentifier: NSUserInterfaceItemIdentifier("videoCard"), for: indexPath) as! VideoGridItem
        let item = items[indexPath.item]
        cell.titleLabel.stringValue = item.title
        cell.metaLabel.stringValue = "\(formatDuration(item.duration))  ·  \(item.resolution)"
        if let cover = item.coverFile, let image = NSImage(contentsOf: cover) {
            cell.coverView.image = image
        } else {
            cell.coverView.image = NSImage(systemSymbolName: "film", accessibilityDescription: "无封面")
        }
        return cell
    }

    func collectionView(_ collectionView: NSCollectionView, didSelectItemsAt indexPaths: Set<IndexPath>) { selectionChanged() }
    func collectionView(_ collectionView: NSCollectionView, didDeselectItemsAt indexPaths: Set<IndexPath>) { selectionChanged() }

    func collectionView(_ collectionView: NSCollectionView, layout collectionViewLayout: NSCollectionViewLayout, sizeForItemAt indexPath: IndexPath) -> NSSize {
        let available = max(collectionView.bounds.width - 60, 800)
        let width = floor(available / 4)
        return NSSize(width: width, height: floor(width * 9.0 / 16.0) + 68)
    }

    func windowDidResize(_ notification: Notification) {
        collectionView.collectionViewLayout?.invalidateLayout()
    }

    private func selectionChanged() {
        guard let index = collectionView.selectionIndexPaths.first?.item, index < items.count else {
            exportButton.isEnabled = false
            detailLabel.stringValue = ""
            return
        }
        let item = items[index]
        let mode = selectedExportMode
        exportButton.isEnabled = (mode == .videoOnly || item.audioFile != nil)
        detailLabel.stringValue = item.audioFile == nil && mode != .videoOnly
            ? "这个缓存缺少音频文件，请选择“仅视频画面”。"
            : "已选择：\(item.title)    \(formatDuration(item.duration))  ·  \(item.resolution)"
    }

    private var selectedExportMode: ExportMode {
        ExportMode(rawValue: exportModeControl.selectedSegment) ?? .videoOnly
    }

    @objc private func exportModeChanged() {
        selectionChanged()
        exportButton.title = selectedExportMode == .audioOnly ? "导出选中音频…" : "导出选中视频…"
    }

    private func formatDuration(_ totalSeconds: Int) -> String {
        guard totalSeconds > 0 else { return "未知" }
        let hours = totalSeconds / 3600
        let minutes = (totalSeconds % 3600) / 60
        let seconds = totalSeconds % 60
        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, minutes, seconds)
        } else {
            return String(format: "%02d:%02d", minutes, seconds)
        }
    }

    @objc private func refreshClicked() { scanDefaultCache() }

    private func scanDefaultCache() {
        items = scanFolder(defaultCache)
        collectionView.reloadData()
        if !items.isEmpty {
            collectionView.selectionIndexPaths = [IndexPath(item: 0, section: 0)]
            selectionChanged()
            statusLabel.stringValue = "找到 \(items.count) 个"
        } else {
            exportButton.isEnabled = false
            detailLabel.stringValue = "未在 ~/Movies/bilibili 找到缓存，可手动选择文件或文件夹。"
            statusLabel.stringValue = "未找到缓存"
        }
    }

    private func scanFolder(_ root: URL) -> [CacheItem] {
        let fm = FileManager.default
        guard let children = try? fm.contentsOfDirectory(at: root, includingPropertiesForKeys: [.isDirectoryKey], options: [.skipsHiddenFiles]) else {
            return itemFromFolder(root).map { [$0] } ?? []
        }
        var found: [CacheItem] = []
        if let direct = itemFromFolder(root) { found.append(direct) }
        for child in children {
            if let item = itemFromFolder(child) { found.append(item) }
        }
        return found.sorted { $0.title.localizedStandardCompare($1.title) == .orderedAscending }
    }

    private func itemFromFolder(_ folder: URL) -> CacheItem? {
        let fm = FileManager.default
        guard let files = try? fm.contentsOfDirectory(at: folder, includingPropertiesForKeys: [.fileSizeKey], options: [.skipsHiddenFiles]) else { return nil }
        let candidates = files.filter {
            $0.pathExtension.lowercased() == "m4s" && !$0.lastPathComponent.contains("30280")
        }
        guard let video = candidates.max(by: { fileSize($0) < fileSize($1) }) else { return nil }
        let prefix = video.deletingPathExtension().lastPathComponent
            .replacingOccurrences(of: "-30016", with: "")
            .replacingOccurrences(of: "-30064", with: "")
        let audioCandidates = files.filter { $0.lastPathComponent.hasSuffix("-30280.m4s") }
        let audio = audioCandidates.first { $0.lastPathComponent.hasPrefix(prefix + "-") }
            ?? audioCandidates.first

        var title = folder.lastPathComponent
        var duration = 0
        var resolution = "未知"
        let info = folder.appendingPathComponent("videoInfo.json")
        if let data = try? Data(contentsOf: info),
           let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            if let parsed = (json["title"] as? String) ?? (json["groupTitle"] as? String), !parsed.isEmpty {
                title = parsed
            }
            duration = (json["duration"] as? Int) ?? Int((json["duration"] as? Double) ?? 0)
        }
        let playURL = folder.appendingPathComponent(".playurl")
        if let data = try? Data(contentsOf: playURL),
           let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let payload = json["data"] as? [String: Any],
           let dash = payload["dash"] as? [String: Any],
           let videos = dash["video"] as? [[String: Any]],
           let first = videos.first,
           let width = first["width"] as? Int,
           let height = first["height"] as? Int,
           width > 0, height > 0 {
            resolution = "\(width)×\(height)"
        }
        let imageJPG = folder.appendingPathComponent("image.jpg")
        let imagePNG = folder.appendingPathComponent("image.png")
        let groupJPG = folder.appendingPathComponent("group.jpg")
        let groupPNG = folder.appendingPathComponent("group.png")
        let cover = [imageJPG, imagePNG, groupJPG, groupPNG].first { fm.fileExists(atPath: $0.path) }
        return CacheItem(title: title, folder: folder, videoFile: video, audioFile: audio, coverFile: cover, duration: duration, resolution: resolution)
    }

    private func fileSize(_ url: URL) -> Int64 {
        let values = try? url.resourceValues(forKeys: [.fileSizeKey])
        return Int64(values?.fileSize ?? 0)
    }

    @objc private func chooseOtherClicked() {
        let panel = NSOpenPanel()
        panel.title = "选择哔哩哔哩缓存文件或文件夹"
        panel.message = "可以选择数字缓存文件夹、bilibili 缓存总目录，或单个视频 .m4s 文件。"
        panel.canChooseDirectories = true
        panel.canChooseFiles = true
        panel.allowsMultipleSelection = false
        panel.directoryURL = defaultCache
        guard panel.runModal() == .OK, let selected = panel.url else { return }

        if selected.pathExtension.lowercased() == "m4s" {
            let folder = selected.deletingLastPathComponent()
            let scanned = itemFromFolder(folder)
            if selected.lastPathComponent.hasSuffix("-30280.m4s") {
                items = scanned.map { [$0] } ?? []
            } else {
                let item = CacheItem(title: scanned?.title ?? selected.deletingPathExtension().lastPathComponent,
                                     folder: folder, videoFile: selected,
                                     audioFile: scanned?.audioFile,
                                     coverFile: scanned?.coverFile,
                                     duration: scanned?.duration ?? 0,
                                     resolution: scanned?.resolution ?? "未知")
                items = [item]
            }
        } else {
            items = scanFolder(selected)
        }
        collectionView.reloadData()
        if !items.isEmpty {
            collectionView.selectionIndexPaths = [IndexPath(item: 0, section: 0)]
            selectionChanged()
            statusLabel.stringValue = "找到 \(items.count) 个"
        } else {
            statusLabel.stringValue = "所选位置没有视频画面流"
            exportButton.isEnabled = false
        }
    }

    @objc private func exportClicked() {
        guard let index = collectionView.selectionIndexPaths.first?.item, index < items.count else { return }
        let item = items[index]
        let mode = selectedExportMode
        if mode != .videoOnly && item.audioFile == nil {
            showAlert(title: "缺少音频", message: "该缓存文件夹里没有找到音频分片。")
            return
        }

        let panel = NSSavePanel()
        panel.title = mode == .audioOnly ? "保存音频 M4A" : "保存视频 MP4"
        panel.allowedContentTypes = mode == .audioOnly ? [UTType(filenameExtension: "m4a")!] : [.mpeg4Movie]
        panel.canCreateDirectories = true
        panel.nameFieldStringValue = safeFilename(item.title) + "." + mode.fileExtension
        panel.directoryURL = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Desktop")
        guard panel.runModal() == .OK, let output = panel.url else { return }
        convert(item: item, mode: mode, output: output)
    }

    private func safeFilename(_ value: String) -> String {
        let invalid = CharacterSet(charactersIn: "/:\\?%*|\"<>")
        let cleaned = value.components(separatedBy: invalid).joined(separator: "-")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return String((cleaned.isEmpty ? "哔哩哔哩视频" : cleaned).prefix(80))
    }

    private func convert(item: CacheItem, mode: ExportMode, output: URL) {
        setBusy(true, message: "正在处理…")
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self else { return }
            do {
                let tempFolder = FileManager.default.temporaryDirectory
                    .appendingPathComponent("bili-export-\(UUID().uuidString)", isDirectory: true)
                try FileManager.default.createDirectory(at: tempFolder, withIntermediateDirectories: true)
                defer { try? FileManager.default.removeItem(at: tempFolder) }

                let videoTemp = tempFolder.appendingPathComponent("video.m4s")
                let audioTemp = tempFolder.appendingPathComponent("audio.m4s")
                if mode != .audioOnly {
                    try self.makeReadableCopy(source: item.videoFile, destination: videoTemp)
                }
                if mode != .videoOnly {
                    guard let audio = item.audioFile else {
                        throw NSError(domain: "BiliVideoTool", code: 3,
                                      userInfo: [NSLocalizedDescriptionKey: "缓存中缺少音频文件。"])
                    }
                    try self.makeReadableCopy(source: audio, destination: audioTemp)
                }

                guard let ffmpeg = Bundle.main.url(forResource: "ffmpeg", withExtension: nil) else {
                    throw NSError(domain: "BiliVideoTool", code: 2, userInfo: [NSLocalizedDescriptionKey: "应用内缺少 FFmpeg。"])
                }
                let process = Process()
                process.executableURL = ffmpeg
                let base = ["-hide_banner", "-loglevel", "error", "-y"]
                switch mode {
                case .videoOnly:
                    process.arguments = base + ["-i", videoTemp.path, "-map", "0:v:0", "-an",
                                                "-c:v", "copy", "-movflags", "+faststart", output.path]
                case .audioOnly:
                    process.arguments = base + ["-i", audioTemp.path, "-map", "0:a:0", "-vn",
                                                "-c:a", "copy", output.path]
                case .videoWithAudio:
                    process.arguments = base + ["-i", videoTemp.path, "-i", audioTemp.path,
                                                "-map", "0:v:0", "-map", "1:a:0", "-c", "copy",
                                                "-movflags", "+faststart", output.path]
                }
                let errors = Pipe()
                process.standardError = errors
                try process.run()
                process.waitUntilExit()
                let errorData = errors.fileHandleForReading.readDataToEndOfFile()
                if process.terminationStatus != 0 {
                    let message = String(data: errorData, encoding: .utf8) ?? "未知错误"
                    throw NSError(domain: "BiliVideoTool", code: Int(process.terminationStatus),
                                  userInfo: [NSLocalizedDescriptionKey: message])
                }

                DispatchQueue.main.async {
                    self.setBusy(false, message: "导出完成")
                    NSWorkspace.shared.activateFileViewerSelecting([output])
                    self.showAlert(title: "导出完成", message: "已生成\(mode.displayName)文件：\n\(output.path)")
                }
            } catch {
                DispatchQueue.main.async {
                    self.setBusy(false, message: "处理失败")
                    self.showAlert(title: "处理失败", message: error.localizedDescription)
                }
            }
        }
    }

    private func makeReadableCopy(source: URL, destination: URL) throws {
        FileManager.default.createFile(atPath: destination.path, contents: nil)
        let input = try FileHandle(forReadingFrom: source)
        let output = try FileHandle(forWritingTo: destination)
        defer { try? input.close(); try? output.close() }

        let prefix = try input.read(upToCount: 9) ?? Data()
        let obfuscated = prefix == Data("000000000".utf8)
        if !obfuscated { try output.write(contentsOf: prefix) }
        while let chunk = try input.read(upToCount: 4 * 1024 * 1024), !chunk.isEmpty {
            try output.write(contentsOf: chunk)
        }
    }

    private func setBusy(_ busy: Bool, message: String) {
        let index = collectionView.selectionIndexPaths.first?.item
        let audioAvailable = index.flatMap { $0 < items.count ? items[$0].audioFile : nil } != nil
        exportButton.isEnabled = !busy && index != nil && (selectedExportMode == .videoOnly || audioAvailable)
        exportModeControl.isEnabled = !busy
        collectionView.isSelectable = !busy
        statusLabel.stringValue = message
        busy ? spinner.startAnimation(nil) : spinner.stopAnimation(nil)
    }

    private func showAlert(title: String, message: String) {
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = message
        alert.alertStyle = title == "导出完成" ? .informational : .warning
        alert.runModal()
    }
}

let application = NSApplication.shared
let delegate = AppDelegate()
application.delegate = delegate
application.setActivationPolicy(.regular)
application.run()
