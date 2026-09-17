library(readxl)
library(dplyr)
library(ggplot2)

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

calculate_survival_probs <- function(issue_age, smoker, n_years, product_type = "Term", deferral_years = NA, mortality_data = mortality_table) {
  
  ages <- issue_age:(issue_age + n_years - 1)
  qx_values <- sapply(ages, get_pricing_qx, smoker = smoker, mortality_data = mortality_data)
  
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
                                term_years = NA, deferral_years = NA, limiting_age = 105,
                                mortality_data = mortality_table) {
  
  if (product_type == "Term") {
    n_years <- term_years
  } else {
    n_years <- limiting_age - issue_age
  }
  
  ages <- issue_age:(issue_age + n_years - 1)
  qx_values <- sapply(ages, get_pricing_qx, smoker = smoker, mortality_data = mortality_data)
  
  if (product_type == "Deferred Whole Life") {
    years <- 1:n_years
    qx_values[years <= deferral_years] <- 0
  }
  
  survival_probs <- calculate_survival_probs(issue_age, smoker, n_years, product_type, deferral_years, mortality_data = mortality_data)
  
  death_probs <- survival_probs * qx_values
  
  years <- 1:n_years
  discount_factors <- 1 / ((1 + interest_rate) ^ years)
  
  pv_claims_by_year <- death_probs * face_amount * discount_factors
  
  total_pv_claims <- sum(pv_claims_by_year)
  
  return(total_pv_claims)
}

calculate_pv_expenses <- function(issue_age, smoker, product_type, interest_rate, 
                                  term_years = NA, deferral_years = NA, limiting_age = 105,
                                  expense_data = expenses_table, mortality_data = mortality_table) {
  
  issue_expense <- expense_data$issue_expense[expense_data$product_type == product_type]
  maintenance_expense <- expense_data$maintenance_expense[expense_data$product_type == product_type]
  
  if (product_type == "Term") {
    n_years <- term_years
  } else {
    n_years <- limiting_age - issue_age
  }
  
  survival_probs <- calculate_survival_probs(issue_age, smoker, n_years, product_type, deferral_years, mortality_data = mortality_data)
  
  years <- 1:n_years
  discount_factors <- 1 / ((1 + interest_rate) ^ years)
  
  pv_maintenance_by_year <- survival_probs * maintenance_expense * discount_factors
  total_pv_maintenance <- sum(pv_maintenance_by_year)
  
  total_pv_expenses <- issue_expense + total_pv_maintenance
  
  return(total_pv_expenses)
}

calculate_annuity_factor <- function(issue_age, smoker, product_type, interest_rate,
                                     term_years = NA, deferral_years = NA, limiting_age = 105,
                                     mortality_data = mortality_table) {
  
  if (product_type == "Term") {
    n_years <- term_years
  } else {
    n_years <- limiting_age - issue_age
  }
  
  survival_probs <- calculate_survival_probs(issue_age, smoker, n_years, product_type, deferral_years, mortality_data = mortality_data)
  
  years <- 1:n_years
  discount_factors <- 1 / ((1 + interest_rate) ^ (years - 1))
  
  annuity_factor <- sum(survival_probs * discount_factors)
  
  return(annuity_factor)
}

calculate_gross_premium <- function(issue_age, smoker, product_type, face_amount, interest_rate,
                                    term_years = NA, deferral_years = NA, limiting_age = 105,
                                    expense_data = expenses_table, profit_data = profit_table,
                                    mortality_data = mortality_table) {
  
  pv_claims <- calculate_pv_claims(issue_age, smoker, product_type, face_amount, interest_rate,
                                   term_years, deferral_years, limiting_age, mortality_data = mortality_data)
  
  pv_expenses <- calculate_pv_expenses(issue_age, smoker, product_type, interest_rate,
                                       term_years, deferral_years, limiting_age, expense_data, mortality_data = mortality_data)
  
  annuity_factor <- calculate_annuity_factor(issue_age, smoker, product_type, interest_rate,
                                             term_years, deferral_years, limiting_age, mortality_data = mortality_data)
  
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

calculate_cashflows <- function(issue_age, smoker, product_type, face_amount, interest_rate, gross_premium,
                                term_years = NA, deferral_years = NA, limiting_age = 105,
                                expense_data = expenses_table, mortality_data = mortality_table) {
  
  if (product_type == "Term") {
    n_years <- term_years
  } else {
    n_years <- limiting_age - issue_age
  }
  
  ages <- issue_age:(issue_age + n_years - 1)
  qx_values <- sapply(ages, get_pricing_qx, smoker = smoker, mortality_data = mortality_data)
  
  if (product_type == "Deferred Whole Life") {
    years_seq <- 1:n_years
    qx_values[years_seq <= deferral_years] <- 0
  }
  
  survival_probs <- calculate_survival_probs(issue_age, smoker, n_years, product_type, deferral_years, mortality_data = mortality_data)
  
  issue_expense <- expense_data$issue_expense[expense_data$product_type == product_type]
  maintenance_expense <- expense_data$maintenance_expense[expense_data$product_type == product_type]
  
  premium_in <- survival_probs * gross_premium
  claim_out <- survival_probs * qx_values * face_amount
  maintenance_out <- survival_probs * maintenance_expense
  issue_out <- c(issue_expense, rep(0, n_years - 1))
  
  net_cashflow <- premium_in - claim_out - maintenance_out - issue_out
  
  cashflow_table <- data.frame(
    policy_year = 1:n_years,
    attained_age = ages,
    survival_prob = survival_probs,
    premium_in = premium_in,
    claim_out = claim_out,
    maintenance_out = maintenance_out,
    issue_out = issue_out,
    net_cashflow = net_cashflow
  )
  
  return(cashflow_table)
}

test_profitability <- function(issue_age, smoker, product_type, face_amount, interest_rate, gross_premium,
                               term_years = NA, deferral_years = NA,
                               mortality_data = mortality_table, expense_data = expenses_table) {
  
  cf <- calculate_cashflows(
    issue_age, smoker, product_type, face_amount, interest_rate, 
    gross_premium = gross_premium,
    term_years, deferral_years, limiting_age = 105,
    expense_data = expense_data,
    mortality_data = mortality_data
  )
  
  margin <- calculate_profit_margin(cf, interest_rate)
  
  return(margin)
}

calculate_pv_profit <- function(cashflow_table, interest_rate) {
  
  premium_discount <- 1 / ((1 + interest_rate) ^ (cashflow_table$policy_year - 1))
  expense_discount <- 1 / ((1 + interest_rate) ^ cashflow_table$policy_year)
  
  pv_premium <- sum(cashflow_table$premium_in * premium_discount)
  pv_claims <- sum(cashflow_table$claim_out * expense_discount)
  pv_maintenance <- sum(cashflow_table$maintenance_out * expense_discount)
  pv_issue <- sum(cashflow_table$issue_out)
  
  pv_profit <- pv_premium - pv_claims - pv_maintenance - pv_issue
  
  return(pv_profit)
}

calculate_profit_margin <- function(cashflow_table, interest_rate) {
  
  premium_discount <- 1 / ((1 + interest_rate) ^ (cashflow_table$policy_year - 1))
  pv_premiums <- sum(cashflow_table$premium_in * premium_discount)
  
  pv_profit <- calculate_pv_profit(cashflow_table, interest_rate)
  
  margin <- pv_profit / pv_premiums
  
  return(margin)
}

sensitivity_cases <- data.frame(
  product_type = c("Term", "Whole Life", "Deferred Whole Life"),
  issue_age = c(35, 55, 45),
  smoker_status = c("Nonsmoker", "Nonsmoker", "Nonsmoker"),
  term_years = c(20, NA, NA),
  deferral_years = c(NA, NA, 5),
  face_amount = c(100000, 100000, 100000)
)

mortality_stressed_up <- mortality_table
mortality_stressed_up$pricing_qx <- pmin(mortality_stressed_up$pricing_qx * 1.10, 1.0)

mortality_stressed_down <- mortality_table
mortality_stressed_down$pricing_qx <- mortality_stressed_down$pricing_qx * 0.90

mortality_sensitivity <- data.frame()

for (i in 1:nrow(sensitivity_cases)) {
  
  base_premium <- calculate_gross_premium(
    sensitivity_cases$issue_age[i], sensitivity_cases$smoker_status[i], 
    sensitivity_cases$product_type[i], sensitivity_cases$face_amount[i], 0.05,
    sensitivity_cases$term_years[i], sensitivity_cases$deferral_years[i]
  )$gross_premium
  
  base_margin <- test_profitability(
    sensitivity_cases$issue_age[i], sensitivity_cases$smoker_status[i], 
    sensitivity_cases$product_type[i], sensitivity_cases$face_amount[i], 0.05,
    gross_premium = base_premium,
    sensitivity_cases$term_years[i], sensitivity_cases$deferral_years[i]
  )
  
  margin_mort_up <- test_profitability(
    sensitivity_cases$issue_age[i], sensitivity_cases$smoker_status[i], 
    sensitivity_cases$product_type[i], sensitivity_cases$face_amount[i], 0.05,
    gross_premium = base_premium,
    sensitivity_cases$term_years[i], sensitivity_cases$deferral_years[i],
    mortality_data = mortality_stressed_up
  )
  
  margin_mort_down <- test_profitability(
    sensitivity_cases$issue_age[i], sensitivity_cases$smoker_status[i], 
    sensitivity_cases$product_type[i], sensitivity_cases$face_amount[i], 0.05,
    gross_premium = base_premium,
    sensitivity_cases$term_years[i], sensitivity_cases$deferral_years[i],
    mortality_data = mortality_stressed_down
  )
  
  mortality_sensitivity <- rbind(mortality_sensitivity, data.frame(
    product_type = sensitivity_cases$product_type[i],
    base_premium = base_premium,
    base_margin = base_margin,
    margin_mortality_up10 = margin_mort_up,
    margin_mortality_down10 = margin_mort_down
  ))
}

interest_sensitivity <- data.frame()

for (i in 1:nrow(sensitivity_cases)) {
  
  base_premium <- calculate_gross_premium(
    sensitivity_cases$issue_age[i], sensitivity_cases$smoker_status[i], 
    sensitivity_cases$product_type[i], sensitivity_cases$face_amount[i], 0.05,
    sensitivity_cases$term_years[i], sensitivity_cases$deferral_years[i]
  )$gross_premium
  
  margin_rate_up <- test_profitability(
    sensitivity_cases$issue_age[i], sensitivity_cases$smoker_status[i], 
    sensitivity_cases$product_type[i], sensitivity_cases$face_amount[i], 0.06,
    gross_premium = base_premium,
    sensitivity_cases$term_years[i], sensitivity_cases$deferral_years[i]
  )
  
  margin_rate_down <- test_profitability(
    sensitivity_cases$issue_age[i], sensitivity_cases$smoker_status[i], 
    sensitivity_cases$product_type[i], sensitivity_cases$face_amount[i], 0.04,
    gross_premium = base_premium,
    sensitivity_cases$term_years[i], sensitivity_cases$deferral_years[i]
  )
  
  interest_sensitivity <- rbind(interest_sensitivity, data.frame(
    product_type = sensitivity_cases$product_type[i],
    base_premium = base_premium,
    margin_rate_up1pp = margin_rate_up,
    margin_rate_down1pp = margin_rate_down
  ))
}

expenses_stressed_up <- expenses_table
expenses_stressed_up$issue_expense <- expenses_stressed_up$issue_expense * 1.10
expenses_stressed_up$maintenance_expense <- expenses_stressed_up$maintenance_expense * 1.10

expenses_stressed_down <- expenses_table
expenses_stressed_down$issue_expense <- expenses_stressed_down$issue_expense * 0.90
expenses_stressed_down$maintenance_expense <- expenses_stressed_down$maintenance_expense * 0.90

expense_sensitivity <- data.frame()

for (i in 1:nrow(sensitivity_cases)) {
  
  base_premium <- calculate_gross_premium(
    sensitivity_cases$issue_age[i], sensitivity_cases$smoker_status[i], 
    sensitivity_cases$product_type[i], sensitivity_cases$face_amount[i], 0.05,
    sensitivity_cases$term_years[i], sensitivity_cases$deferral_years[i]
  )$gross_premium
  
  margin_exp_up <- test_profitability(
    sensitivity_cases$issue_age[i], sensitivity_cases$smoker_status[i], 
    sensitivity_cases$product_type[i], sensitivity_cases$face_amount[i], 0.05,
    gross_premium = base_premium,
    sensitivity_cases$term_years[i], sensitivity_cases$deferral_years[i],
    expense_data = expenses_stressed_up
  )
  
  margin_exp_down <- test_profitability(
    sensitivity_cases$issue_age[i], sensitivity_cases$smoker_status[i], 
    sensitivity_cases$product_type[i], sensitivity_cases$face_amount[i], 0.05,
    gross_premium = base_premium,
    sensitivity_cases$term_years[i], sensitivity_cases$deferral_years[i],
    expense_data = expenses_stressed_down
  )
  
  expense_sensitivity <- rbind(expense_sensitivity, data.frame(
    product_type = sensitivity_cases$product_type[i],
    base_premium = base_premium,
    margin_expenses_up10 = margin_exp_up,
    margin_expenses_down10 = margin_exp_down
  ))
}


tornado_data <- data.frame()

for (i in 1:nrow(sensitivity_cases)) {
  
  product <- sensitivity_cases$product_type[i]
  base_margin_val <- mortality_sensitivity$base_margin[mortality_sensitivity$product_type == product]
  
  mort_low <- min(mortality_sensitivity$margin_mortality_up10[i], mortality_sensitivity$margin_mortality_down10[i])
  mort_high <- max(mortality_sensitivity$margin_mortality_up10[i], mortality_sensitivity$margin_mortality_down10[i])
  
  rate_low <- min(interest_sensitivity$margin_rate_up1pp[i], interest_sensitivity$margin_rate_down1pp[i])
  rate_high <- max(interest_sensitivity$margin_rate_up1pp[i], interest_sensitivity$margin_rate_down1pp[i])
  
  exp_low <- min(expense_sensitivity$margin_expenses_up10[i], expense_sensitivity$margin_expenses_down10[i])
  exp_high <- max(expense_sensitivity$margin_expenses_up10[i], expense_sensitivity$margin_expenses_down10[i])
  
  tornado_data <- rbind(tornado_data, data.frame(
    product_type = rep(product, 3),
    assumption = c("Mortality (±10%)", "Interest Rate (±1pp)", "Expenses (±10%)"),
    margin_low = c(mort_low, rate_low, exp_low),
    margin_high = c(mort_high, rate_high, exp_high),
    base_margin = base_margin_val
  ))
}

tornado_data$swing <- tornado_data$margin_high - tornado_data$margin_low

plot_tornado <- function(product_name) {
  
  data_subset <- tornado_data[tornado_data$product_type == product_name, ]
  
  # Order assumptions by swing size, so the chart shows biggest impact at top
  data_subset$assumption <- factor(data_subset$assumption, levels = data_subset$assumption[order(data_subset$swing)])
  
  ggplot(data_subset, aes(y = assumption)) +
    geom_segment(aes(x = margin_low, xend = margin_high, yend = assumption), linewidth = 8, color = "steelblue") +
    geom_vline(xintercept = data_subset$base_margin[1], linetype = "dashed", color = "red") +
    labs(
      title = paste("Sensitivity of Profit Margin —", product_name),
      subtitle = "Dashed line = base case target margin",
      x = "Achieved Profit Margin",
      y = NULL
    ) +
    theme_minimal()
}

plot_tornado("Term")
plot_tornado("Whole Life")
plot_tornado("Deferred Whole Life")
