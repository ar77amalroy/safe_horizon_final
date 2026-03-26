from fastapi import APIRouter, Depends, Query
from pydantic import BaseModel
from typing import List
import math
from sqlalchemy.orm import Session

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


# --- The Main Endpoint ---
@router.get("/nearby", response_model=HotspotResponse)
def get_nearby_hotspots(
    lat: float = Query(..., description="User's current latitude"),
    lng: float = Query(..., description="User's current longitude"),
    radius: int = Query(5000, description="Search radius in meters"),
    # db: Session = Depends(get_db) # Uncomment when integrating your DB
):
    # 1. Bounding Box Optimization (Roughly 1 degree of lat/lng is ~111km)
    # This filters out records on the other side of the state before doing heavy math.
    offset = (radius / 111000.0) 
    min_lat, max_lat = lat - offset, lat + offset
    min_lng, max_lng = lng - offset, lng + offset

    # 2. Query the database using the Bounding Box
    # Replace `AccidentRecord` with your actual SQLAlchemy model name
    '''
    nearby_records = db.query(AccidentRecord).filter(
        AccidentRecord.lat >= min_lat,
        AccidentRecord.lat <= max_lat,
        AccidentRecord.lng >= min_lng,
        AccidentRecord.lng <= max_lng
    ).all()
    '''
    
    # --- MOCK DATA FOR TESTING (Remove this once DB is connected) ---
    nearby_records = [
        {"id": 1, "lat": lat + 0.001, "lng": lng + 0.001, "severity": "Fatal", "score": 3},
        {"id": 2, "lat": lat + 0.004, "lng": lng - 0.002, "severity": "Grievous", "score": 2},
        {"id": 3, "lat": lat + 0.080, "lng": lng + 0.080, "severity": "Minor", "score": 1} # Outside 5km
    ]
    # -----------------------------------------------------------------

    micro_hotspots = []

    # 3. Exact Distance Calculation & ML Scoring
    for record in nearby_records:
        # If using SQLAlchemy objects, change record["lat"] to record.lat
        distance = calculate_haversine(lat, lng, record["lat"], record["lng"])
        
        if distance <= radius:
            micro_hotspots.append(
                MicroHotspot(
                    hotspot_id=record["id"],
                    lat=record["lat"],
                    lng=record["lng"],
                    predicted_severity=record["severity"],
                    severity_score=record["score"], 
                    distance_meters=int(distance)
                )
            )

    # 4. Return the structured JSON
    return HotspotResponse(
        zone_center={"lat": lat, "lng": lng},
        search_radius_meters=radius,
        total_hotspots_found=len(micro_hotspots),
        micro_hotspots=micro_hotspots
    )