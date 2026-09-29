import Foundation

/** Outputs fixed route/failure categories only; never emits query values or response bodies. */
enum DiagnosticRedactor {
    private static let hosts: Set<String> = [
        "qq.com", "pay.qq.com", "pagedoo.pay.qq.com", "storeapi.pay.qq.com",
        "api.unipay.qq.com", "ssl.ptlogin2.qq.com", "xui.ptlogin2.qq.com",
        "ptlogin2.qq.com", "scp.qq.com", "xinyue.qq.com"
    ]
    private static let paths: Set<String> = [
        "/", "/cgi-bin/xlogin", "/ptqrshow", "/ptqrlogin", "/check_sig",
        "/h5/h5_login_jump.shtml", "/index.shtml", "/h5/index.shtml",
        "/pc/account/index.shtml", "/v1/r/1450000186/wechat_query"
    ]

    static func route(_ raw: String?) -> String {
        guard let raw, let url = URL(string: raw), let originalHost = url.host?.lowercased() else { return "other" }
        let safeHost: String
        if hosts.contains(originalHost) { safeHost = originalHost }
        else if originalHost == "qq.com" || originalHost.hasSuffix(".qq.com") { safeHost = "other-qq" }
        else { safeHost = "other-site" }
        let path = url.path.isEmpty ? "/" : url.path
        return safeHost + (paths.contains(path) ? path : "/other")
    }

    static func failure(_ error: Error) -> String {
        let ns = error as NSError
        if ns.domain == NSURLErrorDomain {
            switch ns.code {
            case NSURLErrorCannotFindHost, NSURLErrorDNSLookupFailed: return "DNS"
            case NSURLErrorTimedOut: return "TIMEOUT"
            case NSURLErrorSecureConnectionFailed, NSURLErrorServerCertificateHasBadDate,
                 NSURLErrorServerCertificateUntrusted, NSURLErrorServerCertificateHasUnknownRoot,
                 NSURLErrorServerCertificateNotYetValid, NSURLErrorClientCertificateRejected,
                 NSURLErrorClientCertificateRequired: return "TLS"
            case NSURLErrorCannotConnectToHost, NSURLErrorNetworkConnectionLost, NSURLErrorNotConnectedToInternet: return "CONNECT"
            default: return "IO"
            }
        }
        return "OTHER"
    }
}
