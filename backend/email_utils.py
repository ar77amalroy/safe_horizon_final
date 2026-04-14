import os


async def send_verification_email(email: str, code: str):
    # Primary: use fastapi-mail SMTP (works locally)
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
        print(f"[OK] Verification email sent via SMTP to {email}")
    except Exception as e:
        print(f"[WARN] SMTP failed: {e}, trying Resend fallback...", flush=True)
        # Fallback: use Resend HTTP API
        try:
            import resend

            if email.lower() == "alanroy2007appu@gmail.com":
                resend_key = os.getenv("RESEND_API_KEY_ALAN", "")
            else:
                resend_key = os.getenv("RESEND_API_KEY", "")

            if not resend_key:
                print(f"[ERR] No Resend API key set, email not sent to {email}", flush=True)
                return

            resend.api_key = resend_key
            r = resend.Emails.send({
                "from": "onboarding@resend.dev",
                "to": [email],
                "subject": "Safe Horizon Email Verification",
                "text": f"Your Safe Horizon verification code is:\n\n{code}\n\nThis code expires in 5 minutes."
            })
            print(f"[OK] Verification email sent via Resend to {email}", flush=True)
        except Exception as e2:
            print(f"[ERR] Both SMTP and Resend failed: {e2}", flush=True)