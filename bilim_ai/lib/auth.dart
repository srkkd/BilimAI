import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:http/http.dart' as http;

class AuthService {
  static const _keyCurrentEmail = 'auth.currentEmail';
  static const _keyToken = 'auth.token';
  static const String _baseUrl = 'http://localhost:4000';

  Future<bool> isLoggedIn() async {
    final p = await SharedPreferences.getInstance();
    return (p.getString(_keyToken) ?? '').isNotEmpty;
  }

  Future<String?> currentUserEmail() async {
    final p = await SharedPreferences.getInstance();
    return p.getString(_keyCurrentEmail);
  }

  Future<void> logout() async {
    final p = await SharedPreferences.getInstance();
    await p.remove(_keyCurrentEmail);
    await p.remove(_keyToken);
  }

  Future<bool> register(String email, String password) async {
    if (password.length < 6) {
      throw Exception('Пароль минимум 6 символов');
    }
    final url = Uri.parse('$_baseUrl/auth/register');
    final resp = await http.post(
      url,
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({'email': email, 'password': password}),
    );
    if (resp.statusCode != 200) {
      final body = resp.body.isNotEmpty ? resp.body : 'status ${resp.statusCode}';
      throw Exception('Регистрация не удалась: $body');
    }
    final data = jsonDecode(resp.body);
    final token = data['token'] as String?;
    if (token == null || token.isEmpty) throw Exception('Не получен токен');
    final p = await SharedPreferences.getInstance();
    await p.setString(_keyToken, token);
    await p.setString(_keyCurrentEmail, email);
    return true;
  }

  Future<bool> login(String email, String password) async {
    final url = Uri.parse('$_baseUrl/auth/login');
    final resp = await http.post(
      url,
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({'email': email, 'password': password}),
    );
    if (resp.statusCode != 200) {
      throw Exception('Неверный email/пароль');
    }
    final data = jsonDecode(resp.body);
    final token = data['token'] as String?;
    if (token == null || token.isEmpty) throw Exception('Не получен токен');
    final p = await SharedPreferences.getInstance();
    await p.setString(_keyToken, token);
    await p.setString(_keyCurrentEmail, email);
    return true;
  }

  Future<void> continueAsGuest() async {
    // Ничего не делаем: гость = нет сессии
    final p = await SharedPreferences.getInstance();
    await p.setBool('guest.mode', true);
  }
}
