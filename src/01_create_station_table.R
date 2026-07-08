### Script for inserting the station information into the station table 

# Clean the environment

rm(list = ls())

# Load the functions 

source("YourPath/functions.R")

# RETO: Having absolute paths in scripts is mostly never a good idea
# source("C:/Users/paull/Documents/26s198822-project-meteo-1/Work_in_Progress/functions.R")  #my path
# setwd("C:/Users/paull/Documents/26s198822-project-meteo-1")

# Connect to db

con <- connect_db()

# Create the table 

create_stations_table(con)

# Parse the station information from the API

data1 <- data_frame_ENDPOINT1(get_XML(URL))

# Insert the information into the table 

insert_stations(con, data1)

# Check how the table looks 

check_stations(con) # 566 stations and all parameters available 

dbGetQuery(con, "SELECT station_id, name FROM stations LIMIT 10")

# Disconnect from db 

disconnect_db(con)

# In the case you need the delete db

# dbExecute(con, "DROP TABLE stations")
