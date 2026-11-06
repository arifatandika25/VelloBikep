// This is a basic Flutter widget test.
//
// To perform an interaction with a widget in your test, use the WidgetTester
// utility in the flutter_test package. For example, you can send tap and scroll
// gestures. You can also use WidgetTester to find child widgets in the widget
// tree, read text, and verify that the values of widget properties are correct.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:velobikep/services/auth_service.dart';
import 'package:velobikep/screens/hubungkan_gps_screen.dart';
import 'package:velobikep/screens/login_screen.dart';
import 'package:velobikep/screens/sepeda_screen.dart';
import 'package:velobikep/services/bike_service.dart';
import 'package:velobikep/widgets/fleet_map.dart';

class _FakeBikeService implements BikeService {
  final List<Bike> bikes = [];
  final List<GpsDevice> gpsDevices = [];

  @override
  Future<List<Bike>> getBikes() async => List.of(bikes);

  @override
  Future<List<GpsDevice>> getGpsDevices() async => gpsDevices.map((device) {
    final connectedBikes = bikes.where((bike) => bike.gpsCode == device.code);
    final bike = connectedBikes.isEmpty ? null : connectedBikes.first;
    return GpsDevice(
      id: device.id,
      code: device.code,
      latitude: device.latitude,
      longitude: device.longitude,
      isActive: device.isActive,
      connectedBikeNumber: bike?.number,
    );
  }).toList();

  @override
  Future<GpsDevice> registerGpsDevice(String code) async {
    final device = GpsDevice(
      id: gpsDevices.length + 1,
      code: code.toUpperCase(),
      latitude: -7.7956 + gpsDevices.length * 0.001,
      longitude: 110.3695,
      isActive: true,
    );
    gpsDevices.add(device);
    return device;
  }

  @override
  Future<void> deleteGpsDevice(int id) async {
    gpsDevices.removeWhere((device) => device.id == id);
  }

  @override
  Future<Bike> addBike({required String name, required String number}) async {
    final bike = Bike(id: bikes.length + 1, name: name, number: number);
    bikes.add(bike);
    return bike;
  }

  @override
  Future<Bike> updateBike({
    required int id,
    required String name,
    required String number,
  }) async {
    final index = bikes.indexWhere((bike) => bike.id == id);
    final bike = Bike(
      id: id,
      name: name,
      number: number,
      gpsCode: bikes[index].gpsCode,
      latitude: bikes[index].latitude,
      longitude: bikes[index].longitude,
    );
    bikes[index] = bike;
    return bike;
  }

  @override
  Future<Bike> connectGps({
    required int bikeId,
    required String gpsCode,
  }) async {
    final index = bikes.indexWhere((bike) => bike.id == bikeId);
    final existing = bikes[index];
    final bike = Bike(
      id: bikeId,
      name: existing.name,
      number: existing.number,
      gpsCode: gpsCode,
      latitude: gpsDevices
          .firstWhere((device) => device.code == gpsCode)
          .latitude,
      longitude: gpsDevices
          .firstWhere((device) => device.code == gpsCode)
          .longitude,
    );
    bikes[index] = bike;
    return bike;
  }

  @override
  Future<Bike> disconnectGps(int bikeId) async {
    final index = bikes.indexWhere((bike) => bike.id == bikeId);
    final existing = bikes[index];
    final bike = Bike(id: bikeId, name: existing.name, number: existing.number);
    bikes[index] = bike;
    return bike;
  }

  @override
  Future<void> deleteBike(int bikeId) async {
    bikes.removeWhere((bike) => bike.id == bikeId);
  }
}

class _FakeAuthService implements AuthService {
  String? identifier;
  String? password;
  bool shouldFail = false;

  @override
  Future<AuthSession> login({
    required String identifier,
    required String password,
  }) async {
    this.identifier = identifier;
    this.password = password;
    if (shouldFail) {
      throw const AuthException('Email/username atau kata sandi salah');
    }

    return const AuthSession(
      accessToken: 'test-token',
      user: AuthUser(
        id: 1,
        fullName: 'Admin Velo',
        username: 'admin',
        email: 'admin@example.com',
      ),
    );
  }

  @override
  Future<AuthUser> register({
    required String fullName,
    required String username,
    required String email,
    required String password,
  }) {
    throw UnimplementedError();
  }

  @override
  Future<void> logout() async {}
}

void main() {
  testWidgets('registers a GPS with a generated test location', (
    WidgetTester tester,
  ) async {
    final bikeService = _FakeBikeService();
    await tester.pumpWidget(
      MaterialApp(home: HubungkanGPSScreen(bikeService: bikeService)),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('Tambah kode GPS'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextFormField), 'gps-dummy-01');
    await tester.tap(find.text('Aktifkan'));
    await tester.pumpAndSettle();

    expect(find.text('GPS-DUMMY-01'), findsOneWidget);
    expect(find.textContaining('Lokasi uji:'), findsOneWidget);
    expect(find.textContaining('Belum terhubung ke sepeda'), findsOneWidget);
    expect(bikeService.gpsDevices.single.isActive, isTrue);
  });

  testWidgets('adds a bike to the bike list', (WidgetTester tester) async {
    final bikeService = _FakeBikeService();
    await tester.pumpWidget(
      MaterialApp(home: SepedaScreen(bikeService: bikeService)),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('Tambah sepeda').first);
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextFormField).at(0), 'Sepeda Kota');
    await tester.enterText(find.byType(TextFormField).at(1), '0001');
    await tester.tap(find.text('Tambah'));
    await tester.pumpAndSettle();

    expect(find.text('Sepeda Kota'), findsOneWidget);
    expect(
      find.text(
        'No. Sepeda 0001\nGPS: Belum terhubung\nLokasi uji: Belum tersedia',
      ),
      findsOneWidget,
    );
    expect(bikeService.bikes.single.number, '0001');
  });

  testWidgets('connects GPS to a bike from its management menu', (
    WidgetTester tester,
  ) async {
    final bikeService = _FakeBikeService();
    await bikeService.addBike(name: 'Sepeda Kota', number: '0001');
    await bikeService.registerGpsDevice('GPS-123');
    await tester.pumpWidget(
      MaterialApp(home: SepedaScreen(bikeService: bikeService)),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('Kelola sepeda'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Hubungkan GPS'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Hubungkan').last);
    await tester.pumpAndSettle();

    expect(
      find.text('No. Sepeda 0001\nGPS: GPS-123\nLokasi uji: -7.7956, 110.3695'),
      findsOneWidget,
    );

    await tester.tap(find.byTooltip('Kelola sepeda'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Hapus koneksi GPS'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Lepaskan').last);
    await tester.pumpAndSettle();

    expect(
      find.text(
        'No. Sepeda 0001\nGPS: Belum terhubung\nLokasi uji: Belum tersedia',
      ),
      findsOneWidget,
    );
  });

  testWidgets('edits and deletes a bike from its management menu', (
    WidgetTester tester,
  ) async {
    final bikeService = _FakeBikeService();
    await bikeService.addBike(name: 'Sepeda Lama', number: '0001');
    await tester.pumpWidget(
      MaterialApp(home: SepedaScreen(bikeService: bikeService)),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('Kelola sepeda'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Edit sepeda'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextFormField).at(0), 'Sepeda Baru');
    await tester.enterText(find.byType(TextFormField).at(1), '0002');
    await tester.tap(find.text('Simpan'));
    await tester.pumpAndSettle();

    expect(find.text('Sepeda Baru'), findsOneWidget);
    expect(
      find.text(
        'No. Sepeda 0002\nGPS: Belum terhubung\nLokasi uji: Belum tersedia',
      ),
      findsOneWidget,
    );

    await tester.tap(find.byTooltip('Kelola sepeda'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Hapus sepeda'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Hapus').last);
    await tester.pumpAndSettle();

    expect(
      find.text('Belum ada sepeda.\nTekan + untuk menambahkan.'),
      findsOneWidget,
    );
    expect(bikeService.bikes, isEmpty);
  });

  test('builds map markers only for bikes with GPS coordinates', () {
    final markers = buildFleetMarkers([
      const Bike(
        id: 1,
        name: 'Sepeda Kota',
        number: '0001',
        gpsCode: 'GPS-0001',
        latitude: -7.7956,
        longitude: 110.3695,
      ),
      const Bike(id: 2, name: 'Sepeda Kedua', number: '0002'),
    ]);

    expect(markers, hasLength(1));
    expect(markers.single.markerId.value, 'bike-1');
    expect(markers.single.position.latitude, -7.7956);
    expect(markers.single.position.longitude, 110.3695);
  });

  testWidgets('login requires username and password', (
    WidgetTester tester,
  ) async {
    final authService = _FakeAuthService();
    await tester.pumpWidget(
      MaterialApp(home: LoginScreen(authService: authService)),
    );

    await tester.tap(find.text('Masuk'));
    await tester.pumpAndSettle();

    expect(find.text('Email atau username wajib diisi'), findsOneWidget);
    expect(find.text('Kata sandi wajib diisi'), findsOneWidget);
    expect(authService.identifier, isNull);
  });

  testWidgets('login sends credentials and opens home on success', (
    WidgetTester tester,
  ) async {
    final authService = _FakeAuthService();
    await tester.pumpWidget(
      MaterialApp(home: LoginScreen(authService: authService)),
    );

    await tester.enterText(find.byType(TextFormField).at(0), 'admin');
    await tester.enterText(find.byType(TextFormField).at(1), 'secure-pass');
    await tester.tap(find.text('Masuk'));
    await tester.pumpAndSettle();

    expect(authService.identifier, 'admin');
    expect(authService.password, 'secure-pass');
    expect(find.text('Hello, Admin Velo'), findsOneWidget);
  });

  testWidgets('login shows API errors without leaving the form', (
    WidgetTester tester,
  ) async {
    final authService = _FakeAuthService()..shouldFail = true;
    await tester.pumpWidget(
      MaterialApp(home: LoginScreen(authService: authService)),
    );

    await tester.enterText(find.byType(TextFormField).at(0), 'admin');
    await tester.enterText(find.byType(TextFormField).at(1), 'wrong-pass');
    await tester.tap(find.text('Masuk'));
    await tester.pumpAndSettle();

    expect(find.text('Email/username atau kata sandi salah'), findsOneWidget);
    expect(find.text('Masuk ke VeloBike'), findsOneWidget);
  });
}
