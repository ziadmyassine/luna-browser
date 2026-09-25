import Foundation

/// `network_read`'s recorder and reader. The recorder runs in the page's own
/// world, because the page's `fetch` is the one it has to wrap, which also
/// means the page can read and rewrite the log: what it holds is untrusted.
///
/// The app adds the recorder as a document-start user script, main frame
/// only, to a tab the first time an agent touches it, and runs it once more
/// straight away for the document already open. Requests a page made before
/// that are not there, except what resource timing still has buffered.
extension ControlScripts {

    /// Each body is cut here, request and response alike.
    public static let networkBodyLimit = 10_240
    /// The log keeps the newest this many entries.
    public static let networkEntryLimit = 500

    /// Wraps `fetch`, `XMLHttpRequest`, `sendBeacon` and `WebSocket.send`, and
    /// takes everything else from resource timing: URL, type, status where
    /// WebKit gives one, no headers or bodies. A response body is read from a
    /// clone and only up to the limit, then that branch is cancelled, so a
    /// large or endless stream costs 10 KB rather than all of it.
    public static let networkInstall = """
    (() => {
      if (window.__lunaNetwork) return;
      const LIMIT = \(networkEntryLimit), BODY = \(networkBodyLimit);
      const log = [];
      Object.defineProperty(window, '__lunaNetwork', { value: log, enumerable: false });
      const keep = entry => { log.push(entry); if (log.length > LIMIT) log.shift(); return entry; };
      const cut = text => text.length > BODY ? text.slice(0, BODY) + ' [cut at 10 KB]' : text;
      const absolute = url => { try { return new URL(String(url), location.href).href; } catch (e) { return String(url); } };
      const since = start => Math.round(performance.now() - start);
      const headersOf = headers => {
        const out = {};
        try { new Headers(headers || {}).forEach((value, name) => { out[name] = value; }); } catch (e) {}
        return out;
      };
      const textual = type => /^(text\\/|application\\/([\\w.+-]*\\+)?(json|xml|javascript|x-www-form-urlencoded))/i
        .test(type || '');
      const describe = body => {
        if (body === undefined || body === null) return undefined;
        if (typeof body === 'string') return cut(body);
        if (body instanceof URLSearchParams) return cut(body.toString());
        if (body instanceof FormData) return '[form data: ' + [...body.keys()].join(', ') + ']';
        if (body instanceof Blob) return '[' + body.size + ' bytes, ' + (body.type || 'binary') + ']';
        if (body instanceof ArrayBuffer || ArrayBuffer.isView(body)) return '[' + body.byteLength + ' bytes]';
        return '[not read]';
      };
      const readCapped = async response => {
        const reader = response.body.getReader();
        const decoder = new TextDecoder();
        let text = '';
        try {
          while (text.length <= BODY) {
            const { done, value } = await reader.read();
            if (done) return cut(text + decoder.decode());
            text += decoder.decode(value, { stream: true });
          }
          reader.cancel().catch(() => {});
          return cut(text);
        } catch (e) { return cut(text) + ' [unreadable]'; }
      };

      const originalFetch = window.fetch;
      if (originalFetch) window.fetch = function (input, init) {
        const request = input instanceof Request ? input : null;
        const entry = keep({
          kind: 'fetch', time: Date.now(),
          method: String((init && init.method) || (request && request.method) || 'GET').toUpperCase(),
          url: absolute(request ? request.url : input),
          requestHeaders: headersOf((init && init.headers) || (request && request.headers)),
          requestBody: init && init.body !== undefined ? describe(init.body) : (request && request.body ? '[not read]' : undefined)
        });
        const start = performance.now();
        const pending = originalFetch.apply(this, arguments);
        pending.then(response => {
          entry.status = response.status;
          entry.duration = since(start);
          entry.responseHeaders = headersOf(response.headers);
          if (response.type === 'opaque') entry.note = 'no-cors: the page cannot see the response either';
          if (response.body && textual(response.headers.get('content-type'))) {
            readCapped(response.clone()).then(text => { entry.responseBody = text; });
          }
        }, error => { entry.error = String((error && error.message) || error); });
        return pending;
      };

      const xhr = XMLHttpRequest.prototype;
      const open = xhr.open, send = xhr.send, setHeader = xhr.setRequestHeader;
      const pendingXHR = new WeakMap();
      xhr.open = function (method, url) {
        pendingXHR.set(this, { kind: 'xhr', method: String(method).toUpperCase(), url: absolute(url), requestHeaders: {} });
        return open.apply(this, arguments);
      };
      xhr.setRequestHeader = function (name, value) {
        const entry = pendingXHR.get(this);
        if (entry) entry.requestHeaders[String(name).toLowerCase()] = String(value);
        return setHeader.apply(this, arguments);
      };
      xhr.send = function (body) {
        const entry = pendingXHR.get(this);
        if (entry) {
          entry.time = Date.now();
          entry.requestBody = describe(body);
          keep(entry);
          const start = performance.now();
          this.addEventListener('loadend', () => {
            entry.status = this.status;
            entry.duration = since(start);
            entry.responseHeaders = {};
            for (const line of this.getAllResponseHeaders().trim().split(/[\\r\\n]+/)) {
              const colon = line.indexOf(':');
              if (colon > 0) entry.responseHeaders[line.slice(0, colon).trim().toLowerCase()] = line.slice(colon + 1).trim();
            }
            try {
              if ((this.responseType === '' || this.responseType === 'text')
                  && textual(this.getResponseHeader('content-type'))) entry.responseBody = cut(this.responseText);
              else if (this.responseType === 'json') entry.responseBody = cut(JSON.stringify(this.response));
            } catch (e) {}
          });
        }
        return send.apply(this, arguments);
      };

      const beacon = navigator.sendBeacon;
      if (beacon) navigator.sendBeacon = function (url, data) {
        keep({ kind: 'beacon', method: 'POST', url: absolute(url), time: Date.now(), requestBody: describe(data) });
        return beacon.apply(this, arguments);
      };

      if (window.WebSocket) {
        const wsSend = WebSocket.prototype.send;
        WebSocket.prototype.send = function (data) {
          keep({ kind: 'websocket', method: 'SEND', url: this.url, time: Date.now(), requestBody: describe(data) });
          return wsSend.apply(this, arguments);
        };
      }

      // Installed before the page's own script ran, the wrappers saw every
      // fetch, XHR and beacon, so timing's copies of them would be doubles.
      const wrapped = new Set(document.readyState === 'loading' ? ['fetch', 'xmlhttprequest', 'beacon'] : []);
      try {
        new PerformanceObserver(list => {
          for (const timing of list.getEntries()) {
            if (wrapped.has(timing.initiatorType)) continue;
            keep({
              kind: 'resource', type: timing.initiatorType, url: timing.name,
              time: Math.round(performance.timeOrigin + timing.startTime), duration: Math.round(timing.duration),
              status: timing.responseStatus || undefined
            });
          }
        }).observe({ type: 'resource', buffered: true });
      } catch (e) {}
    })();
    """

    /// Reads the recorder, one line per request and its headers indented
    /// under it. `args`: `pattern` (matched against the URL), `includeBodies`,
    /// `clear`, and `documents` — the app's own entries for the documents the
    /// tab loaded, from `WKNavigationResponse`, in the same shape.
    public static let networkRead = """
    const log = window.__lunaNetwork || [];
    const pattern = args.pattern ? new RegExp(args.pattern, 'i') : null;
    const entries = (args.documents || []).concat(log).sort((a, b) => (a.time || 0) - (b.time || 0));
    const lines = [];
    const indent = text => String(text).replace(/\\n/g, '\\n    ');
    for (const e of entries) {
      if (pattern && !pattern.test(e.url)) continue;
      let line = e.kind + (e.type ? ' ' + e.type : '') + (e.method ? ' ' + e.method : '') + ' ' + e.url;
      if (e.status !== undefined) line += ' → ' + e.status;
      const notes = [e.frame, e.duration !== undefined ? e.duration + ' ms' : null,
                     e.error ? 'failed: ' + e.error : null, e.note].filter(Boolean);
      if (notes.length) line += ' (' + notes.join(', ') + ')';
      lines.push(line);
      for (const [name, value] of Object.entries(e.requestHeaders || {})) lines.push('  > ' + name + ': ' + value);
      for (const [name, value] of Object.entries(e.responseHeaders || {})) lines.push('  < ' + name + ': ' + value);
      if (args.includeBodies) {
        if (e.requestBody !== undefined) lines.push('  request body: ' + indent(e.requestBody));
        if (e.responseBody !== undefined) lines.push('  response body: ' + indent(e.responseBody));
      }
    }
    if (args.clear) log.length = 0;
    return lines.join('\\n');
    """
}
