# VeloBike

Flutter app with a FastAPI authentication backend.

## Run the API

From the project root in PowerShell:

```powershell
cd backend
py -m venv .venv
.\.venv\Scripts\Activate.ps1
python -m pip install -r requirements.txt
Copy-Item .env.example .env
```

Before starting the API, replace `JWT_SECRET_KEY` in `backend/.env` with a
private random value of at least 32 characters. For example:

```powershell
python -c "import secrets; print(secrets.token_urlsafe(48))"
```

Public account registration is disabled by default. Set
`ALLOW_PUBLIC_REGISTRATION=true` in `backend/.env` only while testing account
creation; disable it again for deployments where admins should provision
accounts themselves.

The default database is SQLite (`backend/velobike.db`), created automatically
when the API starts. When your database is ready, change `DATABASE_URL` in
`backend/.env`. PostgreSQL URLs use the `postgresql+psycopg://` scheme, for example
`postgresql+psycopg://user:password@localhost:5432/velobike`. Create the
database itself before starting the API. The API creates its `users` table on
startup.

SQLite waits up to 30 seconds if another process is writing to the database.
If registration still reports that the database is busy, close any active
edit/transaction in DB Browser for SQLite, then retry the registration.

Start the development API from the `backend` directory:

```powershell
uvicorn app.main:app --reload --host 0.0.0.0 --port 8000
```

Interactive API documentation: <http://127.0.0.1:8000/docs>

### Authentication endpoints

- `POST /api/v1/auth/register` — create an account with `full_name`,
  `username`, `email`, and `password` (minimum 8 characters).
- `POST /api/v1/auth/login` — authenticate with `identifier` (email or
  username) and `password`.

Registration returns the created user. Login returns a bearer access token
and user details. Passwords are stored as Argon2 hashes; the API never stores
the submitted password.

### Bike endpoints

- `GET /api/v1/bikes` — list registered bikes.
- `POST /api/v1/bikes` — add a bike with a required `name` and unique
  `bike_number` of exactly four digits (for example, `0001`).
- `PUT /api/v1/bikes/{id}` — edit its name or number.
- `PUT /api/v1/bikes/{id}/gps` and `DELETE /api/v1/bikes/{id}/gps` — connect
  or disconnect a registered GPS code.
- `DELETE /api/v1/bikes/{id}` — delete the bike.
- `GET /api/v1/gps` — list registered GPS devices and their assigned bike.
- `POST /api/v1/gps` — activate a unique GPS code. In testing, the backend
  assigns a stable sample coordinate around Yogyakarta automatically.
- `DELETE /api/v1/gps/{id}` — delete a GPS code after it has been disconnected
  from its bike.

The map polls bike locations every five seconds. Sample coordinates are static,
not live GPS readings; replace them with device-reported coordinates when
physical trackers are available.

Bike and GPS endpoints require a valid bearer token from login. The database
creates and updates the required tables automatically when the API starts.

## Connect Flutter to the API

The Flutter app defaults to `http://127.0.0.1:8000` on web and desktop, and
`http://10.0.2.2:8000` on the Android emulator. For a physical phone, pass the
development computer's LAN address when launching the app:

```powershell
flutter run --dart-define=API_BASE_URL=http://192.168.1.10:8000
```

Replace the example address with the computer's actual LAN IP. The phone and
computer must be on the same network. Use HTTPS for production deployments.

## Google Maps

The home screen map starts centered on Yogyakarta and shows markers for bikes
with a registered GPS code. Test GPS coordinates are generated automatically
when a GPS code is activated; they are not readings from physical trackers.

Create a Google Maps Platform project, enable billing, and enable **Maps SDK
for Android** (and **Maps JavaScript API** if running on web). For Android,
add this line to `android/local.properties` and replace the value with your
API key:

```properties
googleMapsApiKey=YOUR_GOOGLE_MAPS_API_KEY
```

For web, replace `YOUR_GOOGLE_MAPS_API_KEY` in `web/index.html` with a browser
key restricted to your deployed website's referrers and the Maps JavaScript
API. Restrict the Android key to this app's package name and signing
certificate; avoid committing API keys to source control.

For iOS, initialize `GMSServices` with a restricted iOS key in
`ios/Runner/AppDelegate.swift` as described in the
[Google Maps Flutter setup guide](https://pub.dev/packages/google_maps_flutter#platform-setup).

## Tests

Run backend tests from `backend`:

```powershell
python -m pytest
```

Run Flutter tests from the project root:

```powershell
flutter test
```
