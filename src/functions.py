from datetime import datetime
import os
import json
import xml.etree.ElementTree as ET
import pandas as pd
import requests
import mysql.connector
import logging
import tqdm


# RETO: For clarity it might be better to load the dotenv file in the main
#       script, so a user can see that a dotenv is used when checking
#       the main code.
##from dotenv import load_dotenv
##load_dotenv()
logging.basicConfig(level=logging.DEBUG)


### Function to get the xml data
def get_XML(url: str):
    cache_dir = "cache"
    os.makedirs(cache_dir, exist_ok=True)
    cache_name = os.path.join(cache_dir, url.replace("/", "_").replace("?", "_").replace("=", "_") + ".xml")

    if os.path.exists(cache_name):
        logging.debug(f"Using cache insted of {url}")
        with open(cache_name, "r") as cache:
            return ET.fromstringlist(cache.readlines())
                              
    response = requests.get(url)
    response.raise_for_status()  # Raises an error for bad responses (4xx, 5xx)
    # Parse the XML content from bytes
    with open(cache_name, 'wb') as cache:
        cache.write(response.content)
    return ET.fromstring(response.content)


### Function to parse the data and get a df from Endpoint 1
def data_frame_ENDPOINT1(xml_data):
    # Find all station elements
    stations = xml_data.findall(".//station")

    rows = []
    for station in stations:
        # Extract attributes securely
        station_id = station.get("id")
        date_from = station.get("data_from")
        date_to = station.get("data_to")

        # Check for specific parameters
        tlmax = station.find(".//parameter[@name='tlmax']") is not None
        tlmin = station.find(".//parameter[@name='tlmin']") is not None
        tl_mittel = station.find(".//parameter[@name='tl_mittel']") is not None

        rows.append(
            {
                "id": station_id,
                "date_from": date_from,
                "date_to": date_to,
                "tlmin": tlmin,
                "tlmax": tlmax,
                "tl_mittel": tl_mittel,
            }
        )

    # Create the DataFrame
    df = pd.DataFrame(rows)
    return df


### Function to get the desired information from endpoint 2 of one station
def pager(xml_data):
    # Find the observations text block (which contains JSON)
    obs_element = xml_data.find(".//observations")
    if obs_element is not None and obs_element.text:
        # Convert JSON string to a python list/dict and then to a DataFrame
        json_data = json.loads(obs_element.text)
        df = pd.DataFrame(json_data)
    else:
        df = pd.DataFrame()

    # Find the station metadata to broadcast across rows
    station = xml_data.find(".//station")
    if station is not None:
        name_elem = station.find("name")
        state_elem = station.find("state")
        lon_elem = station.find("longitude")
        lat_elem = station.find("latitude")
        alt_elem = station.find("altitude")

        df["id"] = station.get("id")
        df["stationname"] = name_elem.text if name_elem is not None else None
        df["state"] = state_elem.text if state_elem is not None else None
        df["longitude"] = lon_elem.text if lon_elem is not None else None
        df["latitude"] = lat_elem.text if lat_elem is not None else None
        df["altitude"] = alt_elem.text if alt_elem is not None else None

    return df



### Function to only get the valid endpoint 2 data
def valid_stations(df, start="1990-01-01", end="2019-12-31"):
    # Convert date columns to datetime objects
    df["date_to"] = pd.to_datetime(df["date_to"])
    df["date_from"] = pd.to_datetime(df["date_from"])

    # Now we can compare and filter
    start_dt = pd.to_datetime(start)
    end_dt = pd.to_datetime(end)

    valid = df[(df["date_from"] <= start_dt) & (df["date_to"] >= end_dt)]
    valid = valid[
        (valid["tlmin"] == True)
        & (valid["tlmax"] == True)
        & (valid["tl_mittel"] == True)
    ]

    return valid


### Function to get IDs for the pager URL
def ID_Extractor(df):
    # Strip leading zeros from the 'id' column string
    # .str.lstrip('0') mirrors R's stri_replace_all_regex(..., "^0*", "")
    ids = df["id"].astype(str).str.lstrip("0")
    return ids.tolist()


### Function to get all the URLS
def URL_generator(ids):
    urls = []
    for station_id in ids:
        url = f"https://meteoapi.discdown.org/api/data/198822/xml/{station_id}?parameters=tlmin:tlmax:tl_mittel"
        urls.append(url)
    return urls

# RETO: Moved URL as default arg to this function
def get_station_ids(URL = "https://meteoapi.discdown.org/api/station-search?format=xml"):
    xml_data = get_XML(URL)
    df_ep1 = data_frame_ENDPOINT1(xml_data)
    valid_df = valid_stations(df_ep1)
    return ID_Extractor(valid_df)


### Function that ultimately retrieves the data that we are interested in
def retrieve_observations(station_ids):
    urls = URL_generator(station_ids)
    print(f"{urls=}")

    if not urls:
        return pd.DataFrame()

    # Loop through URLs and bind them together (like rbind)
    dfs = []
    for i in urls:
        try:
            station_xml = get_XML(i)
            pageinfo = pager(station_xml)
            dfs.append(pageinfo)
        except Exception as e:
            print(f"Failed to fetch or parse URL {i}: {e}")
            continue

    # pd.concat handles the 'rbind' functionality efficiently in Python
    if dfs:
        final_df = pd.concat(dfs, ignore_index=True)
        return final_df
    else:
        return pd.DataFrame()
    


### NA_cleaner function
def NA_cleaner(df):
    # In pandas, we use .loc or direct assignment with mask to clean numbers, mapping them to None/NaN
    for col in ["tlmin", "tlmax", "tl_mittel"]:
        if col in df.columns:
            # Convert column to numeric first if it isn't already
            df[col] = pd.to_numeric(df[col], errors="coerce")
            df.loc[df[col] < -100, col] = None
            df[col] = df[col].where(df[col].notna(), None)
    return df



### connecting to DB

def get_db_connection() -> mysql.connector.MySQLConnection:
    try:
        connection = mysql.connector.connect(
            host=os.environ.get("DB_SERVER"),
            user=os.environ.get("DB_USER"),
            password=os.environ.get("DB_PASSWORD"),
            database=os.environ.get("DB_NAME"),
            port=3306,
            charset='utf8mb4',
            collation='utf8mb4_general_ci'
        )
        return connection
    except mysql.connector.Error as err:
        print(f"Error connecting to the database: {err}")
        raise err
## disconnecting from DB
def disconnect_from_db(conn):
    if conn and conn.is_connected():
        conn.close()



### initializing tables for both datasets function

def initialize_database_schema(connection):
    if connection is None:
        print("No active database connection.")
        return
    
    cursor = connection.cursor()
    
    try:
        print("Creating table...")
       
        # Observations Table
        create_observations_table = """
        CREATE TABLE IF NOT EXISTS observations ( 
            station_id INT NOT NULL,
            datum DATETIME NOT NULL,
            tlmax FLOAT,
            tlmin FLOAT,
            tl_mittel FLOAT,
            PRIMARY KEY (station_id, datum),
            FOREIGN KEY (station_id) REFERENCES stations(station_id) ON DELETE CASCADE
        );
        """
        
        # Run the command on the server
        cursor.execute(create_observations_table)
        
        # Commit
        connection.commit()
        print("Table created!")
        
    except mysql.connector.Error as err:
        connection.rollback() # Safely undo changes if something breaks mid-execution
        print(f"An error occurred while executing SQL: {err}")
        raise err
    finally:
        cursor.close()


def drop_table(connection):
    if connection is None:
        print("No active database connection.")
        return
    
    cursor = connection.cursor()
    
    try:
        drop_table_station = """
        DROP TABLE stations;
        );
        """
        drop_table_observations = """
        DROP TABLE observations;
        );
        """
        
        
        # Run the commands on the server
        cursor.execute(drop_table_station)
        
        
        # Commit
        connection.commit()
        print("Tables deleted!")
        
    except mysql.connector.Error as err:
        connection.rollback() # Safely undo changes if something breaks mid-execution
        print(f"An error occurred while executing SQL: {err}")
        raise err
    finally:
        cursor.close()
    


### function for inserting data from the xml into the tables 

def insert_data(connection: mysql.connector.MySQLConnection, df):
    if connection is None or df.empty:
        print("No connection or empty DataFrame.")
        return
    df = df.astype(object).where(pd.notna(df), None)
    cursor = connection.cursor()
    
    cntr = 0
    try:
        # # 1. Insert unique stations first (parent table)
        # stations = df[["id", "stationname"]].drop_duplicates(subset="id")
        # for _, row in stations.iterrows():
        #     cursor.execute(
        #         "INSERT IGNORE INTO stations (station_id, NAME) VALUES (%s, %s);",
        #         (row["id"], row["stationname"])
        #     )
        
        # 2. Insert observations (child table)
        logging.info("Inserting observations into the database...")
        cursor.executemany("""INSERT IGNORE INTO observations 
                   (station_id, datum, tlmax, tlmin, tl_mittel) 
                   VALUES (%s, %s, %s, %s, %s);""", [(row["id"],
                    row.get("datum"),
                    row.get("tlmax"),
                    row.get("tlmin"),
                    row.get("tl_mittel")) for _, row in df.iterrows()])
    
        for _, row in tqdm.tqdm(df.iterrows()):
            pass
            # cursor.execute(
            #     """INSERT IGNORE INTO observations 
            #        (station_id, datum, tlmax, tlmin, tl_mittel) 
            #        VALUES (%s, %s, %s, %s, %s);""",
            #     (
            #         row["id"],
            #         row.get("datum"),
            #         row.get("tlmax"),
            #         row.get("tlmin"),
            #         row.get("tl_mittel")
            #     )
            # )
            
        
        connection.commit()
        print(f"Inserted {len(df)} observations.")
        
    except mysql.connector.Error as err:
        connection.rollback()
        print(f"Insert failed: {err}")
        raise err
    finally:
        cursor.close()

### function to read specific data from observations table

def read_data(connection, station_id, start_date, end_date):
    query = """
    SELECT datum, tlmin, tlmax, tl_mittel
    FROM observations
    WHERE station_id = %s
    AND datum BETWEEN %s AND %s;
    """
    df = pd.read_sql(query, con=connection, params=(station_id, start_date, end_date))
    df["datum"] = pd.to_datetime(df["datum"])
    df = df.set_index("datum")
    return df

    

        

def get_relevant_stations(connection, date_from, date_to):

    cursor = connection.cursor(dictionary=True)

    query = """
    SELECT *
    FROM stations
    WHERE date_from <= %s
    AND date_to >= %s
    AND tlmin = 1 AND tlmax = 1 AND tl_mittel = 1;
    """
    cursor.execute(query, (date_from, date_to))

    results = cursor.fetchall()
    cursor.close()
    return results

# Quick test
if __name__ == "__main__":
    print("This is my test running")


