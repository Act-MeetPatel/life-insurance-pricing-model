library(RSQLite)
library(DBI)

con <- dbConnect(RSQLite::SQLite(), "sql/pricing_model.db")
dbExecute(con, "PRAGMA foreign_keys = ON;")

dbListTables(con)

policies_to_load <- policies
policies_to_load$issue_date <- as.character(policies_to_load$issue_date)

dbWriteTable(con, "Policy", policies_to_load, append = TRUE)

dbWriteTable(con, "Exposure", exposure_final, append = TRUE)

death_final_to_load <- death_final
death_final_to_load$death_date <- as.character(death_final_to_load$death_date)

dbWriteTable(con, "Death", death_final_to_load, append = TRUE)

dbDisconnect(con)
