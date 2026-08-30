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

  function markCurrentPage(){
    var path=window.location.pathname.replace(/\/$/,'/index.html');
    document.querySelectorAll('[data-site-nav] a').forEach(function(link){
      var linkPath=new URL(link.href,window.location.href).pathname.replace(/\/$/,'/index.html');
      if(path===linkPath)link.setAttribute('aria-current','page');
    });
  }

  function init(){initNavigation();markCurrentPage();}
  if(document.readyState==='loading')document.addEventListener('DOMContentLoaded',init);else init();
})();
