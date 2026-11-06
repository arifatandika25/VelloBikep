import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;

class Bike {
  const Bike({
    required this.id,
    required this.name,
    required this.number,
    this.gpsCode,
    this.latitude,
    this.longitude,
  });

  final int id;
  final String name;
  final String number;
  final String? gpsCode;
  final double? latitude;
  final double? longitude;

  factory Bike.fromJson(Map<String, dynamic> json) {
    return Bike(
      id: json['id'] as int,
      name: json['name'] as String,
      number: json['bike_number'] as String,
      gpsCode: json['gps_code'] as String?,
      latitude: (json['latitude'] as num?)?.toDouble(),
      longitude: (json['longitude'] as num?)?.toDouble(),
    );
  }

  bool get hasLocation => latitude != null && longitude != null;
}

class GpsDevice {
  const GpsDevice({
    required this.id,
    required this.code,
    required this.latitude,
    required this.longitude,
    required this.isActive,
    this.connectedBikeNumber,
  });

  final int id;
  final String code;
  final double latitude;
  final double longitude;
  final bool isActive;
  final String? connectedBikeNumber;

  factory GpsDevice.fromJson(Map<String, dynamic> json) {
    return GpsDevice(
      id: json['id'] as int,
      code: json['gps_code'] as String,
      latitude: (json['latitude'] as num).toDouble(),
      longitude: (json['longitude'] as num).toDouble(),
      isActive: json['is_active'] as bool,
      connectedBikeNumber: json['connected_bike_number'] as String?,
    );
  }
}

class BikeApiException implements Exception {
  const BikeApiException(this.message);

  final String message;

  @override
  String toString() => message;
}

abstract interface class BikeService {
  Future<List<Bike>> getBikes();

  Future<List<GpsDevice>> getGpsDevices();

  Future<GpsDevice> registerGpsDevice(String code);

  Future<void> deleteGpsDevice(int id);

  Future<Bike> addBike({required String name, required String number});

  Future<Bike> updateBike({
    required int id,
    required String name,
    required String number,
  });

  Future<Bike> connectGps({required int bikeId, required String gpsCode});

  Future<Bike> disconnectGps(int bikeId);

  Future<void> deleteBike(int bikeId);
}

class ApiBikeService implements BikeService {
  ApiBikeService({
    http.Client? client,
    FlutterSecureStorage? secureStorage,
    String? baseUrl,
  }) : _client = client ?? http.Client(),
       _secureStorage = secureStorage ?? const FlutterSecureStorage(),
       _baseUrl = (baseUrl ?? _defaultBaseUrl).replaceAll(RegExp(r'/$'), '');

  static const _tokenKey = 'access_token';
  static const _configuredBaseUrl = String.fromEnvironment('API_BASE_URL');

  static String get _defaultBaseUrl {
    if (_configuredBaseUrl.isNotEmpty) return _configuredBaseUrl;
    if (!kIsWeb && defaultTargetPlatform == TargetPlatform.android) {
      return 'http://10.0.2.2:8000';
    }
    return 'http://127.0.0.1:8000';
  }

  final http.Client _client;
  final FlutterSecureStorage _secureStorage;
  final String _baseUrl;

  @override
  Future<List<Bike>> getBikes() async {
    final response = await _send(
      (headers) =>
          _client.get(Uri.parse('$_baseUrl/api/v1/bikes'), headers: headers),
    );
    final Object? decoded;
    try {
      decoded = jsonDecode(response.body);
    } on FormatException {
      throw const BikeApiException('Respons dari server tidak valid.');
    }
    if (decoded is! List) {
      throw const BikeApiException('Respons daftar sepeda tidak valid.');
    }
    try {
      return decoded
          .map((item) => Bike.fromJson(item as Map<String, dynamic>))
          .toList();
    } on TypeError {
      throw const BikeApiException('Data sepeda dari server tidak valid.');
    }
  }

  @override
  Future<List<GpsDevice>> getGpsDevices() async {
    final response = await _send(
      (headers) =>
          _client.get(Uri.parse('$_baseUrl/api/v1/gps'), headers: headers),
    );
    final Object? decoded;
    try {
      decoded = jsonDecode(response.body);
    } on FormatException {
      throw const BikeApiException('Respons dari server tidak valid.');
    }
    if (decoded is! List) {
      throw const BikeApiException('Respons daftar GPS tidak valid.');
    }
    try {
      return decoded
          .map((item) => GpsDevice.fromJson(item as Map<String, dynamic>))
          .toList();
    } on TypeError {
      throw const BikeApiException('Data GPS dari server tidak valid.');
    }
  }

  @override
  Future<GpsDevice> registerGpsDevice(String code) async {
    final response = await _send(
      (headers) => _client.post(
        Uri.parse('$_baseUrl/api/v1/gps'),
        headers: headers,
        body: jsonEncode({'gps_code': code}),
      ),
      hasJsonBody: true,
    );
    try {
      return GpsDevice.fromJson(
        jsonDecode(response.body) as Map<String, dynamic>,
      );
    } on FormatException {
      throw const BikeApiException('Respons dari server tidak valid.');
    } on TypeError {
      throw const BikeApiException('Data GPS dari server tidak valid.');
    }
  }

  @override
  Future<void> deleteGpsDevice(int id) async {
    await _send(
      (headers) => _client.delete(
        Uri.parse('$_baseUrl/api/v1/gps/$id'),
        headers: headers,
      ),
      allowNoContent: true,
    );
  }

  @override
  Future<Bike> addBike({required String name, required String number}) async {
    final response = await _send(
      (headers) => _client.post(
        Uri.parse('$_baseUrl/api/v1/bikes'),
        headers: headers,
        body: jsonEncode({'name': name, 'bike_number': number}),
      ),
      hasJsonBody: true,
    );
    return _parseBike(response.body);
  }

  @override
  Future<Bike> updateBike({
    required int id,
    required String name,
    required String number,
  }) async {
    final response = await _send(
      (headers) => _client.put(
        Uri.parse('$_baseUrl/api/v1/bikes/$id'),
        headers: headers,
        body: jsonEncode({'name': name, 'bike_number': number}),
      ),
      hasJsonBody: true,
    );
    return _parseBike(response.body);
  }

  @override
  Future<Bike> connectGps({
    required int bikeId,
    required String gpsCode,
  }) async {
    final response = await _send(
      (headers) => _client.put(
        Uri.parse('$_baseUrl/api/v1/bikes/$bikeId/gps'),
        headers: headers,
        body: jsonEncode({'gps_code': gpsCode}),
      ),
      hasJsonBody: true,
    );
    return _parseBike(response.body);
  }

  @override
  Future<Bike> disconnectGps(int bikeId) async {
    final response = await _send(
      (headers) => _client.delete(
        Uri.parse('$_baseUrl/api/v1/bikes/$bikeId/gps'),
        headers: headers,
      ),
    );
    return _parseBike(response.body);
  }

  @override
  Future<void> deleteBike(int bikeId) async {
    await _send(
      (headers) => _client.delete(
        Uri.parse('$_baseUrl/api/v1/bikes/$bikeId'),
        headers: headers,
      ),
      allowNoContent: true,
    );
  }

  Bike _parseBike(String body) {
    try {
      return Bike.fromJson(jsonDecode(body) as Map<String, dynamic>);
    } on FormatException {
      throw const BikeApiException('Respons dari server tidak valid.');
    } on TypeError {
      throw const BikeApiException('Data sepeda dari server tidak valid.');
    }
  }

  Future<http.Response> _send(
    Future<http.Response> Function(Map<String, String> headers) request, {
    bool hasJsonBody = false,
    bool allowNoContent = false,
  }) async {
    final String? token;
    try {
      token = await _secureStorage.read(key: _tokenKey);
    } on PlatformException {
      throw const BikeApiException('Sesi login tidak dapat dibaca.');
    }
    if (token == null || token.isEmpty) {
      throw const BikeApiException('Silakan masuk terlebih dahulu.');
    }

    final headers = <String, String>{
      'Authorization': 'Bearer $token',
      if (hasJsonBody) 'Content-Type': 'application/json',
    };
    final http.Response response;
    try {
      response = await request(headers);
    } on http.ClientException {
      throw const BikeApiException(
        'Tidak dapat terhubung ke server. Pastikan API sedang berjalan.',
      );
    }

    if (response.statusCode < 200 || response.statusCode >= 300) {
      try {
        final decoded = jsonDecode(response.body);
        final detail = decoded is Map<String, dynamic>
            ? decoded['detail']
            : null;
        if (detail is String) throw BikeApiException(detail);
      } on FormatException {
        throw const BikeApiException('Respons dari server tidak valid.');
      }
      if (response.statusCode == 409) {
        throw const BikeApiException('No. sepeda sudah terdaftar.');
      }
      throw const BikeApiException('Permintaan gagal. Silakan coba lagi.');
    }

    if (allowNoContent && response.statusCode != 204) {
      throw const BikeApiException('Respons dari server tidak valid.');
    }

    return response;
  }
}
