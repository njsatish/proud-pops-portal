/* BLOOMING_EMPTY_TECHNICAL_SECTION_GAP_V39 */
(() => {
  'use strict';
  if (window.__BL_EMPTY_GAP_V39__) return;
  window.__BL_EMPTY_GAP_V39__ = true;

  const normalize = value => String(value || '').replace(/\s+/g, ' ').trim();

  function visibleMeaningfulChildren(element) {
    return [...element.children].filter(child => {
      if (child.matches('script, style, link, template')) return false;
      const style = getComputedStyle(child);
      if (style.display === 'none' || style.visibility === 'hidden') return false;
      return normalize(child.textContent) || child.matches('img, video, iframe, form, canvas, svg');
    });
  }

  function looksLikeEmptyTechnicalWrapper(element) {
    if (!(element instanceof HTMLElement)) return false;
    if (!element.matches('section, main > div, main > section')) return false;
    if (element.id === 'booking-transition-v36') return false;
    if (element.id === 'massage-services-gallery-v34') return false;
    if (element.id === 'reputation-v37') return false;
    if (normalize(element.textContent)) return false;
    if (visibleMeaningfulChildren(element).length) return false;

    const style = getComputedStyle(element);
    const rect = element.getBoundingClientRect();
    const background = style.backgroundImage + ' ' + style.backgroundColor;
    const hasLargeEmptyArea = rect.height >= 80;
    const hasDecorativeBackground = background.includes('gradient') ||
      style.backgroundColor !== 'rgba(0, 0, 0, 0)';
    return hasLargeEmptyArea && hasDecorativeBackground;
  }

  function removeGap() {
    const main = document.querySelector('main');
    if (!main) return;

    // First remove empty descendants left by the deleted technical cards.
    [...main.querySelectorAll('section, div')]
      .sort((a, b) => b.querySelectorAll('*').length - a.querySelectorAll('*').length)
      .forEach(element => {
        const className = String(element.className || '').toLowerCase();
        const id = String(element.id || '').toLowerCase();
        const technicalName = /backend|technical|next-phase|demo-stack|architecture/.test(className + ' ' + id);
        if (technicalName && !normalize(element.textContent) && !visibleMeaningfulChildren(element).length) {
          element.remove();
        }
      });

    // Then remove the remaining large empty gradient wrapper.
    [...main.children].forEach(element => {
      if (looksLikeEmptyTechnicalWrapper(element)) element.remove();
    });

    document.documentElement.dataset.emptyGapV39 = 'removed';
  }

  if (document.readyState === 'loading') {
    document.addEventListener('DOMContentLoaded', removeGap, { once: true });
  } else removeGap();

  let attempts = 0;
  const timer = setInterval(() => {
    attempts += 1;
    removeGap();
    if (attempts >= 24) clearInterval(timer);
  }, 250);
})();
