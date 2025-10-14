// lib/home_screen.dart
import 'package:bilim_ai/api_key.dart'; // Импортируем наш ключ
import 'package:flutter/material.dart';
import 'dart:convert'; 
import 'package:http/http.dart' as http; 

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  // Контроллер для текстового поля
  final TextEditingController _textController = TextEditingController();
  // Переменные для хранения состояния
  String? _aiResponse;
  bool _isLoading = false;

Future<void> _sendToAI() async {
  if (_textController.text.isEmpty) {
    return;
  }

  setState(() {
    _isLoading = true;
    _aiResponse = null;
  });

  try {
    // Формируем URL для прямого запроса
    final url = Uri.parse(
        'https://generativelanguage.googleapis.com/v1beta/models/gemini-pro:generateContent?key=$apiKey');

    // Формируем тело запроса в формате JSON
    final response = await http.post(
      url,
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({
        'contents': [
          {
            'parts': [
              {'text': _textController.text}
            ]
          }
        ]
      }),
    );

    if (response.statusCode == 200) {
      // Если все успешно, извлекаем ответ
      final data = jsonDecode(response.body);
      final text = data['candidates'][0]['content']['parts'][0]['text'];
      setState(() {
        _aiResponse = text;
      });
    } else {
      // Если есть ошибка от сервера
      setState(() {
        _aiResponse = "Ошибка: ${response.body}";
      });
    }
  } catch (e) {
    setState(() {
      _aiResponse = "Произошла ошибка: ${e.toString()}";
    });
  } finally {
    setState(() {
      _isLoading = false;
    });
  }
}


  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Bilim AI'),
        backgroundColor: const Color(0xFF2B6CB0),
        foregroundColor: Colors.white,
      ),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          children: [
            // Поле для ввода текста
            TextField(
              controller: _textController,
              decoration: const InputDecoration(
                hintText: 'Мысалы: 2x + 5 = 11 теңдеуін шеш...',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 16),
            // Кнопка "Жіберу"
            ElevatedButton(
              onPressed: _isLoading ? null : _sendToAI, // Блокируем кнопку во время загрузки
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF2B6CB0),
                foregroundColor: Colors.white,
                minimumSize: const Size(double.infinity, 50),
              ),
              child: const Text('Жіберу'),
            ),
            const SizedBox(height: 20),
            // Область для отображения ответа
            Expanded(
              child: SingleChildScrollView(
                child: _isLoading
                    ? const Center(child: CircularProgressIndicator()) // Показываем загрузку
                    : _aiResponse != null
                        ? Container(
                            padding: const EdgeInsets.all(12.0),
                            decoration: BoxDecoration(
                              color: Colors.grey[200],
                              borderRadius: BorderRadius.circular(8.0),
                            ),
                            child: SelectableText( // Позволяет копировать текст
                              _aiResponse!,
                              textAlign: TextAlign.left,
                            ),
                          )
                        : const Center(child: Text('Нәтиже осында көрсетіледі.')), // Начальный текст
              ),
            ),
          ],
        ),
      ),
    );
  }
}