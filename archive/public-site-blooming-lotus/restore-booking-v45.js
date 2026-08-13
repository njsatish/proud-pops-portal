/* BLOOMING_RESTORE_BOOKING_FORM_V45 */
(() => {
  'use strict';
  if (window.__BL_RESTORE_BOOKING_V45__) return;
  window.__BL_RESTORE_BOOKING_V45__ = true;

  const clean = value => String(value || '').replace(/\s+/g, ' ').trim().toLowerCase();

  function isAppointmentForm(form) {
    if (!(form instanceof HTMLFormElement)) return false;
    const text = clean(form.textContent);
    const fields = [...form.querySelectorAll('input,select,textarea')];
    const fieldText = fields.map(field =>
      `${field.name} ${field.id} ${field.placeholder} ${field.type}`.toLowerCase()
    ).join(' ');
    const hasContact = /name|customer/.test(fieldText) && /phone|email/.test(fieldText);
    const hasDate = /date/.test(fieldText) || fields.some(field => field.type === 'date');
    const hasService = /service|massage/.test(fieldText + ' ' + text);
    return hasContact && hasDate && hasService;
  }

  function findBookingForm() {
    const explicit = document.querySelector('#booking form, form[id*="booking" i], form[name*="booking" i]');
    if (explicit && isAppointmentForm(explicit)) return explicit;
    return [...document.forms].find(isAppointmentForm) || null;
  }

  function findBookingSection(form) {
    if (!form) return null;
    let node = form.closest('section');
    if (node) return node;
    node = form.parentElement;
    while (node && node !== document.body) {
      const text = clean(node.textContent);
      if (text.includes('request') && text.includes('appointment')) return node;
      node = node.parentElement;
    }
    return form.parentElement;
  }

  function findContactSection() {
    const explicit = document.getElementById('contact');
    if (explicit) return explicit.closest('section') || explicit;
    const heading = [...document.querySelectorAll('h1,h2,h3,h4')].find(element => {
      const text = clean(element.textContent);
      return text === 'contact' || text.includes('contact blooming lotus') || text.includes('get in touch');
    });
    return heading?.closest('section') || heading?.parentElement || null;
  }

  function findVisitSection() {
    return document.getElementById('visit-v36') ||
      [...document.querySelectorAll('section')].find(section => {
        const text = clean(section.textContent);
        return text.includes('hours') && text.includes('3214 electric road');
      }) || null;
  }

  function restoreVisibility(section, form) {
    [section, form].filter(Boolean).forEach(element => {
      element.hidden = false;
      element.removeAttribute('aria-hidden');
      element.style.setProperty('display', element === form ? 'grid' : 'block', 'important');
      element.style.setProperty('visibility', 'visible', 'important');
      element.style.setProperty('opacity', '1', 'important');
      element.style.removeProperty('height');
      element.style.removeProperty('max-height');
      element.style.removeProperty('overflow');
    });
  }

  function updateLinks() {
    document.querySelectorAll('a[href="#booking"], header a, nav a').forEach(link => {
      if (link.getAttribute('href') === '#booking' || clean(link.textContent) === 'booking') {
        link.setAttribute('href', '#booking');
      }
    });
  }

  function apply() {
    const form = findBookingForm();
    if (!form) return false;
    const booking = findBookingSection(form);
    if (!booking) return false;

    booking.id = 'booking';
    booking.dataset.bookingRestoredV45 = 'true';
    restoreVisibility(booking, form);

    const contact = findContactSection();
    const visit = findVisitSection();
    const anchor = contact && !booking.contains(contact) && !contact.contains(booking)
      ? contact
      : visit && !booking.contains(visit) && !visit.contains(booking)
        ? visit
        : null;

    if (anchor) anchor.insertAdjacentElement('afterend', booking);

    // Keep the transition immediately before the restored form when present.
    const transition = document.getElementById('booking-transition-v36');
    if (transition && transition !== booking && !booking.contains(transition)) {
      booking.insertAdjacentElement('beforebegin', transition);
    }

    updateLinks();
    document.documentElement.dataset.bookingRestoredV45 = 'complete';
    return true;
  }

  if (document.readyState === 'loading') {
    document.addEventListener('DOMContentLoaded', apply, { once:true });
  } else apply();

  let attempts = 0;
  const timer = setInterval(() => {
    attempts += 1;
    if (apply() || attempts >= 40) clearInterval(timer);
  }, 250);
})();
