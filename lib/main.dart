import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flex_color_picker/flex_color_picker.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

// Base URL for the existing backend (Nest + Prisma). Override via:
// flutter run -d chrome --dart-define=API_BASE_URL=https://api.example.com
const String apiBaseUrl = String.fromEnvironment(
  'API_BASE_URL',
  // Shared Render backend for all apps (MVP + Admin)
  defaultValue: 'https://inzeli-api-6heq.onrender.com/api',
);

// Rollup list of games available across the platform
const List<String> kGameOptions = [
  'كوت',
  'بلوت',
  'تريكس',
  'هند',
  'سبيتة',
  'UNO',
  'اونو',
  'شطرنج',
  'دامه',
  'كيرم',
  'دومنه',
  'طاوله',
  'بلياردو',
  'جاكارو',
  'بيبيفوت',
  'قدم',
  'سله',
  'طائره',
  'بولنج',
  'بادل',
  'تنس طاولة',
  'تنس ارضي',
];

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final auth = AuthState();
  await auth.load();
  runApp(ChangeNotifierProvider(create: (_) => auth, child: const AdminApp()));
}

class AdminApp extends StatelessWidget {
  const AdminApp({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = ThemeData(
      colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF1A6A88)),
      useMaterial3: true,
    );
    return MaterialApp(
      title: 'Admin Enzily',
      theme: theme,
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      supportedLocales: const [Locale('ar'), Locale('en')],
      home: const RootRouter(),
    );
  }
}

class RootRouter extends StatelessWidget {
  const RootRouter({super.key});

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthState>();
    if (auth.loading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    if (!auth.isAuthed) {
      return const LoginScreen();
    }
    return const AdminShell();
  }
}

class AuthState extends ChangeNotifier {
  bool loading = true;
  String? token;
  String? email;

  static const _kAuthKey = 'admin_auth_v1';

  bool get isAuthed => token != null && token!.isNotEmpty;

  Future<void> load() async {
    final sp = await SharedPreferences.getInstance();
    final raw = sp.getString(_kAuthKey);
    if (raw != null && raw.isNotEmpty) {
      try {
        final m = jsonDecode(raw) as Map<String, dynamic>;
        token = (m['token'] ?? '').toString();
        email = (m['email'] ?? '').toString();
      } catch (_) {}
    }
    loading = false;
    notifyListeners();
  }

  Future<void> _save() async {
    final sp = await SharedPreferences.getInstance();
    await sp.setString(_kAuthKey, jsonEncode({'token': token, 'email': email}));
  }

  Future<void> logout() async {
    token = null;
    email = null;
    await _save();
    notifyListeners();
  }

  Future<String?> login({
    required String email,
    required String password,
  }) async {
    final api = ApiClient(token: null);
    final res = await api.post(
      '/auth/login',
      body: {'email': email.trim(), 'password': password},
    );
    if (res.error != null) return res.error;

    final data = res.data;
    final t = data['token']?.toString() ?? '';
    if (t.isEmpty) return 'Token missing';

    token = t;
    this.email = email.trim();
    await _save();
    notifyListeners();
    return null;
  }
}

class ApiResponse {
  final dynamic data; // can be Map or List based on backend response
  final String? error;
  ApiResponse({required this.data, this.error});
}

class ApiClient {
  final String? token;
  const ApiClient({required this.token});

  Map<String, String> _headers() {
    return {
      'Content-Type': 'application/json',
      if (token != null && token!.isNotEmpty) 'Authorization': 'Bearer $token',
    };
  }

  Uri _uri(String path) => Uri.parse('$apiBaseUrl$path');

  Future<ApiResponse> get(String path) async {
    try {
      final resp = await http.get(_uri(path), headers: _headers());
      final m = jsonDecode(resp.body) as Map<String, dynamic>;
      if (resp.statusCode >= 200 &&
          resp.statusCode < 300 &&
          (m['ok'] != false)) {
        return ApiResponse(data: m['data'] ?? m);
      }
      return ApiResponse(
        data: const {},
        error: m['message']?.toString() ?? 'Request failed',
      );
    } catch (e) {
      return ApiResponse(data: const {}, error: e.toString());
    }
  }

  Future<ApiResponse> post(String path, {Map<String, dynamic>? body}) async {
    try {
      final resp = await http.post(
        _uri(path),
        headers: _headers(),
        body: jsonEncode(body ?? const {}),
      );
      final m = jsonDecode(resp.body) as Map<String, dynamic>;
      if (resp.statusCode >= 200 &&
          resp.statusCode < 300 &&
          (m['ok'] != false)) {
        return ApiResponse(data: m['data'] ?? m);
      }
      return ApiResponse(
        data: const {},
        error: m['message']?.toString() ?? 'Request failed',
      );
    } catch (e) {
      return ApiResponse(data: const {}, error: e.toString());
    }
  }

  Future<ApiResponse> patch(String path, {Map<String, dynamic>? body}) async {
    try {
      final resp = await http.patch(
        _uri(path),
        headers: _headers(),
        body: jsonEncode(body ?? const {}),
      );
      final m = jsonDecode(resp.body) as Map<String, dynamic>;
      if (resp.statusCode >= 200 &&
          resp.statusCode < 300 &&
          (m['ok'] != false)) {
        return ApiResponse(data: m['data'] ?? m);
      }
      return ApiResponse(
        data: const {},
        error: m['message']?.toString() ?? 'Request failed',
      );
    } catch (e) {
      return ApiResponse(data: const {}, error: e.toString());
    }
  }

  Future<ApiResponse> delete(String path) async {
    try {
      final resp = await http.delete(_uri(path), headers: _headers());
      final m = jsonDecode(resp.body) as Map<String, dynamic>;
      if (resp.statusCode >= 200 &&
          resp.statusCode < 300 &&
          (m['ok'] != false)) {
        return ApiResponse(data: m['data'] ?? m);
      }
      return ApiResponse(
        data: const {},
        error: m['message']?.toString() ?? 'Request failed',
      );
    } catch (e) {
      return ApiResponse(data: const {}, error: e.toString());
    }
  }
}

Color _parseColor(String input, {Color fallback = const Color(0xFF1A6A88)}) {
  final text = input.trim().replaceAll('#', '');
  if (text.length == 6 || text.length == 8) {
    try {
      final withAlpha = text.length == 8 ? text : 'FF$text';
      return Color(int.parse(withAlpha, radix: 16));
    } catch (_) {}
  }
  return fallback;
}

String _colorCode(Color c) {
  final r = (c.r * 255.0).round().clamp(0, 255);
  final g = (c.g * 255.0).round().clamp(0, 255);
  final b = (c.b * 255.0).round().clamp(0, 255);
  final rgb = (r << 16) | (g << 8) | b;
  return '#${rgb.toRadixString(16).padLeft(6, '0').toUpperCase()}';
}

Future<void> _pickColorForController(
  BuildContext context,
  TextEditingController ctrl,
) async {
  final current = _parseColor(ctrl.text);
  final color = await showColorPickerDialog(
    context,
    current,
    title: const Text('اختر لوناً'),
    width: 40,
    height: 40,
    spacing: 12,
    wheelDiameter: 180,
    showColorName: true,
    pickersEnabled: const <ColorPickerType, bool>{
      ColorPickerType.wheel: true,
      ColorPickerType.accent: false,
      ColorPickerType.primary: true,
    },
  );
  ctrl.text = _colorCode(color);
}

Widget _colorField({
  required String label,
  required TextEditingController controller,
  required BuildContext context,
}) {
  final color = _parseColor(controller.text);
  return LayoutBuilder(
    builder: (context, constraints) {
      final field = TextField(
        controller: controller,
        decoration: InputDecoration(labelText: label, hintText: '#1A6A88'),
      );
      final swatch = InkWell(
        onTap: () => _pickColorForController(context, controller),
        child: Container(
          width: 36,
          height: 36,
          decoration: BoxDecoration(
            color: color,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: Colors.grey.shade400),
          ),
        ),
      );
      if (constraints.maxWidth < 360) {
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            field,
            const SizedBox(height: 8),
            Align(alignment: AlignmentDirectional.centerEnd, child: swatch),
          ],
        );
      }
      return Row(
        children: [
          Expanded(child: field),
          const SizedBox(width: 8),
          swatch,
        ],
      );
    },
  );
}

Widget _responsiveFormLine({
  required List<Widget> fields,
  List<Widget> actions = const [],
  List<int>? flexes,
  double breakpoint = 760,
  double gap = 8,
}) {
  return LayoutBuilder(
    builder: (context, constraints) {
      final compact = constraints.maxWidth < breakpoint;
      if (compact) {
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            for (var i = 0; i < fields.length; i++) ...[
              fields[i],
              if (i != fields.length - 1 || actions.isNotEmpty)
                SizedBox(height: gap),
            ],
            for (var i = 0; i < actions.length; i++) ...[
              SizedBox(width: double.infinity, child: actions[i]),
              if (i != actions.length - 1) SizedBox(height: gap),
            ],
          ],
        );
      }

      final resolvedFlexes = flexes ?? List<int>.filled(fields.length, 1);
      final totalFlex = resolvedFlexes.fold<int>(0, (sum, flex) => sum + flex);
      final itemCount = fields.length + actions.length;
      final totalGap = itemCount > 1 ? gap * (itemCount - 1) : 0.0;
      final availableWidth = (constraints.maxWidth - totalGap)
          .clamp(0.0, double.infinity)
          .toDouble();
      final actionWidth = actions.length * 132.0;
      final fieldSpace = (availableWidth - actionWidth)
          .clamp(0.0, availableWidth)
          .toDouble();

      return Wrap(
        spacing: gap,
        runSpacing: gap,
        crossAxisAlignment: WrapCrossAlignment.end,
        children: [
          for (var i = 0; i < fields.length; i++)
            SizedBox(
              width:
                  (fieldSpace *
                          (i < resolvedFlexes.length ? resolvedFlexes[i] : 1) /
                          (totalFlex == 0 ? 1 : totalFlex))
                      .clamp(180.0, constraints.maxWidth)
                      .toDouble(),
              child: fields[i],
            ),
          for (final action in actions)
            ConstrainedBox(
              constraints: const BoxConstraints(minWidth: 120, maxWidth: 180),
              child: action,
            ),
        ],
      );
    },
  );
}

TextStyle _mutedTextStyle(BuildContext context) {
  final scheme = Theme.of(context).colorScheme;
  return TextStyle(
    color: Color.lerp(scheme.surface, scheme.onSurface, 0.72),
    fontSize: 14,
    height: 1.35,
    fontWeight: FontWeight.w600,
  );
}

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _formKey = GlobalKey<FormState>();
  final _emailCtrl = TextEditingController();
  final _passCtrl = TextEditingController();
  bool _loading = false;
  String? _error;

  @override
  void dispose() {
    _emailCtrl.dispose();
    _passCtrl.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() {
      _loading = true;
      _error = null;
    });
    final auth = context.read<AuthState>();
    final err = await auth.login(
      email: _emailCtrl.text,
      password: _passCtrl.text,
    );
    if (err != null) {
      setState(() => _error = err);
    }
    setState(() => _loading = false);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 420),
          child: Card(
            margin: const EdgeInsets.all(24),
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Form(
                key: _formKey,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const Text(
                      'Admin Enzily',
                      style: TextStyle(
                        fontWeight: FontWeight.w900,
                        fontSize: 22,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Backend: $apiBaseUrl',
                      style: TextStyle(color: Colors.grey[700]),
                    ),
                    const SizedBox(height: 16),
                    TextFormField(
                      controller: _emailCtrl,
                      decoration: const InputDecoration(labelText: 'Email'),
                      validator: (v) =>
                          v == null || v.isEmpty ? 'Required' : null,
                    ),
                    const SizedBox(height: 12),
                    TextFormField(
                      controller: _passCtrl,
                      obscureText: true,
                      decoration: const InputDecoration(labelText: 'Password'),
                      validator: (v) =>
                          v == null || v.isEmpty ? 'Required' : null,
                    ),
                    if (_error != null) ...[
                      const SizedBox(height: 8),
                      Text(_error!, style: const TextStyle(color: Colors.red)),
                    ],
                    const SizedBox(height: 16),
                    FilledButton.icon(
                      onPressed: _loading ? null : _submit,
                      icon: _loading
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.login),
                      label: const Text('Log in (admin)'),
                    ),
                    const SizedBox(height: 12),
                    const Text(
                      'هذا الحساب مخصص للمشرفين فقط. تأكد أن المستخدم في الباكند لديه صلاحيات الإدارة.',
                      style: TextStyle(fontSize: 12),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class AdminShell extends StatefulWidget {
  const AdminShell({super.key});

  @override
  State<AdminShell> createState() => _AdminShellState();
}

class _AdminShellState extends State<AdminShell> {
  int _tab = 0;

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthState>();
    final api = ApiClient(token: auth.token);
    final width = MediaQuery.sizeOf(context).width;
    final compact = width < 560;

    final tabs = [
      _TabData('Sponsors', Icons.work_outline, SponsorTab(api: api)),
      _TabData('Dewanyah', Icons.groups_3_outlined, DewanyahTab(api: api)),
      _TabData('Users', Icons.verified_user_outlined, UsersTab(api: api)),
      _TabData(
        'Notifications',
        Icons.notifications_active_outlined,
        NotificationsTab(api: api),
      ),
    ];

    final content = tabs[_tab].child;

    return Scaffold(
      appBar: AppBar(
        title: Text(
          compact ? tabs[_tab].title : 'Admin Enzily — ${tabs[_tab].title}',
          overflow: TextOverflow.ellipsis,
        ),
        actions: [
          if (auth.email != null && width >= 430)
            Padding(
              padding: const EdgeInsetsDirectional.only(end: 8),
              child: Center(
                child: ConstrainedBox(
                  constraints: BoxConstraints(maxWidth: compact ? 150 : 260),
                  child: Text(
                    auth.email!,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                ),
              ),
            ),
          IconButton(
            tooltip: 'Logout',
            onPressed: () => auth.logout(),
            icon: const Icon(Icons.logout),
          ),
        ],
      ),
      body: Row(
        children: [
          if (MediaQuery.of(context).size.width >= 900)
            NavigationRail(
              selectedIndex: _tab,
              onDestinationSelected: (i) => setState(() => _tab = i),
              destinations: tabs
                  .map(
                    (t) => NavigationRailDestination(
                      icon: Icon(t.icon),
                      label: Text(t.title),
                    ),
                  )
                  .toList(),
            ),
          Expanded(
            child: Padding(
              padding: EdgeInsets.all(compact ? 8 : 12),
              child: content,
            ),
          ),
        ],
      ),
      bottomNavigationBar: MediaQuery.of(context).size.width < 900
          ? NavigationBar(
              selectedIndex: _tab,
              onDestinationSelected: (i) => setState(() => _tab = i),
              destinations: tabs
                  .map(
                    (t) => NavigationDestination(
                      icon: Icon(t.icon),
                      label: t.title,
                    ),
                  )
                  .toList(),
            )
          : null,
    );
  }
}

class _TabData {
  final String title;
  final IconData icon;
  final Widget child;
  _TabData(this.title, this.icon, this.child);
}

class SponsorTab extends StatefulWidget {
  final ApiClient api;
  const SponsorTab({super.key, required this.api});

  @override
  State<SponsorTab> createState() => _SponsorTabState();
}

class _SponsorTabState extends State<SponsorTab> {
  Future<ApiResponse>? _future;
  final _codeCtrl = TextEditingController();
  final _nameCtrl = TextEditingController();
  final _gameIdCtrl = TextEditingController();
  final _prizeCtrl = TextEditingController();
  final _themePrimCtrl = TextEditingController();
  final _themeAccCtrl = TextEditingController();
  final _existingSponsorCtrl = TextEditingController();
  final _existingGameCtrl = TextEditingController();
  final _existingPrizeCtrl = TextEditingController();
  String? _message;

  @override
  void initState() {
    super.initState();
    _future = widget.api.get('/sponsors');
  }

  @override
  void dispose() {
    _codeCtrl.dispose();
    _nameCtrl.dispose();
    _gameIdCtrl.dispose();
    _prizeCtrl.dispose();
    _themePrimCtrl.dispose();
    _themeAccCtrl.dispose();
    _existingSponsorCtrl.dispose();
    _existingGameCtrl.dispose();
    _existingPrizeCtrl.dispose();
    super.dispose();
  }

  Future<void> _refresh() async {
    setState(() {
      _future = widget.api.get('/admin/sponsors');
    });
  }

  Future<void> _createSponsor() async {
    final code = _codeCtrl.text.trim();
    final name = _nameCtrl.text.trim();
    final themePrimary = _themePrimCtrl.text.trim();
    final themeAccent = _themeAccCtrl.text.trim();
    if (code.isEmpty || name.isEmpty) {
      setState(() => _message = 'أدخل الكود والاسم');
      return;
    }
    final res = await widget.api.post(
      '/admin/sponsors',
      body: {
        'code': code,
        'name': name,
        if (themePrimary.isNotEmpty) 'themePrimary': themePrimary,
        if (themeAccent.isNotEmpty) 'themeAccent': themeAccent,
      },
    );
    setState(
      () => _message =
          res.error ??
          'تم طلب إنشاء الراعي (تأكد أن الباكند يدعم endpoint /admin/sponsors)',
    );
    _refresh();
  }

  Future<void> _addSponsorGame() async {
    final code = _codeCtrl.text.trim();
    final gameId = _gameIdCtrl.text.trim();
    final prize = int.tryParse(_prizeCtrl.text.trim());
    if (code.isEmpty || gameId.isEmpty) {
      setState(() => _message = 'أدخل كود الراعي واللعبة');
      return;
    }
    final res = await widget.api.post(
      '/admin/sponsors/$code/games',
      body: {'gameId': gameId, if (prize != null) 'prizeAmount': prize},
    );
    setState(
      () => _message = res.error ?? 'تم طلب إضافة اللعبة (تأكد من دعم الباكند)',
    );
    _refresh();
  }

  Future<void> _addGameToExisting() async {
    final code = _existingSponsorCtrl.text.trim();
    final gameId = _existingGameCtrl.text.trim();
    final prize = int.tryParse(_existingPrizeCtrl.text.trim());
    if (code.isEmpty || gameId.isEmpty) {
      setState(() => _message = 'أدخل كود الراعي واللعبة');
      return;
    }
    final res = await widget.api.post(
      '/admin/sponsors/$code/games',
      body: {'gameId': gameId, if (prize != null) 'prizeAmount': prize},
    );
    setState(() => _message = res.error ?? 'تم طلب إضافة اللعبة للراعي');
    _refresh();
  }

  Future<void> _editSponsor(Map<String, dynamic> s) async {
    final code = (s['code'] ?? '').toString();
    final nameCtrl = TextEditingController(text: s['name']?.toString() ?? '');
    final imgCtrl = TextEditingController(
      text: s['imageUrl']?.toString() ?? '',
    );
    final primCtrl = TextEditingController(
      text: s['themePrimary']?.toString() ?? '',
    );
    final accCtrl = TextEditingController(
      text: s['themeAccent']?.toString() ?? '',
    );
    await showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: Text('تعديل الراعي $code'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: nameCtrl,
                decoration: const InputDecoration(labelText: 'اسم الراعي'),
              ),
              TextField(
                controller: imgCtrl,
                decoration: const InputDecoration(labelText: 'رابط الصورة'),
              ),
              const SizedBox(height: 8),
              _colorField(
                label: 'لون أساسي',
                controller: primCtrl,
                context: context,
              ),
              const SizedBox(height: 8),
              _colorField(
                label: 'لون ثانوي',
                controller: accCtrl,
                context: context,
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('إلغاء'),
          ),
          ElevatedButton(
            onPressed: () async {
              await widget.api.patch(
                '/admin/sponsors/$code',
                body: {
                  'name': nameCtrl.text.trim(),
                  'imageUrl': imgCtrl.text.trim(),
                  'themePrimary': primCtrl.text.trim(),
                  'themeAccent': accCtrl.text.trim(),
                },
              );
              if (mounted) Navigator.pop(context);
              _refresh();
            },
            child: const Text('حفظ'),
          ),
        ],
      ),
    );
  }

  Future<void> _deleteSponsor(String code) async {
    await widget.api.delete('/admin/sponsors/$code');
    _refresh();
  }

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.only(bottom: 24),
      children: [
        Row(
          children: [
            const Text(
              'الرعاة',
              style: TextStyle(fontWeight: FontWeight.w900, fontSize: 18),
            ),
            const Spacer(),
            IconButton(onPressed: _refresh, icon: const Icon(Icons.refresh)),
          ],
        ),
        const SizedBox(height: 8),
        FutureBuilder<ApiResponse>(
          future: _future,
          builder: (context, snap) {
            if (snap.connectionState == ConnectionState.waiting) {
              return const SizedBox(
                height: 150,
                child: Center(child: CircularProgressIndicator()),
              );
            }
            final res = snap.data;
            if (res == null || res.error != null) {
              return SizedBox(
                height: 120,
                child: Center(child: Text(res?.error ?? 'فشل تحميل الرعاة')),
              );
            }
            final data = res.data;
            final list = data is List ? data : const [];
            if (list.isEmpty) {
              return const SizedBox(
                height: 120,
                child: Center(child: Text('لا يوجد رعاة بعد')),
              );
            }
            return Column(
              children: [
                for (var i = 0; i < list.length; i++) ...[
                  Builder(
                    builder: (context) {
                      final s = list[i] as Map<String, dynamic>;
                      final code = (s['code'] ?? '').toString();
                      final name = (s['name'] ?? code).toString();
                      final games =
                          (s['SponsorGame'] as List?) ??
                          (s['games'] as List?) ??
                          const [];
                      final imageUrl = (s['imageUrl'] ?? '').toString();
                      final themePrim = (s['themePrimary'] ?? '').toString();
                      final themeAcc = (s['themeAccent'] ?? '').toString();
                      return Card(
                        child: Padding(
                          padding: const EdgeInsets.all(12),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                '$name — $code',
                                style: const TextStyle(
                                  fontWeight: FontWeight.w900,
                                ),
                                overflow: TextOverflow.ellipsis,
                                maxLines: 2,
                              ),
                              const SizedBox(height: 6),
                              if (imageUrl.isNotEmpty)
                                Text(
                                  'صورة: $imageUrl',
                                  style: const TextStyle(fontSize: 12),
                                ),
                              if (themePrim.isNotEmpty || themeAcc.isNotEmpty)
                                Text(
                                  'الألوان: $themePrim / $themeAcc',
                                  style: const TextStyle(fontSize: 12),
                                ),
                              if (games.isEmpty)
                                const Text('لا توجد ألعاب مربوطة')
                              else
                                Wrap(
                                  spacing: 6,
                                  runSpacing: 6,
                                  children: games.map<Widget>((g) {
                                    final mg = g as Map<String, dynamic>;
                                    final gid = (mg['gameId'] ?? '').toString();
                                    final prize = (mg['prizeAmount'] as num?)
                                        ?.toInt();
                                    return Chip(
                                      label: Text(
                                        prize != null
                                            ? '$gid • جائزة $prize'
                                            : gid,
                                      ),
                                    );
                                  }).toList(),
                                ),
                              const SizedBox(height: 8),
                              Wrap(
                                spacing: 8,
                                runSpacing: 4,
                                children: [
                                  TextButton(
                                    onPressed: () => _editSponsor(s),
                                    child: const Text('تعديل'),
                                  ),
                                  TextButton(
                                    onPressed: () => _deleteSponsor(code),
                                    child: const Text(
                                      'حذف',
                                      style: TextStyle(color: Colors.red),
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
                  if (i != list.length - 1) const SizedBox(height: 8),
                ],
              ],
            );
          },
        ),
        const SizedBox(height: 8),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Text(
                  'إنشاء راعي / لعبة',
                  style: TextStyle(fontWeight: FontWeight.w900),
                ),
                const SizedBox(height: 8),
                _responsiveFormLine(
                  fields: [
                    TextField(
                      controller: _codeCtrl,
                      decoration: const InputDecoration(
                        labelText: 'كود الراعي',
                      ),
                    ),
                    TextField(
                      controller: _nameCtrl,
                      decoration: const InputDecoration(
                        labelText: 'اسم الراعي',
                      ),
                    ),
                  ],
                  actions: [
                    ElevatedButton(
                      onPressed: _createSponsor,
                      child: const Text('إنشاء راعي'),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                _colorField(
                  label: 'لون أساسي (Hex)',
                  controller: _themePrimCtrl,
                  context: context,
                ),
                const SizedBox(height: 8),
                _colorField(
                  label: 'لون ثانوي (Hex)',
                  controller: _themeAccCtrl,
                  context: context,
                ),
                const SizedBox(height: 8),
                _responsiveFormLine(
                  fields: [
                    DropdownButtonFormField<String>(
                      initialValue: _gameIdCtrl.text.isEmpty
                          ? null
                          : _gameIdCtrl.text,
                      decoration: const InputDecoration(labelText: 'Game ID'),
                      items: kGameOptions
                          .map(
                            (g) => DropdownMenuItem(value: g, child: Text(g)),
                          )
                          .toList(),
                      onChanged: (v) =>
                          setState(() => _gameIdCtrl.text = v ?? ''),
                    ),
                    TextField(
                      controller: _prizeCtrl,
                      decoration: const InputDecoration(
                        labelText: 'جائزة (اختياري)',
                      ),
                      keyboardType: TextInputType.number,
                    ),
                  ],
                  actions: [
                    ElevatedButton(
                      onPressed: _addSponsorGame,
                      child: const Text('ربط لعبة'),
                    ),
                  ],
                ),
                if (_message != null) ...[
                  const SizedBox(height: 8),
                  Text(_message!, style: const TextStyle(color: Colors.blue)),
                ],
                const SizedBox(height: 6),
                const Text(
                  'ملاحظة: نحتاج endpoints إدارية في الباكند (/admin/sponsors، /admin/sponsors/:code/games) لتعمل هذه الأزرار.',
                  style: TextStyle(fontSize: 12, color: Colors.grey),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 10),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Text(
                  'إضافة لعبة لراعي موجود',
                  style: TextStyle(fontWeight: FontWeight.w900),
                ),
                const SizedBox(height: 8),
                _responsiveFormLine(
                  fields: [
                    TextField(
                      controller: _existingSponsorCtrl,
                      decoration: const InputDecoration(
                        labelText: 'كود الراعي',
                      ),
                    ),
                    DropdownButtonFormField<String>(
                      initialValue: _existingGameCtrl.text.isEmpty
                          ? null
                          : _existingGameCtrl.text,
                      decoration: const InputDecoration(labelText: 'Game ID'),
                      items: kGameOptions
                          .map(
                            (g) => DropdownMenuItem(value: g, child: Text(g)),
                          )
                          .toList(),
                      onChanged: (v) =>
                          setState(() => _existingGameCtrl.text = v ?? ''),
                    ),
                    TextField(
                      controller: _existingPrizeCtrl,
                      decoration: const InputDecoration(labelText: 'جائزة'),
                      keyboardType: TextInputType.number,
                    ),
                  ],
                  actions: [
                    ElevatedButton(
                      onPressed: _addGameToExisting,
                      child: const Text('إضافة'),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                const Text(
                  'إدارة ألعاب الراعي الحالي (تحتاج دعم endpoint في الباكند).',
                  style: TextStyle(fontSize: 12, color: Colors.grey),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class DewanyahTab extends StatefulWidget {
  final ApiClient api;
  const DewanyahTab({super.key, required this.api});

  @override
  State<DewanyahTab> createState() => _DewanyahTabState();
}

class _DewanyahTabState extends State<DewanyahTab> {
  final _nameCtrl = TextEditingController();
  final _ownerCtrl = TextEditingController();
  final _ownerEmailCtrl = TextEditingController();
  final _ownerUserIdCtrl = TextEditingController();
  final _gameCtrl = TextEditingController();
  final _existingDewIdCtrl = TextEditingController();
  final _existingGameCtrl = TextEditingController();
  final _noteCtrl = TextEditingController();
  final _latCtrl = TextEditingController();
  final _lngCtrl = TextEditingController();
  final _radiusCtrl = TextEditingController(text: '100');
  final _themePrimCtrl = TextEditingController();
  final _themeAccCtrl = TextEditingController();
  String? _msg;
  bool _lockEnabled = false;
  bool _requireApproval = true;
  Future<ApiResponse>? _requestsFuture;
  Future<ApiResponse>? _listFuture;

  @override
  void initState() {
    super.initState();
    _refreshRequests();
    _refreshList();
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _ownerCtrl.dispose();
    _ownerEmailCtrl.dispose();
    _ownerUserIdCtrl.dispose();
    _gameCtrl.dispose();
    _existingDewIdCtrl.dispose();
    _existingGameCtrl.dispose();
    _noteCtrl.dispose();
    _latCtrl.dispose();
    _lngCtrl.dispose();
    _radiusCtrl.dispose();
    _themePrimCtrl.dispose();
    _themeAccCtrl.dispose();
    super.dispose();
  }

  Future<void> _addGameToExistingDewanyah() async {
    final dewId = _existingDewIdCtrl.text.trim();
    final gameId = _existingGameCtrl.text.trim();
    if (dewId.isEmpty || gameId.isEmpty) {
      setState(() => _msg = 'أدخل معرف الديوانية واللعبة');
      return;
    }
    final res = await widget.api.post(
      '/admin/dewanyah/$dewId/games',
      body: {'gameId': gameId},
    );
    setState(() => _msg = res.error ?? 'تم طلب إضافة اللعبة للديوانية');
  }

  void _refreshRequests() {
    setState(() {
      _requestsFuture = widget.api.get('/admin/dewanyah/requests');
    });
  }

  void _refreshList() {
    setState(() {
      _listFuture = widget.api.get('/admin/dewanyah');
    });
  }

  Future<void> _deleteRequest(String id) async {
    final res = await widget.api.delete('/admin/dewanyah/requests/$id');
    setState(() => _msg = res.error ?? 'تم حذف الطلب');
    _refreshRequests();
  }

  Future<void> _createDewanyah() async {
    final name = _nameCtrl.text.trim();
    final owner = _ownerCtrl.text.trim();
    final ownerEmail = _ownerEmailCtrl.text.trim();
    final ownerUserId = _ownerUserIdCtrl.text.trim();
    final game = _gameCtrl.text.trim();
    final themePrimary = _themePrimCtrl.text.trim();
    final themeAccent = _themeAccCtrl.text.trim();
    if (name.isEmpty || game.isEmpty) {
      setState(() => _msg = 'أدخل الاسم واللعبة');
      return;
    }

    double? lat = double.tryParse(_latCtrl.text.trim());
    double? lng = double.tryParse(_lngCtrl.text.trim());
    int? radius = int.tryParse(_radiusCtrl.text.trim());
    if (!_lockEnabled) {
      lat = null;
      lng = null;
      radius = null;
    }

    final res = await widget.api.post(
      '/admin/dewanyah',
      body: {
        'name': name,
        if (owner.isNotEmpty) 'owner': owner,
        if (ownerEmail.isNotEmpty) 'ownerEmail': ownerEmail,
        if (ownerUserId.isNotEmpty) 'ownerUserId': ownerUserId,
        'gameId': game,
        'note': _noteCtrl.text.trim(),
        'requireApproval': _requireApproval,
        if (lat != null && lng != null) 'lockLat': lat,
        if (lat != null && lng != null) 'lockLng': lng,
        if (radius != null) 'lockRadius': radius,
        if (themePrimary.isNotEmpty) 'themePrimary': themePrimary,
        if (themeAccent.isNotEmpty) 'themeAccent': themeAccent,
      },
    );
    setState(
      () => _msg = res.error ?? 'تم طلب إنشاء الديوانية (تأكد من دعم الباكند)',
    );
    _refreshRequests();
    _refreshList();
  }

  Future<void> _editDewanyah(Map<String, dynamic> d) async {
    final id = (d['id'] ?? '').toString();
    final nameCtrl = TextEditingController(text: d['name']?.toString() ?? '');
    final ownerCtrl = TextEditingController(
      text: d['ownerName']?.toString() ?? '',
    );
    final emailCtrl = TextEditingController(
      text: d['ownerEmail']?.toString() ?? '',
    );
    final noteCtrl = TextEditingController(text: d['note']?.toString() ?? '');
    final imgCtrl = TextEditingController(
      text: d['imageUrl']?.toString() ?? '',
    );
    final primCtrl = TextEditingController(
      text: d['themePrimary']?.toString() ?? '',
    );
    final accCtrl = TextEditingController(
      text: d['themeAccent']?.toString() ?? '',
    );
    await showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: Text('تعديل الديوانية'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: nameCtrl,
                decoration: const InputDecoration(labelText: 'الاسم'),
              ),
              TextField(
                controller: ownerCtrl,
                decoration: const InputDecoration(labelText: 'اسم المالك'),
              ),
              TextField(
                controller: emailCtrl,
                decoration: const InputDecoration(labelText: 'إيميل المالك'),
              ),
              TextField(
                controller: noteCtrl,
                decoration: const InputDecoration(labelText: 'ملاحظات'),
              ),
              TextField(
                controller: imgCtrl,
                decoration: const InputDecoration(labelText: 'رابط الصورة'),
              ),
              const SizedBox(height: 8),
              _colorField(
                label: 'لون أساسي',
                controller: primCtrl,
                context: context,
              ),
              const SizedBox(height: 8),
              _colorField(
                label: 'لون ثانوي',
                controller: accCtrl,
                context: context,
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('إلغاء'),
          ),
          ElevatedButton(
            onPressed: () async {
              await widget.api.patch(
                '/admin/dewanyah/$id',
                body: {
                  'name': nameCtrl.text.trim(),
                  'ownerName': ownerCtrl.text.trim(),
                  'ownerEmail': emailCtrl.text.trim(),
                  'note': noteCtrl.text.trim(),
                  'imageUrl': imgCtrl.text.trim(),
                  'themePrimary': primCtrl.text.trim(),
                  'themeAccent': accCtrl.text.trim(),
                },
              );
              if (mounted) Navigator.pop(context);
              _refreshList();
            },
            child: const Text('حفظ'),
          ),
        ],
      ),
    );
  }

  Future<void> _deleteDewanyah(String id) async {
    await widget.api.delete('/admin/dewanyah/$id');
    _refreshList();
  }

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.only(bottom: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'الديوانيات',
            style: TextStyle(fontWeight: FontWeight.w900, fontSize: 18),
          ),
          const SizedBox(height: 8),
          const Card(
            child: Padding(
              padding: EdgeInsets.all(12),
              child: Text(
                'عرض/إدارة الديوانيات يتطلب endpoints إدارية (لم تُحدد بعد في الباكند).',
              ),
            ),
          ),
          const SizedBox(height: 8),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Text(
                    'إنشاء ديوانية جديدة',
                    style: TextStyle(fontWeight: FontWeight.w900),
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    controller: _nameCtrl,
                    decoration: const InputDecoration(
                      labelText: 'اسم الديوانية',
                    ),
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    controller: _ownerCtrl,
                    decoration: const InputDecoration(
                      labelText: 'اسم المالك/المسؤول',
                    ),
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    controller: _ownerEmailCtrl,
                    decoration: const InputDecoration(
                      labelText: 'إيميل المالك (حساب التطبيق)',
                    ),
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    controller: _ownerUserIdCtrl,
                    decoration: const InputDecoration(
                      labelText: 'Owner User ID (اختياري)',
                    ),
                  ),
                  const SizedBox(height: 8),
                  DropdownButtonFormField<String>(
                    initialValue: _gameCtrl.text.isEmpty
                        ? null
                        : _gameCtrl.text,
                    decoration: const InputDecoration(labelText: 'Game ID'),
                    items: kGameOptions
                        .map((g) => DropdownMenuItem(value: g, child: Text(g)))
                        .toList(),
                    onChanged: (v) => setState(() => _gameCtrl.text = v ?? ''),
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    controller: _noteCtrl,
                    decoration: const InputDecoration(
                      labelText: 'ملاحظات (اختياري)',
                    ),
                  ),
                  const SizedBox(height: 8),
                  _colorField(
                    label: 'لون أساسي (Hex)',
                    controller: _themePrimCtrl,
                    context: context,
                  ),
                  const SizedBox(height: 8),
                  _colorField(
                    label: 'لون ثانوي (Hex)',
                    controller: _themeAccCtrl,
                    context: context,
                  ),
                  const SizedBox(height: 10),
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('قفل بالموقع (100م افتراضي)'),
                    value: _lockEnabled,
                    onChanged: (v) => setState(() => _lockEnabled = v),
                    subtitle: const Text('لن يُسمح بالانضمام خارج النطاق'),
                  ),
                  if (_lockEnabled) ...[
                    const SizedBox(height: 6),
                    Row(
                      children: [
                        Expanded(
                          child: TextField(
                            controller: _latCtrl,
                            decoration: const InputDecoration(
                              labelText: 'Latitude',
                            ),
                            keyboardType: TextInputType.numberWithOptions(
                              decimal: true,
                              signed: true,
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: TextField(
                            controller: _lngCtrl,
                            decoration: const InputDecoration(
                              labelText: 'Longitude',
                            ),
                            keyboardType: TextInputType.numberWithOptions(
                              decimal: true,
                              signed: true,
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        SizedBox(
                          width: 110,
                          child: TextField(
                            controller: _radiusCtrl,
                            decoration: const InputDecoration(labelText: 'متر'),
                            keyboardType: TextInputType.number,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 6),
                  ],
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('تتطلب موافقة المالك'),
                    value: _requireApproval,
                    onChanged: (v) => setState(() => _requireApproval = v),
                    subtitle: const Text(
                      'الانضمام بالديوانية يحتاج موافقة صاحبها',
                    ),
                  ),
                  const SizedBox(height: 10),
                  ElevatedButton.icon(
                    onPressed: _createDewanyah,
                    icon: const Icon(Icons.add_business_outlined),
                    label: const Text('إنشاء'),
                  ),
                  if (_msg != null) ...[
                    const SizedBox(height: 6),
                    Text(_msg!, style: const TextStyle(color: Colors.blue)),
                  ],
                  const SizedBox(height: 6),
                  const Text(
                    'نحتاج إضافة endpoint مثل POST /admin/dewanyah في الباكند ليعمل هذا الإجراء.',
                    style: TextStyle(fontSize: 12, color: Colors.grey),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 10),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    children: [
                      const Text(
                        'الديوانيات الحالية',
                        style: TextStyle(fontWeight: FontWeight.w900),
                      ),
                      const Spacer(),
                      IconButton(
                        onPressed: _refreshList,
                        icon: const Icon(Icons.refresh),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  FutureBuilder<ApiResponse>(
                    future: _listFuture,
                    builder: (context, snap) {
                      if (snap.connectionState == ConnectionState.waiting) {
                        return const Center(
                          child: Padding(
                            padding: EdgeInsets.all(12),
                            child: CircularProgressIndicator(),
                          ),
                        );
                      }
                      final res = snap.data;
                      if (res == null || res.error != null) {
                        return Text(
                          res?.error ?? 'فشل تحميل الديوانيات',
                          style: const TextStyle(color: Colors.grey),
                        );
                      }
                      final list = res.data is List
                          ? (res.data as List)
                          : const [];
                      if (list.isEmpty) {
                        return const Text('لا توجد ديوانيات حالياً');
                      }
                      return ListView.separated(
                        shrinkWrap: true,
                        physics: const NeverScrollableScrollPhysics(),
                        itemCount: list.length,
                        separatorBuilder: (context, _) =>
                            const Divider(height: 12),
                        itemBuilder: (context, i) {
                          final d = list[i] as Map<String, dynamic>;
                          final id = (d['id'] ?? '').toString();
                          final name = (d['name'] ?? 'ديوانية').toString();
                          final owner = (d['ownerName'] ?? '').toString();
                          final game =
                              ((d['games'] as List?)?.isNotEmpty ?? false)
                              ? (d['games'][0]['gameId']?.toString() ?? '')
                              : (d['gameId'] ?? '').toString();
                          final members = (d['_count']?['members'] ?? 0)
                              .toString();
                          return ListTile(
                            title: Text(
                              '$name — $game',
                              style: const TextStyle(
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            subtitle: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                SelectableText(
                                  'ID: $id',
                                  style: const TextStyle(
                                    fontSize: 12,
                                    color: Colors.grey,
                                  ),
                                ),
                                if (owner.isNotEmpty) Text('المالك: $owner'),
                                Text('الأعضاء: $members'),
                              ],
                            ),
                            trailing: Wrap(
                              spacing: 6,
                              children: [
                                IconButton(
                                  tooltip: 'استخدام المعرّف',
                                  icon: const Icon(Icons.copy),
                                  onPressed: () {
                                    setState(
                                      () => _existingDewIdCtrl.text = id,
                                    );
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      const SnackBar(
                                        content: Text(
                                          'تم نسخ/تعبئة معرف الديوانية',
                                        ),
                                      ),
                                    );
                                  },
                                ),
                                TextButton(
                                  onPressed: () => _editDewanyah(d),
                                  child: const Text('تعديل'),
                                ),
                                TextButton(
                                  onPressed: () => _deleteDewanyah(id),
                                  child: const Text(
                                    'حذف',
                                    style: TextStyle(color: Colors.red),
                                  ),
                                ),
                              ],
                            ),
                          );
                        },
                      );
                    },
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 10),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Text(
                    'إضافة لعبة لديوانية موجودة',
                    style: TextStyle(fontWeight: FontWeight.w900),
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: _existingDewIdCtrl,
                          decoration: const InputDecoration(
                            labelText: 'معرف الديوانية',
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: DropdownButtonFormField<String>(
                          initialValue: _existingGameCtrl.text.isEmpty
                              ? null
                              : _existingGameCtrl.text,
                          decoration: const InputDecoration(
                            labelText: 'Game ID',
                          ),
                          items: kGameOptions
                              .map(
                                (g) =>
                                    DropdownMenuItem(value: g, child: Text(g)),
                              )
                              .toList(),
                          onChanged: (v) =>
                              setState(() => _existingGameCtrl.text = v ?? ''),
                        ),
                      ),
                      const SizedBox(width: 8),
                      ElevatedButton.icon(
                        onPressed: _addGameToExistingDewanyah,
                        icon: const Icon(Icons.add),
                        label: const Text('إضافة'),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  const Text(
                    'تحتاج endpoint مثل POST /admin/dewanyah/:id/games في الباكند.',
                    style: TextStyle(fontSize: 12, color: Colors.grey),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 10),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const Text(
                        'طلبات إنشاء ديوانية',
                        style: TextStyle(fontWeight: FontWeight.w900),
                      ),
                      const Spacer(),
                      IconButton(
                        onPressed: _refreshRequests,
                        icon: const Icon(Icons.refresh),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  FutureBuilder<ApiResponse>(
                    future: _requestsFuture,
                    builder: (context, snap) {
                      if (snap.connectionState == ConnectionState.waiting) {
                        return const Center(
                          child: Padding(
                            padding: EdgeInsets.all(12),
                            child: CircularProgressIndicator(),
                          ),
                        );
                      }
                      final res = snap.data;
                      if (res == null || res.error != null) {
                        return Text(
                          res?.error ?? 'الطلبات غير متاحة (endpoint مفقود)',
                          style: const TextStyle(color: Colors.grey),
                        );
                      }
                      final data = res.data;
                      final list = data is List ? data : const [];
                      if (list.isEmpty) {
                        return const Text('لا توجد طلبات حاليًا');
                      }
                      return ListView.separated(
                        shrinkWrap: true,
                        physics: const NeverScrollableScrollPhysics(),
                        itemCount: list.length,
                        separatorBuilder: (context, _) =>
                            const Divider(height: 12),
                        itemBuilder: (context, i) {
                          final r = list[i] as Map<String, dynamic>;
                          final name = (r['name'] ?? 'ديوانية').toString();
                          final owner = (r['owner'] ?? '').toString();
                          final email = (r['ownerEmail'] ?? '').toString();
                          final requestId = (r['id'] ?? '').toString();
                          final ownerUserId =
                              (r['ownerUserId'] ?? r['userId'] ?? '')
                                  .toString();
                          final gameId = (r['gameId'] ?? '').toString();
                          final note = (r['note'] ?? '').toString();
                          return ListTile(
                            title: Text(
                              '$name — $gameId',
                              style: const TextStyle(
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                            subtitle: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                if (owner.isNotEmpty) Text('المالك: $owner'),
                                if (email.isNotEmpty) Text('إيميل: $email'),
                                if (ownerUserId.isNotEmpty)
                                  SelectableText(
                                    'Owner ID: $ownerUserId',
                                    style: const TextStyle(
                                      fontSize: 12,
                                      color: Colors.grey,
                                    ),
                                  ),
                                if (note.isNotEmpty) Text('ملاحظة: $note'),
                              ],
                            ),
                            trailing: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                if (ownerUserId.isNotEmpty)
                                  TextButton(
                                    onPressed: () {
                                      setState(() {
                                        _ownerUserIdCtrl.text = ownerUserId;
                                        if (email.isNotEmpty) {
                                          _ownerEmailCtrl.text = email;
                                        }
                                        if (owner.isNotEmpty) {
                                          _ownerCtrl.text = owner;
                                        }
                                      });
                                      ScaffoldMessenger.of(
                                        context,
                                      ).showSnackBar(
                                        const SnackBar(
                                          content: Text(
                                            'تم تعبئة Owner ID في نموذج الإنشاء',
                                          ),
                                        ),
                                      );
                                    },
                                    child: const Text('استخدام ID'),
                                  ),
                                if (requestId.isNotEmpty)
                                  IconButton(
                                    tooltip: 'حذف الطلب',
                                    onPressed: () => _deleteRequest(requestId),
                                    icon: const Icon(
                                      Icons.delete_outline,
                                      color: Colors.redAccent,
                                    ),
                                  ),
                              ],
                            ),
                          );
                        },
                      );
                    },
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class UsersTab extends StatefulWidget {
  final ApiClient api;
  const UsersTab({super.key, required this.api});

  @override
  State<UsersTab> createState() => _UsersTabState();
}

class _UsersTabState extends State<UsersTab> {
  final _searchCtrl = TextEditingController();
  String? _msg;
  Future<ApiResponse>? _listFuture;

  @override
  void initState() {
    super.initState();
    _refresh();
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  void _refresh() {
    final q = _searchCtrl.text.trim();
    final suffix = q.isEmpty ? '' : '&q=${Uri.encodeQueryComponent(q)}';
    setState(() {
      _listFuture = widget.api.get('/admin/users?limit=200$suffix');
    });
  }

  Future<void> _setLeaderboardHidden({
    required String userId,
    required bool hidden,
  }) async {
    final res = await widget.api.patch(
      '/admin/users/$userId/${hidden ? 'ban' : 'unban'}',
    );
    setState(
      () => _msg =
          res.error ??
          (hidden
              ? 'تم إخفاء المستخدم من الليدربورد'
              : 'تم إظهار المستخدم في الليدربورد'),
    );
    _refresh();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'المستخدمون',
          style: TextStyle(fontWeight: FontWeight.w900, fontSize: 18),
        ),
        const SizedBox(height: 8),
        Expanded(
          child: Card(
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: _searchCtrl,
                          decoration: const InputDecoration(
                            labelText: 'بحث (إيميل/اسم/User ID)',
                          ),
                          onSubmitted: (_) => _refresh(),
                        ),
                      ),
                      const SizedBox(width: 8),
                      ElevatedButton.icon(
                        onPressed: _refresh,
                        icon: const Icon(Icons.search),
                        label: const Text('بحث'),
                      ),
                    ],
                  ),
                  if (_msg != null) ...[
                    const SizedBox(height: 8),
                    Text(_msg!, style: const TextStyle(color: Colors.blue)),
                  ],
                  const SizedBox(height: 8),
                  Expanded(
                    child: FutureBuilder<ApiResponse>(
                      future: _listFuture,
                      builder: (context, snap) {
                        if (snap.connectionState == ConnectionState.waiting) {
                          return const Center(
                            child: CircularProgressIndicator(),
                          );
                        }
                        final res = snap.data;
                        if (res == null || res.error != null) {
                          return Center(
                            child: Text(
                              res?.error ?? 'فشل تحميل المستخدمين',
                              style: const TextStyle(color: Colors.red),
                            ),
                          );
                        }
                        final list = res.data is List
                            ? (res.data as List)
                            : const [];
                        if (list.isEmpty) {
                          return const Center(child: Text('لا يوجد مستخدمون'));
                        }

                        return ListView.separated(
                          itemCount: list.length,
                          padding: const EdgeInsets.only(bottom: 12),
                          separatorBuilder: (context, _) =>
                              const Divider(height: 12),
                          itemBuilder: (context, i) {
                            final u = list[i] as Map<String, dynamic>;
                            final userId = (u['id'] ?? '').toString();
                            final name = (u['displayName'] ?? '').toString();
                            final email = (u['email'] ?? '').toString();
                            final hidden = u['hideFromLeaderboard'] == true;
                            final isTest = u['isTestAccount'] == true;
                            return ListTile(
                              title: Text(
                                name.isNotEmpty ? name : email,
                                style: const TextStyle(
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                              subtitle: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  if (email.isNotEmpty) Text(email),
                                  SelectableText(
                                    'ID: $userId',
                                    style: const TextStyle(
                                      fontSize: 12,
                                      color: Colors.grey,
                                    ),
                                  ),
                                  Text(
                                    hidden
                                        ? 'الحالة: مخفي من الليدربورد'
                                        : 'الحالة: ظاهر في الليدربورد',
                                    style: TextStyle(
                                      fontSize: 12,
                                      color: hidden
                                          ? Colors.orange[800]
                                          : Colors.green[700],
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                  if (isTest)
                                    const Text(
                                      'حساب تجريبي',
                                      style: TextStyle(
                                        fontSize: 12,
                                        color: Colors.grey,
                                      ),
                                    ),
                                ],
                              ),
                              trailing: Wrap(
                                spacing: 8,
                                children: [
                                  if (!hidden)
                                    TextButton.icon(
                                      onPressed: () => _setLeaderboardHidden(
                                        userId: userId,
                                        hidden: true,
                                      ),
                                      icon: const Icon(
                                        Icons.visibility_off,
                                        size: 18,
                                      ),
                                      label: const Text('إخفاء'),
                                    ),
                                  if (hidden)
                                    TextButton.icon(
                                      onPressed: () => _setLeaderboardHidden(
                                        userId: userId,
                                        hidden: false,
                                      ),
                                      icon: const Icon(
                                        Icons.visibility,
                                        size: 18,
                                      ),
                                      label: const Text('إظهار'),
                                    ),
                                ],
                              ),
                            );
                          },
                        );
                      },
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class NotificationsTab extends StatefulWidget {
  final ApiClient api;

  const NotificationsTab({super.key, required this.api});

  @override
  State<NotificationsTab> createState() => _NotificationsTabState();
}

class _NotificationsTabState extends State<NotificationsTab> {
  final _titleCtrl = TextEditingController();
  final _messageCtrl = TextEditingController();
  bool _sending = false;
  bool _monthlySending = false;
  bool _seasonNoticeSending = false;
  bool _seasonResetSending = false;
  bool _statusChecking = false;

  @override
  void dispose() {
    _titleCtrl.dispose();
    _messageCtrl.dispose();
    super.dispose();
  }

  String _pushDeliveryMessage(
    dynamic data, {
    String fallback = 'تم إرسال الإشعار',
  }) {
    if (data is! Map) return fallback;
    final id = (data['id'] ?? '').toString();
    final recipients = data['recipients'];
    final errors = data['errors'];
    final error = data['error'];

    if (id.isNotEmpty) {
      if (recipients != null) {
        return 'تم قبول الإشعار من OneSignal، المستلمين: $recipients';
      }
      return 'تم قبول الإشعار من OneSignal';
    }
    if (errors is List && errors.isNotEmpty) {
      return 'OneSignal رجّع خطأ: ${errors.first}';
    }
    if (error != null && error.toString().isNotEmpty) {
      return 'OneSignal رجّع خطأ: $error';
    }
    return fallback;
  }

  Future<void> _checkOneSignalStatus() async {
    setState(() => _statusChecking = true);
    try {
      final res = await widget.api.get('/admin/notifications/status');
      if (!mounted) return;
      if (res.error != null) throw res.error!;
      final data = res.data;
      final appIdOk = data is Map && data['appIdConfigured'] == true;
      final keyOk = data is Map && data['restApiKeyConfigured'] == true;
      final maskedAppId = data is Map ? data['appId'] : null;
      final message = appIdOk && keyOk
          ? 'OneSignal مضبوط على الـ API: $maskedAppId'
          : 'ناقص إعدادات OneSignal على الـ API: App ID ${appIdOk ? 'موجود' : 'ناقص'}، REST Key ${keyOk ? 'موجود' : 'ناقص'}';
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(message)));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('فشل فحص OneSignal: $e')));
    } finally {
      if (mounted) setState(() => _statusChecking = false);
    }
  }

  Future<void> _send() async {
    final title = _titleCtrl.text.trim();
    final message = _messageCtrl.text.trim();
    if (title.isEmpty || message.isEmpty) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('اكتب عنوان الإشعار ونصه أولاً')),
      );
      return;
    }

    setState(() => _sending = true);
    try {
      final res = await widget.api.post(
        '/admin/notifications/broadcast',
        body: {
          'titleAr': title,
          'messageAr': message,
          'title': title,
          'message': message,
        },
      );
      if (!mounted) return;
      if (res.error != null) throw res.error!;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(_pushDeliveryMessage(res.data))));
      _titleCtrl.clear();
      _messageCtrl.clear();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('فشل إرسال الإشعار: $e')));
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  Future<void> _sendMonthlyLeaderboardAwards() async {
    setState(() => _monthlySending = true);
    try {
      final res = await widget.api.post(
        '/admin/notifications/monthly-leaderboards',
        body: {'limit': 10},
      );
      if (!mounted) return;
      if (res.error != null) throw res.error!;
      final data = res.data;
      final sent = data is Map ? (data['pushesSent'] ?? 0) : 0;
      final created = data is Map ? (data['eventsCreated'] ?? 0) : 0;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('تم تجهيز $created إنجاز وإرسال $sent إشعار شهري'),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('فشل إرسال إشعارات الشهر: $e')));
    } finally {
      if (mounted) setState(() => _monthlySending = false);
    }
  }

  Future<void> _sendSeasonEndedNotice() async {
    setState(() => _seasonNoticeSending = true);
    try {
      final res = await widget.api.post('/admin/notifications/season-ended');
      if (!mounted) return;
      if (res.error != null) throw res.error!;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            _pushDeliveryMessage(
              res.data,
              fallback: 'تم إرسال إشعار نهاية السيزن',
            ),
          ),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('فشل إرسال إشعار السيزن: $e')));
    } finally {
      if (mounted) setState(() => _seasonNoticeSending = false);
    }
  }

  Future<void> _resetSeasonAndNotify() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('تصفير السيزن الشهري؟'),
        content: const Text(
          'بيرجع كل اللاعبين إلى ٥ لآلئ، ويترك الانواط محفوظة، ويرسل إشعار نهاية السيزن.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('إلغاء'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('تأكيد'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    setState(() => _seasonResetSending = true);
    try {
      final res = await widget.api.post(
        '/admin/notifications/season-reset',
        body: {'sendPush': true},
      );
      if (!mounted) return;
      if (res.error != null) throw res.error!;
      final data = res.data;
      final skipped = data is Map ? data['skipped'] == true : false;
      final users = data is Map ? (data['usersUpdated'] ?? 0) : 0;
      final push = data is Map ? data['push'] : null;
      final pushSent = push is Map ? push['sent'] == true : false;
      final pushResponse = push is Map ? push['response'] : null;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            skipped
                ? 'السيزن متصفر مسبقًا لهذا الشهر'
                : pushSent
                ? 'تم تصفير $users مستخدم. ${_pushDeliveryMessage(pushResponse)}'
                : 'تم تصفير $users مستخدم، لكن الإشعار ما انرسل',
          ),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('فشل تصفير السيزن: $e')));
    } finally {
      if (mounted) setState(() => _seasonResetSending = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final compact = MediaQuery.sizeOf(context).width < 560;

    return ListView(
      padding: EdgeInsets.fromLTRB(
        compact ? 12 : 24,
        compact ? 12 : 24,
        compact ? 12 : 24,
        compact ? 132 : 112,
      ),
      children: [
        Text(
          'إشعار عام',
          style: TextStyle(
            fontSize: compact ? 24 : 28,
            fontWeight: FontWeight.w800,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          'أرسل إشعارًا لجميع مستخدمي التطبيق.',
          style: _mutedTextStyle(context),
        ),
        const SizedBox(height: 12),
        Align(
          alignment: AlignmentDirectional.centerStart,
          child: OutlinedButton.icon(
            onPressed:
                (_statusChecking ||
                    _sending ||
                    _monthlySending ||
                    _seasonNoticeSending ||
                    _seasonResetSending)
                ? null
                : _checkOneSignalStatus,
            icon: _statusChecking
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.health_and_safety_rounded),
            label: Text(
              _statusChecking ? 'جاري فحص OneSignal...' : 'فحص OneSignal',
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ),
        const SizedBox(height: 24),
        TextField(
          controller: _titleCtrl,
          decoration: const InputDecoration(labelText: 'عنوان الإشعار'),
        ),
        const SizedBox(height: 16),
        TextField(
          controller: _messageCtrl,
          maxLines: 5,
          decoration: const InputDecoration(labelText: 'نص الإشعار'),
        ),
        const SizedBox(height: 20),
        SizedBox(
          width: double.infinity,
          child: FilledButton.icon(
            onPressed: _sending ? null : _send,
            icon: _sending
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.send_rounded),
            label: Text(
              _sending ? 'جاري الإرسال...' : 'إرسال الإشعار للجميع',
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ),
        const SizedBox(height: 24),
        const Divider(),
        const SizedBox(height: 16),
        Text(
          'نهاية السيزن الشهري',
          style: TextStyle(
            fontSize: compact ? 20 : 22,
            fontWeight: FontWeight.w800,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          'يرجع كل اللاعبين إلى ٥ لآلئ، ويبدأ ترتيب الشهر من جديد، وتظل الانواط محفوظة.',
          style: _mutedTextStyle(context),
        ),
        const SizedBox(height: 16),
        SizedBox(
          width: double.infinity,
          child: FilledButton.icon(
            onPressed:
                (_sending ||
                    _monthlySending ||
                    _seasonNoticeSending ||
                    _seasonResetSending)
                ? null
                : _sendSeasonEndedNotice,
            icon: _seasonNoticeSending
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.campaign_rounded),
            label: Text(
              _seasonNoticeSending
                  ? 'جاري إرسال إشعار السيزن...'
                  : 'إرسال إشعار نهاية السيزن فقط',
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ),
        const SizedBox(height: 12),
        SizedBox(
          width: double.infinity,
          child: FilledButton.icon(
            onPressed:
                (_sending ||
                    _monthlySending ||
                    _seasonNoticeSending ||
                    _seasonResetSending)
                ? null
                : _resetSeasonAndNotify,
            icon: _seasonResetSending
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.restart_alt_rounded),
            label: Text(
              _seasonResetSending
                  ? 'جاري تصفير السيزن...'
                  : 'تصفير السيزن وإرسال الإشعار',
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ),
        const SizedBox(height: 24),
        const Divider(),
        const SizedBox(height: 16),
        Text(
          'إشعارات الفايزين الشهرية',
          style: TextStyle(
            fontSize: compact ? 20 : 22,
            fontWeight: FontWeight.w800,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          'يرسل إشعارًا خارجيًا لأول 10 لاعبين في كل لعبة، ويضيف الإنجاز داخل مسيرتهم. يتم احتساب اللاعبين الذين لعبوا فعليًا فقط.',
          style: _mutedTextStyle(context),
        ),
        const SizedBox(height: 16),
        SizedBox(
          width: double.infinity,
          child: FilledButton.icon(
            onPressed: (_sending || _monthlySending)
                ? null
                : _sendMonthlyLeaderboardAwards,
            icon: _monthlySending
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.workspace_premium_rounded),
            label: Text(
              _monthlySending
                  ? 'جاري تجهيز إشعارات الشهر...'
                  : 'إرسال إشعارات الفايزين الشهرية',
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ),
        const SizedBox(height: 24),
      ],
    );
  }
}
