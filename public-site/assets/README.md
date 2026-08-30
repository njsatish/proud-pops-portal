# Proud Pops Shared Multipage Assets

## CSS

- `css/site.css`: global design tokens, header, navigation, footer, buttons, responsive layout, and mobile actions.
- `css/booking.css`: booking form, service summary, date/time controls, loading state, and selected appointment summary.

## JavaScript

- `js/site.js`: mobile navigation and active-page state.
- `js/booking.js`: service-specific availability, available-date rendering, time selection, and booking summary.
- `js/booksy.js`: verified Booksy deep-link builder and official widget fallback.

These files are added without modifying the current production HTML pages. The next phase should create `book.html` using these shared assets and validate behavior before any homepage cutover.
