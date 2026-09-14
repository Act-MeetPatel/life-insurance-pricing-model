# Phase 5 — Assumption Development

## Overview

This phase translates the Phase 4 mortality experience study into a formal set of pricing assumptions — mortality, expenses, interest rate, and target profit margin — and stores them in a structured Excel workbook (`excel/assumptions.xlsx`), separate from the R calculation logic that will consume them in later phases. This mirrors how real actuarial pricing work separates assumption ownership (typically maintained in workbooks by actuaries/product teams) from pricing engine code.

**Design principle:** every assumption in this workbook is stored as an explicit, labeled value — never hardcoded inside a formula — so that any assumption can be varied independently for Phase 8's sensitivity analysis without modifying calculation logic.

## Mortality Assumption

### From Observed Experience to Pricing Assumption

The Phase 4 observed mortality rates (Deaths ÷ Exposure, by 5-year age band and smoker status) are not used directly for pricing. Real actuarial practice applies a **margin for adverse deviation (prudence margin)** on top of best-estimate experience, since observed experience is a single noisy sample, and pricing on the raw estimate risks underpricing if actual future mortality proves worse than observed.

### Margin Structure

A **multiplicative** margin was applied (`pricing_qx = observed_qx × margin factor`), rather than an additive margin, since mortality rates span several orders of magnitude across the age range — an additive margin would be nonsensical at very low or very high rates.

Margin size was set based directly on the exposure reliability findings from Phase 4:

| Age Range | Margin | Rationale |
|---|---|---|
| 20–39 | 25% | Thin exposure, several zero-death cells observed in Phase 4 |
| 40–94 | 10% | Strong exposure, close observed-vs-true agreement in Phase 4 |
| 95+ | 25% | Very thin exposure, high volatility observed in Phase 4 (e.g., one cell based on 2 exposure-years) |

This directly ties the margin structure to evidence from the experience study, rather than an arbitrary flat margin.

### Probability Cap

One age-band/smoker cell (Smoker, age 100) had an observed mortality rate of 100% (from a very small exposure base), and applying the 25% margin produced a mathematically invalid result — a probability of 1.25, exceeding the maximum possible value of 1.0. This was corrected by capping all pricing_qx values at 1.0:

```r
mortality_experience$pricing_qx <- pmin(mortality_experience$pricing_qx, 1.0)
```

This is a legitimate and expected consideration when margining thin-data cells, not a coding error — noted here as a real modeling decision.

## Expense Assumptions

Expenses were set to vary by product, reflecting differences in underwriting complexity and ongoing administration:

| Product | Issue Expense | Annual Maintenance Expense |
|---|---|---|
| Term | $50 | $10 |
| Whole Life | $75 | $15 |
| Deferred Whole Life | $85 | $15 |

**Rationale:** Term retains the baseline figures used in Phase 1's illustrative examples. Whole Life carries higher issue and maintenance expense, reflecting more complex underwriting and indefinite policy duration. Deferred Whole Life carries the highest issue expense, reflecting the added administrative complexity of managing a deferral period on top of eventual lifetime coverage; its maintenance expense matches Whole Life's, since post-deferral the policy behaves identically.

## Economic Assumption

**Interest/discount rate: 5%**, consistent with the rate used throughout Phase 1's worked examples.

## Target Profit Margin

Target profit is expressed as a percentage of premium (present value of future profits ÷ present value of premiums — a standard actuarial profit measure), rather than a flat dollar amount, since a fixed dollar target is not meaningful across the project's $50,000–$500,000 face amount range.

| Product | Target Profit Margin |
|---|---|
| Term | 8% |
| Whole Life | 15% |
| Deferred Whole Life | 12% |

**Rationale:** these figures are adapted from a Society of Actuaries practitioner discussion on profit measures in pricing, which cited an example term portfolio producing an 8% return against a whole life portfolio producing 30%. The 8% Term figure was adopted directly. The Whole Life figure was scaled down substantially from the cited 30% to 15%, since that source's example reflects real whole life products with cash-value and investment components, which this project's Whole Life product does not model (pure protection only, no cash value). Deferred Whole Life was set at 12%, between Term and Whole Life, reflecting its added complexity (the deferral mechanism) without inheriting Whole Life's full duration and complexity profile.

**Source:** *Profit Measures in Pricing: Their Use and Interpretation*, Society of Actuaries (record of proceedings).

## Excel Workbook Structure

`excel/assumptions.xlsx` contains four sheets, generated directly from R (`write_xlsx()`), ensuring the workbook is fully reproducible from code rather than manually maintained:

| Sheet | Contents |
|---|---|
| Mortality | Full margined pricing mortality table (age band, smoker status, observed_qx, margin, pricing_qx) |
| Expenses | Issue and maintenance expense by product |
| Economic | Interest rate |
| Profit | Target profit margin by product |

This workbook is the assumption source of truth for Phase 6's pricing engine, which will read directly from it via `readxl` rather than having any assumption values typed into pricing code.

## Limitations & Simplifying Assumptions

- **Margin zones are based on this project's specific experience study results**, not a general actuarial standard — a different dataset would likely warrant different zone boundaries.
- **Profit margin figures are adapted from a single practitioner reference**, scaled down for Whole Life to account for the absence of cash-value/investment components in this project's product design — not derived from a broad industry benchmark study.
- **Expenses are illustrative, product-differentiated estimates**, not sourced from a specific insurer's actual expense study.

## Files

- `r/05_assumptions.R` — margined mortality calculation, expense/profit/economic assumption tables, and Excel workbook generation
- `excel/assumptions.xlsx` — the assumptions workbook (Mortality, Expenses, Economic, Profit sheets)