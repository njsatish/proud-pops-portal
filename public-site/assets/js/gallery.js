(function(){
  'use strict';
  var items=[];
  var current=0;
  var lastFocus=null;

  function init(){
    items=Array.from(document.querySelectorAll('[data-gallery-item]'));
    var lightbox=document.querySelector('[data-gallery-lightbox]');
    if(!items.length||!lightbox)return;
    var image=lightbox.querySelector('[data-gallery-lightbox-image]');
    var close=lightbox.querySelector('[data-gallery-close]');
    var previous=lightbox.querySelector('[data-gallery-prev]');
    var next=lightbox.querySelector('[data-gallery-next]');

    function render(){var item=items[current];image.src=item.dataset.gallerySrc;image.alt=item.dataset.galleryAlt||'Proud Pops portfolio image';}
    function open(index){current=index;lastFocus=document.activeElement;render();lightbox.classList.add('open');lightbox.setAttribute('aria-hidden','false');document.body.classList.add('pp-gallery-open');close.focus();}
    function dismiss(){lightbox.classList.remove('open');lightbox.setAttribute('aria-hidden','true');document.body.classList.remove('pp-gallery-open');image.removeAttribute('src');if(lastFocus)lastFocus.focus();}
    function move(delta){current=(current+delta+items.length)%items.length;render();}

    items.forEach(function(item,index){item.addEventListener('click',function(){open(index);});});
    close.addEventListener('click',dismiss);
    previous.addEventListener('click',function(){move(-1);});
    next.addEventListener('click',function(){move(1);});
    lightbox.addEventListener('click',function(event){if(event.target===lightbox)dismiss();});
    document.addEventListener('keydown',function(event){if(!lightbox.classList.contains('open'))return;if(event.key==='Escape')dismiss();if(event.key==='ArrowLeft')move(-1);if(event.key==='ArrowRight')move(1);});
  }

  if(document.readyState==='loading')document.addEventListener('DOMContentLoaded',init);else init();
})();
