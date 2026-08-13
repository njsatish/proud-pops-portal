/* BLOOMING_REMOVE_OLD_SERVICES_V35 */
(() => {
  'use strict';
  if (window.__BL_REMOVE_OLD_SERVICES_V35__) return;
  window.__BL_REMOVE_OLD_SERVICES_V35__ = true;

  const normalize = value => String(value || '')
    .replace(/\s+/g, ' ')
    .trim()
    .toLowerCase();

  function findLegacyServicesSection() {
    const headings = [...document.querySelectorAll('h1, h2, h3')];
    const heading = headings.find(element => {
      const text = normalize(element.textContent);
      return text === 'choose the care you need today.' ||
        text === 'choose the care you need today';
    });
    if (!heading) return null;

    let section = heading.closest('section');
    if (section && section.id !== 'massage-services-gallery-v34') return section;

    // Fallback for layouts where the legacy block is a direct child div.
    let node = heading.parentElement;
    while (node && node !== document.body) {
      const text = normalize(node.textContent);
      const hasLegacyCards = text.includes('deep tissue massage') &&
        text.includes('hot stone massage') &&
        text.includes('request this service');
      if (hasLegacyCards && node.id !== 'massage-services-gallery-v34') return node;
      node = node.parentElement;
    }
    return null;
  }

  function updateNavigation() {
    const links = [...document.querySelectorAll('a')];
    links.forEach(link => {
      if (normalize(link.textContent) !== 'services') return;
      // Restrict the update to the main header/navigation area where possible.
      if (!link.closest('header, nav') && link.getAttribute('href') !== '#services') return;
      link.setAttribute('href', '#massage-services-gallery-v34');
      link.setAttribute('aria-label', 'View massage services');
    });
  }

  function removeLegacySection() {
    const legacy = findLegacyServicesSection();
    if (legacy) legacy.remove();
  }

  function apply() {
    updateNavigation();
    removeLegacySection();
  }

  if (document.readyState === 'loading') {
    document.addEventListener('DOMContentLoaded', apply, { once:true });
  } else apply();

  // V34 inserts the photo gallery after page load. Retry briefly so the old
  // section is removed even if the original site renders asynchronously.
  let attempts = 0;
  const timer = setInterval(() => {
    attempts += 1;
    apply();
    if (document.getElementById('massage-services-gallery-v34') &&
        !findLegacyServicesSection()) {
      clearInterval(timer);
    } else if (attempts >= 40) {
      clearInterval(timer);
    }
  }, 250);
})();
