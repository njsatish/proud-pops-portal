/* BLOOMING_BOOKING_GAP_V40 */
(()=>{'use strict';if(window.__BL_BOOKING_GAP_V40__)return;window.__BL_BOOKING_GAP_V40__=true;
const text=e=>String(e?.textContent||'').replace(/\s+/g,' ').trim();
const meaningful=e=>[...e.querySelectorAll(':scope > *')].some(c=>!c.matches('script,style,link,template')&&(text(c)||c.matches('img,video,iframe,form,canvas,svg')));
function isEmptyVisual(e){if(!(e instanceof HTMLElement))return false;if(e.id==='visit-v36'||e.id==='booking-transition-v36'||e.id==='booking')return false;if(text(e)||meaningful(e))return false;let r=e.getBoundingClientRect(),s=getComputedStyle(e);return r.height>24&&(s.paddingTop!=='0px'||s.paddingBottom!=='0px'||s.minHeight!=='0px'||s.backgroundImage!=='none')}
function collapse(){const transition=document.getElementById('booking-transition-v36');if(!transition)return false;
 // Remove all consecutive empty siblings directly before the transition.
 let previous=transition.previousElementSibling,removed=0;
 while(previous&&isEmptyVisual(previous)){let victim=previous;previous=previous.previousElementSibling;victim.remove();removed++}
 // The gap can also be an empty last child inside the preceding wrapper.
 previous=transition.previousElementSibling;
 if(previous){let candidate=previous.lastElementChild;while(candidate&&isEmptyVisual(candidate)){let victim=candidate;candidate=candidate.previousElementSibling;victim.remove();removed++}}
 // Neutralize generated spacing even if the theme applies large margins.
 transition.style.setProperty('margin-top','24px','important');
 transition.style.setProperty('clear','both','important');
 document.documentElement.dataset.bookingGapV40=String(removed);
 return true}
if(document.readyState==='loading')document.addEventListener('DOMContentLoaded',collapse,{once:true});else collapse();let n=0,t=setInterval(()=>{n++;collapse();if(n>=30)clearInterval(t)},250)})();
