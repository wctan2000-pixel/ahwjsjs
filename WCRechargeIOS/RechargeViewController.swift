import UIKit
import WebKit

final class RechargeViewController: UIViewController, WKNavigationDelegate, WKUIDelegate, WKScriptMessageHandler {
    let plan: RechargePlan
    let reusePayer: Bool
    var onRequestPayerScan: (() -> Void)?
    var onGameSessionCleared: (() -> Void)?

    private var web: WKWebView!
    private let statusLabel = UILabel()
    private var forceButton: UIButton!
    private var ruleButton: UIButton!

    private var phase = "preparing"
    private var payerInstalled = false
    private var cookiesReady = false
    private var warmupScheduled = false
    private var deferredInjected = false
    private var deferredAttempts = 0
    private var riskStopped = false
    private var observedPayerQQ = ""
    private var lastRole = ""
    private var lastServer = ""
    private var lastHTTPStatus = 0
    private var forceQuantity: UInt64 = 0
    private var privateRulesEnabled = false
    private var privateRuleApplied = 0
    private var recentLinks: [RecentLink] = []

    init(plan: RechargePlan, reusePayer: Bool) {
        self.plan = plan
        self.reusePayer = reusePayer
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func viewDidLoad() {
        super.viewDidLoad()
        title = "充值页面 · \(plan.browserLabel)"
        view.backgroundColor = .systemBackground
        buildUI()
        LoginDiagnostics.event("page preparation reuse=\(reusePayer) profile=\(plan.browserLabel == "安卓" ? "android" : "ios")")
        beginPreparation()
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        if isMovingFromParent {
            setPrivateRules(false)
            web.stopLoading()
        }
    }

    deinit {
        let ucc = web?.configuration.userContentController
        ucc?.removeScriptMessageHandler(forName: "ruleApplied")
        ucc?.removeScriptMessageHandler(forName: "recentLink")
        web?.stopLoading()
    }

    private func buildUI() {
        let config = WebContext.rechargeConfiguration()
        config.userContentController.add(self, name: "ruleApplied")
        config.userContentController.add(self, name: "recentLink")
        configureDocumentScripts(on: config.userContentController, enabled: false)

        web = WKWebView(frame: .zero, configuration: config)
        web.navigationDelegate = self
        web.uiDelegate = self
        web.allowsBackForwardNavigationGestures = true
        if !plan.userAgent.isEmpty { web.customUserAgent = plan.userAgent }

        statusLabel.font = .systemFont(ofSize: 12)
        statusLabel.textColor = .secondaryLabel
        statusLabel.numberOfLines = 3
        statusLabel.text = "正在准备登录状态…"

        forceButton = button("强改", action: #selector(showForceMenu))
        let scanButton = button("重扫QQ", action: #selector(rescan))
        let stateButton = button("状态", action: #selector(showStatus))
        let headButtons = UIStackView(arrangedSubviews: [forceButton, scanButton, stateButton])
        headButtons.axis = .horizontal
        headButtons.spacing = 8
        headButtons.distribution = .fillEqually

        let head = UIStackView(arrangedSubviews: [statusLabel, headButtons])
        head.axis = .vertical
        head.spacing = 6

        let toolsScroll = UIScrollView()
        toolsScroll.showsHorizontalScrollIndicator = false
        toolsScroll.alwaysBounceHorizontal = true
        let tools = UIStackView()
        tools.axis = .horizontal
        tools.spacing = 6
        tools.translatesAutoresizingMaskIntoConstraints = false
        let back = button("后退", action: #selector(goBack))
        let forward = button("前进", action: #selector(goForward))
        let refresh = button("刷新", action: #selector(refreshPage))
        let clear = button("换号清理", action: #selector(clearGameSession))
        let links = button("最近链接", action: #selector(showRecentLinks))
        ruleButton = button("规则：关", action: #selector(toggleRules))
        let diagnostic = button("诊断", action: #selector(showDiagnostics))
        [back, forward, refresh, clear, links, ruleButton!, diagnostic].forEach {
            $0.widthAnchor.constraint(greaterThanOrEqualToConstant: 76).isActive = true
            tools.addArrangedSubview($0)
        }
        toolsScroll.addSubview(tools)
        NSLayoutConstraint.activate([
            tools.leadingAnchor.constraint(equalTo: toolsScroll.contentLayoutGuide.leadingAnchor, constant: 4),
            tools.trailingAnchor.constraint(equalTo: toolsScroll.contentLayoutGuide.trailingAnchor, constant: -4),
            tools.topAnchor.constraint(equalTo: toolsScroll.contentLayoutGuide.topAnchor, constant: 2),
            tools.bottomAnchor.constraint(equalTo: toolsScroll.contentLayoutGuide.bottomAnchor, constant: -2),
            tools.heightAnchor.constraint(equalTo: toolsScroll.frameLayoutGuide.heightAnchor, constant: -4)
        ])

        head.translatesAutoresizingMaskIntoConstraints = false
        web.translatesAutoresizingMaskIntoConstraints = false
        toolsScroll.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(head)
        view.addSubview(web)
        view.addSubview(toolsScroll)
        NSLayoutConstraint.activate([
            head.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 6),
            head.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 10),
            head.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -10),
            headButtons.heightAnchor.constraint(equalToConstant: 38),

            web.topAnchor.constraint(equalTo: head.bottomAnchor, constant: 6),
            web.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            web.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            web.bottomAnchor.constraint(equalTo: toolsScroll.topAnchor),

            toolsScroll.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            toolsScroll.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            toolsScroll.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor),
            toolsScroll.heightAnchor.constraint(equalToConstant: 48)
        ])
    }

    private func button(_ title: String, action: Selector) -> UIButton {
        let b = UIButton(type: .system)
        b.setTitle(title, for: .normal)
        b.titleLabel?.font = .systemFont(ofSize: 13, weight: .semibold)
        b.addTarget(self, action: action, for: .touchUpInside)
        return b
    }

    private func configureDocumentScripts(on controller: WKUserContentController, enabled: Bool) {
        controller.removeAllUserScripts()
        let initial = enabled ? "true" : "false"
        let shim = """
        (function(){
          'use strict';
          if(window.__wc_rule_bridge_v1){try{window.__wcSetPrivateRules(\(initial));}catch(_){ } return;}
          Object.defineProperty(window,'__wc_rule_bridge_v1',{value:true});
          var state=\(initial);
          function propagate(){
            try{var fs=document.querySelectorAll?document.querySelectorAll('iframe'):[];for(var i=0;i<fs.length;i++){try{fs[i].contentWindow.postMessage({__wcPrivateRuleState:state},'*');}catch(_){}}}catch(_){}
          }
          function set(v){state=!!v;window.__wc_private_rules_enabled=state;propagate();}
          window.WCRuleState={
            isEnabled:function(){return !!state;},
            recordApplied:function(){try{window.webkit.messageHandlers.ruleApplied.postMessage(1);}catch(_){} }
          };
          window.__wcSetPrivateRules=function(v){set(v);};
          window.addEventListener('message',function(e){try{if(e&&e.data&&Object.prototype.hasOwnProperty.call(e.data,'__wcPrivateRuleState'))set(!!e.data.__wcPrivateRuleState);}catch(_){}});
          try{new MutationObserver(function(){propagate();}).observe(document.documentElement||document,{childList:true,subtree:true});}catch(_){}
          set(state);
        })();
        """
        controller.addUserScript(WKUserScript(source: shim, injectionTime: .atDocumentStart, forMainFrameOnly: false))
        if let rules = bundledText("private-rules", "js") {
            controller.addUserScript(WKUserScript(source: rules, injectionTime: .atDocumentStart, forMainFrameOnly: false))
        }
        if let recent = bundledText("recent-links", "js") {
            controller.addUserScript(WKUserScript(source: recent, injectionTime: .atDocumentStart, forMainFrameOnly: false))
        }
    }

    private func bundledText(_ name: String, _ ext: String) -> String? {
        guard let url = Bundle.main.url(forResource: name, withExtension: ext) else { return nil }
        return try? String(contentsOf: url, encoding: .utf8)
    }

    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        switch message.name {
        case "ruleApplied":
            if privateRulesEnabled { privateRuleApplied += 1 }
        case "recentLink":
            if let raw = message.body as? String { recordURL(raw) }
        default: break
        }
    }

    private func setPrivateRules(_ enabled: Bool) {
        privateRulesEnabled = enabled
        if !enabled { privateRuleApplied = 0 }
        ruleButton?.setTitle(enabled ? "规则：开" : "规则：关", for: .normal)
        if web != nil {
            configureDocumentScripts(on: web.configuration.userContentController, enabled: enabled)
            web.evaluateJavaScript("window.__wcSetPrivateRules&&window.__wcSetPrivateRules(\(enabled ? "true" : "false"));", completionHandler: nil)
        }
    }

    @objc private func toggleRules() {
        guard phase == "ready" else { statusLabel.text = "请等待页面准备完成。"; return }
        setPrivateRules(!privateRulesEnabled)
        statusLabel.text = privateRulesEnabled ? "本次规则已启用" : "规则已关闭"
    }

    private func beginPreparation() {
        guard plan.payerQQ.range(of: "^[0-9]{5,12}$", options: .regularExpression) != nil,
              !plan.cookies.isEmpty,
              let target = URL(string: plan.url), target.scheme == "https", isQQHost(target.host) else {
            fail("充值链接或付款 QQ 凭据无效，请返回检查。")
            return
        }
        Task { @MainActor in
            if reusePayer {
                let matched = await WebSessionManager.shared.payerCookieMatches(expectedQQ: plan.payerQQ, host: "pay.qq.com")
                guard matched else { fail("付款 QQ 登录已失效，请返回重新扫码。"); return }
            }
            if !plan.warmupURL.isEmpty {
                phase = "warming"
                let start = min(plan.cookies.count, plan.beforeWarmup.count)
                let rows = reusePayer ? Array(plan.beforeWarmup.dropFirst(start)) : plan.beforeWarmup
                guard await WebSessionManager.shared.install(rows) else { fail("付款账号状态写入失败，请返回重试。"); return }
                payerInstalled = true
                WebSessionManager.shared.bind(payerQQ: plan.payerQQ, source: plan.sourceCookies)
                statusLabel.text = "正在初始化登录站点…"
                load(plan.warmupURL)
                Task { @MainActor [weak self] in
                    try? await Task.sleep(nanoseconds: 25_000_000_000)
                    guard let self, self.phase == "warming" else { return }
                    self.fail("登录站点初始化超时，请检查网络后返回重试。")
                }
            } else {
                await prepareAllCookies()
            }
        }
    }

    private func prepareAllCookies() async {
        guard canPrepare else { return }
        phase = "preparing"
        if !(reusePayer || payerInstalled) {
            guard await WebSessionManager.shared.install(plan.cookies) else { fail("付款 QQ 凭据未完整载入，请返回重新扫码。"); return }
        }
        let base = await WebSessionManager.shared.payerCookieMatches(expectedQQ: plan.payerQQ, host: "pay.qq.com")
        let page = await WebSessionManager.shared.payerCookieMatches(expectedQQ: plan.payerQQ, host: "pagedoo.pay.qq.com")
        let api = await WebSessionManager.shared.payerCookieMatches(expectedQQ: plan.payerQQ, host: "storeapi.pay.qq.com")
        guard base else { fail("付款 QQ 凭据未完整载入，请返回重新扫码。"); return }
        guard page && api else { fail("付款子域凭据未就绪，请重扫QQ后再试。"); return }
        LoginDiagnostics.event("cookie write/readback complete; server acceptance unknown")
        await LoginDiagnostics.live(expectedQQ: plan.payerQQ)
        cookiesReady = true
        payerInstalled = true
        WebSessionManager.shared.bind(payerQQ: plan.payerQQ, source: plan.sourceCookies)
        phase = "ready"
        statusLabel.text = "付款 QQ 凭据已载入，正在打开网页；实际付款账号尚待确认。"
        load(plan.url)
    }

    private var canPrepare: Bool {
        phase != "failed" && phase != "clearing" && phase != "cleared"
    }

    private func load(_ raw: String) {
        guard let url = URL(string: raw) else { fail("页面地址无效。"); return }
        var request = URLRequest(url: url)
        request.setValue("zh-CN,zh;q=0.9,en;q=0.8", forHTTPHeaderField: "Accept-Language")
        web.load(request)
    }

    func webView(_ webView: WKWebView, didStartProvisionalNavigation navigation: WKNavigation!) {
        guard canPrepare else { return }
        let raw = webView.url?.absoluteString ?? ""
        LoginDiagnostics.event("navigation \(DiagnosticRedactor.route(raw))")
        WebSessionManager.shared.remember(raw)
        recordURL(raw)
        lastHTTPStatus = 0
        statusLabel.text = phase == "warming" ? "正在初始化登录站点…" : "正在加载网页…"
        if phase == "ready", let url = webView.url, maybeInjectDeferredCK(url) { return }
        if phase == "ready" {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.08) { [weak self] in self?.syncPrivateRuleState() }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) { [weak self] in self?.applyForceScript() }
        }
    }

    func webView(_ webView: WKWebView, didCommit navigation: WKNavigation!) {
        if phase == "ready" {
            syncPrivateRuleState()
            applyForceScript()
        }
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        guard canPrepare else { return }
        let raw = webView.url?.absoluteString ?? ""
        WebSessionManager.shared.remember(raw)
        recordURL(raw)
        if phase == "warming" {
            guard !warmupScheduled else { return }
            warmupScheduled = true
            let delay: UInt64 = URL(string: plan.warmupURL)?.host?.lowercased() == "xinyue.qq.com" ? 1_200_000_000 : 250_000_000
            Task { @MainActor [weak self] in
                try? await Task.sleep(nanoseconds: delay)
                guard let self else { return }
                await self.prepareAllCookies()
            }
            return
        }
        guard phase == "ready" else { return }
        if let url = webView.url, maybeInjectDeferredCK(url) { return }
        if !riskStopped { statusLabel.text = "网页文档已加载，请核对登录账号、大区及充值档位。" }
        syncPrivateRuleState()
        applyForceScript()
        detectRiskAndIdentity()
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { [weak self] in self?.detectRiskAndIdentity() }
        DispatchQueue.main.asyncAfter(deadline: .now() + 4.0) { [weak self] in self?.detectRiskAndIdentity() }
    }

    func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction,
                 decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
        guard let url = navigationAction.request.url else { decisionHandler(.cancel); return }
        WebSessionManager.shared.remember(url.absoluteString)
        recordURL(url.absoluteString)
        let scheme = url.scheme?.lowercased() ?? ""
        if scheme == "http" || scheme == "https" {
            if navigationAction.targetFrame?.isMainFrame == true, phase == "ready", maybeInjectDeferredCK(url) {
                decisionHandler(.cancel)
                return
            }
            decisionHandler(.allow)
            return
        }
        let external: Set<String> = ["weixin", "mqq", "mqqapi", "mqqopensdkapi", "alipays"]
        if external.contains(scheme), navigationAction.navigationType == .linkActivated {
            UIApplication.shared.open(url, options: [:], completionHandler: nil)
        }
        decisionHandler(.cancel)
    }

    func webView(_ webView: WKWebView, decidePolicyFor navigationResponse: WKNavigationResponse,
                 decisionHandler: @escaping (WKNavigationResponsePolicy) -> Void) {
        if let response = navigationResponse.response as? HTTPURLResponse {
            LoginDiagnostics.event("web HTTP=\(response.statusCode) main=\(navigationResponse.isForMainFrame) \(DiagnosticRedactor.route(response.url?.absoluteString))")
            if navigationResponse.isForMainFrame {
                lastHTTPStatus = response.statusCode
                if response.statusCode >= 400 {
                    statusLabel.text = "网页服务器返回 HTTP \(response.statusCode)，请返回检查链接或稍后重试。"
                }
            }
        }
        decisionHandler(.allow)
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        if (error as NSError).code == NSURLErrorCancelled { return }
        LoginDiagnostics.event("web error reason=\(DiagnosticRedactor.failure(error)) main=true \(DiagnosticRedactor.route(webView.url?.absoluteString))")
        statusLabel.text = "网页加载失败。请检查网络，或返回重新打开。"
    }

    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        if (error as NSError).code == NSURLErrorCancelled { return }
        LoginDiagnostics.event("web provisional error reason=\(DiagnosticRedactor.failure(error)) main=true \(DiagnosticRedactor.route(webView.url?.absoluteString))")
        statusLabel.text = "网页加载失败。请检查网络，或返回重新打开。"
    }

    func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {
        LoginDiagnostics.event("WebKit content process terminated")
        statusLabel.text = "网页进程已重新启动，请点刷新或返回重新打开。"
    }

    func webView(_ webView: WKWebView, createWebViewWith configuration: WKWebViewConfiguration,
                 for navigationAction: WKNavigationAction, windowFeatures: WKWindowFeatures) -> WKWebView? {
        if let url = navigationAction.request.url, url.scheme == "https" || url.scheme == "http" {
            webView.load(navigationAction.request)
        }
        return nil
    }

    private func maybeInjectDeferredCK(_ url: URL) -> Bool {
        guard plan.deferCkInjection, !riskStopped, !plan.ckParams.isEmpty,
              url.scheme?.lowercased() == "https", url.host?.lowercased() == "pagedoo.pay.qq.com" else { return false }

        if urlContainsCurrentCK(url) {
            deferredInjected = true
            LoginDiagnostics.event("Xinyue merged navigation reached final page")
            return false
        }
        if deferredInjected { return false }
        if deferredAttempts > 0 { return true }

        guard let merged = mergeCK(into: url), merged != url else {
            LoginDiagnostics.event("Xinyue merge failed before navigation")
            fail("最终充值页登录信息融合失败，请返回重试。")
            return true
        }
        deferredAttempts += 1
        statusLabel.text = "已到最终充值页，正在载入登录状态…"
        LoginDiagnostics.event("Xinyue merged navigation scheduled")
        DispatchQueue.main.async { [weak self] in
            guard let self, self.phase == "ready", !self.riskStopped else { return }
            self.load(merged.absoluteString)
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 12) { [weak self] in
            guard let self, self.phase == "ready", !self.deferredInjected else { return }
            LoginDiagnostics.event("Xinyue merged navigation did not start")
            self.fail("最终充值页登录信息未成功载入，请返回重试。")
        }
        return true
    }

    private func urlContainsCurrentCK(_ url: URL) -> Bool {
        guard let c = URLComponents(url: url, resolvingAgainstBaseURL: false) else { return false }
        let items = Dictionary(uniqueKeysWithValues: (c.queryItems ?? []).map { ($0.name, $0.value ?? "") })
        let expectedOpenid = plan.ckParams["openid"] ?? plan.ckParams["open_id"] ?? ""
        let expectedOpenkey = plan.ckParams["openkey"] ?? plan.ckParams["open_key"] ?? plan.ckParams["access_token"] ?? ""
        let gotOpenid = items["openid"] ?? items["open_id"] ?? ""
        let gotOpenkey = items["openkey"] ?? items["open_key"] ?? items["access_token"] ?? ""
        return !expectedOpenid.isEmpty && !expectedOpenkey.isEmpty && expectedOpenid == gotOpenid && expectedOpenkey == gotOpenkey
    }

    private func mergeCK(into url: URL) -> URL? {
        guard url.scheme?.lowercased() == "https", isQQHost(url.host), var c = URLComponents(url: url, resolvingAgainstBaseURL: false) else { return nil }
        var order: [String] = []
        var merged: [String: String] = [:]
        for item in c.queryItems ?? [] {
            if merged[item.name] == nil { order.append(item.name) }
            merged[item.name] = item.value ?? ""
        }
        let original = merged
        var ckKeys = Set<String>()
        for (key, value) in plan.ckParams where !key.isEmpty && !value.contains(";") && !value.contains("\n") && !value.contains("\r") {
            ckKeys.insert(key)
            if merged[key] == nil { order.append(key) }
            merged[key] = value
        }
        guard let openid = merged["openid"], !openid.isEmpty,
              let openkey = merged["openkey"], !openkey.isEmpty else { return nil }
        c.queryItems = order.compactMap { key in merged[key].map { URLQueryItem(name: key, value: $0) } }
        guard let final = c.url,
              let check = URLComponents(url: final, resolvingAgainstBaseURL: false) else { return nil }
        let finalMap = Dictionary(uniqueKeysWithValues: (check.queryItems ?? []).map { ($0.name, $0.value ?? "") })
        for (k, v) in original {
            guard let got = finalMap[k] else { return nil }
            if !ckKeys.contains(k) && got != v { return nil }
        }
        return final
    }

    private func syncPrivateRuleState() {
        guard phase == "ready" else { return }
        web.evaluateJavaScript("window.__wcSetPrivateRules&&window.__wcSetPrivateRules(\(privateRulesEnabled ? "true" : "false"));", completionHandler: nil)
    }

    private func forceScript(_ quantity: UInt64) -> String {
        let value = quantity > 0 ? String(quantity) : "null"
        return #"""
        (function(){try{
          var q=\#(value);window.__wc_force_change_quantity=(Number.isInteger(q)&&q>0)?q:null;
          function install(w){try{
            w.__wc_force_change_quantity=window.__wc_force_change_quantity;
            if(!w.__wc_force_change_xhr_installed){
              w.__wc_force_change_xhr_installed=true;
              var original=w.XMLHttpRequest&&w.XMLHttpRequest.prototype.send;
              if(original){w.XMLHttpRequest.prototype.send=function(body){
                var wanted=w.__wc_force_change_quantity;
                if(Number.isInteger(wanted)&&typeof body==='string'){
                  body=body.replace(/(\\"quantity\\"\s*:\s*)\d+/g,'$1'+wanted).replace(/("quantity"\s*:\s*)\d+/g,'$1'+wanted);
                }
                return original.call(this,body);
              };}
            }
            var fs=w.document&&w.document.querySelectorAll?w.document.querySelectorAll('iframe'):[];
            for(var i=0;i<fs.length;i++){try{install(fs[i].contentWindow);}catch(e){}}
          }catch(e){}}
          install(window);
          try{new MutationObserver(function(){install(window);}).observe(document.documentElement||document,{childList:true,subtree:true});}catch(e){}
        }catch(e){}})();
        """#
    }

    private func applyForceScript() {
        guard phase == "ready" else { return }
        web.evaluateJavaScript(forceScript(forceQuantity), completionHandler: nil)
    }

    @objc private func showForceMenu() {
        guard phase != "clearing", phase != "cleared" else { return }
        let alert = UIAlertController(title: forceQuantity > 0 ? "当前 X\(forceQuantity)" : "强改倍率", message: nil, preferredStyle: .actionSheet)
        alert.addAction(UIAlertAction(title: "X50", style: .default) { [weak self] _ in self?.setForce(50) })
        alert.addAction(UIAlertAction(title: "X100", style: .default) { [weak self] _ in self?.setForce(100) })
        alert.addAction(UIAlertAction(title: "任意", style: .default) { [weak self] _ in self?.showCustomForce() })
        if forceQuantity > 0 { alert.addAction(UIAlertAction(title: "关闭强改", style: .destructive) { [weak self] _ in self?.setForce(0) }) }
        alert.addAction(UIAlertAction(title: "取消", style: .cancel))
        present(alert, animated: true)
    }

    private func showCustomForce() {
        let alert = UIAlertController(title: "任意倍率", message: "请输入正整数", preferredStyle: .alert)
        alert.addTextField { field in
            field.keyboardType = .numberPad
            field.placeholder = "例如：5"
        }
        alert.addAction(UIAlertAction(title: "取消", style: .cancel))
        alert.addAction(UIAlertAction(title: "确定", style: .default) { [weak self, weak alert] _ in
            guard let self,
                  let raw = alert?.textFields?.first?.text?.trimmingCharacters(in: .whitespacesAndNewlines),
                  let value = UInt64(raw), value > 0, value <= 9_007_199_254_740_991 else {
                self?.statusLabel.text = "强改倍率无效，请输入有效正整数。"
                return
            }
            self.setForce(value)
        })
        present(alert, animated: true)
    }

    private func setForce(_ value: UInt64) {
        forceQuantity = value
        forceButton?.setTitle(value > 0 ? "X\(value)" : "强改", for: .normal)
        applyForceScript()
    }

    @objc private func goBack() { if web.canGoBack { web.goBack() } }
    @objc private func goForward() { if web.canGoForward { web.goForward() } }

    @objc private func refreshPage() {
        guard phase == "ready" else { statusLabel.text = "请返回重新打开页面。"; return }
        if riskStopped {
            statusLabel.text = "腾讯已提示交易风险，本 App 已停止自动重试；请按页面提示处理。"
            return
        }
        let alert = UIAlertController(title: "刷新网页", message: "将重新加载当前页面；如刚完成操作，请先确认结果。", preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "取消", style: .cancel))
        alert.addAction(UIAlertAction(title: "刷新", style: .default) { [weak self] _ in
            self?.setPrivateRules(false)
            self?.web.reload()
        })
        present(alert, animated: true)
    }

    @objc private func rescan() {
        setPrivateRules(false)
        phase = "cleared"
        web.stopLoading()
        onRequestPayerScan?()
    }

    @objc private func clearGameSession() {
        guard phase != "failed", phase != "clearing" else { return }
        setPrivateRules(false)
        phase = "clearing"
        web.stopLoading()
        recentLinks.removeAll()
        statusLabel.text = "正在清理旧游戏数据，保留付款 QQ 登录…"
        web.loadHTMLString("<meta name='viewport' content='width=device-width'><p>正在清理旧游戏数据，保留付款 QQ 登录…</p>", baseURL: nil)
        Task { @MainActor in
            let ok = await WebSessionManager.shared.clearGameKeepingPayer(source: plan.sourceCookies)
            guard phase == "clearing" else { return }
            if !ok {
                phase = "failed"
                statusLabel.text = "部分旧游戏数据未清理成功，请重试换号清理。"
                return
            }
            phase = "cleared"
            onGameSessionCleared?()
            navigationController?.popViewController(animated: true)
        }
    }

    private func recordURL(_ raw: String) {
        guard raw.count <= 24_000, let url = URL(string: raw),
              url.scheme?.lowercased() == "https", url.host?.lowercased() == "pay.qq.com",
              url.path == "/h5/index.shtml",
              let c = URLComponents(url: url, resolvingAgainstBaseURL: false) else { return }
        let map = Dictionary(uniqueKeysWithValues: (c.queryItems ?? []).map { ($0.name, $0.value ?? "") })
        guard map["m"] == "buy", map["c"] == "goods" else { return }
        if recentLinks.contains(where: { $0.url == raw }) { return }
        let formatter = DateFormatter()
        formatter.dateFormat = "MM-dd HH:mm:ss"
        recentLinks.insert(RecentLink(time: formatter.string(from: Date()), url: raw), at: 0)
        if recentLinks.count > 6 { recentLinks.removeLast(recentLinks.count - 6) }
    }

    @objc private func showRecentLinks() {
        guard !recentLinks.isEmpty else {
            let a = UIAlertController(title: "最近链接", message: "暂无记录", preferredStyle: .alert)
            a.addAction(UIAlertAction(title: "关闭", style: .default))
            present(a, animated: true)
            return
        }
        let a = UIAlertController(title: "最近链接（点击复制）", message: nil, preferredStyle: .actionSheet)
        for item in recentLinks {
            a.addAction(UIAlertAction(title: "\(item.time)\n\(item.url)", style: .default) { _ in
                UIPasteboard.general.string = item.url
            })
        }
        a.addAction(UIAlertAction(title: "清空", style: .destructive) { [weak self] _ in self?.recentLinks.removeAll() })
        a.addAction(UIAlertAction(title: "关闭", style: .cancel))
        present(a, animated: true)
    }

    @objc private func showStatus() {
        Task { @MainActor in
            let pay = await WebSessionManager.shared.payerCookieMatches(expectedQQ: plan.payerQQ, host: "pay.qq.com")
            let page = await WebSessionManager.shared.payerCookieMatches(expectedQQ: plan.payerQQ, host: "pagedoo.pay.qq.com")
            let api = await WebSessionManager.shared.payerCookieMatches(expectedQQ: plan.payerQQ, host: "storeapi.pay.qq.com")
            let site = web.url?.host ?? URL(string: plan.url)?.host ?? "未知"
            let ck = plan.deferCkInjection ? (deferredInjected ? "已完成" : "未完成") : "入口已合并"
            let force = forceQuantity > 0 ? "X\(forceQuantity)" : "关闭"
            var message = "版本：1.0.17"
            message += "\n浏览器类型：\(plan.browserLabel)"
            message += "\n站点：\(site)"
            message += "\n登录字段准备：\(cookiesReady ? "完成" : "未完成")"
            message += "\n主页面 HTTP：\(lastHTTPStatus == 0 ? "未记录" : String(lastHTTPStatus))"
            message += "\n游戏CK跳转注入：\(ck)"
            message += "\n规则：\(privateRulesEnabled ? "已启用" : "关闭")"
            message += "\n规则改写次数：\(privateRuleApplied)"
            message += "\n强改：\(force)"
            message += "\n所选付款 QQ：\(plan.payerQQ)"
            message += "\npagedoo 本地凭据：\(page ? "QQ匹配" : "缺失或不匹配")"
            message += "\nstoreapi 本地凭据：\(api ? "QQ匹配" : "缺失或不匹配")"
            message += "\n本地付款凭据：\(pay ? "与所选 QQ 匹配" : "缺失或不匹配")"
            message += "\n网页付款 QQ：\(observedPayerQQ.isEmpty ? "尚未确认" : observedPayerQQ)"
            if !lastRole.isEmpty { message += "\n游戏角色：\(lastRole)" }
            if !lastServer.isEmpty { message += "\n区服：\(lastServer)" }
            if riskStopped { message += "\n交易风险：腾讯页面已提示，自动重试已停止" }
            message += "\n\(statusLabel.text ?? "")"
            let a = UIAlertController(title: "页面状态", message: message, preferredStyle: .alert)
            a.addAction(UIAlertAction(title: "关闭", style: .default))
            present(a, animated: true)
        }
    }

    @objc private func showDiagnostics() {
        Task { @MainActor in
            await LoginDiagnostics.live(expectedQQ: plan.payerQQ)
            LoginDiagnostics.page(web) { [weak self] in
                guard let self else { return }
                DispatchQueue.main.async { LoginDiagnostics.show(from: self) }
            }
        }
    }

    private func detectRiskAndIdentity() {
        guard phase == "ready" else { return }
        let js = #"(function(){var t=document.body?document.body.innerText:'';var lines=t.split(/\r?\n/).map(function(x){return x.trim();}).filter(Boolean);var riskLine='';for(var i=0;i<lines.length;i++){if(/(交易风险|存在风险|风险提示|支付风险|交易存在风险)/.test(lines[i])){riskLine=lines[i].slice(0,180);break;}}var q=t.match(/(?:付款|支付)\s*(?:QQ|ＱＱ)(?:\s*(?:账号|帐号|号))?\s*[:：]?\s*([1-9][0-9]{4,11})(?![0-9])/i);var r=t.match(/(?:角色名|角色|昵称)\s*[:：]?\s*([^\n\r]{1,40})/);var s=t.match(/(?:区服|服务器|大区)\s*[:：]?\s*([^\n\r]{1,40})/);return {risk:!!riskLine,riskText:riskLine,qq:q?q[1]:'',role:r?r[1].trim():'',server:s?s[1].trim():''};})()"#
        let observedURL = web.url?.absoluteString ?? ""
        web.evaluateJavaScript(js) { [weak self] value, _ in
            guard let self, let obj = value as? [String: Any], self.phase == "ready",
                  observedURL == (self.web.url?.absoluteString ?? "") else { return }
            if obj["risk"] as? Bool == true {
                self.riskStopped = true
                self.setPrivateRules(false)
                self.setForce(0)
                let riskText = (obj["riskText"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                self.statusLabel.text = riskText.isEmpty ? "腾讯页面已提示交易风险，已停止本 App 的自动重试。" : "腾讯提示：\(riskText)｜已停止本 App 的自动重试。"
                return
            }
            if let qq = obj["qq"] as? String, qq.range(of: "^[0-9]{5,12}$", options: .regularExpression) != nil {
                self.observedPayerQQ = qq
                if qq != self.plan.payerQQ {
                    self.fail("网页付款 QQ 与所选账号不一致，请点 重扫QQ 重新登录。")
                    return
                }
            }
            self.lastRole = obj["role"] as? String ?? ""
            self.lastServer = obj["server"] as? String ?? ""
            var pieces: [String] = []
            if !self.lastRole.isEmpty { pieces.append("角色：\(self.lastRole)") }
            if !self.lastServer.isEmpty { pieces.append("区服：\(self.lastServer)") }
            if !self.observedPayerQQ.isEmpty { pieces.append("付款QQ：\(self.observedPayerQQ)") }
            self.statusLabel.text = pieces.isEmpty ? "网页已加载。付款前请在腾讯页面核对游戏角色、区服与实际付款 QQ。" : "请核对后再付款：" + pieces.joined(separator: " · ")
        }
    }

    private func fail(_ text: String) {
        LoginDiagnostics.event("page stopped during preparation/identity check")
        phase = "failed"
        setPrivateRules(false)
        statusLabel.text = text
        web?.stopLoading()
        let html = "<meta name='viewport' content='width=device-width'><p style='font:16px -apple-system;padding:20px'>\(escapeHTML(text))</p>"
        web?.loadHTMLString(html, baseURL: nil)
    }

    private func isQQHost(_ host: String?) -> Bool {
        guard let h = host?.lowercased() else { return false }
        return h == "qq.com" || h.hasSuffix(".qq.com")
    }

    private func escapeHTML(_ s: String) -> String {
        s.replacingOccurrences(of: "&", with: "&amp;")
         .replacingOccurrences(of: "<", with: "&lt;")
         .replacingOccurrences(of: ">", with: "&gt;")
         .replacingOccurrences(of: "\"", with: "&quot;")
    }
}
