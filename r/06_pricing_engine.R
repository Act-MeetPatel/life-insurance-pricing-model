library(readxl)
library(dplyr)

mortality_table <- read_excel("excel/assumptions.xlsx", sheet = "Mortality")
expenses_table <- read_excel("excel/assumptions.xlsx", sheet = "Expenses")
economic_table <- read_excel("excel/assumptions.xlsx", sheet = "Economic")
profit_table <- read_excel("excel/assumptions.xlsx", sheet = "Profit")

get_pricing_qx <- function(age, smoker, mortality_data = mortality_table) {
  
  age_band <- (age %/% 5) * 5
  
  rate <- mortality_data$pricing_qx[
    mortality_data$age_band_start == age_band & 
      mortality_data$smoker_status == smoker
  ]
  
  return(rate)
}

calculate_survival_probs <- function(issue_age, smoker, n_years, product_type = "Term", deferral_years = NA) {
  
  ages <- issue_age:(issue_age + n_years - 1)
  qx_values <- sapply(ages, get_pricing_qx, smoker = smoker)
  
  # Deferred Whole Life: zero out claim risk during the deferral period
  if (product_type == "Deferred Whole Life") {
    years <- 1:n_years
    qx_values[years <= deferral_years] <- 0
  }
  
  px_values <- 1 - qx_values
  survival_probs <- cumprod(px_values)
  survival_probs <- c(1, survival_probs[-length(survival_probs)])
  
  return(survival_probs)
}

calculate_pv_claims <- function(issue_age, smoker, product_type, face_amount, interest_rate, 
                                term_years = NA, deferral_years = NA, limiting_age = 105) {
  
  if (product_type == "Term") {
    n_years <- term_years
  } else {
    n_years <- limiting_age - issue_age
  }
  
  ages <- issue_age:(issue_age + n_years - 1)
  qx_values <- sapply(ages, get_pricing_qx, smoker = smoker)
  
  if (product_type == "Deferred Whole Life") {
    years <- 1:n_years
    qx_values[years <= deferral_years] <- 0
  }
  
  survival_probs <- calculate_survival_probs(issue_age, smoker, n_years, product_type, deferral_years)
  
  death_probs <- survival_probs * qx_values
  
  years <- 1:n_years
  discount_factors <- 1 / ((1 + interest_rate) ^ years)
  
  pv_claims_by_year <- death_probs * face_amount * discount_factors
  
  total_pv_claims <- sum(pv_claims_by_year)
  
  return(total_pv_claims)
}

calculate_pv_expenses <- function(issue_age, smoker, product_type, interest_rate, 
                                  term_years = NA, deferral_years = NA, limiting_age = 105,
                                  expense_data = expenses_table) {
  
  # Look up this product's expense assumptions
  issue_expense <- expense_data$issue_expense[expense_data$product_type == product_type]
  maintenance_expense <- expense_data$maintenance_expense[expense_data$product_type == product_type]
  
  # Determine projection length, same logic as PV(Claims)
  if (product_type == "Term") {
    n_years <- term_years
  } else {
    n_years <- limiting_age - issue_age
  }
  
  survival_probs <- calculate_survival_probs(issue_age, smoker, n_years, product_type, deferral_years)
  
  years <- 1:n_years
  discount_factors <- 1 / ((1 + interest_rate) ^ years)
  
  # Maintenance expense is incurred every year the policy is in force, weighted by survival, discounted
  pv_maintenance_by_year <- survival_probs * maintenance_expense * discount_factors
  total_pv_maintenance <- sum(pv_maintenance_by_year)
  
  # Issue expense: paid once, at time 0, no discounting or survival weighting
  total_pv_expenses <- issue_expense + total_pv_maintenance
  
  return(total_pv_expenses)
}

calculate_annuity_factor <- function(issue_age, smoker, product_type, interest_rate,
                                     term_years = NA, deferral_years = NA, limiting_age = 105) {
  
  if (product_type == "Term") {
    n_years <- term_years
  } else {
    n_years <- limiting_age - issue_age
  }
  
  survival_probs <- calculate_survival_probs(issue_age, smoker, n_years, product_type, deferral_years)
  
  years <- 1:n_years
  discount_factors <- 1 / ((1 + interest_rate) ^ (years - 1))
  
  annuity_factor <- sum(survival_probs * discount_factors)
  
  return(annuity_factor)
}

calculate_gross_premium <- function(issue_age, smoker, product_type, face_amount, interest_rate,
                                    term_years = NA, deferral_years = NA, limiting_age = 105,
                                    expense_data = expenses_table, profit_data = profit_table) {
  
  pv_claims <- calculate_pv_claims(issue_age, smoker, product_type, face_amount, interest_rate,
                                   term_years, deferral_years, limiting_age)
  
  pv_expenses <- calculate_pv_expenses(issue_age, smoker, product_type, interest_rate,
                                       term_years, deferral_years, limiting_age, expense_data)
  
  annuity_factor <- calculate_annuity_factor(issue_age, smoker, product_type, interest_rate,
                                             term_years, deferral_years, limiting_age)
  
  margin <- profit_data$target_profit_margin[profit_data$product_type == product_type]
  
  pv_premiums <- (pv_claims + pv_expenses) / (1 - margin)
  
  gross_premium <- pv_premiums / annuity_factor
  
  return(list(
    pv_claims = pv_claims,
    pv_expenses = pv_expenses,
    annuity_factor = annuity_factor,
    pv_premiums = pv_premiums,
    gross_premium = gross_premium
  ))
}
