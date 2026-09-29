import Foundation

final class AppStore {
    private let defaults = UserDefaults.standard
    private let accountsKey = "accounts-v2"
    private let configsKey = "configs-v1"
    private let platformKey = "browser-platform"
    private let rebateClearKey = "rebate-urls-cleared-ios-117"

    init() {
        clearRebateURLsOnce()
    }

    func configs() -> [RechargeConfig] {
        guard let data = defaults.data(forKey: configsKey),
              let value = try? JSONDecoder().decode([RechargeConfig].self, from: data),
              !value.isEmpty else { return defaultConfigs() }
        return value
    }

    func saveConfigs(_ items: [RechargeConfig]) {
        if let data = try? JSONEncoder().encode(items) { defaults.set(data, forKey: configsKey) }
    }

    func accounts() -> [String: AccountRecord] {
        guard let data = KeychainStore.readData(account: accountsKey),
              let value = try? JSONDecoder().decode([String: AccountRecord].self, from: data) else { return [:] }
        return value
    }

    func saveAccounts(_ value: [String: AccountRecord]) {
        if let data = try? JSONEncoder().encode(value) { KeychainStore.writeData(data, account: accountsKey) }
    }

    func publicAccounts() -> [String: [String: Double]] {
        var out: [String: [String: Double]] = [:]
        for (qq, record) in accounts() {
            if let b = record.balance { out[qq] = ["balance": b] }
            else { out[qq] = [:] }
        }
        return out
    }

    func browserPlatform() -> String {
        defaults.string(forKey: platformKey) == "ios" ? "ios" : "android"
    }

    func setBrowserPlatform(_ value: String) {
        guard value == "android" || value == "ios" else { return }
        defaults.set(value, forKey: platformKey)
    }

    private func defaultConfigs() -> [RechargeConfig] {
        [
            RechargeConfig(title: "王者荣耀", type: "充值官网", url: ""),
            RechargeConfig(title: "和平精英-IOS", type: "充值官网", url: ""),
            RechargeConfig(title: "和平精英-安卓", type: "充值官网", url: ""),
            RechargeConfig(title: "无畏契约", type: "心悦", url: ""),
            RechargeConfig(title: "英雄联盟手游-IOS", type: "充值官网", url: ""),
            RechargeConfig(title: "英雄联盟手游-安卓", type: "充值官网", url: ""),
            RechargeConfig(title: "金铲铲", type: "充值官网", url: "")
        ]
    }

    private func clearRebateURLsOnce() {
        guard !defaults.bool(forKey: rebateClearKey) else { return }
        let source: [RechargeConfig]
        if let data = defaults.data(forKey: configsKey),
           let stored = try? JSONDecoder().decode([RechargeConfig].self, from: data),
           !stored.isEmpty {
            source = stored
        } else {
            source = defaultConfigs()
        }
        let cleared = source.map { RechargeConfig(title: $0.title, type: $0.type, url: "") }
        if let data = try? JSONEncoder().encode(cleared) { defaults.set(data, forKey: configsKey) }
        defaults.set(true, forKey: rebateClearKey)
    }
}
