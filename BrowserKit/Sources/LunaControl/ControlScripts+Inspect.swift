import Foundation

/// The library's `inspect`: what acting on an element would set off, for
/// `ControlPolicy` (`ControlRisk`'s raw values). Read before every click,
/// type, key, drag and form_input, from each element the call names
/// (`ControlCommand.inspections`). Spliced into
/// `library` where `secret`, `element` and `target` are in scope.
extension ControlScripts {

    static let inspection = """
      const captchaFrame = /recaptcha|hcaptcha|challenges\\.cloudflare\\.com|turnstile|arkoselabs|funcaptcha/i;
      const inCaptcha = el => !!el.closest('.g-recaptcha, .h-captcha, .cf-turnstile, [data-sitekey], [data-hcaptcha-widget-id]')
        || (el.tagName === 'IFRAME' && (captchaFrame.test(el.src || '') || /captcha/i.test(el.title || '')));
      const cardField = el => /(^|\\s)cc-/.test((el.getAttribute('autocomplete') || '').toLowerCase())
        || /(^|[^a-z])(card.?num(ber)?|cc.?num(ber)?|cvv|cvc|csc|security.?code)([^a-z]|$)/i.test(
          (el.getAttribute('name') || '') + ' ' + (el.id || '') + ' ' + (el.getAttribute('aria-label') || ''));
      const personalField = el => /(^|\\s)(street-address|address-line|postal-code|tel|bday)/.test(
          (el.getAttribute('autocomplete') || '').toLowerCase())
        || /(^|[^a-z])(ssn|social.?security|passport|iban|national.?id|birth.?date|dob)([^a-z]|$)/i.test(
          (el.getAttribute('name') || '') + ' ' + (el.id || '') + ' ' + (el.getAttribute('aria-label') || ''));
      const words = [
        ['payment', /\\b(pay|buy|order|purchase|checkout|check out|subscribe|donate|place order)\\b/i],
        ['authorization', /\\b(authori[sz]e|allow|grant|approve)\\b/i],
        ['destructive', /\\b(delete|erase|destroy)\\b/i]
      ];
      const pressable = 'button, a[href], input[type=submit], input[type=image], input[type=button], summary, '
        + '[role=button], [role=link], [role=menuitem]';
      // Pressing `control`, by a click or by Enter.
      const pressing = (control, risks) => {
        const label = control.innerText || control.value || control.getAttribute('aria-label') || control.title || '';
        for (const [risk, pattern] of words) if (pattern.test(label)) risks.add(risk);
        if (control.closest('a[download]')) risks.add('download');
        const submits = (control.tagName === 'BUTTON' && (control.getAttribute('type') || 'submit').toLowerCase() === 'submit')
          || (control.tagName === 'INPUT' && ['submit', 'image'].includes(control.type));
        if (submits && control.form) submitting(control.form, risks);
      };
      const submitting = (form, risks) => {
        for (const field of form.elements) {
          if (field.type === 'password') risks.add('credentials');
          else if (cardField(field)) risks.add('payment');
          else if (personalField(field)) risks.add('personalData');
        }
      };
      const typesText = keys => keys.split(' ').filter(Boolean).some(combo => {
        const parts = combo.split('+');
        const key = parts.pop();
        return key.length === 1 && !parts.some(p => /^(cmd|meta|ctrl|control)$/i.test(p));
      });

      const inspect = args => {
        const risks = new Set();
        let el;
        try {
          el = args.op === 'click' ? target(args) : args.ref ? element(args.ref) : document.activeElement;
        } catch (error) {
          // The call itself will fail on the same missing element and say so.
          return JSON.stringify({ risks: [] });
        }
        if (!el || el.nodeType !== Node.ELEMENT_NODE) return JSON.stringify({ risks: [] });
        if (inCaptcha(el)) risks.add('captcha');
        const control = el.closest(pressable);
        if (args.op === 'click' && control) pressing(control, risks);
        if (args.op === 'type' || args.op === 'fill' || (args.op === 'key' && typesText(args.keys || ''))) {
          if (secret(el)) risks.add('secretField');
        }
        if (args.op === 'key' && /(^|\\s)Enter(\\s|$)/.test(args.keys || '')) {
          if (control) pressing(control, risks);
          else if (el.form && el.tagName === 'INPUT') submitting(el.form, risks);
        }
        const link = el.closest('a[href]');
        return JSON.stringify({ risks: [...risks], href: link ? link.href : undefined });
      };
    """
}
