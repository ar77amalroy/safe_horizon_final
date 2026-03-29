from sqlalchemy import Column, Integer, String, Boolean, DateTime
from database import Base

# =====================================================
# USER TABLE
# =====================================================
class User(Base):
    __tablename__ = "users"

    id = Column(Integer, primary_key=True, index=True)

    # user basic info
    name = Column(String(100), nullable=False)

    # OPTIONAL PHONE NUMBER
    phone = Column(String(20), nullable=True)

    # credentials
    email = Column(String(100), unique=True, index=True, nullable=False)
    password = Column(String(255), nullable=False)

    # ✅ PROFILE IMAGE (NEW - PERMANENT STORAGE)
    profile_image = Column(String(255), nullable=True)

    # email verification
    is_verified = Column(Boolean, default=False)
    verification_code = Column(String(10), nullable=True)
    code_expiry = Column(DateTime, nullable=True)


# =====================================================
# ACCIDENT REPORT TABLE
# =====================================================
class Accident(Base):
    __tablename__ = "accidents"

    id = Column(Integer, primary_key=True, index=True)

    # reporter info
    user_email = Column(String(100), nullable=False)

    # location coordinates
    latitude = Column(String(50), nullable=False)
    longitude = Column(String(50), nullable=False)

    # accident details
    severity = Column(String(20), nullable=False)
    description = Column(String(255), nullable=True)

    # stored image file path (not the image itself)
    image_path = Column(String(255), nullable=True)

    # selected accident date & time
    accident_datetime = Column(String(100), nullable=False)

    # ADMIN CONFIRMATION STATUS
    # pending = waiting for admin review
    # approved = confirmed accident
    # rejected = invalid report
    status = Column(String(20), default="pending", nullable=False)

    # ✅ ASSIGNED PARTNER TRACKING (NEW)
    # Links this specific accident to a dispatched hospital/police station
    assigned_partner_id = Column(Integer, nullable=True)


# =====================================================
# AUTHORITY / PARTNER TABLE
# =====================================================
class Authority(Base):
    __tablename__ = "authorities"

    id = Column(Integer, primary_key=True, index=True)
    
    # Partner basic info
    name = Column(String(100), nullable=False)
    type = Column(String(50), nullable=False)  # e.g., police, hospital, fire
    
    # Contact and login
    email = Column(String(100), unique=True, index=True, nullable=False)
    phone = Column(String(20), nullable=False)
    
    # Location for proximity dispatching
    latitude = Column(String(50), nullable=False)
    longitude = Column(String(50), nullable=False)

    # ✅ OTP VERIFICATION FOR PARTNER LOGIN
    otp_code = Column(String(6), nullable=True)
    otp_expires_at = Column(DateTime, nullable=True)