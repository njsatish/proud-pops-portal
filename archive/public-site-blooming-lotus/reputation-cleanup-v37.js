/* BLOOMING_REPUTATION_CLEANUP_V37 */
(() => {
  'use strict';
  if (window.__BL_REPUTATION_CLEANUP_V37__) return;
  window.__BL_REPUTATION_CLEANUP_V37__ = true;

  const normalize = value => String(value || '')
    .replace(/\s+/g, ' ')
    .trim()
    .toLowerCase();

  function sectionContaining(textFragments) {
    const candidates = [...document.querySelectorAll('section, main > div, article')];
    return candidates
      .filter(element => {
        const text = normalize(element.textContent);
        return textFragments.every(fragment => text.includes(fragment));
      })
      .sort((left, right) => left.textContent.length - right.textContent.length)[0] || null;
  }

  function findHero() {
    const candidates = [...document.querySelectorAll('main > section, main > div, section')];
    return candidates.find(element => {
      const text = normalize(element.textContent);
      return text.includes('relax deeply') && text.includes('feel renewed');
    }) || candidates.find(element => element.querySelector('h1')) || null;
  }

  function findReputationStrip() {
    return sectionContaining(['4.9', '125+', 'google ratings']) ||
      sectionContaining(['4.9', 'strong reputation']);
  }

  function replaceText(root, oldFragments, newText) {
    if (!root) return false;
    const walker = document.createTreeWalker(root, NodeFilter.SHOW_TEXT);
    const nodes = [];
    while (walker.nextNode()) nodes.push(walker.currentNode);
    const node = nodes.find(item => {
      const text = normalize(item.nodeValue);
      return oldFragments.some(fragment => text.includes(fragment));
    });
    if (!node) return false;
    node.nodeValue = newText;
    return true;
  }

  function updateReputationStrip(strip) {
    if (!strip) return;
    strip.id = 'reputation-v37';
    strip.dataset.reputationV37 = 'true';

    replaceText(strip,
      ['125+ google ratings'],
      '125+ customer reviews');

    replaceText(strip,
      ['a strong reputation deserves a professional home online'],
      'Thank you to our customers for choosing Blooming Lotus.');

    replaceText(strip,
      ['a colorful, polished website can turn an already strong local reputation'],
      'Trusted by customers for attentive service, a welcoming setting, and massage appointments tailored to individual preferences.');

    // Remove internal concept/developer notes from customer-facing content.
    [...strip.querySelectorAll('p, small, span, div')].forEach(element => {
      const text = normalize(element.textContent);
      if (text.includes('concept message for the demo') ||
          text.includes('replace with an approved customer testimonial')) {
        element.remove();
      }
    });
  }

  function removeWebsiteDesignSection() {
    const section = sectionContaining([
      'warm, polished',
      'unmistakably blooming lotus'
    ]) || sectionContaining([
      'the website now uses the actual colorful logo',
      'generic black-and-white template'
    ]);
    if (section && section.id !== 'reputation-v37') section.remove();
  }

  function moveReputationAfterHero(strip) {
    const hero = findHero();
    if (!hero || !strip || hero === strip || hero.contains(strip)) return;
    hero.insertAdjacentElement('afterend', strip);
  }

  function apply() {
    const strip = findReputationStrip();
    updateReputationStrip(strip);
    removeWebsiteDesignSection();
    moveReputationAfterHero(strip);
  }

  if (document.readyState === 'loading') {
    document.addEventListener('DOMContentLoaded', apply, { once:true });
  } else apply();

  let attempts = 0;
  const timer = setInterval(() => {
    attempts += 1;
    apply();
    if (document.querySelector('[data-reputation-v37="true"]') && attempts >= 8) {
      clearInterval(timer);
    } else if (attempts >= 40) {
      clearInterval(timer);
    }
  }, 250);
})();
