import os
import resend


async def send_verification_email(email: str, code: str):
    resend_key = os.getenv("RESEND_API_KEY", "")

    if resend_key:
        # Use Resend HTTP API (works on Render — SMTP is blocked)
        try:
            resend.api_key = resend_key
            r = resend.Emails.send({
                "from": "onboarding@resend.dev",
                "to": [email],
                "subject": "Safe Horizon Email Verification",
                "text": f"Your Safe Horizon verification code is:\n\n{code}\n\nThis code expires in 5 minutes."
            })
            print(f"✅ Verification email sent via Resend to {email}", flush=True)
        except Exception as e:
            print(f"❌ Resend verification email failed: {e}", flush=True)
    else:
        # Fallback: use fastapi-mail SMTP (works locally)
        try:
            from fastapi_mail import FastMail, MessageSchema
            from email_config import conf

            message = MessageSchema(
                subject="Safe Horizon Email Verification",
                recipients=[email],
                body=f"Your Safe Horizon verification code is:\n\n{code}\n\nThis code expires in 5 minutes.",
                subtype="plain"
            )
            fm = FastMail(conf)
            await fm.send_message(message)
            print(f"✅ Verification email sent via SMTP to {email}")
        except Exception as e:
            print(f"❌ SMTP verification email failed: {e}")