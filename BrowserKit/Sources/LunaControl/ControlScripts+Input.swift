import Foundation

/// The library's input operations beyond clicking and typing: where trusted
/// input should land, hover, drag, and the stage mode that keeps native
/// popups off the user's screen. Spliced into the object `library` returns,
/// so it shares that closure's helpers (`target`, `point`, `describe`, …).
extension ControlScripts {

    static let inputOperations = """
        // Where a trusted event should land, and whether it must go another
        // way: a native popup (select, date, colour, file) would open on the
        // user's screen, and a draggable element would start a real drag.
        locate(args) {
          const el = target(args);
          const at = point(el, args);
          const hit = args.ref ? el : document.elementFromPoint(at.x, at.y) || el;
          const control = hit.closest('label')?.control || hit;
          const type = control.tagName === 'INPUT' ? (control.type || '').toLowerCase() : '';
          const route = hit.closest('select') ? 'form_input'
            : ['date', 'datetime-local', 'month', 'week', 'color'].includes(type) ? 'form_input'
            : type === 'file' ? 'file_upload' : null;
          let draggable = false;
          for (let n = hit; n && !draggable; n = n.parentElement) draggable = n.draggable === true;
          return JSON.stringify({ x: at.x, y: at.y, route, draggable, name: describe(hit) });
        },
        // Before trusted typing: the field to type into, focused with the
        // caret at the end, or the one with focus. Keys sent to a page with
        // no field focused are its shortcuts. A frame passes unexamined: the
        // field is inside it, as in editors that type into an iframe.
        focusEnd(args) {
          const el = args.ref ? element(args.ref) : document.activeElement;
          if (!editable(el) && el?.tagName !== 'IFRAME') {
            throw new Error(args.ref ? describe(el) + ' does not take text.'
              : 'Nothing that takes text has focus. Pass the ref of a text field.');
          }
          if (!args.ref) return describe(el);
          el.focus();
          // Typing appends. Email and number fields refuse a selection range and throw.
          try { el.setSelectionRange(el.value.length, el.value.length); } catch (e) {}
          if (el.isContentEditable) getSelection().collapse(el, el.childNodes.length);
          return describe(el);
        },
        focused() {
          return document.activeElement ? describe(document.activeElement) : '';
        },
        hover(args) {
          const el = target(args);
          const at = point(el, args);
          const hit = args.ref ? el : document.elementFromPoint(at.x, at.y) || el;
          const base = { bubbles: true, cancelable: true, composed: true, clientX: at.x, clientY: at.y, view: window };
          hit.dispatchEvent(new PointerEvent('pointerover', { ...base, pointerType: 'mouse', isPrimary: true }));
          hit.dispatchEvent(new PointerEvent('pointerenter', { ...base, bubbles: false, pointerType: 'mouse', isPrimary: true }));
          hit.dispatchEvent(new MouseEvent('mouseover', base));
          hit.dispatchEvent(new MouseEvent('mouseenter', { ...base, bubbles: false }));
          hit.dispatchEvent(new PointerEvent('pointermove', { ...base, pointerType: 'mouse', isPrimary: true }));
          hit.dispatchEvent(new MouseEvent('mousemove', base));
          return 'Hovered over ' + describe(hit);
        },
        // Page events for a drag. A draggable source gets HTML5 drag and drop
        // with one DataTransfer carried from dragstart to drop: a trusted
        // press on it would start a real drag session following the user's
        // pointer. Anything else gets a pointer drag in ten steps.
        drag(args) {
          const from = target(args.from), start = point(from, args.from);
          const source = args.from.ref ? from : document.elementFromPoint(start.x, start.y) || from;
          const to = target(args.to), end = point(to, args.to);
          const over = () => args.to.ref ? to : document.elementFromPoint(end.x, end.y) || to;
          const at = p => ({ bubbles: true, cancelable: true, composed: true, clientX: p.x, clientY: p.y, view: window });
          let draggable = false;
          for (let n = source; n && !draggable; n = n.parentElement) draggable = n.draggable === true;
          if (draggable) {
            const dataTransfer = new DataTransfer();
            const drag = (el, type, p) => el.dispatchEvent(new DragEvent(type, { ...at(p), dataTransfer }));
            if (!drag(source, 'dragstart', start)) return 'The page cancelled the drag of ' + describe(source) + '.';
            drag(source, 'drag', start);
            const zone = over();
            drag(zone, 'dragenter', end);
            const accepted = !drag(zone, 'dragover', end);
            if (accepted) drag(zone, 'drop', end);
            drag(source, 'dragend', end);
            return 'Dragged ' + describe(source) + ' onto ' + describe(zone)
              + (accepted ? '.' : ', which did not accept the drop.');
          }
          const pointer = (el, type, p, buttons) => {
            el.dispatchEvent(new PointerEvent('pointer' + type, { ...at(p), pointerType: 'mouse', isPrimary: true, buttons }));
            el.dispatchEvent(new MouseEvent('mouse' + type, { ...at(p), buttons }));
          };
          pointer(source, 'down', start, 1);
          for (let step = 1; step <= 10; step++) {
            const p = { x: start.x + (end.x - start.x) * step / 10, y: start.y + (end.y - start.y) * step / 10 };
            pointer(document.elementFromPoint(p.x, p.y) || source, 'move', p, 1);
          }
          pointer(over(), 'up', end, 0);
          return 'Dragged from ' + describe(source) + ' to ' + describe(over()) + '.';
        },
        // While the stage drives the page: its default actions that would put
        // a native menu, popup or drag session on the user's screen are
        // prevented, in the capture phase so the page's listeners still run.
        stage(args) {
          staged = args.on;
          if (!stageListening) {
            stageListening = true;
            const guard = (type, test) => addEventListener(type, e => {
              if (staged && test(e.target)) e.preventDefault();
            }, true);
            const picker = t => {
              const control = t.closest?.('label')?.control || t;
              return control.tagName === 'INPUT'
                && ['file', 'color', 'date', 'datetime-local', 'month', 'week'].includes((control.type || '').toLowerCase());
            };
            guard('contextmenu', () => true);
            guard('mousedown', t => !!t.closest?.('select'));
            guard('click', picker);
            guard('dragstart', () => true);
          }
          return '';
        },
    """
}
