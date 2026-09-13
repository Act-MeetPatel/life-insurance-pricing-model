---
output:
  html_document: default
  pdf_document: default
---
# Phase 3 — Synthetic Experience Data

## Overview

This phase generates the experience data the rest of the project analyzes and prices against: 10,000 synthetic policies across three products (Term, Whole Life, and Deferred Whole Life), simulated year-by-year against an underlying "true" mortality pattern, producing a full set of policy, exposure, and death records loaded into the SQLite database designed in Phase 2.

The purpose of this phase is to create data that *behaves* like real insurance experience data — with a genuine, recoverable mortality signal — without using any real, proprietary, or personally identifiable information. The mortality pattern used to generate this data is treated as a modeling assumption, not an empirical fact; Phase 4 independently recovers mortality rates from the generated Death and Exposure data, the same way a real actuary would from real claims history.

## Policy Characteristics

10,000 policies were generated with the following attributes:

| Field | Distribution |
|---|---|
| issue_age | Uniform, ages 20–70 |
| gender | 50/50 M/F (captured in the data, not used to differentiate mortality in this iteration) |
| smoker_status | 80% Nonsmoker / 20% Smoker |
| product_type | 40% Term / 40% Whole Life / 20% Deferred Whole Life |
| face_amount | Uniform across $50,000–$500,000, in $10,000 increments |
| term_years | Term policies only: 10, 15, 20, or 30 years |
| deferral_years | Deferred Whole Life policies only: 2, 5, or 10 years |
| issue_date | Uniform across a 10-year issue window (2015–2025) |

**Design note — "Deferred" product clarification:** the Deferred product in this project specifically means **Deferred Whole Life** — a waiting period during which no coverage is in force, followed by lifetime coverage once the waiting period ends (as opposed to a deferred term product, which was considered but not used). This is reflected in both the data (`product_type = "Deferred Whole Life"`) and the database schema's CHECK constraint.

## The Mortality Model

### Gompertz-Makeham Law

The "true" underlying mortality pattern used to simulate deaths follows the Gompertz-Makeham law of mortality:

$$\mu(x) = A + B \cdot C^{x}$$

Where μ(x) is the force of mortality at age x, A is a constant background mortality component, and B, C control the rate at which mortality accelerates with age.

**Parameters used:** A = 0.00022, B = 0.0000027, C = 1.124 — sourced from course materials, Actuarial Science 3130.

This produces a mortality curve with the following shape:

| Age | qₓ (annual death probability) | Per 1,000 |
|---|---|---|
| 20 | 0.000248 | ~0.25 |
| 30 | 0.000310 | ~0.31 |
| 40 | 0.000510 | ~0.51 |
| 50 | 0.001153 | ~1.15 |
| 60 | 0.003222 | ~3.22 |
| 70 | 0.009881 | ~9.83 |

### Force of Mortality to Annual Probability

μ(x) represents an instantaneous rate; the simulation requires a discrete annual death probability, qₓ. The standard conversion is used:

$$q_x = 1 - e^{-\mu(x)}$$

### Smoker Loading

Smokers' force of mortality is multiplied by **2.5** before the qₓ conversion, reflecting the well-established elevated mortality risk associated with smoking.

### Gender

Mortality in this simulation varies by **age and smoker status only**; gender is captured in the Policy table but does not differentiate mortality in this iteration — noted as a potential future enhancement.

### Parameterization

The mortality function (`calculate_qx`) takes A, B, C, and the smoker multiplier as parameters with defaults, rather than hardcoded constants, so alternative mortality scenarios can be tested directly (used later in Phase 8's sensitivity analysis) without modifying the function itself.

## Simulation Logic

Each policy is simulated independently, year by year, starting at its issue age, using a random draw (`runif(1) < qx`) each year to determine whether death occurs — a weighted "coin flip" where the odds of landing on "death" equal that year's qₓ. This continues until one of three outcomes ends the simulation:

- **Death** — the random draw falls below qₓ for that year.
- **Coverage ends (Term only)** — the policy reaches the end of its term without a death occurring; no further exposure is generated once coverage ends.
- **Limiting age reached (age 105)** — an artificial ceiling ensuring Whole Life and Deferred Whole Life simulations terminate; qₓ approaches near-certainty well before this age is reached in practice.

### Product-Specific Behavior

- **Term:** death risk is simulated every year until either death occurs or the term expires, whichever comes first.
- **Whole Life:** death risk is simulated every year with no term limit; the simulation only stops at death or the age-105 cap.
- **Deferred Whole Life:** during the deferral period, exposure is recorded (flagged `in_deferral = TRUE`), but **no death risk is simulated** — coverage has not yet begun, so no claim is possible during this window, regardless of mortality risk. Once the deferral period ends, the policy behaves identically to Whole Life.

### Exposure Tracking

Every year a policy is simulated — whether it ends in death, survival to term expiry, or continues to the next year — generates one exposure record, since the Phase 4 mortality study requires a complete denominator (total time at risk) alongside the numerator (deaths), not just the death records themselves.

## Simulation Results

- **10,000 policies** simulated.
- **316,390 total exposure-years** generated across all policies.
- **6,512 deaths** recorded within the simulation; **3,488 policies** survived to either term expiry (Term) or the age-105 cap (Whole Life / Deferred Whole Life).

## Limitations & Simplifying Assumptions

- **Mortality parameters are a modeling assumption**, sourced from course materials, not calibrated to a specific published population mortality table or proprietary insurer data.
- **Gender does not differentiate mortality** in this iteration, though it is captured in the data.
- **Full-year exposure only** — exposure_fraction is always 1.0; the simulation does not model mid-year policy transitions (death, lapse) with fractional exposure. This is a noted simplification; fractional exposure is a potential future enhancement.
- **Age-105 limiting age** is an artificial cap for simulation purposes, not derived from a specific mortality table's limiting age.
- **365-day year approximation** — death dates are computed as issue_date + (death_year × 365 days), which does not account for leap years precisely; dates may drift by a few days over long durations. This has no material effect on any age- or year-based analysis in this project.

## Data Loading

Data was loaded into the SQLite database (`sql/pricing_model.db`) via R using `RSQLite`/`DBI`. Date columns (`issue_date`, `death_date`) were explicitly converted to character strings before loading, since `dbWriteTable()` otherwise stores R Date objects as their underlying numeric (days-since-1970) representation, which is not human-readable when queried directly.

**Note on re-running the load script:** `03_load_to_sqlite.R` uses `append = TRUE` when writing to each table. Running it a second time without first clearing existing data will fail on the `policy_id` primary key constraint (by design, as a safeguard against silent duplication). To regenerate the dataset, run `DELETE FROM Policy; DELETE FROM Exposure; DELETE FROM Death;` before re-running the load script.

## Files

- `r/01_generate_policies.R` — generates the 10,000 policies' static characteristics
- `r/02_simulate_deaths_exposure.R` — contains `calculate_qx()` and `simulate_policy()`, and runs the full year-by-year simulation across all 10,000 policies
- `r/03_load_to_sqlite.R` — loads the generated policies, exposure, and death data into `sql/pricing_model.db`