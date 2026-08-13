/* BLOOMING_PREVIEW_THERAPIST_LINK_V41 */
(() => {
  'use strict';
  if (window.__BL_PREVIEW_THERAPIST_LINK_V41__) return;
  window.__BL_PREVIEW_THERAPIST_LINK_V41__ = true;

  const normalize = value => String(value || '')
    .replace(/\s+/g, ' ')
    .trim()
    .toLowerCase();

  function findPreviewCard() {
    return [...document.querySelectorAll('[data-booking-preview-v32="true"], div, aside, article, section')]
      .filter(element => {
        const text = normalize(element.textContent);
        return text.includes('booking preview') && text.includes('choose your therapist');
      })
      .sort((a, b) => a.getBoundingClientRect().width - b.getBoundingClientRect().width)[0] || null;
  }

  function findTherapistSection() {
    const assigned = document.getElementById('therapists-v36');
    if (assigned) return assigned;

    const heading = [...document.querySelectorAll('h1, h2, h3')].find(element => {
      const text = normalize(element.textContent);
      return text.includes('request the therapist you prefer') ||
        text.includes('choose your therapist');
    });
    return heading?.closest('section') || heading?.parentElement || null;
  }

  function scrollToTherapists() {
    const section = findTherapistSection();
    if (!section) {
      console.warn('Therapist section was not found.');
      return;
    }

    section.id = 'therapists-v36';
    history.replaceState(null, '', '#therapists-v36');

    const header = document.querySelector('body > header, header');
    const offset = (header?.getBoundingClientRect().height || 0) + 18;
    const top = section.getBoundingClientRect().top + window.scrollY - offset;
    window.scrollTo({ top: Math.max(0, top), behavior: 'smooth' });

    const heading = section.querySelector('h1, h2, h3');
    if (heading) {
      heading.setAttribute('tabindex', '-1');
      window.setTimeout(() => heading.focus({ preventScroll: true }), 450);
    }
  }

  function updatePreviewCopy(card) {
    const textNodes = [];
    const walker = document.createTreeWalker(card, NodeFilter.SHOW_TEXT);
    while (walker.nextNode()) textNodes.push(walker.currentNode);
    const names = textNodes.find(node => {
      const text = normalize(node.nodeValue);
      return text.includes('jack') && text.includes('rose') && text.includes('no preference');
    });
    if (names) names.nodeValue = 'Jack · Rose · Mike · No preference';
  }

  function install() {
    const card = findPreviewCard();
    if (!card) return false;

    updatePreviewCopy(card);
    card.setAttribute('role', 'link');
    card.setAttribute('tabindex', '0');
    card.setAttribute('aria-label', 'View therapist choices');
    card.dataset.previewTherapistLinkV41 = 'true';

    // Capture phase takes precedence over the older V32 click handler, which
    // incorrectly searched for the first booking form.
    if (card.dataset.previewTherapistListenerV41 !== 'true') {
      card.dataset.previewTherapistListenerV41 = 'true';
      card.addEventListener('click', event => {
        event.preventDefault();
        event.stopImmediatePropagation();
        scrollToTherapists();
      }, true);
      card.addEventListener('keydown', event => {
        if (event.key !== 'Enter' && event.key !== ' ') return;
        event.preventDefault();
        event.stopImmediatePropagation();
        scrollToTherapists();
      }, true);
    }
    return true;
  }

  if (document.readyState === 'loading') {
    document.addEventListener('DOMContentLoaded', install, { once: true });
  } else install();

  let attempts = 0;
  const timer = setInterval(() => {
    attempts += 1;
    if (install() || attempts >= 40) clearInterval(timer);
  }, 250);
})();
