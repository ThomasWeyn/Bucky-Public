import AppKit
import Carbon

struct InputBinding: Codable, Equatable {
    var kind: String
    var code: UInt32
    var modifiers: UInt32
    var label: String
    static let superwhisper = InputBinding(kind: "key", code: 49, modifiers: UInt32(controlKey), label: "⌃ Space")
    static func fromKey(code: UInt32, flags: CGEventFlags, characters: String?) -> InputBinding? {
        if code == 53 { return nil }
        var modifiers: UInt32 = 0
        var title = ""
        for (flag, carbon, glyph) in [(CGEventFlags.maskControl, controlKey, "⌃"), (.maskAlternate, optionKey, "⌥"), (.maskShift, shiftKey, "⇧"), (.maskCommand, cmdKey, "⌘")] {
            if flags.contains(flag) { modifiers |= UInt32(carbon); title += glyph + " " }
        }
        // Reserved for pasting the last dictation; never replace the recording binding with it.
        if code == 9 && modifiers == UInt32(controlKey | cmdKey) { return nil }
        let functionKeys: [UInt32: String] = [122:"F1",120:"F2",99:"F3",118:"F4",96:"F5",97:"F6",98:"F7",100:"F8",101:"F9",109:"F10",103:"F11",111:"F12",105:"F13",107:"F14",113:"F15",106:"F16",64:"F17",79:"F18",80:"F19",90:"F20"]
        guard modifiers & UInt32(controlKey | optionKey | cmdKey) != 0 || functionKeys[code] != nil else { return nil }
        let names: [UInt32:String] = [49:"Space",36:"Return",48:"Tab",51:"Delete",123:"←",124:"→",125:"↓",126:"↑"]
        let key = names[code] ?? functionKeys[code] ?? characters?.uppercased() ?? "Key \(code)"
        return InputBinding(kind:"key", code:code, modifiers:modifiers, label:title + key)
    }
    static func fromMouse(button: UInt32) -> InputBinding? {
        guard button >= 2 else { return nil }
        return InputBinding(kind:"mouse", code:button, modifiers:0, label:button == 2 ? "Middle mouse button" : "Mouse button \(button + 1)")
    }
}

final class ShortcutManager {
    var onPress: (() -> Void)?
    var onRelease: (() -> Void)?
    var onChange: ((String, String, Bool) -> Void)?
    var binding: InputBinding = .superwhisper
    var mouseBinding: InputBinding?
    var primary: EventHotKeyRef?
    var fallback: EventHotKeyRef?
    var handler: EventHandlerRef?
    var tap: CFMachPort?
    var source: CFRunLoopSource?
    var captureTimer: Timer?
    var capturing = false
    var status = ""
    var pressed = false

    init() {
        if let data = UserDefaults.standard.data(forKey:"inputBinding"), let saved = try? JSONDecoder().decode(InputBinding.self, from:data) { binding = saved }
    }
    func start() {
        if let data = UserDefaults.standard.data(forKey:"mouseBinding") { mouseBinding = try? JSONDecoder().decode(InputBinding.self, from:data) }
        if binding.kind == "mouse" { mouseBinding = binding; binding = .superwhisper }

        var specs = [EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed)), EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyReleased))]
        InstallEventHandler(GetApplicationEventTarget(), { _, event, context in
            guard let event, let context else { return noErr }
            let manager = Unmanaged<ShortcutManager>.fromOpaque(context).takeUnretainedValue()
            var id = EventHotKeyID()
            GetEventParameter(event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID), nil, MemoryLayout<EventHotKeyID>.size, nil, &id)
            guard id.signature == 0x424B5953 else { return OSStatus(eventNotHandledErr) }
            if !manager.capturing {
                if GetEventKind(event) == UInt32(kEventHotKeyPressed) { manager.press() } else { manager.release() }
            }
            return noErr
        }, 2, &specs, Unmanaged.passUnretained(self).toOpaque(), &handler)
        RegisterEventHotKey(49, UInt32(controlKey | optionKey), EventHotKeyID(signature:0x424B5953,id:2), GetApplicationEventTarget(), 0, &fallback)
        bind(binding)
        ensureTap()
    }
    func publish() { onChange?(binding.label + (mouseBinding.map { " / " + $0.label } ?? ""), status, capturing) }
    func bind(_ value: InputBinding) {
        if value.kind == "mouse" {
            mouseBinding = value
            if let data = try? JSONEncoder().encode(value) { UserDefaults.standard.set(data,forKey:"mouseBinding") }
            ensureTap()
            status = tap == nil ? "Enable Accessibility to use your mouse button." : "Mouse button added. The keyboard shortcut also remains active."
            publish()
            return
        }
        if let primary { UnregisterEventHotKey(primary); self.primary = nil }
        binding = value
        if value.kind == "key" {
            if value.code == 49 && value.modifiers == UInt32(controlKey | optionKey) { status = "Shortcut ready." }
            else {
                let result = RegisterEventHotKey(value.code, value.modifiers, EventHotKeyID(signature:0x424B5953,id:1), GetApplicationEventTarget(), 0, &primary)
                status = result == noErr ? "Shortcut ready." : "\(value.label) is in use by another app. Quit Superwhisper, then click Retry. ⌃ ⌥ Space remains available."
            }
        } else {
            ensureTap()
            status = tap == nil ? "Enable Accessibility to use your mouse button." : "Mouse button ready. Its normal click is suppressed while Bucky is running."
        }
        if let data = try? JSONEncoder().encode(value) { UserDefaults.standard.set(data,forKey:"inputBinding") }
        if !NSRunningApplication.runningApplications(withBundleIdentifier:"com.superduper.superwhisper").isEmpty {
            status += " Superwhisper is running; it may respond to the same shortcut. Quit it before testing Bucky."
        }
        publish()
    }
    func clearMouse() {
        mouseBinding = nil
        UserDefaults.standard.removeObject(forKey:"mouseBinding")
        pressed = false
        status = "Mouse shortcut removed. Keyboard shortcut remains active."
        publish()
    }
    func ensureTap() {
        guard tap == nil, AXIsProcessTrusted() else { return }
        let mask = [CGEventType.keyDown, .otherMouseDown, .otherMouseUp].reduce(CGEventMask(0)) { $0 | (1 << $1.rawValue) }
        tap = CGEvent.tapCreate(tap: .cgSessionEventTap, place: .headInsertEventTap, options: .defaultTap, eventsOfInterest:mask, callback: { _, type, event, context in
            guard let context else { return Unmanaged.passUnretained(event) }
            let manager = Unmanaged<ShortcutManager>.fromOpaque(context).takeUnretainedValue()
            if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
                if let tap = manager.tap { CGEvent.tapEnable(tap:tap,enable:true) }
                manager.pressed = false
                manager.onRelease?()
                return Unmanaged.passUnretained(event)
            }
            return manager.handle(type:type,event:event) ? nil : Unmanaged.passUnretained(event)
        }, userInfo:Unmanaged.passUnretained(self).toOpaque())
        if let tap {
            source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault,tap,0)
            CFRunLoopAddSource(CFRunLoopGetMain(),source,.commonModes)
            CGEvent.tapEnable(tap:tap,enable:true)
            if mouseBinding != nil { status = "Mouse button ready. Its normal click is suppressed while Bucky is running."; publish() }
        }
    }
    func beginCapture() {
        ensureTap()
        guard tap != nil else { status = "Enable Accessibility, then try Record shortcut again."; publish(); return }
        capturing = true; pressed = false
        status = "Press a keyboard shortcut or a side/middle mouse button. Escape cancels."
        captureTimer?.invalidate()
        captureTimer = Timer.scheduledTimer(withTimeInterval:15,repeats:false) { [weak self] _ in self?.cancelCapture() }
        publish()
    }
    func cancelCapture() { capturing = false; captureTimer?.invalidate(); status = "Shortcut recording cancelled."; publish() }
    func finishCapture(_ value: InputBinding) { capturing = false; captureTimer?.invalidate(); bind(value) }
    func handle(type: CGEventType, event: CGEvent) -> Bool {
        if capturing {
            if type == .keyDown {
                let code = UInt32(event.getIntegerValueField(.keyboardEventKeycode))
                if code == 53 { cancelCapture(); return true }
                if code == 9, event.flags.intersection([.maskControl, .maskAlternate, .maskShift, .maskCommand]) == [.maskControl, .maskCommand] {
                    status = "Control–Command–V is reserved for Paste last dictation."; publish(); return true
                }
                if let value = InputBinding.fromKey(code:code, flags:event.flags, characters:NSEvent(cgEvent:event)?.charactersIgnoringModifiers) { finishCapture(value) }
                else { status = "Use Control, Option or Command with a key, an F-key, or a side/middle mouse button."; publish() }
                return true
            }
            if type == .otherMouseDown, let value = InputBinding.fromMouse(button:UInt32(event.getIntegerValueField(.mouseEventButtonNumber))) { finishCapture(value); return true }
        }
        if let mouseBinding, (type == .otherMouseDown || type == .otherMouseUp), UInt32(event.getIntegerValueField(.mouseEventButtonNumber)) == mouseBinding.code {
            if type == .otherMouseDown { press() } else { release() }
            return true
        }
        return false
    }
    func press() { guard !pressed else { return }; pressed = true; onPress?() }
    func release() { guard pressed else { return }; pressed = false; onRelease?() }
}
