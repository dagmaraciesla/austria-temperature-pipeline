from functions import *
import pandas as pd
import os
import logging
import mysql.connector
from dotenv import load_dotenv
import datetime as dt

# set True to confirm each station before inserting
INTERACTIVE = False
# set True to drop and re-initialize the observations table before inserting
RESET_DB = False

if __name__ == "__main__":
    logging.basicConfig(level=logging.INFO,
                        format="%(asctime)s %(levelname)s %(message)s")

    # loading dotenv file in the main script
    envfile = ".env"
    if not os.path.isfile(envfile):
        raise FileNotFoundError(f"problems finding dotenv file: {envfile=}")
    load_dotenv(envfile)

    # connecting to db
    conn = get_db_connection()

    if RESET_DB:
        drop_all_observations(conn)
        initialize_database_schema(conn)

    # getting the data from table stations
    stations = get_relevant_stations(conn, '1995-01-01', '2025-12-31')
    logging.info(f"Found {len(stations)} qualifying stations.")

    t1 = dt.datetime.now()

    # getting the observation data from xml and inserting per station
    for station in stations:
        sid = station['station_id']

        if INTERACTIVE:
            answer = input(f"Insert observations for station {sid}? (y/n): ").strip().lower()
            if answer == 'n':
                break
            elif answer != 'y':
                logging.info(f"Skipped station {sid}")
                continue

        observations_df = retrieve_observations([str(int(sid))])
        observations_df = NA_cleaner(observations_df)
        insert_data(conn, observations_df)
        logging.info(f"Done: station {sid}")

    # disconnecting from db
    disconnect_from_db(conn)

    time_taken = dt.datetime.now() - t1
    logging.info(f"Inserted observations for {len(stations)} stations "
                 f"in {time_taken} ({time_taken.total_seconds():.1f}s)")