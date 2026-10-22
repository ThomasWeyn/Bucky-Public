import AppKit
import SwiftUI
import AVFoundation
import Carbon

// Written by build.sh for this clone; no dependency on another Mac's username.
let projectRoot = Bundle.main.object(forInfoDictionaryKey: "BuckyProjectRoot") as? String
    ?? URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().path

final class VoiceState: ObservableObject {
    @Published var phase = "Starting speech engine…"
    @Published var detail = "Parakeet v3 · on this Mac"
    @Published var ready = false
    @Published var recording = false
    @Published var busy = false
    @Published var level: CGFloat = 0
    @Published var elapsed = 0
    @Published var history: [Recent] = []
    @Published var lastResult: Recent?
    @Published var historyError = ""
    @Published var keepHistory = UserDefaults.standard.object(forKey: "keepHistory") as? Bool ?? true {
        didSet { UserDefaults.standard.set(keepHistory, forKey: "keepHistory") }
    }
    #if UI_TESTING
    let historyStore = HistoryStore(url: URL(fileURLWithPath: projectRoot + "/tests/ui-history.json"))
    #else
    let historyStore = HistoryStore()
    #endif
    var historyWritable = true
    init() {
        do { history = try historyStore.load(); if FileManager.default.fileExists(atPath: historyStore.url.path) { try historyStore.save(history) } }
        catch { historyWritable = false; historyError = "History could not be read. Your saved file has been left untouched. " + error.localizedDescription }
        #if UI_TESTING
        if history.isEmpty {
            history = [Recent(text: "Design preview: Goedemorgen, kunnen we de afspraak naar donderdag verplaatsen? Dan stuur ik de documenten van tevoren door.", duration: 12, application: "Preview · Mail"), Recent(text: "Design preview: Please send the updated project notes before our meeting tomorrow. I would like to review the next steps.", date: Date().addingTimeInterval(-3600), duration: 9, application: "Preview · Notes"), Recent(text: "Design preview: Ik heb de feedback verwerkt. The next step is to test the new version together, zodat we weten wat goed werkt.", date: Date().addingTimeInterval(-86400), duration: 15, application: "Preview · Editor")]
        }
        #endif

    }
    @discardableResult func saveHistory(_ entries: [Recent]) -> Bool {
        guard historyWritable else { return false }
        do { try historyStore.save(entries); history = historyStore.retained(entries); historyError = ""; return true }
        catch { historyError = "Could not save history: " + error.localizedDescription; return false }
    }
    func addResult(_ entry: Recent) {
        lastResult = entry
        if keepHistory { saveHistory([entry] + history) }
    }
    @Published var accessibility = AXIsProcessTrusted()
    @Published var microphone = AVCaptureDevice.authorizationStatus(for: .audio) == .authorized
    @Published var autoPaste = UserDefaults.standard.object(forKey: "autoPaste") as? Bool ?? true {
        didSet { UserDefaults.standard.set(autoPaste, forKey: "autoPaste") }
    }
    @Published var glossary = UserDefaults.standard.string(forKey: "glossary") ?? "super whisper = Superwhisper" {
        didSet { UserDefaults.standard.set(glossary, forKey: "glossary") }
    }
    @Published var shortcutLabel = "⌃ Space"
    @Published var shortcutStatus = ""
    @Published var capturingShortcut = false
    @Published var holdToTalk = UserDefaults.standard.bool(forKey: "holdToTalk") {
        didSet { UserDefaults.standard.set(holdToTalk, forKey: "holdToTalk") }
    }
    @Published var soundEffects = UserDefaults.standard.object(forKey: "soundEffects") as? Bool ?? true {
        didSet { UserDefaults.standard.set(soundEffects, forKey: "soundEffects") }
    }
    @Published var atLogin = false
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    let state = VoiceState()
    var item: NSStatusItem!
    var window: NSWindow!
    var hud: NSPanel!
    var worker: Process?
    var input: FileHandle?
    var recorder: AVAudioRecorder?
    var recordingURL: URL?
    var timer: Timer?
    var watchdog: Timer?
    let shortcuts = ShortcutManager()
    var cancelKey: EventHotKeyRef?
    var target: NSRunningApplication?
    var pendingID: String?
    var started = Date()
    var quitting = false
    var generation = 0
    var launchURL: URL {
        FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/LaunchAgents/nl.quickmouse.spreek.plist")
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        // A second manual launch must not create another recorder / hotkey owner.
        if NSRunningApplication.runningApplications(withBundleIdentifier: "nl.quickmouse.spreek").count > 1 { NSApp.terminate(nil); return }
        item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        item.button?.image = NSImage(systemSymbolName: "waveform", accessibilityDescription: "Bucky")
        item.button?.target = self
        item.button?.action = #selector(showWindow)
        window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 1000, height: 740), styleMask: [.titled, .closable, .miniaturizable, .resizable], backing: .buffered, defer: false)
        window.title = "Bucky"
        window.minSize = NSSize(width: 860, height: 650)
        window.setFrameAutosaveName("BuckyWorkspace")
        window.titlebarAppearsTransparent = true
        window.backgroundColor = NSColor(calibratedRed:0.96, green:0.96, blue:0.94, alpha:1)
        window.isReleasedWhenClosed = false
        window.contentView = NSHostingView(rootView: MainView(state: state, controller: self))
        window.center()
        hud = NSPanel(contentRect: NSRect(x: 0, y: 0, width: 340, height: 80), styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        hud.isFloatingPanel = true
        hud.level = .floating
        hud.backgroundColor = .clear
        hud.isOpaque = false
        hud.hasShadow = true
        hud.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        hud.contentView = NSHostingView(rootView: RecordingHUD(state: state, controller: self))
        Timer.scheduledTimer(withTimeInterval: 3600, repeats: true) { [weak self] _ in
            guard let self, self.state.historyWritable else { return }
            if self.state.historyStore.retained(self.state.history) != self.state.history { self.state.saveHistory(self.state.history) }
        }
        #if !UI_TESTING
        installHotkey()
        #endif
        state.atLogin = FileManager.default.fileExists(atPath: launchURL.path)
        #if UI_TESTING
        window.title = "Bucky UI Preview · sample data"
        state.ready = true
        state.phase = "Design preview"
        showWindow()
        #else
        startWorker()
        #endif
        if !UserDefaults.standard.bool(forKey: "hasOpened") {
            showWindow()
            UserDefaults.standard.set(true, forKey: "hasOpened")
        }
        NSWorkspace.shared.notificationCenter.addObserver(self, selector: #selector(sleeping), name: NSWorkspace.willSleepNotification, object: nil)
        Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] _ in
            guard let self else { return }
            self.state.accessibility = AXIsProcessTrusted()
            self.shortcuts.ensureTap()
            self.state.microphone = AVCaptureDevice.authorizationStatus(for: .audio) == .authorized
        }
    }

    func installHotkey() {
        // Escape is registered only during a recording; user shortcuts live separately.
        var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        InstallEventHandler(GetApplicationEventTarget(), { _, event, context in
            guard let event, let context else { return noErr }
            var id = EventHotKeyID()
            GetEventParameter(event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID), nil, MemoryLayout<EventHotKeyID>.size, nil, &id)
            guard id.signature == 0x5350524B && id.id == 2 else { return OSStatus(eventNotHandledErr) }
            Unmanaged<AppDelegate>.fromOpaque(context).takeUnretainedValue().cancel()
            return noErr
        }, 1, &spec, Unmanaged.passUnretained(self).toOpaque(), nil)
        shortcuts.onPress = { [weak self] in
            guard let self else { return }
            if !self.state.holdToTalk || !self.state.recording { self.toggle() }
        }
        shortcuts.onRelease = { [weak self] in
            guard let self, self.state.holdToTalk, self.state.recording else { return }
            self.stop()
        }
        shortcuts.onChange = { [weak self] label, status, capturing in
            self?.state.shortcutLabel = label
            self?.state.shortcutStatus = status
            self?.state.capturingShortcut = capturing
        }
        shortcuts.start()
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool { showWindow(); return true }

    @objc func showWindow() {
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
    }
    func showHUD() {
        let screen = NSScreen.main ?? NSScreen.screens[0]
        hud.setFrameOrigin(NSPoint(x: screen.visibleFrame.midX - 170, y: screen.visibleFrame.minY + 48))
        hud.orderFrontRegardless()
    }
    func requestMicrophone() {
        AVCaptureDevice.requestAccess(for: .audio) { allowed in
            DispatchQueue.main.async {
                self.state.microphone = allowed
                if !allowed { self.openSettings("Privacy_Microphone") }
            }
        }
    }
    func requestAccessibility() {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        state.accessibility = AXIsProcessTrustedWithOptions(options)
        if !state.accessibility { openSettings("Privacy_Accessibility") }
    }
    func openSettings(_ anchor: String) {
        NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?\(anchor)")!)
    }
    func toggleLogin() {
        do {
            if state.atLogin {
                try FileManager.default.removeItem(at: launchURL)
            } else {
                try FileManager.default.createDirectory(at: launchURL.deletingLastPathComponent(), withIntermediateDirectories: true)
                let plist: [String: Any] = ["Label": "nl.quickmouse.spreek", "ProgramArguments": ["/usr/bin/open", "-g", Bundle.main.bundlePath], "RunAtLoad": true]
                let data = try PropertyListSerialization.data(fromPropertyList: plist, format: .xml, options: 0)
                try data.write(to: launchURL, options: .atomic)
            }
            state.atLogin = FileManager.default.fileExists(atPath: launchURL.path)
        } catch { state.detail = "Could not change login setting: \(error.localizedDescription)" }
    }
    func startWorker() {
        guard !state.recording && !state.busy else { return }
        generation += 1
        let currentGeneration = generation
        worker?.terminationHandler = nil
        worker?.terminate()
        state.ready = false
        state.phase = "Loading local speech model…"
        let process = Process()
        process.executableURL = URL(fileURLWithPath: projectRoot + "/.venv/bin/python")
        process.arguments = ["-u", projectRoot + "/worker.py"]
        var env = ProcessInfo.processInfo.environment
        env["HF_HUB_OFFLINE"] = "1"
        env["HF_HUB_DISABLE_TELEMETRY"] = "1"
        process.environment = env
        let stdin = Pipe(), stdout = Pipe()
        process.standardInput = stdin
        process.standardOutput = stdout
        process.standardError = FileHandle.nullDevice
        input = stdin.fileHandleForWriting
        process.terminationHandler = { [weak self] _ in
            DispatchQueue.main.async {
                guard let self, !self.quitting, self.generation == currentGeneration else { return }
                self.state.ready = false
                self.state.busy = false
                self.state.phase = "Speech engine stopped"
                self.state.detail = "Choose Restart engine to try again."
                self.cancel()
            }
        }
        do {
            try process.run()
            worker = process
            DispatchQueue.global(qos: .userInitiated).async { [weak self] in
                var buffer = Data()
                while true {
                    let bytes = stdout.fileHandleForReading.availableData
                    if bytes.isEmpty { break }
                    buffer.append(bytes)
                    while let end = buffer.firstIndex(of: 10) {
                        let line = buffer[..<end]
                        buffer.removeSubrange(...end)
                        if let message = try? JSONSerialization.jsonObject(with: line) as? [String: Any] {
                            DispatchQueue.main.async {
                                guard let self, self.generation == currentGeneration else { return }
                                self.receive(message)
                            }
                        }
                    }
                }
            }
        } catch { state.phase = "Could not start speech engine"; state.detail = error.localizedDescription }
    }
    func receive(_ message: [String: Any]) {
        switch message["event"] as? String {
        case "ready":
            state.ready = true; state.phase = "Ready when you are"; state.detail = "Dutch + English · automatic detection · fully local"
        case "result", "error":
            guard let id = message["id"] as? String, id == pendingID else { return }
            pendingID = nil; watchdog?.invalidate(); state.busy = false
            deleteRecording()
            if let text = message["text"] as? String {
                let cleaned = applyGlossary(text)
                if cleaned.isEmpty { state.phase = "No speech detected"; state.detail = "Try again, or check your microphone in System Settings." }
                else {
                    state.addResult(Recent(text: cleaned, duration: Double(state.elapsed), application: target?.localizedName ?? "Bucky"))
                    deliver(cleaned)
                    let seconds = message["seconds"] as? Double ?? 0
                    state.phase = String(format: "Done in %.1f seconds", seconds)
                }
            } else { state.phase = "Transcription failed"; state.detail = message["message"] as? String ?? "Please try again." }
            hud.orderOut(nil)
            item.button?.image = NSImage(systemSymbolName: "waveform", accessibilityDescription: "Bucky")
        case "fatal": state.phase = "Speech engine unavailable"; state.detail = message["message"] as? String ?? "Restart engine to try again."
        default: break
        }
    }
    func applyGlossary(_ text: String) -> String {
        var result = text
        for line in state.glossary.split(separator: "\n") {
            let pair = line.split(separator: "=", maxSplits: 1).map { $0.trimmingCharacters(in: .whitespaces) }
            if pair.count == 2 && !pair[0].isEmpty {
                let pattern = "(?i)(?<![\\p{L}\\p{N}])" + NSRegularExpression.escapedPattern(for: pair[0]) + "(?![\\p{L}\\p{N}])"
                if let regex = try? NSRegularExpression(pattern: pattern) {
                    result = regex.stringByReplacingMatches(in: result, range: NSRange(result.startIndex..., in: result), withTemplate: NSRegularExpression.escapedTemplate(for: pair[1]))
                }
            }
        }
        return result
    }
    func toggle() {
        if state.recording { stop(); return }
        guard state.ready, !state.busy else { return }
        guard AVCaptureDevice.authorizationStatus(for: .audio) == .authorized else { requestMicrophone(); return }
        target = NSWorkspace.shared.frontmostApplication
        if target?.processIdentifier == ProcessInfo.processInfo.processIdentifier { target = nil }
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("nl.quickmouse.spreek", isDirectory: true)
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
            let url = directory.appendingPathComponent(UUID().uuidString + ".wav")
            let settings: [String: Any] = [AVFormatIDKey: kAudioFormatLinearPCM, AVSampleRateKey: 16000.0, AVNumberOfChannelsKey: 1, AVLinearPCMBitDepthKey: 16, AVLinearPCMIsFloatKey: false, AVLinearPCMIsBigEndianKey: false]
            recorder = try AVAudioRecorder(url: url, settings: settings)
            recorder?.isMeteringEnabled = true
            guard recorder?.record() == true else { throw NSError(domain: "Bucky", code: 1, userInfo: [NSLocalizedDescriptionKey: "Microphone could not start. Check your input device."]) }
            recordingURL = url
            try? FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
            if state.soundEffects { NSSound(named: "Tink")?.play() }
            started = Date(); state.elapsed = 0; state.recording = true
            state.phase = "Listening…"; state.detail = state.holdToTalk ? "Release your shortcut to finish. Escape cancels." : "Press \(state.shortcutLabel) to finish. Escape cancels."
            item.button?.image = NSImage(systemSymbolName: "mic.fill", accessibilityDescription: "Recording")
            RegisterEventHotKey(UInt32(kVK_Escape), 0, EventHotKeyID(signature: 0x5350524B, id: 2), GetApplicationEventTarget(), 0, &cancelKey)
            showHUD()
            timer = Timer.scheduledTimer(withTimeInterval: 0.08, repeats: true) { [weak self] _ in
                guard let self else { return }
                self.recorder?.updateMeters()
                self.state.level = CGFloat(max(0, min(1, ((self.recorder?.averagePower(forChannel: 0) ?? -60) + 60) / 60)))
                self.state.elapsed = Int(Date().timeIntervalSince(self.started))
                // Elapsed time only updates the display; recording ends on user action.
            }
        } catch { state.phase = "Microphone unavailable"; state.detail = error.localizedDescription; deleteRecording() }
    }
    func stop() {
        guard state.recording else { return }
        state.elapsed = Int(Date().timeIntervalSince(started))
        recorder?.stop(); recorder = nil; timer?.invalidate()
        if state.soundEffects { NSSound(named: "Pop")?.play() }
        state.recording = false; state.level = 0
        if let key = cancelKey { UnregisterEventHotKey(key); cancelKey = nil }
        guard let url = recordingURL else { return }
        state.busy = true; state.phase = "Transcribing on your Mac…"
        let id = UUID().uuidString; pendingID = id
        do {
            var data = try JSONSerialization.data(withJSONObject: ["id": id, "path": url.path])
            data.append(10)
            try input?.write(contentsOf: data)
            watchdog = Timer.scheduledTimer(withTimeInterval: max(120, Double(state.elapsed)), repeats: false) { [weak self] _ in
                guard let self else { return }
                self.cancel(); self.state.phase = "Transcription timed out"; self.state.detail = "Restart the engine, then try again."
            }
        } catch { cancel(); state.phase = "Speech engine disconnected" }
    }
    func cancel() {
        recorder?.stop(); recorder = nil; timer?.invalidate(); watchdog?.invalidate()
        let wasBusy = state.busy
        pendingID = nil; state.recording = false; state.busy = false; state.level = 0
        if let key = cancelKey { UnregisterEventHotKey(key); cancelKey = nil }
        deleteRecording(); hud?.orderOut(nil)
        item?.button?.image = NSImage(systemSymbolName: "waveform", accessibilityDescription: "Bucky")
        if state.ready { state.phase = "Ready when you are" }
        if wasBusy && !quitting { startWorker() }
    }
    @objc func sleeping() { if state.recording || state.busy { cancel() } }
    func deleteRecording() {
        if let url = recordingURL { try? FileManager.default.removeItem(at: url) }
        recordingURL = nil
    }
    func copy(_ text: String) {
        NSPasteboard.general.clearContents(); NSPasteboard.general.setString(text, forType: .string)
    }
    func deliver(_ text: String) {
        copy(text)
        guard state.autoPaste, AXIsProcessTrusted(), let target,
              NSWorkspace.shared.frontmostApplication?.processIdentifier == target.processIdentifier else {
            state.detail = "Copied. Press ⌘V where you want your text."; return
        }
        // Never activate another application or press Return; paste only to the still-current app.
        let source = CGEventSource(stateID: .combinedSessionState)
        let down = CGEvent(keyboardEventSource: source, virtualKey: 9, keyDown: true)
        let up = CGEvent(keyboardEventSource: source, virtualKey: 9, keyDown: false)
        down?.flags = .maskCommand; up?.flags = .maskCommand
        down?.post(tap: .cghidEventTap); up?.post(tap: .cghidEventTap)
        state.detail = "Paste sent to \(target.localizedName ?? "your app"). Text is also on your clipboard."
    }
    func applicationWillTerminate(_ notification: Notification) {
        quitting = true; cancel(); worker?.terminationHandler = nil; worker?.terminate()
    }
}

struct RecordingHUD: View {
    @ObservedObject var state: VoiceState
    let controller: AppDelegate
    var body: some View {
        HStack(spacing: 14) {
            if state.busy { ProgressView().controlSize(.small) }
            else {
                HStack(spacing: 3) {
                    ForEach(0..<7) { i in
                        Capsule().fill(Color(red: 0.3, green: 0.85, blue: 0.66)).frame(width: 3, height: 5 + state.level * CGFloat([16, 26, 34, 40, 28, 20, 12][i]))
                    }
                }.frame(width: 42, height: 40)
            }
            VStack(alignment: .leading, spacing: 3) {
                Text(state.busy ? "Finding your words…" : "Listening · \(state.elapsed)s").font(.system(size: 13, weight: .semibold))
                Text(state.busy ? "Locally, on your Mac" : (state.holdToTalk ? "Release to finish" : "\(state.shortcutLabel) to finish")).font(.system(size: 11)).foregroundStyle(.secondary)
            }
            Spacer()
            Button(action: { controller.cancel() }) { Image(systemName: "xmark.circle.fill") }.buttonStyle(.plain).help("Cancel dictation")
        }.padding(18).frame(width: 304, height: 44).background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 22)).environment(\.colorScheme, .dark)
    }
}

let application = NSApplication.shared
let delegate = AppDelegate()
application.delegate = delegate
application.run()
