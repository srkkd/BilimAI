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

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

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
          title: Text(isLogin ? t('login') : t('register')),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (isLoading) const LinearProgressIndicator(),
                TextField(
                  controller: emailController,
                  decoration: InputDecoration(labelText: t('email')),
                  keyboardType: TextInputType.emailAddress,
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: passwordController,
                  decoration: InputDecoration(labelText: t('password')),
                  obscureText: true,
                ),
                if (!isLogin) ...[
                  const SizedBox(height: 16),
                  TextField(
                    controller: confirmPasswordController,
                    decoration: InputDecoration(labelText: t('confirm_password')),
                    obscureText: true,
                  ),
                ],
                const SizedBox(height: 16),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    TextButton(
                      onPressed: () => setDialogState(() => isLogin = !isLogin),
                      child: Text(isLogin ? t('register') : t('login')),
                    ),
                    Row(
                      children: [
                        TextButton(
                          onPressed: () => Navigator.pop(context),
                          child: Text(t('cancel')),
                        ),
                        const SizedBox(width: 8),
                        ElevatedButton(
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
                          child: Text(t('save')),
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

  Future<String?> _discoverSupportedModel() async {
    try {
      final effectiveKey = _effectiveApiKey();
      if (effectiveKey.isEmpty) return null;
      
      final url = Uri.parse('https://generativelanguage.googleapis.com/v1/models?key=$effectiveKey');
      final response = await http.get(url);
      
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final models = data['models'] as List;
        
        // Приоритет: flash-002, pro-002, затем latest
        for (final model in models) {
          final name = model['name'] as String;
          if (name.contains('gemini-1.5-flash-002')) return name;
        }
        for (final model in models) {
          final name = model['name'] as String;
          if (name.contains('gemini-1.5-pro-002')) return name;
        }
        for (final model in models) {
          final name = model['name'] as String;
          if (name.contains('gemini-1.5-flash-latest')) return name;
        }
        for (final model in models) {
          final name = model['name'] as String;
          if (name.contains('gemini-1.5-pro-latest')) return name;
        }
      }
    } catch (_) {
      // ignore
    }
    return null;
  }

  String _effectiveApiKey() {
    if (apiKey.isNotEmpty && apiKey != 'YOUR_GEMINI_API_KEY_HERE') return apiKey;
    return '';
  }

  Future<String?> _getUsableModel() async {
    if (_cachedModelName != null) return _cachedModelName;
    _cachedModelName = await _discoverSupportedModel();
    return _cachedModelName;
  }

  Future<void> _sendToAI() async {
    if (_textController.text.isEmpty) return;

    setState(() {
      _isLoading = true;
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
                'error': 'API ключ не найден. Передайте ключ через --dart-define=BILIM_GEMINI_API_KEY=... или задайте его в lib/api_key.dart.'
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

      if (response.statusCode == 404) {
        final discovered = await _discoverSupportedModel();
        if (discovered != null && discovered != modelToUse) {
          _cachedModelName = discovered;
          response = await _callModel(discovered);
        } else {
          response = await _callModel('gemini-1.5-pro-002');
          if (response.statusCode == 404) {
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
        });
      } else if (response.statusCode == 401) {
        setState(() {
          _aiResponse = 'Ошибка 401: проверьте API-ключ Gemini.';
        });
      } else if (response.statusCode == 403) {
        setState(() {
          _aiResponse = 'Ошибка 403: Generative Language API отключён для вашего проекта.';
        });
      } else if (response.statusCode == 404) {
        setState(() {
          _aiResponse = 'Ошибка 404: модель недоступна для вашей учётной записи/проекта.';
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
          _aiResponse = 'Ошибка ${response.statusCode}: ${response.body}';
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
    final isKazakh = RegExp(r'[әғқңөұүһі]').hasMatch(userQuestion);
    final lang = isKazakh ? 'казахском' : 'русском';
    
    return '''Ты - эксперт по физике. Отвечай кратко (максимум 5 предложений), точно и понятно на $lang языке.

Правила:
- Отвечай только на $lang языке
- Максимум 5 предложений
- Используй формулы когда нужно
- Будь точным и кратким

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

  List<TextSpan> _parseTextWithMath(String text) {
    final List<TextSpan> spans = [];
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
                          _isLoading ? 'Думает...' : 'Готов помочь',
                          style: TextStyle(
                            fontSize: 14,
                            color: _isLoading ? const Color(0xFF3B82F6) : const Color(0xFF64748B),
                          ),
                        ),
                      ],
                    ),
                  ),
                  // Menu Button
                  PopupMenuButton<String>(
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
                        _showAuthDialog();
                      } else if (value == 'logout') {
                        await _auth.logout();
                        if (mounted) setState(() {});
                      } else if (value == 'history') {
                        if (context.mounted) {
                          Navigator.of(context).push(
                            MaterialPageRoute(builder: (_) => const HistoryScreen()),
                          );
                        }
                      } else if (value == 'language') {
                        _showLanguageDialog();
                      }
                    },
                    itemBuilder: (ctx) => [
                      PopupMenuItem(value: 'language', child: Text(t('language'))),
                      PopupMenuItem(value: 'history', child: Text(t('history'))),
                      PopupMenuItem(value: 'login', child: Text(t('login'))),
                    ],
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
                          hintText: 'Задайте вопрос по физике...',
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
            const Text(
              'Добро пожаловать в Bilim AI',
              style: TextStyle(
                fontSize: 28,
                fontWeight: FontWeight.w700,
                color: Color(0xFF1E293B),
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 12),
            Text(
              'Ваш персональный помощник по физике',
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
                'Задайте любой вопрос по физике',
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
                  'Думает...',
                  style: TextStyle(color: const Color(0xFF64748B)),
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