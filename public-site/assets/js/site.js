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
