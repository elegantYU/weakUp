import AppKit

final class FrameBox: NSView {
    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
    }

    required init?(coder: NSCoder) { nil }

    override func draw(_ dirtyRect: NSRect) {
        let path = NSBezierPath(roundedRect: bounds.insetBy(dx: 0.5, dy: 0.5), xRadius: 8, yRadius: 8)
        NSColor.controlBackgroundColor.setFill()
        path.fill()
        NSColor.separatorColor.setStroke()
        path.lineWidth = 1
        path.stroke()
    }
}

final class ClickTable: NSTableView {
    var onClickRow: ((Int) -> Void)?

    override func mouseDown(with event: NSEvent) {
        let local = convert(event.locationInWindow, from: nil)
        let row = self.row(at: local)
        if row >= 0 {
            onClickRow?(row)
        }
    }
}

final class AppController: NSObject, NSApplicationDelegate, NSTableViewDataSource, NSTableViewDelegate, NSWindowDelegate {
    private let store: Store
    private let engine: Engine
    private let lidSupported: Bool
    private var catalog: [ManagedApp] = []
    private var running: Set<String> = []
    private var timer: Timer?
    private var statusItem: NSStatusItem?
    private var window: NSWindow?
    private var leftTable: ClickTable?
    private var rightTable: ClickTable?
    private var searchField: NSSearchField?
    private var floorField: NSTextField?
    private var lidCheck: NSButton?
    private var pauseItem: NSMenuItem?
    private var manualItem: NSMenuItem?
    private var leftRows: [ManagedApp] = []
    private var iconCache: [String: NSImage] = [:]
    private let rowIdentifier = NSUserInterfaceItemIdentifier("app-row")

    init(store: Store, engine: Engine, lidSupported: Bool) {
        self.store = store
        self.engine = engine
        self.lidSupported = lidSupported
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        engine.restoreLidIfNeeded()
        catalog = Catalog.load()
        running = Catalog.runningPaths()
        if store.config.apps.contains(where: { Catalog.isSelf($0.path) }) {
            store.update { $0.apps.removeAll { Catalog.isSelf($0.path) } }
        }
        if ProcessInfo.processInfo.environment["KEEP_AWAKE_DEBUG"] == "1" {
            let cursor = running.contains("/Applications/Cursor.app")
            fputs("debug apps=\(store.config.apps.count) running=\(running.count) cursor=\(cursor) floor=\(store.config.batteryFloor) paused=\(store.config.paused)\n", stderr)
        }
        buildStatusItem()
        buildWindow()
        reloadLists()
        prewarmIcons()
        let snapshot = engine.tick(runningPaths: running)
        if ProcessInfo.processInfo.environment["KEEP_AWAKE_DEBUG"] == "1" {
            fputs("debug hold=\(snapshot.holding) status=\(snapshot.status)\n", stderr)
        }
        applySnapshot(snapshot)
        timer = Timer.scheduledTimer(withTimeInterval: 3, repeats: true) { [weak self] _ in
            self?.refresh()
        }
        NSApp.activate(ignoringOtherApps: true)
    }

    func applicationWillTerminate(_ notification: Notification) {
        timer?.invalidate()
        engine.stop()
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }

    func windowShouldClose(_ sender: NSWindow) -> Bool {
        sender.orderOut(nil)
        return false
    }

    private func buildStatusItem() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        if let image = NSImage(systemSymbolName: "moon.zzz", accessibilityDescription: L10n.t("不许睡", "No Sleep")) {
            image.isTemplate = true
            item.button?.image = image
        }
        let menu = NSMenu()
        let openItem = NSMenuItem(title: L10n.t("打开窗口", "Open"), action: #selector(showWindow), keyEquivalent: "")
        let pause = NSMenuItem(title: L10n.t("先允许睡", "Allow sleep"), action: #selector(togglePause), keyEquivalent: "")
        let manual = NSMenuItem(title: L10n.t("现在不许睡", "Stay awake"), action: #selector(toggleManual), keyEquivalent: "")
        let quitItem = NSMenuItem(title: L10n.t("退出", "Quit"), action: #selector(quit), keyEquivalent: "q")
        for entry in [openItem, pause, manual, quitItem] {
            entry.target = self
        }
        menu.addItem(openItem)
        menu.addItem(pause)
        menu.addItem(manual)
        menu.addItem(.separator())
        menu.addItem(quitItem)
        pauseItem = pause
        manualItem = manual
        item.menu = menu
        statusItem = item
    }

    private func buildWindow() {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 980, height: 620),
            styleMask: [.titled, .closable, .miniaturizable],
            backing: .buffered,
            defer: false
        )
        window.title = L10n.t("不许睡", "No Sleep")
        window.delegate = self
        window.isRestorable = false
        window.center()

        let root = NSView()
        window.contentView = root

        let title = label(L10n.t("给我起床好好干活！", "Get up and get to work!"), size: 15, color: .labelColor)
        title.font = .systemFont(ofSize: 15, weight: .medium)

        let leftBox = FrameBox()
        let rightBox = FrameBox()
        [leftBox, rightBox].forEach {
            $0.translatesAutoresizingMaskIntoConstraints = false
            root.addSubview($0)
        }

        let leftTitle = label(L10n.t("全部应用", "All apps"), size: 13, color: .labelColor)
        let search = NSSearchField()
        search.placeholderString = L10n.t("搜索", "Search")
        search.translatesAutoresizingMaskIntoConstraints = false
        searchField = search
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(searchChanged),
            name: NSControl.textDidChangeNotification,
            object: search
        )

        let leftTable = makeTable(onClick: { [weak self] row in self?.addApp(at: row) })
        self.leftTable = leftTable
        let leftScroll = scroll(for: leftTable)

        let rightTitle = label(L10n.t("不许睡", "Keep awake"), size: 13, color: .labelColor)
        let rightTable = makeTable(onClick: { [weak self] row in self?.removeApp(at: row) })
        self.rightTable = rightTable
        let rightScroll = scroll(for: rightTable)

        let floorLabel = label(L10n.t("电池电量下限", "Battery floor"), size: 13, color: .labelColor)
        let floor = NSTextField(string: "\(store.config.batteryFloor)")
        floor.alignment = .center
        floor.font = .monospacedDigitSystemFont(ofSize: 13, weight: .regular)
        floor.translatesAutoresizingMaskIntoConstraints = false
        floorField = floor
        let percent = label("%", size: 13, color: .labelColor)

        let lid = NSButton(checkboxWithTitle: L10n.t("放心合盖，小心电量", "Mind the lid and the battery"), target: nil, action: nil)
        (lid.cell as? NSButtonCell)?.wraps = true
        lid.state = store.config.lidEnabled ? .on : .off
        lid.translatesAutoresizingMaskIntoConstraints = false
        lid.isHidden = !lidSupported
        lidCheck = lid
        let lidNote = label(
            lidSupported ? L10n.t(
                "勾上后，合盖时整台电脑也不睡。点「保存」会要求管理员密码。",
                "With this on, closing the lid keeps the computer awake. Save asks for an administrator password."
            ) : "",
            size: 11,
            color: .secondaryLabelColor
        )
        lidNote.maximumNumberOfLines = 4

        let reset = NSButton(title: L10n.t("恢复默认", "Reset"), target: self, action: #selector(restoreDefaults))
        reset.bezelStyle = .rounded
        reset.translatesAutoresizingMaskIntoConstraints = false
        let save = NSButton(title: L10n.t("保存", "Save"), target: self, action: #selector(saveAndEnable))
        save.bezelStyle = .rounded
        save.keyEquivalent = "\r"
        save.translatesAutoresizingMaskIntoConstraints = false

        let columns = [title, leftTitle, search, leftScroll, rightTitle, rightScroll, floorLabel, floor, percent, lid, lidNote, reset, save]
        columns.forEach {
            $0.translatesAutoresizingMaskIntoConstraints = false
            root.addSubview($0)
        }

        let pad: CGFloat = 20
        NSLayoutConstraint.activate([
            title.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: pad),
            title.trailingAnchor.constraint(equalTo: root.trailingAnchor, constant: -pad),
            title.topAnchor.constraint(equalTo: root.topAnchor, constant: 16),

            leftBox.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: pad),
            leftBox.topAnchor.constraint(equalTo: title.bottomAnchor, constant: 16),
            leftBox.bottomAnchor.constraint(equalTo: root.bottomAnchor, constant: -pad),

            rightBox.leadingAnchor.constraint(equalTo: leftBox.trailingAnchor, constant: 16),
            rightBox.trailingAnchor.constraint(equalTo: root.trailingAnchor, constant: -pad),
            rightBox.topAnchor.constraint(equalTo: leftBox.topAnchor),
            rightBox.widthAnchor.constraint(equalToConstant: 340),
            rightBox.bottomAnchor.constraint(equalTo: floorLabel.topAnchor, constant: -14),

            leftBox.widthAnchor.constraint(equalTo: rightBox.widthAnchor, multiplier: 1.35),

            leftTitle.leadingAnchor.constraint(equalTo: leftBox.leadingAnchor, constant: 12),
            leftTitle.topAnchor.constraint(equalTo: leftBox.topAnchor, constant: 12),
            search.leadingAnchor.constraint(equalTo: leftTitle.leadingAnchor),
            search.trailingAnchor.constraint(equalTo: leftBox.trailingAnchor, constant: -12),
            search.topAnchor.constraint(equalTo: leftTitle.bottomAnchor, constant: 8),
            leftScroll.leadingAnchor.constraint(equalTo: leftBox.leadingAnchor, constant: 8),
            leftScroll.trailingAnchor.constraint(equalTo: leftBox.trailingAnchor, constant: -8),
            leftScroll.topAnchor.constraint(equalTo: search.bottomAnchor, constant: 8),
            leftScroll.bottomAnchor.constraint(equalTo: leftBox.bottomAnchor, constant: -8),

            rightTitle.leadingAnchor.constraint(equalTo: rightBox.leadingAnchor, constant: 12),
            rightTitle.topAnchor.constraint(equalTo: rightBox.topAnchor, constant: 12),
            rightScroll.leadingAnchor.constraint(equalTo: rightBox.leadingAnchor, constant: 8),
            rightScroll.trailingAnchor.constraint(equalTo: rightBox.trailingAnchor, constant: -8),
            rightScroll.topAnchor.constraint(equalTo: rightTitle.bottomAnchor, constant: 8),
            rightScroll.bottomAnchor.constraint(equalTo: rightBox.bottomAnchor, constant: -8),

            floorLabel.leadingAnchor.constraint(equalTo: rightBox.leadingAnchor),
            floor.leadingAnchor.constraint(equalTo: floorLabel.trailingAnchor, constant: 8),
            floor.centerYAnchor.constraint(equalTo: floorLabel.centerYAnchor),
            floor.widthAnchor.constraint(equalToConstant: 48),
            percent.leadingAnchor.constraint(equalTo: floor.trailingAnchor, constant: 4),
            percent.centerYAnchor.constraint(equalTo: floorLabel.centerYAnchor),

            lid.leadingAnchor.constraint(equalTo: rightBox.leadingAnchor),
            lid.topAnchor.constraint(equalTo: floorLabel.bottomAnchor, constant: 10),
            lid.heightAnchor.constraint(greaterThanOrEqualToConstant: 36),
            lidNote.leadingAnchor.constraint(equalTo: rightBox.leadingAnchor),
            lidNote.trailingAnchor.constraint(equalTo: rightBox.trailingAnchor),
            lidNote.topAnchor.constraint(equalTo: lid.bottomAnchor, constant: 4),
            lidNote.bottomAnchor.constraint(equalTo: save.topAnchor, constant: -12),

            save.trailingAnchor.constraint(equalTo: rightBox.trailingAnchor),
            save.bottomAnchor.constraint(equalTo: root.bottomAnchor, constant: -pad),
            save.widthAnchor.constraint(equalToConstant: 118),
            save.heightAnchor.constraint(equalToConstant: 34),
            reset.trailingAnchor.constraint(equalTo: save.leadingAnchor, constant: -8),
            reset.centerYAnchor.constraint(equalTo: save.centerYAnchor),
            reset.widthAnchor.constraint(equalToConstant: 156),
            reset.heightAnchor.constraint(equalToConstant: 34),
        ])

        self.window = window
        window.makeKeyAndOrderFront(nil)
    }

    private func label(_ text: String, size: CGFloat, color: NSColor) -> NSTextField {
        let field = NSTextField(labelWithString: text)
        field.font = .systemFont(ofSize: size)
        field.textColor = color
        field.lineBreakMode = .byWordWrapping
        field.maximumNumberOfLines = 2
        return field
    }

    private func makeTable(onClick: @escaping (Int) -> Void) -> ClickTable {
        let table = ClickTable()
        table.onClickRow = onClick
        let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("app"))
        column.resizingMask = .autoresizingMask
        column.width = 280
        table.addTableColumn(column)
        table.columnAutoresizingStyle = .firstColumnOnlyAutoresizingStyle
        table.headerView = nil
        table.style = .plain
        table.rowHeight = 56
        table.backgroundColor = .clear
        table.selectionHighlightStyle = .none
        table.dataSource = self
        table.delegate = self
        table.intercellSpacing = NSSize(width: 0, height: 4)
        return table
    }

    private func scroll(for table: NSTableView) -> NSScrollView {
        let scroll = NSScrollView()
        scroll.drawsBackground = false
        scroll.hasVerticalScroller = true
        scroll.documentView = table
        scroll.translatesAutoresizingMaskIntoConstraints = false
        return scroll
    }

    private func rebuildLeftRows() {
        let selected = Set(store.config.apps.map(\.path))
        let query = searchField?.stringValue.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        leftRows = catalog.filter { app in
            guard !Catalog.isSelf(app.path), !selected.contains(app.path) else { return false }
            if query.isEmpty { return true }
            return app.name.localizedStandardContains(query)
        }.sorted { lhs, rhs in
            let lr = running.contains(lhs.path)
            let rr = running.contains(rhs.path)
            if lr != rr { return lr && !rr }
            return lhs.name.localizedStandardCompare(rhs.name) == .orderedAscending
        }
    }

    func numberOfRows(in tableView: NSTableView) -> Int {
        if tableView === leftTable { return leftRows.count }
        return store.config.apps.count
    }

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        let app: ManagedApp
        if tableView === leftTable {
            guard row < leftRows.count else { return nil }
            app = leftRows[row]
        } else {
            guard row < store.config.apps.count else { return nil }
            app = store.config.apps[row]
        }
        let cell = (tableView.makeView(withIdentifier: rowIdentifier, owner: self) as? NSTableCellView) ?? makeAppCell()
        cell.textField?.stringValue = app.name
        cell.imageView?.image = icon(for: app.path)
        (cell.viewWithTag(1) as? NSTextField)?.stringValue = running.contains(app.path) ? L10n.t("运行中", "Running") : ""
        return cell
    }

    private func makeAppCell() -> NSTableCellView {
        let cell = NSTableCellView()
        cell.identifier = rowIdentifier
        let iconView = NSImageView()
        iconView.imageScaling = .scaleProportionallyUpOrDown
        iconView.translatesAutoresizingMaskIntoConstraints = false
        let name = NSTextField(labelWithString: "")
        name.font = .systemFont(ofSize: 13)
        name.textColor = .labelColor
        name.lineBreakMode = .byTruncatingTail
        name.translatesAutoresizingMaskIntoConstraints = false
        let mark = NSTextField(labelWithString: "")
        mark.tag = 1
        mark.font = .systemFont(ofSize: 11)
        mark.textColor = .secondaryLabelColor
        mark.translatesAutoresizingMaskIntoConstraints = false
        cell.addSubview(iconView)
        cell.addSubview(name)
        cell.addSubview(mark)
        cell.textField = name
        cell.imageView = iconView
        NSLayoutConstraint.activate([
            iconView.leadingAnchor.constraint(equalTo: cell.leadingAnchor, constant: 8),
            iconView.centerYAnchor.constraint(equalTo: cell.centerYAnchor),
            iconView.widthAnchor.constraint(equalToConstant: 40),
            iconView.heightAnchor.constraint(equalToConstant: 40),
            name.leadingAnchor.constraint(equalTo: iconView.trailingAnchor, constant: 10),
            name.centerYAnchor.constraint(equalTo: cell.centerYAnchor),
            name.trailingAnchor.constraint(lessThanOrEqualTo: mark.leadingAnchor, constant: -8),
            mark.trailingAnchor.constraint(equalTo: cell.trailingAnchor, constant: -8),
            mark.centerYAnchor.constraint(equalTo: cell.centerYAnchor),
        ])
        return cell
    }

    private func icon(for path: String) -> NSImage {
        if let cached = iconCache[path] { return cached }
        let source = NSWorkspace.shared.icon(forFile: path)
        let points: CGFloat = 40
        let pixels = 80
        let raster = NSImage(size: NSSize(width: points, height: points))
        if let rep = NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: pixels,
            pixelsHigh: pixels,
            bitsPerSample: 8,
            samplesPerPixel: 4,
            hasAlpha: true,
            isPlanar: false,
            colorSpaceName: .deviceRGB,
            bytesPerRow: 0,
            bitsPerPixel: 0
        ) {
            rep.size = NSSize(width: points, height: points)
            NSGraphicsContext.saveGraphicsState()
            NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
            NSGraphicsContext.current?.imageInterpolation = .high
            source.draw(in: NSRect(x: 0, y: 0, width: points, height: points))
            NSGraphicsContext.restoreGraphicsState()
            raster.addRepresentation(rep)
            iconCache[path] = raster
            return raster
        }
        source.size = NSSize(width: points, height: points)
        iconCache[path] = source
        return source
    }

    private func prewarmIcons() {
        let paths = Array(Set(catalog.map(\.path) + store.config.apps.map(\.path)))
        var index = 0
        func step() {
            let end = min(index + 16, paths.count)
            while index < end {
                _ = self.icon(for: paths[index])
                index += 1
            }
            if index < paths.count {
                DispatchQueue.main.async(execute: step)
            }
        }
        DispatchQueue.main.async(execute: step)
    }

    private func addApp(at row: Int) {
        guard row < leftRows.count else { return }
        let app = leftRows[row]
        guard !Catalog.isSelf(app.path) else { return }
        guard !store.config.apps.contains(where: { $0.path == app.path }) else { return }
        store.update { $0.apps.append(app) }
        reloadLists()
    }

    private func removeApp(at row: Int) {
        guard row < store.config.apps.count else { return }
        store.update { $0.apps.remove(at: row) }
        reloadLists()
    }

    private func reloadLists() {
        rebuildLeftRows()
        leftTable?.reloadData()
        rightTable?.reloadData()
    }

    @objc private func searchChanged() {
        rebuildLeftRows()
        leftTable?.reloadData()
    }

    @objc private func saveAndEnable() {
        guard let floor = Int(floorField?.stringValue.trimmingCharacters(in: .whitespaces) ?? ""), (1...90).contains(floor) else {
            let alert = NSAlert()
            alert.messageText = L10n.t("电量下限请填 1 到 90 的整数", "Enter a whole number from 1 to 90.")
            alert.runModal()
            return
        }
        engine.allowLidRetry()
        store.update {
            $0.batteryFloor = floor
            $0.lidEnabled = lidSupported && (lidCheck?.state == .on)
            $0.paused = false
        }
        refresh()
        window?.miniaturize(nil)
    }

    @objc private func restoreDefaults() {
        lidCheck?.state = .off
        if let message = engine.restoreDefaults() {
            let alert = NSAlert()
            alert.messageText = message
            alert.runModal()
        }
        reloadLists()
        refresh()
    }

    @objc private func showWindow() {
        window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    @objc private func togglePause() {
        store.update { $0.paused.toggle() }
        refresh()
    }

    @objc private func toggleManual() {
        store.update {
            $0.manual.toggle()
            if $0.manual { $0.paused = false }
        }
        refresh()
    }

    @objc private func quit() {
        NSApp.terminate(nil)
    }

    @discardableResult
    private func refresh() -> EngineSnapshot {
        let next = Catalog.runningPaths()
        if next != running {
            running = next
            reloadLists()
        }
        let snapshot = engine.tick(runningPaths: running)
        applySnapshot(snapshot)
        return snapshot
    }

    private func applySnapshot(_ snapshot: EngineSnapshot) {
        pauseItem?.title = store.config.paused ? L10n.t("继续不许睡", "Keep awake") : L10n.t("先允许睡", "Allow sleep")
        manualItem?.title = store.config.manual ? L10n.t("可以睡了", "Can sleep") : L10n.t("现在不许睡", "Stay awake")
        let symbol = snapshot.holding ? "bolt.fill" : "moon.zzz"
        if let image = NSImage(systemSymbolName: symbol, accessibilityDescription: snapshot.status) {
            image.isTemplate = true
            statusItem?.button?.image = image
        }
    }
}
