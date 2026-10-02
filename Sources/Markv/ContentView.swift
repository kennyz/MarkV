import SwiftUI
import AppKit

private enum FileSidebarTab: String, CaseIterable, Identifiable {
    case folder = "Folder"
    case recent = "Recent"

    var id: String { rawValue }

    var symbol: String {
        switch self {
        case .folder: "folder"
        case .recent: "clock"
        }
    }
}

enum MarkvDocumentLayout {
    static let defaultOutlineWidth: CGFloat = 220
    static let minimumOutlineWidth: CGFloat = 160
    static let maximumOutlineWidth: CGFloat = 360
    static let outlineEdgeInset: CGFloat = 8

    static func clampedOutlineWidth(_ width: CGFloat) -> CGFloat {
        min(max(width, minimumOutlineWidth), maximumOutlineWidth)
    }

    static func editorTrailingInset(outlineVisible: Bool, outlineWidth: CGFloat) -> CGFloat {
        outlineVisible ? clampedOutlineWidth(outlineWidth) + (outlineEdgeInset * 2) : 0
    }
}

struct ContentView: View {
    @EnvironmentObject private var model: AppModel
    @State private var isDropTargeted = false
    @State private var isShowingSettings = false
    @State private var isOutlineVisible = true
    @State private var fileSidebarTab: FileSidebarTab = .folder
    @State private var isFileListHovered = false
    @State private var isOutlineHovered = false
    @State private var folderSearchQuery = ""
    @State private var isRenamingCurrentFile = false
    @State private var fileNameDraft = ""
    @State private var outlineResizeStartWidth: CGFloat?
    @State private var isOutlineResizeHovered = false
    @AppStorage("markv.outlineWidth") private var storedOutlineWidth = Double(MarkvDocumentLayout.defaultOutlineWidth)
    @FocusState private var isFileNameFieldFocused: Bool
    @FocusState private var isAIPromptFocused: Bool

    private var palette: MarkvPalette { MarkvPalette(theme: model.appearanceTheme) }
    private var paper: Color { palette.paper }
    private var ink: Color { palette.ink }
    private var accent: Color { palette.accent }
    private var outlineWidth: CGFloat {
        MarkvDocumentLayout.clampedOutlineWidth(CGFloat(storedOutlineWidth))
    }

    var body: some View {
        NavigationSplitView {
            sidebar
                .navigationSplitViewColumnWidth(min: 198, ideal: 224, max: 280)
        } detail: {
            detail
        }
        .tint(accent)
        .background(paper)
        .animation(.easeOut(duration: 0.18), value: model.appearanceTheme)
        .dropDestination(for: URL.self) { urls, _ in
            model.handleDroppedFiles(urls)
        } isTargeted: { targeted in
            withAnimation(.easeOut(duration: 0.16)) {
                isDropTargeted = targeted
            }
        }
        .overlay {
            if isDropTargeted {
                dropOverlay
                    .allowsHitTesting(false)
                    .transition(.opacity.combined(with: .scale(scale: 0.985)))
            }
        }
        .onOpenURL { url in
            model.openExternalFiles([url])
        }
        .onChange(of: model.currentFolder) {
            folderSearchQuery = ""
        }
        .onChange(of: model.currentFile) {
            isRenamingCurrentFile = false
            isFileNameFieldFocused = false
        }
        .task {
            await model.checkForUpdatesAutomatically()
        }
        .alert("Markv", isPresented: Binding(
            get: { model.errorMessage != nil },
            set: { if !$0 { model.errorMessage = nil } }
        )) {
            Button(model.text("OK"), role: .cancel) { model.errorMessage = nil }
        } message: {
            Text(model.errorMessage ?? "")
        }
    }

    private var dropOverlay: some View {
        ZStack {
            paper.opacity(0.86)
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(accent, style: StrokeStyle(lineWidth: 2, dash: [8, 6]))
                .padding(11)

            VStack(spacing: 10) {
                Image(systemName: "doc.badge.arrow.up")
                    .font(.system(size: 28, weight: .medium))
                Text(model.text("Drop to open"))
                    .font(.custom("AvenirNext-DemiBold", size: 15))
                Text(model.text("Markdown and image files"))
                    .font(.custom("AvenirNext-Regular", size: 11))
                    .foregroundStyle(ink.opacity(0.52))
            }
            .foregroundStyle(ink)
        }
    }

    private var sidebar: some View {
        VStack(spacing: 0) {
            sidebarTopActions
                .padding(.top, 8)
                .padding(.bottom, 5)

            if fileSidebarTab == .folder {
                folderSearchField
                    .padding(.horizontal, 10)
                    .padding(.bottom, 2)
            }

            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    if fileSidebarTab == .folder {
                        folderSection
                    } else {
                        recentSection
                    }
                }
                .padding(.horizontal, 10)
                .padding(.top, 9)
                .padding(.bottom, 9)
                .background(SlimScrollViewConfigurator(isHovered: isFileListHovered))
            }
            .onHover { isFileListHovered = $0 }

            Divider().overlay(ink.opacity(0.10))
            sidebarFooter
        }
        .background(palette.sidebarEnd)
        .overlay(alignment: .bottomTrailing) {
            versionButton
                .padding(.trailing, 44)
                .padding(.bottom, 7)
        }
    }

    private var sidebarTopActions: some View {
        HStack(spacing: 6) {
            sidebarActionButton(
                "square.and.pencil",
                help: model.text("New Document (⌘N)"),
                prominent: true,
                iconSize: 16,
                controlSize: 34
            ) {
                model.createEmptyDocument()
            }

            sidebarActionButton(
                "doc",
                help: model.text("Open File (⌘O)"),
                iconSize: 16,
                controlSize: 34
            ) {
                model.chooseFile()
            }

            sidebarActionButton(
                "folder",
                help: model.text("Open Folder (⇧⌘O)"),
                iconSize: 16,
                controlSize: 34
            ) {
                model.chooseDirectory()
            }
        }
        .padding(.leading, 10)
        .padding(.trailing, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .frame(height: 36)
    }

    private var sidebarTabPicker: some View {
        HStack(spacing: 4) {
            ForEach(FileSidebarTab.allCases) { tab in
                let selected = fileSidebarTab == tab
                Button {
                    withAnimation(.easeOut(duration: 0.14)) {
                        fileSidebarTab = tab
                    }
                } label: {
                    Image(systemName: tab.symbol)
                        .font(.system(size: 11, weight: .medium))
                        .frame(width: 28, height: 24)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .foregroundStyle(selected ? ink.opacity(0.88) : ink.opacity(0.38))
                .background(
                    selected ? paper.opacity(0.82) : Color.clear,
                    in: RoundedRectangle(cornerRadius: 6, style: .continuous)
                )
                .help(model.text(tab.rawValue))
                .accessibilityLabel(model.text(tab.rawValue))
                .accessibilityAddTraits(selected ? .isSelected : [])
            }
        }
    }

    private var folderSearchField: some View {
        HStack(spacing: 7) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(ink.opacity(0.38))

            TextField(model.text("Search folder"), text: $folderSearchQuery)
                .textFieldStyle(.plain)
                .font(.custom("AvenirNext-Regular", size: CGFloat(model.sidebarFontSize - 2)))

            if !folderSearchQuery.isEmpty {
                Button {
                    folderSearchQuery = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 10))
                }
                .buttonStyle(.plain)
                .foregroundStyle(ink.opacity(0.32))
                .help(model.text("Clear Search"))
            }
        }
        .padding(.horizontal, 9)
        .frame(height: 28)
        .background(paper.opacity(0.72), in: RoundedRectangle(cornerRadius: 7, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .stroke(ink.opacity(0.075), lineWidth: 1)
        }
        .disabled(model.currentFolder == nil)
    }

    private var sidebarFooter: some View {
        HStack(spacing: 4) {
            sidebarTabPicker

            Spacer()

            sidebarActionButton("gearshape", help: model.text("Appearance Settings")) {
                isShowingSettings.toggle()
            }
            .popover(isPresented: $isShowingSettings, arrowEdge: .bottom) {
                AppearanceSettingsView()
                    .environmentObject(model)
            }
        }
        .foregroundStyle(ink.opacity(0.68))
        .padding(.horizontal, 10)
        .frame(height: 42)
    }

    private var versionButton: some View {
        Button {
            if case .available = model.updateStatus {
                model.openAvailableUpdate()
            } else {
                Task { await model.checkForUpdates() }
            }
        } label: {
            HStack(spacing: 4) {
                if model.updateStatus == .checking {
                    ProgressView()
                        .controlSize(.mini)
                        .scaleEffect(0.55)
                        .frame(width: 8, height: 8)
                } else if case .available = model.updateStatus {
                    Circle()
                        .fill(accent)
                        .frame(width: 5, height: 5)
                }

                Text(versionLabel)
                    .font(.system(size: 9, weight: .medium, design: .rounded))
                    .lineLimit(1)
            }
            .foregroundStyle(versionLabelColor)
            .frame(width: 48, height: 28, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .fixedSize(horizontal: true, vertical: true)
        .layoutPriority(1)
        .help(versionHelp)
        .accessibilityLabel(versionHelp)
    }

    private var versionLabel: String {
        return "v\(model.appVersion)"
    }

    private var versionLabelColor: Color {
        if case .available = model.updateStatus { return accent }
        return ink.opacity(0.34)
    }

    private var versionHelp: String {
        switch model.updateStatus {
        case .idle:
            model.text("Check for Updates")
        case .checking:
            model.text("Checking for Updates…")
        case .upToDate:
            model.localizedFormat("MarkV %@ is up to date", model.appVersion)
        case .available(let release):
            model.localizedFormat("Open the %@ release page", release.version)
        case .failed:
            model.text("Update check failed. Click to try again.")
        }
    }

    private func sidebarActionButton(
        _ symbol: String,
        help: String,
        prominent: Bool = false,
        iconSize: CGFloat = 13,
        controlSize: CGFloat = 30,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: iconSize, weight: prominent ? .semibold : .medium))
                .frame(width: controlSize, height: controlSize - 2)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .foregroundStyle(prominent ? paper : ink.opacity(0.72))
        .background(
            prominent ? accent : Color.clear,
            in: RoundedRectangle(cornerRadius: 8, style: .continuous)
        )
        .shadow(
            color: prominent ? accent.opacity(0.18) : Color.clear,
            radius: 3,
            y: 1
        )
        .help(help)
    }

    private var documentOutlinePanel: some View {
        VStack(spacing: 0) {
            HStack(spacing: 4) {
                Text("\(model.outline.count)")
                    .font(.custom("AvenirNext-Medium", size: 8))
                    .foregroundStyle(ink.opacity(0.30))
                Spacer()
                Button {
                    withAnimation(.easeOut(duration: 0.18)) {
                        isOutlineVisible = false
                    }
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 10, weight: .semibold))
                        .frame(width: 20, height: 20)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .foregroundStyle(ink.opacity(0.5))
                .help(model.text("Close Outline"))
                .accessibilityLabel(model.text("Close Outline"))
            }
            .padding(.leading, 6)
            .padding(.trailing, 2)
            .padding(.top, 4)
            .padding(.bottom, 2)

            ScrollView {
                outlineContent
                    .padding(.horizontal, 3)
                    .padding(.top, 2)
                    .padding(.bottom, 6)
                    .background(SlimScrollViewConfigurator(isHovered: isOutlineHovered))
            }
            .onHover { isOutlineHovered = $0 }
        }
        .frame(width: outlineWidth)
        .overlay(alignment: .leading) {
            outlineResizeHandle
                .offset(x: -4)
        }
    }

    private var outlineResizeHandle: some View {
        ZStack {
            Rectangle()
                .fill(ink.opacity(isOutlineResizeHovered || outlineResizeStartWidth != nil ? 0.18 : 0.001))
                .frame(width: 1)
        }
        .frame(width: 8)
        .contentShape(Rectangle())
        .onHover { hovering in
            isOutlineResizeHovered = hovering
            (hovering ? NSCursor.resizeLeftRight : NSCursor.arrow).set()
        }
        .onDisappear { NSCursor.arrow.set() }
        .gesture(
            DragGesture(minimumDistance: 1)
                .onChanged { value in
                    let startWidth = outlineResizeStartWidth ?? outlineWidth
                    if outlineResizeStartWidth == nil {
                        outlineResizeStartWidth = startWidth
                    }
                    setOutlineWidth(startWidth - value.translation.width)
                }
                .onEnded { _ in
                    outlineResizeStartWidth = nil
                }
        )
        .accessibilityElement()
        .accessibilityLabel(model.text("Resize Outline"))
        .accessibilityAdjustableAction { direction in
            switch direction {
            case .increment: setOutlineWidth(outlineWidth + 20)
            case .decrement: setOutlineWidth(outlineWidth - 20)
            @unknown default: break
            }
        }
    }

    private func setOutlineWidth(_ width: CGFloat) {
        storedOutlineWidth = Double(MarkvDocumentLayout.clampedOutlineWidth(width))
    }

    @ViewBuilder
    private var outlineContent: some View {
        VStack(alignment: .leading, spacing: 2) {
            if model.outline.isEmpty {
                Text(model.text("Add headings to build an outline."))
                    .font(.custom("AvenirNext-Regular", size: 10))
                    .foregroundStyle(ink.opacity(0.46))
                    .padding(4)
            } else {
                ForEach(model.outline) { item in
                    Button {
                        model.performEditorAction(.jumpToHeading(item.anchor))
                    } label: {
                        HStack(spacing: 0) {
                            Text(item.title)
                                .font(.custom("AvenirNext-Regular", size: item.level == 1 ? 13 : 12))
                                .lineLimit(2)
                            Spacer(minLength: 2)
                        }
                        .foregroundStyle(ink.opacity(item.level == 1 ? 0.9 : 0.67))
                        .padding(.leading, CGFloat(max(0, item.level - 1)) * 7)
                        .padding(.horizontal, 3)
                        .padding(.vertical, 4)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    @ViewBuilder
    private var folderSection: some View {
        let visibleFiles = model.files(matching: folderSearchQuery)

        VStack(alignment: .leading, spacing: 7) {
            HStack {
                sectionLabel(model.currentFolder?.lastPathComponent.uppercased() ?? model.text("DIRECTORY"))
                Spacer()
                if !folderSearchQuery.isEmpty {
                    Text("\(visibleFiles.count)")
                        .font(.custom("AvenirNext-Medium", size: CGFloat(model.sidebarFontSize - 4)))
                        .foregroundStyle(ink.opacity(0.36))
                }
                if model.currentFolder != nil {
                    Button {
                        model.refreshFiles()
                    } label: {
                        Image(systemName: "arrow.clockwise")
                            .font(.system(size: 10, weight: .semibold))
                    }
                    .buttonStyle(.plain)
                    .help(model.text("Refresh"))
                }
            }
            .padding(.horizontal, 7)

            if model.currentFolder == nil {
                Button {
                    model.chooseDirectory()
                } label: {
                    Label(model.text("Choose a folder"), systemImage: "folder")
                        .font(.custom("AvenirNext-Medium", size: CGFloat(model.sidebarFontSize - 1)))
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(10)
                }
                .buttonStyle(.plain)
                .background(ink.opacity(0.055), in: RoundedRectangle(cornerRadius: 8))
            } else if visibleFiles.isEmpty {
                Text(model.text(model.files.isEmpty ? "No Markdown files here" : "No matching documents"))
                    .font(.custom("AvenirNext-Regular", size: CGFloat(model.sidebarFontSize - 1)))
                    .foregroundStyle(ink.opacity(0.48))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 5)
            } else {
                ForEach(visibleFiles) { file in
                    fileRow(file.url, title: file.displayName, preview: file.preview) {
                        model.openFile(file.url)
                    }
                    .contextMenu {
                        fileContextMenu(file.url)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var recentSection: some View {
        VStack(alignment: .leading, spacing: 7) {
            if model.recentFiles.isEmpty {
                Text(model.text("No recently opened files"))
                    .font(.custom("AvenirNext-Regular", size: CGFloat(model.sidebarFontSize - 1)))
                    .foregroundStyle(ink.opacity(0.48))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 5)
            } else {
                ForEach(model.recentFiles, id: \.self) { url in
                    fileRow(
                        url,
                        title: url.deletingPathExtension().lastPathComponent,
                        preview: model.preview(for: url)
                    ) {
                        model.openRecent(url)
                    }
                    .contextMenu {
                        fileContextMenu(url)
                        Divider()
                        Button(model.text("Remove from Recent")) { model.removeRecent(url) }
                    }
                }
            }
        }
    }

    private func sectionLabel(_ text: String) -> some View {
        Text(text)
            .font(.custom("AvenirNext-DemiBold", size: CGFloat(model.sidebarFontSize - 4)))
            .tracking(1.2)
            .foregroundStyle(ink.opacity(0.45))
            .lineLimit(1)
    }

    private func fileRow(
        _ url: URL,
        title: String,
        preview: String,
        action: @escaping () -> Void
    ) -> some View {
        let selected = model.currentFile?.standardizedFileURL == url.standardizedFileURL
        return Button(action: action) {
            HStack(spacing: 0) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(title)
                        .font(.custom(selected ? "AvenirNext-DemiBold" : "AvenirNext-Medium", size: CGFloat(model.sidebarFontSize)))
                        .foregroundStyle(ink.opacity(selected ? 1 : 0.78))
                        .lineLimit(1)
                    Text(preview.isEmpty ? model.text("Empty document") : preview)
                        .font(.custom("AvenirNext-Regular", size: CGFloat(model.sidebarFontSize - 2)))
                        .foregroundStyle(ink.opacity(0.32))
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                }
                Spacer(minLength: 2)
                if selected && model.isDirty {
                    Circle().fill(accent).frame(width: 6, height: 6)
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 9)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .background(
            selected ? paper.opacity(0.88) : Color.clear,
            in: RoundedRectangle(cornerRadius: 8, style: .continuous)
        )
        .help(title)
    }

    @ViewBuilder
    private func fileContextMenu(_ url: URL) -> some View {
        Button(model.text("Open File")) {
            model.openRecent(url)
        }
        Button(model.text("Export as PDF")) {
            model.choosePDFExportDestination(for: url)
        }
        Button(model.text("Copy File Path")) {
            _ = model.copyFilePath(url)
        }
        Divider()
        Button(model.text("Move to Trash"), role: .destructive) {
            model.confirmMoveFileToTrash(url)
        }
    }

    @ViewBuilder
    private var detail: some View {
        if model.currentFile == nil {
            emptyState
        } else {
            documentView
        }
    }

    private var emptyState: some View {
        ZStack {
            paper.ignoresSafeArea()
            VStack(spacing: 18) {
                ZStack {
                    Circle()
                        .stroke(ink.opacity(0.14), lineWidth: 1)
                        .frame(width: 110, height: 110)
                    MarkvMMark(ink: ink, accent: accent)
                        .frame(width: 58, height: 58)
                }

                VStack(spacing: 6) {
                    Text(model.text("A quiet place for Markdown."))
                        .font(.custom("NewYork-Semibold", size: 24))
                        .foregroundStyle(ink)
                    Text(model.text(model.currentFolder == nil ? "Open a folder to begin." : "Choose a document from the sidebar."))
                        .font(.custom("AvenirNext-Regular", size: 13))
                        .foregroundStyle(ink.opacity(0.52))
                }

                if model.currentFolder == nil {
                    Button(model.text("Open Folder")) { model.chooseDirectory() }
                        .buttonStyle(MarkvPrimaryButtonStyle(foreground: paper, background: ink))
                }
            }
            .offset(y: -20)
        }
    }

    private var documentView: some View {
        VStack(spacing: 0) {
            documentHeader
            Divider().overlay(ink.opacity(0.1))

            ZStack(alignment: .topTrailing) {
                wysiwygEditor
                    .padding(
                        .trailing,
                        MarkvDocumentLayout.editorTrailingInset(
                            outlineVisible: isOutlineVisible,
                            outlineWidth: outlineWidth
                        )
                    )

                if isOutlineVisible {
                    documentOutlinePanel
                        .padding(.top, MarkvDocumentLayout.outlineEdgeInset)
                        .padding(.trailing, MarkvDocumentLayout.outlineEdgeInset)
                        .transition(.move(edge: .trailing).combined(with: .opacity))
                        .zIndex(1)
                }
            }
            .animation(.easeOut(duration: 0.18), value: isOutlineVisible)

            Divider().overlay(ink.opacity(0.1))
            documentFooter
        }
        .background(paper)
        .overlay(alignment: .bottomTrailing) {
            aiOverlay
                .padding(.trailing, 18)
                .padding(.bottom, 38)
        }
    }

    private var documentHeader: some View {
        VStack(spacing: 6) {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 1) {
                    HStack(spacing: 7) {
                        if isRenamingCurrentFile {
                            TextField(model.text("File name"), text: $fileNameDraft)
                                .textFieldStyle(.plain)
                                .font(.custom("AvenirNext-DemiBold", size: 15))
                                .foregroundStyle(ink)
                                .focused($isFileNameFieldFocused)
                                .frame(width: 220)
                                .padding(.horizontal, 5)
                                .padding(.vertical, 2)
                                .background(
                                    ink.opacity(0.055),
                                    in: RoundedRectangle(cornerRadius: 5, style: .continuous)
                                )
                                .overlay {
                                    RoundedRectangle(cornerRadius: 5, style: .continuous)
                                        .stroke(accent.opacity(0.42), lineWidth: 1)
                                }
                                .onSubmit(commitCurrentFileRename)
                                .onExitCommand(perform: cancelCurrentFileRename)
                                .onAppear { isFileNameFieldFocused = true }
                                .onChange(of: isFileNameFieldFocused) {
                                    if !isFileNameFieldFocused, isRenamingCurrentFile {
                                        commitCurrentFileRename()
                                    }
                                }
                        } else {
                            Text(model.currentFile?.deletingPathExtension().lastPathComponent ?? model.text("Untitled"))
                                .font(.custom("AvenirNext-DemiBold", size: 15))
                                .foregroundStyle(ink)
                                .contentShape(Rectangle())
                                .onTapGesture(count: 2, perform: beginCurrentFileRename)
                                .help(model.text("Double-click to rename"))
                                .accessibilityHint(model.text("Double-click to rename this file"))
                        }
                        if model.isDirty {
                            Circle().fill(accent).frame(width: 6, height: 6)
                        }
                    }
                    Text(model.currentFile?.lastPathComponent ?? "")
                        .font(.custom("AvenirNext-Regular", size: 9))
                        .foregroundStyle(ink.opacity(0.42))
                }
                Spacer()
                if model.focusMode {
                    Label(model.text("Focus"), systemImage: "scope")
                        .font(.custom("AvenirNext-Medium", size: 9))
                        .foregroundStyle(accent)
                }
                if model.typewriterMode {
                    Label(model.text("Typewriter"), systemImage: "text.cursor")
                        .font(.custom("AvenirNext-Medium", size: 9))
                        .foregroundStyle(accent)
                }
                Button {
                    withAnimation(.easeOut(duration: 0.18)) {
                        isOutlineVisible.toggle()
                    }
                } label: {
                    Image(systemName: "sidebar.right")
                        .font(.system(size: 12, weight: .medium))
                        .frame(width: 26, height: 26)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .foregroundStyle(isOutlineVisible ? accent : ink.opacity(0.55))
                .help(model.text(isOutlineVisible ? "Hide Outline" : "Show Outline"))
                .accessibilityLabel(model.text(isOutlineVisible ? "Hide Outline" : "Show Outline"))
                Button {
                    model.save()
                } label: {
                    Label(model.text("Save"), systemImage: "square.and.arrow.down")
                        .font(.custom("AvenirNext-DemiBold", size: 11))
                }
                .buttonStyle(.bordered)
                .disabled(!model.isDirty)
                .keyboardShortcut("s", modifiers: .command)
            }

            formattingToolbar
        }
        .padding(.horizontal, 18)
        .padding(.top, 10)
        .padding(.bottom, 8)
        .background(paper)
    }

    private func beginCurrentFileRename() {
        guard let currentFile = model.currentFile else { return }
        fileNameDraft = currentFile.deletingPathExtension().lastPathComponent
        isRenamingCurrentFile = true
    }

    private func commitCurrentFileRename() {
        guard isRenamingCurrentFile else { return }
        if model.renameCurrentFile(to: fileNameDraft) {
            isRenamingCurrentFile = false
            isFileNameFieldFocused = false
        }
    }

    private func cancelCurrentFileRename() {
        isRenamingCurrentFile = false
        isFileNameFieldFocused = false
    }

    private var formattingToolbar: some View {
        HStack(spacing: 3) {
            Menu {
                Button(model.text("Paragraph")) { model.performEditorAction(.paragraph) }
                Divider()
                ForEach(1...6, id: \.self) { level in
                    Button(model.localizedFormat("Heading %d", level)) { model.performEditorAction(.heading(level)) }
                }
            } label: {
                Label(model.text("Text"), systemImage: "textformat")
                    .font(.custom("AvenirNext-Medium", size: 10))
                    .padding(.horizontal, 7)
                    .frame(height: 26)
            }
            .menuStyle(.borderlessButton)
            .fixedSize()

            toolbarDivider
            editorButton("bold", help: model.text("Bold (⌘B)"), action: .bold)
            editorButton("italic", help: model.text("Italic (⌘I)"), action: .italic)
            editorButton("strikethrough", help: model.text("Strikethrough"), action: .strike)
            editorButton("chevron.left.forwardslash.chevron.right", help: model.text("Inline Code"), action: .inlineCode)
            toolbarDivider
            editorButton("text.quote", help: model.text("Blockquote"), action: .quote)
            editorButton("list.bullet", help: model.text("Bullet List"), action: .unorderedList)
            editorButton("list.number", help: model.text("Numbered List"), action: .orderedList)
            editorButton("checklist", help: model.text("Task List"), action: .taskList)
            toolbarDivider
            editorButton("link", help: model.text("Insert Link"), action: .link)
            imageInsertMenu
            editorButton("tablecells", help: model.text("Insert Table"), action: .table)
            editorButton("curlybraces", help: model.text("Code Block"), action: .codeBlock)
            editorButton("minus", help: model.text("Horizontal Rule"), action: .horizontalRule)
            if model.aiEnabled {
                toolbarDivider
                aiEditMenu
            }
            Spacer()
        }
        .foregroundStyle(ink.opacity(0.72))
    }

    private var aiEditMenu: some View {
        Menu {
            ForEach(AIEditAction.allCases) { action in
                Button(model.text(action.titleKey)) {
                    model.beginAISelectionEdit(action)
                }
            }
        } label: {
            Image(systemName: "sparkles")
                .font(.system(size: 11, weight: .semibold))
                .frame(width: 25, height: 25)
                .contentShape(Rectangle())
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
        .foregroundStyle(accent)
        .help(model.text("AI"))
        .disabled(model.aiIsWorking)
    }

    @ViewBuilder
    private var aiOverlay: some View {
        if model.aiIsWorking {
            aiCard {
                HStack(spacing: 10) {
                    ProgressView()
                        .controlSize(.small)
                    Text(model.text("AI is working…"))
                        .font(.custom("AvenirNext-Medium", size: 11))
                    Spacer()
                    Button(model.text("Cancel Request")) {
                        model.cancelAIInteraction()
                    }
                    .buttonStyle(.plain)
                    .font(.custom("AvenirNext-Medium", size: 10))
                    .foregroundStyle(accent)
                }
            }
            .frame(width: 360)
        } else if let promptContext = model.aiPromptContext {
            aiCard {
                VStack(alignment: .leading, spacing: 10) {
                    Label(model.text("AI instruction"), systemImage: "sparkles")
                        .font(.custom("AvenirNext-DemiBold", size: 12))
                        .foregroundStyle(accent)
                    Text(promptContext == .insertion
                         ? model.text("What should AI write?")
                         : model.text("How should AI edit the selected text?"))
                        .font(.custom("AvenirNext-Regular", size: 10))
                        .foregroundStyle(ink.opacity(0.52))
                    TextField(model.text("AI instruction"), text: $model.aiInstruction, axis: .vertical)
                        .textFieldStyle(.plain)
                        .font(.custom("AvenirNext-Regular", size: 11))
                        .lineLimit(2...5)
                        .padding(8)
                        .background(ink.opacity(0.045), in: RoundedRectangle(cornerRadius: 7))
                        .focused($isAIPromptFocused)
                        .onAppear { isAIPromptFocused = true }
                    HStack {
                        Spacer()
                        Button(model.text("Cancel")) { model.cancelAIPrompt() }
                            .buttonStyle(.plain)
                        Button(model.text("Generate")) { model.submitAIPrompt() }
                            .buttonStyle(.borderedProminent)
                    }
                    .font(.custom("AvenirNext-Medium", size: 10))
                }
            }
            .frame(width: 390)
        } else if let revision = model.aiRevision {
            aiCard {
                VStack(alignment: .leading, spacing: 10) {
                    Label(model.text("AI Suggestion"), systemImage: "sparkles")
                        .font(.custom("AvenirNext-DemiBold", size: 12))
                        .foregroundStyle(accent)

                    if revision.mode == .selection {
                        revisionTextSection(model.text("Original"), text: revision.original, muted: true)
                        Divider()
                    }
                    revisionTextSection(model.text("Suggested"), text: revision.revised, muted: false)

                    HStack(spacing: 9) {
                        Button(model.text("Discard")) { model.discardAIRevision() }
                            .buttonStyle(.plain)
                        Button(model.text("Try Again")) { model.retryAIRevision() }
                            .buttonStyle(.plain)
                        Spacer()
                        if revision.mode == .selection {
                            Button(model.text("Insert Below")) {
                                model.acceptAIRevision(replaceSelection: false)
                            }
                            .buttonStyle(.bordered)
                        }
                        Button(model.text(revision.mode == .selection ? "Replace" : "Insert")) {
                            model.acceptAIRevision()
                        }
                        .buttonStyle(.borderedProminent)
                    }
                    .font(.custom("AvenirNext-Medium", size: 10))
                }
            }
            .frame(width: 450)
        }
    }

    private func aiCard<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        content()
            .padding(14)
            .foregroundStyle(ink)
            .background(
                paper.opacity(0.98),
                in: RoundedRectangle(cornerRadius: 12, style: .continuous)
            )
            .overlay {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(ink.opacity(0.10), lineWidth: 1)
            }
            .shadow(color: ink.opacity(0.12), radius: 18, y: 8)
    }

    private func revisionTextSection(_ title: String, text: String, muted: Bool) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title.uppercased())
                .font(.custom("AvenirNext-DemiBold", size: 8))
                .tracking(1)
                .foregroundStyle(ink.opacity(0.40))
            ScrollView {
                Text(text)
                    .font(.custom("AvenirNext-Regular", size: 11))
                    .foregroundStyle(ink.opacity(muted ? 0.52 : 0.88))
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(maxHeight: 120)
        }
    }

    private var imageInsertMenu: some View {
        Menu {
            Button(model.text("Image URL…")) {
                model.performEditorAction(.image)
            }
            Button(model.text("Upload Image…")) {
                model.chooseImageForInsertion()
            }
        } label: {
            Image(systemName: "photo")
                .font(.system(size: 11, weight: .medium))
                .frame(width: 25, height: 25)
                .contentShape(Rectangle())
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
        .help(model.text("Insert Image"))
    }

    private var toolbarDivider: some View {
        Rectangle()
            .fill(ink.opacity(0.10))
            .frame(width: 1, height: 16)
            .padding(.horizontal, 3)
    }

    private func editorButton(_ symbol: String, help: String, action: EditorAction) -> some View {
        Button {
            model.performEditorAction(action)
        } label: {
            Image(systemName: symbol)
                .font(.system(size: 11, weight: .medium))
                .frame(width: 25, height: 25)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .background(ink.opacity(0.001), in: RoundedRectangle(cornerRadius: 5))
        .help(help)
    }

    private var wysiwygEditor: some View {
        MarkdownWebView(
            markdown: model.documentText,
            documentID: model.currentFile?.path ?? "untitled",
            theme: model.appearanceTheme,
            fontSize: model.editorFontSize,
            baseURL: model.currentFile?.deletingLastPathComponent(),
            focusMode: model.focusMode,
            typewriterMode: model.typewriterMode,
            language: model.appLanguage,
            aiEnabled: model.aiEnabled,
            command: model.editorCommand,
            onChange: { model.updateDocument($0) },
            onPDFExport: { model.handlePDFExportResult($0) },
            onImageImport: { payload in
                model.importImageData(
                    payload.data,
                    suggestedFilename: payload.suggestedFilename,
                    mimeType: payload.mimeType
                )
            },
            onAIEvent: { model.handleAIEditorEvent($0) }
        )
            .id(model.currentFile?.path)
            .background(paper)
    }

    private var documentFooter: some View {
        HStack {
            let statistics = model.statistics
            Label(model.localizedFormat("%d words", statistics.words), systemImage: "text.word.spacing")
            Spacer()
            Text(model.localizedFormat(
                "%d characters · %d lines · %d min read",
                statistics.characters,
                statistics.lines,
                statistics.readingMinutes
            ))
            Spacer()
            if !model.currentFileMetadata.isEmpty {
                Text(model.currentFileMetadata)
            }
            Button(model.text("Reveal in Finder")) { model.revealCurrentFile() }
                .buttonStyle(.plain)
        }
        .font(.custom("AvenirNext-Medium", size: 9))
        .foregroundStyle(ink.opacity(0.43))
        .padding(.horizontal, 18)
        .frame(height: 27)
        .background(paper)
    }
}

private struct MarkvMMark: View {
    let ink: Color
    let accent: Color

    var body: some View {
        GeometryReader { proxy in
            let width = proxy.size.width
            let height = proxy.size.height
            let lineWidth = min(width, height) * 0.12

            ZStack {
                Path { path in
                    path.move(to: CGPoint(x: width * 0.20, y: height * 0.80))
                    path.addLine(to: CGPoint(x: width * 0.20, y: height * 0.20))
                    path.addLine(to: CGPoint(x: width * 0.50, y: height * 0.56))
                }
                .stroke(ink, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round, lineJoin: .round))

                Path { path in
                    path.move(to: CGPoint(x: width * 0.50, y: height * 0.56))
                    path.addLine(to: CGPoint(x: width * 0.80, y: height * 0.20))
                    path.addLine(to: CGPoint(x: width * 0.80, y: height * 0.80))
                }
                .stroke(accent, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round, lineJoin: .round))
            }
        }
        .accessibilityHidden(true)
    }
}

private struct SlimScrollViewConfigurator: NSViewRepresentable {
    let isHovered: Bool

    func makeNSView(context: Context) -> SlimScrollConfiguratorView {
        let view = SlimScrollConfiguratorView(frame: .zero)
        view.isHovered = isHovered
        return view
    }

    func updateNSView(_ nsView: SlimScrollConfiguratorView, context: Context) {
        nsView.isHovered = isHovered
        nsView.configureScrollView()
    }
}

final class SlimScrollConfiguratorView: NSView {
    var isHovered = false

    override func viewDidMoveToSuperview() {
        super.viewDidMoveToSuperview()
        configureScrollView()
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        configureScrollView()
    }

    func configureScrollView() {
        guard let scrollView = enclosingScrollView else { return }

        scrollView.scrollerStyle = .overlay
        scrollView.autohidesScrollers = false
        scrollView.hasHorizontalScroller = false

        if !(scrollView.verticalScroller is MarkvSlimScroller) {
            scrollView.verticalScroller = MarkvSlimScroller(frame: .zero)
        }
        scrollView.hasVerticalScroller = true
        scrollView.verticalScroller?.alphaValue = isHovered ? 1 : 0
    }
}

final class MarkvSlimScroller: NSScroller {
    override class func scrollerWidth(
        for controlSize: NSControl.ControlSize,
        scrollerStyle: NSScroller.Style
    ) -> CGFloat {
        5
    }

    override var isOpaque: Bool { false }

    override func drawKnob() {
        let knob = rect(for: .knob).insetBy(dx: 0.5, dy: 1.5)
        guard knob.width > 0, knob.height > 0 else { return }

        NSColor(calibratedWhite: 0.38, alpha: 0.42).setFill()
        NSBezierPath(
            roundedRect: knob,
            xRadius: knob.width / 2,
            yRadius: knob.width / 2
        ).fill()
    }

    override func drawKnobSlot(in slotRect: NSRect, highlight flag: Bool) {
        // Keep the track fully transparent.
    }
}

private struct MarkvPrimaryButtonStyle: ButtonStyle {
    let foreground: Color
    let background: Color

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.custom("AvenirNext-DemiBold", size: 12))
            .foregroundStyle(foreground)
            .padding(.horizontal, 18)
            .padding(.vertical, 9)
            .background(
                background.opacity(configuration.isPressed ? 0.78 : 1),
                in: RoundedRectangle(cornerRadius: 8, style: .continuous)
            )
    }
}

private struct MarkvPalette {
    let paper: Color
    let sidebarStart: Color
    let sidebarEnd: Color
    let editor: Color
    let ink = Color(red: 0.13, green: 0.14, blue: 0.13)
    let accent = Color(red: 0.73, green: 0.25, blue: 0.16)

    init(theme: AppearanceTheme) {
        switch theme {
        case .khaki:
            paper = Color(red: 0.992, green: 0.988, blue: 0.976)
            sidebarStart = Color(red: 0.976, green: 0.970, blue: 0.950)
            sidebarEnd = Color(red: 0.987, green: 0.982, blue: 0.968)
            editor = Color(red: 0.987, green: 0.982, blue: 0.969)
        case .white:
            paper = .white
            sidebarStart = Color(red: 0.969, green: 0.969, blue: 0.958)
            sidebarEnd = Color(red: 0.987, green: 0.987, blue: 0.980)
            editor = Color(red: 0.981, green: 0.981, blue: 0.973)
        }
    }
}

private struct AppearanceSettingsView: View {
    @EnvironmentObject private var model: AppModel

    private let ink = Color(red: 0.13, green: 0.14, blue: 0.13)
    private let accent = Color(red: 0.73, green: 0.25, blue: 0.16)

    var body: some View {
        ScrollView {
            settingsContent
        }
        .scrollIndicators(.hidden)
        .frame(width: 380)
        .frame(maxHeight: 650)
        .background(Color.white)
        .onAppear {
            model.refreshMarkdownFileAssociation()
        }
    }

    private var settingsContent: some View {
        VStack(alignment: .leading, spacing: 15) {
            VStack(alignment: .leading, spacing: 2) {
                Text(model.text("Appearance"))
                    .font(.custom("AvenirNext-DemiBold", size: 16))
                Text(model.text("Choose the reading surface"))
                    .font(.custom("AvenirNext-Regular", size: 11))
                    .foregroundStyle(ink.opacity(0.5))
            }

            HStack(spacing: 10) {
                ForEach(AppearanceTheme.allCases) { theme in
                    themeCard(theme)
                }
            }

            Divider()

            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text(model.text("Font Size"))
                        .font(.custom("AvenirNext-DemiBold", size: 11))
                    Spacer()
                    Button(model.text("Reset to Default")) { model.resetFontSizes() }
                        .controlSize(.small)
                }
                fontSizeControl(
                    "Document text",
                    value: Binding(get: { model.editorFontSize }, set: { model.setEditorFontSize($0) }),
                    range: AppModel.editorFontSizeRange
                )
                fontSizeControl(
                    "File sidebar",
                    value: Binding(get: { model.sidebarFontSize }, set: { model.setSidebarFontSize($0) }),
                    range: AppModel.sidebarFontSizeRange
                )
                Text(model.text("Document shortcuts: ⌘= larger, ⌘− smaller, ⌘0 reset"))
                    .font(.custom("AvenirNext-Regular", size: 10))
                    .foregroundStyle(ink.opacity(0.5))
            }

            Divider()

            VStack(alignment: .leading, spacing: 7) {
                Text(model.text("Language"))
                    .font(.custom("AvenirNext-DemiBold", size: 11))
                    .foregroundStyle(ink.opacity(0.72))
                Picker(model.text("Interface language"), selection: $model.appLanguage) {
                    ForEach(AppLanguage.allCases) { language in
                        Text(language.displayName).tag(language)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
            }

            Divider()

            VStack(alignment: .leading, spacing: 9) {
                Text(model.text("Writing"))
                    .font(.custom("AvenirNext-DemiBold", size: 11))
                    .foregroundStyle(ink.opacity(0.72))
                Toggle(model.text("Focus mode"), isOn: $model.focusMode)
                Toggle(model.text("Typewriter mode"), isOn: $model.typewriterMode)
            }
            .font(.custom("AvenirNext-Medium", size: 11))
            .toggleStyle(.switch)

            Divider()

            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 10) {
                    VStack(alignment: .leading, spacing: 1) {
                        Text(model.text("Markdown Files"))
                            .font(.custom("AvenirNext-DemiBold", size: 11))
                        Text(model.text("Open .md files with MarkV by default"))
                            .font(.custom("AvenirNext-Regular", size: 9))
                            .foregroundStyle(ink.opacity(0.45))
                    }

                    Spacer()

                    if model.isDefaultMarkdownApplication {
                        Label(model.text("Default App"), systemImage: "checkmark.circle.fill")
                            .font(.custom("AvenirNext-DemiBold", size: 10))
                            .foregroundStyle(accent)
                    } else if model.isChangingMarkdownAssociation {
                        ProgressView()
                            .controlSize(.small)
                    } else {
                        Button(model.text("Set as Default")) {
                            Task { await model.setAsDefaultMarkdownApplication() }
                        }
                        .controlSize(.small)
                    }
                }

                Text(model.text("macOS may ask for confirmation before changing this setting."))
                    .font(.custom("AvenirNext-Regular", size: 9))
                    .foregroundStyle(ink.opacity(0.42))
            }

            Divider()

            VStack(alignment: .leading, spacing: 9) {
                HStack {
                    VStack(alignment: .leading, spacing: 1) {
                        Text(model.text("AI Extension"))
                            .font(.custom("AvenirNext-DemiBold", size: 11))
                        Text(model.text("OpenAI-compatible API"))
                            .font(.custom("AvenirNext-Regular", size: 9))
                            .foregroundStyle(ink.opacity(0.45))
                    }
                    Spacer()
                    Toggle(model.text("Enable AI"), isOn: $model.aiEnabled)
                        .labelsHidden()
                        .toggleStyle(.switch)
                }

                if model.aiEnabled {
                    VStack(alignment: .leading, spacing: 7) {
                        aiSettingField(model.text("Base URL")) {
                            TextField("https://api.openai.com/v1", text: $model.aiBaseURL)
                        }
                        aiSettingField(model.text("Model")) {
                            TextField(model.text("Model"), text: $model.aiModel)
                        }
                        aiSettingField(model.text("API Key")) {
                            SecureField(model.text("Optional for local services"), text: $model.aiAPIKey)
                        }
                    }
                    .textFieldStyle(.roundedBorder)
                    .font(.custom("AvenirNext-Regular", size: 10))

                    Text(model.text("API key is stored in macOS Keychain and sent only to the configured endpoint."))
                        .font(.custom("AvenirNext-Regular", size: 9))
                        .foregroundStyle(ink.opacity(0.46))
                        .fixedSize(horizontal: false, vertical: true)
                    Text(model.text("Select text and use the sparkle menu, or type / in an empty paragraph."))
                        .font(.custom("AvenirNext-Regular", size: 9))
                        .foregroundStyle(ink.opacity(0.46))
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .foregroundStyle(ink)
        .padding(18)
    }

    private func fontSizeControl(_ label: String, value: Binding<Double>, range: ClosedRange<Double>) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(model.text(label))
                Spacer()
                Text("\(Int(value.wrappedValue))")
                    .monospacedDigit()
            }
            .font(.custom("AvenirNext-Medium", size: 11))
            Slider(value: value, in: range, step: 1)
                .tint(accent)
                .accessibilityLabel(model.text(label))
                .accessibilityValue("\(Int(value.wrappedValue))")
        }
    }

    private func aiSettingField<Content: View>(
        _ label: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(label)
                .font(.custom("AvenirNext-Medium", size: 9))
                .foregroundStyle(ink.opacity(0.55))
            content()
        }
    }

    private func themeCard(_ theme: AppearanceTheme) -> some View {
        let palette = MarkvPalette(theme: theme)
        let selected = model.appearanceTheme == theme

        return Button {
            withAnimation(.easeOut(duration: 0.18)) {
                model.appearanceTheme = theme
            }
        } label: {
            VStack(alignment: .leading, spacing: 9) {
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .fill(palette.paper)
                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .fill(palette.sidebarStart)
                        .frame(width: 32)
                    VStack(alignment: .leading, spacing: 4) {
                        RoundedRectangle(cornerRadius: 1).fill(ink.opacity(0.75)).frame(width: 41, height: 3)
                        RoundedRectangle(cornerRadius: 1).fill(ink.opacity(0.16)).frame(width: 55, height: 2)
                        RoundedRectangle(cornerRadius: 1).fill(accent.opacity(0.7)).frame(width: 30, height: 2)
                    }
                    .padding(.leading, 45)
                }
                .frame(height: 58)
                .overlay {
                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .stroke(ink.opacity(0.1), lineWidth: 1)
                }

                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 1) {
                        Text(model.text(theme.displayName))
                            .font(.custom("AvenirNext-DemiBold", size: 12))
                        Text(model.text(theme.detail))
                            .font(.custom("AvenirNext-Regular", size: 9))
                            .foregroundStyle(ink.opacity(0.45))
                    }
                    Spacer()
                    if selected {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(accent)
                    }
                }
            }
            .padding(9)
            .frame(width: 132)
            .background(
                selected ? accent.opacity(0.065) : Color.clear,
                in: RoundedRectangle(cornerRadius: 10, style: .continuous)
            )
            .overlay {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .stroke(selected ? accent.opacity(0.75) : ink.opacity(0.10), lineWidth: selected ? 1.5 : 1)
            }
        }
        .buttonStyle(.plain)
    }
}
