import 'dart:convert';
import 'package:crypto/crypto.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';

class AuthService {
  final SupabaseClient _sb = Supabase.instance.client;
  static const _keyCurrentEmail = 'auth.currentEmail';

  Future<bool> isLoggedIn() async {
    final p = await SharedPreferences.getInstance();
    return (p.getString(_keyCurrentEmail) ?? '').isNotEmpty;
  }

  Future<String?> currentUserEmail() async {
    final p = await SharedPreferences.getInstance();
    return p.getString(_keyCurrentEmail);
  }

  Future<void> logout() async {
    final p = await SharedPreferences.getInstance();
    await p.remove(_keyCurrentEmail);
  }

  Future<bool> register(String email, String password) async {
    if (password.length < 6) {
      throw Exception('Пароль минимум 6 символов');
    }
    final existing = await _sb.from('login').select('id').eq('email', email).maybeSingle();
    if (existing != null) {
      throw Exception('Email уже существует');
    }
    final hash = sha256.convert(utf8.encode(password)).toString();
    await _sb.from('login').insert({
      'email': email,
      'password_hash': hash,
    });
    final p = await SharedPreferences.getInstance();
    await p.setString(_keyCurrentEmail, email);
    return true;
  }

  Future<bool> login(String email, String password) async {
    final row = await _sb.from('login').select('email, password_hash').eq('email', email).maybeSingle();
    if (row == null) throw Exception('Неверный email/пароль');
    final stored = (row['password_hash'] as String?) ?? '';
    final hash = sha256.convert(utf8.encode(password)).toString();
    if (stored != hash) throw Exception('Неверный email/пароль');
    final p = await SharedPreferences.getInstance();
    await p.setString(_keyCurrentEmail, email);
    return true;
  }

  Future<void> continueAsGuest() async {
    // Ничего не делаем: гость = нет сессии
    final p = await SharedPreferences.getInstance();
    await p.setBool('guest.mode', true);
  }
}
