/* BLOOMING_THERAPIST_GAP_V43 */
(() => {
  'use strict';
  if (window.__BL_THERAPIST_GAP_V43__) return;
  window.__BL_THERAPIST_GAP_V43__ = true;

  const clean = value => String(value || '').replace(/\s+/g, ' ').trim().toLowerCase();

  function findTherapists() {
    const existing = document.getElementById('therapists-v36');
    if (existing) return existing;
    const heading = [...document.querySelectorAll('h1,h2,h3')].find(element => {
      const text = clean(element.textContent);
      return text.includes('request the therapist you prefer') ||
        text.includes('choose your therapist');
    });
    return heading?.closest('section') || heading?.parentElement || null;
  }

  function meaningful(element) {
    if (!(element instanceof HTMLElement)) return false;
    if (clean(element.textContent)) return true;
    return Boolean(element.querySelector('img,video,iframe,form,canvas,svg,input,button,a[href]'));
  }

  function removeEmptyDecorativeNodes(root) {
    if (!root) return;
    [...root.querySelectorAll('section,div,aside,article')]
      .sort((left, right) => right.querySelectorAll('*').length - left.querySelectorAll('*').length)
      .forEach(element => {
        if (element.id === 'massage-services-gallery-v34' || element.id === 'therapists-v36') return;
        if (meaningful(element)) return;
        const rect = element.getBoundingClientRect();
        const style = getComputedStyle(element);
        const decorative = style.backgroundImage !== 'none' ||
          style.backgroundColor !== 'rgba(0, 0, 0, 0)' ||
          parseFloat(style.paddingTop) + parseFloat(style.paddingBottom) > 20 ||
          rect.height > 40;
        if (decorative) element.remove();
      });
  }

  function apply() {
    const services = document.getElementById('massage-services-gallery-v34');
    const therapists = findTherapists();
    if (!services || !therapists || services === therapists) return false;

    therapists.id = 'therapists-v36';

    // The requested customer journey is Services followed immediately by
    // Therapists. Reinsert the existing section rather than cloning it so all
    // current links and listeners remain intact.
    services.insertAdjacentElement('afterend', therapists);

    // Remove any now-empty wrapper left by the technical/demo cards.
    const oldParent = therapists.parentElement;
    if (oldParent) removeEmptyDecorativeNodes(oldParent);

    // Remove consecutive empty siblings that might still be inserted between
    // Services and Therapists by an older loaded enhancement.
    let sibling = services.nextElementSibling;
    while (sibling && sibling !== therapists) {
      const next = sibling.nextElementSibling;
      if (!meaningful(sibling)) sibling.remove();
      sibling = next;
    }

    therapists.style.setProperty('margin-top', '0', 'important');
    therapists.style.setProperty('padding-top', '72px', 'important');
    document.documentElement.dataset.therapistGapV43 = 'fixed';
    return true;
  }

  if (document.readyState === 'loading') {
    document.addEventListener('DOMContentLoaded', apply, { once: true });
  } else apply();

  // Run after older dynamic scripts so none can restore the abandoned wrapper.
  let attempts = 0;
  const timer = setInterval(() => {
    attempts += 1;
    apply();
    if (attempts >= 40) clearInterval(timer);
  }, 250);
})();
