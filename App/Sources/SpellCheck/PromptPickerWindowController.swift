import AppKit
import SpellCheckCore

/// FixKey-style compact dark prompt picker: a search field on top (focused,
/// filters as you type) and a scrollable list of prompts with icons below.
/// ↑/↓ move the selection, Enter runs the selected prompt, clicking a row runs
/// it, Escape closes the picker without touching the text.
@MainActor
final class PromptPickerWindowController: NSObject, NSWindowDelegate {

    static let panelWidth: CGFloat = 340
    static let panelHeight: CGFloat = 352

    private let panel: NSPanel
    private let content = NSView()
    private let searchField = PickerSearchField()
    private let tableView = PickerTableView()
    private let emptyLabel = NSTextField(labelWithString: "No prompts match your search")
    private var prompts: [Prompt] = []
    private var filtered: [Prompt] = []
    private var selectedIndex = 0

    /// Called with the chosen prompt. The picker closes itself first.
    var onChoose: ((Prompt) -> Void)?
    /// Called when the picker is dismissed without a choice (Escape).
    var onCancel: (() -> Void)?

    init(prompts: [Prompt]) {
        self.prompts = prompts
        panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: Self.panelWidth, height: Self.panelHeight),
            styleMask: [.borderless, .nonactivatingPanelStyle],
            backing: .buffered,
            defer: false
        )
        super.init()
        panel.isFloatingPanel = true
        panel.level = .floating
        panel.hasShadow = true
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.delegate = self
        panel.standardWindowButton(.closeButton)?.isHidden = true
        panel.standardWindowButton(.miniaturizeButton)?.isHidden = true
        panel.standardWindowButton(.zoomButton)?.isHidden = true
        panel.appearance = NSAppearance(named: .darkAqua)

        buildContent()
        filter(searchText: "")
    }

    private func buildContent() {
        content.wantsLayer = true
        content.layer?.backgroundColor = NSColor(red: 0.11, green: 0.11, blue: 0.12, alpha: 1).cgColor
        content.layer?.cornerRadius = 12

        searchField.placeholderString = "Search prompts"
        searchField.translatesAutoresizingMaskIntoConstraints = false
        searchField.onArrowDown = { [weak self] in self?.moveSelection(1) }
        searchField.onArrowUp = { [weak self] in self?.moveSelection(-1) }
        searchField.onEnter = { [weak self] in self?.runSelected() }
        searchField.onEscape = { [weak self] in self?.cancel() }
        searchField.target = self
        searchField.action = #selector(searchChanged(_:))
        (searchField.cell as? NSSearchFieldCell)?.sendsSearchStringImmediately = true
        content.addSubview(searchField)

        let scrollView = NSScrollView()
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.hasVerticalScroller = true
        scrollView.drawsBackground = false
        content.addSubview(scrollView)

        tableView.style = .plain
        tableView.backgroundColor = .clear
        tableView.rowHeight = 36
        tableView.intercellSpacing = NSSize(width: 0, height: 2)
        tableView.headerView = nil
        tableView.allowsEmptySelection = true
        tableView.usesAutomaticRowHeights = false
        let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("prompt"))
        tableView.addTableColumn(column)
        tableView.sizeLastColumnToFit = true
        tableView.delegate = self
        tableView.dataSource = self
        tableView.onSingleClick = { [weak self] row in self?.choose(row: row) }
        scrollView.documentView = tableView

        emptyLabel.translatesAutoresizingMaskIntoConstraints = false
        emptyLabel.textColor = NSColor.secondaryLabelColor
        emptyLabel.font = .systemFont(ofSize: 13, weight: .medium)
        emptyLabel.alignment = .center
        emptyLabel.isHidden = true
        content.addSubview(emptyLabel)

        NSLayoutConstraint.activate([
            searchField.topAnchor.constraint(equalTo: content.topAnchor, constant: 12),
            searchField.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 12),
            searchField.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -12),

            scrollView.topAnchor.constraint(equalTo: searchField.bottomAnchor, constant: 10),
            scrollView.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 12),
            scrollView.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -12),
            scrollView.bottomAnchor.constraint(equalTo: content.bottomAnchor, constant: -12),

            emptyLabel.centerXAnchor.constraint(equalTo: scrollView.centerXAnchor),
            emptyLabel.centerYAnchor.constraint(equalTo: scrollView.centerYAnchor),
        ])

        panel.contentView = content
    }

    // MARK: Presentation

    func show() {
        filter(searchText: "")
        searchField.stringValue = ""
        positionPanel()
        panel.makeKeyAndOrderFront(nil)
        panel.makeFirstResponder(searchField)
    }

    private func positionPanel() {
        let mouse = NSEvent.mouseLocation
        let screen = NSScreen.screens.first { NSMouseInRect(mouse, $0.frame, false) } ?? NSScreen.main
        guard let visible = screen?.visibleFrame else { return }
        let x = visible.midX - Self.panelWidth / 2
        let y = visible.midY + visible.height * 0.18
        panel.setFrameOrigin(NSPoint(x: x, y: y))
    }

    private func close(then completion: (() -> Void)? = nil) {
        panel.orderOut(nil)
        completion?()
    }

    private func cancel() {
        close(then: onCancel)
    }

    // MARK: Selection

    @objc private func searchChanged(_ sender: Any?) {
        filter(searchText: searchField.stringValue)
    }

    private func filter(searchText: String) {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if query.isEmpty {
            filtered = prompts
        } else {
            filtered = prompts.filter {
                $0.name.lowercased().contains(query) || $0.prompt.lowercased().contains(query)
            }
        }
        selectedIndex = 0
        emptyLabel.isHidden = !filtered.isEmpty
        emptyLabel.stringValue = prompts.isEmpty
            ? "No prompts yet — create some in the Prompt Editor"
            : "No prompts match your search"
        tableView.reloadData()
        if !filtered.isEmpty {
            tableView.selectRowIndexes(IndexSet(integer: 0), byExtendingSelection: false)
            tableView.scrollRowToVisible(0)
        }
    }

    private func moveSelection(_ delta: Int) {
        guard !filtered.isEmpty else { return }
        let previous = selectedIndex
        selectedIndex = min(max(selectedIndex + delta, 0), filtered.count - 1)
        tableView.selectRowIndexes(IndexSet(integer: selectedIndex), byExtendingSelection: false)
        tableView.reloadData(forRowIndexes: IndexSet([previous, selectedIndex]), columnIndexes: IndexSet(integer: 0))
        tableView.scrollRowToVisible(selectedIndex)
    }

    private func runSelected() {
        guard filtered.indices.contains(selectedIndex) else { return }
        choose(row: selectedIndex)
    }

    private func choose(row: Int) {
        guard filtered.indices.contains(row) else { return }
        let prompt = filtered[row]
        close(then: { [weak self] in self?.onChoose?(prompt) })
    }

    func windowWillClose(_ notification: Notification) {
        onCancel?()
    }
}
// MARK: - Table plumbing

extension PromptPickerWindowController: NSTableViewDataSource, NSTableViewDelegate {

    func numberOfRows(in tableView: NSTableView) -> Int { filtered.count }

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        guard filtered.indices.contains(row) else { return nil }
        let prompt = filtered[row]
        let cell = PromptPickerRowView(prompt: prompt)
        cell.selected = tableView.selectedRowIndexes.contains(row)
        return cell
    }

    func tableView(_ tableView: NSTableView, shouldSelectRow row: Int) -> Bool {
        selectedIndex = row
        true
    }
}

/// One prompt row: icon glyph in a rounded box, bold title, one-line preview.
final class PromptPickerRowView: NSView {

    private let titleLabel = NSTextField(labelWithString: "")
    private let iconLabel = NSTextField(labelWithString: "")
    private let iconBox = NSView()

    var selected: Bool = false {
        didSet { updateAppearance() }
    }

    init(prompt: Prompt) {
        super.init(frame: NSRect(x: 0, y: 0, width: 300, height: 36))
        wantsLayer = true

        iconBox.wantsLayer = true
        iconBox.layer?.cornerRadius = 7
        iconBox.layer?.backgroundColor = NSColor(white: 0.19, alpha: 1).cgColor
        iconBox.translatesAutoresizingMaskIntoConstraints = false
        addSubview(iconBox)

        iconLabel.stringValue = prompt.iconKind.glyph
        iconLabel.textColor = NSColor(red: 0.4, green: 0.8, blue: 0.5, alpha: 1)
        iconLabel.font = .systemFont(ofSize: 13, weight: .bold)
        iconLabel.alignment = .center
        iconLabel.translatesAutoresizingMaskIntoConstraints = false
        iconBox.addSubview(iconLabel)

        titleLabel.stringValue = prompt.name
        titleLabel.font = .systemFont(ofSize: 13, weight: .semibold)
        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        addSubview(titleLabel)

        NSLayoutConstraint.activate([
            iconBox.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 8),
            iconBox.centerYAnchor.constraint(equalTo: centerYAnchor),
            iconBox.widthAnchor.constraint(equalToConstant: 28),
            iconBox.heightAnchor.constraint(equalToConstant: 28),
            iconLabel.centerXAnchor.constraint(equalTo: iconBox.centerXAnchor),
            iconLabel.centerYAnchor.constraint(equalTo: iconBox.centerYAnchor),
            titleLabel.leadingAnchor.constraint(equalTo: iconBox.trailingAnchor, constant: 10),
            titleLabel.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor, constant: -8),
            titleLabel.centerYAnchor.constraint(equalTo: centerYAnchor),
        ])
        updateAppearance()
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    private func updateAppearance() {
        layer?.backgroundColor = selected
            ? NSColor(red: 0.19, green: 0.83, blue: 0.34, alpha: 0.22).cgColor
            : NSColor(white: 0.15, alpha: 1).cgColor
        layer?.cornerRadius = 8
        titleLabel.textColor = selected ? .white : NSColor.labelColor
    }
}

/// Search field that forwards ↑/↓/Enter/Escape to the picker instead of
/// treating them as text input.
final class PickerSearchField: NSSearchField {
    var onArrowUp: (() -> Void)?
    var onArrowDown: (() -> Void)?
    var onEnter: (() -> Void)?
    var onEscape: (() -> Void)?

    override func keyDown(with event: NSEvent) {
        switch event.keyCode {
        case 126: onArrowUp?()          // up
        case 125: onArrowDown?()        // down
        case 36, 76: onEnter?()         // return / keypad enter
        case 53: onEscape?()            // esc
        default: super.keyDown(with: event)
        }
    }
}

/// The picker's table: runs a prompt on a single row click.
final class PickerTableView: NSTableView {
    var onSingleClick: ((Int) -> Void)?

    override func mouseDown(with event: NSEvent) {
        super.mouseDown(with: event)
        let point = convert(event.locationInWindow, from: nil)
        let row = row(at: point)
        if row >= 0 {
            onSingleClick?(row)
        }
    }
}
