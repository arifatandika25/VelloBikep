from fastapi import APIRouter, Depends, HTTPException, status
from sqlalchemy import select
from sqlalchemy.exc import IntegrityError
from sqlalchemy.orm import Session

from app.database import get_db
from app.dependencies import get_current_user
from app.models import Bike, GPSDevice, User
from app.schemas import GPSDeviceCreateRequest, GPSDeviceResponse

router = APIRouter(prefix="/api/v1/gps", tags=["gps"])

_YOGYAKARTA_TEST_LOCATIONS = (
    (-7.7956, 110.3695),
    (-7.8014, 110.3647),
    (-7.7883, 110.3669),
    (-7.8001, 110.3751),
    (-7.7898, 110.3762),
    (-7.8062, 110.3674),
    (-7.7839, 110.3708),
    (-7.7985, 110.3592),
)


@router.get("", response_model=list[GPSDeviceResponse])
def list_gps_devices(
    db: Session = Depends(get_db),
    _: User = Depends(get_current_user),
) -> list[GPSDeviceResponse]:
    devices = db.scalars(select(GPSDevice).order_by(GPSDevice.gps_code)).all()
    bikes_by_gps = {
        bike.gps_code: bike.bike_number
        for bike in db.scalars(select(Bike).where(Bike.gps_code.is_not(None))).all()
    }
    return [
        GPSDeviceResponse(
            id=device.id,
            gps_code=device.gps_code,
            latitude=device.latitude,
            longitude=device.longitude,
            is_active=device.is_active,
            connected_bike_number=bikes_by_gps.get(device.gps_code),
        )
        for device in devices
    ]


@router.post(
    "",
    response_model=GPSDeviceResponse,
    status_code=status.HTTP_201_CREATED,
)
def register_gps_device(
    payload: GPSDeviceCreateRequest,
    db: Session = Depends(get_db),
    _: User = Depends(get_current_user),
) -> GPSDeviceResponse:
    location_index = sum(payload.gps_code.encode("utf-8")) % len(
        _YOGYAKARTA_TEST_LOCATIONS
    )
    latitude, longitude = _YOGYAKARTA_TEST_LOCATIONS[location_index]
    device = GPSDevice(
        gps_code=payload.gps_code,
        latitude=latitude,
        longitude=longitude,
        is_active=True,
    )
    db.add(device)
    try:
        db.commit()
    except IntegrityError:
        db.rollback()
        if db.scalar(
            select(GPSDevice.id).where(GPSDevice.gps_code == payload.gps_code)
        ):
            raise HTTPException(
                status_code=status.HTTP_409_CONFLICT,
                detail="Kode GPS sudah terdaftar",
            ) from None
        raise

    db.refresh(device)
    return GPSDeviceResponse.model_validate(device)


@router.delete("/{gps_id}", status_code=status.HTTP_204_NO_CONTENT)
def delete_gps_device(
    gps_id: int,
    db: Session = Depends(get_db),
    _: User = Depends(get_current_user),
) -> None:
    device = db.get(GPSDevice, gps_id)
    if device is None:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail="Perangkat GPS tidak ditemukan",
        )
    if db.scalar(select(Bike.id).where(Bike.gps_code == device.gps_code)):
        raise HTTPException(
            status_code=status.HTTP_409_CONFLICT,
            detail="Lepaskan GPS dari sepeda sebelum menghapus kode GPS",
        )
    db.delete(device)
    db.commit()
