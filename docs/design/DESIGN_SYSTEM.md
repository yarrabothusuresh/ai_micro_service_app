# Dashboard implementation reference

Reference: `dashboard-concept.png`, generated with the built-in ImageGen tool for this demo. The concept is a reference, not an image used as functional UI.

Use a true white page, pale slate header and table headings, navy text, teal primary actions, thin slate dividers and 5–8 px corner radii. Use system sans-serif typography, a 46 px page heading, 26 px section headings, 15–20 px body text and readable 14–15 px labels and controls. The desktop reference has a full-width header, open summary strip, and a roughly 2.1:1 table/form layout. At narrow widths stack the form above the table; allow horizontal table scrolling rather than clipping data.

Visible empty-state copy: Ledger Manager, Dashboard, Postings, Create a posting and review its account decision., Total postings, INR volume, Recent postings, Refresh, Reference, Type, Account, Amount, Created, No postings yet, Create your first posting using the form., New posting, Transaction type, Currency, Narration, Create posting, Account selection happens when you submit.

Components: App shell, Summary, PostingTable and PostingForm. Repeat the same field, button, heading, panel and notice styles. No image assets are required by the dashboard itself. In the populated state show rule audit details using a native disclosure control. Add loading, validation, unavailable and saved states as required functional extensions. Never show zero totals or an empty-success state when data retrieval failed. Additional currencies receive their own summary values, never a combined monetary total.
