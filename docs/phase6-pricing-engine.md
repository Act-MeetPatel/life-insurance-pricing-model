# Phase 6 — Pricing Engine

## Overview

This phase builds the R pricing engine that reads assumptions from `excel/assumptions.xlsx` (Phase 5) and calculates a gross premium for a policy of any of the three products — Term, Whole Life, or Deferred Whole Life. Every formula below is verified against manual hand-calculation, not just confirmed to run without error, using a consistent worked example throughout: **a 40-year-old Nonsmoker, 3-year Term policy, $100,000 face amount, 5% interest rate.**

## Reading Assumptions from Excel

```r
mortality_table <- read_excel("excel/assumptions.xlsx", sheet = "Mortality")
expenses_table <- read_excel("excel/assumptions.xlsx", sheet = "Expenses")
economic_table <- read_excel("excel/assumptions.xlsx", sheet = "Economic")
profit_table <- read_excel("excel/assumptions.xlsx", sheet = "Profit")
```

All pricing inputs are pulled from the Phase 5 workbook — no assumption is hardcoded into any pricing formula, so any assumption can later be changed in one place (the Excel file) for Phase 8's sensitivity analysis.

## 1. Mortality Lookup — `get_pricing_qx()`

Since Phase 5's mortality table is banded into 5-year groups, each single age must be mapped to its band, and that band's `pricing_qx` applied flatly across every age within it (Option A: no interpolation).

$$\text{band}(x) = \left\lfloor \frac{x}{5} \right\rfloor \times 5$$

**Example:** ages 40, 41, and 42 all map to band 40, so:
$$q_{40} = q_{41} = q_{42} = 0.0004428936$$

## 2. Survival Probabilities — `calculate_survival_probs()`

The probability of being alive at the **start** of year t, given alive at issue, calculated by chaining single-year survival probabilities:

$$_{t}p_x = \prod_{k=0}^{t-1} p_{x+k}, \quad p_{x+k} = 1 - q_{x+k}$$

Position 1 is defined as exactly 1.0 (certain to be alive at issue, since coverage cannot begin otherwise); this is a deliberate convention, distinct from "survived through year t," and matches the timing assumption that premiums are collected at the start of each year the policyholder is alive.

**For Deferred Whole Life:** qx is set to 0 for every year within the deferral period before this chain is calculated, since no claim is possible during that window. This means px = 1 for those years, leaving survival probability unchanged through the deferral period — mirroring exactly how Phase 3's simulation treated deferral (no mortality risk simulated at all during the waiting period).

**Example (age 40, Nonsmoker, 3 years):**

| t | Age | ₜpₓ |
|---|---|---|
| 1 | 40 | 1.000000 |
| 2 | 41 | 0.999557 |
| 3 | 42 | 0.999114 |

## 3. PV(Claims) — `calculate_pv_claims()`

$$PV(\text{Claim}_t) = {}_{t}p_x \times q_{x+t-1} \times \text{Face} \times \frac{1}{(1+i)^t}$$

$$PV(\text{Claims}) = \sum_{t=1}^{n} PV(\text{Claim}_t)$$

Claims and expenses are assumed to occur at year-**end**, hence discounting by $t$ (full years).

**For Whole Life and Deferred Whole Life** (no fixed term), $n$ is set to `limiting_age − issue_age` (limiting age = 105, matching the age cap used in Phase 3's simulation), since coverage is assumed to run until death or this limiting age, at which point remaining survival probability is negligible.

**Example (age 40, Nonsmoker, 3-year Term, $100,000, 5%):**

| t | ₜpₓ | qₓ₊ₜ₋₁ | Discount | PV(Claimₜ) |
|---|---|---|---|---|
| 1 | 1.000000 | 0.000443 | 0.952381 | $42.18 |
| 2 | 0.999557 | 0.000443 | 0.907029 | $40.15 |
| 3 | 0.999114 | 0.000443 | 0.863838 | $38.22 |

**PV(Claims) = $120.56**

## 4. PV(Expenses) — `calculate_pv_expenses()`

$$PV(\text{Expenses}) = E_{\text{issue}} + \sum_{t=1}^{n} {}_{t}p_x \times E_{\text{maint}} \times \frac{1}{(1+i)^t}$$

Issue expense is incurred once, at time 0 — no discounting, no survival weighting (it is certain and immediate). Maintenance expense is incurred every year the policy is in force, including deferral-period years for Deferred Whole Life, reflecting the confirmed product design: premiums are paid and the policy is administered throughout the deferral period, only claim eligibility is withheld (see "Deferred Whole Life Product Design" below).

Expense figures vary by product (from Phase 5): Term $50 issue / $10 maintenance; Whole Life $75 / $15; Deferred Whole Life $85 / $15.

**Example (Term, age 40, Nonsmoker, 3 years):**

| t | ₜpₓ | Maintenance | Discount | PV(Maintₜ) |
|---|---|---|---|---|
| 1 | 1.000000 | $10 | 0.952381 | $9.52 |
| 2 | 0.999557 | $10 | 0.907029 | $9.07 |
| 3 | 0.999114 | $10 | 0.863838 | $8.63 |

**PV(Expenses) = $50 (issue) + $27.22 (maintenance) = $77.22**

## 5. Annuity Factor — `calculate_annuity_factor()`

The present value of a $1/year premium stream, survival-weighted. Premiums are assumed paid at the **start** of each year — year 1's premium is not discounted at all, distinguishing this from the claims/expenses discounting convention:

$$\ddot{a}_{x:\overline{n}|} = \sum_{t=1}^{n} {}_{t}p_x \times \frac{1}{(1+i)^{t-1}}$$

**Example (age 40, Nonsmoker, 3-year Term, 5%):**

| t | ₜpₓ | Discount | Contribution |
|---|---|---|---|
| 1 | 1.000000 | 1.000000 | 1.000000 |
| 2 | 0.999557 | 0.952381 | 0.951959 |
| 3 | 0.999114 | 0.907029 | 0.906226 |

**Annuity factor = 2.858185**

## 6. Solving for Gross Premium — `calculate_gross_premium()`

Since target profit is expressed as a **percentage of premium** (Phase 5), not a flat amount, premium appears on both sides of the core pricing equation and must be isolated algebraically:

$$PV(\text{Premiums}) = PV(\text{Claims}) + PV(\text{Expenses}) + m \times PV(\text{Premiums})$$

$$PV(\text{Premiums}) = \frac{PV(\text{Claims}) + PV(\text{Expenses})}{1 - m}$$

$$\text{Gross Premium} = \frac{PV(\text{Premiums})}{\ddot{a}_{x:\overline{n}|}}$$

where $m$ is the product-specific target profit margin from Phase 5 (Term 8%, Whole Life 15%, Deferred Whole Life 12%).

**Example (Term, m = 0.08):**

$$PV(\text{Premiums}) = \frac{120.56 + 77.22}{1 - 0.08} = \frac{197.78}{0.92} = 214.98$$

$$\text{Gross Premium} = \frac{214.98}{2.858185} = \mathbf{\$75.21}$$

## Deferred Whole Life Product Design

A design decision confirmed during this phase: **premiums are paid and the policy is administered throughout the deferral period** — only claim eligibility is withheld. This means:
- Maintenance expense accrues normally during deferral (the insurer is still administering the policy).
- Claim probability (qx) is zeroed during deferral, so PV(Claims) reflects zero contribution from those years.
- Survival probability is unaffected by the zeroed qx (multiplying by px = 1 leaves the running product unchanged).

This is distinct from a deferred-annuity-style structure where no payments occur in either direction until the deferral ends; this project's Deferred Whole Life is a life insurance product with deferred claim eligibility only.

## Validation

Six test policies were priced across all three products to confirm directional correctness:

| Product | Age | Smoker | Deferral | Premium |
|---|---|---|---|---|
| Term | 30 | Nonsmoker | — | $86.83 |
| Term | 30 | Smoker | — | $181.20 |
| Whole Life | 50 | Nonsmoker | — | $1,387.99 |
| Whole Life | 50 | Smoker | — | $2,194.18 |
| Deferred Whole Life | 40 | Nonsmoker | 5 yr | $778.73 |
| Deferred Whole Life | 40 | Nonsmoker | 10 yr | $761.68 |
| Whole Life (comparison) | 40 | Nonsmoker | — (no deferral) | $817.58 |

**Confirmed relationships:**
- Smoker premiums exceed Nonsmoker at matched age/product in all cases.
- Whole Life premiums substantially exceed Term premiums, reflecting guaranteed eventual payout versus conditional term coverage.
- Longer deferral periods produce lower premiums (761.68 < 778.73 < 817.58 no-deferral), confirming the deferral mechanism reduces required premium as expected.
- The smoker premium ratio is notably smaller for Whole Life (~1.58x) than for Term (~2.1x) despite the same 2.5x underlying mortality multiplier — attributed to the long Whole Life horizon diluting the proportional impact of the multiplier relative to cumulative age-driven risk. Noted as an observed pattern, not a defect.

## Limitations & Simplifying Assumptions

- **Whole Life and Deferred Whole Life are projected to a fixed limiting age (105)** rather than an unbounded horizon — consistent with Phase 3's simulation cap, and justified since survival probability beyond this age is negligible.
- **Premiums assumed level (unchanging) for the life of the policy** — no provision for increasing premiums, a common simplification in introductory pricing models.
- **The deferral period's effect on premium is modest when deferral occurs at younger ages**, since baseline mortality risk being "removed" is already low — this is a genuine finding of the model, not an error, and is more pronounced when deferral is applied at older starting ages.

## Files

- `r/06_pricing_engine.R` — mortality lookup, survival probabilities, PV(Claims), PV(Expenses), annuity factor, and gross premium solve, for all three products