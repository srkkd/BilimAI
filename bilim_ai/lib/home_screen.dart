// lib/home_screen.dart
import 'package:flutter/material.dart';
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'api_key.dart';
import 'package:flutter_math_fork/flutter_math.dart';
import 'package:flutter/services.dart';
import 'auth.dart';
import 'history.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'history_screen.dart';

// Примечание: API ключ централизован в файле `api_key.dart`.

// Поддержка ключа через --dart-define (предпочтительно для совместной разработки)
const String _apiKeyFromDefine = String.fromEnvironment('BILIM_GEMINI_API_KEY');

String _effectiveApiKey() {
  // 1) dart-define
  if (_apiKeyFromDefine.isNotEmpty) return _apiKeyFromDefine;
  // 2) фолбэк из api_key.dart
  if (apiKey.isNotEmpty && apiKey != 'YOUR_GEMINI_API_KEY_HERE') return apiKey;
  return '';
}

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
  final AuthService _auth = AuthService();
  final HistoryService _history = HistoryService();
  String _uiLang = 'ru'; // RU по умолчанию
  final ScrollController _scrollController = ScrollController();
  final List<Map<String, String>> _messages = <Map<String, String>>[]; // {role: user|assistant, content}
  // Прокрутка ответов управляется автоматически без отдельного контроллера

  @override
  void initState() {
    super.initState();
    _loadUiLang();
    _logDb('app_started');
  }

  Future<void> _loadUiLang() async {
    final p = await SharedPreferences.getInstance();
    final saved = p.getString('ui.lang');
    if (saved == null) {
      await p.setString('ui.lang', 'ru');
      _uiLang = 'ru';
    } else {
      _uiLang = (saved == 'kk') ? 'kk' : 'ru';
    }
    if (mounted) setState(() {});
  }

  String t(String key) {
    final ru = <String, String>{
      'subtitle': 'Физика • Короткие и точные ответы',
      'placeholder': 'Напишите вопрос по физике...',
      'thinking': 'Bilim AI думает...',
      'ask': 'Задайте вопрос по физике',
      'help': 'Я помогу вам!',
      'answer_title': 'Ответ Bilim AI:',
      'clear': 'Очистить',
      'info': 'Инфо',
      'close': 'Закрыть',
      'language': 'Язык',
      'ready': 'Готов',
      'sending': 'Отправка...',
      'login': 'Вход',
      'register': 'Регистрация',
      'guest': 'Гость',
      'logout': 'Выход',
      'cancel': 'Отмена',
      'history': 'История',
      'info_title': 'О Bilim AI',
      'info_desc': 'Bilim AI — это ИИ-помощник по физике.',
      'features': 'Возможности:',
      'f1': '• Решение задач по физике',
      'f2': '• Объяснение понятий',
      'f3': '• Формулы и уравнения',
      'f4': '• Ответы на русском и казахском',
      'examples': 'Примеры:',
      'ex1': '• «Объясни третий закон Ньютона»',
      'ex2': '• «Рассчитай F = m·a»',
      'ex3': '• «Что такое закон сохранения энергии?»',
    };
    final kk = <String, String>{
      'subtitle': 'Физика • Қысқа және нақты жауап',
      'placeholder': 'Физика бойынша сұрағыңызды жазыңыз...',
      'thinking': 'Bilim AI ойланып жатыр...',
      'ask': 'Физика бойынша сұрақ қойыңыз',
      'help': 'Мен сізге көмектесе аламын!',
      'answer_title': 'Bilim AI жауабы:',
      'clear': 'Тазалау',
      'info': 'Ақпарат',
      'close': 'Жабу',
      'language': 'Тіл',
      'ready': 'Дайын',
      'sending': 'Жіберілуде...',
      'login': 'Кіру',
      'register': 'Тіркелу',
      'guest': 'Қонақ',
      'logout': 'Шығу',
      'cancel': 'Болдырмау',
      'history': 'Тарих',
      'info_title': 'Bilim AI туралы',
      'info_desc': 'Bilim AI — физика бойынша маманданған ЖИ көмекшісі.',
      'features': 'Мүмкіндіктер:',
      'f1': '• Физика есептерін шешу',
      'f2': '• Ұғымдарды түсіндіру',
      'f3': '• Формулалар мен теңдеулер',
      'f4': '• Орыс және қазақ тілдерінде жауап',
      'examples': 'Қолдану мысалдары:',
      'ex1': '• «Ньютонның үшінші заңын түсіндір»',
      'ex2': '• «F = m·a формуласын есепте»',
      'ex3': '• «Энергия сақталу заңы дегеніміз не?»',
    };
    final dict = _uiLang == 'kk' ? kk : ru;
    return dict[key] ?? key;
  }

  Future<void> _logDb(String message) async {
    try {
      await Supabase.instance.client.from('app_log').insert({
        'message': message,
      });
    } catch (_) {
      // ignore
    }
  }

  // Рендер обычного текста с поддержкой **жирного** (простая Markdown-эвристика)
  Widget _buildMarkdownText(String text) {
    final defaultStyle = const TextStyle(fontSize: 16, height: 1.6, color: Colors.black87);
    final boldReg = RegExp(r'\*\*(.+?)\*\*', dotAll: true);
    final spans = <TextSpan>[];
    int last = 0;
    for (final m in boldReg.allMatches(text)) {
      if (m.start > last) {
        spans.add(TextSpan(text: text.substring(last, m.start)));
      }
      spans.add(TextSpan(text: m.group(1)!, style: const TextStyle(fontWeight: FontWeight.w600)));
      last = m.end;
    }
    if (last < text.length) {
      spans.add(TextSpan(text: text.substring(last)));
    }
    return RichText(text: TextSpan(style: defaultStyle, children: spans));
  }

  // Рендер ответа с поддержкой inline TeX ($...$) и **жирного** текста
  Widget _buildResponseWidget(String text) {
    final texReg = RegExp(r'\$(.+?)\$', dotAll: true);
    final widgets = <Widget>[];
    int last = 0;
    for (final m in texReg.allMatches(text)) {
      if (m.start > last) {
        final pre = text.substring(last, m.start);
        if (pre.isNotEmpty) widgets.add(_buildMarkdownText(pre));
      }
      final tex = m.group(1)!;
      widgets.add(Math.tex(
        tex,
        mathStyle: MathStyle.text,
        textStyle: const TextStyle(fontSize: 16, height: 1.6, color: Colors.black87),
      ));
      last = m.end;
    }
    if (last < text.length) {
      final tail = text.substring(last);
      if (tail.isNotEmpty) widgets.add(_buildMarkdownText(tail));
    }

    if (widgets.isEmpty) {
      return _buildMarkdownText(text);
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (int i = 0; i < widgets.length; i++) ...[
          widgets[i],
          if (i != widgets.length - 1) const SizedBox(height: 4),
        ],
      ],
    );
  }

  // Простейшее определение языка: наличие специфических казахских символов
  String _detectLanguage(String text) {
    const kkChars = [
      'ә', 'ғ', 'қ', 'ң', 'ө', 'ұ', 'ү', 'һ', 'і',
      'Ә', 'Ғ', 'Қ', 'Ң', 'Ө', 'Ұ', 'Ү', 'Һ', 'І',
    ];
    for (final ch in kkChars) {
      if (text.contains(ch)) return 'kk';
    }
    return 'ru';
  }

  // Специализированный промпт для физики
  String _getPhysicsPrompt(String userQuestion) {
    final lang = _detectLanguage(userQuestion);
    final enforce = lang == 'kk'
        ? 'Тіл: қазақша. Жауапты қатаң қазақ тілінде бер.'
        : 'Язык: русский. Отвечай строго на русском языке.';
  return '''$enforce
Ты — Bilim AI, умный двуязычный помощник по физике.  
Ты умеешь отвечать **на русском и казахском языках**, в зависимости от того, на каком языке задал вопрос пользователь.  
Если пользователь пишет по-русски — отвечай на русском.  
Если пишет по-казахски — отвечай по-казахски.  
Никогда не смешивай языки в одном ответе.

────────────────────────────
🎯 **ТВОЯ ЦЕЛЬ**
Помогать школьникам и студентам изучать физику, объясняя законы, решая задачи и приводя формулы.  
Ты — строгий, точный, логичный и короткий в ответах.

────────────────────────────
⚙️ **ПРАВИЛА ОБЩЕНИЯ**
1. Отвечай **только на вопросы по физике**.  
   ❗ Если вопрос не по физике — пиши:  
   "Извините, я отвечаю только на вопросы по физике."  
   или на казахском:  
   "Кешіріңіз, мен тек физика сұрақтарына жауап беремін."
2. Определи язык вопроса (русский или казахский) и используй его в ответе.  
3. Всегда указывай **формулы, единицы измерения** и **последовательность решения**.  
4. Структура ответа:  
   **Дано → Формула → Подстановка → Вычисление → Ответ.**
5. В конце — обязательно единица измерения (Н, Дж, м/с, кг, т.д.).
6. Если вопрос теоретический — дай **краткое определение + физический смысл.**
7. Если задача с числовыми данными — **обязательно покажи подстановку и вычисление.**
8. Отвечай **коротко**, максимум **5 предложений**.
9. Не выдумывай формулы. Используй только реальные физические законы.
10. Не добавляй ничего, кроме физического ответа.  
11. Не используй «вода», не рассуждай о жизни, истории, астрологии, шутках и прочем.  

────────────────────────────
📘 **СТИЛЬ ОТВЕТА**
- Научный, спокойный, уверенный.  
- Без эмоций, без личного мнения.  
- Без "я думаю", "наверное", "возможно".  
- Всё строго, логично и кратко.  
- Для формул используй стандартную запись: F=ma, v=s/t, E=mc² и т.д.

────────────────────────────
🧠 **ДОПОЛНИТЕЛЬНЫЕ ПРАВИЛА**
- Если данных не хватает — скажи, каких данных не хватает (например: “Не указано время”).  
- Если есть несколько вариантов решения — выбери самый простой.  
- Проверяй размерность результата (не допусти ошибок в единицах).  
- Если задача из школьного курса — решай по школьной методике.  
- Если задача сложная (например, с энергией, сопротивлением) — всё равно объясняй кратко и по шагам.

────────────────────────────
📗 **ТЕМЫ, КОТОРЫЕ ТЫ МОЖЕШЬ ОБСУЖДАТЬ**
- Механика (движение, сила, трение, ускорение, работа, энергия, импульс)
- Термодинамика (температура, тепло, давление, газовые законы)
- Электричество и магнетизм (ток, сопротивление, напряжение, магнитное поле)
- Оптика (отражение, преломление, линзы, зеркала)
- Колебания и волны (частота, амплитуда, период, звук)
- Астрономическая и ядерная физика (в пределах школьного уровня)
- Единицы СИ, измерения, физические константы

────────────────────────────
📐 **БАЗОВЫЕ ФОРМУЛЫ (для внутреннего понимания)**
- Второй закон Ньютона: F = ma  
- Давление: p = F / S  
- Работа: A = F·s  
- Мощность: N = A / t  
- Потенциальная энергия: Eₚ = mgh  
- Кинетическая энергия: Eₖ = mv² / 2  
- Закон Ома: I = U / R  
- Сопротивление: R = ρ·(l / S)  
- Количество теплоты: Q = c·m·Δt  
- Уравнение теплового баланса: Q₁ = Q₂  
- Скорость: v = s / t  
- Плотность: ρ = m / V  

────────────────────────────
🧾 **ПРИМЕРЫ ОТВЕТОВ**

🇷🇺 Русский пример:
Вопрос: “Тело массой 3 кг движется с ускорением 4 м/с². Найди силу.”
Ответ:  
Дано: m=3 кг, a=4 м/с².  
Формула: F=ma.  
Подстановка: 3·4=12 Н.  
Ответ: **12 Н.**

🇰🇿 Қазақ мысалы:
Сұрақ: “Массасы 3 кг дене 4 м/с² үдеумен қозғалады. Күшті тап.”  
Жауап:  
Берілгені: m=3 кг, a=4 м/с².  
Формула: F=ma.  
Қою: 3·4=12 Н.  
Жауап: **12 Н.**

────────────────────────────
Если пользователь задаёт вопрос на другом языке (английском, китайском, и т.д.) —  
ответь:  
"Извините, я отвечаю только на русском или казахском языках."  
или  
"Кешіріңіз, мен тек орыс және қазақ тілдерінде жауап беремін."

────────────────────────────
📍 Вопрос пользователя:
$userQuestion
''';
}

  // Диалог с информацией о приложении
  void _showInfoDialog() {
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: Text(t('info_title')),
          content: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(t('info_desc'), style: const TextStyle(fontSize: 16)),
                SizedBox(height: 16),
                Text(t('features'), style: const TextStyle(fontWeight: FontWeight.bold)),
                SizedBox(height: 8),
                Text(t('f1')),
                Text(t('f2')),
                Text(t('f3')),
                Text(t('f4')),
                SizedBox(height: 16),
                Text(t('examples'), style: const TextStyle(fontWeight: FontWeight.bold)),
                SizedBox(height: 8),
                Text(t('ex1')),
                Text(t('ex2')),
                Text(t('ex3')),
              ],
            ),
          ),
          actions: [
            TextButton(
              child: Text(t('close')),
              onPressed: () {
                Navigator.of(context).pop();
              },
            ),
          ],
        );
      },
    );
  }

  void _showAuthDialog() {
    final emailCtrl = TextEditingController();
    final passCtrl = TextEditingController();
    bool isLogin = true;
    bool busy = false;
    showDialog(
      context: context,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setS) => AlertDialog(
            title: Text(isLogin ? t('login') : t('register')),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (busy)
                    const LinearProgressIndicator(minHeight: 2),
                  TextField(
                    controller: emailCtrl,
                    decoration: const InputDecoration(labelText: 'Email'),
                  ),
                  TextField(
                    controller: passCtrl,
                    decoration: InputDecoration(labelText: _uiLang == 'kk' ? 'Құпиясөз' : 'Пароль'),
                    obscureText: true,
                  ),
                  const SizedBox(height: 8),
                  TextButton(
                    onPressed: () => setS(() => isLogin = !isLogin),
                    child: Text(isLogin ? t('register') : t('login')),
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () async {
                  await _auth.continueAsGuest();
                  if (mounted) setState(() {});
                  Navigator.pop(ctx);
                },
                child: Text(t('guest')),
              ),
              TextButton(
                onPressed: () async {
                  final email = emailCtrl.text.trim();
                  final pass = passCtrl.text;
                  bool ok;
                  try {
                    setS(() => busy = true);
                    if (isLogin) {
                      ok = await _auth.login(email, pass);
                    } else {
                      if (pass.length < 6) {
                        throw Exception(_uiLang == 'kk' ? 'Құпиясөз кемінде 6 таңба' : 'Пароль минимум 6 символов');
                      }
                      ok = await _auth.register(email, pass);
                    }
                  } catch (e) {
                    ok = false;
                    if (ctx.mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(content: Text(e.toString())),
                      );
                    }
                  } finally {
                    setS(() => busy = false);
                  }
                  if (ok) {
                    if (mounted) setState(() {});
                    if (ctx.mounted) Navigator.pop(ctx);
                  } else {
                    if (ctx.mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(content: Text(isLogin ? (_uiLang == 'kk' ? 'Қате email/пароль' : 'Неверный email/пароль') : (_uiLang == 'kk' ? 'Мұндай email бар' : 'Email уже существует'))),
                      );
                    }
                  }
                },
                child: Text(isLogin ? 'Кіру' : 'Тіркелу'),
              ),
            ],
          ),
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
    // Добавляем сообщение пользователя в чат
    _messages.add({'role': 'user', 'content': _textController.text});
    _aiResponse = null;
  });

  try {
    final physicsPrompt = _getPhysicsPrompt(_textController.text);

    Future<http.Response> _callModel(String modelName) {
      final effectiveKey = _effectiveApiKey();
      if (effectiveKey.isEmpty) {
        return Future.value(http.Response(
            jsonEncode({
              'error':
                  'API ключ не найден. Передайте ключ через --dart-define=BILIM_GEMINI_API_KEY=... или задайте его в lib/api_key.dart.'
            }),
            400));
      }
      final url = Uri.parse(
          'https://generativelanguage.googleapis.com/v1/models/'
          '$modelName:generateContent?key=$effectiveKey');
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
            'temperature': 0.3,
            'topK': 32,
            'topP': 0.9,
            'maxOutputTokens': 1024
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
        _messages.add({'role': 'assistant', 'content': text});
      });
      // Save history for logged-in users (local + Supabase)
      final email = await _auth.currentUserEmail();
      if (email != null && email.isNotEmpty) {
        await _history.addEntry(
          email: email,
          question: _textController.text,
          answer: text,
          at: DateTime.now(),
        );
        try {
          final uid = Supabase.instance.client.auth.currentUser?.id;
          await Supabase.instance.client.from('user_history').insert({
            'user_id': uid,
            'email': email,
            'question': _textController.text,
            'answer': text,
          });
          // Также пишем простое сообщение в таблицу telegram_messages (демо)
          await Supabase.instance.client.from('telegram_messages').insert({
            'from_user_id': uid ?? 'guest',
            'from_username': email,
            'to_user_id': 'bilim_ai',
            'message': _textController.text,
          });
        } catch (_) {
          // ignore SB error, keep local history
        }
      }
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
    // Прокручиваем вниз после ответа
    await Future.delayed(const Duration(milliseconds: 50));
    if (_scrollController.hasClients) {
      _scrollController.animateTo(
        _scrollController.position.maxScrollExtent,
        duration: const Duration(milliseconds: 250),
        curve: Curves.easeOut,
      );
    }
  }

}

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        scrolledUnderElevation: 0,
        surfaceTintColor: Colors.transparent,
        actions: [
          // Language picker RU/KZ
          IconButton(
            icon: const Icon(Icons.language, color: Color(0xFF2B6CB0)),
            tooltip: _uiLang == 'kk' ? t('language') : t('language'),
            onPressed: () async {
              final choice = await showDialog<String>(
                context: context,
                builder: (ctx) => SimpleDialog(
                  title: Text(_uiLang == 'kk' ? 'Тілді таңдаңыз' : 'Выберите язык'),
                  children: [
                    SimpleDialogOption(
                      onPressed: () => Navigator.pop(ctx, 'kk'),
                      child: const Text('Қазақша'),
                    ),
                    SimpleDialogOption(
                      onPressed: () => Navigator.pop(ctx, 'ru'),
                      child: const Text('Русский'),
                    ),
                  ],
                ),
              );
              if (choice != null) {
                final p = await SharedPreferences.getInstance();
                await p.setString('ui.lang', choice);
                _uiLang = choice;
                if (mounted) setState(() {});
              }
            },
          ),
          FutureBuilder<String?>(
            future: _auth.currentUserEmail(),
            builder: (context, snapshot) {
              final email = snapshot.data;
              final loggedIn = email != null && email.isNotEmpty;
              return PopupMenuButton<String>(
                icon: Icon(loggedIn ? Icons.account_circle : Icons.login, color: const Color(0xFF2B6CB0)),
                tooltip: loggedIn ? (email) : t('login'),
                onSelected: (value) async {
                  if (value == 'login') {
                    _showAuthDialog();
                  } else if (value == 'logout') {
                    await _auth.logout();
                    if (mounted) setState(() {});
                  } else if (value == 'history') {
                    if (!loggedIn) {
                      _showAuthDialog();
                      return;
                    }
                    if (context.mounted) {
                      Navigator.of(context).push(
                        MaterialPageRoute(builder: (_) => const HistoryScreen()),
                      );
                    }
                  }
                },
                itemBuilder: (ctx) {
                  if (!loggedIn) {
                    return [
                      PopupMenuItem(value: 'login', child: Text(t('login'))),
                    ];
                  }
                  return [
                    PopupMenuItem(value: 'history', child: Text(t('history'))),
                    PopupMenuItem(value: 'logout', child: Text(t('logout'))),
                  ];
                },
              );
            },
          ),
          IconButton(
            icon: const Icon(Icons.info_outline, color: Color(0xFF2B6CB0)),
            onPressed: _showInfoDialog,
            tooltip: t('info'),
          ),
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          children: [
            // Large Title (iOS style)
            const Align(
              alignment: Alignment.centerLeft,
              child: Text(
                'Bilim AI',
                style: TextStyle(
                  fontSize: 34,
                  fontWeight: FontWeight.w700,
                  letterSpacing: -0.5,
                ),
              ),
            ),
            const SizedBox(height: 8),
            Align(
              alignment: Alignment.centerLeft,
              child: Text(
                t('subtitle'),
                style: TextStyle(
                  color: Colors.grey[600],
                  fontSize: 14,
                ),
              ),
            ),
            const SizedBox(height: 16),
            // Поле для ввода текста с улучшенным дизайном
            Container(
              decoration: BoxDecoration(
                color: Colors.grey[50],
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.grey[300]!),
              ),
              child: Focus(
                onKeyEvent: (node, event) {
                  if (event is KeyDownEvent && event.logicalKey == LogicalKeyboardKey.enter) {
                    final bool isShift = HardwareKeyboard.instance.isShiftPressed;
                    if (!isShift && !_isLoading && _textController.text.trim().isNotEmpty) {
                      _sendToAI();
                      return KeyEventResult.handled; // не вставляем перевод строки
                    }
                  }
                  return KeyEventResult.ignored;
                },
                child: TextField(
                  controller: _textController,
                  maxLines: 3,
                  keyboardType: TextInputType.multiline,
                  textInputAction: TextInputAction.newline,
                  onSubmitted: (_) {
                    if (!_isLoading && _textController.text.trim().isNotEmpty) {
                      _sendToAI();
                    }
                  },
                  decoration: InputDecoration(
                  hintText: t('placeholder'),
                    hintStyle: TextStyle(color: Colors.grey[600]),
                    border: InputBorder.none,
                    contentPadding: const EdgeInsets.all(16),
                  ),
                  style: const TextStyle(fontSize: 16),
                ),
              ),
            ),
            const SizedBox(height: 16),
            // Кнопка "Жіберу" с улучшенным дизайном
            // Input actions (iOS pill + circular send)
            Row(
              children: [
                Expanded(
                  child: Container(
                    decoration: BoxDecoration(
                      color: Colors.grey[50],
                      borderRadius: BorderRadius.circular(24),
                      border: Border.all(color: Colors.grey[300]!),
                    ),
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                    child: Row(
                      children: [
                        Expanded(
                          child: Text(
                            _isLoading ? t('sending') : t('ready'),
                            style: TextStyle(color: Colors.grey[600]),
                          ),
                        ),
                        IconButton(
                          icon: const Icon(Icons.clear, size: 20),
                          tooltip: t('clear'),
                          onPressed: () {
                            _textController.clear();
                            setState(() { _aiResponse = null; });
                          },
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                SizedBox(
                  width: 52,
                  height: 52,
                  child: ElevatedButton(
                    onPressed: _isLoading ? null : _sendToAI,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF2B6CB0),
                      foregroundColor: Colors.white,
                      shape: const CircleBorder(),
                      elevation: 2,
                    ),
                    child: _isLoading
                        ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                            ),
                          )
                        : const Icon(Icons.send),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 20),
            // Чат: список пузырей сообщений
            Expanded(
              child: Container(
                width: double.infinity,
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.grey[300]!),
                ),
                child: _messages.isEmpty
                    ? Center(
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
                              t('ask'),
                              style: TextStyle(
                                fontSize: 18,
                                color: Colors.grey[600],
                              ),
                            ),
                            const SizedBox(height: 8),
                            Text(
                              t('help'),
                              style: TextStyle(
                                fontSize: 14,
                                color: Colors.grey[500],
                              ),
                            ),
                          ],
                        ),
                      )
                    : ListView.builder(
                        controller: _scrollController,
                        padding: const EdgeInsets.all(16),
                        itemCount: _messages.length + (_isLoading ? 1 : 0),
                        itemBuilder: (context, index) {
                          if (_isLoading && index == _messages.length) {
                            return Align(
                              alignment: Alignment.centerLeft,
                              child: Container(
                                margin: const EdgeInsets.only(bottom: 12),
                                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                                decoration: BoxDecoration(
                                  color: Colors.grey[100],
                                  borderRadius: BorderRadius.circular(16),
                                  border: Border.all(color: Colors.grey[300]!),
                                ),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    const SizedBox(
                                      width: 16,
                                      height: 16,
                                      child: CircularProgressIndicator(strokeWidth: 2),
                                    ),
                                    const SizedBox(width: 8),
                                    Text(t('thinking'), style: TextStyle(color: Colors.grey[700])),
                                  ],
                                ),
                              ),
                            );
                          }
                          final m = _messages[index];
                          final isUser = m['role'] == 'user';
                          final content = m['content'] ?? '';
                          return Align(
                            alignment: isUser ? Alignment.centerRight : Alignment.centerLeft,
                            child: Container(
                              constraints: const BoxConstraints(maxWidth: 680),
                              margin: const EdgeInsets.only(bottom: 12),
                              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                              decoration: BoxDecoration(
                                color: isUser ? const Color(0xFF2B6CB0) : Colors.white,
                                borderRadius: BorderRadius.circular(16),
                                border: Border.all(color: isUser ? const Color(0xFF2B6CB0) : Colors.grey[300]!),
                              ),
                              child: isUser
                                  ? SelectableText(
                                      content,
                                      style: const TextStyle(color: Colors.white, fontSize: 16, height: 1.5),
                                    )
                                  : _buildResponseWidget(content),
                            ),
                          );
                        },
                      ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}