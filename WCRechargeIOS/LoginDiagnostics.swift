import Foundation
import UIKit
import WebKit

/** Process-local, bounded, redacted diagnostics. Nothing is automatically uploaded or written to a file. */
enum LoginDiagnostics {
    private static let lock = NSLock()
    private static var events: [String] = []
    private static var last = ""
    private static let start = ProcessInfo.processInfo.systemUptime

    static func event(_ fixedText: String) {
        guard !fixedText.isEmpty else { return }
        lock.lock(); defer { lock.unlock() }
        if fixedText == last { return }
        last = fixedText
        let seconds = Int(max(0, ProcessInfo.processInfo.systemUptime - start))
        events.append("+\(seconds)s \(fixedText)")
        if events.count > 300 { events.removeFirst(events.count - 300) }
    }

    static func nativeResult(url: String, code: Int) {
        event("HTTP \(code) \(DiagnosticRedactor.route(url))")
    }

    static func snapshot(_ rows: [CookieRow]) {
        let watched: Set<String> = ["uin", "p_uin", "skey", "p_skey", "pt4_token"]
        var total = 0
        for row in rows where !row.isExpired {
            total += 1
            guard watched.contains(row.name) else { continue }
            let same = ["None", "Lax", "Strict"].contains(row.sameSite) ? row.sameSite : "unset"
            event("saved \(row.name) \(DiagnosticRedactor.route("https://\(row.domain)\(row.path)")) hostOnly=\(row.hostOnly) secure=\(row.secure) httpOnly=\(row.httpOnly) sameSite=\(same) persistent=\(row.expiresAt > 0)")
        }
        event("saved rows=\(total)")
    }

    static func live(expectedQQ: String) async {
        let cookies = await WebSessionManager.shared.allCookies()
        let hosts = ["pay.qq.com", "pagedoo.pay.qq.com", "storeapi.pay.qq.com", "xui.ptlogin2.qq.com", "api.unipay.qq.com"]
        let names = ["uin", "p_uin", "skey", "p_skey", "pt4_token"]
        for host in hosts {
            var parts = ["live \(host)"]
            for name in names {
                var count = 0
                var matches = true
                for cookie in cookies where cookie.name == name && WebSessionManager.shared.cookieApplies(cookie, to: host) && !cookie.value.isEmpty {
                    count += 1
                    if name == "uin" || name == "p_uin" {
                        matches = matches && WebSessionManager.shared.normalizeQQ(cookie.value) == expectedQQ
                    }
                }
                var value = "\(name)=\(count)"
                if count > 0 && (name == "uin" || name == "p_uin") { value += matches ? ":match" : ":different" }
                parts.append(value)
            }
            event(parts.joined(separator: " "))
        }
    }

    static func page(_ web: WKWebView, completion: @escaping () -> Void) {
        let js = "(function(){return {password:!!document.querySelector('input[type=password]'),frames:Array.from(document.querySelectorAll('iframe')).slice(0,12).map(function(f){return f.src;})};})()"
        web.evaluateJavaScript(js) { value, _ in
            if let obj = value as? [String: Any] {
                self.event("main password field=\((obj["password"] as? Bool) == true)")
                if let frames = obj["frames"] as? [String] {
                    for frame in frames { self.event("iframe \(DiagnosticRedactor.route(frame))") }
                }
            } else {
                self.event("DOM observation unavailable")
            }
            completion()
        }
    }

    static func report() -> String {
        lock.lock(); let copy = events; lock.unlock()
        let device = UIDevice.current
        var text = "WC iOS 1.0.17 运行诊断（不代表登录成功）\n"
        text += "iOS=\(device.systemVersion)\n"
        text += "Device=\(device.model)\n"
        text += "WebView=WKWebView\n"
        for item in copy { text += item + "\n" }
        return text
    }

    @MainActor static func show(from controller: UIViewController) {
        let text = report()
        let alert = UIAlertController(title: "运行诊断", message: text, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "复制诊断", style: .default) { _ in
            UIPasteboard.general.string = text
        })
        alert.addAction(UIAlertAction(title: "关闭", style: .cancel))
        controller.present(alert, animated: true)
    }
}
