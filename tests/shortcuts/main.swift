import AppKit
import Carbon
func check(_ value: Bool, _ message: String) { if !value { fatalError(message) } }
let ctrlSpace = InputBinding.fromKey(code:49,flags:.maskControl,characters:" ")
check(ctrlSpace == .superwhisper,"Control-Space must exactly match Superwhisper carbon settings")
check(InputBinding.fromKey(code:0,flags:[],characters:"a") == nil,"Ordinary typing must not become a hotkey")
check(InputBinding.fromKey(code:0,flags:.maskShift,characters:"A") == nil,"Shift-only typing must not become a hotkey")
check(InputBinding.fromKey(code:53,flags:.maskCommand,characters:nil) == nil,"Escape is reserved for cancel")
check(InputBinding.fromKey(code:122,flags:[],characters:nil)?.label == "F1","Function key capture")
check(InputBinding.fromKey(code:0,flags:[.maskCommand,.maskAlternate],characters:"a")?.modifiers == UInt32(cmdKey | optionKey),"Modifier conversion")
check(InputBinding.fromMouse(button:0) == nil && InputBinding.fromMouse(button:1) == nil,"Primary and secondary clicks must not be captured")
check(InputBinding.fromMouse(button:2)?.label == "Middle mouse button","Middle button")
check(InputBinding.fromMouse(button:3)?.code == 3,"Physical side button mapping")
let saved = InputBinding.fromMouse(button:4)!
check(try! JSONDecoder().decode(InputBinding.self,from:JSONEncoder().encode(saved)) == saved,"Binding persistence roundtrip")
let manager = ShortcutManager()
var presses = 0; var releases = 0
manager.onPress = { presses += 1 }; manager.onRelease = { releases += 1 }
manager.press(); manager.press(); manager.release(); manager.release()
check(presses == 1 && releases == 1,"Repeated down/up events must not double-toggle")
check(InputBinding.fromKey(code:9,flags:[.maskCommand,.maskControl],characters:"v") == nil,"Paste last shortcut is reserved")
print("12 shortcut checks passed: keyboard, mouse, persistence, press/release deduplication")
