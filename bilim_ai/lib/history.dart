import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';

class HistoryService {
  static String _keyFor(String email) => 'history.$email';

  Future<SharedPreferences> _prefs() => SharedPreferences.getInstance();

  Future<void> addEntry({required String email, required String question, required String answer, required DateTime at}) async {
    final p = await _prefs();
    final key = _keyFor(email);
    final raw = p.getString(key);
    final List list = raw == null ? <dynamic>[] : (jsonDecode(raw) as List);
    list.add({
      'q': question,
      'a': answer,
      'ts': at.toIso8601String(),
    });
    await p.setString(key, jsonEncode(list));
  }

  Future<List<Map<String, dynamic>>> load({required String email}) async {
    final p = await _prefs();
    final raw = p.getString(_keyFor(email));
    if (raw == null) return <Map<String, dynamic>>[];
    final List list = jsonDecode(raw) as List;
    return list.cast<Map<String, dynamic>>();
  }

  Future<void> clear({required String email}) async {
    final p = await _prefs();
    await p.remove(_keyFor(email));
  }
}
