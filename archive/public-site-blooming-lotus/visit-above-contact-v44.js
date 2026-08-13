/* BLOOMING_VISIT_ABOVE_CONTACT_V44 */
(() => {
  'use strict';
  if (window.__BL_VISIT_ABOVE_CONTACT_V44__) return;
  window.__BL_VISIT_ABOVE_CONTACT_V44__ = true;

  const clean = value => String(value || '').replace(/\s+/g, ' ').trim().toLowerCase();

  function findVisit() {
    const existing = document.getElementById('visit-v36');
    if (existing) return existing;

    const hoursHeading = [...document.querySelectorAll('h1,h2,h3')]
      .find(element => clean(element.textContent) === 'hours');
    if (!hoursHeading) return null;

    let node = hoursHeading.closest('section') || hoursHeading.parentElement;
    while (node && node !== document.body) {
      const text = clean(node.textContent);
      if (text.includes('hours') &&
          text.includes('location') &&
          text.includes('3214 electric road')) return node;
      node = node.parentElement;
    }
    return null;
  }

  function findContact() {
    const direct = document.getElementById('contact');
    if (direct) return direct.closest('section') || direct;

    const heading = [...document.querySelectorAll('h1,h2,h3,h4')]
      .find(element => {
        const text = clean(element.textContent);
        return text === 'contact' ||
          text.includes('contact blooming lotus') ||
          text.includes('get in touch');
      });
    if (heading) return heading.closest('section') || heading.parentElement;

    const contactLink = document.querySelector('a[href^="mailto:"], a[href^="tel:"]');
    return contactLink?.closest('section') || null;
  }

  function updateNavigation() {
    document.querySelectorAll('header a, nav a').forEach(link => {
      if (clean(link.textContent) === 'visit') link.setAttribute('href', '#visit-v36');
    });
  }

  function apply() {
    const visit = findVisit();
    const contact = findContact();
    if (!visit || !contact || visit === contact || visit.contains(contact) || contact.contains(visit)) {
      return false;
    }

    visit.id = 'visit-v36';
    contact.id = contact.id || 'contact';
    contact.insertAdjacentElement('beforebegin', visit);
    visit.style.setProperty('margin-bottom', '28px', 'important');
    updateNavigation();
    document.documentElement.dataset.visitAboveContactV44 = 'complete';
    return true;
  }

  if (document.readyState === 'loading') {
    document.addEventListener('DOMContentLoaded', apply, { once: true });
  } else apply();

  let attempts = 0;
  const timer = setInterval(() => {
    attempts += 1;
    if (apply() || attempts >= 40) clearInterval(timer);
  }, 250);
})();
