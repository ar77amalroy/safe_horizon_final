from database import engine
import models

print("Dropping all old strict tables...")
models.Base.metadata.drop_all(bind=engine)

print("Building new relaxed tables...")
models.Base.metadata.create_all(bind=engine)

print("✅ Tables reset successfully! Remember to run import_data.py next.")