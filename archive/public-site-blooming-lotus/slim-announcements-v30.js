/* BLOOMING_SLIM_ANNOUNCEMENTS_V30 */
(() => {
  'use strict';
  if (window.__BL_SLIM_ANNOUNCEMENTS_V30__) return;
  window.__BL_SLIM_ANNOUNCEMENTS_V30__ = true;

  const DISMISS_PREFIX = 'bl-announcement-dismissed:';
  const escapeHtml = value => String(value ?? '').replace(/[&<>"']/g, ch => ({
    '&':'&amp;', '<':'&lt;', '>':'&gt;', '"':'&quot;', "'":'&#39;'
  })[ch]);

  function labelFor(item) {
    const type = String(item.type || 'INFO').toUpperCase();
    if (type === 'CLOSURE') return 'Closed';
    if (type === 'IMPORTANT') return 'Important';
    return 'Notice';
  }

  function shortDate(value) {
    if (!/^\d{4}-\d{2}-\d{2}$/.test(value || '')) return '';
    const [year, month, day] = value.split('-').map(Number);
    return new Intl.DateTimeFormat('en-US', {
      month:'short', day:'numeric', year:'numeric'
    }).format(new Date(year, month - 1, day));
  }

  function closureSummary(item) {
    if (!item.closureStartDate) return '';
    const start = shortDate(item.closureStartDate);
    const end = shortDate(item.closureEndDate);
    return start && end && start !== end ? `${start} – ${end}` : start;
  }

  function dismissed(id) {
    try { return sessionStorage.getItem(DISMISS_PREFIX + id) === '1'; }
    catch (_) { return false; }
  }

  function dismiss(id, bar) {
    try { sessionStorage.setItem(DISMISS_PREFIX + id, '1'); } catch (_) {}
    bar.remove();
  }

  function removeOldPresentation() {
    document.querySelectorAll(
      '.announcement-banner-v29, .slim-announcement-v30, #slim-announcement-stack-v30'
    ).forEach(node => node.remove());
  }

  function createBar(item) {
    const bar = document.createElement('section');
    const id = String(item.announcementId || 'announcement');
    const type = String(item.type || 'INFO').toLowerCase();
    const dates = closureSummary(item);
    bar.className = `slim-announcement-v30 slim-${type}-v30`;
    bar.dataset.announcementId = id;
    bar.setAttribute('role', type === 'closure' ? 'alert' : 'status');

    const bookingAction = item.blockAppointmentDates
      ? '<a class="slim-announcement-link-v30" href="#booking">Available dates</a>'
      : '';

    bar.innerHTML = `
      <div class="slim-announcement-inner-v30">
        <span class="slim-announcement-badge-v30">${escapeHtml(labelFor(item))}</span>
        <p>
          <strong>${escapeHtml(item.title || 'Schedule Notice')}</strong>
          ${dates ? `<span class="slim-announcement-dates-v30">${escapeHtml(dates)}</span>` : ''}
          <span>${escapeHtml(item.message || '')}</span>
        </p>
        ${bookingAction}
        <button type="button" class="slim-announcement-dismiss-v30"
          aria-label="Dismiss ${escapeHtml(item.title || 'announcement')}">×</button>
      </div>`;

    bar.querySelector('.slim-announcement-dismiss-v30')
      .addEventListener('click', () => dismiss(id, bar));
    return bar;
  }

  async function getActiveAnnouncements() {
    // Derive the existing V29 API URL from its downloaded script. This avoids a
    // second hard-coded environment value and preserves current infrastructure.
    const source = await fetch('/announcements-v29.js?v=29', { cache:'no-store' })
      .then(response => response.text());
    const match = source.match(/const API=(["'])(.*?)\1/);
    if (!match) throw new Error('Announcement API URL could not be located.');
    const response = await fetch(match[2] + '/announcements/active', { cache:'no-store' });
    if (!response.ok) throw new Error('Announcement API returned ' + response.status);
    const data = await response.json();
    return data.announcements || [];
  }

  async function render() {
    try {
      const items = await getActiveAnnouncements();
      removeOldPresentation();
      const visible = items.filter(item =>
        (item.showOnHomePage || item.showOnBookingForm || item.showOnAdmin) &&
        !dismissed(String(item.announcementId || 'announcement'))
      );
      if (!visible.length) return;

      const stack = document.createElement('div');
      stack.id = 'slim-announcement-stack-v30';
      stack.className = 'slim-announcement-stack-v30';
      visible.forEach(item => stack.appendChild(createBar(item)));

      // Place immediately below the concept-preview banner and above the main
      // site navigation/hero. On admin, place below the fixed header.
      const concept = document.querySelector('.concept-preview, [class*="concept-preview"]');
      if (concept) concept.insertAdjacentElement('afterend', stack);
      else {
        const header = document.querySelector('header');
        if (header) header.insertAdjacentElement('afterend', stack);
        else document.body.prepend(stack);
      }
    } catch (error) {
      console.warn('Slim announcements could not be rendered.', error);
    }
  }

  if (document.readyState === 'loading') {
    document.addEventListener('DOMContentLoaded', render, { once:true });
  } else render();
})();
