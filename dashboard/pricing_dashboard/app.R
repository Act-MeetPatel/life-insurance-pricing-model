library(shiny)
library(readxl)
library(dplyr)
library(ggplot2)

mortality_table <- read_excel("../../excel/assumptions.xlsx", sheet = "Mortality")
expenses_table <- read_excel("../../excel/assumptions.xlsx", sheet = "Expenses")
economic_table <- read_excel("../../excel/assumptions.xlsx", sheet = "Economic")
profit_table <- read_excel("../../excel/assumptions.xlsx", sheet = "Profit")

get_pricing_qx <- function(age, smoker, mortality_data = mortality_table) {
  
  age_band <- (age %/% 5) * 5
  
  rate <- mortality_data$pricing_qx[
    mortality_data$age_band_start == age_band & 
      mortality_data$smoker_status == smoker
  ]
  
  return(rate)
}

# Survival probabilities: chains single-year survival, product-aware for deferral
calculate_survival_probs <- function(issue_age, smoker, n_years, product_type = "Term", deferral_years = NA) {
  
  ages <- issue_age:(issue_age + n_years - 1)
  qx_values <- sapply(ages, get_pricing_qx, smoker = smoker)
  
  if (product_type == "Deferred Whole Life") {
    years <- 1:n_years
    qx_values[years <= deferral_years] <- 0
  }
  
  px_values <- 1 - qx_values
  survival_probs <- cumprod(px_values)
  survival_probs <- c(1, survival_probs[-length(survival_probs)])
  
  return(survival_probs)
}

# PV(Claims): expected, discounted death benefit cost
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

# PV(Expenses): one-time issue cost plus discounted, survival-weighted maintenance
calculate_pv_expenses <- function(issue_age, smoker, product_type, interest_rate, 
                                  term_years = NA, deferral_years = NA, limiting_age = 105,
                                  expense_data = expenses_table) {
  
  issue_expense <- expense_data$issue_expense[expense_data$product_type == product_type]
  maintenance_expense <- expense_data$maintenance_expense[expense_data$product_type == product_type]
  
  if (product_type == "Term") {
    n_years <- term_years
  } else {
    n_years <- limiting_age - issue_age
  }
  
  survival_probs <- calculate_survival_probs(issue_age, smoker, n_years, product_type, deferral_years)
  
  years <- 1:n_years
  discount_factors <- 1 / ((1 + interest_rate) ^ years)
  
  pv_maintenance_by_year <- survival_probs * maintenance_expense * discount_factors
  total_pv_maintenance <- sum(pv_maintenance_by_year)
  
  total_pv_expenses <- issue_expense + total_pv_maintenance
  
  return(total_pv_expenses)
}

# Annuity factor: PV of a $1/year premium stream, paid at start of year
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

# Gross premium solve: ties everything together
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

calculate_cashflows <- function(issue_age, smoker, product_type, face_amount, interest_rate, gross_premium,
                                term_years = NA, deferral_years = NA, limiting_age = 105,
                                expense_data = expenses_table) {
  
  if (product_type == "Term") {
    n_years <- term_years
  } else {
    n_years <- limiting_age - issue_age
  }
  
  ages <- issue_age:(issue_age + n_years - 1)
  qx_values <- sapply(ages, get_pricing_qx, smoker = smoker)
  
  if (product_type == "Deferred Whole Life") {
    years_seq <- 1:n_years
    qx_values[years_seq <= deferral_years] <- 0
  }
  
  survival_probs <- calculate_survival_probs(issue_age, smoker, n_years, product_type, deferral_years)
  
  issue_expense <- expense_data$issue_expense[expense_data$product_type == product_type]
  maintenance_expense <- expense_data$maintenance_expense[expense_data$product_type == product_type]
  
  # Premium collected at start of year (survival-weighted, no discounting yet)
  premium_in <- survival_probs * gross_premium
  
  # Expected claim paid at end of year (survival-at-start x death-prob-this-year x face)
  claim_out <- survival_probs * qx_values * face_amount
  
  # Expected maintenance expense at end of year (survival-weighted)
  maintenance_out <- survival_probs * maintenance_expense
  
  # Issue expense only in year 1
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

calculate_pv_profit <- function(cashflow_table, interest_rate) {
  
  premium_discount <- 1 / ((1 + interest_rate) ^ (cashflow_table$policy_year - 1))
  expense_discount <- 1 / ((1 + interest_rate) ^ cashflow_table$policy_year)
  
  pv_premium <- sum(cashflow_table$premium_in * premium_discount)
  pv_claims <- sum(cashflow_table$claim_out * expense_discount)
  pv_maintenance <- sum(cashflow_table$maintenance_out * expense_discount)
  pv_issue <- sum(cashflow_table$issue_out)  # already at time 0, no discounting needed
  
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

ui <- fluidPage(
  titlePanel("Life Insurance Pricing Calculator"),
  
  sidebarLayout(
    sidebarPanel(
      numericInput("issue_age", "Issue Age", value = 40, min = 20, max = 100),
      selectInput("smoker_status", "Smoker Status", choices = c("Nonsmoker", "Smoker")),
      selectInput("product_type", "Product Type", choices = c("Term", "Whole Life", "Deferred Whole Life")),
      numericInput("face_amount", "Face Amount ($)", value = 100000, min = 10000, step = 10000),
      
      conditionalPanel(
        condition = "input.product_type == 'Term'",
        numericInput("term_years", "Term Length (years)", value = 20, min = 1, max = 40)
      ),
      
      conditionalPanel(
        condition = "input.product_type == 'Deferred Whole Life'",
        numericInput("deferral_years", "Deferral Period (years)", value = 5, min = 1, max = 20)
      ),
      
      actionButton("calculate", "Calculate Premium")
    ),
    
    mainPanel(
      h3("Results"),
      verbatimTextOutput("premium_output")
    )
  )
)

server <- function(input, output) {
  
  observeEvent(input$calculate, {
    
    age <- input$issue_age
    smoker <- input$smoker_status
    product <- input$product_type
    face <- input$face_amount
    
    term <- NA
    deferral <- NA
    
    if (product == "Term") {
      term <- input$term_years
    }
    
    if (product == "Deferred Whole Life") {
      deferral <- input$deferral_years
    }
    
    premium_result <- calculate_gross_premium(
      issue_age = age,
      smoker = smoker,
      product_type = product,
      face_amount = face,
      interest_rate = 0.05,
      term_years = term,
      deferral_years = deferral
    )
    
    output$premium_output <- renderText({
      paste0(
        "Issue Age: ", age, "\n",
        "Smoker Status: ", smoker, "\n",
        "Product Type: ", product, "\n",
        "Face Amount: $", face, "\n",
        "Gross Annual Premium: $", round(premium_result$gross_premium, 2)
      )
    })
    
  })
  
}

shinyApp(ui = ui, server = server)

