### Script for analysing the anomalies ###

# Clean the environment

rm(list = ls())

# Load the functions 

 source("/Users/mar/Uni/Data_Managment/Project/26s198822-project-meteo-1/Work_in_Progress/functions.R")

# source("C:/Users/paull/Documents/26s198822-project-meteo-1/Work_in_Progress/functions.R")  #my path

# setwd("C:/Users/paull/Documents/26s198822-project-meteo-1")

# Connect to db

con <- connect_db()

# Retrieve data of interest (station imst)

id_Imst <- dbGetQuery(con, "SELECT station_id, name FROM stations WHERE name = 'Imst'")
id_Imst$station_id

z_ref <- get_obs_data(con, id_Imst$station_id, 1990:2019)
z_2025 <- get_obs_data(con, id_Imst$station_id, 2025)

# Checking for NA 

summary(z_ref)                       # no -999
min(z_ref$tl_mittel, na.rm = TRUE)   
sum(is.na(z_ref$tl_mittel))          # 0 NAs

# Aggregating the data

z_aggr <- aggregte_monthly(z_ref, z_2025)
z_aggr

# Calculating the anomalies 

z_anom <- calc_anomalies(z_aggr)

# Plotting the climate and anomalies 

plot_climatology(z_aggr, "ref_tl_mittel")
plot_anomalies(z_anom, z_aggr, "anom_tl_mittel", "tl_mittel")

# Yearly aggregate and gif generation

valid_station_ids <- get_valid_stations_db(con)
station_df <- join_tables_for_stations(con,valid_station_ids)
yearly <- aggregate_yearly(station_df,min_year = 1950)
animation <- plot_stacked_anim(yearly,fps = 2)
print(animation)

dbDisconnect(con)

