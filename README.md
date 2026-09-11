---
output:
  html_document: default
  pdf_document: default
---
# Experience-Based Life Insurance Pricing & Profit Testing Model

*A recruiter-facing actuarial portfolio project built in SQL, R, and Excel, covering mortality experience analysis, assumption development, pricing, profit testing, sensitivity analysis, and an interactive Shiny dashboard.*

> **Note:** This README will grow as each project phase is completed. This section — Phase 1 — covers the pricing fundamentals underlying everything that follows.

---

## 1. Business Problem

Life insurers must set a premium today for a promise that may not be fulfilled for decades. Getting that premium wrong in either direction is costly: too low, and the insurer loses money on the policy; too high, and the product isn't competitive. Actuarial pricing exists to solve this problem systematically — using mortality, expense, and economic assumptions to set a premium that, across a large pool of similar policies, covers expected costs and delivers a target profit margin.

This project builds an experience-based pricing model end-to-end: generating realistic policy data, deriving mortality assumptions from experience (rather than simply adopting a published table), pricing a term life product, and testing its profitability under both expected and stressed conditions.

## 2. The Core Pricing Equation

$$PV(\text{Premiums}) = PV(\text{Claims}) + PV(\text{Expenses}) + PV(\text{Target Profit})$$

Every term is a **present value**: a future cash flow, weighted by the probability it occurs, discounted back to today at the assumed interest rate.

- **PV(Premiums)** — expected premium income from the policyholder over the life of the policy.
- **PV(Claims)** — expected death benefit payments, weighted by mortality probability in each future year.
- **PV(Expenses)** — the cost of acquiring and administering the policy (commissions, underwriting, maintenance).
- **PV(Target Profit)** — the margin the insurer requires beyond simply breaking even.

Solving this equation for the premium — while holding claims, expenses, and profit fixed — is the foundation of every pricing calculation in this project.

### Net Premium vs. Gross Premium

- **Net premium**: solves `PV(Premiums) = PV(Claims)` alone (the equivalence principle). Represents the pure cost of mortality risk, with no loading.
- **Gross premium**: solves the full equation above, including expenses and profit. This is the premium actually charged to a policyholder.

The difference between the two is the **loading** — and isolating it is a useful diagnostic throughout the project, even though only the gross premium is ever charged.

## 3. Mortality Notation

This project uses standard actuarial notation throughout:

| Symbol | Meaning |
|---|---|
| qₓ | Probability a person aged x dies within one year |
| pₓ | 1 − qₓ; probability a person aged x survives one year |
| ₙpₓ | Probability a person aged x survives n years (= pₓ × pₓ₊₁ × ... × pₓ₊ₙ₋₁) |
| ₙqₓ | Probability a person aged x dies within n years (= 1 − ₙpₓ) |
| ₙ\|qₓ | Probability of surviving n years, then dying in the following year |
| äₓ:ₙ| | Annuity-due factor: present value of a level $1 payment stream over n years, weighted by survival |

## 4. Worked Example: 1-Year Term Policy

To make the pricing equation concrete before any code is written:

**Assumptions:** Face amount $100,000; qₓ = 0.002; interest rate 5%; expenses $50 (at issue); target profit $20.

| Step | Calculation | Result |
|---|---|---|
| Expected claim | 0.002 × $100,000 | $200 |
| PV(Claims) | $200 / 1.05 | $190.48 |
| PV(Expenses) | (incurred at time 0) | $50.00 |
| PV(Target Profit) | (assumed at time 0) | $20.00 |
| **Gross premium** | $190.48 + $50 + $20 | **$260.48** |

For comparison, the **net premium** (claims only) is $190.48 — the gap of $70.48 is entirely expense and profit loading.

A useful sensitivity note: increasing qₓ by just 0.001 (to 0.003) raises the gross premium to $355.71 — a 36% increase from a mortality assumption moving by one part in a thousand. This sensitivity is explored properly in the Sensitivity Analysis phase of this project.

## 5. Worked Example: 2-Year Term Policy

Extending to two years introduces **survival-weighted** cash flows — the mechanical core of the pricing engine built later in this project.

**Assumptions:** Face amount $100,000; qₓ = 0.002 (year 1), qₓ₊₁ = 0.0025 (year 2); interest rate 5%; issue expense $50, year-2 maintenance expense $10; level annual premium P.

**PV of Claims:**
- Year 1: 0.002 × $100,000 / 1.05 = $190.48
- Year 2: (pₓ × qₓ₊₁) × $100,000 / (1.05)² = (0.998 × 0.0025 × $100,000) / 1.1025 = $226.30
- **Total PV(Claims) = $416.78**

**PV of Expenses:**
- Year 1: $50 (time 0, no discounting)
- Year 2: (0.998 × $10) / 1.05 = $9.50
- **Total PV(Expenses) = $59.50**

**PV of Premiums:**
- P is collected at the start of year 1 (certain) and year 2 (weighted by pₓ = 0.998):
- PV(Premiums) = P × [1 + (0.998 / 1.05)] = P × 1.9505

The factor **1.9505** is an annuity factor — the present value of a $1-per-year payment stream, weighted by survival and discounting. This generalizes to äₓ:ₙ| for any term length.

**Solving for P** (with $20 target profit):

P × 1.9505 = $416.78 + $59.50 + $20 = $496.28
**P = $254.44**

The key mechanical insight: every cash flow beyond year 1 must be weighted by the probability the policy is still in force (survival), *before* being discounted for time value. This same logic — extended to a full mortality table and vectorized — becomes the pricing engine in a later phase of this project.

## 6. Project Roadmap

| Phase | Focus |
|---|---|
| 1 | Pricing fundamentals *(this section)* |
| 2 | SQLite database design (Policy, Death, Exposure tables) |
| 3 | Synthetic experience data generation (10,000 policies) |
| 4 | Mortality experience study (Deaths ÷ Exposure by segment) |
| 5 | Assumption development (mortality, expenses, economics, profit) |
| 6 | Pricing engine (R) |
| 7 | Profit testing (cash flow projection, PV of profits) |
| 8 | Sensitivity analysis (tornado charts, stress testing) |
| 9 | Shiny dashboard |

*Further sections will be appended here as each phase is completed.*
