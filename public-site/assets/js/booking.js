(function(global){
  'use strict';

  var API_BASE='https://wkpl27gu7j.execute-api.us-east-1.amazonaws.com';
  var SERVICES={
    'haircut':{name:'Haircut',duration:45,price:40,variantId:7331041,path:'/booksy/availability'},
    'beard-trim':{name:'Beard Trim',duration:25,price:20,variantId:7331042,path:'/booksy/availability/beard-trim'},
    'shave':{name:'Shave',duration:20,price:15,variantId:7331043,path:'/booksy/availability/shave'},
    'haircut-enhancement':{name:'Haircut With Enhancement',duration:60,price:50,variantId:7331044,path:'/booksy/availability/haircut-enhancement'},
    'edgeup':{name:'Edgeup',duration:30,price:25,variantId:7331046,path:'/booksy/availability/edgeup'}
  };

  function formatDate(value){return new Intl.DateTimeFormat('en-US',{weekday:'long',month:'long',day:'numeric'}).format(new Date(value+'T12:00:00'));}
  function formatTime(value){var parts=String(value).split(':'),hour=Number(parts[0]),minute=parts[1]||'00';return(hour%12||12)+':'+minute+' '+(hour>=12?'PM':'AM');}

  function init(root){
    var serviceSelect=root.querySelector('[data-booking-service]');
    var dateSelect=root.querySelector('[data-booking-date]');
    var refresh=root.querySelector('[data-booking-refresh]');
    var status=root.querySelector('[data-booking-status]');
    var times=root.querySelector('[data-booking-times]');
    var selection=root.querySelector('[data-booking-selection]');
    var bookButton=root.querySelector('[data-booking-confirm]');
    var state={serviceKey:'haircut',slots:[],date:'',slot:null,controller:null};

    function currentService(){return SERVICES[state.serviceKey];}
    function setStatus(message,loading){status.innerHTML=(loading?'<span class="pp-spinner" aria-hidden="true"></span>':'')+message;}
    function updateService(){var s=currentService();root.querySelector('[data-service-name]').textContent=s.name;root.querySelector('[data-service-meta]').textContent=s.duration+' min • Booksy availability';root.querySelector('[data-service-price]').textContent='$'+s.price;}
    function clearSelection(){state.slot=null;selection.classList.remove('active');times.querySelectorAll('.pp-time').forEach(function(button){button.setAttribute('aria-pressed','false');});}
    function dates(){return Array.from(new Set(state.slots.map(function(slot){return slot.date;}).filter(Boolean))).sort();}

    function renderDates(){
      var values=dates();dateSelect.innerHTML='';
      if(!values.length){dateSelect.disabled=true;dateSelect.innerHTML='<option>No dates returned</option>';return false;}
      values.forEach(function(value){var option=document.createElement('option');option.value=value;option.textContent=formatDate(value);dateSelect.appendChild(option);});
      state.date=values[0];dateSelect.value=state.date;dateSelect.disabled=false;return true;
    }

    function renderTimes(){
      clearSelection();times.innerHTML='';
      var matches=state.slots.filter(function(slot){return slot.date===state.date;});
      setStatus(matches.length+' available time'+(matches.length===1?'':'s')+' for '+formatDate(state.date)+'.',false);
      matches.forEach(function(slot){
        var button=document.createElement('button');button.type='button';button.className='pp-time';button.textContent=formatTime(slot.time);button.setAttribute('aria-pressed','false');
        button.addEventListener('click',function(){clearSelection();state.slot=slot;button.setAttribute('aria-pressed','true');var s=currentService();root.querySelector('[data-selection-main]').textContent='Your selection: '+s.name+' at '+formatTime(slot.time);root.querySelector('[data-selection-detail]').textContent=formatDate(slot.date)+' • '+s.duration+' min • $'+s.price;selection.classList.add('active');});
        times.appendChild(button);
      });
    }

    function load(){
      if(state.controller)state.controller.abort();state.controller=new AbortController();clearSelection();dateSelect.disabled=true;times.innerHTML='';setStatus('Checking '+currentService().name+' availability…',true);
      fetch(API_BASE+currentService().path+'?v='+Date.now(),{cache:'no-store',credentials:'omit',signal:state.controller.signal})
        .then(function(response){if(!response.ok)throw new Error('HTTP '+response.status);return response.json();})
        .then(function(data){if(data.success!==true||!Array.isArray(data.slots))throw new Error('Invalid availability response');state.slots=data.slots.filter(function(slot){return slot&&slot.date&&slot.time;});if(!renderDates()){setStatus('No upcoming availability was returned.',false);return;}renderTimes();})
        .catch(function(error){if(error.name==='AbortError')return;state.slots=[];dateSelect.innerHTML='<option>Unavailable</option>';setStatus('Live availability is temporarily unavailable.',false);});
    }

    serviceSelect.addEventListener('change',function(event){state.serviceKey=event.target.value;updateService();load();});
    dateSelect.addEventListener('change',function(event){state.date=event.target.value;renderTimes();});
    refresh.addEventListener('click',load);
    bookButton.addEventListener('click',function(){if(!state.slot)return;global.ProudPopsBooksy.openSelection(currentService(),state.slot);});

    var requested=new URLSearchParams(global.location.search).get('service');
    if(Object.prototype.hasOwnProperty.call(SERVICES,requested)){state.serviceKey=requested;serviceSelect.value=requested;}
    updateService();load();
  }

  function start(){document.querySelectorAll('[data-booking-root]').forEach(init);}
  if(document.readyState==='loading')document.addEventListener('DOMContentLoaded',start);else start();
})(window);
