/* BLOOMING_MOBILE_PHONE_DASHES_V18 */
(() => {
  'use strict';
  if (window.__BL_PHONE_DASHES_V18__) return;
  window.__BL_PHONE_DASHES_V18__ = true;

  const phoneSelector = [
    'input[type="tel"]',
    'input[name*="phone" i]',
    'input[id*="phone" i]',
    'input[autocomplete="tel"]'
  ].join(',');

  function digits(value) {
    let number = String(value || '').replace(/\D/g, '');
    if (number.length === 11 && number.startsWith('1')) number = number.slice(1);
    return number.slice(0, 10);
  }

  function format(value) {
    const number = digits(value);
    if (number.length <= 3) return number;
    if (number.length <= 6) return `${number.slice(0, 3)}-${number.slice(3)}`;
    return `${number.slice(0, 3)}-${number.slice(3, 6)}-${number.slice(6)}`;
  }

  function isPhoneInput(element) {
    return element instanceof HTMLInputElement && element.matches(phoneSelector);
  }

  function prepare(input) {
    if (!isPhoneInput(input)) return;
    input.type = 'tel';
    input.inputMode = 'numeric';
    input.autocomplete = 'tel';
    input.maxLength = 12;
    input.placeholder = input.placeholder || '804-496-0413';
    input.pattern = '[0-9]{3}-[0-9]{3}-[0-9]{4}';
    input.dataset.phoneDashesV18 = 'true';
  }

  function apply(input) {
    if (!isPhoneInput(input)) return;
    prepare(input);
    const before = input.value;
    const caret = input.selectionStart ?? before.length;
    const digitsBeforeCaret = before.slice(0, caret).replace(/\D/g, '').length;
    const after = format(before);
    if (after === before) return;

    input.value = after;

    // Keep the caret near the same digit after inserting dashes.
    let nextCaret = 0;
    let seen = 0;
    while (nextCaret < after.length && seen < digitsBeforeCaret) {
      if (/\d/.test(after[nextCaret])) seen += 1;
      nextCaret += 1;
    }
    try { input.setSelectionRange(nextCaret, nextCaret); } catch (_) {}
  }

  // Capture-phase delegation runs before application-specific input listeners.
  ['beforeinput', 'input', 'change', 'blur', 'keyup'].forEach(type => {
    document.addEventListener(type, event => {
      if (!isPhoneInput(event.target)) return;
      if (type === 'beforeinput') prepare(event.target);
      else apply(event.target);
    }, true);
  });

  document.addEventListener('paste', event => {
    const input = event.target;
    if (!isPhoneInput(input)) return;
    event.preventDefault();
    const pasted = event.clipboardData?.getData('text') || '';
    input.value = format(pasted);
    input.dispatchEvent(new Event('input', { bubbles: true }));
  }, true);

  function enhance(root = document) {
    root.querySelectorAll?.(phoneSelector).forEach(input => {
      prepare(input);
      apply(input);
    });

    // Format phone links in appointment cards and details.
    root.querySelectorAll?.('a[href^="tel:" i]').forEach(anchor => {
      const formatted = format(anchor.textContent || anchor.getAttribute('href').slice(4));
      if (digits(formatted).length === 10) anchor.textContent = formatted;
    });
  }

  if (document.readyState === 'loading') {
    document.addEventListener('DOMContentLoaded', () => enhance(), { once: true });
  } else {
    enhance();
  }

  new MutationObserver(mutations => {
    for (const mutation of mutations) {
      for (const node of mutation.addedNodes) {
        if (node instanceof Element) {
          if (isPhoneInput(node)) { prepare(node); apply(node); }
          enhance(node);
        }
      }
    }
  }).observe(document.documentElement, { childList: true, subtree: true });

  window.BloomingPhone = Object.freeze({ format, digits });
})();
