// PROUDPOPS-SEVEN-DAY-AVAILABILITY-V3
const BOOKSY_API_KEY = process.env.BOOKSY_API_KEY;
const BOOKSY_APP_VERSION = process.env.BOOKSY_APP_VERSION;
const BOOKSY_FINGERPRINT = process.env.BOOKSY_FINGERPRINT;
const BUSINESS_ID = process.env.BOOKSY_BUSINESS_ID;
const SERVICE_VARIANT_ID = Number(process.env.BOOKSY_SERVICE_VARIANT_ID);


function addCalendarDays(dateText, days) {
  const date = new Date(`${dateText}T12:00:00Z`);
  date.setUTCDate(date.getUTCDate() + days);
  return date.toISOString().slice(0, 10);
}
function selectSevenDayWindow(allSlots) {
  const ordered = (Array.isArray(allSlots) ? allSlots : [])
    .filter((slot) => slot && slot.date && slot.time)
    .sort((a,b) => String(a.date).localeCompare(String(b.date)) || String(a.time).localeCompare(String(b.time)));
  if (!ordered.length) return { windowStart: null, windowEnd: null, slots: [] };
  const windowStart = ordered[0].date;
  const windowEnd = addCalendarDays(windowStart, 6);
  return { windowStart, windowEnd, slots: ordered.filter((slot) => slot.date >= windowStart && slot.date <= windowEnd) };
}

export const handler = async () => {
  try {
    const startDate = new Date();
    const endDate = new Date();
    endDate.setDate(startDate.getDate() + 30);

    const response = await fetch(
      `https://us.booksy.com/core/v2/customer_api/me/businesses/${BUSINESS_ID}/appointments/time_slots`,
      {
        method: 'POST',
        headers: {
          'Accept': 'application/json',
          'Content-Type': 'application/json',
          'Origin': 'https://booksy.com',
          'Referer': 'https://booksy.com/',
          'X-Api-Key': BOOKSY_API_KEY,
          'X-App-Version': BOOKSY_APP_VERSION,
          'X-Fingerprint': BOOKSY_FINGERPRINT
        },
        body: JSON.stringify({
          subbookings: [{
            service_variant_id: SERVICE_VARIANT_ID,
            staffer_id: -1,
            combo_children: []
          }],
          start_date: startDate.toISOString().split('T')[0],
          end_date: endDate.toISOString().split('T')[0]
        })
      }
    );

    const data = await response.json();
    const slots = [];

    for (const day of (data.time_slots || [])) {
      for (const slot of (day.slots || [])) {
        slots.push({ date: day.date, time: slot.t });
      }
    }

    const sevenDayAvailability = selectSevenDayWindow(slots);
    return {
      statusCode: 200,
      headers: {
        'Content-Type': 'application/json',
        'Access-Control-Allow-Origin': '*'
      },
      body: JSON.stringify({
        success: true,
        nextAvailable: sevenDayAvailability.slots[0] || null,
        windowStart: sevenDayAvailability.windowStart,
        windowEnd: sevenDayAvailability.windowEnd,
        slots: sevenDayAvailability.slots
      })
    };
  } catch (error) {
    return {
      statusCode: 500,
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ success: false, error: error.message })
    };
  }
};
