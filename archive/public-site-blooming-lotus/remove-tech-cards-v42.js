/* BLOOMING_REMOVE_TECH_CARDS_V42 */
(() => {
  'use strict';
  if (window.__BL_REMOVE_TECH_CARDS_V42__) return;
  window.__BL_REMOVE_TECH_CARDS_V42__ = true;

  const clean = value => String(value || '').replace(/\s+/g, ' ').trim().toLowerCase();

  function textElement(fragment) {
    return [...document.querySelectorAll('h1,h2,h3,h4,h5,h6,p,span,strong,div')]
      .find(element => clean(element.textContent) === fragment || clean(element.textContent).includes(fragment));
  }

  function cardFor(element, requiredFragments) {
    if (!element) return null;
    let node = element;
    while (node && node !== document.body) {
      const text = clean(node.textContent);
      const containsAll = requiredFragments.every(fragment => text.includes(fragment));
      if (containsAll) {
        const style = getComputedStyle(node);
        const rect = node.getBoundingClientRect();
        const cardLike = rect.width >= 260 && rect.height >= 180 && (
          parseFloat(style.borderRadius) >= 12 ||
          style.boxShadow !== 'none' ||
          style.backgroundColor !== 'rgba(0, 0, 0, 0)'
        );
        if (cardLike) return node;
      }
      node = node.parentElement;
    }
    return null;
  }

  function removeEmptyAncestors(start) {
    let node = start;
    for (let depth = 0; node && node !== document.body && depth < 4; depth += 1) {
      const parent = node.parentElement;
      if (!parent) return;
      const remaining = [...parent.children].filter(child => {
        if (child.matches('script,style,link,template')) return false;
        return clean(child.textContent) || child.matches('img,form,video,iframe,svg,canvas');
      });
      if (remaining.length === 0) parent.remove();
      node = parent;
    }
  }

  function removeCards() {
    const backendLabel = textElement('aws demo backend');
    const nextLabel = textElement('next phase');

    const backendCard = cardFor(backendLabel, [
      'aws demo backend',
      'requests are stored in dynamodb',
      'api gateway'
    ]);
    const nextCard = cardFor(nextLabel, [
      'next phase',
      'easy to expand later',
      'live therapist time-slot calendar'
    ]);

    const parents = [backendCard?.parentElement, nextCard?.parentElement].filter(Boolean);
    backendCard?.remove();
    nextCard?.remove();
    [...new Set(parents)].forEach(parent => removeEmptyAncestors(parent.firstElementChild || parent));

    // Hide any late-rendered copies immediately if an older page script recreates them.
    [...document.querySelectorAll('section,article,aside,div')].forEach(element => {
      const text = clean(element.textContent);
      if ((text.includes('aws demo backend') && text.includes('requests are stored in dynamodb')) ||
          (text.includes('next phase') && text.includes('easy to expand later'))) {
        const card = cardFor(element, text.includes('aws demo backend')
          ? ['aws demo backend','requests are stored in dynamodb','api gateway']
          : ['next phase','easy to expand later','live therapist time-slot calendar']);
        card?.remove();
      }
    });
  }

  if (document.readyState === 'loading') {
    document.addEventListener('DOMContentLoaded', removeCards, { once: true });
  } else removeCards();

  let attempts = 0;
  const timer = setInterval(() => {
    attempts += 1;
    removeCards();
    if (attempts >= 40) clearInterval(timer);
  }, 250);
})();
