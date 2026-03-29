from fastapi import APIRouter, Depends, HTTPException, Request
from sqlalchemy.orm import Session
from database import get_db
import models

router = APIRouter(prefix="/authority", tags=["Local Authority Portal"])

@router.put("/assign/{report_id}/{auth_id}")
def assign_report_to_authority(report_id: int, auth_id: int, db: Session = Depends(get_db)):
    report = db.query(models.Accident).filter(models.Accident.id == report_id).first()
    if not report: raise HTTPException(status_code=404, detail="Report not found")
    
    report.assigned_authority_id = auth_id
    report.status = "assigned_to_auth" 
    db.commit()
    return {"message": "Case assigned to Local Authority successfully"}

@router.get("/{auth_id}/cases")
def get_authority_cases(auth_id: int, request: Request, db: Session = Depends(get_db)):
    reports = db.query(models.Accident).filter(models.Accident.assigned_authority_id == auth_id).order_by(models.Accident.id.desc()).all()
    result = []
    for r in reports:
        result.append({
            "id": r.id, "latitude": float(r.latitude), "longitude": float(r.longitude),
            "severity": r.severity, "description": r.description, "status": r.status, "reported_at": r.accident_datetime
        })
    return result

@router.put("/verify/{report_id}/{action}")
def verify_case(report_id: int, action: str, db: Session = Depends(get_db)):
    report = db.query(models.Accident).filter(models.Accident.id == report_id).first()
    if not report: raise HTTPException(status_code=404, detail="Report not found")
    
    if action == "approve": report.status = "approved" 
    elif action == "reject": report.status = "rejected" 
        
    db.commit()
    return {"message": f"Case successfully {action}d"}