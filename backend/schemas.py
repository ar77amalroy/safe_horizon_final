from pydantic import BaseModel, EmailStr, Field


# =====================================================
# STEP 1: REGISTER (NAME + EMAIL + OPTIONAL PHONE)
# =====================================================
class UserCreate(BaseModel):
    name: str
    email: EmailStr
    phone: str | None = None   # optional phone number


# =====================================================
# STEP 2: VERIFY EMAIL OTP
# =====================================================
class VerifyEmail(BaseModel):
    email: EmailStr
    code: str


# =====================================================
# STEP 3: CREATE PASSWORD AFTER VERIFICATION
# =====================================================
class SetPassword(BaseModel):
    email: EmailStr
    # Restrict to 72 chars to prevent Bcrypt ValueError
    password: str = Field(..., max_length=72)


# =====================================================
# LOGIN
# =====================================================
class UserLogin(BaseModel):
    email: EmailStr
    # Restrict login payload as well for safety
    password: str = Field(..., max_length=72)


# =====================================================
# FORGOT PASSWORD FLOW
# =====================================================

# Request password reset (enter email)
class ForgotPassword(BaseModel):
    email: EmailStr


# Verify reset OTP
class VerifyResetCode(BaseModel):
    email: EmailStr
    code: str


# Create new password
class ResetPassword(BaseModel):
    email: EmailStr
    # Restrict to 72 chars to prevent Bcrypt ValueError
    password: str = Field(..., max_length=72)