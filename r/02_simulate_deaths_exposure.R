calculate_qx <- function(age, smoker, A = 0.00022, B = 0.0000027, C = 1.124, smoker_multiplier = 2.5) {

    mu <- A + B * (C ^ age)
  
  if (smoker == "Smoker") {
    mu <- mu * smoker_multiplier
  }
  
  qx <- 1 - exp(-mu)
  
  return(qx)
}

simulate_policy <- function(issue_age, smoker_status, product_type, term_years, deferral_years) {
  
  current_age <- issue_age
  year <- 1
  died <- FALSE
  
  exposure_records <- list()
  death_record <- NULL
  
  while (!died) {
    
    # Check if Term coverage has expired
    if (product_type == "Term" && year > term_years) {
      break
    }
    
    # Check if Whole Life has hit the outer age cap (limiting age)
    if (current_age > 105) {
      break
    }
    
    # Determine if this year is within a Deferred Whole Life waiting period
    in_deferral <- FALSE
    if (product_type == "Deferred Whole Life" && year <= deferral_years) {
      in_deferral <- TRUE
    }
    
    # Record exposure for this year regardless of outcome
    exposure_records[[year]] <- data.frame(
      exposure_year = year,
      attained_age = current_age,
      exposure_fraction = 1.0,
      in_deferral = in_deferral
    )
    
    # Only simulate death risk if NOT in deferral (no claim possible during waiting period)
    if (!in_deferral) {
      qx <- calculate_qx(current_age, smoker_status)
      death_occurs <- runif(1) < qx
      
      if (death_occurs) {
        died <- TRUE
        death_record <- data.frame(
          death_year = year,
          attained_age = current_age
        )
      }
    }
    
    if (!died) {
      current_age <- current_age + 1
      year <- year + 1
    }
  }
  
  # Combine all exposure years into one data frame
  exposure_df <- do.call(rbind, exposure_records)
  
  return(list(exposure = exposure_df, death = death_record))
}

all_exposure <- vector("list", n_policies)
all_death <- vector("list", n_policies)


set.seed(3130)

for (i in 1:n_policies) {
  
  result <- simulate_policy(
    issue_age = policies$issue_age[i],
    smoker_status = policies$smoker_status[i],
    product_type = policies$product_type[i],
    term_years = policies$term_years[i],
    deferral_years = policies$deferral_years[i]
  )
  
  # Tag the exposure rows with which policy they belong to
  exposure_with_id <- result$exposure
  exposure_with_id$policy_id <- policies$policy_id[i]
  all_exposure[[i]] <- exposure_with_id
  
  # Tag the death row (if any) with which policy it belongs to
  if (!is.null(result$death)) {
    death_with_id <- result$death
    death_with_id$policy_id <- policies$policy_id[i]
    all_death[[i]] <- death_with_id
  }
}


exposure_final <- do.call(rbind, all_exposure)
death_final <- do.call(rbind, all_death)

exposure_final$exposure_id <- 1:nrow(exposure_final)
death_final$death_id <- 1:nrow(death_final)

exposure_final <- exposure_final[, c("exposure_id", "policy_id", "exposure_year", "attained_age", "exposure_fraction", "in_deferral")]
death_final <- death_final[, c("death_id", "policy_id", "death_date", "attained_age")]

death_final <- merge(death_final, policies[, c("policy_id", "issue_date")], by = "policy_id")
death_final$death_date <- death_final$issue_date + (death_final$death_year * 365)
