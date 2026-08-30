# Proud Pops Booksy Availability

The Node.js 22 package is shared by five service-specific Lambda functions. Each function selects its Booksy service through `BOOKSY_SERVICE_VARIANT_ID`.

The response includes:

- `nextAvailable`
- `windowStart`
- `windowEnd`
- `slots`

The endpoint returns every available slot within fourteen calendar days beginning on the first available date. The frontend derives the available-date selector from the returned slot dates.
