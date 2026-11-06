from sqlalchemy import inspect, text

from app.database import engine


def migrate_bikes_table() -> None:
    with engine.begin() as connection:
        inspector = inspect(connection)
        columns = {column["name"] for column in inspector.get_columns("bikes")}
        if "name" not in columns:
            connection.execute(
                text("ALTER TABLE bikes ADD COLUMN name VARCHAR(120) NOT NULL DEFAULT ''")
            )
            connection.execute(
                text(
                    "UPDATE bikes SET name = 'Sepeda ' || bike_number "
                    "WHERE name = ''"
                )
            )
        if "gps_code" not in columns:
            connection.execute(text("ALTER TABLE bikes ADD COLUMN gps_code VARCHAR(120)"))
        if "latitude" not in columns:
            connection.execute(text("ALTER TABLE bikes ADD COLUMN latitude FLOAT"))
        if "longitude" not in columns:
            connection.execute(text("ALTER TABLE bikes ADD COLUMN longitude FLOAT"))

        inspector = inspect(connection)
        has_unique_gps_code = any(
            constraint.get("column_names") == ["gps_code"]
            for constraint in inspector.get_unique_constraints("bikes")
        ) or any(
            index.get("unique")
            and index.get("column_names") == ["gps_code"]
            for index in inspector.get_indexes("bikes")
        )
        if not has_unique_gps_code:
            connection.execute(
                text(
                    "CREATE UNIQUE INDEX uq_bikes_gps_code "
                    "ON bikes (gps_code)"
                )
            )

        gps_columns = {
            column["name"] for column in inspect(connection).get_columns("gps_devices")
        }
        if not gps_columns:
            return

        connection.execute(
            text(
                "INSERT INTO gps_devices "
                "(gps_code, latitude, longitude, is_active) "
                "SELECT bikes.gps_code, "
                "COALESCE(bikes.latitude, -7.7956), "
                "COALESCE(bikes.longitude, 110.3695), TRUE "
                "FROM bikes LEFT JOIN gps_devices "
                "ON gps_devices.gps_code = bikes.gps_code "
                "WHERE bikes.gps_code IS NOT NULL "
                "AND gps_devices.id IS NULL"
            )
        )
