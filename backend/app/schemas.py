from pydantic import BaseModel, ConfigDict, EmailStr, Field, field_validator


class RegisterRequest(BaseModel):
    full_name: str = Field(min_length=1, max_length=120)
    username: str = Field(min_length=3, max_length=32, pattern=r"^[a-zA-Z0-9_.-]+$")
    email: EmailStr
    password: str = Field(min_length=8, max_length=128)

    @field_validator("full_name", "username", mode="before")
    @classmethod
    def strip_text(cls, value: object) -> object:
        return value.strip() if isinstance(value, str) else value

    @field_validator("username", mode="after")
    @classmethod
    def normalize_username(cls, value: str) -> str:
        return value.lower()

    @field_validator("email", mode="before")
    @classmethod
    def normalize_email(cls, value: object) -> object:
        return value.strip().lower() if isinstance(value, str) else value


class LoginRequest(BaseModel):
    identifier: str = Field(min_length=1, max_length=255)
    password: str = Field(min_length=1, max_length=128)

    @field_validator("identifier", mode="before")
    @classmethod
    def strip_identifier(cls, value: object) -> object:
        return value.strip() if isinstance(value, str) else value


class UserResponse(BaseModel):
    id: int
    full_name: str
    username: str
    email: EmailStr

    model_config = ConfigDict(from_attributes=True)


class AuthResponse(BaseModel):
    access_token: str
    token_type: str = "bearer"
    user: UserResponse


class BikeCreateRequest(BaseModel):
    name: str = Field(min_length=1, max_length=120)
    bike_number: str = Field(pattern=r"^\d{4}$")

    @field_validator("name", mode="before")
    @classmethod
    def strip_bike_name(cls, value: object) -> object:
        return value.strip() if isinstance(value, str) else value


class BikeUpdateRequest(BikeCreateRequest):
    pass


class BikeGpsRequest(BaseModel):
    gps_code: str = Field(min_length=1, max_length=120)

    @field_validator("gps_code", mode="before")
    @classmethod
    def strip_gps_code(cls, value: object) -> object:
        return value.strip().upper() if isinstance(value, str) else value


class GPSDeviceCreateRequest(BaseModel):
    gps_code: str = Field(min_length=1, max_length=120)

    @field_validator("gps_code", mode="before")
    @classmethod
    def normalize_gps_code(cls, value: object) -> object:
        return value.strip().upper() if isinstance(value, str) else value


class GPSDeviceResponse(BaseModel):
    id: int
    gps_code: str
    latitude: float
    longitude: float
    is_active: bool
    connected_bike_number: str | None = None

    model_config = ConfigDict(from_attributes=True)


class BikeResponse(BaseModel):
    id: int
    name: str
    bike_number: str
    gps_code: str | None
    latitude: float | None
    longitude: float | None

    model_config = ConfigDict(from_attributes=True)
