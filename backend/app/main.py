from contextlib import asynccontextmanager
import re

from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware

from app.config import get_settings
from app.database import Base, engine
from app.migrations import migrate_bikes_table
from app.models import Bike, GPSDevice, User  # noqa: F401
from app.routes.auth import router as auth_router
from app.routes.bikes import router as bikes_router
from app.routes.gps import router as gps_router


@asynccontextmanager
async def lifespan(_: FastAPI):
    get_settings()
    Base.metadata.create_all(bind=engine)
    migrate_bikes_table()
    yield


app = FastAPI(title="VeloBike API", version="1.0.0", lifespan=lifespan)
app.add_middleware(
    CORSMiddleware,
    allow_origin_regex=re.compile(r"https?://(localhost|127\.0\.0\.1)(:\d+)?"),
    allow_credentials=False,
    allow_methods=["GET", "POST", "PUT", "DELETE"],
    allow_headers=["Content-Type", "Authorization"],
)
app.include_router(auth_router)
app.include_router(bikes_router)
app.include_router(gps_router)


@app.get("/health")
def health() -> dict[str, str]:
    return {"status": "ok"}
