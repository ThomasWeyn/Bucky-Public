import SwiftUI
import AppKit

private let ink = Color(red:0.12,green:0.17,blue:0.16)
private let leaf = Color(red:0.19,green:0.39,blue:0.31)
private let paper = Color(red:0.97,green:0.97,blue:0.95)
private let muted = Color(red:0.40,green:0.45,blue:0.42)

enum Destination: String, CaseIterable {
    case dictate = "Dictate", history = "History", vocabulary = "Vocabulary", snippets = "Snippets", settings = "Settings"
    var shortcut: Int { switch self { case .dictate: return 1; case .history: return 2; case .vocabulary: return 3; case .settings: return 4; case .snippets: return 5 } }
    var icon: String { switch self { case .dictate: return "waveform"; case .history: return "clock.arrow.circlepath"; case .vocabulary: return "text.book.closed"; case .snippets: return "text.badge.plus"; case .settings: return "slider.horizontal.3" } }
    var subtitle: String { switch self { case .dictate: return "Make room for your thoughts."; case .history: return "Find the words you’ve already spoken."; case .vocabulary: return "Names and spellings, the way you like them."; case .snippets: return "A short phrase. Your full text."; case .settings: return "A few small things. Just how you like them." } }
}

struct Surface<Content: View>: View {
    @ViewBuilder var content: Content
    var body: some View { content.padding(22).frame(maxWidth:.infinity,alignment:.leading).background(.white,in:RoundedRectangle(cornerRadius:18)).overlay(RoundedRectangle(cornerRadius:18).stroke(ink.opacity(0.07),lineWidth:1)) }
}

struct MainView: View {
    @ObservedObject var state: VoiceState
    let controller: AppDelegate
    @State private var destination: Destination = .dictate
    @State private var query = ""
    @State private var selected: UUID?
    @State private var deleted: Recent?
    @State private var confirmClear = false
    @State private var copied: UUID?
    @State private var editingSnippet: Snippet?
    @State private var deletingSnippet: Snippet?
    var matches: [Recent] { state.history.filter { query.isEmpty || $0.text.localizedCaseInsensitiveContains(query) || $0.application.localizedCaseInsensitiveContains(query) } }
    var selectedEntry: Recent? { matches.first { $0.id == selected } ?? matches.first }

    var body: some View {
        HStack(spacing:0) {
            sidebar
            VStack(alignment:.leading,spacing:0) {
                header
                if !state.historyError.isEmpty { Text(state.historyError).font(.callout).foregroundStyle(.red).padding(.horizontal,32).padding(.bottom,12) }
                switch destination {
                case .dictate: dictate
                case .history: history
                case .vocabulary: vocabulary
                case .snippets: snippets
                case .settings: settings
                }
            }.frame(maxWidth:.infinity,maxHeight:.infinity).background(paper)
        }.frame(minWidth:860,minHeight:620).foregroundStyle(ink).tint(leaf).environment(\.colorScheme,.light)
        .alert("Delete all saved dictations?",isPresented:$confirmClear) {
            Button("Cancel",role:.cancel) {}
            Button("Delete all",role:.destructive) { state.saveHistory([]); deleted = nil }
        } message: { Text("This removes the local transcript history. It does not clear text you’ve pasted into other apps or your clipboard.") }
    }
    var sidebar: some View {
        VStack(alignment:.leading,spacing:28) {
            HStack(spacing:10) {
                Image(systemName:"waveform").font(.system(size:22,weight:.bold)).foregroundStyle(.white).frame(width:42,height:42).background(leaf,in:RoundedRectangle(cornerRadius:14))
                Text("bucky").font(.system(size:29,weight:.bold,design:.rounded)).tracking(-1)
            }.padding(.top,13)
            VStack(spacing:6) {
                ForEach(Array(Destination.allCases.enumerated()),id:\.element) { index, page in
                    Button { destination = page } label: {
                        HStack(spacing:12) {
                            Image(systemName:page.icon).font(.system(size:16,weight:.medium)).frame(width:22)
                            Text(page.rawValue).lineLimit(1).font(.system(size:14,weight:destination == page ? .semibold : .medium))
                            Spacer()
                            if page == .history && !state.history.isEmpty { Text("\(state.history.count)").font(.system(size:11,weight:.semibold)).padding(.horizontal,7).padding(.vertical,3).background(ink.opacity(0.06),in:Capsule()) }
                        }.padding(.horizontal,13).padding(.vertical,12).foregroundStyle(destination == page ? leaf : muted).background(destination == page ? Color.white : .clear,in:RoundedRectangle(cornerRadius:11)).contentShape(Rectangle())
                    }.buttonStyle(.plain).keyboardShortcut(KeyEquivalent(Character(String(page.shortcut))),modifiers:.command)
                }
            }
            Spacer()
            VStack(alignment:.leading,spacing:9) {
                HStack(spacing:7) { Circle().fill(state.ready ? leaf : .orange).frame(width:6,height:6); Text(state.ready ? "Ready on your Mac" : "Engine starting").font(.system(size:12,weight:.medium)) }
                Text("Dutch + English\nNo cloud. Just your words.").font(.system(size:11)).foregroundStyle(muted).lineSpacing(4)
            }.padding(14).frame(maxWidth:.infinity,alignment:.leading).background(leaf.opacity(0.06),in:RoundedRectangle(cornerRadius:12))
            HStack { Text("BUCKY  /  0.3").font(.system(size:9,weight:.semibold,design:.monospaced)).tracking(1).foregroundStyle(muted); Spacer(); Button { NSApp.terminate(nil) } label: { Image(systemName:"power") }.buttonStyle(.plain).help("Quit Bucky") }
        }.padding(20).frame(width:210).frame(maxHeight:.infinity).background(Color(red:0.92,green:0.94,blue:0.91))
    }
    var header: some View {
        HStack(alignment:.center) {
            VStack(alignment:.leading,spacing:5) {
                Text(destination.rawValue).font(.system(size:26,weight:.semibold,design:.rounded))
                Text(destination.subtitle).font(.system(size:12)).foregroundStyle(muted)
            }
            Spacer()
            Label("LOCAL",systemImage:"lock.shield").font(.system(size:10,weight:.semibold)).tracking(1).foregroundStyle(leaf).padding(.horizontal,12).padding(.vertical,8).background(leaf.opacity(0.07),in:Capsule())
        }.padding(.horizontal,32).padding(.vertical,25)
    }
    var dictate: some View {
        ScrollView {
            VStack(alignment:.leading,spacing:20) {
                if !state.microphone || !state.accessibility { setupBanner }
                VStack(spacing:18) {
                    Text(state.recording ? "Listening to you." : state.busy ? "Finding your words." : "A little less typing.").font(.system(size:34,weight:.semibold,design:.rounded)).tracking(-1)
                    Text(state.recording ? "Take your time. Finish when you’re ready." : state.busy ? "Transcribing privately on this Mac." : "Speak naturally. Switch languages. Keep your flow.").font(.system(size:13)).foregroundStyle(muted)
                    ZStack {
                        Circle().fill(leaf.opacity(0.05)).frame(width:128,height:128)
                        Circle().stroke(leaf.opacity(0.12),lineWidth:1).frame(width:106,height:106)
                        Button { controller.toggle() } label: {
                            Image(systemName:state.recording ? "stop.fill" : "mic.fill").font(.system(size:30,weight:.medium)).foregroundStyle(.white).frame(width:82,height:82).background(state.recording ? Color(red:0.72,green:0.29,blue:0.24) : leaf,in:Circle())
                        }.buttonStyle(.plain).disabled(!state.ready || state.busy).help(state.recording ? "Finish dictation" : "Start dictation").accessibilityLabel(state.recording ? "Finish dictation" : "Start dictation")
                        if state.busy { ProgressView().offset(y:85) }
                    }.padding(.vertical,4)
                    Text(state.recording ? "\(state.elapsed)s · recording" : state.phase).font(.system(size:12,weight:.medium)).foregroundStyle(leaf)
                    HStack(spacing:8) {
                        Text(state.holdToTalk ? "Hold" : "Press").foregroundStyle(muted)
                        Text(state.shortcutLabel).font(.system(size:12,weight:.medium,design:.monospaced)).padding(.horizontal,10).padding(.vertical,7).background(paper,in:RoundedRectangle(cornerRadius:7))
                        Text(state.holdToTalk ? "to speak" : "to start / stop").foregroundStyle(muted)
                    }.font(.system(size:12))
                    if state.recording || state.busy { Button("Cancel dictation") { controller.cancel() }.buttonStyle(.plain).foregroundStyle(muted) }
                }.padding(.vertical,28).frame(maxWidth:.infinity).background(.white,in:RoundedRectangle(cornerRadius:22)).overlay(RoundedRectangle(cornerRadius:22).stroke(ink.opacity(0.06)))
                HStack(spacing:12) {
                    miniCard("Two languages",detail:"Dutch & English, automatically",icon:"globe")
                    Button { destination = .settings } label: { miniCard("Your shortcut",detail:"Keyboard or mouse · customise",icon:"computermouse") }.buttonStyle(.plain)
                }
                if let entry = state.lastResult ?? state.history.first {
                    HStack { Text("LATEST DICTATION").font(.system(size:10,weight:.semibold)).tracking(1).foregroundStyle(muted); Spacer(); Button("View history →") { destination = .history; selected = entry.id }.buttonStyle(.plain).font(.caption).foregroundStyle(leaf) }
                    Surface {
                        VStack(alignment:.leading,spacing:12) {
                            Text(entry.text).font(.system(size:14)).lineSpacing(5).lineLimit(4).textSelection(.enabled)
                            HStack {
                                entryMeta(entry); Spacer()
                                Button { controller.pasteLast() } label: { Label("Paste last", systemImage: "arrow.up.doc") }
                                    .buttonStyle(.bordered).font(.caption).disabled(state.recording || state.busy)
                                    .help("Use ⌃⌘V in your destination app. From Bucky, this copies the last dictation.")
                                copyButton(entry)
                            }
                        }
                    }
                }
                Text(state.detail).font(.caption).foregroundStyle(muted).textSelection(.enabled)
            }.padding(.horizontal,32).padding(.bottom,28)
        }
    }
    func miniCard(_ title: String, detail: String, icon: String) -> some View {
        HStack(spacing:12) { Image(systemName:icon).font(.system(size:20)).foregroundStyle(leaf); VStack(alignment:.leading,spacing:4) { Text(title).font(.system(size:12,weight:.semibold)); Text(detail).font(.system(size:10)).foregroundStyle(muted) }; Spacer(minLength:0) }.padding(17).frame(maxWidth:.infinity,alignment:.leading).background(leaf.opacity(0.045),in:RoundedRectangle(cornerRadius:13))
    }
    var setupBanner: some View {
        HStack(spacing:12) {
            Image(systemName:"checkmark.shield").font(.title2).foregroundStyle(leaf)
            VStack(alignment:.leading,spacing:3) { Text("One small setup step").font(.system(size:13,weight:.semibold)); Text(!state.microphone ? "Allow the microphone to start dictating." : "Allow Accessibility to use your mouse button and paste.").font(.system(size:11)).foregroundStyle(muted) }
            Spacer()
            Button("Finish setup") { destination = .settings }.buttonStyle(.borderedProminent)
        }.padding(16).background(Color(red:0.94,green:0.91,blue:0.80),in:RoundedRectangle(cornerRadius:13))
    }
    var history: some View {
        VStack(spacing:0) {
            HStack(spacing:10) {
                Image(systemName:"magnifyingglass").foregroundStyle(muted)
                TextField("Search your words or an app…",text:$query).textFieldStyle(.plain)
                if !query.isEmpty { Button { query = "" } label: { Image(systemName:"xmark.circle.fill") }.buttonStyle(.plain).foregroundStyle(muted) }
            }.padding(13).background(.white,in:RoundedRectangle(cornerRadius:11)).padding(.horizontal,32).padding(.bottom,18)
            if matches.isEmpty {
                emptyHistory
            } else {
                HStack(spacing:0) {
                    ScrollView {
                        LazyVStack(spacing:8) {
                            ForEach(matches) { entry in
                                Button { selected = entry.id } label: {
                                    VStack(alignment:.leading,spacing:9) {
                                        HStack { Text(entry.date,format:.dateTime.month(.abbreviated).day().hour().minute()); Spacer(); Text("\(entry.words) words") }.font(.system(size:10)).foregroundStyle(muted)
                                        Text(entry.text).font(.system(size:13,weight:.medium)).lineLimit(3).lineSpacing(3).frame(maxWidth:.infinity,alignment:.leading)
                                        Text(entry.application).font(.system(size:10)).foregroundStyle(leaf)
                                    }.padding(15).frame(maxWidth:.infinity,alignment:.leading).background(selectedEntry?.id == entry.id ? leaf.opacity(0.085) : .white,in:RoundedRectangle(cornerRadius:12)).overlay(RoundedRectangle(cornerRadius:12).stroke(selectedEntry?.id == entry.id ? leaf.opacity(0.35) : ink.opacity(0.06)))
                                }.buttonStyle(.plain)
                            }
                        }.padding(.leading,32).padding(.trailing,15).padding(.bottom,16)
                    }.frame(width:285)
                    if let entry = selectedEntry { transcriptDetail(entry).padding(.trailing,32).padding(.bottom,16) }
                }
            }
            HStack {
                if let deleted { Text("Dictation deleted.").font(.caption); Button("Undo") { if state.saveHistory([deleted] + state.history) { self.deleted = nil } }.font(.caption) }
                else { Text("\(state.history.count) saved · last 30 days · this Mac only").font(.system(size:10)).foregroundStyle(muted) }
                Spacer()
                if !state.history.isEmpty { Button("Delete all…") { confirmClear = true }.buttonStyle(.plain).font(.caption).foregroundStyle(muted) }
            }.padding(.horizontal,32).padding(.vertical,16)
        }
    }
    var emptyHistory: some View {
        VStack(spacing:14) {
            Spacer()
            Image(systemName:query.isEmpty ? "text.bubble" : "magnifyingglass").font(.system(size:38,weight:.light)).foregroundStyle(leaf.opacity(0.6))
            Text(query.isEmpty ? "Your words will live here." : "No matching dictations.").font(.system(size:21,weight:.semibold,design:.rounded))
            Text(query.isEmpty ? (state.keepHistory ? "Start a dictation. Come back to find, copy or read it." : "History is paused. Enable it in Settings to save new dictations.") : "Try a different word or application name.").font(.system(size:12)).foregroundStyle(muted).multilineTextAlignment(.center).frame(maxWidth:330)
            Button(query.isEmpty ? "Go to dictation" : "Clear search") { if query.isEmpty { destination = .dictate } else { query = "" } }.buttonStyle(.bordered)
            Spacer()
        }.frame(maxWidth:.infinity,maxHeight:.infinity)
    }
    func transcriptDetail(_ entry: Recent) -> some View {
        VStack(alignment:.leading,spacing:20) {
            HStack { Text("TRANSCRIPT").font(.system(size:10,weight:.semibold)).tracking(1).foregroundStyle(muted); Spacer(); copyButton(entry) }
            ScrollView { Text(entry.text).font(.system(size:16)).lineSpacing(7).textSelection(.enabled).frame(maxWidth:.infinity,alignment:.leading) }
            Divider()
            entryMeta(entry)
            HStack { Text(entry.application).font(.caption).foregroundStyle(muted); Spacer(); Button { if state.saveHistory(state.history.filter { $0.id != entry.id }) { deleted = entry } } label: { Label("Delete",systemImage:"trash") }.buttonStyle(.plain).font(.caption).foregroundStyle(muted) }
        }.padding(22).frame(maxWidth:.infinity,maxHeight:.infinity,alignment:.topLeading).background(.white,in:RoundedRectangle(cornerRadius:16))
    }
    func entryMeta(_ entry: Recent) -> some View {
        HStack(spacing:10) { Text(entry.date,format:.dateTime.month(.abbreviated).day().hour().minute()); Text("\(entry.words) words"); if entry.duration > 0 { Text("\(Int(entry.duration))s") } }.font(.system(size:10)).foregroundStyle(muted)
    }
    func copyButton(_ entry: Recent) -> some View {
        Button { controller.copy(entry.text); copied = entry.id } label: { Label(copied == entry.id ? "Copied" : "Copy",systemImage:copied == entry.id ? "checkmark" : "doc.on.doc") }.buttonStyle(.bordered).font(.caption)
    }
    var vocabulary: some View {
        ScrollView {
            VStack(alignment:.leading,spacing:20) {
                Surface {
                    VStack(alignment:.leading,spacing:16) {
                        HStack {
                            Label("A familiar spelling, every time.",systemImage:"textformat.abc").font(.headline)
                            Spacer()
                            Button("Import word list…") { controller.importVocabulary() }.buttonStyle(.bordered)
                        }
                        Text("Teach Bucky how to write your names and terms. Put one replacement on each line. Changes save automatically.").font(.callout).foregroundStyle(muted)
                        Text("heard words = preferred spelling").font(.system(size:12,design:.monospaced)).foregroundStyle(leaf)
                        TextEditor(text:$state.glossary).font(.system(size:14,design:.monospaced)).scrollContentBackground(.hidden).padding(12).frame(minHeight:230).background(paper,in:RoundedRectangle(cornerRadius:10))
                        Text("Replacements apply to whole words after transcription. They do not train the speech model.").font(.caption).foregroundStyle(muted)
                        Text("Import UTF-8 CSV, TSV or text. Use two columns for heard words and preferred spelling, or one term per line. Existing entries are kept; review new entries before adding them.").font(.caption).foregroundStyle(muted)
                        if !state.vocabularyMessage.isEmpty { Text(state.vocabularyMessage).font(.caption).foregroundStyle(leaf) }
                    }
                }
            }.padding(.horizontal,32).padding(.bottom,28)
        }
        .sheet(item: $state.importPreview) { preview in
            VocabularyImportPreview(preview: preview, apply: {
                state.glossary = preview.applying(to: state.glossary)
                state.vocabularyMessage = "Added \(preview.additions.count) entries. Existing spellings were kept."
                state.importPreview = nil
            }, cancel: { state.importPreview = nil })
        }
    }
    var snippets: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                Surface {
                    VStack(alignment: .leading, spacing: 14) {
                        HStack {
                            Text("Say a little. Insert the whole thing.").font(.headline)
                            Spacer()
                            Button("New snippet") { state.snippetsError = ""; editingSnippet = Snippet(trigger: "", text: "") }
                                .buttonStyle(.borderedProminent).disabled(!state.snippetsWritable)
                        }
                        Text("Use a distinct phrase for text you often repeat. Snippets match whole phrases, ignore capitals and can contain several lines. They insert text only. Bucky never presses Return.").font(.callout).foregroundStyle(muted)
                        Text("A snippet takes priority if its trigger also appears in Vocabulary.").font(.caption).foregroundStyle(muted)
                        if !state.snippetsError.isEmpty { Text(state.snippetsError).font(.caption).foregroundStyle(.red) }
                    }
                }
                if state.snippets.isEmpty {
                    Text("Your first snippet could be a standard reply, an introduction or a signature.").font(.callout).foregroundStyle(muted).padding(.vertical, 20)
                }
                ForEach(state.snippets) { snippet in
                    Surface {
                        VStack(alignment: .leading, spacing: 12) {
                            HStack {
                                Text(snippet.trigger).font(.system(size: 15, weight: .semibold))
                                Spacer()
                                Toggle("Enabled", isOn: Binding(get: { state.snippets.first { $0.id == snippet.id }?.enabled ?? false }, set: { value in
                                    var edited = snippet; edited.enabled = value; _ = state.saveSnippet(edited)
                                })).toggleStyle(.switch).fixedSize()
                                Button("Edit") { state.snippetsError = ""; editingSnippet = snippet }
                                Button { deletingSnippet = snippet } label: { Image(systemName: "trash") }.help("Delete snippet")
                            }
                            Text(snippet.text).font(.system(size: 13)).lineSpacing(4).lineLimit(4).textSelection(.enabled)
                        }
                    }
                }
            }.padding(.horizontal, 32).padding(.bottom, 28)
        }
        .sheet(item: $editingSnippet) { snippet in
            SnippetEditor(snippet: snippet, error: state.snippetsError, save: { draft in
                if state.saveSnippet(draft) { editingSnippet = nil }
            }, cancel: { editingSnippet = nil })
        }
        .alert("Delete this snippet?", isPresented: Binding(get: { deletingSnippet != nil }, set: { if !$0 { deletingSnippet = nil } })) {
            Button("Cancel", role: .cancel) { deletingSnippet = nil }
            Button("Delete", role: .destructive) {
                if let id = deletingSnippet?.id { state.snippets.removeAll { $0.id == id } }
                deletingSnippet = nil
            }
        } message: { Text("The stored trigger and text will be removed from this Mac.") }
    }
    var settings: some View {
        ScrollView {
            VStack(alignment:.leading,spacing:18) {
                Surface {
                    VStack(alignment:.leading,spacing:16) {
                        sectionTitle("Permissions",icon:"checkmark.shield")
                        permissionRow("Microphone",detail:"Hear you when you start recording.",allowed:state.microphone,action:controller.requestMicrophone)
                        Divider()
                        permissionRow("Accessibility",detail:"Capture your mouse button and paste text.",allowed:state.accessibility,action:controller.requestAccessibility)
                    }
                }
                Surface {
                    VStack(alignment:.leading,spacing:15) {
                        sectionTitle("Keyboard & mouse",icon:"computermouse")
                        Text(state.shortcutLabel).font(.system(size:19,weight:.medium,design:.monospaced)).textSelection(.enabled)
                        HStack {
                            Button(state.capturingShortcut ? "Cancel recording" : "Record a shortcut") { if state.capturingShortcut { controller.shortcuts.cancelCapture() } else { controller.shortcuts.beginCapture() } }.buttonStyle(.borderedProminent)
                            Button("Retry") { controller.shortcuts.bind(controller.shortcuts.binding) }
                            Spacer()
                            Button("Remove mouse") { controller.shortcuts.clearMouse() }.buttonStyle(.plain).font(.caption)
                        }
                        Text(state.capturingShortcut ? "Press your side or middle mouse button now, or a keyboard combination. Escape cancels." : state.shortcutStatus).font(.caption).foregroundStyle(state.capturingShortcut ? leaf : muted).fixedSize(horizontal:false,vertical:true)
                        Toggle("Hold to talk",isOn:$state.holdToTalk)
                        Text(state.holdToTalk ? "Hold your button while speaking. Release it to finish." : "Press once to start. Press again to finish.").font(.caption).foregroundStyle(muted)
                        Divider()
                        HStack { Text("Backup: ⌃ ⌥ Space").font(.caption).foregroundStyle(muted); Spacer(); Button("Reset to Control–Space") { controller.shortcuts.bind(.superwhisper) }.font(.caption) }
                    }.disabled(state.recording || state.busy)
                }
                Surface {
                    VStack(alignment:.leading,spacing:16) {
                        sectionTitle("Everyday use",icon:"slider.horizontal.3")
                        Toggle("Open Bucky when I log in",isOn:Binding(get:{state.atLogin},set:{_ in controller.toggleLogin()}))
                        Toggle("Paste into my current app",isOn:$state.autoPaste)
                        Toggle("Play recording sounds",isOn:$state.soundEffects)
                        Toggle("Restore my clipboard after automatic paste", isOn: $state.preserveClipboard)
                        Text("Keeps your previous clipboard in memory briefly. A new copy is never replaced. Explicit Copy and manual-paste fallback keep the dictation on the clipboard.").font(.caption).foregroundStyle(muted)
                        Divider()
                        Text(state.pasteLastShortcutStatus).font(.caption).foregroundStyle(leaf)
                        Text("In the app where you want the text, press ⌃⌘V to paste your latest available dictation again. This works even when automatic paste is off.").font(.caption).foregroundStyle(muted)
                        Text("If you switch apps while dictating, Bucky copies the text instead. Use ⌃⌘V to paste the latest dictation again.").font(.caption).foregroundStyle(muted)
                    }
                }
                Surface {
                    VStack(alignment:.leading,spacing:16) {
                        sectionTitle("History & privacy",icon:"lock.shield")
                        Toggle("Save dictation history on this Mac",isOn:$state.keepHistory)
                        Text("Keeps up to 500 transcripts for 30 days in your local Application Support folder. Audio is deleted after processing. Turning this off stops saving new dictations; existing history stays until you delete it.").font(.caption).foregroundStyle(muted).fixedSize(horizontal:false,vertical:true)
                        Button("Show saved history") { destination = .history }.font(.caption)
                    }
                }
                Surface {
                    HStack {
                        VStack(alignment:.leading,spacing:5) { sectionTitle("Speech engine",icon:"cpu"); Text("Parakeet v3 · Dutch + English · automatic detection").font(.caption).foregroundStyle(muted) }
                        Spacer()
                        Button("Restart") { controller.startWorker() }.disabled(state.recording || state.busy)
                    }
                }
            }.padding(.horizontal,32).padding(.bottom,28)
        }
    }
    func sectionTitle(_ title: String, icon: String) -> some View { Label(title,systemImage:icon).font(.system(size:14,weight:.semibold)) }
    func permissionRow(_ title: String, detail: String, allowed: Bool, action: @escaping () -> Void) -> some View {
        HStack { VStack(alignment:.leading,spacing:4) { Text(title).font(.system(size:13,weight:.medium)); Text(detail).font(.caption).foregroundStyle(muted) }; Spacer(); if allowed { Label("Allowed",systemImage:"checkmark.circle.fill").font(.caption).foregroundStyle(leaf) } else { Button("Allow",action:action).buttonStyle(.bordered) } }
    }
}


struct VocabularyImportPreview: View {
    let preview: VocabularyImport
    let apply: () -> Void
    let cancel: () -> Void
    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("Review your word list").font(.title2.bold())
            Text("\(preview.additions.count) new entries · \(preview.skipped) existing or duplicate entries skipped").font(.callout)
            Text("Your existing spellings will be kept. Nothing is added until you choose Import.").font(.caption).foregroundStyle(.secondary)
            ScrollView {
                VStack(alignment: .leading, spacing: 10) {
                    ForEach(Array(preview.additions.prefix(50).enumerated()), id: \.offset) { _, rule in
                        HStack(alignment: .top) { Text(rule.trigger).frame(maxWidth: .infinity, alignment: .leading); Image(systemName: "arrow.right"); Text(rule.replacement).frame(maxWidth: .infinity, alignment: .leading) }.font(.system(size: 12))
                    }
                    if preview.additions.count > 50 { Text("Showing the first 50 entries.").font(.caption).foregroundStyle(.secondary) }
                }
            }.frame(height: 240)
            HStack { Button("Cancel", action: cancel).keyboardShortcut(.cancelAction); Spacer(); Button("Import \(preview.additions.count) entries", action: apply).keyboardShortcut(.defaultAction).disabled(preview.additions.isEmpty) }
        }.padding(28).frame(width: 560)
    }
}

struct SnippetEditor: View {
    @State var snippet: Snippet
    let error: String
    let save: (Snippet) -> Void
    let cancel: () -> Void
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Your snippet").font(.title2.bold())
            TextField("Spoken trigger — for example: insert standard reply", text: $snippet.trigger).textFieldStyle(.roundedBorder).accessibilityLabel("Spoken trigger")
            Text("Text to insert").font(.headline)
            TextEditor(text: $snippet.text).font(.system(size: 14)).frame(height: 220).padding(8).background(Color.white, in: RoundedRectangle(cornerRadius: 8)).accessibilityLabel("Snippet text")
            Text("Keep the trigger distinctive. Line breaks and punctuation are inserted exactly as written.").font(.caption).foregroundStyle(.secondary)
            if !error.isEmpty { Text(error).font(.caption).foregroundStyle(.red) }
            HStack { Button("Cancel", action: cancel).keyboardShortcut(.cancelAction); Spacer(); Button("Save snippet") { save(snippet) }.keyboardShortcut(.defaultAction) }
        }.padding(28).frame(width: 580)
    }
}
