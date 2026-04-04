from fastapi import FastAPI, Depends, HTTPException, UploadFile, File, Form, Request
from fastapi.middleware.cors import CORSMiddleware
from fastapi.staticfiles import StaticFiles
from sqlalchemy.orm import Session
from pydantic import BaseModel  # 🟢 Added for Partner schema
import os
import shutil
from io import StringIO # 🟢 NEW: Added for CSV parsing in memory

# 🟢 NEW: Imports for Partner OTP and Email
import smtplib
from email.mime.text import MIMEText
import random
from datetime import datetime, timedelta

# 🟢 AI and Math Imports for Prediction
import pandas as pd
import numpy as np
from sklearn.cluster import DBSCAN
import math

import models, schemas, crud
from database import engine, SessionLocal
from email_utils import send_verification_email


# =====================================================
# CREATE FASTAPI APP
# =====================================================
app = FastAPI()

# CORS
@app.get("/")
def read_root():
    return {"status": "SafeHorizon API is Live and Running!"}

# create tables
models.Base.metadata.create_all(bind=engine)


# =====================================================
# UPLOADS CONFIG
# =====================================================
UPLOAD_DIR = "uploads"
os.makedirs(UPLOAD_DIR, exist_ok=True)

app.mount("/uploads", StaticFiles(directory="uploads"), name="uploads")


# =====================================================
# DATABASE SESSION
# =====================================================
def get_db():
    db = SessionLocal()
    try:
        yield db
    finally:
        db.close()


# =====================================================
# GET USER PROFILE
# =====================================================
@app.get("/user/{email}")
def get_user(email: str, db: Session = Depends(get_db)):

    user = db.query(models.User)\
        .filter(models.User.email == email)\
        .first()

    if not user:
        raise HTTPException(status_code=404, detail="User not found")

    return {
        "name": user.name,
        "email": user.email,
        "phone": user.phone,
        "profile_image": user.profile_image
    }


# =====================================================
# UPLOAD PROFILE IMAGE
# =====================================================
@app.post("/upload-profile-image")
async def upload_profile_image(
    email: str = Form(...),
    image: UploadFile = File(...),
    db: Session = Depends(get_db)
):

    user = db.query(models.User)\
        .filter(models.User.email == email)\
        .first()

    if not user:
        raise HTTPException(status_code=404, detail="User not found")

    filename = f"{email}_{image.filename}"
    file_location = os.path.join(UPLOAD_DIR, filename)

    with open(file_location, "wb") as buffer:
        shutil.copyfileobj(image.file, buffer)

    image_path = file_location.replace("\\", "/")

    user.profile_image = image_path
    db.commit()

    return {
        "message": "Profile image saved successfully",
        "image_url": image_path
    }


# =====================================================
# REGISTER
# =====================================================
@app.post("/register")
async def register(user: schemas.UserCreate, db: Session = Depends(get_db)):

    existing = crud.get_user_by_email(db, user.email)

    if existing and existing.is_verified:
        raise HTTPException(status_code=409, detail="EMAIL_ALREADY_EXISTS")

    new_user = crud.create_user(
        db,
        user.name,
        user.email,
        user.phone
    )

    print("\n==============================")
    print("OTP FOR:", new_user.email)
    print("OTP CODE:", new_user.verification_code)
    print("==============================\n")

    await send_verification_email(
        new_user.email,
        new_user.verification_code
    )

    return {"message": "Verification code generated"}


# =====================================================
# VERIFY EMAIL
# =====================================================
@app.post("/verify-email")
def verify_email(data: schemas.VerifyEmail, db: Session = Depends(get_db)):

    success = crud.verify_email_code(db, data.email, data.code)

    if not success:
        raise HTTPException(
            status_code=400,
            detail="Invalid or expired verification code"
        )

    return {"message": "Email verified successfully"}


# =====================================================
# SET PASSWORD
# =====================================================
@app.post("/set-password")
def set_password(data: schemas.SetPassword, db: Session = Depends(get_db)):

    success = crud.set_user_password(db, data.email, data.password)

    if not success:
        raise HTTPException(
            status_code=400,
            detail="User not found or email not verified"
        )

    return {"message": "Password created successfully"}


# =====================================================
# LOGIN
# =====================================================
@app.post("/login")
def login(user: schemas.UserLogin, db: Session = Depends(get_db)):

    db_user = crud.authenticate_user(db, user.email, user.password)

    if not db_user:
        raise HTTPException(status_code=400, detail="Invalid email or password")

    if not db_user.is_verified:
        raise HTTPException(status_code=403, detail="Email not verified")

    return {
        "message": "Login successful",
        "name": db_user.name,
        "email": db_user.email,
        "phone": db_user.phone if db_user.phone else ""
    }


# =====================================================
# FORGOT PASSWORD FLOW
# =====================================================
@app.post("/forgot-password")
async def forgot_password(data: schemas.ForgotPassword,
                          db: Session = Depends(get_db)):

    user = crud.generate_reset_code(db, data.email)

    if not user:
        raise HTTPException(status_code=404, detail="User not found")

    await send_verification_email(user.email, user.verification_code)

    return {"message": "Reset code sent to email"}


@app.post("/verify-reset-code")
def verify_reset_code(data: schemas.VerifyResetCode,
                      db: Session = Depends(get_db)):

    success = crud.verify_reset_code(db, data.email, data.code)

    if not success:
        raise HTTPException(status_code=400,
                            detail="Invalid or expired code")

    return {"message": "Code verified"}


@app.post("/reset-password")
def reset_password(data: schemas.ResetPassword,
                   db: Session = Depends(get_db)):

    success = crud.reset_password(db, data.email, data.password)

    if not success:
        raise HTTPException(status_code=400, detail="Reset failed")

    return {"message": "Password reset successful"}


# =====================================================
# DELETE ACCOUNT
# =====================================================
@app.delete("/delete-account/{email}")
def delete_account(email: str, db: Session = Depends(get_db)):

    user = db.query(models.User)\
        .filter(models.User.email == email)\
        .first()

    if not user:
        raise HTTPException(status_code=404, detail="User not found")

    db.query(models.Accident)\
        .filter(models.Accident.user_email == email)\
        .delete()

    db.delete(user)
    db.commit()

    return {"message": "Account deleted successfully"}


# =====================================================
# ACCIDENT REPORT
# =====================================================
@app.post("/report-accident")
async def report_accident(
    user_email: str = Form(...),
    latitude: str = Form(...),
    longitude: str = Form(...),
    severity: str = Form(...),
    description: str = Form(""),
    accident_datetime: str = Form(...),
    image: UploadFile = File(None),
    db: Session = Depends(get_db)
):

    print("🚨 REPORT API HIT")

    try:
        image_path = None

        if image:
            filename = f"{user_email}_{image.filename}"
            file_location = os.path.join(UPLOAD_DIR, filename)

            with open(file_location, "wb") as buffer:
                shutil.copyfileobj(image.file, buffer)

            image_path = file_location.replace("\\", "/")

        accident = models.Accident(
            user_email=user_email,
            latitude=latitude,
            longitude=longitude,
            severity=severity,
            description=description,
            image_path=image_path,
            accident_datetime=accident_datetime,
            status="pending"
        )

        db.add(accident)
        db.commit()
        db.refresh(accident)

        print("✅ REPORT SAVED:", accident.id)

        return {
            "message": "Accident report submitted successfully",
            "report_id": accident.id,
            "status": accident.status
        }

    except Exception as e:
        print("❌ REPORT FAILED:", str(e))
        raise HTTPException(status_code=500, detail=str(e))


# =====================================================
# USER REPORT STATUS
# =====================================================
@app.get("/user/reports/{email}")
def get_user_reports(email: str, db: Session = Depends(get_db)):

    reports = db.query(models.Accident)\
        .filter(models.Accident.user_email == email)\
        .order_by(models.Accident.id.desc())\
        .all()

    return reports


# =====================================================
# ADMIN APIs
# =====================================================
@app.get("/admin/pending-reports")
def get_pending_reports(request: Request,
                        db: Session = Depends(get_db)):

    reports = db.query(models.Accident)\
        .filter(models.Accident.status == "pending")\
        .all()

    base_url = str(request.base_url).rstrip("/")

    result = []

    for r in reports:
        image_url = None
        if r.image_path:
            image_url = f"{base_url}/{r.image_path}"

        result.append({
            "id": r.id,
            "user_email": r.user_email,
            "latitude": r.latitude,
            "longitude": r.longitude,
            "severity": r.severity,
            "description": r.description,
            "accident_datetime": r.accident_datetime,
            "status": r.status,
            "image_url": image_url
        })

    return result


@app.put("/admin/approve/{report_id}")
def approve_report(report_id: int, db: Session = Depends(get_db)):

    report = db.query(models.Accident)\
        .filter(models.Accident.id == report_id)\
        .first()

    if not report:
        raise HTTPException(status_code=404, detail="Report not found")

    report.status = "approved"
    db.commit()

    return {"message": "Report approved"}


@app.put("/admin/reject/{report_id}")
def reject_report(report_id: int, db: Session = Depends(get_db)):

    report = db.query(models.Accident)\
        .filter(models.Accident.id == report_id)\
        .first()

    if not report:
        raise HTTPException(status_code=404, detail="Report not found")

    report.status = "rejected"
    db.commit()

    return {"message": "Report rejected"}


# 🟢 NEW: Partner Schema for validation
class PartnerCreate(BaseModel):
    name: str
    type: str
    email: str
    phone: str
    latitude: str
    longitude: str


# 🟢 NEW: Create Partner Route
@app.post("/admin/partners")
def create_partner(partner: PartnerCreate, db: Session = Depends(get_db)):
    try:
        # Check if email already exists
        existing_partner = db.query(models.Authority).filter(models.Authority.email == partner.email).first()
        if existing_partner:
            raise HTTPException(status_code=400, detail="Email already registered")

        new_auth = models.Authority(
            name=partner.name,
            type=partner.type,
            email=partner.email,
            phone=partner.phone,
            latitude=partner.latitude,
            longitude=partner.longitude
        )
        db.add(new_auth)
        db.commit()
        db.refresh(new_auth)
        return new_auth
    except Exception as e:
        db.rollback()
        print(f"DATABASE ERROR: {e}")
        raise HTTPException(status_code=500, detail=str(e))


# 🟢 NEW: Get Partners Route
@app.get("/admin/partners")
def get_partners(db: Session = Depends(get_db)):
    try:
        return db.query(models.Authority).all()
    except Exception as e:
        print(f"DATABASE ERROR: {e}")
        return []


# =====================================================
# 🟢 ADMIN: FIND NEARBY PARTNERS FOR DISPATCH
# =====================================================
@app.get("/admin/report/{report_id}/nearby-partners")
def get_nearby_partners(report_id: int, db: Session = Depends(get_db)):
    # 1. Get the accident location
    report = db.query(models.Accident).filter(models.Accident.id == report_id).first()
    if not report:
        raise HTTPException(status_code=404, detail="Report not found")
    
    # 2. Get all registered partners
    partners = db.query(models.Authority).all()
    
    nearby_partners = []
    for p in partners:
        # 3. Calculate distance using your existing Haversine function
        distance_meters = haversine_distance(
            float(report.latitude), float(report.longitude), 
            float(p.latitude), float(p.longitude)
        )
        
        nearby_partners.append({
            "id": p.id,
            "name": p.name,
            "type": p.type,
            "phone": p.phone,
            "email": p.email,
            "distance_km": round(distance_meters / 1000, 2) # Convert to KM
        })
        
    # 4. Sort the list so the closest partner is at the top
    nearby_partners.sort(key=lambda x: x["distance_km"])
    
    return nearby_partners


# =====================================================
# 🟢 NEW: PARTNER PORTAL OTP ADDITIONS
# =====================================================

# --- EMAIL CONFIGURATION FOR OTP ---
SMTP_SERVER = "smtp.gmail.com"
SMTP_PORT = 587
# ⚠️ ACTION REQUIRED: Update these credentials
SENDER_EMAIL = "safehorizon99@gmail.com" 
SENDER_PASSWORD = "pzgl vynx opqi ykvu"         

def send_otp_email(to_email: str, otp: str):
    msg = MIMEText(f"Emergency System Alert.\n\nYour Safe Horizon Partner Login OTP is: {otp}\n\nThis code is highly sensitive and will expire in 5 minutes.")
    msg['Subject'] = 'Safe Horizon - Secure Partner Login'
    msg['From'] = SENDER_EMAIL
    msg['To'] = to_email

    try:
        with smtplib.SMTP(SMTP_SERVER, SMTP_PORT) as server:
            server.starttls()
            server.login(SENDER_EMAIL, SENDER_PASSWORD)
            server.send_message(msg)
    except Exception as e:
        print(f"Failed to send email: {e}")
        raise HTTPException(status_code=500, detail="Failed to send OTP email. Check server logs.")

# --- OTP ENDPOINTS ---
@app.post("/partner/request-otp")
def request_otp(email: str, db: Session = Depends(get_db)):
    partner = db.query(models.Authority).filter(models.Authority.email == email).first()
    
    if not partner:
        raise HTTPException(status_code=404, detail="Authority account not found. Contact Admin.")

    otp = str(random.randint(100000, 999999))
    
    partner.otp_code = otp
    partner.otp_expires_at = datetime.utcnow() + timedelta(minutes=5)
    db.commit()

    send_otp_email(email, otp)
    
    return {"message": f"OTP sent successfully to {email}"}


@app.post("/partner/verify-otp")
def verify_otp(email: str, otp: str, db: Session = Depends(get_db)):
    partner = db.query(models.Authority).filter(models.Authority.email == email).first()
    
    if not partner:
        raise HTTPException(status_code=404, detail="Authority not found.")
        
    if partner.otp_code != otp:
        raise HTTPException(status_code=401, detail="Invalid OTP code.")
        
    if partner.otp_expires_at and partner.otp_expires_at < datetime.utcnow():
        raise HTTPException(status_code=401, detail="OTP has expired. Please request a new one.")

    partner.otp_code = None
    partner.otp_expires_at = None
    db.commit()

    return {
        "message": "Login successful",
        "partner_id": partner.id,
        "partner_name": partner.name,
        "partner_type": partner.type,
        "latitude": partner.latitude,
        "longitude": partner.longitude
    }


# =====================================================
# 🟢 LIVE DISPATCH ROUTING (ADMIN -> PARTNER)
# =====================================================

@app.put("/authority/assign/{report_id}/{partner_id}")
def assign_report_to_partner(report_id: int, partner_id: int, db: Session = Depends(get_db)):
    # 1. Find the accident report
    report = db.query(models.Accident).filter(models.Accident.id == report_id).first()
    if not report:
        raise HTTPException(status_code=404, detail="Accident report not found")

    # 2. Find the partner authority
    partner = db.query(models.Authority).filter(models.Authority.id == partner_id).first()
    if not partner:
        raise HTTPException(status_code=404, detail="Partner authority not found")

    # 3. Assign the report and update the status
    report.assigned_partner_id = partner.id
    report.status = "dispatched" # Changes from 'pending' to 'dispatched'
    db.commit()

    return {"message": f"Report #{report_id} successfully dispatched to {partner.name}"}


@app.get("/partner/{partner_id}/dispatches")
def get_partner_dispatches(partner_id: int, db: Session = Depends(get_db)):
    # Fetch all reports assigned to this specific partner that aren't resolved yet
    dispatches = db.query(models.Accident)\
        .filter(models.Accident.assigned_partner_id == partner_id)\
        .filter(models.Accident.status == "dispatched")\
        .all()
    
    return dispatches


# =====================================================
# 🟢 HELPER: DISTANCE CALCULATOR
# =====================================================
def haversine_distance(lat1, lon1, lat2, lon2):
    R = 6371000  # Radius of Earth in meters
    phi1, phi2 = math.radians(lat1), math.radians(lat2)
    delta_phi = math.radians(lat2 - lat1)
    delta_lambda = math.radians(lon2 - lon1)
    a = math.sin(delta_phi / 2.0) ** 2 + math.cos(phi1) * math.cos(phi2) * math.sin(delta_lambda / 2.0) ** 2
    c = 2 * math.atan2(math.sqrt(a), math.sqrt(1 - a))
    return R * c


# =====================================================
# 🟢 PARTNER PORTAL: UPLOAD DATA TO ADMIN DATABASE
# =====================================================

# 1. Single Manual Entry Upload
@app.post("/authority/{auth_id}/report")
def partner_report_accident(
    auth_id: int,
    latitude: str = Form(...),
    longitude: str = Form(...),
    severity: str = Form(...),
    description: str = Form("Verified Authority Report"),
    accident_datetime: str = Form(...),
    db: Session = Depends(get_db)
):
    partner = db.query(models.Authority).filter(models.Authority.id == auth_id).first()
    if not partner:
        raise HTTPException(status_code=404, detail="Partner not found")

    new_accident = models.Accident(
        user_email=partner.email, # Tag the upload with the partner's email
        latitude=latitude,
        longitude=longitude,
        severity=severity,
        description=description,
        accident_datetime=accident_datetime,
        status="approved" # Auto-approve trusted data
    )
    db.add(new_accident)
    db.commit()
    
    return {"message": "Data successfully uploaded to the Admin Database."}

# 2. Bulk CSV Upload
@app.post("/authority/{auth_id}/upload-csv")
async def partner_upload_csv(auth_id: int, file: UploadFile = File(...), db: Session = Depends(get_db)):
    if not file.filename.endswith('.csv'):
        raise HTTPException(status_code=400, detail="Only CSV files are allowed")
    
    partner = db.query(models.Authority).filter(models.Authority.id == auth_id).first()
    if not partner:
        raise HTTPException(status_code=404, detail="Partner not found")

    contents = await file.read()
    df = pd.read_csv(StringIO(contents.decode("utf-8")))
    
    inserted_records = 0
    for _, row in df.iterrows():
        raw_sev = str(row.get('severity', 'Minor')).strip()
        sev = 'Critical' if 'Fatal' in raw_sev else 'Major' if 'Grievous' in raw_sev else 'Minor'
        
        acc = models.Accident(
            user_email=partner.email, # Tag the upload
            latitude=str(row['latitude']),
            longitude=str(row['longitude']),
            severity=sev,
            description=str(row.get('description', 'Bulk CSV Upload')),
            accident_datetime=str(row.get('datetime', datetime.now().strftime("%b %d, %Y"))),
            status="approved"
        )
        db.add(acc)
        inserted_records += 1
        
    db.commit()
    return {"message": f"Successfully uploaded {inserted_records} verified records to the Admin Database."}

# 3. Admin Route to View Partner Contributions
@app.get("/admin/partner/{auth_id}/data")
def get_partner_uploaded_data(auth_id: int, db: Session = Depends(get_db)):
    partner = db.query(models.Authority).filter(models.Authority.id == auth_id).first()
    if not partner:
        return []
        
    # Find all accidents where the user_email matches the partner's email
    reports = db.query(models.Accident).filter(models.Accident.user_email == partner.email).all()
    return reports


# =====================================================
# 🟢 ADMIN: MANUALLY ADD RECORD & ANALYTICS
# =====================================================

@app.post("/admin/report")
def admin_manual_add_report(
    latitude: str = Form(...),
    longitude: str = Form(...),
    severity: str = Form(...),
    description: str = Form("Manually added by Admin"),
    accident_datetime: str = Form(...),
    db: Session = Depends(get_db)
):
    # Auto-approve since it is entered by the Admin
    new_accident = models.Accident(
        user_email="admin_manual_entry@safehorizon.com", 
        latitude=latitude,
        longitude=longitude,
        severity=severity,
        description=description,
        accident_datetime=accident_datetime,
        status="approved" 
    )
    db.add(new_accident)
    db.commit()
    
    return {"message": "Record manually added to the system successfully."}


@app.get("/admin/analytics")
def get_admin_analytics(db: Session = Depends(get_db)):
    # 1. Overview Cards Data
    total_reports = db.query(models.Accident).count()
    pending_reports = db.query(models.Accident).filter(models.Accident.status == "pending").count()
    total_partners = db.query(models.Authority).count()
    
    # 2. Severity Distribution for Doughnut Chart
    minor_count = db.query(models.Accident).filter(models.Accident.severity == "Minor").count()
    major_count = db.query(models.Accident).filter(models.Accident.severity == "Major").count()
    critical_count = db.query(models.Accident).filter(models.Accident.severity == "Critical").count()

    # Return structured data for Chart.js
    return {
        "overview": {
            "total_reports": total_reports,
            "pending_action": pending_reports,
            "active_partners": total_partners,
        },
        "severity_chart": [minor_count, major_count, critical_count]
    }


# =====================================================
# 🟢 ACCIDENT-PRONE ZONE PREDICTION API (UPDATED WITH DATA)
# =====================================================
@app.get("/api/accident-zones")
def get_accident_zones(db: Session = Depends(get_db)):
    # 1. Fetch only approved reports from the database
    accidents = db.query(models.Accident).filter(models.Accident.status == "approved").all()
    if not accidents:
        return []

    # 2. Clean the data
    data = []
    for a in accidents:
        try:
            data.append({
                "id": a.id, 
                "lat": float(a.latitude), 
                "lon": float(a.longitude), 
                "severity": a.severity,
                "datetime": a.accident_datetime, # 🟢 Added for UI
                "desc": a.description            # 🟢 Added for UI
            })
        except ValueError:
            continue
            
    if not data:
        return []
            
    df = pd.DataFrame(data)

    # 3. Assign Risk Weights based exactly on your Flutter app categories
    severity_weights = {
        "Critical": 3.0,
        "Major": 2.0,
        "Minor": 1.0
    }
    
    # Map weights. Fill unknown/missing categories with a base value of 1.0
    df['weight'] = df['severity'].map(severity_weights).fillna(1.0)

    # 4. Run the AI Clustering Algorithm
    epsilon_in_radians = (300 / 1000) / 6371.0 # 300 meters search radius
    coords = np.radians(df[['lat', 'lon']].values)

    # Group accidents if there are at least 10 within 300 meters
    dbscan = DBSCAN(eps=epsilon_in_radians, min_samples=10, algorithm='ball_tree', metric='haversine')
    df['cluster'] = dbscan.fit_predict(coords)

    # 5. Process the results into Zones
    zones = []
    for cluster_id in df['cluster'].unique():
        if cluster_id == -1: 
            continue # Skip noise (isolated incidents not near others)

        cluster_points = df[df['cluster'] == cluster_id]
        
        # Find geographic center of the cluster
        center_lat = cluster_points['lat'].mean()
        center_lon = cluster_points['lon'].mean()
        
        # Calculate cluster severity score
        total_score = cluster_points['weight'].sum()
        accident_count = len(cluster_points)

        # Categorize Risk
        if total_score >= 20: 
            risk_level = "High"
        elif total_score >= 10: 
            risk_level = "Medium"
        else: 
            risk_level = "Low"

        # Find the max distance from center to calculate a radius
        max_dist = 0
        for _, row in cluster_points.iterrows():
            dist = haversine_distance(center_lat, center_lon, row['lat'], row['lon'])
            if dist > max_dist: 
                max_dist = dist
                
        # Buffer of 50m padding. Minimum circle size 150m.
        radius = max(max_dist + 50, 150) 

        # --- 🟢 Extract the Micro-Hotspots for this Zone ---
        micro_hotspots = []
        for _, row in cluster_points.iterrows():
            micro_hotspots.append({
                "hotspot_id": int(row['id']),
                "lat": float(row['lat']),
                "lng": float(row['lon']),
                "severity": row['severity'],
                "datetime": row['datetime'], # <-- Passed to UI
                "desc": row['desc'],         # <-- Passed to UI
                "radius_meters": 50 # 50m tight radius for the specific accident point
            })

        zones.append({
            "zone_id": int(cluster_id),
            "center_lat": center_lat,
            "center_lon": center_lon,
            "radius_meters": radius,
            "risk_level": risk_level,
            "score": int(total_score),
            "accident_count": int(accident_count),
            "micro_hotspots": micro_hotspots # <-- Added to the response
        })

    return zones