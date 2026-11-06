from fastapi import APIRouter, Depends, HTTPException, status
from sqlalchemy import select
from sqlalchemy.exc import IntegrityError
from sqlalchemy.orm import Session

from app.database import get_db
from app.dependencies import get_current_user
from app.models import Bike, GPSDevice, User
from app.schemas import (
    BikeCreateRequest,
    BikeGpsRequest,
    BikeResponse,
    BikeUpdateRequest,
)

router = APIRouter(prefix="/api/v1/bikes", tags=["bikes"])


@router.get("", response_model=list[BikeResponse])
def list_bikes(
    db: Session = Depends(get_db),
    _: User = Depends(get_current_user),
) -> list[BikeResponse]:
    bikes = db.scalars(select(Bike).order_by(Bike.bike_number)).all()
    return [_bike_response(db, bike) for bike in bikes]


@router.post(
    "",
    response_model=BikeResponse,
    status_code=status.HTTP_201_CREATED,
)
def create_bike(
    payload: BikeCreateRequest,
    db: Session = Depends(get_db),
    _: User = Depends(get_current_user),
) -> BikeResponse:
    bike = Bike(name=payload.name, bike_number=payload.bike_number)
    db.add(bike)
    try:
        db.commit()
    except IntegrityError:
        db.rollback()
        if _bike_number_exists(db, payload.bike_number):
            raise HTTPException(
                status_code=status.HTTP_409_CONFLICT,
                detail="No. sepeda sudah terdaftar",
            ) from None
        raise

    db.refresh(bike)
    return _bike_response(db, bike)


@router.put("/{bike_id}", response_model=BikeResponse)
def update_bike(
    bike_id: int,
    payload: BikeUpdateRequest,
    db: Session = Depends(get_db),
    _: User = Depends(get_current_user),
) -> BikeResponse:
    bike = _get_bike(db, bike_id)
    bike.name = payload.name
    bike.bike_number = payload.bike_number
    try:
        db.commit()
    except IntegrityError:
        db.rollback()
        if _bike_number_exists(db, payload.bike_number, exclude_id=bike_id):
            raise HTTPException(
                status_code=status.HTTP_409_CONFLICT,
                detail="No. sepeda sudah terdaftar",
            ) from None
        raise

    db.refresh(bike)
    return _bike_response(db, bike)


@router.put("/{bike_id}/gps", response_model=BikeResponse)
def connect_gps(
    bike_id: int,
    payload: BikeGpsRequest,
    db: Session = Depends(get_db),
    _: User = Depends(get_current_user),
) -> BikeResponse:
    bike = _get_bike(db, bike_id)
    gps_device = db.scalar(
        select(GPSDevice).where(
            GPSDevice.gps_code == payload.gps_code,
            GPSDevice.is_active.is_(True),
        )
    )
    if gps_device is None:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail="Kode GPS belum didaftarkan atau sedang nonaktif",
        )
    bike.gps_code = payload.gps_code
    try:
        db.commit()
    except IntegrityError:
        db.rollback()
        if db.scalar(
            select(Bike.id).where(
                Bike.gps_code == payload.gps_code,
                Bike.id != bike_id,
            )
        ):
            raise HTTPException(
                status_code=status.HTTP_409_CONFLICT,
                detail="Kode GPS sudah terhubung ke sepeda lain",
            ) from None
        raise

    db.refresh(bike)
    return _bike_response(db, bike)


@router.delete("/{bike_id}/gps", response_model=BikeResponse)
def disconnect_gps(
    bike_id: int,
    db: Session = Depends(get_db),
    _: User = Depends(get_current_user),
) -> BikeResponse:
    bike = _get_bike(db, bike_id)
    bike.gps_code = None
    bike.latitude = None
    bike.longitude = None
    db.commit()
    db.refresh(bike)
    return _bike_response(db, bike)


@router.delete("/{bike_id}", status_code=status.HTTP_204_NO_CONTENT)
def delete_bike(
    bike_id: int,
    db: Session = Depends(get_db),
    _: User = Depends(get_current_user),
) -> None:
    bike = _get_bike(db, bike_id)
    db.delete(bike)
    db.commit()


def _get_bike(db: Session, bike_id: int) -> Bike:
    bike = db.get(Bike, bike_id)
    if bike is None:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail="Sepeda tidak ditemukan",
        )
    return bike


def _bike_number_exists(
    db: Session,
    bike_number: str,
    *,
    exclude_id: int | None = None,
) -> bool:
    query = select(Bike.id).where(Bike.bike_number == bike_number)
    if exclude_id is not None:
        query = query.where(Bike.id != exclude_id)
    return db.scalar(query) is not None


def _bike_response(db: Session, bike: Bike) -> BikeResponse:
    gps_device = (
        db.scalar(select(GPSDevice).where(GPSDevice.gps_code == bike.gps_code))
        if bike.gps_code is not None
        else None
    )
    return BikeResponse(
        id=bike.id,
        name=bike.name,
        bike_number=bike.bike_number,
        gps_code=bike.gps_code,
        latitude=gps_device.latitude if gps_device and gps_device.is_active else None,
        longitude=(
            gps_device.longitude if gps_device and gps_device.is_active else None
        ),
    )
