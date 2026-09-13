library(RSQLite)
library(DBI)
library(dplyr)
library(ggplot2)

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

exposure_by_band <- dbGetQuery(con, mortality_query)

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

deaths_by_band <- dbGetQuery(con, death_query)


mortality_experience <- merge(
  exposure_by_band, 
  deaths_by_band, 
  by = c("age_band_start", "smoker_status"), 
  all.x = TRUE
)

mortality_experience$total_deaths[is.na(mortality_experience$total_deaths)] <- 0
mortality_experience$observed_qx <- mortality_experience$total_deaths / mortality_experience$total_exposure


calculate_qx <- function(age, smoker, A = 0.00022, B = 0.0000027, C = 1.124, smoker_multiplier = 2.5) {
  mu <- A + B * (C ^ age)
  
  if (smoker == "Smoker") {
    mu <- mu * smoker_multiplier
  }
  
  qx <- 1 - exp(-mu)
  
  return(qx)
}

mortality_experience$band_midpoint <- mortality_experience$age_band_start + 2

mortality_experience$true_qx <- mapply(
  calculate_qx, 
  mortality_experience$band_midpoint, 
  mortality_experience$smoker_status
)

observed_data <- data.frame(
  age_band_start = mortality_experience$age_band_start,
  smoker_status = mortality_experience$smoker_status,
  qx = mortality_experience$observed_qx,
  source = "Observed"
)

true_data <- data.frame(
  age_band_start = mortality_experience$age_band_start,
  smoker_status = mortality_experience$smoker_status,
  qx = mortality_experience$true_qx,
  source = "True"
)

plot_data <- rbind(observed_data, true_data)

ggplot(plot_data, aes(x = age_band_start, y = qx, color = source, linetype = smoker_status)) +
  geom_line(linewidth = 1) +
  geom_point(size = 1.5) +
  labs(
    title = "Observed vs. True Mortality Rates by Age and Smoker Status",
    x = "Age Band (start)",
    y = "Annual Mortality Rate (qx)",
    color = "Source",
    linetype = "Smoker Status"
  ) +
  theme_minimal()
