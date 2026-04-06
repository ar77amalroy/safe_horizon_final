from fastapi import APIRouter, Depends, HTTPException
from sqlalchemy.orm import Session
from database import get_db
import models
from pydantic import BaseModel
import os

router = APIRouter(prefix="/admin", tags=["Admin"])

# -------------------------
# 🔐 LOGIN SCHEMA
# -------------------------
class AdminLogin(BaseModel):
    email: str
    password: str


# -------------------------
# 🔐 ADMIN LOGIN
# -------------------------
@router.post("/login")
def admin_login(data: AdminLogin):
    admin_email = os.getenv("ADMIN_EMAIL")
    admin_password = os.getenv("ADMIN_PASSWORD")

    if data.email == admin_email and data.password == admin_password:
        return {
            "access_token": "admin_token",
            "message": "Login successful"
        }

    raise HTTPException(status_code=401, detail="Invalid credentials")


# -------------------------
# 📊 GET ALL ACCIDENT REPORTS
# -------------------------
@router.get("/reports")
def get_all_reports(db: Session = Depends(get_db)):
    reports = db.query(models.Accident).order_by(models.Accident.id.desc()).all()

    result = []
    for r in reports:
        result.append({
            "id": r.id,
            "latitude": float(r.latitude),
            "longitude": float(r.longitude),
            "severity": r.severity,
            "description": r.description,
            "status": r.status,
            "reported_at": r.accident_datetime,
            "assigned_authority_id": r.assigned_authority_id
        })

    return result


# -------------------------
# 📌 ASSIGN TO AUTHORITY
# -------------------------
@router.put("/assign/{report_id}/{auth_id}")
def assign_report(report_id: int, auth_id: int, db: Session = Depends(get_db)):
    report = db.query(models.Accident).filter(models.Accident.id == report_id).first()

    if not report:
        raise HTTPException(status_code=404, detail="Report not found")

    report.assigned_authority_id = auth_id
    report.status = "assigned_to_auth"
    db.commit()

    return {"message": "Assigned successfully"}