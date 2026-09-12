library(dplyr)
set.seed(3130)
n_policies = 10000

issue_age = sample(20:70, n_policies, replace = TRUE)

gender = sample(c("M", "F"), n_policies, replace = TRUE)

smoker_status <- sample(c("Nonsmoker", "Smoker"), n_policies, replace = TRUE, prob = c(0.8, 0.2))

product_type <- sample(c("Term", "Whole Life", "Deferred Whole Life"), n_policies, replace = TRUE, prob = c(0.4, 0.4, 0.2))

face_amount <- sample(seq(50000, 500000, by = 10000), n_policies, replace = TRUE)

term_years <- ifelse(
  product_type == "Term",
  sample(c(10, 15, 20, 30), n_policies, replace = TRUE),
  NA
)

deferral_years <- ifelse(
  product_type == "Deferred Whole Life",
  sample(c(2, 5, 10), n_policies, replace = TRUE),
  NA
)

issue_date <- as.Date("2015-01-01") + sample(0:(365*10), n_policies, replace = TRUE)


policies <- data.frame(
  policy_id = 1:n_policies,
  issue_age = issue_age,
  gender = gender,
  smoker_status = smoker_status,
  product_type = product_type,
  face_amount = face_amount,
  term_years = term_years,
  deferral_years = deferral_years,
  issue_date = issue_date
)
