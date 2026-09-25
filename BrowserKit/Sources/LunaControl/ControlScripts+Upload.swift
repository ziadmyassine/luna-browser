import Foundation

/// `file_upload`'s operation, spliced into the library's operations so it
/// shares `element` and `describe`. Its own file to keep the library under
/// the length limit.
extension ControlScripts {

    /// A file input is given the files as if they were picked, then input
    /// and change; anything else has them dropped on it, for drop zones that
    /// have no input at all.
    static let upload = """
    function (args) {
          const el = element(args.ref);
          const transfer = new DataTransfer();
          for (const f of args.files) transfer.items.add(new File([Uint8Array.fromBase64(f.data)], f.name, { type: f.mimeType }));
          const count = args.files.length + (args.files.length === 1 ? ' file' : ' files');
          if (el.tagName !== 'INPUT' || el.type !== 'file') {
            const init = { bubbles: true, cancelable: true, composed: true, dataTransfer: transfer };
            for (const type of ['dragenter', 'dragover', 'drop']) el.dispatchEvent(new DragEvent(type, init));
            return 'Dropped ' + count + ' on ' + describe(el);
          }
          if (!el.multiple && args.files.length > 1) throw new Error(describe(el) + ' takes one file.');
          el.files = transfer.files;
          for (const type of ['input', 'change']) el.dispatchEvent(new Event(type, { bubbles: true, composed: true }));
          return 'Gave ' + count + ' to ' + describe(el);
        }
    """
}
