import { useEffect, useMemo, useState } from 'react'

const apiBase = import.meta.env.VITE_API_BASE_URL || 'https://wkpl27gu7j.execute-api.us-east-1.amazonaws.com'
const staff = { name: 'Steve', businessId: 212027 }
const formatDetails = (service) => [service.priceLabel, `${service.durationMinutes} min`].filter(Boolean).join(' · ')
const formatDate = (value) => new Intl.DateTimeFormat('en-US', { weekday: 'long', month: 'long', day: 'numeric' }).format(new Date(`${value}T12:00:00`))
const formatTime = (value) => {
  const [hour, minute] = String(value).split(':').map(Number)
  return new Intl.DateTimeFormat('en-US', { hour: 'numeric', minute: '2-digit' }).format(new Date(2000, 0, 1, hour, minute || 0))
}

export default function TwoColumnBookingArea({ services }) {
  const [selectedServiceId, setSelectedServiceId] = useState('')
  const [availability, setAvailability] = useState(null)
  const [selectedDate, setSelectedDate] = useState('')
  const [selectedTime, setSelectedTime] = useState('')
  const [loading, setLoading] = useState(false)
  const [error, setError] = useState('')
  const [widgetOpen, setWidgetOpen] = useState(false)
  /* PROUDPOPS-BOOKSY-LOADING-V1-STATE-START */
  const [widgetLoaded, setWidgetLoaded] = useState(false)
  /* PROUDPOPS-BOOKSY-LOADING-V1-STATE-END */

  const selectedService = useMemo(() => services.find((service) => String(service.id) === selectedServiceId) || null, [services, selectedServiceId])
  const selectedDateTimes = useMemo(() => (availability?.slots || []).filter((slot) => slot.date === selectedDate), [availability, selectedDate])

  useEffect(() => {
    if (!widgetOpen) return undefined
    const closeOnEscape = (event) => { if (event.key === 'Escape') setWidgetOpen(false) }
    document.body.classList.add('modal-open')
    window.addEventListener('keydown', closeOnEscape)
    return () => {
      document.body.classList.remove('modal-open')
      window.removeEventListener('keydown', closeOnEscape)
    }
  }, [widgetOpen])

  const chooseService = async (service) => {
    setSelectedServiceId(String(service.id))
    setAvailability(null)
    setSelectedDate('')
    setSelectedTime('')
    setWidgetOpen(false)
    setWidgetLoaded(false)
    setError('')
    setLoading(true)
    try {
      const response = await fetch(`${apiBase}${service.availabilityPath}?v=${Date.now()}`, {
        cache: 'no-store', credentials: 'omit', headers: { Accept: 'application/json' },
      })
      if (!response.ok) throw new Error(`Availability request failed (${response.status})`)
      const data = await response.json()
      if (data.success !== true || !Array.isArray(data.slots)) throw new Error('Invalid availability response')
      const dates = [...new Set(data.slots.map((slot) => slot.date).filter(Boolean))].sort().map((value) => ({ value, label: formatDate(value) }))
      const slots = data.slots.filter((slot) => slot?.date && slot?.time).map((slot) => ({ date: slot.date, value: slot.time, label: formatTime(slot.time) }))
      setAvailability({ dates, slots })
      if (dates.length === 1) setSelectedDate(dates[0].value)
    } catch (requestError) {
      console.error(requestError)
      setError('Live availability is temporarily unavailable.')
    } finally {
      setLoading(false)
    }
  }

  const selectDate = (date) => { setSelectedDate(date); setSelectedTime('') }
  const selectedDateLabel = availability?.dates?.find((date) => date.value === selectedDate)?.label || selectedDate
  const selectedTimeLabel = selectedDateTimes.find((time) => time.value === selectedTime)?.label || selectedTime
  const widgetURL = selectedService && selectedDate && selectedTime
    ? `https://booksy.com/widget/index.html?id=${staff.businessId}` +
      `&variantId=${encodeURIComponent(selectedService.variantId)}` +
      `&date=${encodeURIComponent(`${selectedDate}T${selectedTime}`)}` +
      '&lang=en&country=us'
    : 'about:blank'

  return <section id="booking-area" className="two-column-booking" aria-label="Choose a service, date, and time">
    <div className="wrap">
      <div className="booking-columns">
        <section className="booking-column" aria-labelledby="service-title">
          <span className="column-number">1</span>
          <h3 id="service-title">Choose a service</h3>
          <p className="column-help">Five exact Proud Pops Booksy services.</p>
          <div className="booking-selection-list standalone">
            {services.map((service) => <button type="button" key={service.id} className={`booking-selection ${selectedServiceId === String(service.id) ? 'is-selected' : ''}`} onClick={() => chooseService(service)}>
              <strong>{service.name}</strong><span>{formatDetails(service)}</span>
            </button>)}
          </div>
        </section>
        <section className="booking-column" aria-labelledby="availability-title">
          <span className="column-number">2</span>
          <h3 id="availability-title">Choose date and time</h3>
          <p className="column-help">Live availability for the selected Proud Pops service.</p>
          {!selectedService && <p className="booking-state">Select a service to load availability.</p>}
          {loading && <p className="booking-state">Loading live availability…</p>}
          {error && <p className="booking-error">{error}</p>}
          {availability && !loading && <>
            <label className="booking-field"><span>Date</span><select value={selectedDate} onChange={(event) => selectDate(event.target.value)}><option value="">Select date</option>{availability.dates.map((date) => <option key={date.value} value={date.value}>{date.label}</option>)}</select></label>
            <div className="booking-field"><span>Time</span>{!selectedDate && <p className="booking-state compact">Choose a date first.</p>}{selectedDate && selectedDateTimes.length === 0 && <p className="booking-state compact">No times are currently available.</p>}{selectedDateTimes.length > 0 && <div className="time-grid">{selectedDateTimes.map((time) => <button type="button" key={`${time.date}-${time.value}`} className={selectedTime === time.value ? 'is-selected' : ''} onClick={() => setSelectedTime(time.value)}>{time.label}</button>)}</div>}</div>
          </>}
          <button type="button" className="booking-continue" disabled={!selectedService || !selectedDate || !selectedTime} onClick={() => { setWidgetLoaded(false); setWidgetOpen(true) }}>{selectedTime ? `Continue · ${selectedDateLabel} at ${selectedTimeLabel}` : 'Select service, date and time'}</button>
        </section>
      </div>
    </div>
    {widgetOpen && selectedService && <div className="booking-widget-modal" role="dialog" aria-modal="true" aria-labelledby="booking-widget-title">
      <button className="booking-widget-backdrop" type="button" aria-label="Close booking" onClick={() => { setWidgetOpen(false); setWidgetLoaded(false) }} />
      <section className="booking-widget-dialog">
        <header><div><strong id="booking-widget-title">Book with {staff.name}</strong><span>{selectedService.name} · {selectedDateLabel} at {selectedTimeLabel}</span></div><button type="button" aria-label="Close booking" onClick={() => { setWidgetOpen(false); setWidgetLoaded(false) }}>×</button></header>
        <div className={`booking-widget-frame-shell ${widgetLoaded ? 'is-loaded' : ''}`}>
          <div className="booking-widget-loading" role="status" aria-live="polite" aria-label="Loading secure Booksy booking">
            <div className="booking-widget-loading__brand" aria-hidden="true">
              <span className="booking-widget-loading__mark">PP</span>
              <span className="booking-widget-loading__name">Proud Pops Barbershop</span>
            </div>
            <div className="booking-widget-loading__spinner" aria-hidden="true"></div>
            <strong>Loading secure Booksy booking</strong>
            <span>Keeping your selected service, date, and time ready.</span>
          </div>
          <iframe
            src={widgetURL}
            title={`${staff.name} Booksy booking widget`}
            allow="geolocation; microphone; camera; payment"
            referrerPolicy="strict-origin-when-cross-origin"
            onLoad={() => setWidgetLoaded(true)}
          />
        </div>
        <footer>Secure booking provided by Booksy.</footer>
      </section>
    </div>}
  </section>
}
