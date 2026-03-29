from fastapi import APIRouter, Depends, Query
from pydantic import BaseModel
from typing import List
import math
from sqlalchemy.orm import Session
import pandas as pd
import numpy as np
from sklearn.cluster import DBSCAN

# IMPORTANT: Update these imports to match your actual project structure
# from app.database import get_db 
# from app.models import AccidentRecord 

router = APIRouter(
    prefix="/api/v1/hotspots",
    tags=["Hotspots"]
)

# --- Pydantic Schemas for the Output ---
class MicroHotspot(BaseModel):
    hotspot_id: int
    lat: float
    lng: float
    predicted_severity: str
    severity_score: int
    distance_meters: int
    total_accidents_in_cluster: int # Shows how many scattered points were merged

class HotspotResponse(BaseModel):
    zone_center: dict
    search_radius_meters: int
    total_hotspots_found: int
    micro_hotspots: List[MicroHotspot]


# --- Helper Function: Haversine Distance ---
def calculate_haversine(lat1: float, lon1: float, lat2: float, lon2: float) -> float:
    R = 6371000  # Earth radius in meters
    phi1, phi2 = math.radians(lat1), math.radians(lat2)
    delta_phi = math.radians(lat2 - lat1)
    delta_lambda = math.radians(lon2 - lon1)

    a = math.sin(delta_phi / 2.0) ** 2 + \
        math.cos(phi1) * math.cos(phi2) * \
        math.sin(delta_lambda / 2.0) ** 2
    
    c = 2 * math.atan2(math.sqrt(a), math.sqrt(1 - a))
    return R * c

# --- Helper Function: DBSCAN Clustering (Fixes GPS Drift) ---
def generate_clustered_hotspots(raw_records, user_lat, user_lng):
    if not raw_records:
        return []

    df = pd.DataFrame(raw_records)
    
    # Ensure we have lat/lon columns
    if 'lat' not in df.columns or 'lng' not in df.columns:
        return []

    # 1. Convert to radians for Haversine math
    coords = np.radians(df[['lat', 'lng']].to_numpy())

    # 2. DBSCAN Config for Junction Snapping
    kms_per_radian = 6371.0088
    
    # 🟢 150-METER RADIUS (0.15 km): This is wide enough to catch all 
    # scattered accidents around a single large intersection and merge them.
    epsilon = (0.15) / kms_per_radian 
    
    # 🟢 Minimum accidents required to form a valid hotspot
    minimum_accidents = 7 

    # 3. Run clustering algorithm
    db = DBSCAN(eps=epsilon, min_samples=minimum_accidents, algorithm='ball_tree', metric='haversine').fit(coords)
    df['cluster'] = db.labels_

    clustered_hotspots = []
    cluster_id_counter = 1
    
    unique_clusters = set(df['cluster'])
    
    for cluster_id in unique_clusters:
        if cluster_id == -1:
            continue # Skip isolated accidents (noise)
        
        # Get all the scattered accidents that belong to this one junction
        cluster_points = df[df['cluster'] == cluster_id]
        
        # 🟢 THE JUNCTION SNAP: Calculate the exact mathematical center of the scatter plot
        center_lat = cluster_points['lat'].mean()
        center_lng = cluster_points['lng'].mean()
        accident_count = len(cluster_points)
        
        # Determine severity (grab the highest score in the cluster)
        max_score = cluster_points['score'].max()
        if max_score >= 3:
            severity = "Fatal"
        elif max_score == 2:
            severity = "Grievous"
        else:
            severity = "Minor"

        # Calculate distance from the user to the perfectly centered junction hotspot
        distance_to_user = calculate_haversine(user_lat, user_lng, center_lat, center_lng)

        clustered_hotspots.append(
            MicroHotspot(
                hotspot_id=cluster_id_counter,
                lat=round(center_lat, 6),
                lng=round(center_lng, 6),
                predicted_severity=severity,
                severity_score=max_score, 
                distance_meters=int(distance_to_user),
                total_accidents_in_cluster=accident_count
            )
        )
        cluster_id_counter += 1

    return clustered_hotspots

# --- The Main Endpoint ---
@router.get("/nearby", response_model=HotspotResponse)
def get_nearby_hotspots(
    lat: float = Query(..., description="User's current latitude"),
    lng: float = Query(..., description="User's current longitude"),
    radius: int = Query(5000, description="Search radius in meters"),
    # db: Session = Depends(get_db) # Uncomment when integrating your DB
):
    # 1. Bounding Box Optimization
    offset = (radius / 111000.0) 
    min_lat, max_lat = lat - offset, lat + offset
    min_lng, max_lng = lng - offset, lng + offset

    # Replace `AccidentRecord` with your actual SQLAlchemy model name
    '''
    nearby_records = db.query(AccidentRecord).filter(
        AccidentRecord.lat >= min_lat,
        AccidentRecord.lat <= max_lat,
        AccidentRecord.lng >= min_lng,
        AccidentRecord.lng <= max_lng
    ).all()
    
    # Convert SQLAlchemy objects to dicts for pandas
    raw_data = [{"id": r.id, "lat": r.lat, "lng": r.lng, "severity": r.severity, "score": r.score} for r in nearby_records]
    '''
    
    # --- MOCK DATA FOR TESTING (Remove this when DB is connected) ---
    # These 7 points simulate scattered accidents around a single junction
    raw_data = [
        {"id": 1, "lat": lat + 0.0010, "lng": lng + 0.0010, "severity": "Fatal", "score": 3},
        {"id": 2, "lat": lat + 0.0011, "lng": lng + 0.0011, "severity": "Minor", "score": 1},
        {"id": 3, "lat": lat + 0.0009, "lng": lng + 0.0009, "severity": "Grievous", "score": 2},
        {"id": 4, "lat": lat + 0.0010, "lng": lng + 0.0012, "severity": "Minor", "score": 1},
        {"id": 5, "lat": lat + 0.0008, "lng": lng + 0.0010, "severity": "Minor", "score": 1},
        {"id": 6, "lat": lat + 0.0012, "lng": lng + 0.0008, "severity": "Minor", "score": 1},
        {"id": 7, "lat": lat + 0.0011, "lng": lng + 0.0009, "severity": "Minor", "score": 1},
        {"id": 8, "lat": lat + 0.0200, "lng": lng - 0.0200, "severity": "Fatal", "score": 3}, # Isolated noise (will be ignored)
    ]
    # -----------------------------------------------------------------

    # Filter out anything truly outside the search radius before clustering
    filtered_raw_data = []
    for record in raw_data:
        dist = calculate_haversine(lat, lng, record["lat"], record["lng"])
        if dist <= radius:
            filtered_raw_data.append(record)

    # Pass the filtered raw accidents to the DBSCAN clustering function
    final_micro_hotspots = generate_clustered_hotspots(filtered_raw_data, lat, lng)

    # Return the clean, merged list of hotspots to your Flutter app
    return HotspotResponse(
        zone_center={"lat": lat, "lng": lng},
        search_radius_meters=radius,
        total_hotspots_found=len(final_micro_hotspots),
        micro_hotspots=final_micro_hotspots
    )