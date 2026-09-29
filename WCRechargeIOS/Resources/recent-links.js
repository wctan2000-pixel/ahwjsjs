(function () {
  'use strict';
  if (window.__wcRecentLinks) return;
  window.__wcRecentLinks = true;
  var seen = Object.create(null), count = 0;
  function record(value) {
    if (typeof value !== 'string' || value.length > 24000 || !/^https:\/\/pay\.qq\.com\/h5\/index\.shtml\?/.test(value)) return;
    if (seen[value] || count >= 100) return;
    seen[value] = true; count++;
    try { window.webkit.messageHandlers.recentLink.postMessage(value); } catch (_) {}
  }
  function scan() { try { performance.getEntriesByType('resource').forEach(function (entry) { record(entry.name); }); } catch (_) {} }
  window.addEventListener('load', scan);
  try {
    var observer = new PerformanceObserver(function (list) { list.getEntries().forEach(function (entry) { record(entry.name); }); });
    observer.observe({entryTypes:['resource']});
  } catch (_) {}
  scan();
})();
