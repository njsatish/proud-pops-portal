/* BLOOMING_BOOKING_PREVIEW_LOCATION_V32 */
(() => {
  'use strict';
  if (window.__BL_BOOKING_PREVIEW_V32__) return;
  window.__BL_BOOKING_PREVIEW_V32__ = true;

  function normalizedText(element) {
    return String(element?.textContent || '').replace(/\s+/g, ' ').trim().toLowerCase();
  }

  function findPreviewCard() {
    const candidates = [...document.querySelectorAll('div, aside, article, section')];
    return candidates
      .filter(element => {
        const text = normalizedText(element);
        return text.includes('booking preview') &&
          text.includes('choose your therapist') &&
          element.children.length <= 10;
      })
      .sort((a, b) => a.getBoundingClientRect().width - b.getBoundingClientRect().width)[0] || null;
  }

  function findHeroSection(card) {
    if (!card) return null;
    let node = card.parentElement;
    while (node && node !== document.body) {
      const text = normalizedText(node);
      if (text.includes('relax deeply') && text.includes('feel renewed')) return node;
      node = node.parentElement;
    }
    return [...document.querySelectorAll('section, main > div')]
      .find(element => {
        const text = normalizedText(element);
        return text.includes('relax deeply') && text.includes('feel renewed');
      }) || null;
  }

  function movePreview() {
    const card = findPreviewCard();
    if (!card || card.dataset.bookingPreviewV32 === 'true') return;

    const hero = findHeroSection(card);
    if (!hero) {
      console.warn('Booking Preview card found, but hero section was not identified.');
      return;
    }

    const wrapper = document.createElement('section');
    wrapper.className = 'booking-preview-strip-v32';
    wrapper.setAttribute('aria-label', 'Booking preview');

    card.dataset.bookingPreviewV32 = 'true';
    card.classList.add('booking-preview-card-v32');
    card.style.position = 'static';
    card.style.inset = 'auto';
    card.style.transform = 'none';
    card.style.margin = '0';
    card.style.width = 'auto';
    card.style.maxWidth = 'none';

    wrapper.appendChild(card);
    hero.insertAdjacentElement('afterend', wrapper);

    // Make the relocated preview actionable without changing the current text.
    if (!card.querySelector('a, button')) {
      card.setAttribute('role', 'link');
      card.setAttribute('tabindex', '0');
      card.setAttribute('aria-label', 'Choose your therapist in the booking form');
      const go = () => {
        const booking = document.querySelector('#booking, [id*="booking" i], form');
        booking?.scrollIntoView({ behavior: 'smooth', block: 'start' });
      };
      card.addEventListener('click', go);
      card.addEventListener('keydown', event => {
        if (event.key === 'Enter' || event.key === ' ') {
          event.preventDefault();
          go();
        }
      });
    }
  }

  if (document.readyState === 'loading') {
    document.addEventListener('DOMContentLoaded', movePreview, { once: true });
  } else movePreview();

  // The page contains several dynamic enhancements, so retry briefly while the
  // hero is assembled. The operation is idempotent after the first successful move.
  let attempts = 0;
  const timer = setInterval(() => {
    attempts += 1;
    movePreview();
    if (document.querySelector('[data-booking-preview-v32="true"]') || attempts >= 30) {
      clearInterval(timer);
    }
  }, 250);
})();
