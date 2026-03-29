import pandas as pd
from sqlalchemy.orm import Session
from database import SessionLocal
import models

# 1. Load the CSV Data
file_path = "data.csv"

# Added low_memory=False to prevent Pandas dtype warnings
df = pd.read_csv(file_path, header=0, low_memory=False) 

# Extract Latitude (col 1), Longitude (col 2), and Severity (col 3)
df = df.iloc[:, [1, 2, 3]].copy()
df.columns = ['latitude', 'longitude', 'severity']

# Drop rows with missing GPS coordinates
df = df.dropna(subset=['latitude', 'longitude'])

# 2. Map the long CSV text to your Flutter App's 3 severity levels
def standardize_severity(text):
    text = str(text).strip()
    if 'Fatal' in text:
        return 'Critical'
    elif 'Grievous' in text:
        return 'Major'
    else:
        # Catches 'Minor Injury Hospitalized', 'Minor Injury Non Hospitalized', and 'No Injury'
        return 'Minor' 

# Apply the mapping to the dataframe
df['severity'] = df['severity'].apply(standardize_severity)

# 3. Open database connection
db: Session = SessionLocal()

print(f"Starting import of {len(df)} records...")

# 4. Insert into the Database
inserted_count = 0
for index, row in df.iterrows():
    try:
        # Create an Accident record for the database
        historical_accident = models.Accident(
            user_email="system@safehorizon.com", 
            latitude=str(row['latitude']),
            longitude=str(row['longitude']),
            severity=str(row['severity']), 
            description="Historical Data Import",
            accident_datetime="2023-01-01 12:00 PM",
            status="approved" 
            # 🟢 REMOVED assigned_authority_id to prevent the keyword error
        )
        db.add(historical_accident)
        inserted_count += 1
        
        # Save to database in batches of 500 to prevent crashing
        if inserted_count % 500 == 0:
            db.commit()
            print(f"Inserted {inserted_count} records...")
            
    except Exception as e:
        print(f"Error on row {index}: {e}")
        db.rollback()

# Final commit for the remaining records
db.commit()
db.close()

print(f"✅ Successfully imported {inserted_count} historical accidents into the database!")