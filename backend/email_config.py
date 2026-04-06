from fastapi_mail import ConnectionConfig
import os

conf = ConnectionConfig(
    MAIL_USERNAME=os.getenv("MAIL_USERNAME"),
    MAIL_PASSWORD=os.getenv("MAIL_PASSWORD"),
    MAIL_FROM=os.getenv("MAIL_FROM"),

    MAIL_SERVER=os.getenv("MAIL_SERVER", "smtp.gmail.com"),
    MAIL_PORT=int(os.getenv("MAIL_PORT", 465)),

    MAIL_STARTTLS=False,
    MAIL_SSL_TLS=True,

    USE_CREDENTIALS=True,
    VALIDATE_CERTS=True
)