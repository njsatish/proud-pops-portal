/* BLOOMING_SECTION_ORDER_V36 */
(() => {
  'use strict';
  if (window.__BL_SECTION_ORDER_V36__) return;
  window.__BL_SECTION_ORDER_V36__ = true;

  const normalize = value => String(value || '')
    .replace(/\s+/g, ' ')
    .trim()
    .toLowerCase();

  const headings = () => [...document.querySelectorAll('h1, h2, h3')];

  function sectionForHeading(patterns) {
    const heading = headings().find(element => {
      const text = normalize(element.textContent);
      return patterns.some(pattern => text.includes(pattern));
    });
    if (!heading) return null;
    return heading.closest('section') || heading.parentElement?.closest('div') || null;
  }

  function findSections() {
    const services = document.getElementById('massage-services-gallery-v34');
    const therapists = sectionForHeading([
      'request the therapist you prefer',
      'choose your therapist',
      'our team'
    ]);

    const booking = document.querySelector('#booking')?.closest('section') ||
      sectionForHeading(['request your appointment', 'request an appointment']);

    // The Hours and Location content can be inside one shared section or in
    // sibling cards. Use the nearest common section that contains both labels.
    const hourHeading = headings().find(element => normalize(element.textContent) === 'hours');
    const locationHeading = headings().find(element =>
      normalize(element.textContent).includes('blooming lotus oriental massage')
    );
    let visit = hourHeading?.closest('section') || null;
    if (visit && locationHeading && !visit.contains(locationHeading)) {
      const hourSection = hourHeading.closest('section, div');
      let node = hourSection;
      while (node && node !== document.body && !node.contains(locationHeading)) {
        node = node.parentElement;
      }
      if (node && node !== document.body) visit = node;
    }
    if (!visit) visit = sectionForHeading(['plan your visit', 'hours and location']);

    return { services, therapists, visit, booking };
  }

  function commonParent(elements) {
    if (!elements.length) return null;
    let node = elements[0].parentElement;
    while (node && node !== document.body) {
      if (elements.every(element => node.contains(element))) return node;
      node = node.parentElement;
    }
    return document.querySelector('main') || document.body;
  }

  function updateTherapistCopy(therapists) {
    if (!therapists) return;
    const paragraphs = [...therapists.querySelectorAll('p')];
    const demoCopy = paragraphs.find(paragraph => {
      const text = normalize(paragraph.textContent);
      return text.includes('for this demo') ||
        text.includes('mike is also shown as the manager');
    });
    if (demoCopy) {
      demoCopy.textContent = 'Choose a preferred therapist when requesting your appointment. If you have no preference, the front desk can help match availability.';
    }
  }

  function installTransition(visit, booking) {
    if (!visit || !booking || document.getElementById('booking-transition-v36')) return;
    const block = document.createElement('section');
    block.id = 'booking-transition-v36';
    block.className = 'booking-transition-v36';
    block.innerHTML = `
      <div>
        <span>Ready to schedule?</span>
        <h2>Request your appointment</h2>
        <p>Choose a preferred date and time. The front desk will contact you to confirm availability.</p>
      </div>
      <a href="#booking">Request an Appointment</a>`;
    booking.insertAdjacentElement('beforebegin', block);
  }

  function updateNavigation() {
    const targets = {
      services: '#massage-services-gallery-v34',
      therapists: '#therapists-v36',
      visit: '#visit-v36',
      booking: '#booking'
    };
    document.querySelectorAll('header a, nav a').forEach(link => {
      const label = normalize(link.textContent);
      if (targets[label]) link.setAttribute('href', targets[label]);
    });
  }

  function orderSections() {
    const { services, therapists, visit, booking } = findSections();
    if (!services || !therapists || !visit || !booking) return false;

    therapists.id = 'therapists-v36';
    visit.id = 'visit-v36';
    if (!booking.id) booking.id = 'booking';

    const unique = [...new Set([services, therapists, visit, booking])];
    if (unique.length !== 4) return false;

    const parent = commonParent(unique);
    if (!parent) return false;

    // Moving existing elements preserves all of their event listeners and form
    // behavior. Each element is appended in the requested customer journey.
    parent.appendChild(services);
    parent.appendChild(therapists);
    parent.appendChild(visit);
    parent.appendChild(booking);

    updateTherapistCopy(therapists);
    installTransition(visit, booking);
    updateNavigation();
    document.documentElement.dataset.sectionOrderV36 = 'complete';
    return true;
  }

  if (document.readyState === 'loading') {
    document.addEventListener('DOMContentLoaded', orderSections, { once: true });
  } else orderSections();

  let attempts = 0;
  const timer = setInterval(() => {
    attempts += 1;
    if (orderSections() || attempts >= 40) clearInterval(timer);
  }, 250);
})();
