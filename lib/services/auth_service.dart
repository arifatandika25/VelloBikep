import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;

class AuthException implements Exception {
  const AuthException(this.message);

  final String message;

  @override
  String toString() => message;
}

class AuthUser {
  const AuthUser({
    required this.id,
    required this.fullName,
    required this.username,
    required this.email,
  });

  final int id;
  final String fullName;
  final String username;
  final String email;

  factory AuthUser.fromJson(Map<String, dynamic> json) {
    return AuthUser(
      id: json['id'] as int,
      fullName: json['full_name'] as String,
      username: json['username'] as String,
      email: json['email'] as String,
    );
  }
}

class AuthSession {
  const AuthSession({required this.accessToken, required this.user});

  final String accessToken;
  final AuthUser user;

  factory AuthSession.fromJson(Map<String, dynamic> json) {
    return AuthSession(
      accessToken: json['access_token'] as String,
      user: AuthUser.fromJson(json['user'] as Map<String, dynamic>),
    );
  }
}

abstract interface class AuthService {
  Future<AuthSession> login({
    required String identifier,
    required String password,
  });

  Future<AuthUser> register({
    required String fullName,
    required String username,
    required String email,
    required String password,
  });

  Future<void> logout();
}

class ApiAuthService implements AuthService {
  ApiAuthService({
    http.Client? client,
    FlutterSecureStorage? secureStorage,
    String? baseUrl,
  }) : _client = client ?? http.Client(),
       _secureStorage = secureStorage ?? const FlutterSecureStorage(),
       _baseUrl = (baseUrl ?? _defaultBaseUrl).replaceAll(RegExp(r'/$'), '');

  static const _tokenKey = 'access_token';
  static const _configuredBaseUrl = String.fromEnvironment('API_BASE_URL');

  static String get _defaultBaseUrl {
    if (_configuredBaseUrl.isNotEmpty) {
      return _configuredBaseUrl;
    }
    if (!kIsWeb && defaultTargetPlatform == TargetPlatform.android) {
      return 'http://10.0.2.2:8000';
    }
    return 'http://127.0.0.1:8000';
  }

  final http.Client _client;
  final FlutterSecureStorage _secureStorage;
  final String _baseUrl;

  @override
  Future<AuthSession> login({
    required String identifier,
    required String password,
  }) {
    return _authenticate(
      endpoint: '/api/v1/auth/login',
      payload: {'identifier': identifier, 'password': password},
    );
  }

  @override
  Future<AuthUser> register({
    required String fullName,
    required String username,
    required String email,
    required String password,
  }) async {
    final body = await _postJson(
      endpoint: '/api/v1/auth/register',
      payload: {
        'full_name': fullName,
        'username': username,
        'email': email,
        'password': password,
      },
    );
    return AuthUser.fromJson(body);
  }

  Future<AuthSession> _authenticate({
    required String endpoint,
    required Map<String, String> payload,
  }) async {
    final body = await _postJson(endpoint: endpoint, payload: payload);
    final session = AuthSession.fromJson(body);
    try {
      await _secureStorage.write(key: _tokenKey, value: session.accessToken);
    } on PlatformException {
      throw const AuthException('Sesi login tidak dapat disimpan dengan aman.');
    }
    return session;
  }

  @override
  Future<void> logout() async {
    try {
      await _secureStorage.delete(key: _tokenKey);
    } on PlatformException {
      throw const AuthException('Sesi login tidak dapat dihapus.');
    }
  }

  Future<Map<String, dynamic>> _postJson({
    required String endpoint,
    required Map<String, String> payload,
  }) async {
    final http.Response response;
    try {
      response = await _client.post(
        Uri.parse('$_baseUrl$endpoint'),
        headers: const {'Content-Type': 'application/json'},
        body: jsonEncode(payload),
      );
    } on http.ClientException {
      throw const AuthException(
        'Tidak dapat terhubung ke server. Pastikan API sedang berjalan.',
      );
    }

    final Map<String, dynamic> body;
    try {
      final decoded = jsonDecode(response.body);
      if (decoded is! Map<String, dynamic>) {
        throw const FormatException('Unexpected API response');
      }
      body = decoded;
    } on FormatException {
      throw const AuthException('Respons dari server tidak valid.');
    }

    if (response.statusCode < 200 || response.statusCode >= 300) {
      final detail = body['detail'];
      if (detail is List && detail.isNotEmpty && detail.first is Map) {
        final message = detail.first['msg'];
        if (message is String) throw AuthException(message);
      }
      throw AuthException(
        detail is String ? detail : 'Permintaan gagal. Silakan coba lagi.',
      );
    }

    return body;
  }
}
