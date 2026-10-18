import Cocoa
import NaturalLanguage

final class TranslationPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override func cancelOperation(_ sender: Any?) { orderOut(nil) }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    var item: NSStatusItem!
    var panel: TranslationPanel!
    var source = NSTextView()
    var result = NSTextView()
    var status = NSTextField(labelWithString: "选中文字，连按两次 ⌘C 或 Ctrl+C")
    var language = NSPopUpButton()
    var model = NSPopUpButton()
    var tap: CFMachPort?
    var tapSource: CFRunLoopSource?
    var lastCopy: TimeInterval = 0
    var pending: DispatchWorkItem?
    var request: URLSessionDataTask?
    var generation = UUID()
    var translated = ""
    var automatic = true

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        makePanel()
        item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        item.button?.title = "译"
        let menu = NSMenu()
        menu.addItem(withTitle: "打开翻译窗口…", action: #selector(openWindow), keyEquivalent: "")
        menu.addItem(withTitle: "翻译剪贴板", action: #selector(translateClipboard), keyEquivalent: "")
        menu.addItem(.separator())
        menu.addItem(withTitle: "开启 / 重新连接快捷键监听…", action: #selector(enableKeyboard), keyEquivalent: "")
        menu.addItem(withTitle: "暂停 / 恢复双击复制", action: #selector(toggleAutomatic), keyEquivalent: "")
        menu.addItem(withTitle: "下载 Ollama…", action: #selector(downloadOllama), keyEquivalent: "")
        menu.addItem(.separator())
        menu.addItem(withTitle: "退出本地译", action: #selector(quit), keyEquivalent: "q")
        for entry in menu.items { entry.target = self }
        item.menu = menu
        _ = installTap()
        if !UserDefaults.standard.bool(forKey: "hasOpened") {
            UserDefaults.standard.set(true, forKey: "hasOpened")
            openWindow()
        }
    }

    func scroll(_ text: NSTextView, height: CGFloat, editable: Bool) -> NSScrollView {
        let view = NSScrollView()
        view.hasVerticalScroller = true
        view.borderType = .bezelBorder
        text.isEditable = editable
        text.isRichText = false
        text.font = .systemFont(ofSize: 16)
        text.textContainerInset = NSSize(width: 10, height: 10)
        text.isVerticallyResizable = true
        text.isHorizontallyResizable = false
        text.autoresizingMask = [.width]
        text.textContainer?.widthTracksTextView = true
        view.documentView = text
        view.heightAnchor.constraint(equalToConstant: height).isActive = true
        return view
    }

    func button(_ title: String, _ action: Selector) -> NSButton {
        NSButton(title: title, target: self, action: action)
    }

    func makePanel() {
        panel = TranslationPanel(contentRect: NSRect(x: 0, y: 0, width: 540, height: 560),
                                 styleMask: [.titled, .closable, .utilityWindow], backing: .buffered, defer: false)
        panel.title = "本地译 · English / 日本語 → 中文"
        panel.level = .floating
        panel.isReleasedWhenClosed = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        let root = NSStackView()
        root.orientation = .vertical
        root.alignment = .leading
        root.spacing = 10
        root.edgeInsets = NSEdgeInsets(top: 16, left: 16, bottom: 16, right: 16)
        root.translatesAutoresizingMaskIntoConstraints = false
        panel.contentView!.addSubview(root)
        NSLayoutConstraint.activate([
            root.leadingAnchor.constraint(equalTo: panel.contentView!.leadingAnchor),
            root.trailingAnchor.constraint(equalTo: panel.contentView!.trailingAnchor),
            root.topAnchor.constraint(equalTo: panel.contentView!.topAnchor),
            root.bottomAnchor.constraint(equalTo: panel.contentView!.bottomAnchor)
        ])
        language.addItems(withTitles: ["自动识别", "英语 → 中文", "日语 → 中文"])
        model.addItems(withTitles: ["translategemma:4b", "translategemma:12b"])
        model.selectItem(withTitle: UserDefaults.standard.string(forKey: "model") ?? "translategemma:4b")
        model.target = self
        model.action = #selector(modelChanged)
        let choices = NSStackView(views: [language, model])
        choices.spacing = 10
        root.addArrangedSubview(choices)
        root.addArrangedSubview(NSTextField(labelWithString: "原文（可粘贴、修改）"))
        let input = scroll(source, height: 135, editable: true)
        root.addArrangedSubview(input)
        root.addArrangedSubview(NSTextField(labelWithString: "中文译文"))
        let output = scroll(result, height: 185, editable: false)
        root.addArrangedSubview(output)
        let actions = NSStackView(views: [button("翻译", #selector(translateInput)), button("翻译剪贴板", #selector(translateClipboard)), button("复制译文", #selector(copyResult)), button("快捷键权限", #selector(enableKeyboard))])
        actions.spacing = 8
        root.addArrangedSubview(actions)
        status.font = .systemFont(ofSize: 11)
        status.textColor = .secondaryLabelColor
        status.maximumNumberOfLines = 3
        status.lineBreakMode = .byWordWrapping
        root.addArrangedSubview(status)
        for view in [input, output, status] as [NSView] {
            view.widthAnchor.constraint(equalTo: root.widthAnchor, constant: -32).isActive = true
        }
        panel.setContentSize(NSSize(width: 540, height: 540))
    }

    @objc func modelChanged() {
        UserDefaults.standard.set(model.titleOfSelectedItem, forKey: "model")
    }
    @objc func toggleAutomatic() {
        automatic.toggle()
        lastCopy = 0
        pending?.cancel()
        item.button?.title = automatic ? "译" : "译·停"
    }
    @objc func quit() { NSApp.terminate(nil) }
    @objc func downloadOllama() { NSWorkspace.shared.open(URL(string: "https://ollama.com/download/mac")!) }
    @objc func openWindow() {
        let mouse = NSEvent.mouseLocation
        let screen = NSScreen.screens.first(where: { $0.frame.contains(mouse) }) ?? NSScreen.main!
        let area = screen.visibleFrame
        let size = panel.frame.size
        panel.setFrameOrigin(NSPoint(x: min(max(mouse.x + 12, area.minX), max(area.minX, area.maxX - size.width)),
                                     y: min(max(mouse.y - size.height - 12, area.minY), max(area.minY, area.maxY - size.height))))
        NSApp.activate(ignoringOtherApps: true)
        panel.makeKeyAndOrderFront(nil)
    }
    @objc func copyResult() {
        guard !translated.isEmpty else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(translated, forType: .string)
    }
    @objc func translateClipboard() {
        guard let text = NSPasteboard.general.string(forType: .string), !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            openWindow()
            status.stringValue = "剪贴板没有文字。请先复制，或在原文框粘贴文字。"
            return
        }
        source.string = text
        openWindow()
        translateInput()
    }
    @objc func translateInput() {
        let text = source.string.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { status.stringValue = "请先输入或复制文字。"; return }
        guard text.count <= 12000 else { status.stringValue = "一次最多翻译 12000 个字符，请分段复制。"; return }
        request?.cancel()
        let id = UUID()
        generation = id
        translated = ""
        result.string = ""
        let sourceLanguage: String
        if language.indexOfSelectedItem == 1 { sourceLanguage = "en" }
        else if language.indexOfSelectedItem == 2 { sourceLanguage = "ja" }
        else {
            let recognizer = NLLanguageRecognizer()
            recognizer.languageConstraints = [.english, .japanese]
            recognizer.processString(text)
            sourceLanguage = recognizer.dominantLanguage == .japanese ? "ja" : "en"
        }
        let name = sourceLanguage == "ja" ? "Japanese" : "English"
        let selectedModel = model.titleOfSelectedItem ?? "translategemma:4b"
        status.stringValue = "正在翻译 · \(name) → 中文 · \(selectedModel)（首次加载稍慢）"
        let prompt = "You are a professional \(name) (\(sourceLanguage)) to Chinese (zh-Hans) translator. Your goal is to accurately convey the meaning and nuances of the original \(name) text while adhering to Chinese grammar, vocabulary, and cultural sensitivities.\nProduce only the Chinese translation, without any additional explanations or commentary. Please translate the following \(name) text into Chinese:\n\n\n\(text)"
        var req = URLRequest(url: URL(string: "http://127.0.0.1:11434/api/chat")!)
        req.httpMethod = "POST"
        req.timeoutInterval = 180
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = try! JSONSerialization.data(withJSONObject: [
            "model": selectedModel, "messages": [["role": "user", "content": prompt]],
            "stream": false, "keep_alive": "30m", "options": ["temperature": 0, "num_predict": 4096, "num_ctx": 16384]
        ])
        let start = Date()
        request = URLSession.shared.dataTask(with: req) { data, response, error in
            DispatchQueue.main.async {
                guard self.generation == id else { return }
                if let error = error {
                    self.status.stringValue = "无法连接或请求超时：\(error.localizedDescription)"
                    self.result.string = "请启动 Ollama，并在终端运行：\n\nollama pull \(selectedModel)\n\n模型下载完成后重试。"
                    return
                }
                guard let data = data, let json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else {
                    self.status.stringValue = "Ollama 返回了无法识别的响应。"; return
                }
                if let error = json["error"] as? String {
                    self.status.stringValue = "Ollama：\(error)"
                    self.result.string = "请在终端运行：\nollama pull \(selectedModel)"
                    return
                }
                guard (response as? HTTPURLResponse)?.statusCode == 200,
                      let message = json["message"] as? [String: Any], let content = message["content"] as? String, !content.isEmpty else {
                    self.status.stringValue = "没有收到有效译文，请重试。"; return
                }
                self.translated = content.trimmingCharacters(in: .whitespacesAndNewlines)
                self.result.string = self.translated
                let truncated = json["done_reason"] as? String == "length"
                self.status.stringValue = truncated ? "译文达到输出上限，请分段翻译。" : String(format: "完成 · %.1f 秒 · %@ → 中文 · 仅本机处理", Date().timeIntervalSince(start), name)
            }
        }
        request?.resume()
    }

    @objc func enableKeyboard() {
        if !CGPreflightListenEventAccess() { _ = CGRequestListenEventAccess() }
        if !installTap() {
            NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ListenEvent")!)
            status.stringValue = "在「输入监控」中开启本地译，然后退出并重新打开应用。"
        } else { status.stringValue = "快捷键已就绪：选中文字后，0.65 秒内连按两次 ⌘C 或 Ctrl+C。" }
    }
    func installTap() -> Bool {
        if tap != nil { return true }
        guard CGPreflightListenEventAccess() else { return false }
        let callback: CGEventTapCallBack = { _, type, event, userInfo in
            guard let userInfo = userInfo else { return Unmanaged.passUnretained(event) }
            let app = Unmanaged<AppDelegate>.fromOpaque(userInfo).takeUnretainedValue()
            if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
                if let tap = app.tap { CGEvent.tapEnable(tap: tap, enable: true) }
                return Unmanaged.passUnretained(event)
            }
            guard app.automatic, type == .keyDown else { return Unmanaged.passUnretained(event) }
            let key = event.getIntegerValueField(.keyboardEventKeycode)
            let flags = event.flags.intersection([.maskCommand, .maskControl, .maskAlternate, .maskShift])
            if key == 8 && (flags == .maskCommand || flags == .maskControl) {
                if event.getIntegerValueField(.keyboardEventAutorepeat) == 0 {
                    let now = ProcessInfo.processInfo.systemUptime
                    if now - app.lastCopy < 0.65 && app.lastCopy > 0 {
                        app.lastCopy = 0
                        app.pending?.cancel()
                        let work = DispatchWorkItem { app.translateClipboard() }
                        app.pending = work
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.18, execute: work)
                    } else { app.lastCopy = now }
                }
            } else {
                app.lastCopy = 0
                if key == 53 { app.pending?.cancel(); app.panel.orderOut(nil) }
            }
            return Unmanaged.passUnretained(event)
        }
        guard let created = CGEvent.tapCreate(tap: .cgSessionEventTap, place: .headInsertEventTap,
            options: .listenOnly, eventsOfInterest: CGEventMask(1 << CGEventType.keyDown.rawValue),
            callback: callback, userInfo: Unmanaged.passUnretained(self).toOpaque()) else { return false }
        tap = created
        tapSource = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, created, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), tapSource, .commonModes)
        CGEvent.tapEnable(tap: created, enable: true)
        return true
    }
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.run()
