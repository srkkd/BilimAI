// lib/home_screen.dart
import 'package:flutter/material.dart';
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'dart:async';
import 'api_key.dart';
import 'package:flutter_math_fork/flutter_math.dart';
import 'package:flutter/services.dart';
import 'auth.dart';
import 'history.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'history_screen.dart';

const String kGeminiKeyFromEnv = String.fromEnvironment('BILIM_GEMINI_API_KEY', defaultValue: '');

class HomeScreen extends StatefulWidget {
  final String? initialChatId;
  const HomeScreen({super.key, this.initialChatId});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> with TickerProviderStateMixin {
  final TextEditingController _textController = TextEditingController();
  String? _aiResponse;
  bool _isLoading = false;
  String? _cachedModelName;
  final AuthService _auth = AuthService();
  final HistoryService _history = HistoryService();
  String _uiLang = 'ru';
  final ScrollController _scrollController = ScrollController();
  final List<Map<String, String>> _messages = <Map<String, String>>[];
  late AnimationController _animationController;
  late Animation<double> _fadeAnimation;
  static const Duration _httpTimeout = Duration(seconds: 20);
  bool _loggedIn = false;
  String? _chatId;
  DateTime? _chatCreatedAt;
  static const String _apiBase = 'http://localhost:4000';

  @override
  void initState() {
    super.initState();
    _loadUiLang();
    _logDb('app_started');
    _animationController = AnimationController(
      duration: const Duration(milliseconds: 300),
      vsync: this,
    );
    _fadeAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _animationController, curve: Curves.easeInOut),
    );
    _animationController.forward();
    _refreshAuthState();
    if (widget.initialChatId != null) {
      _chatId = widget.initialChatId;
      _loadMessagesForChat(widget.initialChatId!);
    }
  }

  Future<void> _loadMessagesForChat(String chatId) async {
    final token = await _getToken();
    if (token == null || token.isEmpty) return;
    try {
      final resp = await http.get(
        Uri.parse('$_apiBase/messages/$chatId'),
        headers: { 'Authorization': 'Bearer $token' },
      ).timeout(const Duration(seconds: 15));
      if (resp.statusCode == 200) {
        final data = jsonDecode(resp.body) as List;
        final msgs = <Map<String, String>>[];
        for (final m in data) {
          final role = (m['role'] as String?) ?? 'assistant';
          final content = (m['content'] as String?) ?? '';
          msgs.add({'role': role, 'content': content});
        }
        if (mounted) setState(() {
          _messages
            ..clear()
            ..addAll(msgs);
        });
        WidgetsBinding.instance.addPostFrameCallback((_) => _scrollToBottom());
      }
    } catch (_) {}
  }

  Future<void> _refreshAuthState() async {
    try {
      final v = await _auth.isLoggedIn();
      if (mounted) setState(() => _loggedIn = v);
    } catch (_) {}
  }

  Future<String?> _getToken() async {
    final p = await SharedPreferences.getInstance();
    return p.getString('auth.token');
  }

  Future<void> _startNewChat() async {
    setState(() {
      _messages.clear();
      _chatId = null;
      _chatCreatedAt = null;
    });
  }

  Future<void> _ensureChat(String title) async {
    if (_chatId != null) return;
    final token = await _getToken();
    if (token == null || token.isEmpty) {
      // гость: не создаем чат на сервере, работаем локально
      return;
    }
    try {
      final resp = await http
          .post(
        Uri.parse('$_apiBase/chats'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $token',
        },
        body: jsonEncode({'title': title}),
      )
          .timeout(const Duration(seconds: 15));
      if (resp.statusCode == 201) {
        final data = jsonDecode(resp.body) as Map<String, dynamic>;
        setState(() {
          _chatId = data['id'] as String?;
          final ts = data['createdAt'] as String?;
          _chatCreatedAt = ts != null ? DateTime.tryParse(ts) : DateTime.now();
        });
      }
    } catch (_) {}
  }

  Future<void> _postMessage(String role, String content) async {
    final chatId = _chatId;
    if (chatId == null) return;
    final token = await _getToken();
    if (token == null || token.isEmpty) return;
    try {
      await http
          .post(
        Uri.parse('$_apiBase/messages/$chatId'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $token',
        },
        body: jsonEncode({'role': role, 'content': content}),
      )
          .timeout(const Duration(seconds: 15));
    } catch (_) {}
  }

  String _sanitize(String s) {
    String out = s;
    // Remove Markdown headings (#, ##, ...)
    out = out.replaceAll(RegExp(r'^\s*#{1,6}\s*', multiLine: true), '');
    // Replace Markdown bullets (* or •) with '- '
    out = out.replaceAll(RegExp(r'^\s*[\*\u2022]\s+', multiLine: true), '- ');
    // Remove horizontal rules (---, ***)
    out = out.replaceAll(RegExp(r'^\s*[-*_]{3,}\s*$', multiLine: true), '');
    // Remove unknown object replacement char
    out = out.replaceAll('\uFFFC', '');
    // Collapse excessive blank lines
    out = out.replaceAll(RegExp(r'\n{3,}'), '\n\n');
    return out.trim();
  }

  @override
  void dispose() {
    _animationController.dispose();
    super.dispose();
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
      'logout': 'Выход',
      'history': 'История',
      'email': 'Email',
      'password': 'Пароль',
      'confirm_password': 'Подтвердите пароль',
      'cancel': 'Отмена',
      'save': 'Сохранить',
      'info_title': 'О приложении',
      'info_desc': 'Bilim AI - ваш персональный помощник по физике. Задавайте вопросы и получайте точные, краткие ответы.',
      'welcome_title': 'Добро пожаловать в Bilim AI',
      'welcome_subtitle': 'Ваш персональный помощник по физике',
      'welcome_prompt': 'Задайте любой вопрос по физике',
      'new_chat': 'Новый чат',
      'about': 'О нас',
      'about_title': 'О BilimAI',
      'about_desc': 'BilimAI — умный помощник для обучения физике: краткие и точные ответы, понятные объяснения и формулы.',
      'who_dev': 'Кто разработал',
      'who_dev_desc': 'BilimAI разработали студенты 3 курса колледжа Astana IT University, группа ПО-2309: Серик и Аружан.',
      'support': 'Тех. поддержка',
      'support_desc': 'Telegram разработчиков:\nСерик — @sssssrkd\nАружан — @aruwknva',
    };
    final kk = <String, String>{
      'subtitle': 'Физика • Қысқа және нақты жауап',
      'placeholder': 'Физика бойынша сұрақ жазыңыз...',
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
      'logout': 'Шығу',
      'history': 'Тарих',
      'email': 'Email',
      'password': 'Құпия сөз',
      'confirm_password': 'Құпия сөзді растаңыз',
      'cancel': 'Болдырмау',
      'save': 'Сақтау',
      'info_title': 'Қосымша туралы',
      'info_desc': 'Bilim AI - физика бойынша жеке көмекшіңіз. Сұрақ қойып, дәл, қысқа жауап алыңыз.',
      'welcome_title': 'Bilim AI-ға қош келдіңіз',
      'welcome_subtitle': 'Физика бойынша жеке көмекшіңіз',
      'welcome_prompt': 'Физика бойынша кез келген сұрақ қойыңыз',
      'new_chat': 'Жаңа чат',
      'about': 'Біз туралы',
      'about_title': 'BilimAI туралы',
      'about_desc': 'BilimAI — физиканы үйренуге арналған ақылды көмекші: қысқа әрі нақты жауаптар, түсінікті түсіндіру және формулалар.',
      'who_dev': 'Кім әзірледі',
      'who_dev_desc': 'BilimAI — Astana IT University колледжінің 3-курс студенттері, ПО-2309 тобы: Серік және Аружан әзірледі.',
      'support': 'Тех. қолдау',
      'support_desc': 'Әзірлеушілердің Telegram-дары:\nСерік — @sssssrkd\nАружан — @aruwknva',
    };
    return (_uiLang == 'kk' ? kk : ru)[key] ?? key;
  }

  Future<void> _logDb(String event) async {
    try {
      await Supabase.instance.client.from('telegram_messages').insert({
        'from_user_id': 'system',
        'from_username': 'system',
        'to_user_id': 'bilim_ai',
        'message': event,
      });
    } catch (_) {
      // ignore
    }
  }

  Future<void> _showLanguageDialog() async {
    String? choice = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(t('language')),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              title: const Text('Русский'),
              leading: Radio<String>(value: 'ru', groupValue: _uiLang, onChanged: (v) => Navigator.pop(context, v)),
            ),
            ListTile(
              title: const Text('Қазақша'),
              leading: Radio<String>(value: 'kk', groupValue: _uiLang, onChanged: (v) => Navigator.pop(context, v)),
            ),
          ],
        ),
      ),
    );
    if (choice != null) {
      final p = await SharedPreferences.getInstance();
      await p.setString('ui.lang', choice);
      _uiLang = choice;
      if (mounted) setState(() {});
    }
  }

  Future<void> _showAuthDialog() async {
    final emailController = TextEditingController();
    final passwordController = TextEditingController();
    final confirmPasswordController = TextEditingController();
    bool isLogin = true;
    bool isLoading = false;

    await showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          backgroundColor: Colors.white,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
          titlePadding: const EdgeInsets.fromLTRB(24, 20, 24, 0),
          contentPadding: const EdgeInsets.fromLTRB(24, 12, 24, 24),
          title: Row(
            children: [
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: const Color(0xFFF1F5F9),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(Icons.lock_outline, color: Color(0xFF64748B), size: 20),
              ),
              const SizedBox(width: 12),
              Text(
                isLogin ? t('login') : t('register'),
                style: const TextStyle(fontWeight: FontWeight.w700),
              ),
            ],
          ),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (isLoading) const LinearProgressIndicator(minHeight: 2),
                const SizedBox(height: 12),
                TextField(
                  controller: emailController,
                  keyboardType: TextInputType.emailAddress,
                  decoration: InputDecoration(
                    prefixIcon: const Icon(Icons.alternate_email),
                    labelText: t('email'),
                    filled: true,
                    fillColor: const Color(0xFFF8FAFC),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: const BorderSide(color: Color(0xFFE2E8F0)),
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: passwordController,
                  obscureText: true,
                  decoration: InputDecoration(
                    prefixIcon: const Icon(Icons.lock),
                    labelText: t('password'),
                    filled: true,
                    fillColor: const Color(0xFFF8FAFC),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: const BorderSide(color: Color(0xFFE2E8F0)),
                    ),
                  ),
                ),
                if (!isLogin) ...[
                  const SizedBox(height: 12),
                  TextField(
                    controller: confirmPasswordController,
                    obscureText: true,
                    decoration: InputDecoration(
                      prefixIcon: const Icon(Icons.lock_outline),
                      labelText: t('confirm_password'),
                      filled: true,
                      fillColor: const Color(0xFFF8FAFC),
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: const BorderSide(color: Color(0xFFE2E8F0)),
                      ),
                    ),
                  ),
                ],
                const SizedBox(height: 16),
                Wrap(
                  alignment: WrapAlignment.spaceBetween,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  runSpacing: 8,
                  spacing: 8,
                  children: [
                    TextButton(
                      onPressed: () => setDialogState(() => isLogin = !isLogin),
                      child: Text(isLogin ? t('register') : t('login')),
                    ),
                    Wrap(
                      spacing: 8,
                      children: [
                        OutlinedButton(
                          onPressed: () => Navigator.pop(context),
                          child: Text(t('cancel')),
                        ),
                        ElevatedButton(
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFF3B82F6),
                            foregroundColor: Colors.white,
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                          ),
                          onPressed: isLoading ? null : () async {
                            setDialogState(() => isLoading = true);
                            try {
                              if (isLogin) {
                                await _auth.login(emailController.text, passwordController.text);
                              } else {
                                if (passwordController.text != confirmPasswordController.text) {
                                  throw Exception('Пароли не совпадают');
                                }
                                await _auth.register(emailController.text, passwordController.text);
                              }
                              if (mounted) {
                                Navigator.pop(context);
                                setState(() {});
                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(content: Text(isLogin ? 'Вход выполнен' : 'Регистрация успешна')),
                                );
                              }
                            } catch (e) {
                              if (mounted) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(content: Text('Ошибка: ${e.toString()}')),
                                );
                              }
                            } finally {
                              if (mounted) setDialogState(() => isLoading = false);
                            }
                          },
                          child: Text(isLogin ? t('login') : t('register')),
                        ),
                      ],
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _showInfoDialog() async {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(t('info_title')),
        content: Text(t('info_desc')),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(t('close')),
          ),
        ],
      ),
    );
  }

  Future<void> _showAboutDialog() async {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Row(
          children: [
            Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                color: const Color(0xFFF1F5F9),
                borderRadius: BorderRadius.circular(10),
              ),
              child: const Icon(Icons.info_outline, color: Color(0xFF64748B), size: 20),
            ),
            const SizedBox(width: 12),
            Text(t('about_title'), style: const TextStyle(fontWeight: FontWeight.w700)),
          ],
        ),
        content: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(t('about_desc')),
              const SizedBox(height: 16),
              Text(t('who_dev'), style: const TextStyle(fontWeight: FontWeight.w600)),
              const SizedBox(height: 6),
              Text(t('who_dev_desc')),
              const SizedBox(height: 16),
              Text(t('support'), style: const TextStyle(fontWeight: FontWeight.w600)),
              const SizedBox(height: 6),
              Text(t('support_desc')),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(t('close')),
          ),
        ],
      ),
    );
  }

  Future<String?> _discoverSupportedModel() async {
    try {
      final effectiveKey = _effectiveApiKey();
      if (effectiveKey.isEmpty) return null;
      
      final url = Uri.parse('https://generativelanguage.googleapis.com/v1/models?key=$effectiveKey');
      final response = await http.get(url).timeout(_httpTimeout);
      
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final models = (data['models'] as List?) ?? const [];

        String asId(dynamic m) {
          final name = (m['name'] as String?) ?? '';
          // API возвращает 'models/<id>', нам нужен только <id>
          return name.contains('/') ? name.split('/').last : name;
        }

        // Приоритет: 2.5 flash -> 2.5 pro -> 2.0 flash -> 2.0 flash-lite -> 1.5 flash -> 1.5 pro
        for (final model in models) {
          final id = asId(model);
          if (id.contains('gemini-2.5-flash')) return id;
        }
        for (final model in models) {
          final id = asId(model);
          if (id.contains('gemini-2.5-pro')) return id;
        }
        for (final model in models) {
          final id = asId(model);
          if (id.contains('gemini-2.0-flash')) return id;
        }
        for (final model in models) {
          final id = asId(model);
          if (id.contains('gemini-2.0-flash-lite')) return id;
        }
        for (final model in models) {
          final id = asId(model);
          if (id.contains('gemini-1.5-flash')) return id;
        }
        for (final model in models) {
          final id = asId(model);
          if (id.contains('gemini-1.5-pro')) return id;
        }
      }
    } catch (_) {
      // ignore
    }
    return null;
  }

  String _effectiveApiKey() {
    if (kGeminiKeyFromEnv.isNotEmpty) return kGeminiKeyFromEnv;
    if (apiKey.isNotEmpty && apiKey != 'YOUR_GEMINI_API_KEY_HERE') return apiKey;
    return '';
  }

  Future<String?> _getUsableModel() async {
    if (_cachedModelName != null) return _cachedModelName;
    _cachedModelName = await _discoverSupportedModel();
    return _cachedModelName;
  }

  void _scrollToBottom() {
    if (_scrollController.hasClients) {
      _scrollController.animateTo(
        _scrollController.position.maxScrollExtent,
        duration: const Duration(milliseconds: 250),
        curve: Curves.easeOut,
      );
    }
  }

  Future<void> _sendToAI() async {
    if (_textController.text.isEmpty) return;

    final userText = _textController.text.trim();
    if (userText.isEmpty) return;

    setState(() {
      _isLoading = true;
      _messages.add({'role': 'user', 'content': userText});
      _aiResponse = null;
    });

    WidgetsBinding.instance.addPostFrameCallback((_) => _scrollToBottom());

    _textController.clear();

    try {
      // при первом сообщении создаем чат (для вошедших)
      final chatTitle = userText.length > 40 ? userText.substring(0, 40) + '…' : userText;
      await _ensureChat(chatTitle);
      // сохранить сообщение пользователя
      _postMessage('user', userText);

      final lower = userText.toLowerCase();
      final isGreeting = lower.contains('привет') || lower.contains('салам') || lower.contains('сәлем') || lower.contains('hi') || lower.contains('hello');
      final isIdentity = lower.contains('кто ты') || lower.contains('кто вы') || lower.contains('who are you');
      if (isGreeting || isIdentity) {
        setState(() {
          _aiResponse = 'Я отвечаю на вопросы по физике. Задайте, пожалуйста, вопрос по теме.';
          _messages.add({'role': 'assistant', 'content': _aiResponse ?? ''});
        });
        WidgetsBinding.instance.addPostFrameCallback((_) => _scrollToBottom());
        // сохранить ответ ассистента
        _postMessage('assistant', _aiResponse ?? '');
        return;
      }

      final physicsPrompt = _getPhysicsPrompt(userText);
      final isListQuery = lower.contains('все формул') || lower.contains('все формулы') || lower.contains('барлық формул') || lower.contains('all formula') || lower.contains('формул по') || lower.contains('список') || lower.contains('list');
      final Duration effectiveTimeout = isListQuery ? const Duration(seconds: 45) : _httpTimeout;
      debugPrint('[BilimAI] Sending prompt: ' + physicsPrompt.substring(0, physicsPrompt.length.clamp(0, 200)) + '...');

      Future<http.Response> _callModel(String modelName) {
        final effectiveKey = _effectiveApiKey();
        if (effectiveKey.isEmpty) {
          return Future.value(http.Response(
              jsonEncode({
                'error': 'API ключ не найден. Передайте ключ через --dart-define=BILIM_GEMINI_API_KEY=... или задайте его в lib/api_key.dart.'
              }),
              400));
        }
        final url = Uri.parse(
            'https://generativelanguage.googleapis.com/v1/models/'
            '$modelName:generateContent?key=$effectiveKey');
        return http
            .post(
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
              'maxOutputTokens': 4096
            }
          }),
        )
            .timeout(effectiveTimeout);
      }

      String? modelToUse = await _getUsableModel();
      modelToUse ??= 'gemini-2.5-flash';
      http.Response response = await _callModel(modelToUse);
      debugPrint('[BilimAI] Response status: ' + response.statusCode.toString());
      debugPrint('[BilimAI] Response body head: ' + (response.body.length > 300 ? response.body.substring(0, 300) + '...' : response.body));

      if (response.statusCode == 404) {
        final discovered = await _discoverSupportedModel();
        if (discovered != null && discovered != modelToUse) {
          _cachedModelName = discovered;
          response = await _callModel(discovered);
        } else {
          // Попробуем другие популярные варианты
          final fallbacks = <String>[
            'gemini-2.5-pro',
            'gemini-2.0-flash',
            'gemini-2.0-flash-lite',
            'gemini-1.5-flash',
            'gemini-1.5-pro',
          ];
          for (final m in fallbacks) {
            response = await _callModel(m);
            if (response.statusCode != 404) break;
          }
        }
        debugPrint('[BilimAI] After 404 fallback status: ' + response.statusCode.toString());
        debugPrint('[BilimAI] After 404 fallback body head: ' + (response.body.length > 300 ? response.body.substring(0, 300) + '...' : response.body));
      }

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        String? text;
        try {
          final candidates = data['candidates'] as List?;
          if (candidates != null && candidates.isNotEmpty) {
            final first = candidates.first;
            final content = first['content'];
            final parts = content != null ? content['parts'] as List? : null;
            if (parts != null && parts.isNotEmpty) {
              final buffer = StringBuffer();
              for (final p in parts) {
                final pt = p['text'] as String?;
                if (pt != null && pt.isNotEmpty) {
                  if (buffer.isNotEmpty) buffer.writeln();
                  buffer.write(pt);
                }
              }
              final joined = buffer.toString();
              if (joined.trim().isNotEmpty) text = joined;
            }
          }
        } catch (_) {
          text = null;
        }
        text ??= data['output'] as String?; // на случай другого формата
        text ??= data.toString();
        if (text == null || text.trim().isEmpty) {
          text = 'Не удалось получить ответ от модели. Попробуйте переформулировать вопрос.';
        }
        final sanitized = _sanitize(text ?? '');
        setState(() {
          _aiResponse = sanitized;
          _messages.add({'role': 'assistant', 'content': sanitized});
        });
        // сохранить ответ ассистента
        _postMessage('assistant', sanitized);
        WidgetsBinding.instance.addPostFrameCallback((_) => _scrollToBottom());
        
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
            await Supabase.instance.client.from('telegram_messages').insert({
              'from_user_id': uid ?? 'guest',
              'from_username': email,
              'to_user_id': 'bilim_ai',
              'message': _textController.text,
            });
          } catch (_) {
            // ignore
          }
        }
      } else if (response.statusCode == 400) {
        setState(() {
          _aiResponse = 'Ошибка 400: проверьте вопрос и параметры запроса.';
          _messages.add({'role': 'assistant', 'content': _aiResponse ?? ''});
        });
        WidgetsBinding.instance.addPostFrameCallback((_) => _scrollToBottom());
      } else if (response.statusCode == 401) {
        setState(() {
          _aiResponse = 'Ошибка 401: проверьте API-ключ Gemini.';
          _messages.add({'role': 'assistant', 'content': _aiResponse ?? ''});
        });
        WidgetsBinding.instance.addPostFrameCallback((_) => _scrollToBottom());
      } else if (response.statusCode == 403) {
        setState(() {
          _aiResponse = 'Ошибка 403: Generative Language API отключён для вашего проекта.';
          _messages.add({'role': 'assistant', 'content': _aiResponse ?? ''});
        });
        WidgetsBinding.instance.addPostFrameCallback((_) => _scrollToBottom());
      } else if (response.statusCode == 404) {
        setState(() {
          _aiResponse = 'Ошибка 404: модель недоступна для вашей учётной записи/проекта.';
          _messages.add({'role': 'assistant', 'content': _aiResponse ?? ''});
        });
        WidgetsBinding.instance.addPostFrameCallback((_) => _scrollToBottom());
      } else if (response.statusCode == 429) {
        setState(() {
          _aiResponse = 'Ошибка 429: слишком много запросов. Попробуйте позже.';
          _messages.add({'role': 'assistant', 'content': _aiResponse ?? ''});
        });
        WidgetsBinding.instance.addPostFrameCallback((_) => _scrollToBottom());
      } else if (response.statusCode >= 500) {
        setState(() {
          _aiResponse = 'Серверная ошибка Gemini. Повторите попытку позже.';
          _messages.add({'role': 'assistant', 'content': _aiResponse ?? ''});
        });
        WidgetsBinding.instance.addPostFrameCallback((_) => _scrollToBottom());
      } else {
        setState(() {
          _aiResponse = 'Ошибка ${response.statusCode}: ${response.body}';
          _messages.add({'role': 'assistant', 'content': _aiResponse ?? ''});
        });
        WidgetsBinding.instance.addPostFrameCallback((_) => _scrollToBottom());
      }
    } on TimeoutException {
      debugPrint('[BilimAI] Timeout waiting for Gemini response');
      // one-time retry with alternative model
      try {
        debugPrint('[BilimAI] Retrying with alternate model gemini-2.5-pro');
        final alt = await http
            .post(
          Uri.parse('https://generativelanguage.googleapis.com/v1/models/gemini-2.5-pro:generateContent?key=${_effectiveApiKey()}'),
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode({
            'contents': [
              {
                'role': 'user',
                'parts': [
                  {'text': _getPhysicsPrompt(userText)}
                ]
              }
            ],
            'generationConfig': {
              'temperature': 0.3,
              'topK': 32,
              'topP': 0.9,
              'maxOutputTokens': 4096
            }
          }),
        ).timeout(const Duration(seconds: 45));
        if (alt.statusCode == 200) {
          final data = jsonDecode(alt.body);
          String? text;
          try {
            final candidates = data['candidates'] as List?;
            if (candidates != null && candidates.isNotEmpty) {
              final first = candidates.first;
              final content = first['content'];
              final parts = content != null ? content['parts'] as List? : null;
              if (parts != null && parts.isNotEmpty) {
                final buffer = StringBuffer();
                for (final p in parts) {
                  final pt = p['text'] as String?;
                  if (pt != null && pt.isNotEmpty) {
                    if (buffer.isNotEmpty) buffer.writeln();
                    buffer.write(pt);
                  }
                }
                final joined = buffer.toString();
                if (joined.trim().isNotEmpty) text = joined;
              }
            }
          } catch (_) {}
          text ??= data['output'] as String?;
          text ??= data.toString();
          final sanitized = _sanitize(text ?? '');
          setState(() {
            _aiResponse = sanitized;
            _messages.add({'role': 'assistant', 'content': sanitized});
          });
          WidgetsBinding.instance.addPostFrameCallback((_) => _scrollToBottom());
          return;
        }
      } catch (e) {
        debugPrint('[BilimAI] Retry failed: ' + e.toString());
      }
      setState(() {
        _aiResponse = 'Таймаут запроса. Проверьте интернет или попробуйте запрос короче.';
        _messages.add({'role': 'assistant', 'content': _aiResponse ?? ''});
      });
      WidgetsBinding.instance.addPostFrameCallback((_) => _scrollToBottom());
    } catch (e) {
      debugPrint('[BilimAI] Exception: ' + e.toString());
      setState(() {
        _aiResponse = 'Произошла ошибка: ${e.toString()}';
        _messages.add({'role': 'assistant', 'content': _aiResponse ?? ''});
      });
      WidgetsBinding.instance.addPostFrameCallback((_) => _scrollToBottom());
    } finally {
      setState(() {
        _isLoading = false;
      });
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

  String _getPhysicsPrompt(String userQuestion) {
    final isKazakhUi = _uiLang == 'kk';
    final isKazakhHeur = RegExp(r'[әғқңөұүһі]').hasMatch(userQuestion) || userQuestion.contains('деген не');
    final useKz = isKazakhUi || isKazakhHeur;
    final lang = useKz ? 'казахском' : 'русском';
    final qLower = userQuestion.toLowerCase();
    final isListQuery = qLower.contains('все формул') || qLower.contains('все формулы') || qLower.contains('барлық формул') || qLower.contains('all formula') || qLower.contains('формул по') || qLower.contains('список') || qLower.contains('list');
    
    if (isListQuery) {
      return '''Ты - эксперт по физике. Дай структурированный и полный список на $lang языке.

Правила:
- Отвечай только на $lang языке
- Дай список в виде пунктов, каждый пункт с новой строки, начинай с "- "
- Включай обозначения и формулы в виде LaTeX, где уместно (обрамляй \$)
- Будь точным и структурированным
- Не используй Markdown (#, *, ---), выводи простой текст

Вопрос: $userQuestion''';
    }

    return '''Ты - эксперт по физике. Отвечай кратко (максимум 5 предложений), точно и понятно на $lang языке.

Правила:
- Отвечай только на $lang языке
- Максимум 5 предложений
- Используй формулы когда нужно
- Будь точным и кратким
- Не используй Markdown (#, *, ---), выводи простой текст

Примеры хороших ответов:
Вопрос: "Что такое сила?"
Ответ: "Сила - это векторная величина, характеризующая воздействие на тело. Измеряется в ньютонах (Н). Второй закон Ньютона: F = ma, где F - сила, m - масса, a - ускорение."

Вопрос: "Күш дегеніміз не?"
Жауап: "Күш - денеге әсер ететін векторлық шама. Ньютонмен өлшенеді (Н). Ньютонның екінші заңы: F = ma, мұнда F - күш, m - масса, a - үдеу."

Вопрос: $userQuestion''';
  }

  Widget _buildResponseWidget(String text) {
    return SelectableText.rich(
      TextSpan(
        children: _parseTextWithMath(text),
        style: const TextStyle(fontSize: 16, height: 1.4, color: Color(0xFF1E293B)),
      ),
    );
  }

  List<InlineSpan> _parseTextWithMath(String text) {
    final List<InlineSpan> spans = [];
    final RegExp mathRegex = RegExp(r'\$([^$]+)\$');
    int lastEnd = 0;

    for (final Match match in mathRegex.allMatches(text)) {
      if (match.start > lastEnd) {
        spans.add(TextSpan(text: text.substring(lastEnd, match.start)));
      }
      
      final mathContent = match.group(1)!;
      spans.add(WidgetSpan(
        child: Math.tex(
          mathContent,
          textStyle: const TextStyle(fontSize: 16, color: Color(0xFF3B82F6)),
        ),
      ));
      
      lastEnd = match.end;
    }
    
    if (lastEnd < text.length) {
      spans.add(TextSpan(text: text.substring(lastEnd)));
    }
    
    return spans;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      body: SafeArea(
        child: Column(
          children: [
            // Modern Header
            Container(
              padding: const EdgeInsets.all(20),
              decoration: const BoxDecoration(
                color: Colors.white,
                boxShadow: [
                  BoxShadow(
                    color: Color(0x0A000000),
                    blurRadius: 10,
                    offset: Offset(0, 2),
                  ),
                ],
              ),
              child: Row(
                children: [
                  // AI Avatar
                  Container(
                    width: 50,
                    height: 50,
                    decoration: BoxDecoration(
                      gradient: const LinearGradient(
                        colors: [Color(0xFF667EEA), Color(0xFF764BA2)],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      ),
                      borderRadius: BorderRadius.circular(25),
                    ),
                    child: const Icon(
                      Icons.psychology,
                      color: Colors.white,
                      size: 28,
                    ),
                  ),
                  const SizedBox(width: 16),
                  // Title & Status
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Bilim AI',
                          style: TextStyle(
                            fontSize: 24,
                            fontWeight: FontWeight.w700,
                            color: Color(0xFF1E293B),
                          ),
                        ),
                        Text(
                          _isLoading ? t('thinking') : t('ready'),
                          style: TextStyle(
                            fontSize: 14,
                            color: _isLoading ? const Color(0xFF3B82F6) : const Color(0xFF64748B),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  // New Chat button
                  Tooltip(
                    message: t('new_chat'),
                    child: InkWell(
                      onTap: _startNewChat,
                      borderRadius: BorderRadius.circular(10),
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                        decoration: BoxDecoration(
                          color: const Color(0xFFF1F5F9),
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(color: const Color(0xFFE2E8F0)),
                        ),
                        child: Row(
                          children: [
                            const Icon(Icons.add, size: 18, color: Color(0xFF1E293B)),
                            const SizedBox(width: 6),
                            Text(t('new_chat'), style: const TextStyle(color: Color(0xFF1E293B))),
                          ],
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  // Menu Button
                  PopupMenuButton<String>(
                    elevation: 8,
                    color: Colors.white,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    offset: const Offset(0, 8),
                    icon: Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: const Color(0xFFF1F5F9),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: const Icon(Icons.more_vert, color: Color(0xFF64748B)),
                    ),
                    onSelected: (value) async {
                      if (value == 'login') {
                        await _showAuthDialog();
                        await _refreshAuthState();
                      } else if (value == 'logout') {
                        await _auth.logout();
                        if (mounted) setState(() { _loggedIn = false; });
                      } else if (value == 'history') {
                        if (context.mounted) {
                          Navigator.of(context).push(
                            MaterialPageRoute(builder: (_) => const HistoryScreen()),
                          );
                        }
                      } else if (value == 'language') {
                        _showLanguageDialog();
                      } else if (value == 'about') {
                        _showAboutDialog();
                      }
                    },
                    itemBuilder: (ctx) {
                      final loggedIn = _loggedIn;
                      final items = <PopupMenuEntry<String>>[
                        PopupMenuItem(
                          value: 'language',
                          child: Row(
                            children: [
                              const Icon(Icons.language, size: 18, color: Color(0xFF64748B)),
                              const SizedBox(width: 10),
                              Text(t('language')),
                            ],
                          ),
                        ),
                        PopupMenuItem(
                          value: 'about',
                          child: Row(
                            children: [
                              const Icon(Icons.info_outline, size: 18, color: Color(0xFF64748B)),
                              const SizedBox(width: 10),
                              Text(t('about')),
                            ],
                          ),
                        ),
                      ];
                      if (loggedIn) {
                        items.add(const PopupMenuDivider(height: 8));
                        items.add(
                          PopupMenuItem(
                            value: 'history',
                            child: Row(
                              children: [
                                const Icon(Icons.history, size: 18, color: Color(0xFF64748B)),
                                const SizedBox(width: 10),
                                Text(t('history')),
                              ],
                            ),
                          ),
                        );
                        items.add(
                          PopupMenuItem(
                            value: 'logout',
                            child: Row(
                              children: [
                                const Icon(Icons.logout, size: 18, color: Color(0xFFEF4444)),
                                const SizedBox(width: 10),
                                Text(t('logout')),
                              ],
                            ),
                          ),
                        );
                      } else {
                        items.add(const PopupMenuDivider(height: 8));
                        items.add(
                          PopupMenuItem(
                            value: 'login',
                            child: Row(
                              children: [
                                const Icon(Icons.login, size: 18, color: Color(0xFF10B981)),
                                const SizedBox(width: 10),
                                Text(t('login')),
                              ],
                            ),
                          ),
                        );
                      }
                      return items;
                    },
                  ),
                ],
              ),
            ),
            // Chat Area
            Expanded(
              child: _messages.isEmpty
                  ? _buildWelcomeScreen()
                  : ListView.builder(
                      controller: _scrollController,
                      padding: const EdgeInsets.all(20),
                      itemCount: _messages.length + (_isLoading ? 1 : 0),
                      itemBuilder: (context, index) {
                        if (_isLoading && index == _messages.length) {
                          return _buildTypingIndicator();
                        }
                        return _buildMessageBubble(_messages[index]);
                      },
                    ),
            ),
            // Input Area
            Container(
              padding: const EdgeInsets.all(20),
              decoration: const BoxDecoration(
                color: Colors.white,
                boxShadow: [
                  BoxShadow(
                    color: Color(0x0A000000),
                    blurRadius: 10,
                    offset: Offset(0, -2),
                  ),
                ],
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Container(
                      decoration: BoxDecoration(
                        color: const Color(0xFFF8FAFC),
                        borderRadius: BorderRadius.circular(25),
                        border: Border.all(color: const Color(0xFFE2E8F0)),
                      ),
                      child: TextField(
                        controller: _textController,
                        maxLines: null,
                        textInputAction: TextInputAction.send,
                        onSubmitted: (_) {
                          if (!_isLoading && _textController.text.trim().isNotEmpty) {
                            _sendToAI();
                          }
                        },
                        decoration: InputDecoration(
                          hintText: t('placeholder'),
                          hintStyle: const TextStyle(color: Color(0xFF94A3B8)),
                          border: InputBorder.none,
                          contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 15),
                        ),
                        style: const TextStyle(fontSize: 16, color: Color(0xFF1E293B)),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Container(
                    width: 50,
                    height: 50,
                    decoration: BoxDecoration(
                      gradient: const LinearGradient(
                        colors: [Color(0xFF3B82F6), Color(0xFF1D4ED8)],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      ),
                      borderRadius: BorderRadius.circular(25),
                      boxShadow: [
                        BoxShadow(
                          color: const Color(0xFF3B82F6).withOpacity(0.3),
                          blurRadius: 8,
                          offset: const Offset(0, 4),
                        ),
                      ],
                    ),
                    child: Material(
                      color: Colors.transparent,
                      child: InkWell(
                        borderRadius: BorderRadius.circular(25),
                        onTap: _isLoading ? null : _sendToAI,
                        child: _isLoading
                            ? const SizedBox(
                                width: 20,
                                height: 20,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                                ),
                              )
                            : const Icon(Icons.send, color: Colors.white, size: 20),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 6),
            Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: Text(
                'BilimAI | by srk & aruka. послед. обновление 31.10.2025',
                style: const TextStyle(
                  fontSize: 11,
                  color: Color(0xFF94A3B8),
                  height: 1.1,
                ),
                textAlign: TextAlign.center,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildWelcomeScreen() {
    return FadeTransition(
      opacity: _fadeAnimation,
      child: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 120,
              height: 120,
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  colors: [Color(0xFF667EEA), Color(0xFF764BA2)],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                borderRadius: BorderRadius.circular(60),
                boxShadow: [
                  BoxShadow(
                    color: const Color(0xFF667EEA).withOpacity(0.3),
                    blurRadius: 20,
                    offset: const Offset(0, 10),
                  ),
                ],
              ),
              child: const Icon(
                Icons.psychology,
                color: Colors.white,
                size: 60,
              ),
            ),
            const SizedBox(height: 32),
            Text(
              t('welcome_title'),
              style: const TextStyle(
                fontSize: 28,
                fontWeight: FontWeight.w700,
                color: Color(0xFF1E293B),
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 12),
            Text(
              t('welcome_subtitle'),
              style: TextStyle(
                fontSize: 16,
                color: const Color(0xFF64748B),
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 40),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
              decoration: BoxDecoration(
                color: const Color(0xFFF1F5F9),
                borderRadius: BorderRadius.circular(20),
              ),
              child: Text(
                t('welcome_prompt'),
                style: TextStyle(
                  fontSize: 14,
                  color: const Color(0xFF64748B),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTypingIndicator() {
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      child: Row(
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [Color(0xFF667EEA), Color(0xFF764BA2)],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.circular(20),
            ),
            child: const Icon(Icons.psychology, color: Colors.white, size: 20),
          ),
          const SizedBox(width: 12),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: const Color(0xFFE2E8F0)),
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
                Text(
                  t('thinking'),
                  style: const TextStyle(color: Color(0xFF64748B)),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMessageBubble(Map<String, String> message) {
    final isUser = message['role'] == 'user';
    final content = message['content'] ?? '';
    
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      child: Row(
        mainAxisAlignment: isUser ? MainAxisAlignment.end : MainAxisAlignment.start,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (!isUser) ...[
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  colors: [Color(0xFF667EEA), Color(0xFF764BA2)],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                borderRadius: BorderRadius.circular(20),
              ),
              child: const Icon(Icons.psychology, color: Colors.white, size: 20),
            ),
            const SizedBox(width: 12),
          ],
          Flexible(
            child: Container(
              constraints: const BoxConstraints(maxWidth: 280),
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              decoration: BoxDecoration(
                color: isUser ? const Color(0xFF3B82F6) : Colors.white,
                borderRadius: BorderRadius.circular(20),
                border: isUser ? null : Border.all(color: const Color(0xFFE2E8F0)),
                boxShadow: isUser ? [
                  BoxShadow(
                    color: const Color(0xFF3B82F6).withOpacity(0.2),
                    blurRadius: 8,
                    offset: const Offset(0, 4),
                  ),
                ] : null,
              ),
              child: isUser
                  ? Text(
                      content,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 16,
                        height: 1.4,
                      ),
                    )
                  : _buildResponseWidget(content),
            ),
          ),
          if (isUser) ...[
            const SizedBox(width: 12),
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: const Color(0xFF3B82F6),
                borderRadius: BorderRadius.circular(20),
              ),
              child: const Icon(Icons.person, color: Colors.white, size: 20),
            ),
          ],
        ],
      ),
    );
  }
}