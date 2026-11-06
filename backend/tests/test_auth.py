import os
import sqlite3
import tempfile

_test_database_directory = tempfile.TemporaryDirectory()
os.environ["DATABASE_URL"] = (
    f"sqlite:///{_test_database_directory.name.replace(os.sep, '/')}/test.db"
)
os.environ["JWT_SECRET_KEY"] = "test-secret-key-with-at-least-32-characters"
os.environ["ALLOW_PUBLIC_REGISTRATION"] = "true"

from fastapi.testclient import TestClient
from sqlalchemy.exc import OperationalError
from sqlalchemy.orm import Session

from app.database import Base, SessionLocal, engine
from app.main import app
from app.migrations import migrate_bikes_table
from app.models import User


def setup_function() -> None:
    Base.metadata.drop_all(bind=engine)
    Base.metadata.create_all(bind=engine)


def teardown_function() -> None:
    engine.dispose()


def _bike_auth_headers(client: TestClient) -> dict[str, str]:
    credentials = {
        "full_name": "Bike Admin",
        "username": "bikeadmin",
        "email": "bikeadmin@example.com",
        "password": "secure-pass-123",
    }
    assert client.post("/api/v1/auth/register", json=credentials).status_code == 201
    login = client.post(
        "/api/v1/auth/login",
        json={"identifier": credentials["username"], "password": credentials["password"]},
    )
    return {"Authorization": f"Bearer {login.json()['access_token']}"}


def test_register_and_login_with_email_or_username() -> None:
    with TestClient(app) as client:
        registration = client.post(
            "/api/v1/auth/register",
            json={
                "full_name": "Admin Velo",
                "username": "adminvelo",
                "email": "admin@example.com",
                "password": "secure-pass-123",
            },
        )
        assert registration.status_code == 201
        assert registration.json()["email"] == "admin@example.com"

        for identifier in ("admin@example.com", "adminvelo", "ADMINVELO"):
            response = client.post(
                "/api/v1/auth/login",
                json={"identifier": identifier, "password": "secure-pass-123"},
            )
            assert response.status_code == 200
            assert response.json()["user"]["username"] == "adminvelo"
            assert response.json()["access_token"]


def test_register_rejects_duplicate_username() -> None:
    with TestClient(app) as client:
        payload = {
            "full_name": "Admin Velo",
            "username": "adminvelo",
            "email": "admin@example.com",
            "password": "secure-pass-123",
        }
        assert client.post("/api/v1/auth/register", json=payload).status_code == 201

        duplicate = {
            **payload,
            "username": "ADMINVELO",
            "email": "other@example.com",
        }
        response = client.post("/api/v1/auth/register", json=duplicate)

    assert response.status_code == 409


def test_registration_can_be_disabled(monkeypatch) -> None:
    monkeypatch.setenv("ALLOW_PUBLIC_REGISTRATION", "false")
    with TestClient(app) as client:
        response = client.post(
            "/api/v1/auth/register",
            json={
                "full_name": "Admin Velo",
                "username": "adminvelo",
                "email": "admin@example.com",
                "password": "secure-pass-123",
            },
        )

    assert response.status_code == 403


def test_login_rejects_invalid_password() -> None:
    with TestClient(app) as client:
        client.post(
            "/api/v1/auth/register",
            json={
                "full_name": "Admin Velo",
                "username": "adminvelo",
                "email": "admin@example.com",
                "password": "secure-pass-123",
            },
        )
        response = client.post(
            "/api/v1/auth/login",
            json={"identifier": "adminvelo", "password": "wrong-password"},
        )

    assert response.status_code == 401
    assert response.json()["detail"] == "Email/username atau kata sandi salah"


def test_login_rejects_unrecognized_password_hash() -> None:
    with TestClient(app) as client:
        client.post(
            "/api/v1/auth/register",
            json={
                "full_name": "Admin Velo",
                "username": "adminvelo",
                "email": "admin@example.com",
                "password": "secure-pass-123",
            },
        )
        with SessionLocal() as db:
            user = db.query(User).filter_by(username="adminvelo").one()
            user.password_hash = "not-a-supported-password-hash"
            db.commit()

        response = client.post(
            "/api/v1/auth/login",
            json={"identifier": "adminvelo", "password": "secure-pass-123"},
        )

    assert response.status_code == 401
    assert response.json()["detail"] == "Email/username atau kata sandi salah"


def test_register_returns_retryable_error_when_database_is_locked(
    monkeypatch,
) -> None:
    def raise_locked_error(self) -> None:
        raise OperationalError(
            "INSERT INTO users",
            {},
            sqlite3.OperationalError("database is locked"),
        )

    monkeypatch.setattr(Session, "commit", raise_locked_error)
    with TestClient(app) as client:
        response = client.post(
            "/api/v1/auth/register",
            json={
                "full_name": "Admin Velo",
                "username": "adminvelo",
                "email": "admin@example.com",
                "password": "secure-pass-123",
            },
        )

    assert response.status_code == 503
    assert response.headers["retry-after"] == "2"
    assert "Database sedang digunakan" in response.json()["detail"]


def test_create_and_list_bikes_preserves_four_digit_number() -> None:
    with TestClient(app) as client:
        headers = _bike_auth_headers(client)
        created = client.post(
            "/api/v1/bikes",
            json={"name": "Sepeda Kota", "bike_number": "0001"},
            headers=headers,
        )
        listed = client.get("/api/v1/bikes", headers=headers)

    assert created.status_code == 201
    assert created.json()["name"] == "Sepeda Kota"
    assert created.json()["bike_number"] == "0001"
    assert created.json()["gps_code"] is None
    assert listed.status_code == 200
    assert listed.json() == [created.json()]


def test_create_bike_rejects_duplicate_number() -> None:
    with TestClient(app) as client:
        headers = _bike_auth_headers(client)
        payload = {"name": "Sepeda Kota", "bike_number": "0001"}
        assert (
            client.post("/api/v1/bikes", json=payload, headers=headers).status_code
            == 201
        )
        duplicate = client.post("/api/v1/bikes", json=payload, headers=headers)

    assert duplicate.status_code == 409
    assert duplicate.json()["detail"] == "No. sepeda sudah terdaftar"


def test_create_bike_requires_exactly_four_digits() -> None:
    with TestClient(app) as client:
        headers = _bike_auth_headers(client)
        short_number = client.post(
            "/api/v1/bikes",
            json={"name": "Sepeda", "bike_number": "001"},
            headers=headers,
        )
        non_numeric = client.post(
            "/api/v1/bikes",
            json={"name": "Sepeda", "bike_number": "0A01"},
            headers=headers,
        )
        missing_name = client.post(
            "/api/v1/bikes",
            json={"bike_number": "0001"},
            headers=headers,
        )

    assert short_number.status_code == 422
    assert non_numeric.status_code == 422
    assert missing_name.status_code == 422


def test_bike_endpoints_require_login() -> None:
    with TestClient(app) as client:
        response = client.get("/api/v1/bikes")

    assert response.status_code == 401


def _register_gps(client: TestClient, headers: dict[str, str], code: str) -> dict:
    response = client.post(
        "/api/v1/gps",
        json={"gps_code": code},
        headers=headers,
    )
    assert response.status_code == 201
    return response.json()


def test_register_gps_generates_stable_yogyakarta_test_coordinates() -> None:
    with TestClient(app) as client:
        headers = _bike_auth_headers(client)
        first = client.post(
            "/api/v1/gps",
            json={"gps_code": "gps-dummy-001"},
            headers=headers,
        )
        listed = client.get("/api/v1/gps", headers=headers)

    assert first.status_code == 201
    assert first.json()["gps_code"] == "GPS-DUMMY-001"
    assert first.json()["is_active"] is True
    assert first.json()["latitude"] < 0
    assert 110.3 < first.json()["longitude"] < 110.4
    assert listed.json() == [first.json()]


def test_register_gps_rejects_duplicate_code() -> None:
    with TestClient(app) as client:
        headers = _bike_auth_headers(client)
        _register_gps(client, headers, "GPS-001")
        duplicate = client.post(
            "/api/v1/gps",
            json={"gps_code": " gps-001 "},
            headers=headers,
        )

    assert duplicate.status_code == 409


def test_update_bike_and_connect_disconnect_gps() -> None:
    with TestClient(app) as client:
        headers = _bike_auth_headers(client)
        gps_device = _register_gps(client, headers, "GPS-0001")
        created = client.post(
            "/api/v1/bikes",
            json={"name": "Sepeda Lama", "bike_number": "0001"},
            headers=headers,
        )
        bike_id = created.json()["id"]
        updated = client.put(
            f"/api/v1/bikes/{bike_id}",
            json={"name": "Sepeda Baru", "bike_number": "0002"},
            headers=headers,
        )
        connected = client.put(
            f"/api/v1/bikes/{bike_id}/gps",
            json={"gps_code": gps_device["gps_code"]},
            headers=headers,
        )
        listed = client.get("/api/v1/bikes", headers=headers)
        disconnected = client.delete(
            f"/api/v1/bikes/{bike_id}/gps",
            headers=headers,
        )

    assert updated.status_code == 200
    assert updated.json()["name"] == "Sepeda Baru"
    assert updated.json()["bike_number"] == "0002"
    assert connected.json()["gps_code"] == "GPS-0001"
    assert connected.json()["latitude"] == gps_device["latitude"]
    assert connected.json()["longitude"] == gps_device["longitude"]
    assert listed.json()[0]["gps_code"] == "GPS-0001"
    assert listed.json()[0]["latitude"] == gps_device["latitude"]
    assert disconnected.json()["gps_code"] is None


def test_bike_cannot_connect_unregistered_gps_code() -> None:
    with TestClient(app) as client:
        headers = _bike_auth_headers(client)
        bike = client.post(
            "/api/v1/bikes",
            json={"name": "Sepeda Kota", "bike_number": "0001"},
            headers=headers,
        ).json()
        response = client.put(
            f"/api/v1/bikes/{bike['id']}/gps",
            json={"gps_code": "GPS-TIDAK-TERDAFTAR"},
            headers=headers,
        )

    assert response.status_code == 404


def test_gps_code_cannot_be_assigned_to_multiple_bikes() -> None:
    with TestClient(app) as client:
        headers = _bike_auth_headers(client)
        _register_gps(client, headers, "GPS-0001")
        first = client.post(
            "/api/v1/bikes",
            json={"name": "Sepeda Satu", "bike_number": "0001"},
            headers=headers,
        ).json()
        second = client.post(
            "/api/v1/bikes",
            json={"name": "Sepeda Dua", "bike_number": "0002"},
            headers=headers,
        ).json()
        assert client.put(
            f"/api/v1/bikes/{first['id']}/gps",
            json={"gps_code": "GPS-0001"},
            headers=headers,
        ).status_code == 200
        duplicate = client.put(
            f"/api/v1/bikes/{second['id']}/gps",
            json={"gps_code": "GPS-0001"},
            headers=headers,
        )

    assert duplicate.status_code == 409
    assert duplicate.json()["detail"] == "Kode GPS sudah terhubung ke sepeda lain"


def test_delete_bike() -> None:
    with TestClient(app) as client:
        headers = _bike_auth_headers(client)
        created = client.post(
            "/api/v1/bikes",
            json={"name": "Sepeda Kota", "bike_number": "0001"},
            headers=headers,
        ).json()
        deleted = client.delete(
            f"/api/v1/bikes/{created['id']}",
            headers=headers,
        )
        listed = client.get("/api/v1/bikes", headers=headers)

    assert deleted.status_code == 204
    assert listed.json() == []


def test_cannot_delete_gps_while_connected_to_a_bike() -> None:
    with TestClient(app) as client:
        headers = _bike_auth_headers(client)
        gps_device = _register_gps(client, headers, "GPS-0001")
        bike = client.post(
            "/api/v1/bikes",
            json={"name": "Sepeda Kota", "bike_number": "0001"},
            headers=headers,
        ).json()
        client.put(
            f"/api/v1/bikes/{bike['id']}/gps",
            json={"gps_code": gps_device["gps_code"]},
            headers=headers,
        )
        response = client.delete(
            f"/api/v1/gps/{gps_device['id']}",
            headers=headers,
        )

    assert response.status_code == 409


def test_existing_bike_table_is_migrated() -> None:
    with engine.begin() as connection:
        connection.exec_driver_sql("DROP TABLE bikes")
        connection.exec_driver_sql(
            "CREATE TABLE bikes "
            "(id INTEGER PRIMARY KEY, bike_number VARCHAR(4) NOT NULL UNIQUE, "
            "gps_code VARCHAR(120), latitude FLOAT, longitude FLOAT)"
        )
        connection.exec_driver_sql(
            "INSERT INTO bikes (bike_number, gps_code) "
            "VALUES ('0001', 'GPS-LEGACY')"
        )

    migrate_bikes_table()

    with engine.connect() as connection:
        bike = connection.exec_driver_sql(
            "SELECT name, bike_number, gps_code, latitude, longitude FROM bikes"
        ).one()
        gps_device = connection.exec_driver_sql(
            "SELECT gps_code, latitude, longitude, is_active FROM gps_devices"
        ).one()
    assert bike == ("Sepeda 0001", "0001", "GPS-LEGACY", None, None)
    assert gps_device == ("GPS-LEGACY", -7.7956, 110.3695, 1)
    Base.metadata.create_all(bind=engine)
