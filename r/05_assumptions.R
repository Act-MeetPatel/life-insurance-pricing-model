library(RSQLite)
library(DBI)
library(dplyr)

con <- dbConnect(RSQLite::SQLite(), "sql/pricing_model.db")
dbExecute(con, "PRAGMA foreign_keys = ON;")

mortality_query <- "
SELECT 
    (Exposure.attained_age / 5) * 5 AS age_band_start,
    Policy.smoker_status,
    SUM(Exposure.exposure_fraction) AS total_exposure
FROM Exposure
JOIN Policy ON Exposure.policy_id = Policy.policy_id
WHERE Exposure.in_deferral = 0
GROUP BY age_band_start, Policy.smoker_status
ORDER BY age_band_start, Policy.smoker_status;
"

death_query <- "
SELECT 
    (Death.attained_age / 5) * 5 AS age_band_start,
    Policy.smoker_status,
    COUNT(*) AS total_deaths
FROM Death
JOIN Policy ON Death.policy_id = Policy.policy_id
GROUP BY age_band_start, Policy.smoker_status
ORDER BY age_band_start, Policy.smoker_status;
"

exposure_by_band <- dbGetQuery(con, mortality_query)
deaths_by_band <- dbGetQuery(con, death_query)

mortality_experience <- merge(exposure_by_band, deaths_by_band, by = c("age_band_start", "smoker_status"), all.x = TRUE)
mortality_experience$total_deaths[is.na(mortality_experience$total_deaths)] <- 0
mortality_experience$observed_qx <- mortality_experience$total_deaths / mortality_experience$total_exposure


mortality_experience$margin <- ifelse(
  mortality_experience$age_band_start >= 40 & mortality_experience$age_band_start <= 94,
  1.10,
  1.25
)

mortality_experience$pricing_qx <- mortality_experience$observed_qx * mortality_experience$margin
mortality_experience$pricing_qx <- pmin(mortality_experience$pricing_qx, 1.0)


expenses <- data.frame(
  product_type = c("Term", "Whole Life", "Deferred Whole Life"),
  issue_expense = c(50, 75, 85),
  maintenance_expense = c(10, 15, 15)
)

profit_margin <- data.frame(
  product_type = c("Term", "Whole Life", "Deferred Whole Life"),
  target_profit_margin = c(0.08, 0.15, 0.12)
)

economic <- data.frame(
  assumption = "interest_rate",
  value = 0.05
)

library(writexl)

assumptions_workbook <- list(
  "Mortality" = mortality_experience,
  "Expenses" = expenses,
  "Economic" = economic,
  "Profit" = profit_margin
)

write_xlsx(assumptions_workbook, "excel/assumptions.xlsx")
