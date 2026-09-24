import Foundation

/// The library `ControlScripts.call` builds once per document: the ref table,
/// the accessibility-style tree, and the DOM actions. Its own file because it
/// is one long string, and a JavaScript source is easier to read whole.
extension ControlScripts {

    static let library = """
    () => {
      const refs = new Map();
      const back = new WeakMap();
      let counter = 0;
      const limit = 50000;

      const refOf = el => {
        let ref = back.get(el);
        if (ref && refs.get(ref)?.deref() === el) return ref;
        ref = 'e' + (++counter);
        refs.set(ref, new WeakRef(el));
        back.set(el, ref);
        return ref;
      };
      const element = ref => {
        const el = refs.get(ref)?.deref();
        if (!el || !el.isConnected) throw new Error('No element ' + ref + ' on this page any more. Call read_page or find again.');
        return el;
      };

      const tags = {
        a: 'link', button: 'button', select: 'combobox', textarea: 'textbox', img: 'image',
        h1: 'heading', h2: 'heading', h3: 'heading', h4: 'heading', h5: 'heading', h6: 'heading',
        nav: 'navigation', main: 'main', header: 'banner', footer: 'contentinfo', aside: 'complementary',
        form: 'form', table: 'table', ul: 'list', ol: 'list', li: 'listitem', dialog: 'dialog',
        summary: 'button', label: 'label', p: 'paragraph', iframe: 'iframe', video: 'video', audio: 'audio'
      };
      const inputs = {
        checkbox: 'checkbox', radio: 'radio', button: 'button', submit: 'button', reset: 'button',
        image: 'button', file: 'button', range: 'slider', search: 'searchbox'
      };
      const role = el => {
        const explicit = el.getAttribute('role');
        if (explicit) return explicit.split(' ')[0];
        const tag = el.tagName.toLowerCase();
        if (tag === 'input') return inputs[(el.type || 'text').toLowerCase()] || 'textbox';
        if (tag === 'a' && !el.hasAttribute('href')) return 'generic';
        if (el.isContentEditable && !el.parentElement?.isContentEditable) return 'textbox';
        return tags[tag] || 'generic';
      };
      // A field whose value never leaves the page: passwords, every cc-*
      // autofill field, one-time codes, and fields whose name, id or label
      // says card number, CVV, OTP, PIN, SSN or IBAN. Its label still does,
      // so the agent can find the field and hand it to the user.
      const secretHint = new RegExp('(^|[^a-z])(' + ['otp', 'cvv', 'cvc', 'csc', 'ssn', 'iban', 'pin', 'passcode',
        'password', 'passwd', 'one.?time', 'card.?num(ber)?', 'cc.?num(ber)?', 'security.?code', 'social.?security',
        'verification.?code'].join('|') + ')([^a-z]|$)', 'i');
      const secret = el => {
        if (!['INPUT', 'TEXTAREA', 'SELECT'].includes(el.tagName) && !el.isContentEditable) return false;
        const type = (el.getAttribute('type') || '').toLowerCase();
        const auto = (el.getAttribute('autocomplete') || '').toLowerCase();
        if (type === 'password' || /password|one-time-code|(^|\\s)cc-/.test(auto)) return true;
        const label = el.getAttribute('aria-label') || (el.labels && el.labels[0] ? el.labels[0].textContent : '');
        return secretHint.test((el.getAttribute('name') || '') + ' ' + (el.id || '') + ' ' + label);
      };
      const ownText = el => {
        let text = '';
        for (const node of el.childNodes) if (node.nodeType === Node.TEXT_NODE) text += node.textContent;
        return text.replace(/\\s+/g, ' ').trim();
      };
      const clip = (text, n) => text.length > n ? text.slice(0, n) + '…' : text;
      const name = el => {
        const label = el.getAttribute('aria-label');
        if (label && label.trim()) return label.trim();
        const by = el.getAttribute('aria-labelledby');
        if (by) {
          const text = by.split(' ').map(id => document.getElementById(id)?.textContent || '').join(' ').trim();
          if (text) return text;
        }
        if (el.labels && el.labels.length) {
          const text = el.labels[0].textContent.replace(/\\s+/g, ' ').trim();
          if (text) return text;
        }
        for (const attribute of ['alt', 'title', 'placeholder']) {
          const value = el.getAttribute(attribute);
          if (value && value.trim()) return value.trim();
        }
        const tag = el.tagName.toLowerCase();
        if (['a', 'button', 'summary', 'label', 'option', 'li', 'h1', 'h2', 'h3', 'h4', 'h5', 'h6'].includes(tag)
            || ['button', 'link', 'tab', 'menuitem', 'option', 'heading'].includes(el.getAttribute('role'))) {
          return el.textContent.replace(/\\s+/g, ' ').trim();
        }
        return ownText(el);
      };
      const interactive = el => {
        const tag = el.tagName.toLowerCase();
        if (['a', 'button', 'input', 'select', 'textarea', 'summary', 'option'].includes(tag)) {
          return tag !== 'a' || el.hasAttribute('href');
        }
        if (el.isContentEditable) return true;
        const r = el.getAttribute('role');
        if (['button', 'link', 'checkbox', 'radio', 'tab', 'menuitem', 'option', 'switch', 'textbox',
             'combobox', 'searchbox', 'slider'].includes(r)) return true;
        return el.hasAttribute('onclick') || (el.hasAttribute('tabindex') && el.tabIndex >= 0);
      };
      const visible = el => {
        if (el.getAttribute('aria-hidden') === 'true') return false;
        const style = getComputedStyle(el);
        if (style.display === 'none' || style.visibility === 'hidden') return false;
        const box = el.getBoundingClientRect();
        return box.width > 0 || box.height > 0 || style.display === 'contents';
      };
      const skipped = new Set(['script', 'style', 'noscript', 'template', 'meta', 'link', 'head', 'svg']);

      const describe = el => {
        const r = role(el);
        let line = r;
        const tag = el.tagName.toLowerCase();
        // A secret editable's name would be its own text; a field's is its label.
        const n = secret(el) && el.isContentEditable ? '' : clip(name(el), 120);
        if (n) line += ' "' + n.replace(/"/g, '\\\\"') + '"';
        if (interactive(el)) line += ' [' + refOf(el) + ']';
        if (tag === 'a' && el.getAttribute('href')) line += ' href="' + clip(el.getAttribute('href'), 200) + '"';
        if (/^h[1-6]$/.test(tag)) line += ' level=' + tag[1];
        if ((tag === 'input' || tag === 'textarea') && !['checkbox', 'radio'].includes(el.type)) {
          if (el.value && !secret(el)) line += ' value="' + clip(el.value, 200).replace(/"/g, '\\\\"') + '"';
          if (secret(el) && el.value) line += ' value=[hidden]';
        }
        if (tag === 'select' && el.selectedOptions.length) {
          line += secret(el) ? ' value=[hidden]' : ' value="' + clip(el.selectedOptions[0].text, 120) + '"';
        }
        if (el.checked) line += ' (checked)';
        if (el.disabled) line += ' (disabled)';
        if (el.getAttribute('aria-expanded')) line += ' expanded=' + el.getAttribute('aria-expanded');
        return line;
      };
      const worth = (el, onlyInteractive) => {
        if (interactive(el)) return true;
        if (onlyInteractive) return false;
        if (role(el) !== 'generic') return true;
        return ownText(el).length > 0;
      };

      const tree = (root, onlyInteractive, maxDepth) => {
        const lines = [];
        let size = 0;
        const walk = (el, depth) => {
          if (size > limit || depth > maxDepth) return;
          const tag = el.tagName.toLowerCase();
          if (skipped.has(tag) || !visible(el)) return;
          const shown = el === root || worth(el, onlyInteractive);
          if (shown) {
            const line = '  '.repeat(depth) + describe(el);
            lines.push(line);
            size += line.length + 1;
          }
          if (tag === 'select') {
            for (const option of el.options) {
              lines.push('  '.repeat(depth + 1) + 'option "' + clip(option.text.trim(), 120) + '"'
                + (option.selected && !secret(el) ? ' (selected)' : ''));
            }
            return;
          }
          for (const child of el.children) walk(child, shown ? depth + 1 : depth);
          if (el.shadowRoot) for (const child of el.shadowRoot.children) walk(child, shown ? depth + 1 : depth);
        };
        walk(root, 0);
        let text = lines.join('\\n');
        if (size > limit) text = text.slice(0, limit) + '\\n… truncated. Pass ref to read one part, or filter "interactive".';
        return text;
      };

      const header = () => 'URL: ' + location.href + '\\nTitle: ' + document.title
        + '\\nViewport: ' + innerWidth + 'x' + innerHeight + ', scrolled to ' + Math.round(scrollX) + ',' + Math.round(scrollY)
        + ' of ' + document.documentElement.scrollWidth + 'x' + document.documentElement.scrollHeight + '\\n\\n';

      const target = args => {
        if (args.ref) return element(args.ref);
        const el = document.elementFromPoint(args.x, args.y);
        if (!el) throw new Error('Nothing at ' + args.x + ',' + args.y + ' — it is outside the viewport.');
        return el;
      };
      const point = (el, args) => {
        if (args.ref) {
          el.scrollIntoView({ block: 'center', inline: 'center', behavior: 'instant' });
          const box = el.getBoundingClientRect();
          return { x: box.left + box.width / 2, y: box.top + box.height / 2 };
        }
        return { x: args.x, y: args.y };
      };
      const editable = el => el && (el.isContentEditable
        || (el.tagName === 'INPUT' && !['checkbox', 'radio', 'button', 'submit', 'reset', 'file', 'image'].includes(el.type))
        || el.tagName === 'TEXTAREA');
      const setValue = (el, value) => {
        const proto = el.tagName === 'TEXTAREA' ? HTMLTextAreaElement.prototype
          : el.tagName === 'SELECT' ? HTMLSelectElement.prototype : HTMLInputElement.prototype;
        Object.getOwnPropertyDescriptor(proto, 'value').set.call(el, value);
        el.dispatchEvent(new Event('input', { bubbles: true }));
        el.dispatchEvent(new Event('change', { bubbles: true }));
      };
      const insert = (el, text) => {
        if (document.execCommand('insertText', false, text)) return;
        if (el.isContentEditable) { el.textContent += text; el.dispatchEvent(new InputEvent('input', { bubbles: true })); return; }
        setValue(el, el.value + text);
      };
      const focusable = () => [...document.querySelectorAll(
        'a[href], button, input, select, textarea, [tabindex], [contenteditable="true"], summary'
      )].filter(el => !el.disabled && el.tabIndex >= 0 && visible(el));

      const press = (combo) => {
        const parts = combo.split('+');
        const key = parts.pop();
        const mods = new Set(parts.map(p => p.toLowerCase()));
        const init = {
          key: key.length === 1 ? key : key.charAt(0).toUpperCase() + key.slice(1), bubbles: true, cancelable: true,
          metaKey: mods.has('cmd') || mods.has('meta'), ctrlKey: mods.has('ctrl') || mods.has('control'),
          altKey: mods.has('alt') || mods.has('option'), shiftKey: mods.has('shift')
        };
        const el = document.activeElement || document.body;
        const proceed = el.dispatchEvent(new KeyboardEvent('keydown', init));
        if (proceed && init.key.length === 1 && !init.metaKey && !init.ctrlKey) {
          el.dispatchEvent(new KeyboardEvent('keypress', init));
          if (editable(el)) insert(el, init.key);
        } else if (proceed) {
          defaultAction(el, init);
        }
        el.dispatchEvent(new KeyboardEvent('keyup', init));
      };
      const defaultAction = (el, init) => {
        const command = init.metaKey || init.ctrlKey;
        const scroller = document.scrollingElement || document.documentElement;
        const k = init.key.toLowerCase();
        if (command && k === 'a') { editable(el) && el.select ? el.select() : document.execCommand('selectAll'); return; }
        switch (init.key) {
          case 'Enter':
            if (el.tagName === 'TEXTAREA' || el.isContentEditable) document.execCommand('insertLineBreak');
            else if (el.form && el.tagName === 'INPUT') el.form.requestSubmit();
            else if (el.click && el !== document.body) el.click();
            return;
          case 'Tab': {
            const all = focusable();
            const at = all.indexOf(el);
            const next = all[(at + (init.shiftKey ? -1 : 1) + all.length) % all.length];
            next?.focus();
            return;
          }
          case 'Backspace': document.execCommand('delete'); return;
          case 'Delete': document.execCommand('forwardDelete'); return;
          case 'Escape': el.blur?.(); return;
        }
        if (editable(el)) return;
        const step = { ArrowDown: [0, 40], ArrowUp: [0, -40], ArrowRight: [40, 0], ArrowLeft: [-40, 0],
          PageDown: [0, innerHeight * 0.9], PageUp: [0, -innerHeight * 0.9], ' ': [0, innerHeight * 0.9] }[init.key];
        if (step) scroller.scrollBy(step[0], step[1]);
        if (init.key === 'Home') scroller.scrollTo(0, 0);
        if (init.key === 'End') scroller.scrollTo(0, scroller.scrollHeight);
      };
      const scrollable = el => {
        for (let node = el; node && node !== document.body; node = node.parentElement) {
          const style = getComputedStyle(node);
          if (/(auto|scroll)/.test(style.overflowY + style.overflowX)
              && (node.scrollHeight > node.clientHeight || node.scrollWidth > node.clientWidth)) return node;
        }
        return document.scrollingElement || document.documentElement;
      };

      const masked = [];

      return {
        mask() {
          for (const el of document.querySelectorAll('input, textarea')) {
            if (!secret(el) || el.type === 'password') continue;
            const property = '-webkit-text-security';
            masked.push([new WeakRef(el), el.style.getPropertyValue(property), el.style.getPropertyPriority(property)]);
            el.style.setProperty(property, 'disc', 'important');
          }
          return String(masked.length);
        },
        unmask() {
          for (const [ref, value, priority] of masked.splice(0)) {
            const el = ref.deref();
            if (!el) continue;
            if (value) el.style.setProperty('-webkit-text-security', value, priority);
            else el.style.removeProperty('-webkit-text-security');
          }
          return '';
        },
        readPage(args) {
          const root = args.ref ? element(args.ref) : document.body;
          if (!root) return header() + '(the page has no body yet)';
          return header() + tree(root, args.interactiveOnly, args.maxDepth);
        },
        pageText() {
          const main = document.querySelector('article, main, [role="main"]');
          const body = document.body ? document.body.innerText : '';
          let text = main && main.innerText.length > body.length / 3 ? main.innerText : body;
          text = text.replace(/\\n{3,}/g, '\\n\\n').trim();
          if (text.length > limit) text = text.slice(0, limit) + '\\n… truncated.';
          return header() + text;
        },
        find(args) {
          const query = args.query.toLowerCase().trim();
          const words = query.split(/\\s+/);
          const found = [];
          for (const el of document.body ? document.body.querySelectorAll('*') : []) {
            if (skipped.has(el.tagName.toLowerCase()) || !worth(el, false) || !visible(el)) continue;
            const haystack = (role(el) + ' ' + (secret(el) && el.isContentEditable ? '' : name(el)) + ' '
              + (el.getAttribute('placeholder') || '')
              + ' ' + (el.getAttribute('name') || '') + ' ' + (el.id || '')).toLowerCase();
            if (words.every(word => haystack.includes(word))) {
              if (!interactive(el)) refOf(el);
              const line = describe(el);
              found.push(interactive(el) ? line : line + ' [' + refOf(el) + ']');
              if (found.length >= 25) break;
            }
          }
          return found.length ? found.join('\\n') : 'Nothing on the page matches “' + args.query + '”.';
        },
        click(args) {
          const el = target(args);
          const at = point(el, args);
          const hit = args.ref ? el : document.elementFromPoint(at.x, at.y) || el;
          const base = { bubbles: true, cancelable: true, composed: true, clientX: at.x, clientY: at.y, button: 0, view: window };
          for (let n = 1; n <= args.clickCount; n++) {
            hit.dispatchEvent(new PointerEvent('pointerdown', { ...base, pointerType: 'mouse', isPrimary: true, buttons: 1 }));
            hit.dispatchEvent(new MouseEvent('mousedown', { ...base, detail: n, buttons: 1 }));
            if (n === 1 && hit.focus) hit.focus({ preventScroll: true });
            hit.dispatchEvent(new PointerEvent('pointerup', { ...base, pointerType: 'mouse', isPrimary: true }));
            hit.dispatchEvent(new MouseEvent('mouseup', { ...base, detail: n }));
            hit.click();
          }
          if (args.clickCount === 2) hit.dispatchEvent(new MouseEvent('dblclick', { ...base, detail: 2 }));
          return 'Clicked ' + describe(hit);
        },
        type(args) {
          const el = args.ref ? element(args.ref) : document.activeElement;
          if (!editable(el)) throw new Error('Nothing that takes text has focus. Pass the ref of a text field.');
          if (args.ref) {
            el.focus();
            // Typing appends. Email and number fields refuse a selection range and throw.
            try { el.setSelectionRange(el.value.length, el.value.length); } catch (e) {}
          }
          insert(el, args.text);
          return 'Typed into ' + describe(el);
        },
        key(args) {
          for (const combo of args.keys.split(' ').filter(Boolean)) press(combo);
          return 'Pressed ' + args.keys + (document.activeElement ? '; focus is on ' + describe(document.activeElement) : '');
        },
        scroll(args) {
          if (args.ref) {
            const el = element(args.ref);
            el.scrollIntoView({ block: 'center', behavior: 'instant' });
            return 'Scrolled ' + describe(el) + ' into view.';
          }
          const box = args.x !== undefined ? scrollable(document.elementFromPoint(args.x, args.y)) : scrollable(document.activeElement);
          const step = 100 * args.amount;
          const dx = args.direction === 'left' ? -step : args.direction === 'right' ? step : 0;
          const dy = args.direction === 'up' ? -step : args.direction === 'down' ? step : 0;
          box.scrollBy({ left: dx, top: dy, behavior: 'instant' });
          return 'Scrolled to ' + Math.round(box.scrollLeft) + ',' + Math.round(box.scrollTop)
            + ' of ' + box.scrollWidth + 'x' + box.scrollHeight + '.';
        },
        fill(args) {
          const el = element(args.ref);
          const value = args.value;
          el.scrollIntoView({ block: 'center', behavior: 'instant' });
          if (el.tagName === 'SELECT') {
            const wanted = String(value).toLowerCase();
            const option = [...el.options].find(o => o.value.toLowerCase() === wanted)
              || [...el.options].find(o => o.text.trim().toLowerCase() === wanted);
            if (!option) throw new Error('No option “' + value + '”. Options: ' + [...el.options].map(o => o.text.trim()).join(', '));
            setValue(el, option.value);
          } else if (el.type === 'checkbox' || el.type === 'radio') {
            const on = value === true || value === 'true' || value === 1;
            if (el.checked !== on) el.click();
          } else if (el.isContentEditable) {
            el.focus();
            document.execCommand('selectAll');
            document.execCommand('insertText', false, String(value));
          } else if ('value' in el) {
            el.focus();
            setValue(el, String(value));
          } else {
            throw new Error(describe(el) + ' is not a form control.');
          }
          return 'Set ' + describe(el);
        },
        upload: \(upload)
      };
    }
    """
}
