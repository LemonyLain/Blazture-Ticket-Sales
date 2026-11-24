# Blazture Ticket Sales: 2025 vs 2026

A SQL + dashboard project analyzing ticket sales for Blazture, a festival whose ticketing division I head at Statistics Day. Built to practice SQL and BI tools (MySQL, Looker Studio) alongside my background in statistics and Python.

**[View the live dashboard](https://datastudio.google.com/reporting/40e8d04f-1cb7-4b4c-8aaa-6ae6ec4fed6e)**

---

## The question

Blazture's ticket sales grew from 1,972 to 2,987 tickets across two editions — about +51%. As the festival's ticketing lead, I wanted to know *why*: which ticket types and sales channels drove that growth, how the pace of sales differed between years, and when buyers actually pull the trigger. The goal was to turn operational data I already had access to into decisions a marketing or events team could act on — which phases to repeat, which channel to invest in, and when to schedule promotions.

## The data and method

The source was Blazture's own ticketing records: two editions, two sales channels (a website and manual WhatsApp orders), with no personal buyer information in the export. I used MySQL to build the pipeline (full script: [`blazture_project.sql`](./blazture_project.sql)):

- **Staging and cleaning:** loaded the raw export into a staging table, then mapped inconsistent ticket-type labels (typos, year-specific naming) into clean categories using a lookup table, with a safety check to guarantee nothing fell through unmapped.
- **Grain mismatch:** the two channels record differently — one row per ticket on the web, one row per transaction (with a quantity) on WhatsApp — so every query sums `quantity` rather than counting rows.
- **Date repair:** a meaningful share of manual-order dates had day and month transposed by Excel. I caught this by cross-checking each date against the known sales window for that ticket phase (a Presale 2 ticket can't be dated before Presale 2 opened), then corrected the affected rows.
- **Reconciliation:** I compared my cleaned totals against the ticketing team's own manual recap. 2026 matched exactly once I added 41 tickets the recap had that the export was missing (a bundle and on-the-spot shortfall). 2025 still runs 5 tickets short of the historical count, so I report 1,972 as the verified total for 2025 and note the discrepancy rather than silently adjusting it.
- **Analysis:** window functions for cumulative sales curves, a manual pivot (`CASE WHEN`) to compare ticket types side by side between editions, and a hard rule that special-offer tickets (bundles, promos, on-the-spot) are *not* compared year-over-year because they were different products each year — only Early Bird and Presale 1–3 get a growth percentage.
- **Dashboard:** built in Google Looker Studio from exported, aggregated CSVs (in [`dashboard_data/`](./dashboard_data)) — no row-level or personal data was published.

## What the data showed

- **2026 grew but started slower.** By day 60 of sales, 2025 had sold 20.8% of its tickets versus 9.6% for 2026. 2026 didn't catch up in raw ticket count until day 81 of its sales window, then pulled ahead and finished with 51% more tickets.
- **One phase explains almost all the growth.** Presale 2 sold 1,959 tickets in 2026 (65.6% of the edition), up 150% from 783 in 2025. Presale 1 fell 57% over the same period. Early Bird and Presale 3 both grew modestly. The net effect: one phase shift, not a broad-based increase, drove the year-over-year growth.
- **Sales moved almost entirely online.** The web channel's share rose from 76.1% to 93.1% of tickets; manual WhatsApp transactions fell from 248 to 78, even though the average order size on WhatsApp held steady at around 2 tickets.
- **Evenings dominate buying behavior.** 18:00–23:59 accounted for 42–48% of web tickets in both years, peaking around 20:00 — a clear window for timing promotional pushes or reminder messages.
- **Sales spikes track the phase calendar, not the calendar week.** The busiest days in both editions cluster tightly around each presale's opening or closing date; weekday patterns looked meaningful at first glance but turned out to be an artifact of which day phases happened to end on, so I excluded that chart rather than publish a misleading pattern.

## Limits and next step

The data shows *when* and *through which channel* people bought, not *why* Presale 2 outperformed Presale 1 — that likely reflects a pricing or messaging decision made by the organizing team, which isn't captured in the ticketing records. I'd also flag that 2025's total carries a small (5-ticket) unresolved gap against the historical count, which I've disclosed rather than smoothed over. For the next edition, I'd recommend instrumenting *why* behind presale performance (e.g., which specific promotion ran, or capacity constraints) so that pattern can be explained with data instead of guessed at afterward.

## Repo contents

- `blazture_project.sql` — full MySQL pipeline: staging, cleaning, ticket-type mapping, reconciliation, and the five analytical views
- `dashboard_data/` — the aggregated, anonymized CSV exports used to build the dashboard (no row-level or personal data)
- `staging_sales.csv` — the cleaned-but-still-row-level staging file (dates, ticket type, quantity — no buyer information), included for full pipeline transparency

## Tools

MySQL (MySQL Workbench) for data cleaning and analysis · Google Looker Studio for the dashboard
