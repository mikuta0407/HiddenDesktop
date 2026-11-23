// HiddenDesktop — メニューバーからデスクトップアイコン/ウィジェットを隠す/表示する小さなアプリ
//
// 仕組み:
//  - アイコン:   com.apple.finder の CreateDesktop を false にして Finder を再起動
//  - ウィジェット: com.apple.WindowManager の StandardHideWidgets / StageManagerHideWidgets を true
//                 (WindowManager が設定を監視しているので即時反映。システム設定の
//                  「ウィジェットを表示: デスクトップ」と同じ設定)
// 壁紙の上に絵を重ねる方式ではないので、動画(空撮)壁紙でもそのまま動く。

import AppKit
import Carbon.HIToolbox
import ServiceManagement

// MARK: - 他アプリの設定の読み書き

enum Prefs {
    static let finder = "com.apple.finder" as CFString
    static let windowManager = "com.apple.WindowManager" as CFString

    static func bool(_ key: String, _ app: CFString) -> Bool? {
        CFPreferencesAppSynchronize(app)
        return CFPreferencesCopyAppValue(key as CFString, app) as? Bool
    }

    static func set(_ key: String, _ value: Bool?, _ app: CFString) {
        CFPreferencesSetAppValue(key as CFString, value.map { $0 as CFBoolean } as CFPropertyList?, app)
        CFPreferencesAppSynchronize(app)
    }
}

enum Desktop {
    // アイコン
    static var iconsHidden: Bool { Prefs.bool("CreateDesktop", Prefs.finder) == false }

    static func setIconsHidden(_ hidden: Bool) {
        guard hidden != iconsHidden else { return }
        // 表示に戻すときはキーごと消してデフォルト状態に戻す
        Prefs.set("CreateDesktop", hidden ? false : nil, Prefs.finder)
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/killall")
        p.arguments = ["Finder"]  // launchd が自動で再起動する
        try? p.run()
    }

    // ウィジェット
    static let widgetKeys = ["StandardHideWidgets", "StageManagerHideWidgets"]

    static var widgetsHidden: Bool { Prefs.bool("StandardHideWidgets", Prefs.windowManager) == true }

    /// 隠す前の値を覚えておき、表示に戻すときにそれを復元する
    static func setWidgetsHidden(_ hidden: Bool) {
        let store = UserDefaults.standard
        for key in widgetKeys {
            let savedKey = "saved.\(key)"
            if hidden {
                if store.object(forKey: savedKey) == nil {
                    store.set(Prefs.bool(key, Prefs.windowManager) ?? false, forKey: savedKey)
                }
                Prefs.set(key, true, Prefs.windowManager)
            } else {
                // 自分で隠していないなら触らない (ユーザーが元々非表示にしている場合を壊さない)
                guard let original = store.object(forKey: savedKey) as? Bool else { continue }
                Prefs.set(key, original, Prefs.windowManager)
                store.removeObject(forKey: savedKey)
            }
        }
    }
}

// MARK: - グローバルホットキー (⌃⌥⌘H)

final class HotKey {
    private var ref: EventHotKeyRef?
    private static var handler: (() -> Void)?

    init(keyCode: UInt32, modifiers: UInt32, handler: @escaping () -> Void) {
        HotKey.handler = handler
        var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        InstallEventHandler(GetApplicationEventTarget(), { _, _, _ in
            HotKey.handler?()
            return noErr
        }, 1, &spec, nil, nil)
        let id = EventHotKeyID(signature: OSType(0x4844_534B), id: 1) // 'HDSK'
        RegisterEventHotKey(keyCode, modifiers, id, GetApplicationEventTarget(), 0, &ref)
    }
}

// MARK: - アプリ本体

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem!
    private var hotKey: HotKey?
    private var signalSources: [DispatchSourceSignal] = []
    private let defaults = UserDefaults.standard

    /// ウィジェットも一緒に隠すか (デフォルト: する)
    private var includeWidgets: Bool {
        get { defaults.object(forKey: "includeWidgets") as? Bool ?? true }
        set { defaults.set(newValue, forKey: "includeWidgets") }
    }

    /// 実際の状態はシステム設定から読む (アプリを再起動しても食い違わない)
    private var isHidden: Bool { Desktop.iconsHidden }

    func applicationDidFinishLaunching(_ notification: Notification) {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = statusItem.button {
            button.target = self
            button.action = #selector(statusItemClicked(_:))
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
        }
        hotKey = HotKey(keyCode: UInt32(kVK_ANSI_H),
                        modifiers: UInt32(controlKey | optionKey | cmdKey)) { [weak self] in
            self?.toggle()
        }
        // kill / pkill (SIGTERM) や Ctrl-C (SIGINT) でも通常終了させて元に戻す
        for sig in [SIGTERM, SIGINT, SIGHUP] {
            signal(sig, SIG_IGN)
            let source = DispatchSource.makeSignalSource(signal: sig, queue: .main)
            source.setEventHandler { NSApp.terminate(nil) }
            source.resume()
            signalSources.append(source)
        }
        updateIcon()
    }

    /// 終了時は必ずデスクトップを表示状態に戻す
    func applicationWillTerminate(_ notification: Notification) {
        Desktop.setWidgetsHidden(false)
        Desktop.setIconsHidden(false)
    }

    // 左クリック: 切り替え / 右クリック (or ⌥クリック): メニュー
    @objc private func statusItemClicked(_ sender: NSStatusBarButton) {
        guard let event = NSApp.currentEvent else { return }
        if event.type == .rightMouseUp || event.modifierFlags.contains(.option) {
            showMenu()
        } else {
            toggle()
        }
    }

    private func showMenu() {
        let menu = NSMenu()
        let toggleItem = NSMenuItem(title: isHidden ? "デスクトップを表示" : "デスクトップを隠す",
                                    action: #selector(toggle), keyEquivalent: "h")
        toggleItem.keyEquivalentModifierMask = [.control, .option, .command]
        toggleItem.target = self
        menu.addItem(toggleItem)

        let widgets = NSMenuItem(title: "ウィジェットも隠す", action: #selector(toggleIncludeWidgets), keyEquivalent: "")
        widgets.state = includeWidgets ? .on : .off
        widgets.target = self
        menu.addItem(widgets)
        menu.addItem(.separator())

        let login = NSMenuItem(title: "ログイン時に起動", action: #selector(toggleLoginItem), keyEquivalent: "")
        login.state = SMAppService.mainApp.status == .enabled ? .on : .off
        login.target = self
        menu.addItem(login)
        menu.addItem(.separator())
        let quit = NSMenuItem(title: "終了 (デスクトップを表示に戻す)",
                              action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        quit.target = NSApp
        menu.addItem(quit)

        statusItem.menu = menu
        statusItem.button?.performClick(nil)
        statusItem.menu = nil  // 次の左クリックはトグルに戻す
    }

    @objc func toggle() {
        let hide = !isHidden
        Desktop.setIconsHidden(hide)
        if hide {
            if includeWidgets { Desktop.setWidgetsHidden(true) }
        } else {
            Desktop.setWidgetsHidden(false)
        }
        updateIcon()
    }

    @objc private func toggleIncludeWidgets() {
        includeWidgets.toggle()
        // 隠している最中に切り替えたら即反映
        if isHidden { Desktop.setWidgetsHidden(includeWidgets) }
    }

    @objc private func toggleLoginItem() {
        do {
            if SMAppService.mainApp.status == .enabled {
                try SMAppService.mainApp.unregister()
            } else {
                try SMAppService.mainApp.register()
            }
        } catch {
            NSAlert(error: error).runModal()
        }
    }

    private func updateIcon() {
        let symbol = isHidden ? "eye.slash" : "eye"
        statusItem.button?.image = NSImage(systemSymbolName: symbol,
                                           accessibilityDescription: isHidden ? "デスクトップ非表示中" : "デスクトップ表示中")
        statusItem.button?.toolTip = "クリックで切り替え / 右クリックでメニュー (⌃⌥⌘H)"
    }
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.accessory)
app.run()
