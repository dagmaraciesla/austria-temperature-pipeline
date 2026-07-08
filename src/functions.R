

## Function to get the xml data
require(xml2)
# RETO: Using URL as default arg to this function
get_XML <- function(URL = "https://meteoapi.discdown.org/api/station-search?format=xml") {
  data <- read_xml(URL)
  return(data)
}


## function to parse the data and get a df from Endpoint 1 (station information)
data_frame_ENDPOINT1 <- function(data) {
  ## I assume that every station needs an id, so i think that all the station do have one so no NAs
  station   <- (xml_find_all(data,"//stations/station"))
  # Use relative paths here and xml find first to handle silent NAs
  id        <- xml_text(xml_find_first(station,".//@id"))
  date_from <- xml_text(xml_find_first(station,".//@data_from"))
  date_to   <- xml_text(xml_find_first(station,".//@data_to"))
  ## Extract if the station has the correct parameters available
  tlmax     <- !is.na(xml_text(xml_find_first(station,".//parameters/parameter[@name='tlmax']")))
  tlmin     <- !is.na(xml_text(xml_find_first(station,".//parameters/parameter[@name='tlmin']")))
  tl_mittel <- !is.na(xml_text(xml_find_first(station,".//parameters/parameter[@name='tl_mittel']")))
  ## Get additinal info
  longitude <- xml_text(xml_find_first(station,".//longitude"))
  latitude  <- xml_text(xml_find_first(station,".//latitude"))
  altitude  <- xml_text(xml_find_first(station,".//altitude"))
  state     <- xml_text(xml_find_first(station,".//state"))
  name      <- xml_text(xml_find_first(station,".//name"))
  ## get the other parameters
  ffx       <- !is.na(xml_text(xml_find_first(station,".//parameters/parameter[@name='ffx']")))
  p_mittel  <- !is.na(xml_text(xml_find_first(station,".//parameters/parameter[@name='p_mittel']")))
  rf_mittel <- !is.na(xml_text(xml_find_first(station,".//parameters/parameter[@name='rf_mittel']")))
  rr        <- !is.na(xml_text(xml_find_first(station,".//parameters/parameter[@name='rr']")))
  sh        <- !is.na(xml_text(xml_find_first(station,".//parameters/parameter[@name='sh']")))
  shneu_manu<- !is.na(xml_text(xml_find_first(station,".//parameters/parameter[@name='shneu_manu']")))
  so_h      <- !is.na(xml_text(xml_find_first(station,".//parameters/parameter[@name='so_h']")))
  tsmin     <- !is.na(xml_text(xml_find_first(station,".//parameters/parameter[@name='tsmin']")))
  vv_mittel <- !is.na(xml_text(xml_find_first(station,".//parameters/parameter[@name='vv_mittel']")))
  
  ## create the df
  df <- as.data.frame(list(
             "id"        = id,
             "name"      = name,     
             "state"     = state,
             "date_from" = date_from, 
             "date_to"   = date_to, 
             "tlmin"     = tlmin, 
             "tlmax"     = tlmax, 
             "tl_mittel" = tl_mittel,
             "ffx"       = ffx, 
             "p_mittel"  = p_mittel, 
             "rf_mittel" = rf_mittel, 
             "rr"        = rr, 
             "sh"        = sh, 
             "shneu_manu"= shneu_manu, 
             "so_h"      = so_h, 
             "tsmin"     = tsmin, 
             "vv_mittel" = vv_mittel, 
             "longitude" = longitude,
             "latitude"  = latitude,
             "altitude"  = altitude))
  
  return(df)
}



## function to get the desired information from endpoint 2 of one station
require(jsonlite)
pager <- function(data) {
  ## Our observations are delivered as a JSON file, we need to convert first
  df             <- as.data.frame(fromJSON(xml_text(xml_find_all(data,"//observations"))))
  df$id          <- xml_text(xml_find_first(data,"//station/@id"))
  df$stationname <- xml_text(xml_find_first(data,"//station/name"))
  df$state       <- xml_text(xml_find_first(data,"//station/state"))
  df$longitude   <- xml_text(xml_find_first(data,"//station/longitude"))
  df$latitude    <- xml_text(xml_find_first(data,"//station/latitude"))
  df$altitude    <- xml_text(xml_find_first(data,"//station/altitude"))
  
  return(df)
}


## function to only get the valid enpoint 2 data
valid_stations <- function(data,start = "1990-01-01",end = "2019-12-31") {
  ## first convert the dates to Date
  data$date_to   <- as.Date(data$date_to)
  data$date_from <- as.Date(data$date_from)
  ## Now we can compare and filter with the time as well as if the stations provide the info we need
  valid_stations <- data[data$date_from <= as.Date(start) & data$date_to >= as.Date(end),]
  valid_stations <- valid_stations[valid_stations$tlmin == TRUE & valid_stations$tlmax == TRUE & valid_stations$tl_mittel == TRUE,]
  
  return(valid_stations)
}


## function to get IDs for the pager URL
ID_Extractor <- function(data) {
  ## We need to get rid of the first zeros for the URL
  ids <- gsub("^0+", "", ids) # RETO: could also done with base R
  ##require(stringi)
  ##ids <- stri_replace_all_regex(data$id, "^0*","") 
  return(ids)
}

## function to get all the URLS
URL_generator <- function(ids) {
    stopifnot(
        "argument `ids` must evaluate to integer" = is.integer(ids) && length(ids) > 0L,
        "argument `ids` evaluated to NA" = all(!is.na(ids))
    )
    sprintf("https://meteoapi.discdown.org/api/data/198822/xml/%d?parameters=tlmin:tlmax:tl_mittel", ids)
}



## function that ultimately retrieves the data that we are interested in
retriver <- function(URL) {
  tmp <- get_XML(URL)
  tmp <- data_frame_ENDPOINT1(tmp)
  tmp <- valid_stations(tmp)
  tmp <- ID_Extractor(tmp)
  tmp <- URL_generator(tmp)
  ## we first call all the functions we created in order to then parse the data
  
  df <- pager(get_XML(tmp[1]))
  pageinfo <- c()
  for (i in tmp[2:length(tmp)]) {
    pageinfo <- pager(get_XML(i))
    df <- rbind(df,pageinfo)
  }
  return(df)
}



## NA_cleaner function
NA_cleaner <- function(data) {
  #data$tlmin     <- ifelse(data$tlmin     < -100, NA, data$tlmin)
  #data$tlmax     <- ifelse(data$tlmax     < -100, NA, data$tlmax)
  #data$tl_mittel <- ifelse(data$tl_mittel < -100, NA, data$tl_mittel)
  # RETO: Alternative approach
  for (n in c("tlmin", "tlmax", "tl_mitte")) {
      data[[n]][data[[n]] < -100] <- NA_real_
  }
  return(data)
}

## functions to connect and disconnect to the database

library(DBI)
library(RMariaDB)
library(dotenv)

connect_db <- function(envfile = ".env") {
  if (!file.exists(envfile)) stop("Can't find file \"", envfile, "\"")
  require("dotenv")
  load_dot_env(envfile)
 # RETO: Should use a dotenv file 
 con <- dbConnect(
  RMariaDB::MariaDB(),
  host     = Sys.getenv("DB_SERVER"), 
  user     = Sys.getenv("DB_USER"),
  password = Sys.getenv("DB_PASSWORD"),
  dbname   = Sys.getenv("DB_NAME"),
  port     = 3306
  )
  if (dbIsValid(con)) {
    message("Connection successful!")         #same as in the python code 
  }
  return(con)
}

disconnect_db <- function(con) {
dbDisconnect(con)
  message("Disconnected from database.")
}

## function for reading from the database (I dont know yet if thats useful or not)

get_observations <- function(con, station_id, start_date, end_date) {
query <- paste0(
  "SELECT datum, tlmin, tlmax, tl_mittel 
  FROM observations 
  WHERE station_id = '", station_id, "'
  AND datum BETWEEN '", start_date, "' AND '", end_date, "'"
  )
   df <- dbGetQuery(con, query)
 return(df)
}


# function we did in class somewhat : 

create_stations_table <- function(con) {
  query <- "
 CREATE TABLE IF NOT EXISTS stations (
  station_id  VARCHAR(10) PRIMARY KEY,
  name        VARCHAR(100),
  state       VARCHAR(100),
  date_from   DATE,
  date_to     DATE,
  longitude   FLOAT,
  latitude    FLOAT,
  altitude    FLOAT, 
  tlmin       BOOLEAN,
  tlmax       BOOLEAN,
  tl_mittel   BOOLEAN
  )
  "
  dbExecute(con, query)
  message("Stations table created!")
}

# function for inserting the dataframe into the table 
insert_stations <- function(con, df) {
 for (i in 1:nrow(df)) {                                       # Loops over the df
  query <- paste0(
    "INSERT IGNORE INTO stations                                
      (station_id, name, state, date_from, date_to,
       longitude, latitude, altitude, tlmin, tlmax, tl_mittel)
    VALUES ('",
    df$id[i], "', '",
    df$name[i], "', '",
    df$state[i], "', '",
    df$date_from[i], "', '",
    df$date_to[i], "', ",
    as.numeric(df$longitude[i]), ", ",
    as.numeric(df$latitude[i]), ", ",
    as.numeric(df$altitude[i]), ", ",
    df$tlmin[i], ", ",
    df$tlmax[i], ", ",
    df$tl_mittel[i],
      ")"
    )
  dbExecute(con, query)
  }
  message("Stations inserted!")
}

# Small function to check the table 

check_stations <- function(con) {
  print(dbGetQuery(con, "SELECT COUNT(*) FROM stations"))       # checks count 
  
  print(dbGetQuery(con, "SELECT * FROM stations LIMIT 5"))      # shows the first few rows
}

# function for retrieving the data of one station

library("zoo")

get_obs_data <- function(con, station_id, years, take = c("datum", "tlmin", "tlmax", "tl_mittel")) {
  station_id <- as.integer(station_id)
  years <- as.integer(years)
  stopifnot(
    "argument `station_id` must be a single positive integer" = 
      is.integer(station_id) && length(station_id) == 1L && station_id > 0L
  )
  warning("CHECK IF THERE ARE -999s! IF SO, FIX IT")
  
  query <- sprintf("SELECT %s FROM observations WHERE station_id = %d AND datum >= '%d-01-01' AND datum <= '%d-12-31';",
                   paste(take, collapse = ", "), station_id, min(years), max(years))
  ##cat(query, "\n")
  x <- dbGetQuery(con, query)
  z <- zoo(x[, grep("^tl", names(x), value = TRUE)],  x$datum)
  return(z)
}

# function for aggregating the data 

as.month <- function(x) as.integer(format(x, "%m"))  # helper function 

aggregte_monthly <- function(ref, target, threshold_NA_ref = 0.1, threshold_NA_target = 0.01) {
  
  # MISSING DATA: Mean will return NA
  count_na <- function(x) sum(is.na(x))
  
  # Mean when we have enough non-missings
  my_mean <- function(x, threshold) {
    m <- mean(is.na(x))
    if (m > threshold) return(NA_real_)
    return(mean(x, na.rm = TRUE))
  }
  
  # Aggregating the months and combining them (I am using the n_ref and n_target here because those are clean either way)
  n_ref    <- aggregate(ref, as.month,    FUN = my_mean, threshold = threshold_NA_ref) # 0.5 percent!!!
  n_target <- aggregate(target, as.month, FUN = my_mean, threshold = threshold_NA_target) # 0.5 percent!!!
  names(n_ref) <- paste0("ref_", names(n_ref))
  x <- cbind(n_ref, n_target)
  
  # Return aggregated data first and write another function for the calculation (split seems easier)
  return(x)
}

# function for calculating the anomalies 

calc_anomalies <- function(x) {
  
  # Parameters 
  par <- c("tlmin", "tlmax", "tl_mittel")
  
  # Calculate the anomalies for each parameter 
  anomalies <- sapply(par, function(p) {
    x[ , p] - x[ , paste0("ref_", p)]
  })
  
  # Return zoo objet with the same index and the anomalies 
  z <- zoo(anomalies, index(x))
  names(z) <- paste0("anom_", par)
  return(z)
  
}

# Plotting functions (These were done with AI. I just have no idea how to write plot functions)

month_names <- c("Jan","Feb","Mar","Apr","May","Jun",
                 "Jul","Aug","Sep","Oct","Nov","Dec")

# function for aggregated data 

plot_climatology <- function(x, var = "ref_tl_mittel") {
  vals <- as.numeric(x[, var])
  
  # build step coordinates: each month spans a full unit width
  xs <- c(rbind(0:11, 1:12))      # 0,1,1,2,2,3...
  ys <- rep(vals, each = 2)        # each value twice for the plateau
  
  plot(xs, ys, type = "l", lwd = 2, col = "steelblue",
       xaxt = "n", xlab = "", 
       ylab = "average daily mean temperature [deg C]",
       main = "Climatology [1990-2019]",
       ylim = c(min(vals) - 2, max(vals) + 2))
  axis(1, at = 0.5:11.5, labels = month_names)
  
  # labels sit above the middle of each plateau, clear of the line
  text(0.5:11.5, vals, labels = round(vals, 1), pos = 3, cex = 0.8, offset = 0.6)
}

# function for anomalies
plot_anomalies <- function(anom, actual, var = "anom_tl_mittel", 
                           actual_var = "tl_mittel") {
  a   <- as.numeric(anom[, var])
  act <- as.numeric(actual[, actual_var])
  
  cols <- ifelse(a >= 0, "firebrick", "grey70")
  
  bp <- barplot(a, col = cols, border = NA, names.arg = month_names,
                ylim = c(-6, 6), ylab = "anomaly [deg C]",
                main = "Temperature Anomaly 2025")
  abline(h = 0)
  
  # anomaly value label
  text(bp, a, labels = sprintf("%+.1f", a),
       pos = ifelse(a >= 0, 3, 1), cex = 0.8)
  # actual 2025 mean in parentheses
  text(bp, 0, labels = sprintf("(%.1f)", act),
       pos = ifelse(a >= 0, 1, 3), cex = 0.7, col = "grey30")
}

# Insert ignore so we do not duplicate 
# id as character because integer would change the information (character is the easiest option here so the python team can macth it directly)
# most of the other values will be converted into the right class because of the constraints in the table 
# parameters ended up being 1 / 0 

## Get the station ids we are interested in

get_valid_stations_db <- function(con,date_from = '1950-01-01',date_to = '2024-12-31') {
  query <- "
  SELECT station_id 
  FROM stations 
  WHERE tl_mittel = TRUE
  AND       tlmax = TRUE
  AND       tlmin = TRUE
  AND  date_from <= '%s'
  AND     date_to > '%s';
  "
  query <- sprintf(query,date_from,date_to)
  dbGetQuery(con,query)
}

## Join the tables on those ids

join_tables_for_stations <- function(con,valid_station_ids,date_from = '1950-01-01',date_to = '2024-12-31') {
  query <- "
  SELECT stations.station_id, 
  observations.tl_mittel, 
  altitude, 
  latitude, 
  longitude, 
  datum
  FROM stations
  JOIN observations
  ON stations.station_id = observations.station_id
  WHERE stations.station_id IN (%s)
  AND observations.datum 
  BETWEEN '%s'
  AND '%s'"
  ids   <- paste(valid_station_ids[[1]], collapse = ", ")
  query <- sprintf(query, ids, date_from, date_to)
  dbGetQuery(con,query)
}

## Aggregate the table on a yearly basis
aggregate_yearly <- function(df) {
  df$year  <- as.integer(format(as.Date(df$datum), "%Y"))
  year_agg <- aggregate(tl_mittel ~ station_id + year + latitude + longitude + altitude,
            data = df, FUN = mean)
  return(year_agg)
}


## AI for plot animations, plots the temperature agg for each year

library(ggplot2)
library(gganimate)
library(magick)

plot_stacked_anim <- function(yearly, nframes = 100, fps = 5,
                              outfile = "austria_temps.gif") {
  temp_range <- range(yearly$tl_mittel)
  
  top  <- transform(yearly, xval = longitude, yval = latitude)
  side <- transform(yearly, xval = longitude, yval = altitude)
  
  top_anim <- ggplot(top, aes(longitude, latitude, color = tl_mittel,
                              group = station_id)) +
    geom_point(size = 4) +
    scale_color_viridis_c(option = "inferno", name = "Mean temp (°C)",
                          limits = temp_range) +
    coord_fixed(ratio = 1 / cos(47 * pi / 180)) +
    labs(x = NULL, y = "Latitude", title = "Year: {round(frame_time)}") +
    transition_time(year)
  
  side_anim <- ggplot(side, aes(longitude, altitude, color = tl_mittel,
                                group = station_id)) +
    geom_point(size = 4) +
    scale_color_viridis_c(option = "inferno", name = "Mean temp (°C)",
                          limits = temp_range) +
    labs(x = "Longitude", y = "Altitude (m)") +
    transition_time(year)
  
  top_gif  <- animate(top_anim,  nframes = nframes, fps = fps,
                      width = 800, height = 350)
  side_gif <- animate(side_anim, nframes = nframes, fps = fps,
                      width = 800, height = 300)
  
  t <- image_read(top_gif)
  s <- image_read(side_gif)
  frames <- image_join(lapply(seq_len(nframes), function(i) {
    image_append(c(t[i], s[i]), stack = TRUE)
  }))
  
  image_write(frames, outfile)
  frames
}


##
### What next ?
## We need to store the results in our DB, we discussed doing it in 2 stages
## first the result from the data_frame_ENDPOINT1 function
## then the result from the retriver function
## optionally use the NA_cleaner before but would argue against it we can use it in the Data Analytics part
