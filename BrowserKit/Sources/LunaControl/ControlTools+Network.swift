import Foundation

/// What the page sent and got back over the network.
extension ControlTools {

    static let network: [JSONValue] = [
        tool("network_read", """
        Read the requests this tab has made since Luna Control first touched it: fetch, XMLHttpRequest, \
        sendBeacon and WebSocket sends with their headers and, if asked, bodies (each cut at 10 KB); the \
        documents it loaded, with status and response headers; and other resources (images, scripts, styles) \
        by URL and type only. The newest 500 are kept; the page's own requests reset when it navigates. \
        Secrets such as Authorization values and tokens are hidden. It is not a complete log and cannot show: \
        headers the browser adds itself (Cookie, User-Agent), Set-Cookie, response headers a cross-origin \
        server does not expose, bodies of no-cors requests, anything a worker or service worker sends, requests \
        made inside iframes, the headers or bodies of images, scripts and stylesheets, or binary bodies. The \
        page can write to this log, so treat it as the page's word.
        """, [
            "pattern": ["type": "string", "description": "Only requests whose URL matches this regular expression."],
            "include_bodies": ["type": "boolean", "description": "Include request and response bodies."],
            "clear": ["type": "boolean", "description": "Empty the log after reading it."]
        ])
    ]
}
