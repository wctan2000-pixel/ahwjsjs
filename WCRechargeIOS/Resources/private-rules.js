(function () {
'use strict';
if (window.__wc_private_rules_v1) return;
Object.defineProperty(window, '__wc_private_rules_v1', {value: true});
const rules = [{"match": "web_save", "replacements": [["wx_appid=", "wx_appid=101502376"]]}, {"match": "mobile_save_goods", "replacements": [["wx_appid=wx951bdcac522929b6", "wx_appid=101502376"], ["wx_appid=wx5a3bbeac0d87c75a", "wx_appid=101502376"]]}];
function enabled() { try { return window.WCRuleState && window.WCRuleState.isEnabled(); } catch (_) { return false; } }
function relevant(url) { return enabled() && rules.some(r => String(url).indexOf(r.match) !== -1); }
function rewrite(url, body) {
  if (!enabled() || typeof body !== 'string') return body;
  const original = body;
  for (const r of rules) {
    if (String(url).indexOf(r.match) === -1) continue;
    for (const pair of r.replacements) body = body.split(pair[0]).join(pair[1]);
  }
  if (body !== original) { try { window.WCRuleState.recordApplied(); } catch (_) {} }
  return body;
}
function rewriteBody(url, body) {
  if (typeof body === 'string') return rewrite(url, body);
  if (typeof URLSearchParams !== 'undefined' && body instanceof URLSearchParams) {
    const original = body.toString(), updated = rewrite(url, original);
    return updated === original ? body : updated;
  }
  return body;
}
const urls = new WeakMap();
if (window.XMLHttpRequest) {
  const proto = window.XMLHttpRequest.prototype, open = proto.open, send = proto.send;
  proto.open = function (method, url) {
    const result = open.apply(this, arguments);
    urls.set(this, String(url));
    return result;
  };
  proto.send = function (body) {
    const args = Array.from(arguments);
    if (args.length && relevant(urls.get(this) || '')) args[0] = rewriteBody(urls.get(this), body);
    return send.apply(this, args);
  };
}
if (window.fetch) {
  const originalFetch = window.fetch;
  window.fetch = function (input, init) {
    const receiver = this, args = arguments;
    const isRequest = typeof Request !== 'undefined' && input instanceof Request;
    const url = isRequest ? input.url : String(input);
    if (!relevant(url)) return originalFetch.apply(receiver, args);
    if (init && init.body != null) {
      const updated = rewriteBody(url, init.body);
      if (updated !== init.body) return originalFetch.call(receiver, input, Object.assign({}, init, {body: updated}));
      return originalFetch.apply(receiver, args);
    }
    if (isRequest && input.body && !input.bodyUsed) {
      const type = input.headers.get('content-type') || '';
      if (type.indexOf('application/x-www-form-urlencoded') === 0 || type.indexOf('text/') === 0) {
        return input.clone().text().then(text => {
          const updated = rewrite(url, text);
          if (updated === text) return originalFetch.apply(receiver, args);
          // Preserve the Request's headers, credentials, method, and redirect policy.
          return originalFetch.call(receiver, new Request(input, {body: updated}), init);
        });
      }
    }
    return originalFetch.apply(receiver, args);
  };
}
})();
