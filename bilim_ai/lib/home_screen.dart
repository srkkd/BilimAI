// lib/home_screen.dart
import 'package:flutter/material.dart';
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'api_key.dart';

// Примечание: API ключ централизован в файле `api_key.dart`.

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
  String? _cachedModelName; // Кеш выбранной модели
  // Прокрутка ответов управляется автоматически без отдельного контроллера

  // Специализированный промпт для физики
  String _getPhysicsPrompt(String userQuestion) {
    return '''Ты Bilim AI — помощник по физике. Отвечай только на вопросы по физике.

Правила ответа:
1. Считай вопросы с формулами (например, F=ma, v=at, s=vt) физическими и принимай их
2. Отвечай ВСЕГДА на русском языке
3. Приводи необходимые формулы и единицы измерения
4. Решай по шагам: дано → формула → подстановка → вычисление → ответ
5. Кратко поясняй физический смысл, когда это уместно

Если вопрос не по физике, отвечай: "Извините, я отвечаю только на вопросы по физике".

Вопрос пользователя: $userQuestion''';
  }

  // Диалог с информацией о приложении
  void _showInfoDialog() {
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: const Text('Bilim AI туралы'),
          content: const SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  'Bilim AI - бұл физика бойынша маманданған жасанды интеллект жүйесі.',
                  style: TextStyle(fontSize: 16),
                ),
                SizedBox(height: 16),
                Text(
                  'Мүмкіндіктер:',
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
                SizedBox(height: 8),
                Text('• Физика есептерін шешу'),
                Text('• Физикалық ұғымдарды түсіндіру'),
                Text('• Формулалар мен теңдеулерді көрсету'),
                Text('• Қазақ тілінде жауап беру'),
                SizedBox(height: 16),
                Text(
                  'Қолдану мысалдары:',
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
                SizedBox(height: 8),
                Text('• "Ньютонның үшінші заңын түсіндір"'),
                Text('• "F = m·a формуласын есепте"'),
                Text('• "Энергия сақталу заңы дегеніміз не?"'),
              ],
            ),
          ),
          actions: [
            TextButton(
              child: const Text('Жабу'),
              onPressed: () {
                Navigator.of(context).pop();
              },
            ),
          ],
        );
      },
    );
  }

  Future<String?> _discoverSupportedModel() async {
    try {
      final uri = Uri.parse('https://generativelanguage.googleapis.com/v1/models?key=$apiKey');
      final response = await http.get(uri);
      if (response.statusCode != 200) {
        return null;
      }
      final data = jsonDecode(response.body);
      final List models = (data['models'] as List? ?? []);

      // Фильтруем модели, поддерживающие generateContent
      final List<String> availableModelNames = models
          .where((m) => (m['supportedGenerationMethods'] as List?)?.contains('generateContent') == true)
          .map<String>((m) => (m['name'] as String).replaceFirst('models/', ''))
          .toList();

      if (availableModelNames.isEmpty) return null;

      // Предпочтительный порядок
      const List<String> preferred = [
        'gemini-1.5-flash-002',
        'gemini-1.5-pro-002',
        'gemini-1.5-flash-latest',
        'gemini-1.5-pro-latest',
      ];

      for (final p in preferred) {
        if (availableModelNames.contains(p)) return p;
      }

      // Если ни одна из предпочтительных не доступна — берём первую доступную
      return availableModelNames.first;
    } catch (_) {
      return null;
    }
  }

  Future<String?> _getUsableModel() async {
    if (_cachedModelName != null) return _cachedModelName;
    final discovered = await _discoverSupportedModel();
    if (discovered != null) {
      _cachedModelName = discovered;
    }
    return _cachedModelName;
  }

Future<void> _sendToAI() async {
  if (_textController.text.isEmpty) {
    return;
  }

  setState(() {
    _isLoading = true;
    _aiResponse = null;
  });

  try {
    final physicsPrompt = _getPhysicsPrompt(_textController.text);

    Future<http.Response> _callModel(String modelName) {
      final url = Uri.parse(
          'https://generativelanguage.googleapis.com/v1/models/'
          '$modelName:generateContent?key=$apiKey');
      return http.post(
        url,
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'contents': [
            {
              'role': 'user',
              'parts': [
                {'text': physicsPrompt}
              ]
            }
          ],
          'generationConfig': {
            'temperature': 0.4,
            'topK': 40,
            'topP': 0.95,
            'maxOutputTokens': 2048
          }
        }),
      );
    }

    String? modelToUse = await _getUsableModel();
    modelToUse ??= 'gemini-1.5-flash-002';
    http.Response response = await _callModel(modelToUse);

    // Если модель недоступна — пытаемся переоткрыть список и выбрать заново
    if (response.statusCode == 404) {
      final discovered = await _discoverSupportedModel();
      if (discovered != null && discovered != modelToUse) {
        _cachedModelName = discovered;
        response = await _callModel(discovered);
      } else {
        // Явный фолбэк
        response = await _callModel('gemini-1.5-pro-002');
        if (response.statusCode == 404) {
          // Попробуем latest как последний шанс
          response = await _callModel('gemini-1.5-pro-latest');
        }
      }
    }

    if (response.statusCode == 200) {
      final data = jsonDecode(response.body);
      final text = data['candidates'][0]['content']['parts'][0]['text'];
      setState(() {
        _aiResponse = text;
      });
    } else if (response.statusCode == 400) {
      setState(() {
        _aiResponse = 'Ошибка 400: проверьте вопрос и параметры запроса.';
      });
    } else if (response.statusCode == 401) {
      setState(() {
        _aiResponse = 'Ошибка 401: проверьте API-ключ Gemini.';
      });
    } else if (response.statusCode == 403) {
      setState(() {
        _aiResponse = 'Ошибка 403: Generative Language API отключён для вашего проекта. Откройте ссылку и включите API, затем подождите пару минут и повторите:\nhttps://console.developers.google.com/apis/api/generativelanguage.googleapis.com/overview?project=1045343908557';
      });
    } else if (response.statusCode == 404) {
      setState(() {
        _aiResponse = 'Ошибка 404: модель недоступна для вашей учётной записи/проекта. Включите нужные модели или используйте gemini-1.5-pro-002.';
      });
    } else if (response.statusCode == 429) {
      setState(() {
        _aiResponse = 'Ошибка 429: слишком много запросов. Попробуйте позже.';
      });
    } else if (response.statusCode >= 500) {
      setState(() {
        _aiResponse = 'Серверная ошибка Gemini. Повторите попытку позже.';
      });
    } else {
      setState(() {
        _aiResponse = 'Ошибка ${response.statusCode}: ${response.body}\n\nПопробуйте gemini-1.5-pro-002 (v1). Убедитесь, что API включён в том же проекте, что и ключ.';
      });
    }
  } catch (e) {
    setState(() {
      _aiResponse = 'Произошла ошибка: ${e.toString()}';
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
        title: const Text(
          'Bilim AI',
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
        backgroundColor: const Color(0xFF2B6CB0),
        foregroundColor: Colors.white,
        elevation: 4,
        shadowColor: Colors.black26,
        actions: [
          IconButton(
            icon: const Icon(Icons.clear),
            onPressed: () {
              _textController.clear();
              setState(() {
                _aiResponse = null;
              });
            },
            tooltip: 'Тазалау',
          ),
          IconButton(
            icon: const Icon(Icons.info_outline),
            onPressed: () {
              _showInfoDialog();
            },
            tooltip: 'Ақпарат',
          ),
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          children: [
            // Поле для ввода текста с улучшенным дизайном
            Container(
              decoration: BoxDecoration(
                color: Colors.grey[50],
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.grey[300]!),
              ),
              child: TextField(
                controller: _textController,
                maxLines: 3,
                decoration: InputDecoration(
                  hintText: 'Физика бойынша сұрағыңызды жазыңыз...\nМысалы: "Ньютонның үшінші заңын түсіндір" немесе "F = m·a формуласын есепте"',
                  hintStyle: TextStyle(color: Colors.grey[600]),
                  border: InputBorder.none,
                  contentPadding: const EdgeInsets.all(16),
                ),
                style: const TextStyle(fontSize: 16),
              ),
            ),
            const SizedBox(height: 16),
            // Кнопка "Жіберу" с улучшенным дизайном
            ElevatedButton.icon(
              onPressed: _isLoading ? null : _sendToAI,
              icon: _isLoading
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                      ),
                    )
                  : const Icon(Icons.send),
              label: Text(_isLoading ? 'Жіберілуде...' : 'Жіберу'),
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF2B6CB0),
                foregroundColor: Colors.white,
                minimumSize: const Size(double.infinity, 50),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                elevation: 2,
              ),
            ),
            const SizedBox(height: 20),
            // Область для отображения ответа с улучшенным дизайном
            Expanded(
              child: Container(
                width: double.infinity,
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.grey[300]!),
                ),
                child: _isLoading
                    ? const Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            CircularProgressIndicator(
                              valueColor: AlwaysStoppedAnimation<Color>(Color(0xFF2B6CB0)),
                            ),
                            SizedBox(height: 16),
                            Text(
                              'Bilim AI ойланып жатыр...',
                              style: TextStyle(
                                color: Colors.grey,
                                fontSize: 16,
                              ),
                            ),
                          ],
                        ),
                      )
                    : _aiResponse != null
                        ? Scrollbar(
                            thumbVisibility: true,
                            child: SingleChildScrollView(
                              primary: true,
                              padding: const EdgeInsets.all(20.0),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    children: [
                                      const Icon(
                                        Icons.lightbulb_outline,
                                        color: Color(0xFF2B6CB0),
                                      ),
                                      const SizedBox(width: 8),
                                      const Text(
                                        'Ответ Bilim AI:',
                                        style: TextStyle(
                                          fontSize: 16,
                                          fontWeight: FontWeight.bold,
                                          color: Color(0xFF2B6CB0),
                                        ),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 12),
                                  SelectableText(
                                    _aiResponse!,
                                    textAlign: TextAlign.left,
                                    style: const TextStyle(
                                      fontSize: 16,
                                      height: 1.6,
                                    ),
                                  ),
                                  const SizedBox(height: 12),
                                ],
                              ),
                            ),
                          )
                        : Center(
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Icon(
                                  Icons.school_outlined,
                                  size: 64,
                                  color: Colors.grey[400],
                                ),
                                const SizedBox(height: 16),
                                Text(
                                  'Физика бойынша сұрақ қойыңыз',
                                  style: TextStyle(
                                    fontSize: 18,
                                    color: Colors.grey[600],
                                  ),
                                ),
                                const SizedBox(height: 8),
                                Text(
                                  'Мен сізге көмектесе аламын!',
                                  style: TextStyle(
                                    fontSize: 14,
                                    color: Colors.grey[500],
                                  ),
                                ),
                              ],
                            ),
                          ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}