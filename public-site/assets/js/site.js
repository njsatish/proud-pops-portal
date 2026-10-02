// PROUDPOPS-SINGLE-ACTIVE-NAVIGATION-V1
(function(){
  'use strict';

  function initNavigation(){
    var button=document.querySelector('[data-menu-toggle]');
    var nav=document.querySelector('[data-site-nav]');
    if(!button||!nav)return;

    function setOpen(open){
      nav.classList.toggle('open',open);
      button.setAttribute('aria-expanded',String(open));
    }

    button.addEventListener('click',function(){setOpen(!nav.classList.contains('open'));});
    document.addEventListener('keydown',function(event){if(event.key==='Escape')setOpen(false);});
    nav.addEventListener('click',function(event){if(event.target.closest('a'))setOpen(false);});
  }

  function normalizePath(value){
    var path=String(value||'/').split('?')[0].split('#')[0];
    if(path==='/'||path==='')return '/index.html';
    if(path.length>1&&path.endsWith('/'))path=path.slice(0,-1);
    return path;
  }

  function markCurrentPage(){
    var currentPath=normalizePath(window.location.pathname);
    var links=Array.from(document.querySelectorAll('[data-site-nav] a'));

    links.forEach(function(link){link.removeAttribute('aria-current');});

    var currentLink=links.find(function(link){
      return normalizePath(new URL(link.href,window.location.href).pathname)===currentPath;
    });

    if(currentLink)currentLink.setAttribute('aria-current','page');
  }

  function init(){initNavigation();markCurrentPage();}
  if(document.readyState==='loading')document.addEventListener('DOMContentLoaded',init);else init();
})();

/* PROUDPOPS-SAME-PAGE-BOOKSY-WIDGET-V1-START */
(() => {
  'use strict';

  const MODAL_ID = 'pp-booksy-widget-modal';
  const BOOKSY_HOSTS = new Set(['booksy.com', 'www.booksy.com']);
  const INSTANT_PATH = '/en-us/instant-experiences/widget/';
  const WIDGET_PATH = '/widget/index.html';
  let lastTrigger = null;

  function decodeHTML(value) {
    const textarea = document.createElement('textarea');
    textarea.innerHTML = value || '';
    return textarea.value;
  }

  function toWidgetURL(rawURL) {
    if (!rawURL) return null;

    let parsed;
    try {
      parsed = new URL(decodeHTML(rawURL), window.location.href);
    } catch {
      return null;
    }

    if (!BOOKSY_HOSTS.has(parsed.hostname.toLowerCase())) return null;

    let businessId = parsed.searchParams.get('id') || '';
    if (parsed.pathname.startsWith(INSTANT_PATH)) {
      businessId = parsed.pathname.slice(INSTANT_PATH.length).split('/')[0];
    }
    if (parsed.pathname === WIDGET_PATH && businessId) return parsed.toString();
    if (!businessId) return null;

    const variantId = parsed.searchParams.get('variantId');
    const selectedDateTime = parsed.searchParams.get('date');
    if (!variantId || !selectedDateTime) return null;

    const widget = new URL('https://booksy.com/widget/index.html');
    widget.searchParams.set('id', businessId);
    widget.searchParams.set('variantId', variantId);
    widget.searchParams.set('date', selectedDateTime);
    widget.searchParams.set('lang', parsed.searchParams.get('lang') || 'en');
    widget.searchParams.set('country', parsed.searchParams.get('country') || 'us');
    return widget.toString();
  }

  function selectedSummary(url) {
    const dateValue = url.searchParams.get('date') || '';
    const [date, time] = dateValue.split('T');
    if (!date || !time) return 'Complete the selected appointment in Booksy.';

    const localDate = new Date(`${date}T00:00:00`);
    const [hours, minutes] = time.split(':').map(Number);
    const timeDate = new Date(2000, 0, 1, hours, minutes);
    const dateLabel = Number.isNaN(localDate.getTime())
      ? date
      : new Intl.DateTimeFormat('en-US', {
          weekday: 'short',
          month: 'short',
          day: 'numeric',
          year: 'numeric',
        }).format(localDate);
    const timeLabel = Number.isNaN(timeDate.getTime())
      ? time
      : new Intl.DateTimeFormat('en-US', {
          hour: 'numeric',
          minute: '2-digit',
        }).format(timeDate);
    return `${dateLabel} at ${timeLabel}`;
  }

  function createModal() {
    const existing = document.getElementById(MODAL_ID);
    if (existing) return existing;

    const modal = document.createElement('div');
    modal.id = MODAL_ID;
    modal.className = 'pp-booksy-modal';
    modal.hidden = true;
    modal.innerHTML = `
      <button class="pp-booksy-modal__backdrop" type="button" aria-label="Close Booksy booking"></button>
      <section class="pp-booksy-modal__dialog" role="dialog" aria-modal="true" aria-labelledby="pp-booksy-modal-title">
        <header class="pp-booksy-modal__header">
          <div>
            <strong id="pp-booksy-modal-title">Complete Your Booking</strong>
            <span class="pp-booksy-modal__summary">Selected appointment</span>
          </div>
          <button class="pp-booksy-modal__close" type="button" aria-label="Close booking">×</button>
        </header>
        <div class="pp-booksy-modal__frame-wrap">
          <div class="pp-booksy-modal__loading" role="status">Loading secure Booksy booking…</div>
          <iframe
            class="pp-booksy-modal__frame"
            title="Proud Pops Booksy booking widget"
            allow="geolocation; microphone; camera; payment"
            referrerpolicy="strict-origin-when-cross-origin"
          ></iframe>
        </div>
        <footer class="pp-booksy-modal__footer">
          <span>Secure booking provided by Booksy.</span>
          <a class="pp-booksy-modal__fallback" href="#" rel="noopener">Open directly in Booksy</a>
        </footer>
      </section>`;

    modal.querySelector('.pp-booksy-modal__backdrop').addEventListener('click', closeModal);
    modal.querySelector('.pp-booksy-modal__close').addEventListener('click', closeModal);
    modal.querySelector('.pp-booksy-modal__frame').addEventListener('load', () => {
      modal.classList.add('is-loaded');
    });
    document.body.appendChild(modal);
    return modal;
  }

  function openModal(widgetURL, trigger) {
    const modal = createModal();
    const parsed = new URL(widgetURL);
    const frame = modal.querySelector('.pp-booksy-modal__frame');
    const fallback = modal.querySelector('.pp-booksy-modal__fallback');
    const summary = modal.querySelector('.pp-booksy-modal__summary');

    lastTrigger = trigger || document.activeElement;
    modal.classList.remove('is-loaded');
    summary.textContent = selectedSummary(parsed);
    fallback.href = widgetURL;
    frame.src = widgetURL;
    modal.hidden = false;
    document.documentElement.classList.add('pp-booksy-modal-open');
    document.body.classList.add('pp-booksy-modal-open');
    modal.querySelector('.pp-booksy-modal__close').focus();
  }

  function closeModal() {
    const modal = document.getElementById(MODAL_ID);
    if (!modal || modal.hidden) return;
    modal.hidden = true;
    modal.classList.remove('is-loaded');
    modal.querySelector('.pp-booksy-modal__frame').src = 'about:blank';
    document.documentElement.classList.remove('pp-booksy-modal-open');
    document.body.classList.remove('pp-booksy-modal-open');
    if (lastTrigger && typeof lastTrigger.focus === 'function') lastTrigger.focus();
  }

  function candidateURL(element) {
    if (!element) return '';
    return (
      element.dataset.booksyUrl ||
      element.dataset.bookingUrl ||
      element.getAttribute('href') ||
      element.closest('[data-booksy-url]')?.dataset.booksyUrl ||
      element.closest('[data-booking-url]')?.dataset.bookingUrl ||
      ''
    );
  }

  document.addEventListener('click', (event) => {
    const trigger = event.target.closest('a, button, [data-booksy-url], [data-booking-url]');
    if (!trigger) return;
    const widgetURL = toWidgetURL(candidateURL(trigger));
    if (!widgetURL) return;

    event.preventDefault();
    event.stopPropagation();
    if (typeof event.stopImmediatePropagation === 'function') event.stopImmediatePropagation();
    trigger.removeAttribute('target');
    openModal(widgetURL, trigger);
  }, true);

  document.addEventListener('keydown', (event) => {
    if (event.key === 'Escape') closeModal();
  });

  window.ProudPopsBooksyWidget = {
    open(rawURL) {
      const widgetURL = toWidgetURL(rawURL);
      if (!widgetURL) throw new Error('A valid Booksy URL with business ID, variantId, and date is required.');
      openModal(widgetURL, document.activeElement);
    },
    close: closeModal,
    toWidgetURL,
  };
})();
/* PROUDPOPS-SAME-PAGE-BOOKSY-WIDGET-V1-END */
