import Cocoa
import Darwin
import SwiftUI

struct AIEntry: Codable {
    let name: String
    let connected: Bool?
    let input_tokens: Int
    let output_tokens: Int
    let credits_remaining: Double?
    let quota_percent: Int?
    let secondary_quota_percent: Int?
    let credits_spent_today: Double?
    let checkin_today: Double?
    let sessions_today: Int?
    let reset_seconds: Int?
}

struct StatusPayload: Codable {
    let locale: String?
    let refresh_interval_sec: Int?
    let updated_at: String
    let antigravity: AIEntry
    let workbuddy: AIEntry
}

struct AIConfigSection: Codable {
    var credits_anchor_value: Double?
    var credits_anchor_at_ms: Int64?
    var reset_at: String?
}

struct WidgetConfig: Codable {
    var locale: String?
    var refresh_interval_sec: Int?
    var antigravity: AIConfigSection
    var workbuddy: AIConfigSection
}

@MainActor
final class StatusStore: ObservableObject {
    @Published var payload: StatusPayload?
    @Published var tickOffset: Int = 0
    @Published var isRefreshing: Bool = false
    @Published var locale: String = "en"

    private var refreshTimer: Timer?
    private var tickTimer: Timer?
    private var currentInterval: TimeInterval = 30.0
    var onLocaleChanged: ((String) -> Void)?

    var collectorPath: String {
        if let resPath = Bundle.main.resourcePath {
            let bundled = resPath + "/collector.py"
            if FileManager.default.fileExists(atPath: bundled) {
                return bundled
            }
        }
        return NSHomeDirectory() + "/Desktop/ai-status-widget/collector.py"
    }

    var setupHtmlPath: String {
        if let resPath = Bundle.main.resourcePath {
            let bundled = resPath + "/setup.html"
            if FileManager.default.fileExists(atPath: bundled) {
                return bundled
            }
        }
        return NSHomeDirectory() + "/Desktop/ai-status-widget/setup.html"
    }

    var configPath: String {
        let dir = NSHomeDirectory() + "/Library/Application Support/AIStatusWidget"
        try? FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
        return dir + "/config.json"
    }

    init() {
        let cfg = loadConfig()
        locale = cfg.locale ?? "en"
        currentInterval = TimeInterval(cfg.refresh_interval_sec ?? 30)
        refresh()
        scheduleRefreshTimer()
        tickTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.tickOffset += 1
            }
        }
    }

    private func scheduleRefreshTimer() {
        refreshTimer?.invalidate()
        refreshTimer = Timer.scheduledTimer(withTimeInterval: currentInterval, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.refresh()
            }
        }
    }

    func refresh(completion: (() -> Void)? = nil) {
        isRefreshing = true
        let script = collectorPath
        DispatchQueue.global(qos: .userInitiated).async {
            let proc = Process()
            proc.executableURL = URL(fileURLWithPath: "/usr/bin/python3")
            proc.arguments = [script]
            let pipe = Pipe()
            proc.standardOutput = pipe
            proc.standardError = Pipe()
            do {
                try proc.run()
                proc.waitUntilExit()
                let data = pipe.fileHandleForReading.readDataToEndOfFile()
                if let decoded = try? JSONDecoder().decode(StatusPayload.self, from: data) {
                    Task { @MainActor in
                        self.payload = decoded
                        if let loc = decoded.locale, loc != self.locale {
                            self.locale = loc
                            self.onLocaleChanged?(loc)
                        }
                        self.tickOffset = 0
                        self.isRefreshing = false
                        completion?()
                    }
                    return
                }
            } catch {}
            Task { @MainActor in
                self.isRefreshing = false
                completion?()
            }
        }
    }

    func loadConfig() -> WidgetConfig {
        let url = URL(fileURLWithPath: configPath)
        if let data = try? Data(contentsOf: url),
           let cfg = try? JSONDecoder().decode(WidgetConfig.self, from: data) {
            return cfg
        }
        return WidgetConfig(
            locale: "en",
            refresh_interval_sec: 30,
            antigravity: AIConfigSection(credits_anchor_value: nil, credits_anchor_at_ms: nil, reset_at: nil),
            workbuddy: AIConfigSection(credits_anchor_value: nil, credits_anchor_at_ms: nil, reset_at: nil)
        )
    }

    func saveConfig(_ cfg: WidgetConfig) {
        let url = URL(fileURLWithPath: configPath)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        if let data = try? encoder.encode(cfg) {
            try? data.write(to: url)
            if let loc = cfg.locale, loc != locale {
                locale = loc
                onLocaleChanged?(loc)
            }
            let nextInterval = TimeInterval(cfg.refresh_interval_sec ?? 30)
            if nextInterval != currentInterval {
                currentInterval = nextInterval
                scheduleRefreshTimer()
            }
            refresh()
        }
    }
}

func formatTokens(_ count: Int) -> String {
    if count >= 1_000_000 {
        return String(format: "%.1fM", Double(count) / 1_000_000.0)
    } else if count >= 1_000 {
        return String(format: "%.1fk", Double(count) / 1_000.0)
    }
    return "\(count)"
}

func formatNumber(_ val: Double) -> String {
    if abs(val.rounded() - val) < 0.05 {
        return "\(Int(val.rounded()))"
    }
    return String(format: "%.1f", val)
}

func formatCountdown(_ baseSeconds: Int?, sessionsToday: Int?, offset: Int, isZh: Bool) -> String {
    guard let base = baseSeconds else {
        if let sess = sessionsToday {
            return isZh ? "\(sess) 会话" : "\(sess) sess"
        }
        return isZh ? "本地" : "Local"
    }
    let rem = max(0, base - offset)
    if rem == 0 { return isZh ? "即将重置" : "Resetting" }
    let h = rem / 3600
    let m = (rem % 3600) / 60
    let s = rem % 60
    if h > 0 {
        return String(format: "%dh%02dm", h, m)
    } else if m > 0 {
        return String(format: "%dm%02ds", m, s)
    }
    return "\(s)s"
}

// MARK: - 344 x 116 Liquid Glass Widget UI

struct AntigravityColumn: View {
    let entry: AIEntry
    let tickOffset: Int
    let isZh: Bool

    private let accent = Color(red: 0.30, green: 0.72, blue: 1.0)

    var primaryPct: Int { entry.quota_percent ?? 0 }
    var secondaryPct: Int { entry.secondary_quota_percent ?? 0 }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 5) {
                Circle()
                    .fill(accent)
                    .frame(width: 6, height: 6)
                Text("Antigravity")
                    .font(.system(size: 11.5, weight: .semibold))
                    .foregroundColor(.primary)
                Spacer(minLength: 2)
                Text(formatCountdown(entry.reset_seconds, sessionsToday: nil, offset: tickOffset, isZh: isZh))
                    .font(.system(size: 9.5, weight: .medium).monospacedDigit())
                    .foregroundColor(accent)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(accent.opacity(0.16))
                    .clipShape(Capsule())
            }

            HStack(alignment: .firstTextBaseline) {
                Text("Gemini 5h")
                    .font(.system(size: 10.5, weight: .medium))
                    .foregroundColor(.secondary)
                Spacer()
                Text(entry.quota_percent != nil ? "\(primaryPct)%" : "--")
                    .font(.system(size: 18, weight: .bold).monospacedDigit())
                    .foregroundColor(.primary)
            }

            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(Color.primary.opacity(0.12))
                    Capsule()
                        .fill(accent.opacity(entry.quota_percent != nil ? 0.92 : 0.25))
                        .frame(width: geo.size.width * min(1.0, max(0.0, Double(primaryPct) / 100.0)))
                }
            }
            .frame(height: 4)

            HStack {
                Text("Claude \(entry.secondary_quota_percent != nil ? "\(secondaryPct)%" : "--")")
                    .font(.system(size: 9.5, weight: .medium).monospacedDigit())
                    .foregroundColor(.secondary)
                Spacer()
                Text("↑\(formatTokens(entry.input_tokens))  ↓\(formatTokens(entry.output_tokens))")
                    .font(.system(size: 9.5, weight: .medium).monospacedDigit())
                    .foregroundColor(.secondary)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
    }
}

struct WorkBuddyColumn: View {
    let entry: AIEntry
    let tickOffset: Int
    let isZh: Bool

    private let accent = Color(red: 0.22, green: 0.85, blue: 0.65)

    var barFraction: Double {
        if let rem = entry.credits_remaining {
            let spent = max(0, entry.credits_spent_today ?? 0)
            let base = max(rem + spent, 1)
            return min(1.0, max(0.0, rem / base))
        }
        return (entry.credits_spent_today ?? 0) > 0 ? 1.0 : 0.0
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 5) {
                Circle()
                    .fill(accent)
                    .frame(width: 6, height: 6)
                Text("WorkBuddy")
                    .font(.system(size: 11.5, weight: .semibold))
                    .foregroundColor(.primary)
                Spacer(minLength: 2)
                Text(formatCountdown(entry.reset_seconds, sessionsToday: entry.sessions_today, offset: tickOffset, isZh: isZh))
                    .font(.system(size: 9.5, weight: .medium).monospacedDigit())
                    .foregroundColor(accent)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(accent.opacity(0.16))
                    .clipShape(Capsule())
            }

            HStack(alignment: .firstTextBaseline) {
                Text("Credits")
                    .font(.system(size: 10.5, weight: .medium))
                    .foregroundColor(.secondary)
                Spacer()
                Text(entry.credits_remaining != nil ? formatNumber(entry.credits_remaining!) : "--")
                    .font(.system(size: 18, weight: .bold).monospacedDigit())
                    .foregroundColor(.primary)
            }

            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(Color.primary.opacity(0.12))
                    Capsule()
                        .fill(accent.opacity(barFraction > 0 ? 0.92 : 0.25))
                        .frame(width: geo.size.width * barFraction)
                }
            }
            .frame(height: 4)

            HStack {
                Text(isZh ? "今日 -\(formatNumber(entry.credits_spent_today ?? 0))" : "Today -\(formatNumber(entry.credits_spent_today ?? 0))")
                    .font(.system(size: 9.5, weight: .medium).monospacedDigit())
                    .foregroundColor(.secondary)
                Spacer()
                Text("↑\(formatTokens(entry.input_tokens))  ↓\(formatTokens(entry.output_tokens))")
                    .font(.system(size: 9.5, weight: .medium).monospacedDigit())
                    .foregroundColor(.secondary)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
    }
}

final class DragStateObservable: ObservableObject {
    @Published var isDragging = false
    @Published var glowPulse = false
}

struct WidgetView: View {
    @ObservedObject var store: StatusStore
    @ObservedObject var dragState: DragStateObservable

    var isZh: Bool { store.locale == "zh" }

    var body: some View {
        ZStack(alignment: .top) {
            if let data = store.payload {
                HStack(spacing: 0) {
                    AntigravityColumn(entry: data.antigravity, tickOffset: store.tickOffset, isZh: isZh)
                        .frame(width: 171.5, height: 116)
                        .transition(.opacity)

                    Rectangle()
                        .fill(Color.primary.opacity(0.14))
                        .frame(width: 1, height: 66)
                        .padding(.top, 34)

                    WorkBuddyColumn(entry: data.workbuddy, tickOffset: store.tickOffset, isZh: isZh)
                        .frame(width: 171.5, height: 116)
                        .transition(.opacity)
                }
                .animation(.easeInOut(duration: 0.25), value: data.updated_at)
            } else {
                Text(isZh ? "正在读取..." : "Loading...")
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }

            Button {
                withAnimation(.easeOut(duration: 0.2)) {
                    dragState.glowPulse = true
                }
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.32) {
                    withAnimation(.easeInOut(duration: 0.25)) {
                        dragState.glowPulse = false
                    }
                }
                store.refresh()
            } label: {
                ZStack {
                    Circle()
                        .fill(Color.primary.opacity(dragState.glowPulse ? 0.20 : 0.12))
                        .frame(width: 22, height: 22)
                        .overlay(
                            Circle()
                                .stroke(Color.white.opacity(0.28), lineWidth: 0.7)
                        )
                    Image(systemName: "arrow.clockwise")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundColor(.primary.opacity(0.92))
                        .rotationEffect(.degrees(store.isRefreshing ? 360 : 0))
                        .animation(store.isRefreshing ? .linear(duration: 0.7).repeatForever(autoreverses: false) : .default, value: store.isRefreshing)
                }
                .frame(width: 26, height: 26)
                .contentShape(Circle())
            }
            .buttonStyle(.plain)
            .padding(.top, 4)
            .help(isZh ? "刷新状态" : "Refresh")
        }
        .frame(width: 344, height: 116)
    }
}

// MARK: - Glass Container with 1px Specular Rim, Caustics Glow & 0.25s Long-Press Drag

final class GlassWidgetHostView<Content: View>: NSHostingView<Content> {
    var dragState: DragStateObservable?
    var onDragFinished: (() -> Void)?

    private var rimGrad = CAGradientLayer()
    private var rimMask = CAShapeLayer()
    private var causticsLayer = CAGradientLayer()

    private var holdTimer: Timer?
    private var isDragArmed = false
    private var startMouseScreen: NSPoint = .zero
    private var startWindowOrigin: NSPoint = .zero

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        wantsLayer = true
        layer?.shadowOpacity = 0.0
        setupGlassEffects()
        updateAppearanceColors()
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        updateAppearanceColors()
    }

    private var isDarkAppearance: Bool {
        let match = effectiveAppearance.bestMatch(from: [.darkAqua, .aqua])
        return match == .darkAqua
    }

    func updateAppearanceColors() {
        let dark = isDarkAppearance

        // Update 1px specular rim for Light vs Dark mode
        rimGrad.colors = dark
            ? [
                NSColor.white.withAlphaComponent(0.68).cgColor,
                NSColor(red: 0.61, green: 0.88, blue: 1.0, alpha: 0.30).cgColor,
                NSColor.white.withAlphaComponent(0.06).cgColor
            ]
            : [
                NSColor.white.withAlphaComponent(0.90).cgColor,
                NSColor(red: 0.45, green: 0.78, blue: 1.0, alpha: 0.38).cgColor,
                NSColor.black.withAlphaComponent(0.10).cgColor
            ]

        // Update glass container tint if supported
        if let glass = superview {
            if NSClassFromString("NSGlassEffectView") != nil, glass.isKind(of: NSClassFromString("NSGlassEffectView")!) {
                if glass.responds(to: NSSelectorFromString("setTintColor:")) {
                    let tint = dark ? NSColor(white: 0.05, alpha: 0.14) : NSColor(white: 1.0, alpha: 0.10)
                    glass.setValue(tint, forKey: "tintColor")
                }
            } else if let effect = glass as? NSVisualEffectView {
                effect.material = dark ? .hudWindow : .popover
                effect.layer?.backgroundColor = dark
                    ? NSColor(white: 0.05, alpha: 0.18).cgColor
                    : NSColor(white: 1.0, alpha: 0.10).cgColor
            }
        }
    }

    private func setupGlassEffects() {
        guard let rootLayer = layer else { return }

        // Caustics click glow (320x320 radial, hidden by default)
        causticsLayer.type = .radial
        causticsLayer.colors = [
            NSColor.white.withAlphaComponent(0.32).cgColor,
            NSColor(red: 0.61, green: 0.88, blue: 1.0, alpha: 0.16).cgColor,
            NSColor.clear.cgColor
        ]
        causticsLayer.startPoint = CGPoint(x: 0.5, y: 0.5)
        causticsLayer.endPoint = CGPoint(x: 1.0, y: 1.0)
        causticsLayer.bounds = CGRect(x: 0, y: 0, width: 320, height: 320)
        causticsLayer.opacity = 0.0
        causticsLayer.zPosition = 997.0
        if causticsLayer.superlayer == nil {
            rootLayer.addSublayer(causticsLayer)
        }

        // 1px Specular Rim Highlight
        rimGrad.colors = [
            NSColor.white.withAlphaComponent(0.78).cgColor,
            NSColor(red: 0.61, green: 0.88, blue: 1.0, alpha: 0.34).cgColor,
            NSColor.white.withAlphaComponent(0.06).cgColor
        ]
        rimGrad.startPoint = CGPoint(x: 0.0, y: 1.0)
        rimGrad.endPoint = CGPoint(x: 1.0, y: 0.0)
        rimGrad.opacity = 0.88
        rimGrad.zPosition = 999.0
        rimMask.fillColor = NSColor.clear.cgColor
        rimMask.strokeColor = NSColor.white.cgColor
        rimMask.lineWidth = 1.0
        rimGrad.mask = rimMask
        if rimGrad.superlayer == nil {
            rootLayer.addSublayer(rimGrad)
        }
        updateRimBounds()
    }

    override func layout() {
        super.layout()
        updateRimBounds()
    }

    private func updateRimBounds() {
        rimGrad.frame = bounds
        let path = CGPath(roundedRect: bounds.insetBy(dx: 0.5, dy: 0.5), cornerWidth: 16, cornerHeight: 16, transform: nil)
        rimMask.path = path
        rimMask.frame = bounds
    }

    private func showCaustics(at point: NSPoint) {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        causticsLayer.position = point
        causticsLayer.opacity = 1.0
        CATransaction.commit()
    }

    private func hideCaustics() {
        CATransaction.begin()
        CATransaction.setAnimationDuration(0.25)
        causticsLayer.opacity = 0.0
        CATransaction.commit()
    }

    private func isInsideInteractiveButton(_ windowPoint: NSPoint) -> Bool {
        let local = convert(windowPoint, from: nil)
        let btnZone = NSRect(x: (bounds.width - 30) / 2, y: bounds.height - 32, width: 30, height: 32)
        return btnZone.contains(local)
    }

    override func mouseDown(with event: NSEvent) {
        let local = convert(event.locationInWindow, from: nil)
        showCaustics(at: local)

        if isInsideInteractiveButton(event.locationInWindow) {
            super.mouseDown(with: event)
            return
        }

        holdTimer?.invalidate()
        isDragArmed = false
        startMouseScreen = NSEvent.mouseLocation
        startWindowOrigin = window?.frame.origin ?? .zero

        holdTimer = Timer.scheduledTimer(withTimeInterval: 0.25, repeats: false) { [weak self] _ in
            Task { @MainActor in
                guard let self else { return }
                self.isDragArmed = true
                self.dragState?.isDragging = true
                NSCursor.closedHand.push()
            }
        }
    }

    override func mouseDragged(with event: NSEvent) {
        let local = convert(event.locationInWindow, from: nil)
        showCaustics(at: local)

        if isInsideInteractiveButton(event.locationInWindow) && !isDragArmed {
            super.mouseDragged(with: event)
            return
        }
        guard isDragArmed, let win = window else { return }
        let cur = NSEvent.mouseLocation
        let dx = cur.x - startMouseScreen.x
        let dy = cur.y - startMouseScreen.y
        win.setFrameOrigin(NSPoint(x: startWindowOrigin.x + dx, y: startWindowOrigin.y + dy))
    }

    override func mouseUp(with event: NSEvent) {
        hideCaustics()
        holdTimer?.invalidate()
        holdTimer = nil
        if isDragArmed {
            isDragArmed = false
            dragState?.isDragging = false
            NSCursor.pop()
            onDragFinished?()
            return
        }
        super.mouseUp(with: event)
    }
}

// MARK: - Lightweight Local HTTP Server for Industrial Web Workbench

final class LocalSetupServer: @unchecked Sendable {
    private var listenFD: Int32 = -1
    private(set) var port: UInt16 = 0
    private let htmlPath: String
    private let onGetState: (@escaping (Data) -> Void) -> Void
    private let onRefreshState: (@escaping (Data) -> Void) -> Void
    private let onSaveState: (Data, @escaping (Bool) -> Void) -> Void

    init(
        htmlPath: String,
        onGetState: @escaping (@escaping (Data) -> Void) -> Void,
        onRefreshState: @escaping (@escaping (Data) -> Void) -> Void,
        onSaveState: @escaping (Data, @escaping (Bool) -> Void) -> Void
    ) {
        self.htmlPath = htmlPath
        self.onGetState = onGetState
        self.onRefreshState = onRefreshState
        self.onSaveState = onSaveState
    }

    func startIfNeeded() -> UInt16 {
        if listenFD >= 0 && port > 0 { return port }

        let fd = socket(AF_INET, SOCK_STREAM, 0)
        guard fd >= 0 else { return 0 }

        var yes: Int32 = 1
        setsockopt(fd, SOL_SOCKET, SO_REUSEADDR, &yes, socklen_t(MemoryLayout<Int32>.size))

        var addr = sockaddr_in()
        addr.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
        addr.sin_family = sa_family_t(AF_INET)
        addr.sin_port = 0
        addr.sin_addr.s_addr = inet_addr("127.0.0.1")

        let bindRes = withUnsafePointer(to: &addr) { ptr in
            ptr.withMemoryRebound(to: sockaddr.self, capacity: 1) { sa in
                Darwin.bind(fd, sa, socklen_t(MemoryLayout<sockaddr_in>.size))
            }
        }
        guard bindRes == 0, listen(fd, 16) == 0 else {
            close(fd)
            return 0
        }

        var boundAddr = sockaddr_in()
        var len = socklen_t(MemoryLayout<sockaddr_in>.size)
        _ = withUnsafeMutablePointer(to: &boundAddr) { ptr in
            ptr.withMemoryRebound(to: sockaddr.self, capacity: 1) { sa in
                getsockname(fd, sa, &len)
            }
        }
        self.port = UInt16(bigEndian: boundAddr.sin_port)
        self.listenFD = fd

        DispatchQueue.global(qos: .utility).async { [weak self] in
            self?.acceptLoop(fd: fd)
        }
        return self.port
    }

    private func acceptLoop(fd: Int32) {
        while true {
            var clientAddr = sockaddr_in()
            var addrLen = socklen_t(MemoryLayout<sockaddr_in>.size)
            let clientFD = withUnsafeMutablePointer(to: &clientAddr) { ptr in
                ptr.withMemoryRebound(to: sockaddr.self, capacity: 1) { sa in
                    accept(fd, sa, &addrLen)
                }
            }
            if clientFD < 0 { break }
            DispatchQueue.global(qos: .userInitiated).async { [weak self] in
                self?.handleClient(clientFD)
            }
        }
    }

    private func handleClient(_ clientFD: Int32) {
        var buffer = [UInt8](repeating: 0, count: 65536)
        let bytesRead = read(clientFD, &buffer, buffer.count)
        guard bytesRead > 0 else {
            close(clientFD)
            return
        }
        let raw = Data(buffer[0..<bytesRead])
        guard let reqStr = String(data: raw, encoding: .utf8) else {
            close(clientFD)
            return
        }

        let lines = reqStr.components(separatedBy: "\r\n")
        let firstLine = lines.first ?? ""
        let parts = firstLine.split(separator: " ")
        let method = parts.count > 0 ? String(parts[0]) : "GET"
        let path = parts.count > 1 ? String(parts[1]) : "/"

        let bodyData: Data
        if let range = reqStr.range(of: "\r\n\r\n") {
            bodyData = Data(reqStr[range.upperBound...].utf8)
        } else {
            bodyData = Data()
        }

        if method == "GET" && (path == "/" || path == "/setup.html") {
            let html = (try? Data(contentsOf: URL(fileURLWithPath: htmlPath))) ?? Data("Not found".utf8)
            sendResponse(clientFD, status: "200 OK", contentType: "text/html; charset=utf-8", body: html)
        } else if method == "GET" && path == "/api/state" {
            onGetState { jsonData in
                self.sendResponse(clientFD, status: "200 OK", contentType: "application/json; charset=utf-8", body: jsonData)
            }
        } else if method == "POST" && path == "/api/refresh" {
            onRefreshState { jsonData in
                self.sendResponse(clientFD, status: "200 OK", contentType: "application/json; charset=utf-8", body: jsonData)
            }
        } else if method == "POST" && path == "/api/save" {
            onSaveState(bodyData) { ok in
                let resp = Data((ok ? "{\"ok\":true}" : "{\"ok\":false}").utf8)
                self.sendResponse(clientFD, status: ok ? "200 OK" : "400 Bad Request", contentType: "application/json; charset=utf-8", body: resp)
            }
        } else {
            sendResponse(clientFD, status: "404 Not Found", contentType: "text/plain", body: Data("Not Found".utf8))
        }
    }

    private func sendResponse(_ fd: Int32, status: String, contentType: String, body: Data) {
        let header = "HTTP/1.1 \(status)\r\nContent-Type: \(contentType)\r\nContent-Length: \(body.count)\r\nConnection: close\r\n\r\n"
        var packet = Data(header.utf8)
        packet.append(body)
        packet.withUnsafeBytes { ptr in
            if let base = ptr.baseAddress {
                _ = write(fd, base, packet.count)
            }
        }
        close(fd)
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate {
    private var panel: NSPanel!
    private var statusItem: NSStatusItem!
    private var store = StatusStore()
    private var dragState = DragStateObservable()
    private var webServer: LocalSetupServer!

    private let posXKey = "widget_pos_x"
    private let posYKey = "widget_pos_y"
    private let launchAgentLabel = "com.local.ai-status-widget"

    private var launchAgentPath: String {
        NSHomeDirectory() + "/Library/LaunchAgents/\(launchAgentLabel).plist"
    }

    private var isLaunchAtLoginEnabled: Bool {
        FileManager.default.fileExists(atPath: launchAgentPath)
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)

        store.onLocaleChanged = { [weak self] _ in
            self?.statusItem.menu = self?.buildMenu()
        }

        setupWebServer()
        setupMenuBar()
        setupDesktopPanel()
    }

    private func buildStateJSON() -> Data {
        let cfg = store.loadConfig()
        var dict: [String: Any] = ["launch_at_login": isLaunchAtLoginEnabled]
        if let payload = store.payload,
           let pData = try? JSONEncoder().encode(payload),
           let pObj = try? JSONSerialization.jsonObject(with: pData) {
            dict["payload"] = pObj
        }
        if let cData = try? JSONEncoder().encode(cfg),
           let cObj = try? JSONSerialization.jsonObject(with: cData) {
            dict["config"] = cObj
        }
        return (try? JSONSerialization.data(withJSONObject: dict)) ?? Data("{}".utf8)
    }

    private func setupWebServer() {
        webServer = LocalSetupServer(
            htmlPath: store.setupHtmlPath,
            onGetState: { [weak self] reply in
                Task { @MainActor in
                    reply(self?.buildStateJSON() ?? Data("{}".utf8))
                }
            },
            onRefreshState: { [weak self] reply in
                Task { @MainActor in
                    guard let self else {
                        reply(Data("{}".utf8))
                        return
                    }
                    self.store.refresh {
                        reply(self.buildStateJSON())
                    }
                }
            },
            onSaveState: { [weak self] bodyData, reply in
                Task { @MainActor in
                    guard let self,
                          let body = try? JSONSerialization.jsonObject(with: bodyData) as? [String: Any] else {
                        reply(false)
                        return
                    }
                    var cfg = self.store.loadConfig()
                    if let loc = body["locale"] as? String {
                        cfg.locale = loc
                    }
                    if let freq = body["refresh_interval_sec"] as? Int {
                        cfg.refresh_interval_sec = freq
                    }
                    if let agyReset = body["agy_reset_at"] as? String {
                        cfg.antigravity.reset_at = agyReset
                    } else if body["agy_reset_at"] is NSNull {
                        cfg.antigravity.reset_at = nil
                    }
                    if let rem = body["wb_credits_remaining"] as? Double {
                        cfg.workbuddy.credits_anchor_value = rem
                        cfg.workbuddy.credits_anchor_at_ms = Int64(Date().timeIntervalSince1970 * 1000)
                    } else if body["wb_credits_remaining"] is NSNull {
                        cfg.workbuddy.credits_anchor_value = nil
                        cfg.workbuddy.credits_anchor_at_ms = nil
                    }
                    if let wbReset = body["wb_reset_at"] as? String {
                        cfg.workbuddy.reset_at = wbReset
                    } else if body["wb_reset_at"] is NSNull {
                        cfg.workbuddy.reset_at = nil
                    }
                    if let login = body["launch_at_login"] as? Bool {
                        self.setLaunchAtLogin(login)
                    }
                    self.store.saveConfig(cfg)
                    reply(true)
                }
            }
        )
    }

    private func setupMenuBar() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        if let btn = statusItem.button {
            let img = NSImage(systemSymbolName: "bolt.circle.fill", accessibilityDescription: "AI Status")
            img?.isTemplate = true
            btn.image = img
        }
        statusItem.menu = buildMenu()
    }

    private func clampedOrigin(_ origin: NSPoint, size: NSSize) -> NSPoint {
        let vf = NSScreen.main?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1280, height: 800)
        let x = min(max(origin.x, vf.minX + 8), vf.maxX - size.width - 8)
        let y = min(max(origin.y, vf.minY + 8), vf.maxY - size.height - 8)
        return NSPoint(x: x, y: y)
    }

    private func makeGlassBackground(frame: NSRect) -> NSView {
        if let glassCls = NSClassFromString("NSGlassEffectView") as? NSView.Type {
            let glass = glassCls.init(frame: frame)
            glass.wantsLayer = true
            glass.layer?.cornerRadius = 16
            glass.layer?.masksToBounds = true
            glass.layer?.shadowOpacity = 0.0
            if glass.responds(to: NSSelectorFromString("setStyle:")) {
                glass.setValue(1, forKey: "style") // 1 = NSGlassEffectViewStyleClear
            }
            return glass
        }
        let effect = NSVisualEffectView(frame: frame)
        effect.material = .hudWindow
        effect.blendingMode = .behindWindow
        effect.state = .active
        effect.wantsLayer = true
        effect.layer?.cornerRadius = 16
        effect.layer?.masksToBounds = true
        effect.layer?.shadowOpacity = 0.0
        return effect
    }

    private func setupDesktopPanel() {
        let width: CGFloat = 344
        let height: CGFloat = 116
        let size = NSSize(width: width, height: height)
        let vf = NSScreen.main?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1280, height: 800)

        let defaults = UserDefaults.standard
        let rawOrigin: NSPoint
        if defaults.object(forKey: posXKey) != nil, defaults.object(forKey: posYKey) != nil {
            rawOrigin = NSPoint(x: defaults.double(forKey: posXKey), y: defaults.double(forKey: posYKey))
        } else {
            rawOrigin = NSPoint(x: vf.maxX - width - 24, y: vf.maxY - height - 20)
        }
        let origin = clampedOrigin(rawOrigin, size: size)

        panel = NSPanel(
            contentRect: NSRect(origin: origin, size: size),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.delegate = self
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.hidesOnDeactivate = false
        panel.level = NSWindow.Level(rawValue: -2147483602)
        panel.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle]
        panel.isMovableByWindowBackground = false

        let glass = makeGlassBackground(frame: NSRect(origin: .zero, size: size))
        let hosting = GlassWidgetHostView(rootView: WidgetView(store: store, dragState: dragState))
        hosting.dragState = dragState
        hosting.onDragFinished = { [weak self] in
            guard let self else { return }
            let pos = self.clampedOrigin(self.panel.frame.origin, size: size)
            self.panel.setFrameOrigin(pos)
            UserDefaults.standard.set(Double(pos.x), forKey: self.posXKey)
            UserDefaults.standard.set(Double(pos.y), forKey: self.posYKey)
        }
        hosting.frame = glass.bounds
        hosting.autoresizingMask = [.width, .height]

        glass.addSubview(hosting)
        panel.contentView = glass
        panel.orderBack(nil)
    }

    private func buildMenu() -> NSMenu {
        let isZh = store.locale == "zh"
        let menu = NSMenu()

        let wizardItem = NSMenuItem(title: isZh ? "设置向导..." : "Settings Wizard...", action: #selector(onOpenWizard), keyEquivalent: ",")
        wizardItem.target = self
        menu.addItem(wizardItem)

        let restartItem = NSMenuItem(title: isZh ? "重启" : "Restart", action: #selector(onRestart), keyEquivalent: "r")
        restartItem.target = self
        menu.addItem(restartItem)

        let quitItem = NSMenuItem(title: isZh ? "退出" : "Quit", action: #selector(onQuit), keyEquivalent: "q")
        quitItem.target = self
        menu.addItem(quitItem)

        return menu
    }

    private func setLaunchAtLogin(_ enabled: Bool) {
        let fm = FileManager.default
        if !enabled {
            try? fm.removeItem(atPath: launchAgentPath)
        } else {
            let dir = (launchAgentPath as NSString).deletingLastPathComponent
            try? fm.createDirectory(atPath: dir, withIntermediateDirectories: true)
            let execPath = Bundle.main.executablePath ?? (Bundle.main.bundlePath + "/Contents/MacOS/AIStatusWidget")
            let plist = """
            <?xml version="1.0" encoding="UTF-8"?>
            <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
            <plist version="1.0">
            <dict>
                <key>Label</key>
                <string>\(launchAgentLabel)</string>
                <key>ProgramArguments</key>
                <array>
                    <string>\(execPath)</string>
                </array>
                <key>RunAtLoad</key>
                <true/>
            </dict>
            </plist>
            """
            try? plist.write(toFile: launchAgentPath, atomically: true, encoding: .utf8)
        }
    }

    @objc private func onOpenWizard() {
        let port = webServer.startIfNeeded()
        if port > 0, let url = URL(string: "http://127.0.0.1:\(port)/") {
            NSWorkspace.shared.open(url)
        }
    }

    @objc private func onRestart() {
        let bundleURL = Bundle.main.bundleURL
        let config = NSWorkspace.OpenConfiguration()
        config.createsNewApplicationInstance = true
        NSWorkspace.shared.openApplication(at: bundleURL, configuration: config) { _, _ in
            Task { @MainActor in
                NSApp.terminate(nil)
            }
        }
    }

    @objc private func onQuit() { NSApp.terminate(nil) }
}

MainActor.assumeIsolated {
    let app = NSApplication.shared
    let delegate = AppDelegate()
    app.delegate = delegate
    app.run()
}
