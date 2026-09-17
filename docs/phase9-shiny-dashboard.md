# Phase 9 — Shiny Dashboard

## Overview

This phase builds an interactive dashboard that prices a hypothetical policy — Term, Whole Life, or Deferred Whole Life — using the same pricing engine built and verified in Phase 6, wrapped in a user-friendly interface. No new actuarial logic was introduced in this phase; the dashboard's role is purely to provide an interface to already-verified calculations.

**Location:** `dashboard/pricing_dashboard/app.R`

## Architecture: UI and Server

A Shiny app consists of two components: a **UI**, defining what the user sees and interacts with, and a **server**, containing the logic that reacts to user input and produces output. The two are linked through reactive values — `input$<id>` reads a value the user entered, `output$<id>` writes a value back to be displayed, where `<id>` is a matching identifier defined in the UI.

### UI Structure

The interface uses a `sidebarLayout()` — inputs on the left (`sidebarPanel`), results on the right (`mainPanel`):

- `numericInput()` for Issue Age and Face Amount
- `selectInput()` for Smoker Status and Product Type — choices are spelled identically to the values used throughout the project (Phase 3 data, Phase 5 tables, all pricing functions), since a mismatch would cause lookups to silently fail
- `conditionalPanel()` for Term Length and Deferral Period — each field is shown only when relevant to the selected product, directly mirroring the nullable-field design of the Policy table schema (Phase 2)
- `actionButton()` to trigger calculation on demand, rather than recalculating on every keystroke

### Server Logic

```r
observeEvent(input$calculate, {
  # read inputs, conditionally read term/deferral, call calculate_gross_premium(), render output
})
```

`observeEvent()` watches the Calculate button specifically — the block inside only runs when it's clicked. Inputs are read into local variables, with `term_years`/`deferral_years` defaulting to `NA` and only populated when the selected product requires them (matching the same conditional logic used in the pricing engine since Phase 6). The values are passed directly into `calculate_gross_premium()` — the identical Phase 6 function, unmodified — and the result is formatted and written to `output$premium_output` via `renderText()`.

## Path Resolution Issue

A significant debugging exercise arose from Shiny's working-directory behavior differing across execution contexts:

- Running individual lines in the **Console** uses the RStudio Project's working directory (the project root) — `read_excel("excel/assumptions.xlsx", ...)` works correctly here.
- Running the app via **`runApp()`** or the **"Run App"** button uses the directory the `app.R` file is actually located in. Because the Shiny app creation wizard placed `app.R` inside an additional subfolder (`dashboard/pricing_dashboard/`, not directly in `dashboard/`), the correct relative path in this context required going up **two** directory levels: `read_excel("../../excel/assumptions.xlsx", ...)`.

This was diagnosed by explicitly checking `getwd()` under each execution context rather than assuming a single answer, and confirmed directly against the actual error message (`runApp('dashboard/pricing_dashboard')`), which revealed the true file location. The final script uses `../../` paths, correct for how the app is actually launched and intended to be run.

## Visual Design

The dashboard uses a custom `bslib` theme (Bootswatch "flatly" base, with a deep blue primary color) plus custom CSS for:
- A large, dark, low-opacity shield emoji watermark centered on the page
- Rounded corners, subtle shadows, and hover/focus transitions on inputs, buttons, and the results card
- A fixed copyright footer

All styling is layered on top of the functional UI/server logic without altering any input IDs or calculation code — visual and functional concerns were kept fully separate throughout.

## Validation

The dashboard was tested across all three products, confirming: correct conditional field display/hiding on product selection, correct routing of inputs into `calculate_gross_premium()`, and premiums matching values already verified in Phase 6 (e.g., age 40, Nonsmoker, Term, 20 years, $100,000 face amount → $135.50, confirmed identical to the Phase 6 test case).

## Limitations & Simplifying Assumptions

- **Interest rate is hardcoded at 5%** in the server logic rather than read from `economic_table` or exposed as a user input — the dashboard prices under the standard base-case assumption only; alternate economic scenarios are covered separately by Phase 8's sensitivity analysis, not by this interface.
- **The dashboard prices a single hypothetical policy per calculation** — it does not add policies to the underlying dataset or write back to the SQLite database.
- **No live deployment** — the app runs locally via RStudio (`runApp()` or the "Run App" button); it is not hosted on a public URL. GitHub stores and displays the source code but cannot execute R/Shiny applications directly; a service such as shinyapps.io would be required for a publicly accessible live version, noted here as a potential future enhancement rather than part of the current build.
- **No interactive sensitivity controls** (e.g., a live-adjustable interest rate slider) were added in this phase, consistent with the earlier decision to treat that as a possible future enhancement rather than a core requirement.

## Files

- `dashboard/pricing_dashboard/app.R` — complete UI and server code for the pricing dashboard