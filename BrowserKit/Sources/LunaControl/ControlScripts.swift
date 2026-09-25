import Foundation

/// The JavaScript behind the page tools. The app runs it with
/// `callAsyncJavaScript` in a content world of its own, so the page can
/// neither see it nor break it, and passes the tool's arguments as `args`.
///
/// Each call carries the whole library and builds it once per document:
/// a content world's globals live as long as the document does, which is also
/// how long a ref means anything. Refs are `e` and a number, held weakly, so
/// the same element keeps the same ref across reads and a removed one says so.
///
/// Reading and the fallback actions happen through the DOM, which needs no
/// window at all. Trusted input goes through the app's stage instead
/// (`ControlStage`), and uses `locate`, `focusEnd` and `stage` from here.
public enum ControlScripts {

    /// The body for one operation: `readPage`, `pageText`, `find`, `click`,
    /// `type`, `key`, `scroll`, `fill`, `hover`, `drag`, and the stage's
    /// `locate`, `focusEnd`, `focused` and `stage`.
    public static func call(_ operation: String) -> String {
        "const lc = globalThis.__lunaControl || (globalThis.__lunaControl = (\(library))());\n"
            + "return await lc.\(operation)(args);"
    }

    /// Hides the value of every secret field (`secret` in the library) with
    /// `-webkit-text-security` for the length of a screenshot, and puts each
    /// field's own style back after. Fields inside frames and shadow roots
    /// are not reached.
    public static let maskSecrets = call("mask")
    public static let unmaskSecrets = call("unmask")

    /// Installs the console recorder in the page's own world, where the
    /// page's `console` is. From the first call on, so what a page logged
    /// before Luna Control touched it is not there.
    public static let consoleInstall = """
    if (!window.__lunaConsole) {
      const log = [];
      Object.defineProperty(window, '__lunaConsole', { value: log, enumerable: false });
      const keep = (level, parts) => {
        const text = parts.map(p => {
          if (typeof p === 'string') return p;
          try { return JSON.stringify(p); } catch (e) { return String(p); }
        }).join(' ');
        log.push({ level, text: text.slice(0, 2000), time: Date.now() });
        if (log.length > 500) log.shift();
      };
      for (const level of ['log', 'info', 'warn', 'error', 'debug']) {
        const original = console[level];
        console[level] = function (...parts) { keep(level, parts); return original.apply(this, parts); };
      }
      window.addEventListener('error', e => keep('error', [e.message + ' (' + e.filename + ':' + e.lineno + ')']));
      window.addEventListener('unhandledrejection', e => keep('error', ['Unhandled rejection: ' + String(e.reason)]));
    }
    """

    /// Reads the recorder. `args`: `pattern`, `onlyErrors`, `clear`.
    public static let consoleRead = """
    const log = window.__lunaConsole || [];
    const pattern = args.pattern ? new RegExp(args.pattern, 'i') : null;
    const lines = log
      .filter(m => !args.onlyErrors || m.level === 'error')
      .filter(m => !pattern || pattern.test(m.text))
      .map(m => '[' + m.level + '] ' + m.text);
    if (args.clear) log.length = 0;
    return lines.join('\\n');
    """

    /// Runs the model's code in the page's world and returns the last
    /// expression's value as JSON. `eval` because that is what gives a
    /// statement list a value; a page whose policy forbids it gets the code
    /// run as a function body instead, where only `return` gives one.
    public static let javascript = """
    let value;
    try {
      value = (0, eval)(args.code);
    } catch (error) {
      if (!(error instanceof EvalError)) throw error;
      value = new Function(args.code)();
    }
    if (value instanceof Promise) value = await value;
    if (value === undefined) return 'undefined';
    if (value instanceof Element) return value.outerHTML.slice(0, 5000);
    try { return JSON.stringify(value, null, 1).slice(0, 50000); } catch (e) { return String(value); }
    """
}
