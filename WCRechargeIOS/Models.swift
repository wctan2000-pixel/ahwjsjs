import Foundation
import WebKit

struct CookieRow: Encodable, Equatable {
    var name: String
    var value: String
    var domain: String
    var path: String
    var hostOnly: Bool
    var secure: Bool
    var httpOnly: Bool
    var sameSite: String
    var expiresAt: Double

    var isExpired: Bool { expiresAt > 0 && expiresAt <= Date().timeIntervalSince1970 * 1000 }

    func matches(host: String, path requestPath: String = "/") -> Bool {
        let d = domain.trimmingCharacters(in: CharacterSet(charactersIn: ".")).lowercased()
        let h = host.lowercased()
        let domainOK = hostOnly ? h == d : (h == d || h.hasSuffix("." + d))
        guard domainOK else { return false }
        let p = path.isEmpty ? "/" : path
        return requestPath == p || requestPath.hasPrefix(p.hasSuffix("/") ? p : p + "/") || p == "/"
    }

    func asHTTPCookie() -> HTTPCookie? {
        guard !name.isEmpty, !value.isEmpty, !domain.isEmpty, path.hasPrefix("/") else { return nil }
        let cleanDomain = domain.trimmingCharacters(in: CharacterSet(charactersIn: ".")).lowercased()
        guard !cleanDomain.isEmpty else { return nil }
        var props: [HTTPCookiePropertyKey: Any] = [
            .name: name,
            .value: value,
            .path: path,
            .secure: secure ? "TRUE" : "FALSE"
        ]
        if hostOnly {
            props[.originURL] = URL(string: "https://\(cleanDomain)\(path)") as Any
            props[.domain] = cleanDomain
        } else {
            props[.domain] = "." + cleanDomain
        }
        if httpOnly { props[HTTPCookiePropertyKey(rawValue: "HttpOnly")] = "TRUE" }
        if ["None", "Lax", "Strict"].contains(sameSite) {
            props[HTTPCookiePropertyKey(rawValue: "SameSite")] = sameSite
        }
        if expiresAt > 0 { props[.expires] = Date(timeIntervalSince1970: expiresAt / 1000) }
        return HTTPCookie(properties: props)
    }
}

extension CookieRow: Decodable {
    enum CodingKeys: String, CodingKey {
        case name, value, domain, path, hostOnly, secure, httpOnly, sameSite, expiresAt
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        name = try c.decode(String.self, forKey: .name)
        value = try c.decode(String.self, forKey: .value)
        domain = try c.decode(String.self, forKey: .domain)
        path = try c.decodeIfPresent(String.self, forKey: .path) ?? "/"
        hostOnly = try c.decodeIfPresent(Bool.self, forKey: .hostOnly) ?? true
        secure = try c.decodeIfPresent(Bool.self, forKey: .secure) ?? true
        httpOnly = try c.decodeIfPresent(Bool.self, forKey: .httpOnly) ?? false
        sameSite = try c.decodeIfPresent(String.self, forKey: .sameSite) ?? ""
        expiresAt = try c.decodeIfPresent(Double.self, forKey: .expiresAt) ?? 0
    }
}

struct AccountRecord: Codable {
    var cookies: [String: String]
    var cookieRows: [CookieRow]
    var cookieSchema: Int
    var balance: Double?
}

struct RechargeConfig: Codable, Equatable {
    var title: String
    var type: String
    var url: String
}

struct RechargePlan {
    let url: String
    let payerQQ: String
    let sourceCookies: [CookieRow]
    let cookies: [CookieRow]
    let userAgent: String
    let browserLabel: String
    let warmupURL: String
    let beforeWarmup: [CookieRow]
    let deferCkInjection: Bool
    let ckParams: [String: String]
}

struct RecentLink: Equatable {
    let time: String
    let url: String
}

enum WCError: LocalizedError {
    case message(String)
    var errorDescription: String? {
        if case .message(let text) = self { return text }
        return "操作失败"
    }
}

enum WebContext {
    static let processPool = WKProcessPool()
    static let dataStore = WKWebsiteDataStore.default()

    static func rechargeConfiguration() -> WKWebViewConfiguration {
        let c = WKWebViewConfiguration()
        c.processPool = processPool
        c.websiteDataStore = dataStore
        c.preferences.javaScriptCanOpenWindowsAutomatically = true
        c.defaultWebpagePreferences.allowsContentJavaScript = true
        c.allowsInlineMediaPlayback = true
        c.mediaTypesRequiringUserActionForPlayback = []
        return c
    }

    static func panelConfiguration() -> WKWebViewConfiguration {
        let c = WKWebViewConfiguration()
        c.processPool = WKProcessPool()
        c.websiteDataStore = .nonPersistent()
        c.preferences.javaScriptCanOpenWindowsAutomatically = false
        c.defaultWebpagePreferences.allowsContentJavaScript = true
        return c
    }

    static func configuration() -> WKWebViewConfiguration { rechargeConfiguration() }
}
