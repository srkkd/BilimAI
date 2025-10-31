import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'home_screen.dart';

class HistoryScreen extends StatefulWidget {
  const HistoryScreen({super.key});

  @override
  State<HistoryScreen> createState() => _HistoryScreenState();
}

class _HistoryScreenState extends State<HistoryScreen> {
  static const String _apiBase = 'http://localhost:4000';
  String _uiLang = 'ru';

  Future<String?> _getToken() async {
    final p = await SharedPreferences.getInstance();
    return p.getString('auth.token');
  }

  Future<List<Map<String, dynamic>>> _load() async {
    final token = await _getToken();
    if (token == null || token.isEmpty) return <Map<String, dynamic>>[];
    final resp = await http.get(
      Uri.parse('$_apiBase/chats'),
      headers: {
        'Authorization': 'Bearer $token',
      },
    );
    if (resp.statusCode != 200) return <Map<String, dynamic>>[];
    final data = jsonDecode(resp.body) as List;
    return data.cast<Map<String, dynamic>>();
  }

  @override
  void initState() {
    super.initState();
    _loadLang();
  }

  Future<void> _loadLang() async {
    final p = await SharedPreferences.getInstance();
    final saved = p.getString('ui.lang');
    setState(() => _uiLang = (saved == 'kk') ? 'kk' : 'ru');
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(_uiLang == 'kk' ? 'Тарих' : 'История'),
      ),
      body: FutureBuilder<List<Map<String, dynamic>>>(
        future: _load(),
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done) {
            return const Center(child: CircularProgressIndicator());
          }
          final items = snapshot.data ?? [];
          if (items.isEmpty) {
            return const Center(child: Text('Пока пусто'));
          }
          return ListView.separated(
            padding: const EdgeInsets.all(16),
            itemCount: items.length,
            separatorBuilder: (_, __) => const SizedBox(height: 12),
            itemBuilder: (context, i) {
              final it = items[i];
              final created = it['createdAt'] as String?;
              final dt = created != null ? DateTime.tryParse(created) : null;
              final dateStr = dt != null ? _formatDate(dt.toLocal()) : '';
              final title = (it['title'] as String?) ?? 'Без названия';
              final chatId = it['id'] as String?;
              return Dismissible(
                key: ValueKey(chatId ?? i.toString()),
                direction: chatId == null ? DismissDirection.none : DismissDirection.endToStart,
                background: Container(
                  alignment: Alignment.centerRight,
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  decoration: BoxDecoration(
                    color: Colors.red[50],
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Icon(Icons.delete, color: Colors.red),
                ),
                confirmDismiss: chatId == null
                    ? null
                    : (dir) async {
                        final ok = await _deleteChat(chatId);
                        if (ok) {
                          setState(() => items.removeAt(i));
                        }
                        return ok;
                      },
                child: InkWell(
                  onTap: chatId == null
                      ? null
                      : () {
                          Navigator.of(context).pushReplacement(
                            MaterialPageRoute(
                              builder: (_) => HomeScreen(initialChatId: chatId),
                            ),
                          );
                        },
                  child: Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: Colors.grey[300]!),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(title, style: const TextStyle(fontWeight: FontWeight.w600), overflow: TextOverflow.ellipsis),
                              const SizedBox(height: 6),
                              Text(dateStr, style: TextStyle(color: Colors.grey[600], fontSize: 12)),
                            ],
                          ),
                        ),
                        const Icon(Icons.chevron_right, color: Colors.grey),
                      ],
                    ),
                  ),
                ),
              );
            },
          );
        },
      ),
    );
  }

  String _formatDate(DateTime dt) {
    final y = dt.year.toString().padLeft(4, '0');
    final m = dt.month.toString().padLeft(2, '0');
    final d = dt.day.toString().padLeft(2, '0');
    final hh = dt.hour.toString().padLeft(2, '0');
    final mm = dt.minute.toString().padLeft(2, '0');
    return '$d.$m.$y $hh:$mm';
  }

  Future<bool> _deleteChat(String chatId) async {
    try {
      final token = await _getToken();
      if (token == null || token.isEmpty) return false;
      final resp = await http.delete(
        Uri.parse('$_apiBase/chats/$chatId'),
        headers: { 'Authorization': 'Bearer $token' },
      );
      return resp.statusCode == 200;
    } catch (_) {
      return false;
    }
  }
}
