(function(global){
  'use strict';

  var BUSINESS_ID='212027';
  var ALLOWED_VARIANTS=new Set(['7331041','7331042','7331043','7331044','7331046']);

  function buildDeepLink(service,slot){
    var variantId=String(service&&service.variantId||'');
    var date=String(slot&&slot.date||'');
    var time=String(slot&&slot.time||'');

    if(!ALLOWED_VARIANTS.has(variantId))throw new Error('Unsupported Booksy service variant.');
    if(!/^\d{4}-\d{2}-\d{2}$/.test(date))throw new Error('Invalid appointment date.');
    if(!/^\d{2}:\d{2}$/.test(time))throw new Error('Invalid appointment time.');

    var url=new URL('https://booksy.com/en-us/instant-experiences/widget/'+BUSINESS_ID);
    url.searchParams.set('variantId',variantId);
    url.searchParams.set('date',date+'T'+time);
    return url.toString();
  }

  function openFallback(){
    if(typeof global.openBooksyModal==='function'){global.openBooksyModal();return true;}
    var trigger=Array.from(document.querySelectorAll('a,button')).find(function(element){
      var label=(element.textContent||'').replace(/\s+/g,' ').trim();
      return !element.closest('[data-booking-root]')&&/BOOK NOW|BOOK APPOINTMENT|BOOK YOUR APPOINTMENT/i.test(label);
    });
    if(trigger){trigger.click();return true;}
    var link=document.querySelector('a[href*="booksy.com"]');
    if(link){link.click();return true;}
    return false;
  }

  function openSelection(service,slot){
    try{
      var url=buildDeepLink(service,slot);
      var opened=global.open(url,'_blank','noopener,noreferrer');
      if(opened)return true;
    }catch(error){console.warn('Verified Booksy deep link failed.',error);}
    return openFallback();
  }

  global.ProudPopsBooksy={buildDeepLink:buildDeepLink,openSelection:openSelection,openFallback:openFallback};
})(window);
