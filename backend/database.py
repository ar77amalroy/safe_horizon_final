from sqlalchemy import create_engine
from sqlalchemy.orm import sessionmaker, declarative_base

# Just remember to replace YOUR_GENERATED_PASSWORD with the password you generated earlier!
DATABASE_URL = "mysql+pymysql://2K3gYUe4LSEWSLX.root:rOPczS0IsBGtYz4I@gateway01.ap-northeast-1.prod.aws.tidbcloud.com:4000/test?ssl_verify_cert=true&ssl_verify_identity=true"

engine = create_engine(DATABASE_URL)

SessionLocal = sessionmaker(autocommit=False, autoflush=False, bind=engine)

Base = declarative_base()